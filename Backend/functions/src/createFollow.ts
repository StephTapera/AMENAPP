/**
 * createFollow.ts
 *
 * WHY THIS EXISTS:
 *   Following a user requires two Firestore writes:
 *     1. follows/{docId}                           — the follow edge document
 *        (followerId, followingId, createdAt)
 *     2. follows_index/{followerId}_{followingId}  — O(1) index doc
 *        used by callerFollows() in Firestore security rules and by
 *        callerCanReadPost() to gate follower-only content visibility
 *
 *   FollowService.swift currently writes both from the client. If the device
 *   loses connectivity between the two writes, follows_index is missing:
 *     • callerFollows() → false
 *     • Follower-only posts are invisible to the follower
 *     • callerCanComment() may deny access to comment threads
 *
 *   This callable writes both in a single Firestore batch (atomic) and
 *   additionally increments followersCount / followingCount on the affected
 *   user documents — replacing the separate client-side counter write.
 *
 * createUnfollow mirrors this for the delete path.
 *
 * MIGRATION:
 *   FollowService.swift should call these callables instead of direct Firestore
 *   writes. After all clients are on the new version, restrict direct writes:
 *     match /follows/{followId}      { allow create: if false; }
 *     match /follows_index/{indexId} { allow create, update: if false; }
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

export const createFollow = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Must be signed in to follow a user."
        );
    }

    if (context.app == undefined) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }

    const followerId = context.auth.uid;
    const followingId: unknown = data?.followingId;

    if (typeof followingId !== "string" || followingId.trim() === "") {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "followingId must be a non-empty string."
        );
    }

    if (followerId === followingId) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Cannot follow yourself."
        );
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const indexId = `${followerId}_${followingId}`;

    // Check for existing follow to make this idempotent
    const existingIndex = await db.collection("follows_index").doc(indexId).get();
    if (existingIndex.exists) {
        return { success: true, alreadyFollowing: true };
    }

    const followDocRef = db.collection("follows").doc(indexId);
    const indexDocRef = db.collection("follows_index").doc(indexId);

    const batch = db.batch();

    // Edge doc
    batch.set(followDocRef, {
        followerId,
        followingId,
        createdAt: now,
    }, { merge: true });

    // Index doc (used by Firestore rules callerFollows())
    batch.set(indexDocRef, {
        followerId,
        followingId,
        createdAt: now,
    }, { merge: true });

    // Counter increments (atomic, best-effort — reconciliation runs weekly)
    batch.update(db.collection("users").doc(followerId), {
        followingCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
    });
    batch.update(db.collection("users").doc(followingId), {
        followersCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
    });

    await batch.commit();

    functions.logger.info(`[createFollow] ${followerId} → ${followingId}`);
    return { success: true };
});

// ─── createUnfollow ───────────────────────────────────────────────────────────

export const createUnfollow = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Must be signed in to unfollow a user."
        );
    }

    if (context.app == undefined) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }

    const followerId = context.auth.uid;
    const followingId: unknown = data?.followingId;

    if (typeof followingId !== "string" || followingId.trim() === "") {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "followingId must be a non-empty string."
        );
    }

    const indexId = `${followerId}_${followingId}`;
    const now = admin.firestore.FieldValue.serverTimestamp();

    const batch = db.batch();

    // Delete edge doc (idempotent — rules allow delete when resource==null)
    batch.delete(db.collection("follows").doc(indexId));
    batch.delete(db.collection("follows_index").doc(indexId));

    // Counter decrements
    batch.update(db.collection("users").doc(followerId), {
        followingCount: admin.firestore.FieldValue.increment(-1),
        updatedAt: now,
    });
    batch.update(db.collection("users").doc(followingId), {
        followersCount: admin.firestore.FieldValue.increment(-1),
        updatedAt: now,
    });

    await batch.commit();

    functions.logger.info(`[createUnfollow] ${followerId} ↛ ${followingId}`);
    return { success: true };
});
