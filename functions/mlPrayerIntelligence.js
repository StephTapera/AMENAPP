/**
 * ML Prayer & Spiritual Intelligence Functions
 *
 * Intercessor matching, testimony-prayer linking,
 * spiritual gift detection, personal verse engine,
 * scripture sentiment match.
 */

const admin = require("firebase-admin");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall } = require("firebase-functions/v2/https");
const {
  hfInference, pineconeUpsert, pineconeQuery,
  logFunction, checkRateLimit, cosineSimilarity, sleep,
} = require("./mlClients");

const db = admin.firestore();

// ═══════════════════════════════════════════
// matchIntercessors — On prayer request created
// ═══════════════════════════════════════════

const matchIntercessors = onDocumentCreated(
  { document: "posts/{postId}", region: "us-central1" },
  async (event) => {
    const postId = event.params.postId;
    const data = event.data?.data();
    if (!data) return;

    // Only fire for prayer requests
    const category = (data.category || "").toLowerCase();
    if (category !== "prayer") return;

    const content = data.content || "";
    const requesterId = data.authorId || "";
    const isAnonymous = data.isAnonymous || false;

    if (content.length < 15) return;

    const startMs = Date.now();

    try {
      // 1. Generate embedding for prayer request
      const embedding = await hfInference(
        "sentence-transformers/all-MiniLM-L6-v2",
        content
      );

      if (!embedding || !Array.isArray(embedding)) return;
      const vector = Array.isArray(embedding[0]) ? embedding[0] : embedding;

      // 2. Query Pinecone for users with aligned interests
      const matches = await pineconeQuery(
        "user-interest-embeddings",
        vector,
        10,
        {
          userId: { $ne: requesterId },
        }
      );

      if (matches.length === 0) return;

      // 3. Additional scoring — prayer warrior activity
      const scoredMatches = [];
      for (const match of matches.slice(0, 5)) {
        const matchUserId = match.metadata?.userId || match.id;
        if (matchUserId === requesterId) continue;

        // Check if user is active and has prayed for others
        let activityBoost = 0;
        try {
          const recentPrayers = await db.collection("posts")
            .where("authorId", "==", matchUserId)
            .where("category", "==", "prayer")
            .orderBy("createdAt", "desc")
            .limit(5)
            .get();
          activityBoost = Math.min(0.3, recentPrayers.docs.length * 0.06);
        } catch (e) { /* ignore */ }

        scoredMatches.push({
          userId: matchUserId,
          score: (match.score || 0) + activityBoost,
          vectorScore: match.score || 0,
        });
      }

      // Sort by combined score and take top 3
      scoredMatches.sort((a, b) => b.score - a.score);
      const topMatches = scoredMatches.slice(0, 3);

      // 4. Send silent notifications to matched intercessors
      for (const m of topMatches) {
        await db.collection("users").doc(m.userId).collection("notifications").add({
          type: "intercessor_match",
          postId,
          title: "Someone needs prayer",
          body: "Someone in your community needs prayer in an area you care deeply about.",
          // Never share requester info if anonymous
          requesterId: isAnonymous ? null : requesterId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          read: false,
          silent: true,
        });
      }

      // 5. Log match
      await db.collection("intercessorMatches").add({
        postId,
        requesterId,
        matchedUserIds: topMatches.map((m) => m.userId),
        scores: topMatches.map((m) => m.score),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      logFunction("matchIntercessors", {
        postId,
        matchCount: topMatches.length,
        durationMs: Date.now() - startMs,
      });
    } catch (err) {
      logFunction("matchIntercessors", { postId, error: err.message, durationMs: Date.now() - startMs });
    }
  }
);

// ═══════════════════════════════════════════
// detectTestimonyOutcome — Weekly
// ═══════════════════════════════════════════

const detectTestimonyOutcome = onSchedule(
  { schedule: "0 3 * * 0", region: "us-central1", timeoutSeconds: 540 },
  async () => {
    const startMs = Date.now();
    const sixMonthsAgo = new Date(Date.now() - 180 * 86400000);
    let linked = 0;

    const users = await db.collection("users")
      .where("lastActiveAt", ">=", admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 30 * 86400000)
      ))
      .select("lastActiveAt")
      .limit(200)
      .get();

    for (const userDoc of users.docs) {
      const uid = userDoc.id;

      try {
        // Fetch prayers
        const prayers = await db.collection("posts")
          .where("authorId", "==", uid)
          .where("category", "==", "prayer")
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(sixMonthsAgo))
          .orderBy("createdAt", "desc")
          .limit(20)
          .get();

        if (prayers.empty) continue;

        // Fetch testimonies
        const testimonies = await db.collection("posts")
          .where("authorId", "==", uid)
          .where("category", "==", "testimonies")
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(sixMonthsAgo))
          .orderBy("createdAt", "desc")
          .limit(20)
          .get();

        if (testimonies.empty) continue;

        // Generate embeddings for both sets
        const prayerTexts = prayers.docs.map((d) => d.data().content || "").filter((t) => t.length > 10);
        const testimonyTexts = testimonies.docs.map((d) => d.data().content || "").filter((t) => t.length > 10);

        if (prayerTexts.length === 0 || testimonyTexts.length === 0) continue;

        const [prayerEmbeddings, testimonyEmbeddings] = await Promise.all([
          hfInference("sentence-transformers/all-MiniLM-L6-v2", prayerTexts),
          hfInference("sentence-transformers/all-MiniLM-L6-v2", testimonyTexts),
        ]);

        if (!prayerEmbeddings || !testimonyEmbeddings) continue;

        // Compare each prayer to each testimony
        for (let pi = 0; pi < prayerEmbeddings.length; pi++) {
          for (let ti = 0; ti < testimonyEmbeddings.length; ti++) {
            const pVec = Array.isArray(prayerEmbeddings[pi]) ? prayerEmbeddings[pi] : null;
            const tVec = Array.isArray(testimonyEmbeddings[ti]) ? testimonyEmbeddings[ti] : null;
            if (!pVec || !tVec) continue;

            const similarity = cosineSimilarity(pVec, tVec);

            if (similarity > 0.75) {
              const prayerDoc = prayers.docs[pi];
              const testimonyDoc = testimonies.docs[ti];
              const prayerDate = prayerDoc.data().createdAt?.toDate?.();
              const testimonyDate = testimonyDoc.data().createdAt?.toDate?.();

              // Testimony must be after prayer
              if (!prayerDate || !testimonyDate || testimonyDate <= prayerDate) continue;

              // Check if already linked
              const existing = prayerDoc.data().linkedTestimonyId;
              if (existing) continue;

              // Link them
              await prayerDoc.ref.update({ linkedTestimonyId: testimonyDoc.id });

              await db.collection("users").doc(uid).collection("answeredPrayers").add({
                prayerId: prayerDoc.id,
                testimonyId: testimonyDoc.id,
                similarity,
                linkedAt: admin.firestore.FieldValue.serverTimestamp(),
              });

              // Notify user
              await db.collection("users").doc(uid).collection("notifications").add({
                type: "answered_prayer",
                title: "God answered this prayer",
                body: "It looks like a testimony you shared may be connected to a prayer you prayed.",
                prayerPostId: prayerDoc.id,
                testimonyPostId: testimonyDoc.id,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                read: false,
              });

              linked++;
            }
          }
        }
      } catch (err) {
        console.error(`[TestimonyOutcome] Error for user ${uid}:`, err.message);
      }

      // Throttle HF calls
      await sleep(1000);
    }

    logFunction("detectTestimonyOutcome", {
      durationMs: Date.now() - startMs,
      linked,
    });
  }
);

// ═══════════════════════════════════════════
// detectSpiritualGift — Monthly
// ═══════════════════════════════════════════

const detectSpiritualGift = onSchedule(
  { schedule: "0 4 1 * *", region: "us-central1", timeoutSeconds: 540 },
  async () => {
    const startMs = Date.now();
    const ninetyDaysAgo = new Date(Date.now() - 90 * 86400000);

    const users = await db.collection("users")
      .where("lastActiveAt", ">=", admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 30 * 86400000)
      ))
      .select("lastActiveAt")
      .limit(300)
      .get();

    let detected = 0;

    // Gift signal mappings
    const giftSignals = {
      teaching: { categories: ["openTable"], keywords: ["teach", "explain", "study", "theology", "doctrine"] },
      encouragement: { categories: ["encouragement"], keywords: ["encourage", "uplift", "support", "you can"] },
      mercy: { categories: ["prayer"], keywords: ["compassion", "hurt", "suffering", "empathy"] },
      giving: { keywords: ["give", "generous", "tithe", "donate", "bless"] },
      faith: { categories: ["testimonies"], keywords: ["trust", "believe", "miracle", "impossible"] },
      intercession: { categories: ["prayer"], keywords: ["pray", "intercede", "warfare", "covering"] },
      wisdom: { keywords: ["wise", "counsel", "advice", "discernment", "guide"] },
      leadership: { keywords: ["lead", "organize", "vision", "strategy", "build"] },
      prophecy: { keywords: ["prophetic", "vision", "revelation", "discern"] },
    };

    for (const userDoc of users.docs) {
      const uid = userDoc.id;

      try {
        // Fetch 90-day posts and comments
        const posts = await db.collection("posts")
          .where("authorId", "==", uid)
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(ninetyDaysAgo))
          .limit(50)
          .get();

        if (posts.docs.length < 5) continue;

        const allContent = posts.docs.map((d) => (d.data().content || "").toLowerCase()).join(" ");
        const categories = posts.docs.map((d) => d.data().category || "");

        // Score each gift
        const giftScores = {};
        for (const [gift, signals] of Object.entries(giftSignals)) {
          let score = 0;

          // Keyword matches
          const keywordMatches = (signals.keywords || []).filter((k) => allContent.includes(k)).length;
          score += keywordMatches * 0.15;

          // Category alignment
          if (signals.categories) {
            const catMatches = categories.filter((c) => signals.categories.includes(c)).length;
            score += (catMatches / posts.docs.length) * 0.5;
          }

          giftScores[gift] = Math.min(1.0, score);
        }

        // Find top gift
        const sorted = Object.entries(giftScores).sort((a, b) => b[1] - a[1]);
        const topGift = sorted[0];

        if (topGift && topGift[1] >= 0.4) {
          await db.collection("users").doc(uid).update({
            "spiritualGifts.detected": {
              gift: topGift[0],
              confidence: topGift[1],
              detectedAt: admin.firestore.FieldValue.serverTimestamp(),
              topThree: sorted.slice(0, 3).map(([g, s]) => ({ gift: g, confidence: s })),
            },
          });

          // Notify user if high confidence
          if (topGift[1] >= 0.6) {
            await db.collection("users").doc(uid).collection("notifications").add({
              type: "spiritual_gift_detected",
              title: "Your community sees this gift in you",
              body: `Based on how you engage, your gift of ${topGift[0]} shines through.`,
              gift: topGift[0],
              confidence: topGift[1],
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              read: false,
            });
            detected++;
          }
        }
      } catch (err) {
        console.error(`[SpiritualGift] Error for user ${uid}:`, err.message);
      }
    }

    logFunction("detectSpiritualGift", {
      durationMs: Date.now() - startMs,
      detected,
    });
  }
);

// ═══════════════════════════════════════════
// computeScriptureSentimentMatch — HTTPS callable
// ═══════════════════════════════════════════

const computeScriptureSentimentMatch = onCall(
  { region: "us-central1" },
  async (request) => {
    const { text, userId } = request.data;
    if (!text || text.length < 10) {
      return { scriptures: [] };
    }

    const allowed = await checkRateLimit(userId || "anon", "scriptureSentiment", 10);
    if (!allowed) throw new Error("Rate limited");

    const startMs = Date.now();

    try {
      // 1. Generate embedding
      const [embedding, sentimentResult] = await Promise.all([
        hfInference("sentence-transformers/all-MiniLM-L6-v2", text),
        hfInference("cardiffnlp/twitter-roberta-base-sentiment-latest", text),
      ]);

      if (!embedding) return { scriptures: [] };

      const vector = Array.isArray(embedding[0]) ? embedding[0] : embedding;

      // 2. Determine sentiment for filtering
      let sentiment = "neutral";
      if (sentimentResult && Array.isArray(sentimentResult[0])) {
        const top = sentimentResult[0].reduce((a, b) => a.score > b.score ? a : b, { score: 0 });
        sentiment = top.label || "neutral";
      }

      // 3. Query Pinecone scripture-embeddings with sentiment filter
      const filter = {};
      if (sentiment === "negative" || sentiment === "NEGATIVE") {
        filter.tone = { $in: ["comfort", "hope", "encouragement", "peace"] };
      } else if (sentiment === "positive" || sentiment === "POSITIVE") {
        filter.tone = { $in: ["praise", "thanksgiving", "joy", "celebration"] };
      }

      const matches = await pineconeQuery(
        "scripture-embeddings",
        vector,
        5,
        Object.keys(filter).length > 0 ? filter : undefined
      );

      const scriptures = matches.slice(0, 3).map((m) => ({
        book: m.metadata?.book || "",
        chapter: m.metadata?.chapter || 0,
        verse: m.metadata?.verse || 0,
        reference: m.metadata?.reference || m.id,
        text: m.metadata?.text || "",
        relevanceScore: m.score || 0,
      }));

      logFunction("computeScriptureSentimentMatch", {
        durationMs: Date.now() - startMs,
        sentiment,
        resultCount: scriptures.length,
      });

      return { scriptures, sentiment };
    } catch (err) {
      logFunction("computeScriptureSentimentMatch", {
        durationMs: Date.now() - startMs,
        error: err.message,
      });
      return { scriptures: [], error: err.message };
    }
  }
);

// ═══════════════════════════════════════════
// generatePersonalVerseEngine — Daily 6am UTC
// ═══════════════════════════════════════════

const generatePersonalVerseEngine = onSchedule(
  { schedule: "0 6 * * *", region: "us-central1", timeoutSeconds: 540 },
  async () => {
    const startMs = Date.now();

    const users = await db.collection("users")
      .where("lastActiveAt", ">=", admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 7 * 86400000)
      ))
      .select("lastActiveAt")
      .limit(500)
      .get();

    let generated = 0;

    for (const userDoc of users.docs) {
      const uid = userDoc.id;

      try {
        // Build user scripture preference from recent activity
        const recentPosts = await db.collection("posts")
          .where("authorId", "==", uid)
          .orderBy("createdAt", "desc")
          .limit(10)
          .get();

        // Collect texts for embedding
        const texts = recentPosts.docs
          .map((d) => d.data().content || "")
          .filter((t) => t.length > 20);

        if (texts.length === 0) continue;

        // Generate embedding from recent activity
        const embedding = await hfInference(
          "sentence-transformers/all-MiniLM-L6-v2",
          texts.join(". ")
        );

        if (!embedding) continue;
        const vector = Array.isArray(embedding[0]) ? embedding[0] : embedding;

        // Query Pinecone for matching scripture
        const matches = await pineconeQuery(
          "scripture-embeddings",
          vector,
          5
        );

        if (matches.length === 0) continue;

        // Pick top match (could add diversity logic)
        const topMatch = matches[0];
        const today = new Date().toISOString().split("T")[0];

        await db.collection("users").doc(uid)
          .collection("dailyVerse")
          .doc(today)
          .set({
            reference: topMatch.metadata?.reference || topMatch.id,
            text: topMatch.metadata?.text || "",
            book: topMatch.metadata?.book || "",
            relevanceScore: topMatch.score || 0,
            generatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

        generated++;
      } catch (err) {
        console.error(`[PersonalVerse] Error for user ${uid}:`, err.message);
      }

      // Throttle
      if (generated % 20 === 0) await sleep(2000);
    }

    logFunction("generatePersonalVerseEngine", {
      durationMs: Date.now() - startMs,
      generated,
    });
  }
);

module.exports = {
  matchIntercessors,
  detectTestimonyOutcome,
  detectSpiritualGift,
  computeScriptureSentimentMatch,
  generatePersonalVerseEngine,
};
