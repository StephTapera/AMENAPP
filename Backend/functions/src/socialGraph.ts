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

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2";
import { onCall, onRequest } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

const db = admin.firestore();

// ---------------------------------------------------------------------------
// MARK: - Types
// ---------------------------------------------------------------------------

interface ActivitySummary {
  userId: string;
  lastPostAt?: admin.firestore.Timestamp;
  lastPrayerAt?: admin.firestore.Timestamp;
  lastNoteAt?: admin.firestore.Timestamp;
  lastActiveAt?: admin.firestore.Timestamp;
  postCount7d: number;
  prayerCount7d: number;
  noteCount7d: number;
  latestPostSnippet?: string;
  latestPostId?: string;
  topicTags: string[];
  activeStreak: number;
  updatedAt: admin.firestore.FieldValue;
}

// ---------------------------------------------------------------------------
// MARK: - updateUserActivitySummary
// Trigger: Firestore write on posts/{postId}
// ---------------------------------------------------------------------------

export const updateUserActivitySummaryOnPost = onDocumentWritten(
  "posts/{postId}",
  async (event) => {
    const after = event.data?.after?.data();
    if (!after) return; // deletion

    const userId: string | undefined = after.authorId ?? after.userId;
    if (!userId) return;

    await updateSummaryForUser(userId, "post", {
      snippet: (after.content as string | undefined)?.slice(0, 120),
      postId: event.params.postId,
      topics: (after.tags as string[] | undefined) ?? [],
    });
  }
);

export const updateUserActivitySummaryOnPrayer = onDocumentWritten(
  "prayers/{prayerId}",
  async (event) => {
    const after = event.data?.after?.data();
    if (!after) return;

    const userId: string | undefined = after.authorId ?? after.userId;
    if (!userId) return;

    await updateSummaryForUser(userId, "prayer", {
      topics: (after.tags as string[] | undefined) ?? [],
    });
  }
);

export const updateUserActivitySummaryOnNote = onDocumentWritten(
  "churchNotes/{noteId}",
  async (event) => {
    const after = event.data?.after?.data();
    if (!after) return;

    const userId: string | undefined = after.userId ?? after.authorId;
    if (!userId) return;

    await updateSummaryForUser(userId, "note", {
      topics: (after.tags as string[] | undefined) ?? [],
    });
  }
);

// ---------------------------------------------------------------------------
// MARK: - Core summary updater
// ---------------------------------------------------------------------------

async function updateSummaryForUser(
  userId: string,
  activityType: "post" | "prayer" | "note",
  meta: { snippet?: string; postId?: string; topics?: string[] }
) {
  const ref = db.collection("user_activity_summary").doc(userId);
  const now = admin.firestore.Timestamp.now();
  const sevenDaysAgo = new Date(Date.now() - 7 * 86_400_000);

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
  const lastActiveAt: admin.firestore.Timestamp | undefined = current.lastActiveAt;
  const streak = computeStreak(lastActiveAt, current.activeStreak as number | undefined);

  const update: Partial<ActivitySummary> & { updatedAt: admin.firestore.FieldValue } = {
    userId,
    postCount7d: postCount,
    prayerCount7d: prayerCount,
    noteCount7d: noteCount,
    lastActiveAt: now,
    topicTags: mergeTags(current.topicTags as string[] | undefined, meta.topics ?? []),
    activeStreak: streak,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (activityType === "post") {
    update.lastPostAt = now;
    if (meta.snippet) update.latestPostSnippet = meta.snippet;
    if (meta.postId) update.latestPostId = meta.postId;
  } else if (activityType === "prayer") {
    update.lastPrayerAt = now;
  } else if (activityType === "note") {
    update.lastNoteAt = now;
  }

  await ref.set(update, { merge: true });

  // Fan out to relationship states for all followers of this user
  await fanOutToFollowerRelationships(userId, activityType);
}

// ---------------------------------------------------------------------------
// MARK: - Fan-out: update relationship_activity_state for each follower
// ---------------------------------------------------------------------------

async function fanOutToFollowerRelationships(
  targetId: string,
  activityType: "post" | "prayer" | "note"
) {
  // Get all followers of targetId
  const followersSnap = await db
    .collection("follows")
    .where("followingId", "==", targetId)
    .get();

  if (followersSnap.empty) return;

  const now = admin.firestore.Timestamp.now();

  const unseenField =
    activityType === "post"
      ? "unseenPostCount"
      : activityType === "prayer"
      ? "unseenPrayerCount"
      : "unseenNoteCount";

  const BATCH_CHUNK = 400;
  const docs = followersSnap.docs;
  for (let i = 0; i < docs.length; i += BATCH_CHUNK) {
    const batch = db.batch();
    const chunk = docs.slice(i, i + BATCH_CHUNK);
    for (const doc of chunk) {
      const viewerId: string | undefined = doc.data().followerId;
      if (!viewerId) continue;

      const docId = `${viewerId}_${targetId}`;
      const ref = db.collection("relationship_activity_state").doc(docId);

      batch.set(
        ref,
        {
          viewerId,
          targetId,
          [unseenField]: admin.firestore.FieldValue.increment(1),
          lastActivityAt: now,
          computedAt: now,
        },
        { merge: true }
      );
    }
    await batch.commit();
  }
}

// ---------------------------------------------------------------------------
// MARK: - markRelationshipSeen (Callable)
// ---------------------------------------------------------------------------

export const markRelationshipSeen = onCall(
  { enforceAppCheck: false },
  async (request) => {
    const viewerId = request.auth?.uid;
    if (!viewerId) throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");

    const { targetIds } = request.data as { targetIds: string[] };
    if (!Array.isArray(targetIds) || targetIds.length === 0) {
      throw new functions.https.HttpsError("invalid-argument", "targetIds must be a non-empty array.");
    }
    if (targetIds.length > 400) {
      throw new functions.https.HttpsError("invalid-argument", "Maximum 400 targets per call.");
    }

    const batch = db.batch();
    const now = admin.firestore.Timestamp.now();

    for (const targetId of targetIds) {
      const docId = `${viewerId}_${targetId}`;
      const ref = db.collection("relationship_activity_state").doc(docId);
      batch.set(
        ref,
        {
          unseenPostCount: 0,
          unseenPrayerCount: 0,
          unseenNoteCount: 0,
          lastSeenAt: now,
          computedAt: now,
        },
        { merge: true }
      );
    }

    await batch.commit();
    return { success: true, marked: targetIds.length };
  }
);

// ---------------------------------------------------------------------------
// MARK: - reconcileRelationshipStates (Scheduled — daily)
// Removes relationship_activity_state docs for relationships that no longer exist.
// ---------------------------------------------------------------------------

export const reconcileRelationshipStates = onSchedule(
  { schedule: "every 24 hours" },
  async () => {
    const statesSnap = await db
      .collection("relationship_activity_state")
      .where(
        "lastActivityAt",
        "<",
        admin.firestore.Timestamp.fromDate(new Date(Date.now() - 30 * 86_400_000))
      )
      .limit(500)
      .get();

    if (statesSnap.empty) return;

    const batch = db.batch();
    for (const doc of statesSnap.docs) {
      const { viewerId, targetId } = doc.data() as { viewerId: string; targetId: string };

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
  }
);

// ---------------------------------------------------------------------------
// MARK: - computeRelationshipMutualTopics (Triggered on summary update)
// Updates mutualTopics and hasMutualInteraction on relationship state docs.
// ---------------------------------------------------------------------------

export const computeRelationshipMutualData = onDocumentWritten(
  "user_activity_summary/{userId}",
  async (event) => {
    const userId = event.params.userId;
    const summaryData = event.data?.after?.data();
    if (!summaryData) return;

    const userTopics: string[] = summaryData.topicTags ?? [];

    // Get all followers of this user and update their relationship state mutual fields
    const followersSnap = await db
      .collection("follows")
      .where("followingId", "==", userId)
      .limit(200) // fan-out cap
      .get();

    if (followersSnap.empty) return;

    const batch = db.batch();

    for (const followDoc of followersSnap.docs) {
      const viewerId: string | undefined = followDoc.data().followerId;
      if (!viewerId) continue;

      // Get viewer's topics
      const viewerSummarySnap = await db
        .collection("user_activity_summary")
        .doc(viewerId)
        .get();
      const viewerTopics: string[] = viewerSummarySnap.data()?.topicTags ?? [];

      const mutualTopics = userTopics.filter((t) => viewerTopics.includes(t)).slice(0, 5);

      const docId = `${viewerId}_${userId}`;
      const ref = db.collection("relationship_activity_state").doc(docId);
      batch.set(ref, { mutualTopics, computedAt: admin.firestore.Timestamp.now() }, { merge: true });
    }

    await batch.commit();
  }
);

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

async function countRecent(
  collection: string,
  userId: string,
  since: Date
): Promise<number> {
  const snap = await db
    .collection(collection)
    .where("authorId", "==", userId)
    .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(since))
    .count()
    .get();
  return snap.data().count;
}

function computeStreak(
  lastActiveAt: admin.firestore.Timestamp | undefined,
  currentStreak: number | undefined
): number {
  if (!lastActiveAt) return 1;
  const lastDate = lastActiveAt.toDate();
  const now = new Date();
  const diffDays = Math.floor((now.getTime() - lastDate.getTime()) / 86_400_000);

  if (diffDays === 0) return currentStreak ?? 1;
  if (diffDays === 1) return (currentStreak ?? 0) + 1;
  return 1; // streak broken
}

function mergeTags(existing: string[] | undefined, incoming: string[]): string[] {
  const merged = new Set([...(existing ?? []), ...incoming]);
  return Array.from(merged).slice(0, 20); // cap at 20 tags
}
