"use strict";
/**
 * notifications/invalidation.ts
 *
 * Firestore triggers that invalidate notifications when the
 * referenced content is deleted or when users block each other.
 * Marks affected notifications as `invalidTarget: true` so the
 * client can show a "this content is no longer available" message
 * instead of navigating to a broken route.
 *
 * Uses gen2 Firestore trigger syntax to coexist with other gen2
 * triggers in the same deployment without CPU-setting conflicts.
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
exports.onUserDeactivated = exports.onUserBlockedV2 = exports.onCommentDeleted = exports.onPostFlagged = exports.onPostDeleted = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const v2_1 = require("firebase-functions/v2");
const admin = __importStar(require("firebase-admin"));
const db = admin.firestore();
// ─── Post Deleted ───────────────────────────────────────────────────
/**
 * Trigger: posts/{postId} — onDelete
 * Marks all notifications referencing this post as invalidTarget.
 */
exports.onPostDeleted = (0, firestore_1.onDocumentDeleted)("posts/{postId}", async (event) => {
    const postId = event.params.postId;
    const snap = event.data;
    if (!snap)
        return;
    const postData = snap.data();
    if (!postData)
        return;
    const authorId = postData.userId || postData.authorId;
    await invalidateNotificationsForPost(postId, authorId);
});
/**
 * Trigger: posts/{postId} — onUpdate
 * If the post is flagged for review or removed, invalidate notifications.
 */
exports.onPostFlagged = (0, firestore_1.onDocumentUpdated)("posts/{postId}", async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return;
    const postId = event.params.postId;
    const authorId = after.userId || after.authorId;
    const wasVisible = !before.removed && !before.flaggedForReview;
    const isNowHidden = after.removed === true || after.flaggedForReview === true;
    if (wasVisible && isNowHidden) {
        await invalidateNotificationsForPost(postId, authorId);
    }
});
async function invalidateNotificationsForPost(postId, authorId) {
    if (authorId) {
        const authorNotifs = await db
            .collection("users")
            .doc(authorId)
            .collection("notifications")
            .where("postId", "==", postId)
            .limit(100)
            .get();
        if (!authorNotifs.empty) {
            const batch = db.batch();
            for (const doc of authorNotifs.docs) {
                batch.update(doc.ref, { invalidTarget: true });
            }
            await batch.commit();
        }
    }
    const topLevelNotifs = await db
        .collection("notifications")
        .where("postId", "==", postId)
        .limit(100)
        .get();
    if (!topLevelNotifs.empty) {
        const batch = db.batch();
        for (const doc of topLevelNotifs.docs) {
            batch.update(doc.ref, { invalidTarget: true });
        }
        await batch.commit();
    }
}
// ─── Comment Deleted ────────────────────────────────────────────────
/**
 * Trigger: comments/{commentId} — onDelete
 * Marks all notifications referencing this comment as invalidTarget.
 */
exports.onCommentDeleted = (0, firestore_1.onDocumentDeleted)("comments/{commentId}", async (event) => {
    const commentId = event.params.commentId;
    const snap = event.data;
    if (!snap)
        return;
    const commentData = snap.data();
    if (!commentData)
        return;
    const postId = commentData.postId;
    const authorId = commentData.userId || commentData.authorId;
    if (authorId) {
        const authorNotifs = await db
            .collection("users")
            .doc(authorId)
            .collection("notifications")
            .where("commentId", "==", commentId)
            .limit(50)
            .get();
        if (!authorNotifs.empty) {
            const batch = db.batch();
            for (const doc of authorNotifs.docs) {
                batch.update(doc.ref, { invalidTarget: true });
            }
            await batch.commit();
        }
    }
    if (postId) {
        const postDoc = await db.collection("posts").doc(postId).get();
        const postAuthorId = postDoc.data()?.userId || postDoc.data()?.authorId;
        if (postAuthorId) {
            const replyNotifs = await db
                .collection("users")
                .doc(postAuthorId)
                .collection("notifications")
                .where("parentCommentId", "==", commentId)
                .limit(50)
                .get();
            if (!replyNotifs.empty) {
                const batch = db.batch();
                for (const doc of replyNotifs.docs) {
                    batch.update(doc.ref, { invalidTarget: true });
                }
                await batch.commit();
            }
        }
    }
});
// ─── User Blocked ───────────────────────────────────────────────────
/**
 * Trigger: users/{userId}/blockedUsers/{blockedId} — onCreate
 * When a user blocks another, suppress any pending notifications
 * between the two users.
 */
exports.onUserBlockedV2 = (0, firestore_1.onDocumentCreated)("users/{userId}/blockedUsers/{blockedId}", async (event) => {
    const { userId, blockedId } = event.params;
    await invalidateNotificationsBetweenUsers(userId, blockedId);
    await invalidateNotificationsBetweenUsers(blockedId, userId);
});
async function invalidateNotificationsBetweenUsers(recipientId, actorId) {
    const notifs = await db
        .collection("users")
        .doc(recipientId)
        .collection("notifications")
        .where("actorId", "==", actorId)
        .limit(100)
        .get();
    if (notifs.empty)
        return;
    const batch = db.batch();
    for (const doc of notifs.docs) {
        batch.update(doc.ref, {
            invalidTarget: true,
            read: true,
        });
    }
    await batch.commit();
    const stateRef = db
        .collection("users")
        .doc(recipientId)
        .collection("notificationState")
        .doc("inbox");
    const unseenSnap = await db
        .collection("users")
        .doc(recipientId)
        .collection("notifications")
        .where("seenAt", "==", null)
        .where("dismissedAt", "==", null)
        .limit(500)
        .get();
    await stateRef.set({
        unseenCount: unseenSnap.size,
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}
// ─── User Account Deactivated ───────────────────────────────────────
/**
 * Trigger: users/{userId} — onUpdate
 * When a user deactivates their account, invalidate their
 * outgoing notifications (notifications they sent to others).
 */
exports.onUserDeactivated = (0, firestore_1.onDocumentUpdated)("users/{userId}", async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return;
    const userId = event.params.userId;
    const wasActive = !before.deactivated && !before.suspended;
    const isNowInactive = after.deactivated === true || after.suspended === true;
    if (!wasActive || !isNowInactive)
        return;
    const outgoingNotifs = await db
        .collection("notifications")
        .where("actorId", "==", userId)
        .limit(200)
        .get();
    if (outgoingNotifs.empty)
        return;
    const batch = db.batch();
    for (const doc of outgoingNotifs.docs) {
        batch.update(doc.ref, { invalidTarget: true });
    }
    await batch.commit();
    v2_1.logger.info(`User ${userId} deactivated: invalidated ${outgoingNotifs.size} outgoing notifications`);
});
//# sourceMappingURL=invalidation.js.map