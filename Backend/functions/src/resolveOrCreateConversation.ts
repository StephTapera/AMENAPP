import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { isBlocked as isBlockedEitherWay } from "./aclHelper";

const db = admin.firestore();

function participantHashFor(a: string, b: string): string {
    return [a, b].sort().join("_");
}

// isBlockedEitherWay is now aclHelper.isBlocked — uses top-level blockedUsers collection.

async function getFollowStatus(followerId: string, followingId: string): Promise<boolean> {
    const snapshot = await db.collection("follows")
        .where("followerId", "==", followerId)
        .where("followingId", "==", followingId)
        .limit(1)
        .get();

    return !snapshot.empty;
}

export const resolveOrCreateConversation = onCall({ enforceAppCheck: true }, async (request) => {
    const requesterId = request.auth?.uid;
    if (!requesterId) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const targetUserId = String(request.data?.targetUserId ?? "").trim();
    const sourcePostId = typeof request.data?.sourcePostId === "string"
        ? request.data.sourcePostId.trim()
        : "";

    if (!targetUserId) {
        throw new HttpsError("invalid-argument", "targetUserId is required.");
    }

    if (targetUserId === requesterId) {
        throw new HttpsError("failed-precondition", "Cannot message yourself.");
    }

    const [requesterSnap, targetSnap] = await Promise.all([
        db.collection("users").doc(requesterId).get(),
        db.collection("users").doc(targetUserId).get()
    ]);

    if (!requesterSnap.exists || !targetSnap.exists) {
        throw new HttpsError("not-found", "User not found.");
    }

    const requester = requesterSnap.data() ?? {};
    const target = targetSnap.data() ?? {};

    if (await isBlockedEitherWay(requesterId, targetUserId)) {
        throw new HttpsError("permission-denied", "Messaging unavailable.");
    }

    const allowMessagesFromEveryone = target.allowMessagesFromEveryone ?? true;
    const requireFollowToMessage = target.requireFollowToMessage ?? false;

    if (!allowMessagesFromEveryone) {
        throw new HttpsError("permission-denied", "This user is not accepting messages.");
    }

    if (requireFollowToMessage) {
        const requesterFollowsTarget = await getFollowStatus(requesterId, targetUserId);
        if (!requesterFollowsTarget) {
            throw new HttpsError("permission-denied", "This user is not accepting messages.");
        }
    }

    const participantHash = participantHashFor(requesterId, targetUserId);
    const conversationRef = db.collection("conversations").doc(participantHash);
    const existing = await conversationRef.get();

    if (existing.exists) {
        return { conversationId: conversationRef.id, created: false };
    }

    const [requesterFollowsTarget, targetFollowsRequester] = await Promise.all([
        getFollowStatus(requesterId, targetUserId),
        getFollowStatus(targetUserId, requesterId)
    ]);
    const isMutual = requesterFollowsTarget && targetFollowsRequester;
    const now = admin.firestore.FieldValue.serverTimestamp();

    await db.runTransaction(async (tx) => {
        const current = await tx.get(conversationRef);
        if (current.exists) {
            return;
        }

        tx.set(conversationRef, {
            participantIds: [requesterId, targetUserId].sort(),
            participantNames: {
                [requesterId]: requester.displayName ?? requester.username ?? "Unknown",
                [targetUserId]: target.displayName ?? target.username ?? "Unknown"
            },
            participantPhotoURLs: {
                [requesterId]: requester.profilePhotoURL ?? requester.profileImageURL ?? "",
                [targetUserId]: target.profilePhotoURL ?? target.profileImageURL ?? ""
            },
            participantHash,
            isGroup: false,
            groupName: null,
            groupAvatarUrl: null,
            lastMessage: null,
            lastMessageText: "",
            lastMessageTimestamp: now,
            unreadCounts: {},
            createdAt: now,
            updatedAt: now,
            conversationStatus: isMutual ? "accepted" : "pending",
            requesterId,
            requestReadBy: [],
            sourcePostId: sourcePostId || null
        });
    });

    if (sourcePostId) {
        await db.collection("users")
            .doc(targetUserId)
            .collection("notifications")
            .add({
                userId: targetUserId,
                type: "dm_cta_tap",
                actorId: requesterId,
                actorName: requester.displayName ?? requester.username ?? "Someone",
                actorUsername: requester.username ?? null,
                actorProfileImageURL: requester.profilePhotoURL ?? requester.profileImageURL ?? null,
                postId: sourcePostId,
                conversationId: conversationRef.id,
                read: false,
                createdAt: now,
                targetRouteType: "conversation",
                routePayload: {
                    conversationId: conversationRef.id
                },
                fallbackRouteType: "notifications_inbox",
                fallbackRoutePayload: {},
                schemaVersion: "v3",
                deepLinkVersion: "v3"
            });
    }

    return { conversationId: conversationRef.id, created: true };
});
