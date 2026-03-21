/**
 * semanticEmbeddings.js — OpenAI Embedding Layer for AMEN
 *
 * All embedding work uses HuggingFace all-MiniLM-L6-v2 (384-dim) via mlClients.openaiEmbed,
 * matching the existing Pinecone index dimensions. Firestore caches every vector under
 * embeddings/{cacheKey} for 30 days so the same text is never embedded twice.
 * OpenAI (GPT-4o-mini) is used only for text generation in classifyReportedContent.
 *
 * Pinecone namespaces:
 *   scripture-embeddings    — 31K KJV Bible verses (seeded via seedBibleVersesToPinecone)
 *   testimony-embeddings    — User testimony posts (upserted on creation)
 *   prayer-partner-pool     — Active prayer-partner seekers (upserted on match request)
 *
 * Exports:
 *   seedBibleVersesToPinecone    — Admin callable: populates scripture-embeddings in batches
 *   findSimilarTestimonies       — Callable: semantic testimony matching
 *   getScriptureRecommendation   — Callable: context-aware scripture for any text
 *   matchPrayerPartners          — Callable: find prayer partners by topic similarity
 *   onTestimonyCreated           — Firestore trigger: auto-embed new testimony posts
 *   classifyReportedContent      — Firestore trigger: GPT-4o-mini toxicity on reports only
 *   trackPrayerSentimentWellness — Weekly scheduled: prayer sentiment arc as wellness signal
 */

const admin = require("firebase-admin");
const { onCall } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const {
  getSecret,
  openaiEmbed,
  openaiEmbedBatch,
  pineconeUpsert,
  pineconeQuery,
  logFunction,
  checkRateLimit,
  sleep,
} = require("./mlClients");

const db = admin.firestore();

// ─── OpenAI client (for GPT-4o-mini classification only) ─────────────────────
let _openai = null;
async function getOpenAI() {
  if (_openai) return _openai;
  const apiKey = await getSecret("OPENAI_API_KEY");
  if (!apiKey) throw new Error("[Embed] OPENAI_API_KEY not configured");
  const { OpenAI } = require("openai");
  _openai = new OpenAI({ apiKey });
  return _openai;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEED BIBLE VERSES → PINECONE
// ═══════════════════════════════════════════════════════════════════════════════
//
// Setup:
//   1. Upload KJV Bible to Firestore bibleVerses/{book_chapter_verse} with fields:
//        { text, book, chapter, verse, reference, testament, sortKey, tone[] }
//      sortKey format: "GEN_001_001" for stable canonical ordering.
//   2. Call this function as a Firebase Admin (auth.token.admin = true).
//      It processes in batches of 50 and returns a `nextCursor` for resumption.
//      Run repeatedly until `done: true`.
//
// Pinecone vector schema:
//   id:       "{book}_{chapter}_{verse}"  e.g. "John_3_16"
//   values:   number[1536]
//   metadata: { book, chapter, verse, reference, text, testament, tone[] }
//
const seedBibleVersesToPinecone = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 540,
    secrets: ["PINECONE_API_KEY", "PINECONE_HOST"],
  },
  async (request) => {
    if (!request.auth?.token?.admin) throw new Error("Admin only");

    const { startAfter = null, batchSize = 50, dryRun = false } = request.data || {};
    const startMs = Date.now();

    let query = db.collection("bibleVerses").orderBy("sortKey").limit(batchSize);
    if (startAfter) {
      const cursorDoc = await db.collection("bibleVerses").doc(startAfter).get();
      if (cursorDoc.exists) query = query.startAfter(cursorDoc);
    }

    const snap = await query.get();
    if (snap.empty) return { seeded: 0, done: true, message: "No more verses to seed" };

    const verses = snap.docs
      .map((doc) => ({ id: doc.id, ...doc.data() }))
      .filter((v) => (v.text || "").length > 5);

    let seeded = 0;
    if (!dryRun) {
      const vectors = await openaiEmbedBatch(verses.map((v) => v.text));
      const pineconeVectors = verses.map((v, i) => ({
        id: v.id,
        values: vectors[i],
        metadata: {
          book:      v.book      || "",
          chapter:   v.chapter   || 0,
          verse:     v.verse     || 0,
          reference: v.reference || "",
          text:      (v.text     || "").slice(0, 512), // Pinecone metadata cap
          testament: v.testament || "",
          tone:      v.tone      || [],
        },
      }));
      await pineconeUpsert("scripture-embeddings", pineconeVectors);
      seeded = pineconeVectors.length;
    } else {
      seeded = verses.length;
    }

    const nextCursor = snap.docs[snap.docs.length - 1]?.id || null;
    logFunction("seedBibleVersesToPinecone", { seeded, dryRun, durationMs: Date.now() - startMs });
    return { seeded, nextCursor, done: snap.docs.length < batchSize, durationMs: Date.now() - startMs };
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// FIND SIMILAR TESTIMONIES
// ═══════════════════════════════════════════════════════════════════════════════

const findSimilarTestimonies = onCall(
  {
    region: "us-central1",
    secrets: ["PINECONE_API_KEY", "PINECONE_HOST"],
  },
  async (request) => {
    const { postId, limit = 5 } = request.data || {};
    const uid = request.auth?.uid;
    if (!uid)    throw new Error("Authentication required");
    if (!postId) throw new Error("postId is required");

    const allowed = await checkRateLimit(uid, "findSimilarTestimonies", 20);
    if (!allowed) throw new Error("Rate limited");

    const startMs = Date.now();

    // Fetch source post
    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists) throw new Error("Post not found");

    const postData = postDoc.data();
    const category = (postData.category || "").toLowerCase();
    if (!["testimonies", "testimony"].includes(category)) throw new Error("Post must be a testimony");

    const content = postData.content || postData.text || "";
    if (content.length < 10) throw new Error("Post content too short");

    // Get/generate embedding (cached by postId)
    const queryVector = await openaiEmbed(content, `post_${postId}`);

    // Query testimony-embeddings namespace, exclude same author
    const rawMatches = await pineconeQuery(
      "testimony-embeddings",
      queryVector,
      limit + 3,
      { authorId: { $ne: postData.authorId || uid } }
    );

    // Enrich with Firestore data, respect privacy
    const testimonies = [];
    for (const match of rawMatches) {
      const matchPostId = match.metadata?.postId || match.id;
      if (matchPostId === postId) continue;
      if (testimonies.length >= limit) break;

      try {
        const matchDoc = await db.collection("posts").doc(matchPostId).get();
        if (!matchDoc.exists) continue;
        const md = matchDoc.data();
        if (md.isPrivate) continue;

        testimonies.push({
          postId:              matchPostId,
          authorId:            md.authorId            || "",
          authorDisplayName:   md.authorDisplayName   || "",
          authorPhotoURL:      md.authorPhotoURL      || "",
          content:             (md.content || "").slice(0, 300),
          createdAt:           md.createdAt?.toMillis?.() || 0,
          relevanceScore:      Math.round((match.score || 0) * 100) / 100,
        });
      } catch (e) { /* skip inaccessible */ }
    }

    logFunction("findSimilarTestimonies", { postId, resultCount: testimonies.length, durationMs: Date.now() - startMs });
    return { testimonies };
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// REAL-TIME SCRIPTURE RECOMMENDATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// Returns contextually relevant Bible verses for any text.
// Sentiment is detected via keyword heuristic (no extra API call).
// Tone filter steers Pinecone toward comfort/hope for negative content,
// praise/thanksgiving for positive content.
//

const getScriptureRecommendation = onCall(
  {
    region: "us-central1",
    secrets: ["PINECONE_API_KEY", "PINECONE_HOST"],
  },
  async (request) => {
    const { text, postId, limit = 3 } = request.data || {};
    const uid = request.auth?.uid;
    if (!uid) throw new Error("Authentication required");
    if (!text || text.length < 5) return { scriptures: [] };

    const allowed = await checkRateLimit(uid, "getScriptureRecommendation", 30);
    if (!allowed) throw new Error("Rate limited");

    const startMs = Date.now();

    const cacheKey = postId ? `post_${postId}` : null;
    const queryVector = await openaiEmbed(text, cacheKey);

    // Keyword-based sentiment heuristic (avoids extra API call)
    const lc = text.toLowerCase();
    const negWords = ["anxious","worried","scared","fear","grief","lost","broken",
                      "depressed","hopeless","alone","hurting","cry","pain",
                      "struggling","doubt","angry","overwhelmed","desperate"];
    const posWords = ["thankful","grateful","blessed","praise","joy","celebrate",
                      "answered","miracle","victory","healed","overflow","rejoice"];
    const negScore = negWords.filter((w) => lc.includes(w)).length;
    const posScore = posWords.filter((w) => lc.includes(w)).length;
    const sentiment = negScore > posScore ? "negative" : posScore > negScore ? "positive" : "neutral";

    let toneFilter;
    if (sentiment === "negative") {
      toneFilter = { tone: { $in: ["comfort", "hope", "encouragement", "peace", "healing"] } };
    } else if (sentiment === "positive") {
      toneFilter = { tone: { $in: ["praise", "thanksgiving", "joy", "celebration", "blessing"] } };
    }

    const matches = await pineconeQuery("scripture-embeddings", queryVector, limit + 2, toneFilter);

    const scriptures = matches.slice(0, limit).map((m) => ({
      book:           m.metadata?.book      || "",
      chapter:        m.metadata?.chapter   || 0,
      verse:          m.metadata?.verse     || 0,
      reference:      m.metadata?.reference || m.id,
      text:           m.metadata?.text      || "",
      testament:      m.metadata?.testament || "",
      relevanceScore: Math.round((m.score   || 0) * 100) / 100,
    }));

    logFunction("getScriptureRecommendation", {
      sentiment, resultCount: scriptures.length, cached: !!cacheKey, durationMs: Date.now() - startMs,
    });
    return { scriptures, sentiment };
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// PRAYER PARTNER MATCHING
// ═══════════════════════════════════════════════════════════════════════════════
//
// Stores the caller's prayer embedding in the prayer-partner-pool namespace,
// then returns other users whose current prayer topics are semantically similar.
// Only matches users who have public profiles or have opted into prayer matching
// (prayerPartnerOptIn: true).
//

const matchPrayerPartners = onCall(
  {
    region: "us-central1",
    secrets: ["PINECONE_API_KEY", "PINECONE_HOST"],
  },
  async (request) => {
    const { prayerText, prayerId } = request.data || {};
    const uid = request.auth?.uid;
    if (!uid)                        throw new Error("Authentication required");
    if (!prayerText?.length >= 10)   throw new Error("Prayer text too short");

    const allowed = await checkRateLimit(uid, "matchPrayerPartners", 5);
    if (!allowed) throw new Error("Rate limited");

    const startMs = Date.now();
    const cacheKey = prayerId ? `prayer_${prayerId}` : `prayerpartner_user_${uid}`;
    const queryVector = await openaiEmbed(prayerText, cacheKey);

    // Upsert caller into the partner pool so they become discoverable too
    await pineconeUpsert("prayer-partner-pool", [{
      id: `user_${uid}`,
      values: queryVector,
      metadata: { userId: uid, prayerId: prayerId || "", updatedAt: Date.now() },
    }]);

    // Query for similar partners (exclude self, minimum 0.60 similarity)
    const rawMatches = await pineconeQuery(
      "prayer-partner-pool", queryVector, 8, { userId: { $ne: uid } }
    );

    const partners = [];
    for (const match of rawMatches) {
      if ((match.score || 0) < 0.60) continue;
      if (partners.length >= 5) break;

      const matchUserId = match.metadata?.userId || match.id.replace("user_", "");
      if (matchUserId === uid) continue;

      try {
        const userDoc = await db.collection("users").doc(matchUserId).get();
        if (!userDoc.exists) continue;
        const ud = userDoc.data();
        if (ud.isPrivate && !ud.prayerPartnerOptIn) continue;

        partners.push({
          userId:          matchUserId,
          displayName:     ud.displayName          || "AMEN member",
          photoURL:        ud.profileImageURL       || ud.profilePictureURL || "",
          similarityScore: Math.round((match.score  || 0) * 100) / 100,
          spiritualGift:   ud.spiritualGifts?.detected?.gift || null,
        });
      } catch (e) { /* skip */ }
    }

    logFunction("matchPrayerPartners", { uid, resultCount: partners.length, durationMs: Date.now() - startMs });
    return { partners };
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// ON TESTIMONY CREATED — AUTO-EMBED → PINECONE
// ═══════════════════════════════════════════════════════════════════════════════
//
// Fires on every new post; skips non-testimonies. Embeds content and upserts
// to testimony-embeddings so findSimilarTestimonies works immediately.
//

const onTestimonyCreated = onDocumentCreated(
  {
    document: "posts/{postId}",
    region: "us-central1",
    secrets: ["PINECONE_API_KEY", "PINECONE_HOST"],
  },
  async (event) => {
    const postId = event.params.postId;
    const data = event.data?.data();
    if (!data) return;

    const category = (data.category || "").toLowerCase();
    if (!["testimonies", "testimony"].includes(category)) return;

    const content = data.content || data.text || "";
    if (content.length < 20) return;

    try {
      const vector = await openaiEmbed(content, `post_${postId}`);
      await pineconeUpsert("testimony-embeddings", [{
        id: postId,
        values: vector,
        metadata: {
          postId,
          authorId:  data.authorId || "",
          createdAt: Date.now(),
          category:  "testimony",
        },
      }]);
      logFunction("onTestimonyCreated", { postId });
    } catch (err) {
      logFunction("onTestimonyCreated", { postId, error: err.message });
    }
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// CLASSIFY REPORTED CONTENT  (toxicity runs only on reports, not every post)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Replaces the BART zero-shot classification that previously ran on every post
// in mlContentPipeline. Now fires only when a user files a report, keeping
// GPT-4o-mini cost proportional to actual violations.
//
// Result is written back to the report doc and, for medium/high severity,
// a moderation queue task is created for human review.
//

const classifyReportedContent = onDocumentCreated(
  {
    document: "reports/{reportId}",
    region: "us-central1",
    secrets: ["OPENAI_API_KEY"],
  },
  async (event) => {
    const reportId   = event.params.reportId;
    const reportData = event.data?.data();
    if (!reportData) return;

    const postId = reportData.postId;
    const reason = reportData.reason || "other";
    if (!postId) return;

    const startMs = Date.now();

    try {
      const postDoc = await db.collection("posts").doc(postId).get();
      if (!postDoc.exists) return;
      const postData = postDoc.data();
      const content  = (postData.content || postData.text || "").slice(0, 1000);
      if (content.length < 5) return;

      const openai = await getOpenAI();
      const classifyResp = await openai.chat.completions.create({
        model:    "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: `You are a content safety classifier for a faith-based social app.
Classify the content below (JSON only, no prose):
{
  "toxic":      boolean,
  "severity":   "none"|"low"|"medium"|"high",
  "categories": string[],  // from: ["hate","harassment","violence","spam","misinformation","explicit","self_harm"]
  "faithBased": boolean,
  "confidence": number      // 0.0–1.0
}`,
          },
          {
            role: "user",
            content: `Report reason: ${reason}\n\nContent: ${content}`,
          },
        ],
        temperature:     0,
        max_tokens:      200,
        response_format: { type: "json_object" },
      });

      let classification = { toxic: false, severity: "none", confidence: 0 };
      try { classification = JSON.parse(classifyResp.choices[0].message.content); } catch (e) {}

      // Update report doc
      await event.data.ref.update({
        aiClassification: classification,
        classifiedAt:     admin.firestore.FieldValue.serverTimestamp(),
        status: classification.toxic && classification.severity !== "low"
          ? "pending_review"
          : "reviewed_safe",
      });

      // Escalate medium/high severity to moderation queue
      if (classification.toxic && ["medium", "high"].includes(classification.severity)) {
        await db.collection("moderationQueue").add({
          postId,
          reportId,
          severity:     classification.severity,
          categories:   classification.categories || [],
          confidence:   classification.confidence || 0,
          reportReason: reason,
          authorId:     postData.authorId,
          createdAt:    admin.firestore.FieldValue.serverTimestamp(),
          status:       "unreviewed",
        });
      }

      logFunction("classifyReportedContent", {
        reportId, postId, toxic: classification.toxic,
        severity: classification.severity, durationMs: Date.now() - startMs,
      });
    } catch (err) {
      logFunction("classifyReportedContent", { reportId, error: err.message, durationMs: Date.now() - startMs });
    }
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// PRAYER SENTIMENT WELLNESS TRACKER  (weekly, Monday 5am UTC)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Analyses the sentiment arc of each active user's prayers over the last 30 days
// using keyword scoring (no API call needed — keeps this free to run at scale).
//
// Stores per-user results in users/{uid}/wellness/prayerSentiment for display
// in SpiritualHealthView. Flags statistically significant declining arcs as
// pastoralCareAlerts — never surfaces prayer text to anyone, only the signal.
//

const trackPrayerSentimentWellness = onSchedule(
  {
    schedule:       "0 5 * * 1", // Monday 5am UTC
    region:         "us-central1",
    timeoutSeconds: 540,
  },
  async () => {
    const startMs      = Date.now();
    const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000);
    let processed = 0;
    let flagged   = 0;

    // Keyword → sentiment score table
    const sentimentWords = {
      distress:  { words: ["anxious","afraid","lost","hopeless","broken","alone","can't","overwhelmed","scared","desperate"],   score: -2 },
      struggle:  { words: ["struggling","difficult","hard","pain","hurting","tired","confused","doubt","worried"],               score: -1 },
      neutral:   { words: ["pray","ask","request","hope","believe","trust"],                                                      score:  0 },
      peace:     { words: ["peaceful","calm","rest","still","quiet","surrender"],                                                 score:  1 },
      gratitude: { words: ["thank","grateful","blessed","thankful","praise","answered","glory","appreciate"],                    score:  2 },
      joy:       { words: ["joy","joyful","celebrate","rejoice","happy","wonderful","amazing","overflow"],                        score:  2 },
    };

    // Only process users active in the last 14 days
    const users = await db.collection("users")
      .where("lastActiveAt", ">=", admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 14 * 86400000)
      ))
      .select("lastActiveAt")
      .limit(300)
      .get();

    for (const userDoc of users.docs) {
      const uid = userDoc.id;
      try {
        const prayersSnap = await db.collection("posts")
          .where("authorId", "==", uid)
          .where("category", "==", "prayer")
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
          .orderBy("createdAt", "asc")
          .limit(30)
          .get();

        if (prayersSnap.docs.length < 3) continue; // Need enough data points

        // Score each prayer by keyword presence
        const dataPoints = prayersSnap.docs.map((doc) => {
          const text          = (doc.data().content || "").toLowerCase();
          const date          = doc.data().createdAt?.toDate?.()?.toISOString()?.split("T")[0] || "";
          let totalScore      = 0;
          let dominantTone    = "neutral";
          let maxMatches      = 0;

          for (const [tone, { words, score }] of Object.entries(sentimentWords)) {
            const matches = words.filter((w) => text.includes(w)).length;
            totalScore += score * matches;
            if (matches > maxMatches) { maxMatches = matches; dominantTone = tone; }
          }

          return {
            prayerId:     doc.id,
            date,
            score:        Math.max(-5, Math.min(5, totalScore)), // clamp [-5, 5]
            dominantTone,
          };
        });

        // Trend: first half vs second half average
        const half         = Math.floor(dataPoints.length / 2);
        const firstHalfAvg = dataPoints.slice(0, half).reduce((s, p) => s + p.score, 0) / half;
        const secondHalfAvg= dataPoints.slice(half).reduce((s, p) => s + p.score, 0) / (dataPoints.length - half);
        const trend        = secondHalfAvg - firstHalfAvg; // positive = improving
        const currentScore = dataPoints[dataPoints.length - 1].score;
        const overallAvg   = dataPoints.reduce((s, p) => s + p.score, 0) / dataPoints.length;

        await db.collection("users").doc(uid)
          .collection("wellness").doc("prayerSentiment")
          .set({
            dataPoints,
            trend,
            currentScore,
            overallAvg:   Math.round(overallAvg * 100) / 100,
            prayerCount:  dataPoints.length,
            weekOf:       new Date().toISOString().split("T")[0],
            updatedAt:    admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });

        processed++;

        // Flag significant decline for pastoral care
        if (trend < -1.5 && currentScore < -1) {
          flagged++;
          await db.collection("pastoralCareAlerts").add({
            userId:      uid,
            alertType:   "prayer_sentiment_decline",
            trend,
            currentScore,
            prayerCount: dataPoints.length,
            note:        "User's prayer sentiment shows a declining trend over the past 30 days.",
            createdAt:   admin.firestore.FieldValue.serverTimestamp(),
            status:      "unreviewed",
          });
        }
      } catch (err) {
        console.error(`[PrayerWellness] Error for user ${uid}:`, err.message);
      }
    }

    logFunction("trackPrayerSentimentWellness", { processed, flagged, durationMs: Date.now() - startMs });
  }
);

// ─────────────────────────────────────────────────────────────────────────────
module.exports = {
  seedBibleVersesToPinecone,
  findSimilarTestimonies,
  getScriptureRecommendation,
  matchPrayerPartners,
  onTestimonyCreated,
  classifyReportedContent,
  trackPrayerSentimentWellness,
};
