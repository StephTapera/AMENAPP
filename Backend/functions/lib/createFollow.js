"use strict";
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
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.createUnfollow = exports.createFollow = void 0;
const functions = __importStar(require("firebase-functions"));
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const db = admin.firestore();
// ─── Private Account Helper ───────────────────────────────────────────────────
/** Returns the privacy state of a user account. */
async function getAccountState(uid) {
    const doc = await db.collection("users").doc(uid).get();
    return {
        isPrivate: doc.data()?.isPrivate === true,
        ageTier: doc.data()?.ageTier ?? null,
    };
}
// ─── Rate Limiting ────────────────────────────────────────────────────────────
const HOURLY_FOLLOW_LIMIT = 200;
const HOUR_MS = 3600000;
/**
 * Throws resource-exhausted if followerId has exceeded HOURLY_FOLLOW_LIMIT
 * follow operations in the current clock hour.
 *
 * Uses a Firestore counter doc with a 2-hour TTL for automatic cleanup.
 * The transaction makes the check-and-increment atomic under concurrent calls.
 */
async function enforceFollowRateLimit(followerId) {
    const hourBucket = Math.floor(Date.now() / HOUR_MS);
    const rateLimitRef = db
        .collection("_rateLimits")
        .doc(`follow_${followerId}_${hourBucket}`);
    await db.runTransaction(async (tx) => {
        const doc = await tx.get(rateLimitRef);
        const count = doc.exists ? (doc.data()?.count ?? 0) : 0;
        if (count >= HOURLY_FOLLOW_LIMIT) {
            throw new https_1.HttpsError("resource-exhausted", "Follow rate limit exceeded. Please slow down before following more people.");
        }
        tx.set(rateLimitRef, {
            count: count + 1,
            uid: followerId,
            bucket: hourBucket,
            // TTL for automatic cleanup (2 hours from bucket start)
            ttl: admin.firestore.Timestamp.fromMillis((hourBucket + 2) * HOUR_MS),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
}
exports.createFollow = (0, https_1.onCall)({ enforceAppCheck: true, region: "us-east1" }, async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    if (!context.auth) {
        throw new https_1.HttpsError("unauthenticated", "Must be signed in to follow a user.");
    }
    if (context.app == undefined) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const followerId = context.auth.uid;
    const followingId = data?.followingId;
    if (typeof followingId !== "string" || followingId.trim() === "") {
        throw new https_1.HttpsError("invalid-argument", "followingId must be a non-empty string.");
    }
    if (followerId === followingId) {
        throw new https_1.HttpsError("invalid-argument", "Cannot follow yourself.");
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
        getAccountState(followingId),
    ]);
    if (targetState.isPrivate) {
        // Check for an existing pending request (idempotent)
        const existingRequest = await db
            .collection("users")
            .doc(followingId)
            .collection("followRequests")
            .doc(followerId)
            .get();
        if (existingRequest.exists) {
            return { success: true, requestAlreadySent: true };
        }
        // Create the follow request doc. GUARDIAN: adult→minor requests are stored
        // with a guardian flag so the notification policy can route them appropriately.
        const isAdultToMinor = !callerState.ageTier?.startsWith("tier") &&
            (targetState.ageTier === "tierB" || targetState.ageTier === "tierC");
        await db
            .collection("users")
            .doc(followingId)
            .collection("followRequests")
            .doc(followerId)
            .set({
            requesterId: followerId,
            fromUserId: followerId, // iOS FollowRequest model compat
            targetId: followingId,
            toUserId: followingId, // iOS FollowRequest model compat
            status: "pending",
            guardianRouted: isAdultToMinor,
            createdAt: now,
        });
        // Server-side follow-request notification (deterministic ID prevents duplicates)
        await db
            .collection("users")
            .doc(followingId)
            .collection("notifications")
            .doc(`follow_req_${followerId}`)
            .set({
            type: "followRequest",
            actorId: followerId,
            isRead: false,
            createdAt: now,
        }, { merge: true });
        functions.logger.info(`[createFollow] Follow request: ${followerId} → ${followingId}` +
            (isAdultToMinor ? " [GUARDIAN]" : ""));
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
    batch.update(db.collection("users").doc(followingId), {
        followersCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
    });
    await batch.commit();
    functions.logger.info(`[createFollow] ${followerId} → ${followingId}`);
    return { success: true };
});
// ─── createUnfollow ───────────────────────────────────────────────────────────
exports.createUnfollow = (0, https_1.onCall)({ enforceAppCheck: true, region: "us-east1" }, async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    if (!context.auth) {
        throw new https_1.HttpsError("unauthenticated", "Must be signed in to unfollow a user.");
    }
    if (context.app == undefined) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const followerId = context.auth.uid;
    const followingId = data?.followingId;
    if (typeof followingId !== "string" || followingId.trim() === "") {
        throw new https_1.HttpsError("invalid-argument", "followingId must be a non-empty string.");
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
//# sourceMappingURL=createFollow.js.map