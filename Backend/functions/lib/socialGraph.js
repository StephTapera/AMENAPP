"use strict";
/**
 * socialGraph.ts
 * AMENAPP Cloud Functions — Smart Activity Layer for Followers/Following Lists
 *
 * Functions:
 *   updateUserActivitySummary     — Triggered on post/prayer/note writes. Updates user_activity_summary/{userId}.
 *   computeRelationshipActivityState — Triggered on activity summary update. Fans out to all followers' relationship states.
 *   markRelationshipSeen          — Callable. Marks viewer's seen state for one or more targets.
 *   reconcileRelationshipStates   — Scheduled daily. Cleans up stale states.
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
exports.computeRelationshipMutualData = exports.reconcileRelationshipStates = exports.markRelationshipSeen = exports.updateUserActivitySummaryOnNote = exports.updateUserActivitySummaryOnPrayer = exports.updateUserActivitySummaryOnPost = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v2"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const db = admin.firestore();
// ---------------------------------------------------------------------------
// MARK: - updateUserActivitySummary
// Trigger: Firestore write on posts/{postId}
// ---------------------------------------------------------------------------
exports.updateUserActivitySummaryOnPost = (0, firestore_1.onDocumentWritten)("posts/{postId}", async (event) => {
    const after = event.data?.after?.data();
    if (!after)
        return; // deletion
    const userId = after.authorId ?? after.userId;
    if (!userId)
        return;
    await updateSummaryForUser(userId, "post", {
        snippet: after.content?.slice(0, 120),
        postId: event.params.postId,
        topics: after.tags ?? [],
    });
});
exports.updateUserActivitySummaryOnPrayer = (0, firestore_1.onDocumentWritten)("prayers/{prayerId}", async (event) => {
    const after = event.data?.after?.data();
    if (!after)
        return;
    const userId = after.authorId ?? after.userId;
    if (!userId)
        return;
    await updateSummaryForUser(userId, "prayer", {
        topics: after.tags ?? [],
    });
});
exports.updateUserActivitySummaryOnNote = (0, firestore_1.onDocumentWritten)("churchNotes/{noteId}", async (event) => {
    const after = event.data?.after?.data();
    if (!after)
        return;
    const userId = after.userId ?? after.authorId;
    if (!userId)
        return;
    await updateSummaryForUser(userId, "note", {
        topics: after.tags ?? [],
    });
});
// ---------------------------------------------------------------------------
// MARK: - Core summary updater
// ---------------------------------------------------------------------------
async function updateSummaryForUser(userId, activityType, meta) {
    const ref = db.collection("user_activity_summary").doc(userId);
    const now = admin.firestore.Timestamp.now();
    const sevenDaysAgo = new Date(Date.now() - 7 * 86400000);
    // Read current summary to compute rolling 7d counts
    const snap = await ref.get();
    const current = snap.data() ?? {};
    // Recount from source for accuracy (bounded query)
    const [postCount, prayerCount, noteCount] = await Promise.all([
        countRecent("posts", userId, sevenDaysAgo),
        countRecent("prayers", userId, sevenDaysAgo),
        countRecent("churchNotes", userId, sevenDaysAgo),
    ]);
    // Streak: increment if lastActiveAt was yesterday, reset if >1 day gap
    const lastActiveAt = current.lastActiveAt;
    const streak = computeStreak(lastActiveAt, current.activeStreak);
    const update = {
        userId,
        postCount7d: postCount,
        prayerCount7d: prayerCount,
        noteCount7d: noteCount,
        lastActiveAt: now,
        topicTags: mergeTags(current.topicTags, meta.topics ?? []),
        activeStreak: streak,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (activityType === "post") {
        update.lastPostAt = now;
        if (meta.snippet)
            update.latestPostSnippet = meta.snippet;
        if (meta.postId)
            update.latestPostId = meta.postId;
    }
    else if (activityType === "prayer") {
        update.lastPrayerAt = now;
    }
    else if (activityType === "note") {
        update.lastNoteAt = now;
    }
    await ref.set(update, { merge: true });
    // Fan out to relationship states for all followers of this user
    await fanOutToFollowerRelationships(userId, activityType);
}
// ---------------------------------------------------------------------------
// MARK: - Fan-out: update relationship_activity_state for each follower
// ---------------------------------------------------------------------------
async function fanOutToFollowerRelationships(targetId, activityType) {
    // Get all followers of targetId
    const followersSnap = await db
        .collection("follows")
        .where("followingId", "==", targetId)
        .get();
    if (followersSnap.empty)
        return;
    const batch = db.batch();
    const now = admin.firestore.Timestamp.now();
    const unseenField = activityType === "post"
        ? "unseenPostCount"
        : activityType === "prayer"
            ? "unseenPrayerCount"
            : "unseenNoteCount";
    for (const doc of followersSnap.docs) {
        const viewerId = doc.data().followerId;
        if (!viewerId)
            continue;
        const docId = `${viewerId}_${targetId}`;
        const ref = db.collection("relationship_activity_state").doc(docId);
        batch.set(ref, {
            viewerId,
            targetId,
            [unseenField]: admin.firestore.FieldValue.increment(1),
            lastActivityAt: now,
            computedAt: now,
        }, { merge: true });
    }
    await batch.commit();
}
// ---------------------------------------------------------------------------
// MARK: - markRelationshipSeen (Callable)
// ---------------------------------------------------------------------------
exports.markRelationshipSeen = (0, https_1.onCall)({ enforceAppCheck: false }, async (request) => {
    const viewerId = request.auth?.uid;
    if (!viewerId)
        throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");
    const { targetIds } = request.data;
    if (!Array.isArray(targetIds) || targetIds.length === 0) {
        throw new functions.https.HttpsError("invalid-argument", "targetIds must be a non-empty array.");
    }
    const batch = db.batch();
    const now = admin.firestore.Timestamp.now();
    for (const targetId of targetIds) {
        const docId = `${viewerId}_${targetId}`;
        const ref = db.collection("relationship_activity_state").doc(docId);
        batch.set(ref, {
            unseenPostCount: 0,
            unseenPrayerCount: 0,
            unseenNoteCount: 0,
            lastSeenAt: now,
            computedAt: now,
        }, { merge: true });
    }
    await batch.commit();
    return { success: true, marked: targetIds.length };
});
// ---------------------------------------------------------------------------
// MARK: - reconcileRelationshipStates (Scheduled — daily)
// Removes relationship_activity_state docs for relationships that no longer exist.
// ---------------------------------------------------------------------------
exports.reconcileRelationshipStates = (0, scheduler_1.onSchedule)({ schedule: "every 24 hours" }, async () => {
    const statesSnap = await db
        .collection("relationship_activity_state")
        .where("lastActivityAt", "<", admin.firestore.Timestamp.fromDate(new Date(Date.now() - 30 * 86400000)))
        .limit(500)
        .get();
    if (statesSnap.empty)
        return;
    const batch = db.batch();
    for (const doc of statesSnap.docs) {
        const { viewerId, targetId } = doc.data();
        // Verify the follow relationship still exists
        const followSnap = await db
            .collection("follows")
            .where("followerId", "==", viewerId)
            .where("followingId", "==", targetId)
            .limit(1)
            .get();
        if (followSnap.empty) {
            batch.delete(doc.ref);
        }
    }
    await batch.commit();
    console.log(`[socialGraph] reconciled up to ${statesSnap.size} stale relationship states`);
});
// ---------------------------------------------------------------------------
// MARK: - computeRelationshipMutualTopics (Triggered on summary update)
// Updates mutualTopics and hasMutualInteraction on relationship state docs.
// ---------------------------------------------------------------------------
exports.computeRelationshipMutualData = (0, firestore_1.onDocumentWritten)("user_activity_summary/{userId}", async (event) => {
    const userId = event.params.userId;
    const summaryData = event.data?.after?.data();
    if (!summaryData)
        return;
    const userTopics = summaryData.topicTags ?? [];
    // Get all followers of this user and update their relationship state mutual fields
    const followersSnap = await db
        .collection("follows")
        .where("followingId", "==", userId)
        .limit(200) // fan-out cap
        .get();
    if (followersSnap.empty)
        return;
    const batch = db.batch();
    for (const followDoc of followersSnap.docs) {
        const viewerId = followDoc.data().followerId;
        if (!viewerId)
            continue;
        // Get viewer's topics
        const viewerSummarySnap = await db
            .collection("user_activity_summary")
            .doc(viewerId)
            .get();
        const viewerTopics = viewerSummarySnap.data()?.topicTags ?? [];
        const mutualTopics = userTopics.filter((t) => viewerTopics.includes(t)).slice(0, 5);
        const docId = `${viewerId}_${userId}`;
        const ref = db.collection("relationship_activity_state").doc(docId);
        batch.set(ref, { mutualTopics, computedAt: admin.firestore.Timestamp.now() }, { merge: true });
    }
    await batch.commit();
});
// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------
async function countRecent(collection, userId, since) {
    const snap = await db
        .collection(collection)
        .where("authorId", "==", userId)
        .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(since))
        .count()
        .get();
    return snap.data().count;
}
function computeStreak(lastActiveAt, currentStreak) {
    if (!lastActiveAt)
        return 1;
    const lastDate = lastActiveAt.toDate();
    const now = new Date();
    const diffDays = Math.floor((now.getTime() - lastDate.getTime()) / 86400000);
    if (diffDays === 0)
        return currentStreak ?? 1;
    if (diffDays === 1)
        return (currentStreak ?? 0) + 1;
    return 1; // streak broken
}
function mergeTags(existing, incoming) {
    const merged = new Set([...(existing ?? []), ...incoming]);
    return Array.from(merged).slice(0, 20); // cap at 20 tags
}
//# sourceMappingURL=socialGraph.js.map