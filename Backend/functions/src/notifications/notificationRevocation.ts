/**
 * notificationRevocation.ts
 *
 * WHY THIS EXISTS:
 *   When a comment is deleted or content becomes inaccessible, in-app
 *   notification records referencing it must be rendered inert or removed.
 *   Without this, a user can tap an old notification and either see a
 *   "content unavailable" crash or (worse) still access cached content.
 *
 *   Handles:
 *   A. Comment soft-delete → revoke notification from post owner's inbox
 *   B. Post soft-delete → revoke all comment/reaction notifications for that post
 *
 *   Block-triggered notification revocation is in blockRelationshipCleanup.ts.
 *
 * See docs/privacy-model.md §9 (Notification Revocation).
 */

import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

const db = admin.firestore();

const NOTIFICATION_BATCH_LIMIT = 100;

// ─── A. Comment Soft-Delete Revocation ───────────────────────────────────────

/**
 * When a comment is soft-deleted (isDeleted: false → true), revoke the
 * corresponding notification in the post owner's inbox.
 *
 * Only fires on isDeleted transitions (not on every comment update) to avoid
 * unnecessary Firestore reads.
 */
export const revokeNotificationsOnCommentDelete = onDocumentUpdated(
    "posts/{postId}/comments/{commentId}",
    async (event) => {
        const before = event.data?.before.data();
        const after = event.data?.after.data();

        // Only process isDeleted: false → true transitions
        if (!after?.isDeleted || before?.isDeleted === true) return;

        const { postId, commentId } = event.params;

        logger.info(
            `[revokeNotificationsOnCommentDelete] Comment ${commentId} on post ${postId} soft-deleted`
        );

        // Fetch the post to get its author (who received the comment notification)
        const postSnap = await db.collection("posts").doc(postId).get();
        if (!postSnap.exists) {
            logger.warn(
                `[revokeNotificationsOnCommentDelete] Parent post ${postId} not found`
            );
            return;
        }

        const postAuthorId = postSnap.data()?.authorId ?? "";
        if (!postAuthorId) return;

        // Delete any notifications in the post author's inbox that reference this comment
        const byCommentId = await db
            .collection("users")
            .doc(postAuthorId)
            .collection("notifications")
            .where("commentId", "==", commentId)
            .limit(NOTIFICATION_BATCH_LIMIT)
            .get();

        // Also delete by sourceRef = commentId (some notification types store it differently)
        const bySourceRef = await db
            .collection("users")
            .doc(postAuthorId)
            .collection("notifications")
            .where("sourceRef", "==", commentId)
            .limit(NOTIFICATION_BATCH_LIMIT)
            .get();

        const allDocs = [
            ...byCommentId.docs,
            ...bySourceRef.docs.filter(
                (d) => !byCommentId.docs.some((x) => x.id === d.id)
            ),
        ];

        if (allDocs.length === 0) return;

        const batch = db.batch();
        for (const doc of allDocs) {
            batch.delete(doc.ref);
        }
        await batch.commit();

        logger.info(
            `[revokeNotificationsOnCommentDelete] Revoked ${allDocs.length} notifications ` +
            `for deleted comment ${commentId} (postAuthor=${postAuthorId})`
        );
    }
);

// ─── B. Post Soft-Delete Revocation ──────────────────────────────────────────

/**
 * When a post is soft-deleted (isDeleted: false → true), revoke all comment
 * and reaction notifications that reference it in the post author's inbox.
 *
 * This prevents deep-link taps from leading to "post unavailable" states.
 */
export const revokeNotificationsOnPostDelete = onDocumentUpdated(
    "posts/{postId}",
    async (event) => {
        const before = event.data?.before.data();
        const after = event.data?.after.data();

        // Only process isDeleted: false → true transitions
        if (!after?.isDeleted || before?.isDeleted === true) return;

        const { postId } = event.params;
        const postAuthorId = after.authorId ?? after.userId ?? "";

        if (!postAuthorId) return;

        logger.info(
            `[revokeNotificationsOnPostDelete] Post ${postId} soft-deleted, revoking notifications`
        );

        // Delete notifications in the post author's inbox referencing this post
        const notifSnap = await db
            .collection("users")
            .doc(postAuthorId)
            .collection("notifications")
            .where("postId", "==", postId)
            .limit(NOTIFICATION_BATCH_LIMIT)
            .get();

        if (notifSnap.empty) return;

        const batch = db.batch();
        for (const doc of notifSnap.docs) {
            batch.delete(doc.ref);
        }
        await batch.commit();

        logger.info(
            `[revokeNotificationsOnPostDelete] Revoked ${notifSnap.size} notifications ` +
            `for deleted post ${postId}`
        );
    }
);
