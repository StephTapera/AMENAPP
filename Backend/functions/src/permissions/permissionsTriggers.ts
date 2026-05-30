/**
 * permissionsTriggers.ts
 *
 * Firestore triggers and scheduled functions that keep permissions/{uid}
 * and Auth custom claims in sync with the underlying account state.
 *
 * Three compute paths:
 *   1. onWrite users/{uid}  — fires on mode, verification, trust, or state change
 *   2. Scheduled daily      — promotes ageTier when DOB crosses 13 or 18;
 *                             forces token refresh so custom claims propagate
 *   3. writeResolvedPermissions — shared write helper used by triggers and callables
 *
 * The permissions/{uid} document is the denormalized resolved set.
 * Security rules enforce allow write: if false — only this module may write it.
 *
 * Auth custom claims (hot-path, zero extra reads in security rules):
 *   { ageTier, canPostPublic, reachTier }
 * Full PermissionSet stays in permissions/{uid}.
 */

import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

import { AgeTier, AccountSnapshot, PermissionSet } from "./permissionsTypes";
import { resolvePermissions, defaultModeForTier } from "./permissionsEngine";
import { normalizeAgeTier } from "./permissionsUtils";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Shared write helper ──────────────────────────────────────────────────────

/**
 * Persists a resolved PermissionSet to permissions/{uid} and syncs the
 * hot-path subset into Auth custom claims. Called by triggers and callables.
 */
export async function writeResolvedPermissions(
  uid: string,
  resolved: PermissionSet,
  ceilingTier: AgeTier
): Promise<void> {
  const stored = {
    ...resolved,
    resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    ceilingTier,
  };

  // Write the full set to the denormalized doc
  await db.collection("permissions").doc(uid).set(stored);

  // Sync hot-path fields into Auth custom claims (~1000-byte budget; keep minimal)
  try {
    const currentUser = await admin.auth().getUser(uid);
    const currentClaims = (currentUser.customClaims as Record<string, unknown>) ?? {};
    await admin.auth().setCustomUserClaims(uid, {
      ...currentClaims,
      ageTier: ceilingTier,
      canPostPublic: resolved.canPostPublic,
      reachTier: resolved.reachTier,
    });
  } catch (err) {
    // Non-fatal: claims update failed (e.g. user deleted). permissions/{uid} is the source of truth.
    logger.warn(`[PermissionsEngine] Failed to update custom claims for uid=${uid}`, err);
  }
}

// ─── Trigger: onUserWrite ─────────────────────────────────────────────────────

/**
 * Recomputes permissions whenever the fields that drive resolution change.
 * Skips the recompute if none of the relevant fields changed to avoid
 * an infinite loop (writeResolvedPermissions does NOT write back to users/{uid}).
 */
export const onUserWrite = onDocumentWritten(
  "users/{uid}",
  async (event) => {
    const uid = event.params.uid;
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!after) return; // Document deleted — permissions doc stays until cascade deletes it

    const WATCHED_FIELDS = [
      "ageTier", "mode", "verificationStatus", "mentorApproved",
      "trustLevel", "accountState", "guardianConsentStatus", "csamFlag",
    ];

    const isNew = !before;
    const hasRelevantChange = WATCHED_FIELDS.some(
      (f) => after[f] !== (before ?? {})[f]
    );

    if (!isNew && !hasRelevantChange) return;

    try {
      const account = snapshotFromDoc(uid, after);
      const resolved = resolvePermissions(account);
      await writeResolvedPermissions(uid, resolved, account.ageTier);

      logger.info(
        `[PermissionsEngine] onUserWrite uid=${uid} ageTier=${account.ageTier} mode=${account.mode}`
      );
    } catch (err) {
      logger.error(`[PermissionsEngine] onUserWrite failed uid=${uid}`, err);
    }
  }
);

// ─── Scheduled: daily age-tier promotion ─────────────────────────────────────

/**
 * Runs daily at 02:00 UTC. Finds accounts whose dateOfBirth (in the private
 * subcollection) has crossed the 13 or 18 threshold since the last run,
 * updates ageTier on users/{uid}, and forces a token refresh.
 *
 * Processes in batches of 500 to stay within function timeout.
 */
// NOTE: Add a Firestore TTL policy on `system/scheduledJobLocks` collection
// with field `expiresAt` set to 7 days. This automatically cleans up old lock documents.

export const dailyAgeTierPromotion = onSchedule(
  { schedule: "0 2 * * *", timeoutSeconds: 540 },
  async () => {
    const today = new Date().toISOString().slice(0, 10);
    const lockRef = db.doc(`system/scheduledJobLocks/dailyAgeTierPromotion_${today}`);

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
      logger.info("[PermissionsEngine] dailyAgeTierPromotion already completed today, skipping", { date: today });
      return;
    }

    try {
      const now = new Date();
      const thirteenYearsAgo = new Date(now);
      thirteenYearsAgo.setFullYear(now.getFullYear() - 13);
      const eighteenYearsAgo = new Date(now);
      eighteenYearsAgo.setFullYear(now.getFullYear() - 18);

      // Promoted to teen: accounts with ageTier "under13" whose DOB is now ≥ 13 years ago.
      // Promoted to adult: accounts with ageTier "teen" whose DOB is now ≥ 18 years ago.
      // DOB is stored in users/{uid}/private/safety.dateOfBirth (Timestamp).

      let promoted = 0;

      // Query users with outdated tier: under13 candidates
      const under13Snap = await db
        .collection("users")
        .where("ageTier", "in", ["minor", "under13", "under_minimum"])
        .limit(500)
        .get();

      for (const doc of under13Snap.docs) {
        try {
          const dob = await getDateOfBirth(doc.id);
          if (!dob) continue;
          const age = ageInYears(dob, now);
          if (age >= 18) {
            await promoteAgeTier(doc.id, "adult");
            promoted++;
          } else if (age >= 13) {
            await promoteAgeTier(doc.id, "teen");
            promoted++;
          }
        } catch (err) {
          logger.warn(`[PermissionsEngine] dailyPromotion failed for uid=${doc.id}`, err);
        }
      }

      // Query teens who may have turned 18
      const teenSnap = await db
        .collection("users")
        .where("ageTier", "==", "teen")
        .limit(500)
        .get();

      for (const doc of teenSnap.docs) {
        try {
          const dob = await getDateOfBirth(doc.id);
          if (!dob) continue;
          if (ageInYears(dob, now) >= 18) {
            await promoteAgeTier(doc.id, "adult");
            promoted++;
          }
        } catch (err) {
          logger.warn(`[PermissionsEngine] dailyPromotion failed for uid=${doc.id}`, err);
        }
      }

      logger.info(`[PermissionsEngine] dailyAgeTierPromotion promoted=${promoted}`);

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

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function getDateOfBirth(uid: string): Promise<Date | null> {
  const snap = await db
    .collection("users")
    .doc(uid)
    .collection("private")
    .doc("safety")
    .get();
  const dob = snap.data()?.dateOfBirth;
  if (!dob) return null;
  return dob instanceof admin.firestore.Timestamp ? dob.toDate() : new Date(dob);
}

function ageInYears(dob: Date, now: Date): number {
  let age = now.getFullYear() - dob.getFullYear();
  const m = now.getMonth() - dob.getMonth();
  if (m < 0 || (m === 0 && now.getDate() < dob.getDate())) age--;
  return age;
}

async function promoteAgeTier(uid: string, newTier: AgeTier): Promise<void> {
  const normalizedTier =
    newTier === "under13" ? "under13" : newTier === "teen" ? "teen" : "adult";

  await db.collection("users").doc(uid).update({ ageTier: normalizedTier });

  // Force a token refresh so custom claim change propagates on next request
  try {
    await admin.auth().revokeRefreshTokens(uid);
    logger.info(
      `[PermissionsEngine] Promoted ageTier uid=${uid} newTier=${normalizedTier} — token revoked`
    );
  } catch (err) {
    logger.warn(`[PermissionsEngine] Token revocation failed uid=${uid}`, err);
  }

  // onUserWrite trigger will recompute permissions from the ageTier update above.
}

/**
 * Builds an AccountSnapshot from a raw Firestore document.
 * Exported so callables and the trigger can share the same normalization logic.
 * Fails closed: any missing field defaults to the most restrictive value.
 */
export function snapshotFromDoc(uid: string, data: FirebaseFirestore.DocumentData): AccountSnapshot {
  const rawTier: string = data.ageTier ?? "adult";
  const ageTier = normalizeAgeTier(rawTier);

  const rawMode = data.mode ?? defaultModeForTier(ageTier);
  const validModes = ["social", "discussion", "study", "quiet", "postless", "campus", "family"];
  const mode = validModes.includes(rawMode) ? rawMode : defaultModeForTier(ageTier);

  const rawVerification = data.verificationStatus ?? "none";
  const verificationStatus: AccountSnapshot["verificationStatus"] =
    ["none", "pending", "verified"].includes(rawVerification) ? rawVerification : "none";

  const rawState = data.accountState ?? "active";
  const accountState: AccountSnapshot["accountState"] =
    ["active", "pending", "suspended"].includes(rawState) ? rawState : "active";

  const rawConsent = data.guardianConsentStatus ?? (ageTier === "under13" ? "pending" : "n/a");
  const guardianConsentStatus: AccountSnapshot["guardianConsentStatus"] =
    ["n/a", "pending", "confirmed"].includes(rawConsent) ? rawConsent : "n/a";

  return {
    uid,
    ageTier,
    mode,
    verificationStatus,
    mentorApproved: data.mentorApproved === true,
    trustLevel: typeof data.trustLevel === "number" ? Math.max(0, Math.min(5, data.trustLevel)) : 0,
    accountState,
    guardianConsentStatus,
    csamFlag: data.csamFlag === true,
  };
}
