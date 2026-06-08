/**
 * followKnowledge.js
 * Agent G — Topic Follow + Knowledge Notification System (ADDITIVE ONLY)
 *
 * Exports (all onCall, auth required):
 *   - followTopic        — user explicitly follows a topic (opt-in only)
 *   - unfollowTopic      — user removes a followed topic
 *   - getFollowedTopics  — list followed topics with recent work counts
 *   - getTopicFeed       — recent works across all followed topics
 *
 * Internal (called by Agent C's onWorkPublished):
 *   - notifyTopicFollowers — fan-out in-app notifications to topic followers
 *
 * Privacy invariants:
 *   - All follows are EXPLICIT user actions — no forced subscriptions
 *   - No comparative metrics (leaderboards, engagement scores) exposed
 *   - FCM push NOT sent for catalog updates by default (in-app only)
 *   - Dedup: max 1 notification per topic per creator per user per day
 *
 * Firestore schema:
 *   users/{uid}/followedTopics/{topicId} = { topicId, topicName, createdAt }
 *   users/{uid}/notifications/{notifId}  = { type:'catalogUpdate', ... }
 *
 * Required Firestore index:
 *   Collection group: followedTopics  Field: topicId (ASC)
 *   (Add in Firebase Console → Firestore → Indexes → Single field)
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin     = require("firebase-admin");

// admin is already initialized in index.js — do not call initializeApp() again.
const db = admin.firestore();

// ── CONSTANTS ─────────────────────────────────────────────────────────────────

const MAX_FOLLOWED_TOPICS = 50;
const MAX_TOPIC_FEED_SIZE = 50;
const NOTIFY_BATCH_MAX    = 1000; // max followers to notify per topic per publish event
const NOTIFY_DEDUP_HOURS  = 24;   // hours between duplicate notifications

// ── HELPERS ───────────────────────────────────────────────────────────────────

function topicDocRef(uid, topicId) {
  return db.collection("users").doc(uid).collection("followedTopics").doc(topicId);
}

function notificationRef(uid) {
  return db.collection("users").doc(uid).collection("notifications").doc();
}

/** Returns the start-of-today timestamp for dedup window checks. */
function todayStartMs() {
  const now = new Date();
  now.setHours(0, 0, 0, 0);
  return now.getTime();
}

// ── TOPIC ID NORMALIZER ───────────────────────────────────────────────────────

function normalizeTopicId(raw) {
  return (raw ?? "").toLowerCase().trim().replace(/\s+/g, "-").replace(/[^a-z0-9-]/g, "");
}

// ═════════════════════════════════════════════════════════════════════════════
// CF: followTopic
// ═════════════════════════════════════════════════════════════════════════════

exports.followTopic = onCall({ region: 'us-central1' }, async (req) => { const data = req.data; const context = { auth: req.auth };
  if (!context.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const uid = context.auth.uid;

  const topicId   = normalizeTopicId(data.topicId ?? "");
  const topicName = (data.topicName ?? topicId).trim();

  if (!topicId) {
    throw new HttpsError("invalid-argument", "topicId is required.");
  }
  if (topicName.length > 80) {
    throw new HttpsError("invalid-argument", "topicName too long (max 80 chars).");
  }

  // Enforce max 50 followed topics
  const existingSnap = await db
    .collection("users")
    .doc(uid)
    .collection("followedTopics")
    .limit(MAX_FOLLOWED_TOPICS + 1)
    .get();

  if (existingSnap.size >= MAX_FOLLOWED_TOPICS) {
    // Check if this topic already exists (re-follow is idempotent)
    const already = existingSnap.docs.some((d) => d.id === topicId);
    if (!already) {
      throw new HttpsError(
        "resource-exhausted",
        `You can follow at most ${MAX_FOLLOWED_TOPICS} topics. Unfollow some before adding more.`
      );
    }
  }

  // Write follow document — idempotent (set with merge would overwrite, but we want createdAt preserved)
  const ref = topicDocRef(uid, topicId);
  const existing = await ref.get();
  if (!existing.exists) {
    await ref.set({
      topicId,
      topicName,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`[followTopic] uid=${uid} followed topic="${topicId}"`);
  } else {
    console.log(`[followTopic] uid=${uid} already following topic="${topicId}" — no-op`);
  }

  return { followed: true, topicId };
});

// ═════════════════════════════════════════════════════════════════════════════
// CF: unfollowTopic
// ═════════════════════════════════════════════════════════════════════════════

exports.unfollowTopic = onCall({ region: 'us-central1' }, async (req) => { const data = req.data; const context = { auth: req.auth };
  if (!context.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const uid     = context.auth.uid;
  const topicId = normalizeTopicId(data.topicId ?? "");

  if (!topicId) {
    throw new HttpsError("invalid-argument", "topicId is required.");
  }

  await topicDocRef(uid, topicId).delete();
  console.log(`[unfollowTopic] uid=${uid} unfollowed topic="${topicId}"`);

  return { unfollowed: true, topicId };
});

// ═════════════════════════════════════════════════════════════════════════════
// CF: getFollowedTopics
// ═════════════════════════════════════════════════════════════════════════════

exports.getFollowedTopics = onCall({ region: 'us-central1' }, async (req) => { const data = req.data; const context = { auth: req.auth };
  if (!context.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const uid = context.auth.uid;

  const snap = await db
    .collection("users")
    .doc(uid)
    .collection("followedTopics")
    .orderBy("createdAt", "desc")
    .limit(MAX_FOLLOWED_TOPICS)
    .get();

  const topicIds = snap.docs.map((d) => d.id);

  // Compute recent work counts for each followed topic
  const recentCutoff = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) // last 30 days
  );

  const workCounts = await Promise.all(
    topicIds.map(async (tid) => {
      try {
        const workSnap = await db
          .collection("catalog_works")
          .where("topics", "array-contains", tid)
          .where("reviewState", "==", "published")
          .where("visibility", "==", "public")
          .where("publishedAt", ">=", recentCutoff)
          .limit(99)
          .get();
        return workSnap.size;
      } catch (_) {
        return 0;
      }
    })
  );

  const topics = snap.docs.map((doc, i) => {
    const d = doc.data();
    return {
      topicId:        doc.id,
      topicName:      d.topicName ?? doc.id,
      recentWorkCount: workCounts[i] ?? 0,
      followedAt:     d.createdAt?.toMillis() ?? null,
    };
  });

  return { topics };
});

// ═════════════════════════════════════════════════════════════════════════════
// CF: getTopicFeed
// ═════════════════════════════════════════════════════════════════════════════

exports.getTopicFeed = onCall({ region: 'us-central1' }, async (req) => { const data = req.data; const context = { auth: req.auth };
  if (!context.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const uid = context.auth.uid;

  // Fetch followed topics
  const topicsSnap = await db
    .collection("users")
    .doc(uid)
    .collection("followedTopics")
    .limit(MAX_FOLLOWED_TOPICS)
    .get();

  if (topicsSnap.empty) {
    return { works: [], topics: [] };
  }

  const followedTopicIds = topicsSnap.docs.map((d) => d.id);

  // Fetch recent works for each followed topic (parallel, max 10 per topic)
  const perTopicWorks = await Promise.all(
    followedTopicIds.map(async (tid) => {
      try {
        const snap = await db
          .collection("catalog_works")
          .where("topics", "array-contains", tid)
          .where("reviewState", "==", "published")
          .where("visibility", "==", "public")
          .orderBy("publishedAt", "desc")
          .limit(10)
          .get();

        return snap.docs.map((doc) => {
          const d = doc.data();
          return {
            id:          doc.id,
            creatorId:   d.creatorId ?? "",
            title:       d.title ?? "",
            type:        d.type ?? "article",
            topics:      d.topics ?? [],
            coverUrl:    d.coverUrl ?? null,
            publishedAt: d.publishedAt?.toMillis() ?? null,
          };
        });
      } catch (_) {
        return [];
      }
    })
  );

  // Flatten, deduplicate by work ID, sort by publishedAt DESC
  const seen    = new Set();
  const allWorks = [];
  for (const batch of perTopicWorks) {
    for (const work of batch) {
      if (!seen.has(work.id)) {
        seen.add(work.id);
        allWorks.push(work);
      }
    }
  }

  allWorks.sort((a, b) => (b.publishedAt ?? 0) - (a.publishedAt ?? 0));
  const works = allWorks.slice(0, MAX_TOPIC_FEED_SIZE);

  // Enrich with creator names
  const creatorIds = [...new Set(works.map((w) => w.creatorId).filter(Boolean))];
  const profileMap = new Map();
  for (let i = 0; i < creatorIds.length; i += 10) {
    const chunk = creatorIds.slice(i, i + 10);
    const snaps = await Promise.all(chunk.map((id) => db.collection("users").doc(id).get()));
    for (const snap of snaps) {
      if (snap.exists) profileMap.set(snap.id, snap.data());
    }
  }

  const enrichedWorks = works.map((w) => {
    const profile = profileMap.get(w.creatorId);
    return {
      ...w,
      creatorName: profile?.displayName ?? profile?.username ?? "",
      creatorAvatar: profile?.avatarUrl ?? profile?.photoURL ?? null,
    };
  });

  const topicNames = topicsSnap.docs.map((d) => d.data().topicName ?? d.id);

  return { works: enrichedWorks, topics: topicNames };
});

// ═════════════════════════════════════════════════════════════════════════════
// INTERNAL: notifyTopicFollowers
// Called by Agent C's onWorkPublished after a work transitions to published.
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Fan-out in-app catalog update notifications to followers of any topic
 * that the published work belongs to.
 *
 * @param {{ workId: string, creatorId: string, workType: string, topics: string[], creatorName: string, workTitle: string }} params
 */
async function notifyTopicFollowers({
  workId,
  creatorId,
  workType = "work",
  topics,
  creatorName,
  workTitle,
}) {
  if (!workId || !creatorId || !topics || topics.length === 0) {
    console.warn("[notifyTopicFollowers] Missing required params — skipping");
    return;
  }

  const dedupCutoff = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - NOTIFY_DEDUP_HOURS * 60 * 60 * 1000)
  );

  for (const rawTopicId of topics) {
    const tid = normalizeTopicId(rawTopicId);
    if (!tid) continue;

    // Collection-group query: all users who follow this topic
    // Requires Firestore index: followedTopics (topicId ASC)
    let followersQuery;
    try {
      followersQuery = await db
        .collectionGroup("followedTopics")
        .where("topicId", "==", tid)
        .limit(NOTIFY_BATCH_MAX)
        .get();
    } catch (err) {
      console.error(`[notifyTopicFollowers] Collection group query failed for topicId="${tid}":`, err.message);
      console.error("  => Ensure Firestore index exists on collection group 'followedTopics' for field 'topicId'");
      continue;
    }

    if (followersQuery.empty) continue;

    const batch = db.batch();
    let count   = 0;

    for (const followDoc of followersQuery.docs) {
      // followDoc.ref path: users/{followerId}/followedTopics/{topicId}
      const pathSegments = followDoc.ref.path.split("/");
      const followerId   = pathSegments[1];

      // Do not notify the creator about their own publish
      if (followerId === creatorId) continue;

      // Dedup: check if we already sent a notification for this creator + topic today
      try {
        const dedupSnap = await db
          .collection("users")
          .doc(followerId)
          .collection("notifications")
          .where("type", "==", "catalogUpdate")
          .where("data.creatorId", "==", creatorId)
          .where("data.topic", "==", tid)
          .where("createdAt", ">=", dedupCutoff)
          .limit(1)
          .get();

        if (!dedupSnap.empty) continue; // already notified today
      } catch (err) {
        // Dedup query may fail if index is missing — proceed without dedup rather than block
        console.warn(`[notifyTopicFollowers] Dedup check failed for ${followerId}:`, err.message);
      }

      const notifRef = db
        .collection("users")
        .doc(followerId)
        .collection("notifications")
        .doc();

      batch.set(notifRef, {
        type:      "catalogUpdate",
        title:     `${creatorName} published a new ${workType}`,
        body:      workTitle,
        data:      { workId, creatorId, topic: tid },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        read:      false,
      });

      count++;

      // Commit in chunks of 500 (Firestore batch limit)
      if (count % 500 === 0) {
        await batch.commit();
        console.log(`[notifyTopicFollowers] Committed batch of 500 for topic="${tid}"`);
      }
    }

    // Commit remaining
    if (count % 500 !== 0 && count > 0) {
      await batch.commit();
    }

    console.log(`[notifyTopicFollowers] Sent ${count} notifications for topic="${tid}" workId=${workId}`);

    // NOTE: FCM push NOT sent for catalog updates by default.
    // Push is only sent if the user has enabled catalogUpdate push in their
    // notificationSettings (to be wired by the settings layer when ready).
  }
}

exports.notifyTopicFollowers = notifyTopicFollowers;
