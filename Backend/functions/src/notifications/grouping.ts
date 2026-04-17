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

import * as admin from "firebase-admin";
import {
    NotificationCandidate,
    NotificationDocument,
    NotificationActor,
    SCHEMA_VERSION,
    DEEP_LINK_VERSION,
    GROUPING_WINDOW_MS,
    MAX_INLINE_ACTORS,
} from "./types";
import { buildIdempotencyKey, buildGroupingKey } from "./helpers";

const db = admin.firestore();

// ─── Grouping Result ────────────────────────────────────────────────

export interface GroupingResult {
    notificationId: string;
    isNewNotification: boolean;
    notificationDoc: NotificationDocument;
}

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
export async function applyGrouping(
    candidate: NotificationCandidate
): Promise<GroupingResult> {
    const targetEntityId =
        candidate.postId ||
        candidate.commentId ||
        candidate.conversationId ||
        candidate.prayerId ||
        candidate.noteId ||
        candidate.recipientId;

    const groupingKey = buildGroupingKey(candidate.type, targetEntityId);

    // Only attempt grouping for supported types
    if (!GROUPABLE_TYPES.has(candidate.type)) {
        return createNewNotification(candidate, groupingKey);
    }

    // Look for an existing open group within the aggregation window
    const windowStart = admin.firestore.Timestamp.fromMillis(
        Date.now() - GROUPING_WINDOW_MS
    );

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

async function createNewNotification(
    candidate: NotificationCandidate,
    groupingKey: string
): Promise<GroupingResult> {
    const targetEntityId =
        candidate.postId ||
        candidate.commentId ||
        candidate.conversationId ||
        candidate.prayerId ||
        candidate.noteId ||
        candidate.recipientId;

    const idempotencyKey = buildIdempotencyKey(
        candidate.type,
        candidate.actorId,
        targetEntityId
    );

    const actor: NotificationActor = {
        id: candidate.actorId,
        name: candidate.actorName,
        username: candidate.actorUsername,
        profileImageURL: candidate.actorProfileImageURL,
    };

    const notificationDoc: NotificationDocument = {
        // Core identity
        userId: candidate.recipientId,
        type: candidate.type,
        idempotencyKey,
        schemaVersion: SCHEMA_VERSION,

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
        deepLinkVersion: DEEP_LINK_VERSION,

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

async function mergeIntoGroup(
    candidate: NotificationCandidate,
    existingDoc: FirebaseFirestore.QueryDocumentSnapshot
): Promise<GroupingResult> {
    const existingData = existingDoc.data();

    const newActor: NotificationActor = {
        id: candidate.actorId,
        name: candidate.actorName,
        username: candidate.actorUsername,
        profileImageURL: candidate.actorProfileImageURL,
    };

    // Check if this actor is already in the group
    const existingActors: NotificationActor[] = existingData.actors || [];
    const alreadyInGroup = existingActors.some(
        (a) => a.id === candidate.actorId
    );

    if (alreadyInGroup) {
        // Actor already in group — don't duplicate, just return existing
        return {
            notificationId: existingDoc.id,
            isNewNotification: false,
            notificationDoc: existingData as NotificationDocument,
        };
    }

    // Build updated actors list (keep max MAX_INLINE_ACTORS most recent)
    const updatedActors = [newActor, ...existingActors].slice(
        0,
        MAX_INLINE_ACTORS
    );
    const newActorCount = (existingData.actorCount || 1) + 1;

    // Use transaction for safe concurrent writes
    await db.runTransaction(async (transaction) => {
        const freshDoc = await transaction.get(existingDoc.ref);
        if (!freshDoc.exists) return;

        const freshData = freshDoc.data();
        if (!freshData) return;

        // Re-check actor count inside transaction
        const freshActors: NotificationActor[] = freshData.actors || [];
        const freshAlreadyInGroup = freshActors.some(
            (a) => a.id === candidate.actorId
        );
        if (freshAlreadyInGroup) return;

        const transactionActors = [newActor, ...freshActors].slice(
            0,
            MAX_INLINE_ACTORS
        );
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
    const updatedDoc: NotificationDocument = {
        ...(existingData as NotificationDocument),
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
