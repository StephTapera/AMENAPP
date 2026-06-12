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
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = admin.firestore();

// ─── Private Account Helper ───────────────────────────────────────────────────

/** Returns the privacy state of a user account. */
async function getAccountState(
    uid: string
): Promise<{ isPrivate: boolean; ageTier: string | null }> {
    const doc = await db.collection("users").doc(uid).get();
    return {
        isPrivate: doc.data()?.isPrivate === true,
        ageTier: (doc.data()?.ageTier as string | null) ?? null,
    };
}

// ─── Rate Limiting ────────────────────────────────────────────────────────────

const HOURLY_FOLLOW_LIMIT = 200;
const HOUR_MS = 3_600_000;

/**
 * Throws resource-exhausted if followerId has exceeded HOURLY_FOLLOW_LIMIT
 * follow operations in the current clock hour.
 *
 * Uses a Firestore counter doc with a 2-hour TTL for automatic cleanup.
 * The transaction makes the check-and-increment atomic under concurrent calls.
 */
async function enforceFollowRateLimit(followerId: string): Promise<void> {
    const hourBucket = Math.floor(Date.now() / HOUR_MS);
    const rateLimitRef = db
        .collection("_rateLimits")
        .doc(`follow_${followerId}_${hourBucket}`);

    await db.runTransaction(async (tx) => {
        const doc = await tx.get(rateLimitRef);
        const count: number = doc.exists ? ((doc.data()?.count as number) ?? 0) : 0;

        if (count >= HOURLY_FOLLOW_LIMIT) {
            throw new HttpsError(
                "resource-exhausted",
                "Follow rate limit exceeded. Please slow down before following more people."
            );
        }

        tx.set(
            rateLimitRef,
            {
                count: count + 1,
                uid: followerId,
                bucket: hourBucket,
                // TTL for automatic cleanup (2 hours from bucket start)
                ttl: admin.firestore.Timestamp.fromMillis((hourBucket + 2) * HOUR_MS),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
        );
    });
}

export const createFollow = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    if (!context.auth) {
        throw new HttpsError(
            "unauthenticated",
            "Must be signed in to follow a user."
        );
    }

    if (context.app == undefined) {
        throw new HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }

    const followerId = context.auth.uid;
    const followingId: unknown = data?.followingId;

    if (typeof followingId !== "string" || followingId.trim() === "") {
        throw new HttpsError(
            "invalid-argument",
            "followingId must be a non-empty string."
        );
    }

    if (followerId === followingId) {
        throw new HttpsError(
            "invalid-argument",
            "Cannot follow yourself."
        );
    }

    // Server-side rate limit: max 200 follows per hour.
    // Prevents mass-follow abuse and follow-churn cycling.
    // See docs/privacy-model.md §2 (Follow Churn Abuse).
    await enforceFollowRateLimit(followerId);

    const now = admin.firestore.FieldValue.serverTimestamp();
    const indexId = `${followerId}_${followingId}`;

    // Check for existing follow (idempotent)
    const existingIndex = await db.collection("follows_index").doc(indexId).get();
    if (existingIndex.exists) {
        return { success: true, alreadyFollowing: true };
    }

    // ── Private-account gate (docs/privacy-model.md §2) ──────────────────────
    // If the target account is private, create a follow REQUEST instead of an
    // edge. A pending request is NOT a follow — it must never be treated as one.
    const [callerState, targetState] = await Promise.all([
        getAccountState(followerId),
        getAccountState(followingId as string),
    ]);

    if (targetState.isPrivate) {
        // Check for an existing pending request (idempotent)
        const existingRequest = await db
            .collection("users")
            .doc(followingId as string)
            .collection("followRequests")
            .doc(followerId)
            .get();
        if (existingRequest.exists) {
            return { success: true, requestAlreadySent: true };
        }

        // Create the follow request doc. GUARDIAN: adult→minor requests are stored
        // with a guardian flag so the notification policy can route them appropriately.
        const isAdultToMinor =
            !callerState.ageTier?.startsWith("tier") &&
            (targetState.ageTier === "tierB" || targetState.ageTier === "tierC");

        await db
            .collection("users")
            .doc(followingId as string)
            .collection("followRequests")
            .doc(followerId)
            .set({
                requesterId: followerId,
                targetId: followingId,
                status: "pending",
                guardianRouted: isAdultToMinor,
                createdAt: now,
            });

        functions.logger.info(
            `[createFollow] Follow request: ${followerId} → ${followingId}` +
            (isAdultToMinor ? " [GUARDIAN]" : "")
        );
        return { success: true, requestSent: true };
    }

    // ── Public account: create follow edge atomically ─────────────────────────
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
    batch.update(db.collection("users").doc(followingId as string), {
        followersCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
    });

    await batch.commit();

    functions.logger.info(`[createFollow] ${followerId} → ${followingId}`);
    return { success: true };
});

// ─── createUnfollow ───────────────────────────────────────────────────────────

export const createUnfollow = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    if (!context.auth) {
        throw new HttpsError(
            "unauthenticated",
            "Must be signed in to unfollow a user."
        );
    }

    if (context.app == undefined) {
        throw new HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }

    const followerId = context.auth.uid;
    const followingId: unknown = data?.followingId;

    if (typeof followingId !== "string" || followingId.trim() === "") {
        throw new HttpsError(
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
