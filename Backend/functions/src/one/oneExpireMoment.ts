/**
 * one_expireMoment — P5 gate deploy item
 *
 * Decays a Moment when its lifetime expires. MUST check evidenceLocked
 * before deleting — evidence path takes unconditional precedence (SECURITY.md §4/§8.2).
 * Also invoked by Cloud Scheduler (scheduled trigger wired separately).
 *
 * Contract: CONTRACTS.md §15 / SECURITY.md §4
 */
import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = () => admin.firestore();

interface ExpireMomentData { momentID: string; }

export const one_expireMoment = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) throw new functions.HttpsError("unauthenticated", "Auth required");
    const data = request.data as ExpireMomentData;
    if (!data?.momentID) throw new functions.HttpsError("invalid-argument", "momentID required");

    const ref = db().collection("one_moments").doc(data.momentID);
    const snap = await ref.get();
    if (!snap.exists) return { expired: false, reason: "not_found" };

    const moment = snap.data() as Record<string, unknown>;

    // Evidence-before-decay invariant (SECURITY.md §8.2).
    // If the moment has been reported, evidence is locked — skip decay unconditionally.
    if (moment["reportedAt"] || moment["evidenceLocked"] === true) {
      return { expired: false, reason: "evidence_locked" };
    }

    // Verify the moment has actually reached its expiry time
    const expiresAt = moment["expiresAt"] as admin.firestore.Timestamp | undefined;
    if (expiresAt && expiresAt.toMillis() > Date.now()) {
      return { expired: false, reason: "not_yet_expired" };
    }

    // Permanent moments (permanentAt set = user explicitly remembered) never decay
    if (moment["permanentAt"]) {
      return { expired: false, reason: "permanent" };
    }

    // Soft-delete: mark expired; physical deletion is a separate scheduled sweep
    await ref.update({
      expired: true,
      expiredAt: admin.firestore.FieldValue.serverTimestamp(),
      "content": admin.firestore.FieldValue.delete(), // strip content payload
    });

    return { expired: true };
  }
);
