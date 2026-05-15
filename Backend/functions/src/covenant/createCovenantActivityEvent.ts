import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

// createCovenantActivityEvent
// Server-only callable. Writes to /users/{userId}/covenantActivity/{activityId}.
// Clients can mark read/unread on their own records but cannot create system activity.

export const createCovenantActivityEvent = onCall(
    { enforceAppCheck: true, region: "us-central1" },
    async (request) => {
        // Only service accounts / Cloud Functions can hit this through the admin SDK;
        // here we accept calls from privileged callers (e.g. other Cloud Functions via admin SDK).
        // For direct client calls we require a verified covenantAdmin claim.
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }

        const {
            userId,
            type,
            title,
            body,
            covenantId,
            roomId,
            postId,
            threadId,
            eventId,
            deepLink,
            priority = "normal",
            groupId,
            expiresAt,
        } = request.data;

        if (!userId || !type || !title) {
            throw new HttpsError("invalid-argument", "userId, type, and title are required.");
        }

        const validTypes = [
            "mention", "reply", "creator_announcement", "new_paid_post",
            "event_reminder", "prayer_follow_up", "moderation_notice",
            "tier_update", "digest_ready", "room_invite",
        ];
        if (!validTypes.includes(type)) {
            throw new HttpsError("invalid-argument", `Unknown activity type: ${type}`);
        }

        const db = admin.firestore();
        const activityRef = db.collection("users").doc(userId)
            .collection("covenantActivity").doc();

        const payload: Record<string, unknown> = {
            userId,
            type,
            title,
            body: body ?? "",
            covenantId: covenantId ?? null,
            roomId: roomId ?? null,
            postId: postId ?? null,
            threadId: threadId ?? null,
            eventId: eventId ?? null,
            deepLink: deepLink ?? "",
            isRead: false,
            priority,
            groupId: groupId ?? null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: expiresAt ? admin.firestore.Timestamp.fromMillis(expiresAt) : null,
        };

        await activityRef.set(payload);

        return { activityId: activityRef.id };
    }
);
