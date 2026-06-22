/**
 * notifications/sendNotificationCallable.ts
 *
 * Callable: sendNotification
 *
 * Allows an authenticated client to send a single FCM push notification to
 * one recipient. All calls are:
 *
 *   1. Authenticated — caller must be signed in; their UID is the senderId.
 *   2. Rate-limited  — at most BULK_SEND_LIMIT_PER_MINUTE (100) sends per
 *      sender per minute via the Firestore-backed counter in rateLimits.ts.
 *   3. Recipient-capped — this callable accepts a single recipientId only;
 *      bulk broadcast paths (fan-out triggers) are handled by the Firestore
 *      trigger pipeline in onSocialEvent.ts.
 *
 * Input:
 *   {
 *     recipientId : string   — Firebase Auth UID of the recipient
 *     title       : string   — notification title (max 200 chars)
 *     body        : string   — notification body  (max 500 chars)
 *     data?       : Record<string, string>  — optional FCM data payload
 *   }
 *
 * Output:
 *   { success: true; messageId: string }
 *   | { success: false; reason: string }
 *
 * Security:
 *   - Caller can only send to OTHER users (self-send is rejected).
 *   - Block checks are enforced: if either user has blocked the other
 *     the call returns { success: false, reason: 'blocked' } without
 *     consuming rate-limit quota.
 *   - The recipient's FCM tokens are fetched server-side; the client
 *     never sees another user's device tokens.
 *
 * TTL NOTE: Rate-limit docs in _rateLimits must have a TTL policy
 *   configured in the Firebase console (collection group _rateLimits,
 *   field ttl). See rateLimits.ts for details.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { getDeviceTokens, isBlocked } from "./helpers";
import {
    checkAndIncrementBulkSendRateLimit,
    assertRecipientCountWithinCap,
} from "./rateLimits";

const db = admin.firestore();

// ─── Input Validation ────────────────────────────────────────────────

interface SendNotificationRequest {
    recipientId: string;
    title: string;
    body: string;
    data?: Record<string, string>;
}

function validateRequest(raw: unknown): SendNotificationRequest {
    if (!raw || typeof raw !== "object") {
        throw new HttpsError("invalid-argument", "Request body must be an object.");
    }

    const req = raw as Record<string, unknown>;

    if (typeof req.recipientId !== "string" || req.recipientId.trim() === "") {
        throw new HttpsError("invalid-argument", "recipientId is required.");
    }

    if (typeof req.title !== "string" || req.title.trim() === "") {
        throw new HttpsError("invalid-argument", "title is required.");
    }

    if (typeof req.body !== "string" || req.body.trim() === "") {
        throw new HttpsError("invalid-argument", "body is required.");
    }

    if (req.title.length > 200) {
        throw new HttpsError("invalid-argument", "title must be 200 characters or fewer.");
    }

    if (req.body.length > 500) {
        throw new HttpsError("invalid-argument", "body must be 500 characters or fewer.");
    }

    if (req.data !== undefined) {
        if (
            typeof req.data !== "object" ||
            req.data === null ||
            Array.isArray(req.data)
        ) {
            throw new HttpsError("invalid-argument", "data must be a string-keyed object when provided.");
        }
        // Ensure every value is a string (FCM data payload requirement)
        for (const [k, v] of Object.entries(req.data as object)) {
            if (typeof k !== "string" || typeof v !== "string") {
                throw new HttpsError(
                    "invalid-argument",
                    "All keys and values in data must be strings."
                );
            }
        }
    }

    return {
        recipientId: req.recipientId.trim(),
        title: req.title.trim(),
        body: req.body.trim(),
        data: req.data as Record<string, string> | undefined,
    };
}

// ─── Callable ────────────────────────────────────────────────────────

export const sendNotification = onCall({ enforceAppCheck: true }, async (request) => {
    // 1. Auth gate
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Must be signed in to send notifications.");
    }

    const senderId = request.auth.uid;
    const req = validateRequest(request.data);
    const { recipientId, title, body, data } = req;

    // 2. Self-send guard
    if (senderId === recipientId) {
        throw new HttpsError("invalid-argument", "Cannot send a notification to yourself.");
    }

    // 3. Single-recipient cap (this callable is 1:1; broadcast uses the trigger pipeline)
    assertRecipientCountWithinCap([recipientId], 1);

    // 4. Block check — don't charge rate-limit quota for blocked pairs
    const blocked = await isBlocked(senderId, recipientId);
    if (blocked) {
        return { success: false, reason: "blocked" };
    }

    // 5. Rate limit — max BULK_SEND_LIMIT_PER_MINUTE sends per sender per minute.
    //    Throws HttpsError('resource-exhausted') if limit is exceeded.
    await checkAndIncrementBulkSendRateLimit(senderId);

    // 6. Fetch recipient device tokens (server-side; never exposed to caller)
    const deviceTokens = await getDeviceTokens(recipientId);
    if (deviceTokens.length === 0) {
        return { success: false, reason: "no_device_tokens" };
    }

    // 7. Build FCM message
    const tokens = deviceTokens.map((dt) => dt.token);
    const message: admin.messaging.MulticastMessage = {
        tokens,
        notification: { title, body },
        apns: {
            payload: {
                aps: {
                    sound: "default",
                    mutableContent: true,
                    category: "DIRECT",
                },
            },
        },
        data: {
            // Always include routing defaults so the iOS handler can parse safely
            type: "direct",
            targetRouteType: "notifications_inbox",
            routePayload: "{}",
            fallbackRouteType: "notifications_inbox",
            fallbackRoutePayload: "{}",
            collapseKey: `direct_${senderId}_${recipientId}`,
            schemaVersion: "2",
            deepLinkVersion: "1",
            // Merge caller-supplied data last so it cannot override routing keys
            ...data,
        },
    };

    // 8. Dispatch via FCM
    const response = await admin.messaging().sendEachForMulticast(message);

    // 9. Record the send for audit / observability
    await db.collection("notificationSendLog").add({
        senderId,
        recipientId,
        title,
        // body is not stored to limit PII retention
        tokensAttempted: tokens.length,
        tokensSucceeded: response.successCount,
        tokensFailed: response.failureCount,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (response.successCount > 0) {
        // Return the messageId of the first successful send for traceability
        const firstSuccess = response.responses.find((r) => r.success);
        return {
            success: true,
            messageId: firstSuccess?.messageId ?? "delivered",
        };
    }

    return { success: false, reason: "fcm_all_tokens_failed" };
});
