/**
 * followRequests.ts
 *
 * WHY THIS EXISTS:
 *   The `createFollow` callable routes private-account follow attempts here by
 *   creating a `users/{targetId}/followRequests/{requesterId}` document. This
 *   module provides all lifecycle operations for that request, plus the
 *   `removeFollower` callable and the `onAccountPrivacyChange` trigger that
 *   auto-accepts pending requests when an account goes public.
 *
 * Callables:
 *   acceptFollowRequest(requesterId)  — target accepts a pending request
 *   rejectFollowRequest(requesterId)  — target silently rejects a request
 *   cancelFollowRequest(targetId)     — requester cancels their own request
 *   removeFollower(followerId)        — account owner silently removes a follower
 *
 * Trigger:
 *   onAccountPrivacyChange — when isPrivate: true → false, auto-accept all
 *   pending follow requests for that account.
 *
 * See docs/privacy-model.md §2 (Follow System) and §5 (Remove Follower).
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

const db = admin.firestore();

// ─── acceptFollowRequest ─────────────────────────────────────────────────────

/**
 * Called by the private-account OWNER to accept a pending follow request.
 * Atomically: deletes the request doc, creates follow edges, increments counters.
 */
export const acceptFollowRequest = onCall({ region: "us-east1" }, async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    if (!request.app) {
        throw new HttpsError("failed-precondition", "App Check required.");
    }

    const targetId = request.auth.uid; // caller is the account owner
    const requesterId = (request.data as any)?.requesterId;

    if (typeof requesterId !== "string" || requesterId.trim() === "") {
        throw new HttpsError("invalid-argument", "requesterId must be non-empty.");
    }
    if (requesterId === targetId) {
        throw new HttpsError("invalid-argument", "Cannot accept a self-follow request.");
    }

    const requestRef = db
        .collection("users")
        .doc(targetId)
        .collection("followRequests")
        .doc(requesterId);

    const requestDoc = await requestRef.get();
    if (!requestDoc.exists || requestDoc.data()?.status !== "pending") {
        // Idempotent: request may have already been accepted or cancelled
        return { success: true, alreadyProcessed: true };
    }

    const indexId = `${requesterId}_${targetId}`;
    const now = admin.firestore.FieldValue.serverTimestamp();

    const batch = db.batch();

    // Delete request doc
    batch.delete(requestRef);

    // Create follow edges (atomic with request deletion)
    batch.set(db.collection("follows").doc(indexId), {
        followerId: requesterId,
        followingId: targetId,
        createdAt: now,
    }, { merge: true });
    batch.set(db.collection("follows_index").doc(indexId), {
        followerId: requesterId,
        followingId: targetId,
        createdAt: now,
    }, { merge: true });

    // Counter increments
    batch.update(db.collection("users").doc(requesterId), {
        followingCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
    });
    batch.update(db.collection("users").doc(targetId), {
        followersCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
    });

    await batch.commit();

    logger.info(`[acceptFollowRequest] ${requesterId} now follows ${targetId}`);
    return { success: true };
});

// ─── rejectFollowRequest ─────────────────────────────────────────────────────

/**
 * Called by the private-account OWNER to reject a pending follow request.
 * Silent: no notification to the requester. Requester can re-request later.
 */
export const rejectFollowRequest = onCall({ region: "us-east1" }, async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    if (!request.app) {
        throw new HttpsError("failed-precondition", "App Check required.");
    }

    const targetId = request.auth.uid;
    const requesterId = (request.data as any)?.requesterId;

    if (typeof requesterId !== "string" || requesterId.trim() === "") {
        throw new HttpsError("invalid-argument", "requesterId must be non-empty.");
    }

    const requestRef = db
        .collection("users")
        .doc(targetId)
        .collection("followRequests")
        .doc(requesterId);

    // Idempotent delete — no error if already gone
    await requestRef.delete();

    logger.info(`[rejectFollowRequest] ${targetId} rejected request from ${requesterId}`);
    return { success: true };
});

// ─── cancelFollowRequest ─────────────────────────────────────────────────────

/**
 * Called by the REQUESTER to cancel their own pending follow request.
 * Deletes the request doc from the target's followRequests subcollection.
 */
export const cancelFollowRequest = onCall({ region: "us-east1" }, async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    if (!request.app) {
        throw new HttpsError("failed-precondition", "App Check required.");
    }

    const requesterId = request.auth.uid;
    const targetId = (request.data as any)?.targetId;

    if (typeof targetId !== "string" || targetId.trim() === "") {
        throw new HttpsError("invalid-argument", "targetId must be non-empty.");
    }

    const requestRef = db
        .collection("users")
        .doc(targetId)
        .collection("followRequests")
        .doc(requesterId);

    await requestRef.delete();

    logger.info(`[cancelFollowRequest] ${requesterId} cancelled request to ${targetId}`);
    return { success: true };
});

// ─── removeFollower ───────────────────────────────────────────────────────────

/**
 * Called by an ACCOUNT OWNER to silently remove a follower.
 * The removed follower is not notified. They revert to non-follower state
 * and may re-follow (or re-request if the account is private).
 *
 * See docs/privacy-model.md §5 (Remove Follower / Soft Block).
 */
export const removeFollower = onCall({ region: "us-east1" }, async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    if (!request.app) {
        throw new HttpsError("failed-precondition", "App Check required.");
    }

    const targetId = request.auth.uid; // caller is the account being followed
    const followerId = (request.data as any)?.followerId;

    if (typeof followerId !== "string" || followerId.trim() === "") {
        throw new HttpsError("invalid-argument", "followerId must be non-empty.");
    }
    if (followerId === targetId) {
        throw new HttpsError("invalid-argument", "Cannot remove yourself.");
    }

    const indexId = `${followerId}_${targetId}`;
    const now = admin.firestore.FieldValue.serverTimestamp();

    const batch = db.batch();

    // Delete follow edges (idempotent)
    batch.delete(db.collection("follows").doc(indexId));
    batch.delete(db.collection("follows_index").doc(indexId));

    // Counter decrements
    batch.update(db.collection("users").doc(followerId), {
        followingCount: admin.firestore.FieldValue.increment(-1),
        updatedAt: now,
    });
    batch.update(db.collection("users").doc(targetId), {
        followersCount: admin.firestore.FieldValue.increment(-1),
        updatedAt: now,
    });

    await batch.commit();

    logger.info(`[removeFollower] ${targetId} removed follower ${followerId} (silent)`);
    return { success: true };
});

// ─── onAccountPrivacyChange ───────────────────────────────────────────────────

const AUTO_ACCEPT_BATCH_SIZE = 400;

/**
 * Trigger: when an account switches from private (isPrivate: true) to public
 * (isPrivate: false), auto-accept all pending follow requests.
 *
 * See docs/privacy-model.md §2: "Private→Public switch: all pending requests
 * auto-accepted (CF `onAccountPrivacyChange`)."
 *
 * When an account switches FROM public TO private, existing followers are
 * retained (Instagram behavior). All new follow attempts via `createFollow`
 * will create requests instead of edges.
 */
export const onAccountPrivacyChange = onDocumentUpdated(
    { document: "users/{uid}", region: "us-east1" },
    async (event) => {
        const before = event.data?.before.data();
        const after = event.data?.after.data();

        if (!before || !after) return;

        const wasPrivate = before.isPrivate === true;
        const isNowPublic = after.isPrivate !== true; // undefined or false = public

        // Only process private → public transitions
        if (!wasPrivate || !isNowPublic) return;

        const uid = event.params.uid;
        logger.info(`[onAccountPrivacyChange] ${uid} went private→public, auto-accepting pending requests`);

        let processedCount = 0;
        let lastDoc: admin.firestore.QueryDocumentSnapshot | null = null;

        while (true) {
            let query: admin.firestore.Query = db
                .collection("users")
                .doc(uid)
                .collection("followRequests")
                .where("status", "==", "pending")
                .limit(AUTO_ACCEPT_BATCH_SIZE);

            if (lastDoc) {
                query = query.startAfter(lastDoc);
            }

            const snap = await query.get();
            if (snap.empty) break;

            lastDoc = snap.docs[snap.docs.length - 1];

            const now = admin.firestore.FieldValue.serverTimestamp();
            const batch = db.batch();

            for (const requestDoc of snap.docs) {
                const requesterId = requestDoc.data().requesterId as string;
                if (!requesterId) continue;

                const indexId = `${requesterId}_${uid}`;

                // Delete request doc
                batch.delete(requestDoc.ref);

                // Create follow edges
                batch.set(db.collection("follows").doc(indexId), {
                    followerId: requesterId,
                    followingId: uid,
                    createdAt: now,
                }, { merge: true });
                batch.set(db.collection("follows_index").doc(indexId), {
                    followerId: requesterId,
                    followingId: uid,
                    createdAt: now,
                }, { merge: true });

                // Counter increments (batched — reconciliation corrects any drift)
                batch.update(db.collection("users").doc(requesterId), {
                    followingCount: admin.firestore.FieldValue.increment(1),
                    updatedAt: now,
                });

                processedCount++;
            }

            // Increment follower count once for the whole batch
            batch.update(db.collection("users").doc(uid), {
                followersCount: admin.firestore.FieldValue.increment(snap.size),
                updatedAt: now,
            });

            await batch.commit();
        }

        logger.info(
            `[onAccountPrivacyChange] Auto-accepted ${processedCount} pending requests for ${uid}`
        );
    }
);
