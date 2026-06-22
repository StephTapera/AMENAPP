"use strict";
/**
 * notifications/grouping.ts
 *
 * Server-side notification grouping (Threads-style multi-actor aggregation).
 * Merges notifications of the same type targeting the same entity within
 * the aggregation window into a single grouped notification doc.
 *
 * Example: 5 users amen the same post → 1 notification:
 *   "Alice, Bob, and 3 others said Amen to your post"
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
exports.applyGrouping = applyGrouping;
const admin = __importStar(require("firebase-admin"));
const types_1 = require("./types");
const helpers_1 = require("./helpers");
const db = admin.firestore();
// ─── Types That Support Grouping ────────────────────────────────────
/**
 * Only certain notification types are grouped.
 * Comments, replies, and mentions are kept individual for context.
 */
const GROUPABLE_TYPES = new Set([
    "amen",
    "follow",
    "repost",
    "prayer_supported",
]);
// ─── Apply Grouping ─────────────────────────────────────────────────
/**
 * Checks if the candidate can be merged into an existing group.
 * If yes, updates the existing doc. If no, creates a new one.
 *
 * Uses Firestore transactions for safe concurrent writes.
 */
async function applyGrouping(candidate) {
    const targetEntityId = candidate.postId ||
        candidate.commentId ||
        candidate.conversationId ||
        candidate.prayerId ||
        candidate.noteId ||
        candidate.recipientId;
    const groupingKey = (0, helpers_1.buildGroupingKey)(candidate.type, targetEntityId);
    // Only attempt grouping for supported types
    if (!GROUPABLE_TYPES.has(candidate.type)) {
        return createNewNotification(candidate, groupingKey);
    }
    // Look for an existing open group within the aggregation window
    const windowStart = admin.firestore.Timestamp.fromMillis(Date.now() - types_1.GROUPING_WINDOW_MS);
    const existingGroupQuery = await db
        .collection("users")
        .doc(candidate.recipientId)
        .collection("notifications")
        .where("groupId", "==", groupingKey)
        .where("createdAt", ">=", windowStart)
        .orderBy("createdAt", "desc")
        .limit(1)
        .get();
    if (!existingGroupQuery.empty) {
        const existingDoc = existingGroupQuery.docs[0];
        return mergeIntoGroup(candidate, existingDoc);
    }
    return createNewNotification(candidate, groupingKey);
}
// ─── Create New Notification ────────────────────────────────────────
async function createNewNotification(candidate, groupingKey) {
    const targetEntityId = candidate.postId ||
        candidate.commentId ||
        candidate.conversationId ||
        candidate.prayerId ||
        candidate.noteId ||
        candidate.recipientId;
    const idempotencyKey = (0, helpers_1.buildIdempotencyKey)(candidate.type, candidate.actorId, targetEntityId);
    const actor = {
        id: candidate.actorId,
        name: candidate.actorName,
        username: candidate.actorUsername,
        profileImageURL: candidate.actorProfileImageURL,
    };
    const notificationDoc = {
        // Core identity
        userId: candidate.recipientId,
        type: candidate.type,
        idempotencyKey,
        schemaVersion: types_1.SCHEMA_VERSION,
        // Actor info
        actorId: candidate.actorId,
        actorName: candidate.actorName,
        actorUsername: candidate.actorUsername,
        actorProfileImageURL: candidate.actorProfileImageURL,
        // Target entity IDs
        postId: candidate.postId,
        commentId: candidate.commentId,
        parentCommentId: candidate.parentCommentId,
        conversationId: candidate.conversationId,
        prayerId: candidate.prayerId,
        noteId: candidate.noteId,
        commentText: candidate.commentText,
        // Grouping
        groupId: GROUPABLE_TYPES.has(candidate.type) ? groupingKey : null,
        actors: [actor],
        actorCount: 1,
        // State machine
        read: false,
        seenAt: null,
        openedAt: null,
        dismissedAt: null,
        // Routing
        targetRouteType: candidate.targetRouteType,
        routePayload: candidate.routePayload,
        fallbackRouteType: candidate.fallbackRouteType,
        fallbackRoutePayload: candidate.fallbackRoutePayload,
        deepLinkVersion: types_1.DEEP_LINK_VERSION,
        // Smart notification metadata
        priority: null,
        invalidTarget: false,
        // Push delivery
        pushDelivered: false,
        pushDeliveredAt: null,
        // Timestamps
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: null,
    };
    const docRef = await db
        .collection("users")
        .doc(candidate.recipientId)
        .collection("notifications")
        .add(notificationDoc);
    return {
        notificationId: docRef.id,
        isNewNotification: true,
        notificationDoc,
    };
}
// ─── Merge Into Existing Group ──────────────────────────────────────
async function mergeIntoGroup(candidate, existingDoc) {
    const existingData = existingDoc.data();
    const newActor = {
        id: candidate.actorId,
        name: candidate.actorName,
        username: candidate.actorUsername,
        profileImageURL: candidate.actorProfileImageURL,
    };
    // Check if this actor is already in the group
    const existingActors = existingData.actors || [];
    const alreadyInGroup = existingActors.some((a) => a.id === candidate.actorId);
    if (alreadyInGroup) {
        // Actor already in group — don't duplicate, just return existing
        return {
            notificationId: existingDoc.id,
            isNewNotification: false,
            notificationDoc: existingData,
        };
    }
    // Build updated actors list (keep max MAX_INLINE_ACTORS most recent)
    const updatedActors = [newActor, ...existingActors].slice(0, types_1.MAX_INLINE_ACTORS);
    const newActorCount = (existingData.actorCount || 1) + 1;
    // Use transaction for safe concurrent writes
    await db.runTransaction(async (transaction) => {
        const freshDoc = await transaction.get(existingDoc.ref);
        if (!freshDoc.exists)
            return;
        const freshData = freshDoc.data();
        if (!freshData)
            return;
        // Re-check actor count inside transaction
        const freshActors = freshData.actors || [];
        const freshAlreadyInGroup = freshActors.some((a) => a.id === candidate.actorId);
        if (freshAlreadyInGroup)
            return;
        const transactionActors = [newActor, ...freshActors].slice(0, types_1.MAX_INLINE_ACTORS);
        const transactionCount = (freshData.actorCount || 1) + 1;
        transaction.update(existingDoc.ref, {
            // Update to latest actor as primary
            actorId: candidate.actorId,
            actorName: candidate.actorName,
            actorUsername: candidate.actorUsername,
            actorProfileImageURL: candidate.actorProfileImageURL,
            // Update group
            actors: transactionActors,
            actorCount: transactionCount,
            // Reset read state (new activity in group)
            read: false,
            seenAt: null,
            // Update timestamp
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    });
    // Return the updated doc shape
    const updatedDoc = {
        ...existingData,
        actorId: candidate.actorId,
        actorName: candidate.actorName,
        actorUsername: candidate.actorUsername,
        actorProfileImageURL: candidate.actorProfileImageURL,
        actors: updatedActors,
        actorCount: newActorCount,
        read: false,
        seenAt: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    return {
        notificationId: existingDoc.id,
        isNewNotification: false,
        notificationDoc: updatedDoc,
    };
}
//# sourceMappingURL=grouping.js.map