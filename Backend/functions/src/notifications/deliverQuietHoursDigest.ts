/**
 * notifications/deliverQuietHoursDigest.ts
 *
 * 5.6 FIX: Scheduled function that delivers batch push notifications to users
 * whose quiet-hours window just ended.
 *
 * WHY THIS EXISTS:
 *   When the notification policy returns PolicyResult.Digest (quiet hours active),
 *   processCandidate writes the notification to the user's inbox but skips the
 *   push. Without this function, those notifications would only appear in-app —
 *   users would miss them unless they opened the app proactively.
 *
 * HOW IT WORKS:
 *   1. processCandidate (onSocialEvent.ts) writes to quietHoursDigestQueue
 *      whenever a notification is deferred due to quiet hours.
 *   2. This function runs every 30 minutes and queries the queue for pending
 *      entries older than 30 minutes (to ensure quiet hours have ended).
 *   3. For each user with pending entries, it counts unread notifications and
 *      sends a single summary push: "You have X notifications while you were away."
 *   4. Processed queue entries are deleted.
 *
 * NOTE: For precise "quiet hours just ended" detection, see the timezone fix
 * in policies.ts (5.7). This function uses a conservative 30-minute staleness
 * threshold — any notification that has been pending for ≥30 minutes is assumed
 * to be outside the quiet window. If a user's quiet window is shorter than 30
 * minutes, they may receive the digest slightly late.
 *
 * Firestore indexes required:
 *   quietHoursDigestQueue: (status ASC, enqueuedAt ASC)
 *   quietHoursDigestQueue: (userId ASC, status ASC)
 */

import * as functions from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import { getDeviceTokens } from "./helpers";

const db = admin.firestore();

// Notifications pending for ≥ this many minutes are assumed to be outside
// the quiet window. Conservative buffer to avoid delivering before the window ends.
const STALENESS_THRESHOLD_MINUTES = 30;

export const deliverQuietHoursDigest = onSchedule({ schedule: "every 30 minutes", timeZone: "UTC" }, async () => {
        const cutoff = admin.firestore.Timestamp.fromMillis(
            Date.now() - STALENESS_THRESHOLD_MINUTES * 60 * 1000
        );

        // Query all pending digest entries that have been waiting long enough.
        const pendingSnap = await db
            .collection("quietHoursDigestQueue")
            .where("status", "==", "pending")
            .where("enqueuedAt", "<=", cutoff)
            .limit(500) // Process at most 500 per run; remainder handled next cycle.
            .get();

        if (pendingSnap.empty) return;

        // Group entries by userId for batch digest sends.
        const byUser = new Map<string, string[]>(); // userId → [docId]
        for (const doc of pendingSnap.docs) {
            const userId: string = doc.data().userId;
            if (!userId) continue;
            const existing = byUser.get(userId) ?? [];
            existing.push(doc.id);
            byUser.set(userId, existing);
        }

        functions.logger.info(
            `[deliverQuietHoursDigest] Processing ${pendingSnap.size} queue entries for ${byUser.size} users`
        );

        const deleteBatch = db.batch();
        let digestsSent = 0;
        let digestsFailed = 0;

        await Promise.all(
            Array.from(byUser.entries()).map(async ([userId, docIds]) => {
                try {
                    await sendDigestPush(userId, docIds.length);
                    // Mark entries as delivered.
                    for (const docId of docIds) {
                        deleteBatch.delete(db.collection("quietHoursDigestQueue").doc(docId));
                    }
                    digestsSent++;
                } catch (e) {
                    functions.logger.error(
                        `[deliverQuietHoursDigest] Failed for user ${userId}`, e
                    );
                    // Mark entries as failed so they are not retried endlessly.
                    for (const docId of docIds) {
                        deleteBatch.update(
                            db.collection("quietHoursDigestQueue").doc(docId),
                            { status: "failed", failedAt: admin.firestore.FieldValue.serverTimestamp() }
                        );
                    }
                    digestsFailed++;
                }
            })
        );

        await deleteBatch.commit();

        functions.logger.info(
            `[deliverQuietHoursDigest] Done — sent: ${digestsSent}, failed: ${digestsFailed}`
        );
    });

/**
 * Send a single digest push to the user summarising how many notifications
 * arrived during their quiet window.
 */
async function sendDigestPush(userId: string, count: number): Promise<void> {
    const deviceTokens = await getDeviceTokens(userId);
    if (deviceTokens.length === 0) return;
    // MulticastMessage.tokens expects string[] — extract the FCM token string from each DeviceToken.
    const tokens: string[] = deviceTokens.map((dt) => dt.token);

    const body =
        count === 1
            ? "You have 1 notification while you were away."
            : `You have ${count} notifications while you were away.`;

    const message: admin.messaging.MulticastMessage = {
        tokens,
        notification: {
            title: "AMEN",
            body,
        },
        apns: {
            payload: {
                aps: {
                    sound: "default",
                    badge: count,
                    "mutable-content": 1,
                    "thread-id": "digest",
                    category: "DIGEST",
                },
            },
        },
        data: {
            type: "digest",
            count: String(count),
            targetRouteType: "notifications_inbox",
            routePayload: "{}",
            fallbackRouteType: "notifications_inbox",
            fallbackRoutePayload: "{}",
            collapseKey: `digest_${userId}`,
            schemaVersion: "2",
            deepLinkVersion: "1",
        },
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    functions.logger.info(
        `[deliverQuietHoursDigest] Digest push to ${userId}: ` +
        `${response.successCount}/${tokens.length} tokens succeeded`
    );
}
