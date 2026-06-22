/**
 * usernameChangeTracking.ts
 *
 * Section-13 FIX: Username change rate limiting (30-day cooldown).
 *
 * PROBLEM:
 *   Users can change their username repeatedly, enabling impersonation attacks
 *   and making harassment harder to trace.
 *
 * SOLUTION:
 *   1. trackUsernameChange (Firestore onUpdate trigger on users/{uid}):
 *      When a user document's `username` field changes, writes to
 *      userSafetyRecords/{uid}:
 *        • usernameChangedAt:  server timestamp of the change
 *        • canChangeUsername:  false  (locks out further changes)
 *        • previousUsername:   the old username (audit trail)
 *
 *   2. usernameChangeCooldownRelease (daily scheduled, in scheduledMaintenance.ts):
 *      Finds all userSafetyRecords where canChangeUsername == false AND
 *      usernameChangeCooldownUntil <= now, and sets canChangeUsername: true.
 *
 *   3. Firestore rule (users/{userId} allow update):
 *      Already reads userSafetyRecords/{uid}.canChangeUsername. The existing
 *      check prevents username writes when canChangeUsername == false.
 *
 * Uses gen2 Firestore trigger syntax to coexist with other gen2 triggers.
 */

import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

const db = admin.firestore();

/** Cooldown duration in milliseconds (30 days). */
const USERNAME_COOLDOWN_MS = 30 * 24 * 60 * 60 * 1000;

// ─── Trigger: record username change ─────────────────────────────────────────

export const trackUsernameChange = onDocumentUpdated("users/{uid}", async (event) => {
    const { uid } = event.params;
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) return;

    // Only act when username actually changed.
    if (before.username === after.username) return;

    const now = admin.firestore.FieldValue.serverTimestamp();
    const cooldownUntilMs = Date.now() + USERNAME_COOLDOWN_MS;

    logger.info(
        `[trackUsernameChange] User ${uid} changed username ` +
        `"${before.username}" → "${after.username}" — locking for 30 days.`
    );

    await db.collection("userSafetyRecords").doc(uid).set(
        {
            canChangeUsername: false,
            usernameChangedAt: now,
            usernameChangeCooldownUntil: admin.firestore.Timestamp.fromMillis(cooldownUntilMs),
            previousUsername: before.username ?? null,
            usernameChangeHistory: admin.firestore.FieldValue.arrayUnion({
                from: before.username ?? null,
                to: after.username ?? null,
                changedAt: admin.firestore.Timestamp.fromMillis(Date.now()),
            }),
        },
        { merge: true }
    );
});
