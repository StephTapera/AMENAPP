/**
 * ML Content Pipeline — onPostCreated / onPostDeleted
 *
 * Runs parallel ML analysis on every new post:
 * language detection, sentiment, classification, embeddings,
 * crisis detection, scripture matching, virality baseline.
 */

const admin = require("firebase-admin");
const { onDocumentCreated, onDocumentDeleted, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const {
  hfInference, pineconeUpsert, pineconeQuery,
  pineconeDelete, logFunction, cosineSimilarity,
} = require("./mlClients");

const db = admin.firestore();

// ═══════════════════════════════════════════
// onPostCreated — Full ML Pipeline
// ═══════════════════════════════════════════

const onPostCreatedML = onDocumentCreated(
  { document: "posts/{postId}", region: "us-central1" },
  async (event) => {
    const startMs = Date.now();
    const postId = event.params.postId;
    const data = event.data?.data();
    if (!data) return;

    const content = data.content || "";
    const authorId = data.authorId || "";

    if (content.length < 10) {
      console.log(`[onPostCreatedML] Post ${postId} too short for ML — skipping`);
      return;
    }

    try {
      // Run all ML tasks in parallel
      const [
        languageResult,
        sentimentResult,
        classificationResult,
        embeddingResult,
        crisisResult,
      ] = await Promise.allSettled([
        // 1. Language detection
        hfInference("papluca/xlm-roberta-base-language-detection", content),

        // 2. Sentiment analysis
        hfInference("cardiffnlp/twitter-roberta-base-sentiment-latest", content),

        // 3. Content classification (zero-shot)
        hfInference("facebook/bart-large-mnli", content, {
          parameters: {
            candidate_labels: [
              "encouraging", "questioning", "sharing", "celebrating",
              "grieving", "teaching", "testimony", "prayer",
            ],
          },
        }),

        // 4. Embedding generation
        hfInference("sentence-transformers/all-MiniLM-L6-v2", content),

        // 5. Crisis signal detection (using sentiment as proxy)
        hfInference("cardiffnlp/twitter-roberta-base-sentiment-latest", content),
      ]);

      // Parse results
      const mlData = {};

      // Language
      if (languageResult.status === "fulfilled" && languageResult.value) {
        const langs = Array.isArray(languageResult.value) ? languageResult.value[0] : languageResult.value;
        if (Array.isArray(langs)) {
          const topLang = langs.reduce((a, b) => a.score > b.score ? a : b, { score: 0 });
          mlData.language = topLang.label || "en";
          mlData.languageConfidence = topLang.score || 0;
        }
      }

      // Sentiment
      if (sentimentResult.status === "fulfilled" && sentimentResult.value) {
        const sentiments = Array.isArray(sentimentResult.value) ? sentimentResult.value[0] : sentimentResult.value;
        if (Array.isArray(sentiments)) {
          const topSentiment = sentiments.reduce((a, b) => a.score > b.score ? a : b, { score: 0 });
          mlData.sentiment = topSentiment.label || "neutral";
          mlData.sentimentScore = topSentiment.score || 0;
        }
      }

      // Classification
      if (classificationResult.status === "fulfilled" && classificationResult.value) {
        const cls = classificationResult.value;
        if (cls.labels && cls.scores) {
          mlData.classification = cls.labels[0];
          mlData.classificationScore = cls.scores[0];
        }
      }

      // Embedding → Pinecone
      let embeddingVector = null;
      if (embeddingResult.status === "fulfilled" && embeddingResult.value) {
        embeddingVector = Array.isArray(embeddingResult.value)
          ? embeddingResult.value
          : embeddingResult.value?.embedding || null;

        // Flatten nested arrays
        if (embeddingVector && Array.isArray(embeddingVector[0])) {
          embeddingVector = embeddingVector[0];
        }
      }

      // Crisis detection — check for negative sentiment + keyword signals
      const crisisKeywords = [
        "want to die", "end it all", "no reason to live", "can't go on",
        "kill myself", "suicide", "self harm", "hurt myself",
        "nobody cares", "completely alone", "giving up",
      ];
      const lowerContent = content.toLowerCase();
      const hasCrisisKeyword = crisisKeywords.some((kw) => lowerContent.includes(kw));
      const isNegativeSentiment = mlData.sentiment === "negative" && (mlData.sentimentScore || 0) > 0.7;

      if (hasCrisisKeyword || (isNegativeSentiment && lowerContent.includes("help"))) {
        const crisisSeverity = hasCrisisKeyword ? "high" : "medium";
        mlData.hasCrisisSignal = true;
        mlData.crisisSeverity = crisisSeverity;

        // Write pastoral alert
        await db.collection("pastoralAlerts").add({
          postId,
          authorId,
          severity: crisisSeverity,
          detectedAt: admin.firestore.FieldValue.serverTimestamp(),
          status: "unreviewed",
          signals: crisisKeywords.filter((kw) => lowerContent.includes(kw)),
        });

        console.log(`[Crisis] ${crisisSeverity} signal detected for post ${postId}`);
      }

      // Scripture sentiment match via Pinecone
      if (embeddingVector && embeddingVector.length > 0) {
        const scriptureMatches = await pineconeQuery(
          "scripture-embeddings",
          embeddingVector,
          3,
          // Filter to match emotional tone
          mlData.sentiment === "negative"
            ? { tone: { $in: ["comfort", "hope", "encouragement"] } }
            : undefined
        );

        if (scriptureMatches.length > 0) {
          mlData.suggestedScriptures = scriptureMatches.map((m) => ({
            reference: m.metadata?.reference || m.id,
            score: m.score,
            text: m.metadata?.text || "",
          }));
        }
      }

      // Virality baseline
      try {
        const authorDoc = await db.collection("users").document(authorId).get();
        const followerCount = authorDoc.data()?.followerCount || 0;
        const postsSnap = await db.collection("posts")
          .where("authorId", "==", authorId)
          .orderBy("createdAt", "desc")
          .limit(20)
          .get();
        let avgEngagement = 0;
        if (!postsSnap.empty) {
          const total = postsSnap.docs.reduce((sum, doc) => {
            const d = doc.data();
            return sum + (d.amenCount || 0) + (d.commentCount || 0) + (d.repostCount || 0);
          }, 0);
          avgEngagement = total / postsSnap.docs.length;
        }
        mlData.viralityBaseline = (followerCount * 0.3) + (avgEngagement * 0.7);
      } catch (e) {
        mlData.viralityBaseline = 0;
      }

      // Update post with ML data
      await db.collection("posts").doc(postId).update({
        "ml": mlData,
      });

      // Upsert to Pinecone content index
      if (embeddingVector && embeddingVector.length > 0) {
        await pineconeUpsert("content-embeddings", [{
          id: postId,
          values: embeddingVector,
          metadata: {
            userId: authorId,
            type: data.category || "openTable",
            language: mlData.language || "en",
            sentiment: mlData.sentiment || "neutral",
            classification: mlData.classification || "",
            createdAt: new Date().toISOString(),
            hasCrisisSignal: mlData.hasCrisisSignal || false,
          },
        }]);
      }

      logFunction("onPostCreatedML", {
        postId,
        durationMs: Date.now() - startMs,
        mlFields: Object.keys(mlData),
        hasEmbedding: !!embeddingVector,
      });
    } catch (err) {
      logFunction("onPostCreatedML", {
        postId,
        durationMs: Date.now() - startMs,
        error: err.message,
      });
    }
  }
);

// ═══════════════════════════════════════════
// onPostDeleted — Cleanup
// ═══════════════════════════════════════════

const onPostDeletedML = onDocumentDeleted(
  { document: "posts/{postId}", region: "us-central1" },
  async (event) => {
    const postId = event.params.postId;
    const data = event.data?.data();
    const authorId = data?.authorId;

    try {
      // 1. Delete from Pinecone
      await pineconeDelete("content-embeddings", [postId]);

      // 2. Delete subcollections
      const subcollections = ["comments", "reactions", "bookmarks"];
      for (const sub of subcollections) {
        const snap = await db.collection("posts").doc(postId).collection(sub).limit(500).get();
        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        if (!snap.empty) await batch.commit();
      }

      // 3. Delete media from Storage
      if (data?.imageURLs?.length > 0) {
        const storage = admin.storage().bucket();
        for (const url of data.imageURLs) {
          try {
            const path = decodeURIComponent(url.split("/o/")[1]?.split("?")[0] || "");
            if (path) await storage.file(path).delete().catch(() => {});
          } catch (e) { /* ignore missing files */ }
        }
      }

      // 4. Update author post count
      if (authorId) {
        await db.collection("users").doc(authorId).update({
          postCount: admin.firestore.FieldValue.increment(-1),
        }).catch(() => {});
      }

      // 5. Log deletion
      await db.collection("auditTrail").add({
        action: "post_deleted",
        postId,
        authorId: authorId || "unknown",
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      logFunction("onPostDeletedML", { postId });
    } catch (err) {
      logFunction("onPostDeletedML", { postId, error: err.message });
    }
  }
);

// ═══════════════════════════════════════════
// computeViralityScore — Engagement velocity
// ═══════════════════════════════════════════

const computeViralityScore = onDocumentUpdated(
  { document: "posts/{postId}", region: "us-central1" },
  async (event) => {
    const postId = event.params.postId;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    // Only fire when engagement changes
    const engagementBefore = (before.amenCount || 0) + (before.commentCount || 0) + (before.repostCount || 0);
    const engagementAfter = (after.amenCount || 0) + (after.commentCount || 0) + (after.repostCount || 0);
    if (engagementAfter <= engagementBefore) return;

    const createdAt = after.createdAt?.toDate?.() || new Date();
    const minutesSincePublished = Math.max(1, (Date.now() - createdAt.getTime()) / 60000);
    const engagementDelta = engagementAfter - engagementBefore;
    const velocity = engagementDelta / minutesSincePublished;

    const baseline = after.ml?.viralityBaseline || 1;
    const viralityScore = Math.min(1.0, velocity / Math.max(baseline, 1));

    const updates = { "ml.viralityScore": viralityScore };

    // Check if viral (velocity significantly above baseline)
    if (velocity > baseline * 2 && engagementAfter >= 10 && !after.ml?.isViral) {
      updates["ml.isViral"] = true;

      // Write to viral boost collection
      await db.collection("viralBoost").doc(postId).set({
        postId,
        authorId: after.authorId,
        velocity,
        engagementCount: engagementAfter,
        detectedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Notify author
      const authorId = after.authorId;
      if (authorId) {
        await db.collection("users").doc(authorId).collection("notifications").add({
          type: "viral_post",
          postId,
          title: "Your post is resonating",
          body: `Your post is getting ${engagementAfter} interactions and growing fast.`,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          read: false,
        });
      }

      console.log(`[Virality] Post ${postId} detected as viral (velocity: ${velocity.toFixed(2)})`);
    }

    await db.collection("posts").doc(postId).update(updates).catch(() => {});
  }
);

// ═══════════════════════════════════════════
// scheduledPostPublisher — Every 5 minutes
// ═══════════════════════════════════════════

const scheduledPostPublisherML = onSchedule(
  { schedule: "every 5 minutes", region: "us-central1" },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db.collection("posts")
      .where("status", "==", "scheduled")
      .where("scheduledAt", "<=", now)
      .limit(50)
      .get();

    if (snap.empty) return;

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.update(doc.ref, {
        status: "published",
        publishedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    console.log(`[ScheduledPost] Published ${snap.docs.length} scheduled posts`);
  }
);

// ═══════════════════════════════════════════
// scoreContentAuthenticity
// ═══════════════════════════════════════════

async function scoreContentAuthenticity(content, authorId) {
  let score = 0.5; // Neutral default
  const lower = content.toLowerCase();

  // Personal language signals (genuine)
  const personalIndicators = [
    "i struggled", "god showed me", "my journey", "i realized",
    "honestly", "vulnerable", "real talk", "truth is",
  ];
  const personalMatches = personalIndicators.filter((p) => lower.includes(p)).length;
  score += personalMatches * 0.1;

  // Performative signals
  const performativeIndicators = [
    "like and share", "follow for", "tag someone",
    "drop an amen", "type yes if", "share this",
  ];
  const performativeMatches = performativeIndicators.filter((p) => lower.includes(p)).length;
  score -= performativeMatches * 0.15;

  // Check author's posting variety
  try {
    const recentPosts = await db.collection("posts")
      .where("authorId", "==", authorId)
      .orderBy("createdAt", "desc")
      .limit(10)
      .get();

    if (recentPosts.docs.length >= 5) {
      const uniqueStarts = new Set(
        recentPosts.docs.map((d) => (d.data().content || "").substring(0, 20))
      );
      const variety = uniqueStarts.size / Math.min(10, recentPosts.docs.length);
      score += (variety - 0.5) * 0.2;
    }
  } catch (e) { /* ignore */ }

  return Math.max(0, Math.min(1, score));
}

module.exports = {
  onPostCreatedML,
  onPostDeletedML,
  computeViralityScore,
  scheduledPostPublisherML,
  scoreContentAuthenticity,
};
