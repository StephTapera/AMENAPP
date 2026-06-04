const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const db = admin.firestore();

/**
 * Helper: check user notification preference before sending push.
 * Always writes to in-app notification center regardless of preference.
 */
async function getUserNotificationPreference(uid, key) {
  const doc = await db.doc(`users/${uid}/settings/notifications`).get();
  if (!doc.exists) return true;
  const data = doc.data();
  return data[key] !== false;
}

/**
 * onPrayerAnswered — HTTP callable
 * Notifies all intercessors when a prayer is answered.
 */
exports.onPrayerAnswered = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = request.auth.uid;
  const { prayerPostId, testimonyPostId } = request.data;
  if (!prayerPostId || !testimonyPostId) {
    throw new HttpsError("invalid-argument", "Missing required fields");
  }
  // Use the authenticated uid as the author — callers cannot impersonate others.
  const authorId = uid;

  // Gather intercessors from witnesses
  const witnessSnap = await db
    .collection("witnesses").doc(prayerPostId)
    .collection("active").get();
  const witnessUids = witnessSnap.docs.map(d => d.data().uid).filter(Boolean);

  // Gather comment uids
  const commentSnap = await db
    .collection("posts").doc(prayerPostId)
    .collection("comments").get();
  const commentUids = commentSnap.docs.map(d => d.data().authorId).filter(Boolean);

  // Merge + deduplicate + remove author
  const allUids = [...new Set([...witnessUids, ...commentUids])].filter(uid => uid !== authorId);

  // Fetch pinned scriptures on the post
  const postDoc = await db.collection("posts").doc(prayerPostId).get();
  const pinnedScriptures = postDoc.data()?.pinnedScriptures || [];
  const scriptureAuthorIds = pinnedScriptures.map(s => s.authorId).filter(Boolean);

  const now = admin.firestore.FieldValue.serverTimestamp();

  for (const uid of allUids) {
    const sendPush = await getUserNotificationPreference(uid, "prayerAnswered");
    const isScriptureAuthor = scriptureAuthorIds.includes(uid);

    // Write in-app notification always
    await db.collection("notifications").doc(uid)
      .collection("items").add({
        type: "answeredPrayer",
        testimonyPostId,
        prayerPostId,
        createdAt: now,
        read: false
      });

    if (sendPush) {
      const userDoc = await db.collection("users").doc(uid).get();
      const tokens = userDoc.data()?.fcmTokens || [];
      if (tokens.length === 0) continue;

      const messages = [{
        notification: {
          title: "A prayer was answered",
          body: "A prayer you stood with was answered — read the testimony",
        },
        data: { type: "answeredPrayer", testimonyPostId },
        tokens,
      }];

      // Extra notification for scripture authors
      if (isScriptureAuthor) {
        messages.push({
          notification: {
            title: "A prayer was answered",
            body: "The verse you covered this prayer with was confirmed by a testimony",
          },
          data: { type: "scriptureConfirmed", testimonyPostId },
          tokens,
        });
      }

      for (const msg of messages) {
        await admin.messaging().sendEachForMulticast(msg).catch(() => {});
      }
    }
  }

  return { notified: allUids.length };
});

/**
 * computePrayerFulfillmentInsight — scheduled daily
 * Computes keyword-grouped prayer fulfillment stats and writes insight docs
 * to each open prayer post that matches.
 */
exports.computePrayerFulfillmentInsight = onSchedule(
  { schedule: "every 24 hours", timeoutSeconds: 300 },
  async () => {
    const keywordGroups = {
      job: ["job", "work", "employment"],
      health: ["health", "healing", "sick"],
      relationship: ["relationship", "marriage", "family"],
      finance: ["finance", "money", "provision"],
      guidance: ["guidance", "direction", "purpose"],
      peace: ["peace", "anxiety", "fear"],
      school: ["school", "exams", "graduation"],
    };

    // P1 FIX #7: cursor-based pagination — answered and open post queries now
    // page through results in chunks of PAGE_SIZE instead of fetching the entire
    // collection in one unbounded read. Each keyword group reuses the same
    // answered-posts page results, then paginates the open-posts write loop
    // with batched Firestore writes (500 ops per batch).
    const PAGE_SIZE = 500;

    for (const [keyword, terms] of Object.entries(keywordGroups)) {
      // ── Paginate answered prayer posts ──────────────────────────────────────
      const matched = [];
      let lastAnsweredDoc = null;
      while (true) {
        let q = db.collection("posts")
          .where("category", "==", "prayer")
          .where("prayerStatus", "==", "answered")
          .orderBy("createdAt", "desc")
          .limit(PAGE_SIZE);
        if (lastAnsweredDoc) q = q.startAfter(lastAnsweredDoc);
        const snap = await q.get();
        snap.docs.forEach((doc) => {
          const content = (doc.data().content || "").toLowerCase();
          if (terms.some((t) => content.includes(t))) matched.push(doc);
        });
        if (snap.docs.length < PAGE_SIZE) break;
        lastAnsweredDoc = snap.docs[snap.docs.length - 1];
      }

      if (matched.length === 0) continue;

      const days = matched.map((doc) => {
        const created  = doc.data().createdAt?.toDate();
        const answered = doc.data().answeredAt?.toDate() || new Date();
        if (!created) return null;
        return Math.round((answered - created) / (1000 * 60 * 60 * 24));
      }).filter((d) => d !== null);

      if (days.length === 0) continue;

      const avg = Math.round(days.reduce((a, b) => a + b, 0) / days.length);
      const min = Math.min(...days);
      const max = Math.max(...days);

      await db.collection("prayerInsights").doc(keyword).set({
        keyword,
        answeredCount: matched.length,
        averageDays:   avg,
        minDays:       min,
        maxDays:       max,
        updatedAt:     admin.firestore.FieldValue.serverTimestamp(),
      });

      const insightText = `${matched.length} ${keyword}-related prayers answered in this community — avg ${avg} days`;

      // ── Paginate open prayer posts + batched writes ──────────────────────────
      let lastOpenDoc = null;
      while (true) {
        let oq = db.collection("posts")
          .where("category", "==", "prayer")
          .where("prayerStatus", "in", ["praying", "believing"])
          .orderBy("createdAt", "desc")
          .limit(PAGE_SIZE);
        if (lastOpenDoc) oq = oq.startAfter(lastOpenDoc);
        const openSnap = await oq.get();

        const batch = db.batch();
        let batchCount = 0;
        for (const doc of openSnap.docs) {
          const content = (doc.data().content || "").toLowerCase();
          if (terms.some((t) => content.includes(t))) {
            batch.set(doc.ref.collection("insight").doc("community"), {
              insightText,
              keyword,
              answeredCount: matched.length,
              averageDays:   avg,
            });
            batchCount++;
          }
        }
        if (batchCount > 0) await batch.commit();
        if (openSnap.docs.length < PAGE_SIZE) break;
        lastOpenDoc = openSnap.docs[openSnap.docs.length - 1];
      }
    }

    console.log("computePrayerFulfillmentInsight: complete");
  }
);

/**
 * trackTestimonyRipple — scheduled daily
 * Detects whether viewers of a testimony post subsequently created prayer/testimony posts
 * within 7 days, indicating the testimony sparked spiritual action (ripple effect).
 */
exports.trackTestimonyRipple = onSchedule(
  { schedule: "every 24 hours", timeoutSeconds: 300 },
  async () => {
    const now = new Date();
    const oneDayAgo  = new Date(now - 86400000);
    const eightDaysAgo = new Date(now - 8 * 86400000);

    const snap = await db.collection("posts")
      .where("category", "==", "testimonies")
      .where("createdAt", ">", admin.firestore.Timestamp.fromDate(eightDaysAgo))
      .where("createdAt", "<", admin.firestore.Timestamp.fromDate(oneDayAgo))
      .where("rippleTracked", "!=", true)
      .get();

    for (const doc of snap.docs) {
      const postId = doc.id;
      const postData = doc.data();
      const authorId = postData.authorId;
      const testimonyCreatedAt = postData.createdAt?.toDate();
      if (!testimonyCreatedAt) continue;

      // Fetch witnesses who visited
      const historySnap = await db.collection("witnesses").doc(postId)
        .collection("history").get();
      const visitorUids = historySnap.docs.map(d => d.data().uid).filter(Boolean);

      if (visitorUids.length === 0) {
        await doc.ref.update({ rippleTracked: true, rippleCount: 0 });
        continue;
      }

      // Find downstream posts by visitors in 7 days after testimony.
      // P0 FIX #3: replaced N sequential per-uid queries with batched "in" queries
      // (max 30 UIDs per batch — Firestore limit), reducing Firestore reads from
      // O(visitorUids.length) to O(ceil(visitorUids.length / 30)).
      const sevenDaysAfter = new Date(testimonyCreatedAt.getTime() + 7 * 86400000);
      let rippleUids = new Set();
      const createdAfter  = admin.firestore.Timestamp.fromDate(testimonyCreatedAt);
      const createdBefore = admin.firestore.Timestamp.fromDate(sevenDaysAfter);

      const IN_LIMIT = 30; // Firestore "in" operator max
      for (let i = 0; i < visitorUids.length; i += IN_LIMIT) {
        const chunk = visitorUids.slice(i, i + IN_LIMIT);
        const downstream = await db.collection("posts")
          .where("authorId", "in", chunk)
          .where("createdAt", ">", createdAfter)
          .where("createdAt", "<", createdBefore)
          .get();
        downstream.docs.forEach((d) => {
          if (["prayer", "testimonies"].includes(d.data().category)) {
            rippleUids.add(d.data().authorId);
          }
        });
      }

      const rippleCount = rippleUids.size;
      const update = { rippleCount, rippleTracked: true, rippleUpdatedAt: admin.firestore.FieldValue.serverTimestamp() };
      await doc.ref.update(update);

      // Push if rippleCount >= 5 and not yet notified
      if (rippleCount >= 5 && !postData.rippleNotified) {
        const sendPush = await getUserNotificationPreference(authorId, "testimonyRipple");
        if (sendPush) {
          const userDoc = await db.collection("users").doc(authorId).get();
          const tokens = userDoc.data()?.fcmTokens || [];
          if (tokens.length > 0) {
            await admin.messaging().sendEachForMulticast({
              notification: {
                title: "Your testimony is still moving people",
                body: `Your testimony sparked spiritual action in ${rippleCount} people this week`,
              },
              data: { type: "ripple", testimonyPostId: postId },
              tokens,
            }).catch(() => {});
          }
        }
        // Always write in-app notification
        await db.collection("notifications").doc(authorId)
          .collection("items").add({
            type: "ripple",
            testimonyPostId: postId,
            rippleCount,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
          });
        await doc.ref.update({ rippleNotified: true });
      }
    }

    console.log("trackTestimonyRipple: complete");
  }
);
