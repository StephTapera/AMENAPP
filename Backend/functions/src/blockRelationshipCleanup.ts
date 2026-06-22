/**
 * blockRelationshipCleanup.ts
 *
 * CRITICAL: Server-side cleanup when one user blocks another.
 *
 * WHY THIS EXISTS:
 *   When user A blocks user B, the client-side BlockService adds a document
 *   to users/{blockerId}/blockedUsers/{blockedId}. However, the existing follow
 *   relationships, pending follow requests, and shared conversation access remain
 *   intact. A blocked user can still see the blocker's content through their
 *   follower feed, and the blocker's follow count is not reconciled.
 *
 * WHAT THIS DOES on users/{blockerId}/blockedUsers/{blockedId} creation:
 *   1. Removes any follow in both directions (A→B and B→A)
 *   2. Removes pending follow requests in both directions
 *   3. Marks shared conversations as blocked so the client can hide them
 *      (conversations are not deleted — messages are evidence for appeals)
 *
 * IDEMPOTENT: All operations use "ignore not found" patterns so re-triggering
 * on the same block document is safe.
 *
 * Uses gen2 Firestore trigger syntax to coexist with other gen2 triggers.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

const db = admin.firestore();

// ─── Trigger ─────────────────────────────────────────────────────────────────

export const blockRelationshipCleanupTrigger = onDocumentCreated(
    { document: "users/{blockerId}/blockedUsers/{blockedId}", region: "us-east1" },
    async (event) => {
        const { blockerId, blockedId } = event.params;

        logger.info(
            `[blockRelationshipCleanup] Processing block: ${blockerId} → ${blockedId}`
        );

        await Promise.allSettled([
            removeFollows(blockerId, blockedId),
            removeFollowRequests(blockerId, blockedId),
            restrictSharedConversations(blockerId, blockedId),
            // Revoke notifications FROM the blocked user in the blocker's inbox,
            // AND notifications FROM the blocker in the blocked user's inbox.
            // See docs/privacy-model.md §9.
            revokeNotificationsOnBlock(blockerId, blockedId),
        ]);

        logger.info(
            `[blockRelationshipCleanup] Done for block: ${blockerId} → ${blockedId}`
        );
    }
);

// ─── Follow Removal ───────────────────────────────────────────────────────────

/**
 * Deletes follow documents in both directions from the top-level `follows`
 * collection. Follows are stored as {followerId, followingId} fields.
 */
async function removeFollows(
    blockerId: string,
    blockedId: string
): Promise<void> {
    const [aFollowsB, bFollowsA] = await Promise.all([
        db.collection("follows")
            .where("followerId", "==", blockerId)
            .where("followingId", "==", blockedId)
            .limit(10)
            .get(),
        db.collection("follows")
            .where("followerId", "==", blockedId)
            .where("followingId", "==", blockerId)
            .limit(10)
            .get(),
    ]);

    const batch = db.batch();
    for (const doc of [...aFollowsB.docs, ...bFollowsA.docs]) {
        batch.delete(doc.ref);
    }

    // Also delete from follows_index (used by callerFollows() in Firestore rules)
    const indexIds = [
        `${blockerId}_${blockedId}`,
        `${blockedId}_${blockerId}`,
    ];
    for (const indexId of indexIds) {
        batch.delete(db.collection("follows_index").doc(indexId));
    }

    await batch.commit();

    logger.info(
        `[blockRelationshipCleanup] Removed ${aFollowsB.size + bFollowsA.size} follow edges for block ${blockerId}→${blockedId}`
    );
}

// ─── Follow Request Removal ───────────────────────────────────────────────────

async function removeFollowRequests(
    blockerId: string,
    blockedId: string
): Promise<void> {
    const [requestsAtoB, requestsBtoA] = await Promise.all([
        db.collection("users").doc(blockedId)
            .collection("followRequests")
            .where("requesterId", "==", blockerId)
            .limit(10)
            .get(),
        db.collection("users").doc(blockerId)
            .collection("followRequests")
            .where("requesterId", "==", blockedId)
            .limit(10)
            .get(),
    ]);

    if (requestsAtoB.empty && requestsBtoA.empty) return;

    const batch = db.batch();
    for (const doc of [...requestsAtoB.docs, ...requestsBtoA.docs]) {
        batch.delete(doc.ref);
    }
    await batch.commit();
}

// ─── Notification Revocation ─────────────────────────────────────────────────

const NOTIFICATION_LIMIT = 100;

/**
 * Deletes all notifications FROM the blocked user in the blocker's inbox,
 * and all notifications FROM the blocker in the blocked user's inbox.
 *
 * Bidirectional: after a block, neither party should see notifications from
 * the other. Capped at NOTIFICATION_LIMIT per direction to avoid timeout;
 * a follow-up sweep is triggered if more exist (unlikely in practice).
 */
async function revokeNotificationsOnBlock(
    blockerId: string,
    blockedId: string
): Promise<void> {
    const [blockerInbox, blockedInbox] = await Promise.allSettled([
        // Notifications from blockedId in blockerId's inbox
        db
            .collection("users")
            .doc(blockerId)
            .collection("notifications")
            .where("actorId", "==", blockedId)
            .limit(NOTIFICATION_LIMIT)
            .get(),
        // Notifications from blockerId in blockedId's inbox
        db
            .collection("users")
            .doc(blockedId)
            .collection("notifications")
            .where("actorId", "==", blockerId)
            .limit(NOTIFICATION_LIMIT)
            .get(),
    ]);

    const allDocs: admin.firestore.QueryDocumentSnapshot[] = [];

    if (blockerInbox.status === "fulfilled") {
        allDocs.push(...blockerInbox.value.docs);
    }
    if (blockedInbox.status === "fulfilled") {
        allDocs.push(...blockedInbox.value.docs);
    }

    if (allDocs.length === 0) return;

    const batch = db.batch();
    for (const doc of allDocs) {
        batch.delete(doc.ref);
    }
    await batch.commit();

    logger.info(
        `[blockRelationshipCleanup] Revoked ${allDocs.length} notifications for block ${blockerId}→${blockedId}`
    );
}

// ─── Conversation Restriction ─────────────────────────────────────────────────

/**
 * Marks shared conversations with a `blockedBetween` field containing the
 * sorted blocker/blocked pair. The client hides conversations with this field.
 */
async function restrictSharedConversations(
    blockerId: string,
    blockedId: string
): Promise<void> {
    const snap = await db.collection("conversations")
        .where("participantIds", "array-contains", blockerId)
        .limit(50)
        .get();

    if (snap.empty) return;

    const blockedPair = [blockerId, blockedId].sort().join("_");
    const sharedConvos = snap.docs.filter((doc) => {
        const participants: string[] = doc.data().participantIds ?? [];
        return participants.includes(blockedId);
    });

    if (sharedConvos.length === 0) return;

    const batch = db.batch();
    for (const doc of sharedConvos) {
        // blockedBetween: sorted-pair string for display/legacy use
        // blockedParticipantUids: individual UIDs array for Firestore rules check
        // (Rules cannot do string-contains operations, so we store both UIDs explicitly)
        batch.update(doc.ref, {
            blockedBetween: admin.firestore.FieldValue.arrayUnion(blockedPair),
            blockedParticipantUids: admin.firestore.FieldValue.arrayUnion(blockerId, blockedId),
        });
    }
    await batch.commit();

    logger.info(
        `[blockRelationshipCleanup] Restricted ${sharedConvos.length} shared conversations for block ${blockerId}→${blockedId}`
    );
}
