/**
 * notifications/sendPush.ts
 *
 * FCM push dispatch with APNs-compatible payload construction.
 * Handles multi-device delivery, invalid token cleanup,
 * privacy-aware content, and collapse key management.
 */

import * as admin from "firebase-admin";
import {
    NotificationType,
    NotificationDocument,
    PushPayload,
    LockScreenPrivacy,
    RoutePayload,
    SCHEMA_VERSION,
    DEEP_LINK_VERSION,
} from "./types";
import {
    getDeviceTokens,
    markTokenInvalid,
    getUserPreferences,
    buildPushText,
    buildGroupingKey,
    getCategoryForType,
} from "./helpers";

const db = admin.firestore();

// ─── Push Result ────────────────────────────────────────────────────

export interface PushResult {
    success: boolean;
    tokensAttempted: number;
    tokensSucceeded: number;
    tokensFailed: number;
    invalidTokensCleaned: number;
}

// ─── Send Push ──────────────────────────────────────────────────────

/**
 * Sends push notification to all active device tokens for the recipient.
 *
 * Steps:
 * 1. Fetch device tokens
 * 2. Load privacy preferences
 * 3. Build APNs-compatible payload
 * 4. Send via FCM multicast
 * 5. Clean up invalid tokens
 * 6. Update notification doc with delivery status
 */
export async function sendPushNotification(
    notificationDoc: NotificationDocument,
    notificationId: string,
    precomputedBadgeCount?: number
): Promise<PushResult> {
    const tokens = await getDeviceTokens(notificationDoc.userId);

    if (tokens.length === 0) {
        return {
            success: false,
            tokensAttempted: 0,
            tokensSucceeded: 0,
            tokensFailed: 0,
            invalidTokensCleaned: 0,
        };
    }

    // Load user preferences for privacy level
    const prefs = await getUserPreferences(notificationDoc.userId);
    const type = notificationDoc.type as NotificationType;

    // Build push text respecting privacy settings
    const { title, body } = buildPushText(
        type,
        notificationDoc.actorName || "Someone",
        prefs.lockScreenPrivacy,
        {
            commentText: notificationDoc.commentText || undefined,
            actorCount: notificationDoc.actorCount || undefined,
        }
    );

    // Check if sound is allowed for this category
    const category = getCategoryForType(type);
    const catPref = prefs.categories[category];
    const soundEnabled = catPref?.soundEnabled ?? true;

    // Build the grouping/collapse key
    const targetEntityId =
        notificationDoc.postId ||
        notificationDoc.commentId ||
        notificationDoc.conversationId ||
        notificationDoc.prayerId ||
        notificationDoc.noteId ||
        notificationDoc.userId;
    const collapseKey = buildGroupingKey(type, targetEntityId);

    // Use the pre-computed badge count when provided (avoids the read-after-write
    // race condition under concurrent notifications). Fall back to a direct read
    // only for callers that don't pass the increment result.
    const badgeCount =
        precomputedBadgeCount !== undefined
            ? precomputedBadgeCount
            : await getUnreadCount(notificationDoc.userId);

    // Build APNs-compatible payload
    const payload = buildPayload({
        title,
        body,
        type,
        notificationId,
        targetRouteType: notificationDoc.targetRouteType || "notifications_inbox",
        routePayload: notificationDoc.routePayload || {},
        fallbackRouteType: notificationDoc.fallbackRouteType || "notifications_inbox",
        fallbackRoutePayload: notificationDoc.fallbackRoutePayload || {},
        collapseKey,
        badgeCount,
        soundEnabled,
        threadId: notificationDoc.groupId || collapseKey,
    });

    // Send to all device tokens
    const tokenStrings = tokens.map((t) => t.token);
    const result = await sendMulticast(tokenStrings, payload);

    // Clean up invalid tokens
    let invalidTokensCleaned = 0;
    if (result.failedTokens.length > 0) {
        for (const failedToken of result.failedTokens) {
            await markTokenInvalid(notificationDoc.userId, failedToken);
            invalidTokensCleaned++;
        }
    }

    // Update notification doc with delivery status
    if (result.successCount > 0) {
        await db
            .collection("users")
            .doc(notificationDoc.userId)
            .collection("notifications")
            .doc(notificationId)
            .update({
                pushDelivered: true,
                pushDeliveredAt: admin.firestore.FieldValue.serverTimestamp(),
            });
    }

    return {
        success: result.successCount > 0,
        tokensAttempted: tokenStrings.length,
        tokensSucceeded: result.successCount,
        tokensFailed: result.failureCount,
        invalidTokensCleaned,
    };
}

// ─── Payload Builder ────────────────────────────────────────────────

interface PayloadOpts {
    title: string;
    body: string;
    type: NotificationType;
    notificationId: string;
    targetRouteType: string;
    routePayload: RoutePayload;
    fallbackRouteType: string;
    fallbackRoutePayload: RoutePayload;
    collapseKey: string;
    badgeCount: number;
    soundEnabled: boolean;
    threadId: string;
}

function buildPayload(opts: PayloadOpts): admin.messaging.MulticastMessage {
    return {
        notification: {
            title: opts.title,
            body: opts.body,
        },
        data: {
            type: opts.type,
            notificationId: opts.notificationId,
            targetRouteType: opts.targetRouteType,
            routePayload: JSON.stringify(opts.routePayload),
            fallbackRouteType: opts.fallbackRouteType,
            fallbackRoutePayload: JSON.stringify(opts.fallbackRoutePayload),
            collapseKey: opts.collapseKey,
            schemaVersion: SCHEMA_VERSION,
            deepLinkVersion: DEEP_LINK_VERSION,
        },
        apns: {
            payload: {
                aps: {
                    badge: opts.badgeCount,
                    sound: opts.soundEnabled ? "default" : undefined,
                    mutableContent: true,
                    threadId: opts.threadId,
                    category: opts.type,
                    // contentAvailable is intentionally omitted for social event
                    // notifications — Apple rate-limits background push throughput and
                    // setting this on every notification can delay delivery.
                    // Only background sync notifications should set contentAvailable.
                },
            },
            headers: {
                "apns-collapse-id": opts.collapseKey.substring(0, 64),
                "apns-priority": "10",
            },
        },
        // Required but filled in by sendMulticast
        tokens: [],
    };
}

// ─── Multicast Sender ───────────────────────────────────────────────

interface MulticastResult {
    successCount: number;
    failureCount: number;
    failedTokens: string[];
}

/**
 * Sends push to multiple tokens via FCM sendEachForMulticast.
 * Returns which tokens failed for cleanup.
 */
async function sendMulticast(
    tokens: string[],
    message: admin.messaging.MulticastMessage
): Promise<MulticastResult> {
    // FCM has a 500-token limit per multicast call
    const BATCH_SIZE = 500;
    let totalSuccess = 0;
    let totalFailure = 0;
    const allFailedTokens: string[] = [];

    for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
        const batch = tokens.slice(i, i + BATCH_SIZE);
        const batchMessage = { ...message, tokens: batch };

        // Retry transient FCM batch failures with exponential backoff (3 attempts).
        const MAX_ATTEMPTS = 3;
        let lastError: unknown;
        let succeeded = false;

        for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
            try {
                const response =
                    await admin.messaging().sendEachForMulticast(batchMessage);

                totalSuccess += response.successCount;
                totalFailure += response.failureCount;

                // Identify permanently invalid tokens for cleanup
                response.responses.forEach((resp, index) => {
                    if (resp.error) {
                        const errorCode = resp.error.code;
                        if (
                            errorCode === "messaging/registration-token-not-registered" ||
                            errorCode === "messaging/invalid-registration-token" ||
                            errorCode === "messaging/invalid-argument"
                        ) {
                            allFailedTokens.push(batch[index]);
                        }
                    }
                });

                succeeded = true;
                break;
            } catch (error) {
                lastError = error;
                if (attempt < MAX_ATTEMPTS) {
                    // Exponential backoff: 500 ms, 1000 ms between attempts
                    await new Promise((resolve) =>
                        setTimeout(resolve, 500 * attempt)
                    );
                }
            }
        }

        if (!succeeded) {
            // All retry attempts exhausted — treat entire batch as transient failure.
            // Item-15 FIX: Write to dead-letter queue so the failure is observable,
            // alertable, and replayable instead of silently dropped.
            totalFailure += batch.length;
            console.error(
                `FCM multicast batch failed after ${MAX_ATTEMPTS} attempts ` +
                `(tokens ${i}-${i + batch.length}):`,
                lastError
            );
            db.collection("notificationDeadLetterQueue").add({
                failedTokens: batch,
                notificationPayload: {
                    title: message.notification?.title ?? "",
                    body: message.notification?.body ?? "",
                    data: message.data ?? {},
                },
                failureReason: lastError instanceof Error ? lastError.message : String(lastError),
                attemptsExhausted: MAX_ATTEMPTS,
                enqueuedAt: admin.firestore.FieldValue.serverTimestamp(),
                status: "pending_retry",
            }).catch((dlqErr) =>
                console.error("[sendPush] Dead-letter queue write failed:", dlqErr)
            );
        }
    }

    return {
        successCount: totalSuccess,
        failureCount: totalFailure,
        failedTokens: allFailedTokens,
    };
}

// ─── Unread Count Helper ────────────────────────────────────────────

/**
 * Gets the current unread notification count for badge number.
 * Reads from the notification state document (fast) or falls back
 * to counting unread docs (slower, more accurate).
 */
async function getUnreadCount(userId: string): Promise<number> {
    // Try the fast path: read from notification state doc
    const stateDoc = await db
        .collection("users")
        .doc(userId)
        .collection("notificationState")
        .doc("inbox")
        .get();

    if (stateDoc.exists) {
        const data = stateDoc.data();
        if (data && typeof data.unseenCount === "number") {
            return data.unseenCount;
        }
    }

    // Slow fallback: count unread notifications (capped for performance)
    const unreadSnapshot = await db
        .collection("users")
        .doc(userId)
        .collection("notifications")
        .where("read", "==", false)
        .limit(100)
        .get();

    return unreadSnapshot.size;
}
