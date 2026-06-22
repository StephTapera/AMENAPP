"use strict";
/**
 * notifications/onSocialEvent.ts
 *
 * Firestore triggers for core social events that generate notifications.
 * Each trigger extracts event data, builds a notification candidate,
 * evaluates policies, applies grouping, writes to inbox, and dispatches push.
 *
 * Uses gen2 Firestore trigger syntax (firebase-functions/v2/firestore) so that
 * these triggers can coexist with gen2 onCall functions in the same deployment
 * without the gen1/gen2 CPU-setting conflict.
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
exports.onPostCreated = exports.onChurchNoteShared = exports.onPrayerAnswered = exports.onPrayerSupportCreated = exports.onRepostCreated = exports.onCommentCreated = exports.onAmenCreated = exports.onFollowEvent = void 0;
exports.processCandidate = processCandidate;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const types_1 = require("./types");
const helpers_1 = require("./helpers");
const policies_1 = require("./policies");
const grouping_1 = require("./grouping");
const sendPush_1 = require("./sendPush");
const counts_1 = require("./counts");
const db = admin.firestore();
// ─── Follow Event (merged trigger) ──────────────────────────────────
//
// 5.5 FIX: Previously two separate functions triggered on follows/{docId}
// onCreate — onFollowCreated (public accounts) and onFollowRequestAcceptedV2
// (private account accepted requests). Dual triggers on the same path create
// a race condition: a follow doc written with status:"accepted" for a PUBLIC
// account would pass onFollowCreated's isPrivate guard AND
// onFollowRequestAcceptedV2's status guard, sending duplicate notifications.
//
// This single function dispatches based on isPrivate + status, eliminating
// the race condition and making the routing logic explicit.
//
// NOTE: When deploying this change, manually delete the two old Cloud Function
// instances (onFollowCreated, onFollowRequestAcceptedV2) from the Firebase
// Console so they stop receiving triggers alongside this new function.
/**
 * Trigger: follows/{docId} — onCreate
 * Dispatches to the correct notification type based on account privacy:
 *   - Public account  → "follow" notification to followed user
 *   - Private account, status:"accepted" → "follow_request_accepted" to requester
 *   - Private account, other status → no notification (pending approval)
 */
exports.onFollowEvent = (0, firestore_1.onDocumentCreated)("follows/{docId}", async (event) => {
    const snap = event.data;
    if (!snap)
        return;
    const data = snap.data();
    if (!data)
        return;
    const { followerId, followedId, status } = data;
    if (!followerId || !followedId)
        return;
    const followedDoc = await db.collection("users").doc(followedId).get();
    const isPrivate = followedDoc.data()?.isPrivate === true;
    if (isPrivate) {
        // Private account: only notify when a follow request is accepted.
        if (status !== "accepted")
            return;
        // Notify the follower that their request was accepted.
        const actor = await (0, helpers_1.getActorInfo)(followedId);
        if (!actor)
            return;
        const routes = (0, helpers_1.buildRoutes)(types_1.NotificationType.FollowRequestAccepted, {
            actorId: followedId,
        });
        await processCandidate({
            recipientId: followerId,
            type: types_1.NotificationType.FollowRequestAccepted,
            actorId: followedId,
            actorName: actor.name,
            actorUsername: actor.username,
            actorProfileImageURL: actor.profileImageURL,
            postId: null,
            commentId: null,
            parentCommentId: null,
            conversationId: null,
            prayerId: null,
            noteId: null,
            commentText: null,
            ...routes,
        });
    }
    else {
        // Public account: notify the followed user of the new follower.
        // Block check: don't notify if the followed user has blocked the follower.
        const blockDoc = await db
            .collection("blockedUsers")
            .doc(`${followedId}_${followerId}`)
            .get();
        if (blockDoc.exists)
            return;
        const actor = await (0, helpers_1.getActorInfo)(followerId);
        if (!actor)
            return;
        const routes = (0, helpers_1.buildRoutes)(types_1.NotificationType.Follow, {
            actorId: followerId,
        });
        await processCandidate({
            recipientId: followedId,
            type: types_1.NotificationType.Follow,
            actorId: followerId,
            actorName: actor.name,
            actorUsername: actor.username,
            actorProfileImageURL: actor.profileImageURL,
            postId: null,
            commentId: null,
            parentCommentId: null,
            conversationId: null,
            prayerId: null,
            noteId: null,
            commentText: null,
            ...routes,
        });
    }
});
// ─── Amen (Like) Created ───────────────────────────────────────────
/**
 * Trigger: posts/{postId}/amens/{userId} — onCreate
 * Notifies: the post author
 */
exports.onAmenCreated = (0, firestore_1.onDocumentCreated)("posts/{postId}/amens/{userId}", async (event) => {
    const { postId, userId: actorId } = event.params;
    // Get the post to find the author
    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists)
        return;
    const postData = postDoc.data();
    if (!postData)
        return;
    const recipientId = postData.userId || postData.authorId;
    if (!recipientId)
        return;
    const actor = await (0, helpers_1.getActorInfo)(actorId);
    if (!actor)
        return;
    const routes = (0, helpers_1.buildRoutes)(types_1.NotificationType.Amen, {
        postId,
        actorId,
    });
    const candidate = {
        recipientId,
        type: types_1.NotificationType.Amen,
        actorId,
        actorName: actor.name,
        actorUsername: actor.username,
        actorProfileImageURL: actor.profileImageURL,
        postId,
        commentId: null,
        parentCommentId: null,
        conversationId: null,
        prayerId: null,
        noteId: null,
        commentText: null,
        ...routes,
    };
    await processCandidate(candidate);
});
// ─── Comment Created ────────────────────────────────────────────────
/**
 * Trigger: comments/{commentId} — onCreate
 * Doc fields: postId, userId, text, parentCommentId (null for top-level)
 *
 * If parentCommentId is null → top-level comment → notify post author
 * If parentCommentId is set → reply → notify parent comment author
 */
exports.onCommentCreated = (0, firestore_1.onDocumentCreated)("comments/{commentId}", async (event) => {
    const snap = event.data;
    if (!snap)
        return;
    const data = snap.data();
    if (!data)
        return;
    const commentId = event.params.commentId;
    const actorId = data.userId || data.authorId;
    const postId = data.postId;
    const parentCommentId = data.parentCommentId || null;
    const commentText = data.text || data.content || null;
    if (!actorId || !postId)
        return;
    const actor = await (0, helpers_1.getActorInfo)(actorId);
    if (!actor)
        return;
    if (parentCommentId) {
        // This is a REPLY to another comment
        await handleReply(actor, actorId, postId, commentId, parentCommentId, commentText);
    }
    else {
        // This is a top-level COMMENT on a post
        await handleComment(actor, actorId, postId, commentId, commentText);
    }
    // Also check for @mentions in the text
    if (commentText) {
        await handleMentions(actor, actorId, postId, commentId, commentText);
    }
});
/**
 * Handle top-level comment notification → notify post author.
 */
async function handleComment(actor, actorId, postId, commentId, commentText) {
    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists)
        return;
    const postData = postDoc.data();
    if (!postData)
        return;
    const recipientId = postData.userId || postData.authorId;
    if (!recipientId)
        return;
    const routes = (0, helpers_1.buildRoutes)(types_1.NotificationType.Comment, {
        postId,
        commentId,
        actorId,
    });
    const candidate = {
        recipientId,
        type: types_1.NotificationType.Comment,
        actorId,
        actorName: actor.name,
        actorUsername: actor.username,
        actorProfileImageURL: actor.profileImageURL,
        postId,
        commentId,
        parentCommentId: null,
        conversationId: null,
        prayerId: null,
        noteId: null,
        commentText,
        ...routes,
    };
    await processCandidate(candidate);
}
/**
 * Handle reply notification → notify parent comment author.
 */
async function handleReply(actor, actorId, postId, replyId, parentCommentId, commentText) {
    // Get the parent comment to find its author
    const parentDoc = await db
        .collection("comments")
        .doc(parentCommentId)
        .get();
    if (!parentDoc.exists)
        return;
    const parentData = parentDoc.data();
    if (!parentData)
        return;
    const recipientId = parentData.userId || parentData.authorId;
    if (!recipientId)
        return;
    const routes = (0, helpers_1.buildRoutes)(types_1.NotificationType.Reply, {
        postId,
        commentId: replyId,
        parentCommentId,
        replyId,
        actorId,
    });
    const candidate = {
        recipientId,
        type: types_1.NotificationType.Reply,
        actorId,
        actorName: actor.name,
        actorUsername: actor.username,
        actorProfileImageURL: actor.profileImageURL,
        postId,
        commentId: replyId,
        parentCommentId,
        conversationId: null,
        prayerId: null,
        noteId: null,
        commentText,
        ...routes,
    };
    await processCandidate(candidate);
    // Also notify the post author if they're different from the parent comment author
    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists)
        return;
    const postData = postDoc.data();
    const postAuthorId = postData?.userId || postData?.authorId;
    if (postAuthorId && postAuthorId !== recipientId && postAuthorId !== actorId) {
        const postAuthorRoutes = (0, helpers_1.buildRoutes)(types_1.NotificationType.Reply, {
            postId,
            commentId: replyId,
            parentCommentId,
            replyId,
            actorId,
        });
        const postAuthorCandidate = {
            recipientId: postAuthorId,
            type: types_1.NotificationType.Reply,
            actorId,
            actorName: actor.name,
            actorUsername: actor.username,
            actorProfileImageURL: actor.profileImageURL,
            postId,
            commentId: replyId,
            parentCommentId,
            conversationId: null,
            prayerId: null,
            noteId: null,
            commentText,
            ...postAuthorRoutes,
        };
        await processCandidate(postAuthorCandidate);
    }
}
/**
 * Handle @mentions in comment/reply text.
 * Parses @username patterns and notifies mentioned users.
 */
async function handleMentions(actor, actorId, postId, commentId, text) {
    // Extract @mentions from text
    const mentionPattern = /@([a-zA-Z0-9_]+)/g;
    const mentions = [];
    let match;
    while ((match = mentionPattern.exec(text)) !== null) {
        mentions.push(match[1]);
    }
    if (mentions.length === 0)
        return;
    // Cap at 5 mentions per comment to bound Firestore reads (fix 5.9).
    // A comment with 20+ @mentions would otherwise fire 20+ serial queries.
    const MAX_MENTIONS = 5;
    const dedupedMentions = [...new Set(mentions)].slice(0, MAX_MENTIONS);
    // Batch all username lookups in parallel instead of serial for...of (fix 5.9).
    const userSnapshots = await Promise.all(dedupedMentions.map((username) => db.collection("users").where("username", "==", username).limit(1).get()));
    await Promise.all(userSnapshots.map(async (userQuery) => {
        if (userQuery.empty)
            return;
        const mentionedUserId = userQuery.docs[0].id;
        if (mentionedUserId === actorId)
            return;
        const routes = (0, helpers_1.buildRoutes)(types_1.NotificationType.Mention, {
            postId,
            commentId,
            actorId,
        });
        const candidate = {
            recipientId: mentionedUserId,
            type: types_1.NotificationType.Mention,
            actorId,
            actorName: actor.name,
            actorUsername: actor.username,
            actorProfileImageURL: actor.profileImageURL,
            postId,
            commentId,
            parentCommentId: null,
            conversationId: null,
            prayerId: null,
            noteId: null,
            commentText: null,
            ...routes,
        };
        await processCandidate(candidate);
    }));
}
// ─── Repost Created ─────────────────────────────────────────────────
/**
 * Trigger: reposts/{docId} — onCreate
 * Doc fields: userId (reposter), postId (original post)
 * Notifies: the original post author
 */
exports.onRepostCreated = (0, firestore_1.onDocumentCreated)("reposts/{docId}", async (event) => {
    const snap = event.data;
    if (!snap)
        return;
    const data = snap.data();
    if (!data)
        return;
    const actorId = data.userId || data.reposterId;
    const postId = data.postId || data.originalPostId;
    if (!actorId || !postId)
        return;
    // Get the original post to find the author
    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists)
        return;
    const postData = postDoc.data();
    if (!postData)
        return;
    const recipientId = postData.userId || postData.authorId;
    if (!recipientId)
        return;
    const actor = await (0, helpers_1.getActorInfo)(actorId);
    if (!actor)
        return;
    const routes = (0, helpers_1.buildRoutes)(types_1.NotificationType.Repost, {
        postId,
        actorId,
    });
    const candidate = {
        recipientId,
        type: types_1.NotificationType.Repost,
        actorId,
        actorName: actor.name,
        actorUsername: actor.username,
        actorProfileImageURL: actor.profileImageURL,
        postId,
        commentId: null,
        parentCommentId: null,
        conversationId: null,
        prayerId: null,
        noteId: null,
        commentText: null,
        ...routes,
    };
    await processCandidate(candidate);
});
// ─── Prayer Supported ───────────────────────────────────────────────
/**
 * Trigger: prayers/{prayerId}/supporters/{userId} — onCreate
 * Notifies: the prayer author
 */
exports.onPrayerSupportCreated = (0, firestore_1.onDocumentCreated)("prayers/{prayerId}/supporters/{userId}", async (event) => {
    const { prayerId, userId: actorId } = event.params;
    // Get the prayer to find the author
    const prayerDoc = await db.collection("prayers").doc(prayerId).get();
    if (!prayerDoc.exists)
        return;
    const prayerData = prayerDoc.data();
    if (!prayerData)
        return;
    const recipientId = prayerData.userId || prayerData.authorId;
    if (!recipientId)
        return;
    const actor = await (0, helpers_1.getActorInfo)(actorId);
    if (!actor)
        return;
    const routes = (0, helpers_1.buildRoutes)(types_1.NotificationType.PrayerSupported, {
        prayerId,
        actorId,
    });
    const candidate = {
        recipientId,
        type: types_1.NotificationType.PrayerSupported,
        actorId,
        actorName: actor.name,
        actorUsername: actor.username,
        actorProfileImageURL: actor.profileImageURL,
        postId: null,
        commentId: null,
        parentCommentId: null,
        conversationId: null,
        prayerId,
        noteId: null,
        commentText: null,
        ...routes,
    };
    await processCandidate(candidate);
});
// ─── Prayer Answered ────────────────────────────────────────────────
/**
 * Trigger: prayers/{prayerId} — onUpdate
 * When the prayer author marks it as answered, notify all supporters.
 */
exports.onPrayerAnswered = (0, firestore_1.onDocumentUpdated)("prayers/{prayerId}", async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return;
    // Only trigger when prayer is newly marked as answered
    if (before.answered === true || after.answered !== true)
        return;
    const prayerId = event.params.prayerId;
    const authorId = after.userId || after.authorId;
    if (!authorId)
        return;
    const actor = await (0, helpers_1.getActorInfo)(authorId);
    if (!actor)
        return;
    // Get all supporters
    const supportersSnapshot = await db
        .collection("prayers")
        .doc(prayerId)
        .collection("supporters")
        .get();
    const supporterIds = supportersSnapshot.docs
        .map((doc) => doc.id)
        .filter((id) => id !== authorId);
    if (supporterIds.length === 0)
        return;
    // 5.4 FIX: Fan-out via Firestore job queue instead of inline processing.
    //
    // BEFORE: sequential batches of 500 in a single invocation → 10s+ for
    // 5,000 supporters × (policy reads + writes per supporter) → timeout risk.
    //
    // AFTER: write one batch document per 100 supporters to
    // prayerAnsweredJobs/{prayerId}/batches/{index}. Each document triggers
    // processPrayerAnsweredBatch in a separate Cloud Function invocation,
    // distributing the work and eliminating the single-function timeout risk.
    // Each invocation handles ≤100 supporters — well within the 9-min limit.
    const JOB_BATCH_SIZE = 100;
    const writeBatch = db.batch();
    for (let i = 0; i < supporterIds.length; i += JOB_BATCH_SIZE) {
        const batchRef = db
            .collection("prayerAnsweredJobs")
            .doc(prayerId)
            .collection("batches")
            .doc(String(i / JOB_BATCH_SIZE));
        writeBatch.set(batchRef, {
            prayerId,
            authorId,
            actorName: actor.name,
            actorUsername: actor.username,
            actorProfileImageURL: actor.profileImageURL,
            supporterIds: supporterIds.slice(i, i + JOB_BATCH_SIZE),
            status: "pending",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    await writeBatch.commit();
});
// ─── Church Note Shared ─────────────────────────────────────────────
/**
 * Trigger: churchNotes/{noteId}/shares/{userId} — onCreate
 * Notifies: the note author
 */
exports.onChurchNoteShared = (0, firestore_1.onDocumentCreated)("churchNotes/{noteId}/shares/{userId}", async (event) => {
    const { noteId, userId: actorId } = event.params;
    const noteDoc = await db.collection("churchNotes").doc(noteId).get();
    if (!noteDoc.exists)
        return;
    const noteData = noteDoc.data();
    if (!noteData)
        return;
    const recipientId = noteData.userId || noteData.authorId;
    if (!recipientId)
        return;
    const actor = await (0, helpers_1.getActorInfo)(actorId);
    if (!actor)
        return;
    const routes = (0, helpers_1.buildRoutes)(types_1.NotificationType.ChurchNoteShared, {
        noteId,
        actorId,
    });
    const candidate = {
        recipientId,
        type: types_1.NotificationType.ChurchNoteShared,
        actorId,
        actorName: actor.name,
        actorUsername: actor.username,
        actorProfileImageURL: actor.profileImageURL,
        postId: null,
        commentId: null,
        parentCommentId: null,
        conversationId: null,
        prayerId: null,
        noteId,
        commentText: null,
        ...routes,
    };
    await processCandidate(candidate);
});
// ─── Mention in Post ────────────────────────────────────────────────
/**
 * Trigger: posts/{postId} — onCreate
 * Parses @mentions from post text and notifies mentioned users.
 */
exports.onPostCreated = (0, firestore_1.onDocumentCreated)("posts/{postId}", async (event) => {
    const snap = event.data;
    if (!snap)
        return;
    const data = snap.data();
    if (!data)
        return;
    const postId = event.params.postId;
    const actorId = data.userId || data.authorId;
    const text = data.text || data.content || data.caption || "";
    if (!actorId || !text)
        return;
    // Check for @mentions
    const mentionPattern = /@([a-zA-Z0-9_]+)/g;
    const mentions = [];
    let match;
    while ((match = mentionPattern.exec(text)) !== null) {
        mentions.push(match[1]);
    }
    if (mentions.length === 0)
        return;
    const actor = await (0, helpers_1.getActorInfo)(actorId);
    if (!actor)
        return;
    // Cap at 5 and deduplicate, then batch-lookup in parallel (fix 5.9).
    const MAX_MENTIONS = 5;
    const dedupedMentions = [...new Set(mentions)].slice(0, MAX_MENTIONS);
    const userSnapshots = await Promise.all(dedupedMentions.map((username) => db.collection("users").where("username", "==", username).limit(1).get()));
    await Promise.all(userSnapshots.map(async (userQuery) => {
        if (userQuery.empty)
            return;
        const mentionedUserId = userQuery.docs[0].id;
        if (mentionedUserId === actorId)
            return;
        const routes = (0, helpers_1.buildRoutes)(types_1.NotificationType.Mention, {
            postId,
            actorId,
        });
        const candidate = {
            recipientId: mentionedUserId,
            type: types_1.NotificationType.Mention,
            actorId,
            actorName: actor.name,
            actorUsername: actor.username,
            actorProfileImageURL: actor.profileImageURL,
            postId,
            commentId: null,
            parentCommentId: null,
            conversationId: null,
            prayerId: null,
            noteId: null,
            commentText: null,
            ...routes,
        };
        await processCandidate(candidate);
    }));
});
// ─── Candidate Processor ────────────────────────────────────────────
/**
 * Central processing pipeline for all notification candidates.
 *
 * 1. Evaluate policies (fail-fast)
 * 2. Apply grouping (merge or create)
 * 3. Write to inbox
 * 4. Update unseen count
 * 5. Dispatch push (if allowed), or enqueue quiet-hours digest (if deferred)
 *
 * Exported so that processPrayerAnsweredBatch can reuse the pipeline.
 */
async function processCandidate(candidate) {
    try {
        // 1. Policy evaluation
        const policy = await (0, policies_1.evaluatePolicies)(candidate);
        if (policy.result === "suppress") {
            console.log(`Notification suppressed: ${candidate.type} from ${candidate.actorId} to ${candidate.recipientId} — reason: ${policy.triggeredBy}`);
            return;
        }
        // 2. Apply grouping — returns the notification doc ID (new or existing)
        const { notificationId, isNewNotification, notificationDoc } = await (0, grouping_1.applyGrouping)(candidate);
        // 3. Update unseen count (only for new notifications, not group updates).
        //    The transaction returns the post-increment value so we can pass it
        //    directly to sendPushNotification — eliminating the badge race under
        //    concurrent fan-out (fix 5.8).
        let badgeCount;
        if (isNewNotification) {
            badgeCount = await (0, counts_1.incrementUnseenCount)(candidate.recipientId);
        }
        // 4. Dispatch push if policy allows, or enqueue digest for quiet hours.
        if (policy.pushAllowed && notificationDoc) {
            const pushResult = await (0, sendPush_1.sendPushNotification)(notificationDoc, notificationId, badgeCount);
            console.log(`Push sent for ${candidate.type}: ${pushResult.tokensSucceeded}/${pushResult.tokensAttempted} succeeded`);
        }
        else if (policy.result === types_1.PolicyResult.Digest) {
            // 5.6 FIX: Write a quiet-hours digest queue entry so the scheduled
            // deliverQuietHoursDigest function can send a batch push at the end
            // of the user's quiet window. Without this, quiet-hours notifications
            // land in the inbox but the user never gets a push nudge.
            await db
                .collection("quietHoursDigestQueue")
                .doc(`${candidate.recipientId}_${notificationId}`)
                .set({
                userId: candidate.recipientId,
                notificationId,
                type: candidate.type,
                status: "pending",
                enqueuedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    }
    catch (error) {
        console.error(`Error processing notification ${candidate.type} from ${candidate.actorId} to ${candidate.recipientId}:`, error);
    }
}
//# sourceMappingURL=onSocialEvent.js.map