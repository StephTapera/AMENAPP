/**
 * inferUserRoles.ts
 *
 * Cloud Function (Gen2 onCall): `inferUserRoles`
 * Cloud Function (Gen2 scheduled): `scheduledInferRoles`
 *
 * Computes and writes `profile.roleFlags` on a user document by reading
 * server-authoritative signals (Stripe Connect, mentor verifications,
 * church admin membership, post count).
 *
 * onCall request:  { userId: string }
 * onCall access:   admin OR owner (uid === userId)
 *
 * Response: { success: true, roleFlags: RoleFlags }
 *
 * Error codes:
 *   unauthenticated  — caller is not signed in
 *   permission-denied — non-admin caller tried to infer a different user's roles
 *   invalid-argument — userId missing or empty
 *   not-found        — user document does not exist
 *   internal         — unexpected Firestore failure
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

// ── Types ──────────────────────────────────────────────────────────────────

interface RoleFlags {
  isMentor: boolean;
  isCreator: boolean;
  isMinistryLeader: boolean;
  isChurchAccount: boolean;
  churchId: string | null;
}

// ── Core inference logic ───────────────────────────────────────────────────

async function computeRoleFlags(userId: string): Promise<RoleFlags> {
  const db = admin.firestore();

  // Run all reads in parallel for efficiency
  const [userSnap, stripeSnap, mentorSnap, churchQuery] = await Promise.all([
    db.collection("users").doc(userId).get(),
    db.collection("stripeConnect").doc(userId).get().catch(() => null),
    db.collection("mentorVerifications").doc(userId).get().catch(() => null),
    db
      .collection("churches")
      .where("adminId", "==", userId)
      .limit(1)
      .get()
      .catch(() => null),
  ]);

  if (!userSnap.exists) {
    throw new HttpsError("not-found", `User '${userId}' does not exist.`);
  }

  const userData = userSnap.data() ?? {};

  // isMentor: mentorVerifications/{userId}.verified === true
  const isMentor = mentorSnap?.exists
    ? (mentorSnap.data() ?? {}).verified === true
    : false;

  // isCreator: Stripe Connect exists with payoutsEnabled OR postsCount indicates serial content
  //   We use postsCount > 0 as the isCreator signal (content creator with at least one post).
  //   Stripe Connect is separately surfaced in hasGivingEnabled; here isCreator = posts exist.
  const postsCount = (userData.postsCount as number) ?? 0;
  const isCreator = postsCount > 0;

  // isChurchAccount + churchId: user is admin of a church
  const isChurchAccount = !!churchQuery && !churchQuery.empty;
  let churchId: string | null = null;
  if (isChurchAccount && churchQuery && !churchQuery.empty) {
    churchId = churchQuery.docs[0].id;
  }

  // isMinistryLeader: church account OR explicitly flagged on user doc
  const isMinistryLeader =
    isChurchAccount || (userData.isMinistryLeader === true);

  const roleFlags: RoleFlags = {
    isMentor,
    isCreator,
    isMinistryLeader,
    isChurchAccount,
    churchId,
  };

  return roleFlags;
}

async function writeRoleFlags(userId: string, roleFlags: RoleFlags): Promise<void> {
  const db = admin.firestore();
  await db.collection("users").doc(userId).set(
    { profile: { roleFlags } },
    { merge: true }
  );
}

// ── onCall export ──────────────────────────────────────────────────────────

export const inferUserRoles = onCall(async (request) => {
  // 1. Auth guard
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in to infer user roles.");
  }

  const callerUid = request.auth.uid;
  const isAdmin = request.auth.token?.admin === true;

  // 2. Input validation
  const { userId } = (request.data ?? {}) as { userId?: string };

  if (!userId || typeof userId !== "string" || userId.trim() === "") {
    throw new HttpsError("invalid-argument", "userId is required and must be a non-empty string.");
  }

  // 3. Owner-or-admin gate
  if (!isAdmin && callerUid !== userId) {
    throw new HttpsError(
      "permission-denied",
      "Only the account owner or an admin may infer role flags."
    );
  }

  // 4. Compute and write
  let roleFlags: RoleFlags;
  try {
    roleFlags = await computeRoleFlags(userId);
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "Failed to compute role flags.");
  }

  try {
    await writeRoleFlags(userId, roleFlags);
  } catch {
    throw new HttpsError("internal", "Failed to persist role flags.");
  }

  return { success: true, roleFlags };
});

// ── Scheduled export — runs daily at 03:00 UTC ────────────────────────────

// NOTE: Add a Firestore TTL policy on `system/scheduledJobLocks` collection
// with field `expiresAt` set to 7 days. This automatically cleans up old lock documents.

export const scheduledInferRoles = onSchedule(
  {
    schedule: "every 24 hours",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const db = admin.firestore();
    const today = new Date().toISOString().slice(0, 10);
    const lockRef = db.doc(`system/scheduledJobLocks/scheduledInferRoles_${today}`);

    const lockAcquired = await db.runTransaction(async (tx) => {
      const snap = await tx.get(lockRef);
      if (snap.exists && snap.data()?.status === "completed") {
        return false;
      }
      tx.set(lockRef, {
        status: "running",
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
        date: today,
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      });
      return true;
    });

    if (!lockAcquired) {
      logger.info("scheduledInferRoles: already completed today, skipping", { date: today });
      return;
    }

    try {
      let processed = 0;
      let errors = 0;
      let cursor: admin.firestore.QueryDocumentSnapshot | null = null;
      const BATCH_SIZE = 100;

      logger.info("scheduledInferRoles: starting daily role inference sweep");

      // Paginate through all users
      while (true) {
        let query = db.collection("users").orderBy("__name__").limit(BATCH_SIZE);
        if (cursor) {
          query = query.startAfter(cursor);
        }

        const snap = await query.get().catch((err) => {
          logger.error("scheduledInferRoles: failed to page users", err);
          return null;
        });

        if (!snap || snap.empty) break;

        // Process each user in the page concurrently (capped at page size)
        await Promise.all(
          snap.docs.map(async (doc) => {
            try {
              const roleFlags = await computeRoleFlags(doc.id);
              await writeRoleFlags(doc.id, roleFlags);
              processed++;
            } catch (err) {
              errors++;
              logger.warn(`scheduledInferRoles: failed for user ${doc.id}`, err);
            }
          })
        );

        if (snap.docs.length < BATCH_SIZE) break;
        cursor = snap.docs[snap.docs.length - 1];
      }

      logger.info(
        `scheduledInferRoles: complete — processed=${processed}, errors=${errors}`
      );

      await lockRef.update({
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      await lockRef.update({
        status: "failed",
        error: String(err),
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw err;
    }
  }
);
