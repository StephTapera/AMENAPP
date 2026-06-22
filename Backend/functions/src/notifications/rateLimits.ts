/**
 * notifications/rateLimits.ts
 *
 * Firestore-backed bulk notification rate limiting.
 *
 * Two guards are exported:
 *
 *   checkAndIncrementBulkSendRateLimit(senderId)
 *     - Allows at most BULK_SEND_LIMIT_PER_MINUTE FCM sends per sender per
 *       rolling 60-second window. Throws HttpsError('resource-exhausted') when
 *       the limit is hit. Uses a Firestore doc keyed by
 *       `_rateLimits/notif_{senderId}_{minuteBucket}` so multiple Cloud
 *       Function instances converge on the same counter.
 *
 *   assertRecipientCountWithinCap(recipientIds, cap?)
 *     - Throws HttpsError('invalid-argument') when the recipient list exceeds
 *       MAX_RECIPIENTS_PER_CALL (500). Call this before fan-out to prevent
 *       runaway broadcast calls.
 *
 * TTL POLICY NOTE:
 *   Each rate-limit doc contains a `ttl` Timestamp field set 120 seconds into
 *   the future. To auto-delete stale docs you MUST create a Firestore TTL
 *   policy in the Firebase console:
 *     Collection group : _rateLimits
 *     Timestamp field  : ttl
 *   Without this, docs accumulate indefinitely (they are safe to ignore but
 *   waste storage). The TTL policy is a one-time console step and cannot be
 *   set via code.
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

const db = admin.firestore();

// ─── Constants ──────────────────────────────────────────────────────

/** Maximum FCM sends a single sender may trigger in one 60-second window. */
export const BULK_SEND_LIMIT_PER_MINUTE = 100;

/** Maximum recipients allowed in a single broadcast/bulk call. */
export const MAX_RECIPIENTS_PER_CALL = 500;

/** How long (ms) each rate-limit counter document lives before TTL cleans it. */
const RATE_LIMIT_TTL_MS = 120_000; // 2 minutes — covers the current + next window

// ─── Rate Limit Guard ────────────────────────────────────────────────

/**
 * Checks the per-sender-per-minute bulk-send counter.
 *
 * Uses Firestore as the distributed counter so that concurrent Cloud Function
 * instances — which each run in their own process — share the same count.
 * The document key includes the Unix-minute bucket so each 60-second window
 * starts a fresh counter.
 *
 * @param senderId  Firebase Auth UID of the user or system actor sending
 *                  notifications (used as the rate-limit key).
 *
 * @throws HttpsError('resource-exhausted') when the sender has reached
 *         BULK_SEND_LIMIT_PER_MINUTE in the current minute window.
 */
export async function checkAndIncrementBulkSendRateLimit(
    senderId: string
): Promise<void> {
    const minuteBucket = Math.floor(Date.now() / 60_000);
    const rateLimitRef = db
        .collection("_rateLimits")
        .doc(`notif_${senderId}_${minuteBucket}`);

    await db.runTransaction(async (transaction) => {
        const rateDoc = await transaction.get(rateLimitRef);
        const currentCount: number = rateDoc.exists
            ? (rateDoc.data()?.count ?? 0)
            : 0;

        if (currentCount >= BULK_SEND_LIMIT_PER_MINUTE) {
            // Throw inside the transaction — Firebase rolls back and surfaces the error.
            throw new HttpsError(
                "resource-exhausted",
                `Notification rate limit exceeded. Maximum ${BULK_SEND_LIMIT_PER_MINUTE} sends per minute.`
            );
        }

        // Increment and (re-)write TTL so Firestore TTL policy can clean up.
        // NOTE: A TTL policy must be configured in the Firebase console on
        //       collection group '_rateLimits', field 'ttl'.
        transaction.set(
            rateLimitRef,
            {
                count: currentCount + 1,
                senderId,
                minuteBucket,
                // ttl is a Firestore Timestamp; the console TTL policy deletes
                // docs after this time has passed.
                ttl: admin.firestore.Timestamp.fromMillis(
                    Date.now() + RATE_LIMIT_TTL_MS
                ),
            },
            { merge: true }
        );
    });
}

// ─── Recipient Count Guard ───────────────────────────────────────────

/**
 * Asserts that a recipient list does not exceed the per-call cap.
 *
 * FCM's sendEachForMulticast API supports up to 500 tokens per call.
 * Allowing more than this on the application layer would require
 * unbounded batching inside a single function invocation, which risks
 * Cloud Function timeouts for large broadcasts.
 *
 * @param recipientIds  Array of recipient user IDs or FCM tokens.
 * @param cap           Override the default MAX_RECIPIENTS_PER_CALL cap.
 *
 * @throws HttpsError('invalid-argument') when the list exceeds the cap.
 */
export function assertRecipientCountWithinCap(
    recipientIds: string[],
    cap: number = MAX_RECIPIENTS_PER_CALL
): void {
    if (recipientIds.length > cap) {
        throw new HttpsError(
            "invalid-argument",
            `Too many recipients. Maximum ${cap} per call; got ${recipientIds.length}.`
        );
    }
}
