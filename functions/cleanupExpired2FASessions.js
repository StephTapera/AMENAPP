"use strict";

/**
 * Scheduled cleanup for expired 2FA sessions.
 *
 * Runs every 60 minutes and:
 * 1. Sets session2FAActive=false on userSecurity documents whose
 *    session2FAExpiresAt has passed (authoritative gate for Firestore rules).
 * 2. Deletes expired legacy twoFactorSessions subcollection documents so
 *    Firestore storage does not grow unbounded.
 *
 * The expire2FASessions trigger in twoFactorAuth.js fires only when a new OTP
 * document is created, meaning low-traffic periods leave stale sessions active.
 * This scheduled function provides the guaranteed TTL enforcement regardless of
 * traffic volume.
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

// Run every 60 minutes — matches the 30-minute session TTL with a 2x safety margin.
exports.cleanupExpired2FASessions = onSchedule(
  { schedule: "every 60 minutes", timeZone: "America/New_York", region: "us-central1" },
  async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    // ── Step 1: Deactivate expired userSecurity sessions ──────────────────────
    // The Firestore rule caller2FASessionValid() reads session2FAActive.
    // Setting it to false immediately revokes write access for the expired session
    // without requiring the client to re-authenticate.
    try {
      const expiredSecurity = await db
        .collection("userSecurity")
        .where("session2FAActive", "==", true)
        .where("session2FAExpiresAt", "<", now)
        .limit(500)
        .get();

      if (!expiredSecurity.empty) {
        const batch = db.batch();
        expiredSecurity.docs.forEach((doc) => {
          batch.update(doc.ref, { session2FAActive: false });
        });
        await batch.commit();
        console.log(
          `cleanupExpired2FASessions: deactivated ${expiredSecurity.size} userSecurity sessions`
        );
      } else {
        console.log("cleanupExpired2FASessions: no expired userSecurity sessions found");
      }
    } catch (err) {
      console.error("cleanupExpired2FASessions: error deactivating userSecurity sessions:", err);
    }

    // ── Step 2: Delete expired legacy twoFactorSessions sub-documents ─────────
    // verify2FAOTP also writes twoFactorSessions/{userId}/sessions/{sessionId}
    // for backward compatibility. These are never updated to active=false, so
    // we delete them outright once expired to prevent unbounded accumulation.
    try {
      const expiredLegacy = await db
        .collectionGroup("sessions")
        .where("expiresAt", "<", now)
        .limit(500)
        .get();

      if (!expiredLegacy.empty) {
        const batch = db.batch();
        expiredLegacy.docs.forEach((doc) => {
          // Only delete documents that live under twoFactorSessions (not other
          // collectionGroup matches) by checking the parent collection name.
          const parentPath = doc.ref.parent.path;
          if (parentPath.startsWith("twoFactorSessions/")) {
            batch.delete(doc.ref);
          }
        });
        await batch.commit();
        console.log(
          `cleanupExpired2FASessions: deleted ${expiredLegacy.size} legacy twoFactorSessions documents`
        );
      } else {
        console.log("cleanupExpired2FASessions: no expired legacy twoFactorSessions found");
      }
    } catch (err) {
      console.error("cleanupExpired2FASessions: error deleting legacy twoFactorSessions:", err);
    }
  }
);
