/**
 * notifications.js
 * Additional notification triggers for AMEN App
 *
 * Covers:
 *  - Prayer amens (someone prays for your request)
 *  - Prayer comments (someone responds to your prayer)
 *  - Post mentions (@username in post text)
 *  - Weekly check-in reminder (Monday 9 AM ET)
 *  - Community digest (Friday 6 PM ET)
 *  - Berean daily scripture insight (daily 7 AM ET)
 *
 * Uses existing sendPushNotificationToUser() from pushNotifications.js
 * and writes in-app notification docs to users/{userId}/notifications.
 */

"use strict";

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

// admin is already initialized in index.js — do not call initializeApp() again.
const db = admin.firestore();

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: write in-app notification doc and send push
// ─────────────────────────────────────────────────────────────────────────────

async function notifyUser(recipientId, {
  type,
  title,
  body,
  actorId = "",
  actorName = "",
  targetId = "",
  targetType = "",
  deepLink = "",
  channelId = "default",
}) {
  if (!recipientId) return;

  // Fetch recipient to check preferences and get FCM tokens
  const recipientDoc = await db.collection("users").doc(recipientId).get();
  if (!recipientDoc.exists) return;
  const recipient = recipientDoc.data();

  // Preference check — key matches notificationSettings structure in pushNotifications.js
  const prefKey = {
    prayer: "prayerRequests",
    mention: "mentions",
    weeklyCheckin: "reminders",
    communityDigest: "communityUpdates",
    bereanInsight: "bereanInsights",
  }[type] ?? type;

  const settings = recipient?.notificationSettings || {};
  if (settings[prefKey] === false) {
    console.log(`🔕 ${recipientId} has disabled ${type} notifications`);
    return;
  }

  // Write in-app notification with a deterministic ID so Cloud Function retries
  // are idempotent — a duplicate trigger overwrites instead of creating a second row.
  // ID format: {type}_{actorId}_{targetId}_{hourBucket} where hourBucket is
  // floor(epochSeconds / 3600) — collapses retries within the same hour.
  const hourBucket = Math.floor(Date.now() / 3_600_000);
  const notifId = `${type}_${actorId}_${targetId}_${hourBucket}`.replace(/[^a-zA-Z0-9_-]/g, "_");
  await db.collection("users").doc(recipientId)
    .collection("notifications").doc(notifId)
    .set({
      type,
      title,
      body,
      actorId,
      actorName,
      targetId,
      targetType,
      deepLink,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: false });

  // Send push to all enabled device tokens
  const tokenSnap = await db
    .collection("users").doc(recipientId)
    .collection("deviceTokens")
    .where("enabled", "==", true)
    .get();

  let tokens = tokenSnap.docs.map((d) => d.data().token).filter(Boolean);
  if (tokens.length === 0 && recipient?.fcmToken) {
    tokens = [recipient.fcmToken]; // legacy fallback
  }
  if (tokens.length === 0) return;

  const stale = [];
  await Promise.all(tokens.map(async (token) => {
    try {
      // Sensitive categories (prayer / testimony) require mutable-content: 1
      // so the Notification Service Extension can mask the body on the lock screen.
      const sensitiveCategories = new Set(["prayer", "prayer_request", "testimony"]);
      const isSensitive = sensitiveCategories.has(type) || sensitiveCategories.has(channelId);
      // Map internal type to the NSE category constant
      const apnsCategory = type === "testimony" ? "testimony" : (isSensitive ? "prayer_request" : undefined);

      await admin.messaging().send({
        token,
        notification: {title, body},
        data: {type, targetId, targetType, actorId, actorName, deepLink, channelId, category: apnsCategory ?? ""},
        apns: {
          payload: {
            aps: {
              badge: (recipient?.unreadNotificationCount ?? 0) + 1,
              sound: "default",
              "content-available": 1,
              // mutable-content: 1 allows the Notification Service Extension to
              // intercept and mask prayer/testimony content before display.
              ...(isSensitive ? {"mutable-content": 1, category: apnsCategory} : {}),
            },
          },
        },
      });
    } catch (err) {
      if (
        err.code === "messaging/registration-token-not-registered" ||
        err.code === "messaging/invalid-registration-token"
      ) {
        stale.push(token);
      } else {
        console.error(`❌ FCM send error for ${recipientId}:`, err.message);
      }
    }
  }));

  // Clean up stale tokens
  if (stale.length > 0) {
    const batch = db.batch();
    tokenSnap.docs.forEach((d) => {
      if (stale.includes(d.data().token)) batch.delete(d.ref);
    });
    await batch.commit();
    console.log(`🧹 Removed ${stale.length} stale token(s) for ${recipientId}`);
  }

  // Increment server-side unread count (used for badge in push payload)
  await db.collection("users").doc(recipientId).update({
    unreadNotificationCount: admin.firestore.FieldValue.increment(1),
  });

  console.log(`✅ Notified ${recipientId} (${type})`);
}

// ─────────────────────────────────────────────────────────────────────────────
// TRIGGER 1: Prayer Amen — someone says Amen on your prayer request
// Document path: prayers/{prayerId}/amens/{amenId}
// ─────────────────────────────────────────────────────────────────────────────

exports.onPrayerAmen = onDocumentCreated(
  {document: "prayers/{prayerId}/amens/{amenId}"},
  async (event) => {
    try {
      const amen = event.data.data();
      const prayerDoc = await db.collection("prayers").doc(event.params.prayerId).get();
      if (!prayerDoc.exists) return;
      const prayer = prayerDoc.data();

      // No self-notification
      if (!prayer?.authorId || amen.userId === prayer.authorId) return;

      await notifyUser(prayer.authorId, {
        type: "prayer",
        title: "🙏 Someone is praying for you",
        body: `${amen.userName || "Someone"} said Amen to your prayer request`,
        actorId: amen.userId || "",
        actorName: amen.userName || "",
        targetId: event.params.prayerId,
        targetType: "prayer",
        deepLink: `amen://prayer/${event.params.prayerId}`,
        channelId: "prayer",
      });
    } catch (err) {
      console.error("❌ onPrayerAmen error:", err);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// TRIGGER 2: Prayer Comment — someone responds to your prayer
// Document path: prayers/{prayerId}/comments/{commentId}
// ─────────────────────────────────────────────────────────────────────────────

exports.onPrayerComment = onDocumentCreated(
  {document: "prayers/{prayerId}/comments/{commentId}"},
  async (event) => {
    try {
      const comment = event.data.data();
      const prayerDoc = await db.collection("prayers").doc(event.params.prayerId).get();
      if (!prayerDoc.exists) return;
      const prayer = prayerDoc.data();

      if (!prayer?.authorId || comment.authorId === prayer.authorId) return;

      const preview = (comment.text || "").slice(0, 80);
      const ellipsis = (comment.text || "").length > 80 ? "…" : "";

      await notifyUser(prayer.authorId, {
        type: "prayer",
        title: "🙏 Response to your prayer",
        body: `${comment.authorName || "Someone"}: "${preview}${ellipsis}"`,
        actorId: comment.authorId || "",
        actorName: comment.authorName || "",
        targetId: event.params.prayerId,
        targetType: "prayer",
        deepLink: `amen://prayer/${event.params.prayerId}`,
        channelId: "prayer",
      });
    } catch (err) {
      console.error("❌ onPrayerComment error:", err);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// TRIGGER 3: Post Mention — @username in a new post
// Document path: posts/{postId}
// Parses @mentions from post.text and notifies each mentioned user.
// ─────────────────────────────────────────────────────────────────────────────

exports.onPostMention = onDocumentCreated(
  {document: "posts/{postId}"},
  async (event) => {
    try {
      const post = event.data.data();
      if (!post?.text) return;

      const mentionedUsernames = extractMentions(post.text);
      if (mentionedUsernames.length === 0) return;

      const preview = post.text.slice(0, 80);
      const ellipsis = post.text.length > 80 ? "…" : "";

      await Promise.all(mentionedUsernames.map(async (username) => {
        const mentionedUser = await getUserByUsername(username);
        if (!mentionedUser || mentionedUser.id === post.authorId) return;

        await notifyUser(mentionedUser.id, {
          type: "mention",
          title: "@ You were mentioned",
          body: `${post.authorName || "Someone"}: "${preview}${ellipsis}"`,
          actorId: post.authorId || "",
          actorName: post.authorName || "",
          targetId: event.params.postId,
          targetType: "post",
          deepLink: `amen://post/${event.params.postId}`,
          channelId: "social",
        });
      }));
    } catch (err) {
      console.error("❌ onPostMention error:", err);
    }
  }
);

function extractMentions(text) {
  const matches = text.match(/@(\w+)/g) || [];
  return [...new Set(matches.map((m) => m.slice(1).toLowerCase()))];
}

async function getUserByUsername(username) {
  const snap = await db
    .collection("users")
    .where("usernameLowercase", "==", username)
    .limit(1)
    .get();
  if (snap.empty) return null;
  return {id: snap.docs[0].id, ...snap.docs[0].data()};
}

// ─────────────────────────────────────────────────────────────────────────────
// TRIGGER 4: Weekly Check-in Reminder (Monday 9:00 AM ET)
// ─────────────────────────────────────────────────────────────────────────────

exports.weeklyCheckin = onSchedule(
  {schedule: "every monday 09:00", timeZone: "America/New_York"},
  async () => {
    try {
      // Fan-out in batches of 500 to avoid memory pressure
      let lastDoc = null;
      const batchSize = 500;

      while (true) {
        let query = db.collection("users")
          .where("notificationSettings.reminders", "!=", false)
          .limit(batchSize);
        if (lastDoc) query = query.startAfter(lastDoc);

        const snap = await query.get();
        if (snap.empty) break;

        await Promise.all(snap.docs.map(async (userDoc) => {
          const user = userDoc.data();
          if (!user?.fcmToken && (!user?.deviceTokens || user.deviceTokens.length === 0)) return;

          await notifyUser(userDoc.id, {
            type: "weeklyCheckin",
            title: "✦ Weekly Check-in",
            body: "How is your faith walk this week? Take 2 minutes to reflect.",
            targetId: "walkwithchrist",
            targetType: "resource",
            deepLink: "amen://resources/walkwithchrist",
            channelId: "reminders",
          });
        }));

        lastDoc = snap.docs[snap.docs.length - 1];
        if (snap.docs.length < batchSize) break;
      }

      console.log("✅ Weekly check-in notifications sent");
    } catch (err) {
      console.error("❌ weeklyCheckin error:", err);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// TRIGGER 5: Community Digest (Friday 6:00 PM ET)
// Surfaces top 3 posts this week from the discoverFeed collection
// ─────────────────────────────────────────────────────────────────────────────

exports.communityDigest = onSchedule(
  {schedule: "every friday 18:00", timeZone: "America/New_York"},
  async () => {
    try {
      const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
      const topPosts = await db.collection("discoverFeed")
        .orderBy("discoverScore", "desc")
        .where("createdAt", ">=", weekAgo)
        .limit(3)
        .get();

      const postCount = topPosts.size;
      const bodyText = postCount > 0
        ? `${postCount} powerful ${postCount === 1 ? "post" : "posts"} are trending in your community`
        : "Catch up on what your community has been sharing this week";

      let lastDoc = null;
      const batchSize = 500;

      while (true) {
        let query = db.collection("users")
          .where("notificationSettings.communityUpdates", "!=", false)
          .limit(batchSize);
        if (lastDoc) query = query.startAfter(lastDoc);

        const snap = await query.get();
        if (snap.empty) break;

        await Promise.all(snap.docs.map(async (userDoc) => {
          await notifyUser(userDoc.id, {
            type: "communityDigest",
            title: "🌟 This Week in AMEN",
            body: bodyText,
            targetId: "discover",
            targetType: "feed",
            deepLink: "amen://discover",
            channelId: "digest",
          });
        }));

        lastDoc = snap.docs[snap.docs.length - 1];
        if (snap.docs.length < batchSize) break;
      }

      console.log("✅ Community digest sent");
    } catch (err) {
      console.error("❌ communityDigest error:", err);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// TRIGGER 6: Berean Daily Scripture Insight (daily 7:00 AM ET)
// ─────────────────────────────────────────────────────────────────────────────

const DAILY_VERSES = [
  {text: "Be still, and know that I am God.", ref: "Psalm 46:10"},
  {text: "I can do all things through Christ who strengthens me.", ref: "Philippians 4:13"},
  {text: "The Lord is my shepherd; I shall not want.", ref: "Psalm 23:1"},
  {text: "For God so loved the world that he gave his one and only Son.", ref: "John 3:16"},
  {text: "Trust in the Lord with all your heart.", ref: "Proverbs 3:5"},
  {text: "The steadfast love of the Lord never ceases.", ref: "Lamentations 3:22"},
  {text: "Be strong and courageous. Do not be afraid.", ref: "Joshua 1:9"},
];

exports.bereanDailyInsight = onSchedule(
  {schedule: "every day 07:00", timeZone: "America/New_York"},
  async () => {
    try {
      const today = DAILY_VERSES[new Date().getDay() % DAILY_VERSES.length];

      let lastDoc = null;
      const batchSize = 500;

      while (true) {
        let query = db.collection("users")
          .where("notificationSettings.bereanInsights", "!=", false)
          .limit(batchSize);
        if (lastDoc) query = query.startAfter(lastDoc);

        const snap = await query.get();
        if (snap.empty) break;

        await Promise.all(snap.docs.map(async (userDoc) => {
          await notifyUser(userDoc.id, {
            type: "bereanInsight",
            title: `✦ ${today.ref}`,
            body: `"${today.text}"`,
            targetId: "berean",
            targetType: "ai",
            deepLink: "amen://berean",
            channelId: "daily",
          });
        }));

        lastDoc = snap.docs[snap.docs.length - 1];
        if (snap.docs.length < batchSize) break;
      }

      console.log("✅ Berean daily insight sent");
    } catch (err) {
      console.error("❌ bereanDailyInsight error:", err);
    }
  }
);
