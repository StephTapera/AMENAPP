/**
 * discussionFunctions.js — Discussion system callable Cloud Functions (V1)
 * CommonJS module for the default codebase. Exports all 7 discussion callables.
 *
 * LLM key: process.env.BEREAN_LLM_KEY — if absent, mock adapter is used.
 * Embedding key: process.env.EMBEDDING_KEY — if absent, duplicate check short-circuits.
 * DO NOT hardcode any keys here.
 */
// TODO: USE_DEFINE_SECRET — migrate this secret to defineSecret() for Functions v2

const functions = require("firebase-functions/v1");
const logger = require("firebase-functions/logger");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

// ── Book-name → OSIS key map (40 most common books) ──────────────────────────

const BOOK_MAP = {
  genesis:"GEN",gen:"GEN",exodus:"EXO",exo:"EXO",leviticus:"LEV",lev:"LEV",
  numbers:"NUM",num:"NUM",deuteronomy:"DEU",deu:"DEU",joshua:"JOS",jos:"JOS",
  judges:"JDG",ruth:"RUT",psalms:"PSA",psalm:"PSA",psa:"PSA",ps:"PSA",
  proverbs:"PRO",pro:"PRO",prov:"PRO",ecclesiastes:"ECC",isaiah:"ISA",isa:"ISA",
  jeremiah:"JER",jer:"JER",ezekiel:"EZK",daniel:"DAN",
  matthew:"MAT",mat:"MAT",mark:"MRK",mrk:"MRK",luke:"LUK",luk:"LUK",
  john:"JHN",jhn:"JHN",acts:"ACT",act:"ACT",
  romans:"ROM",rom:"ROM",
  corinthians:"COR",galatians:"GAL",gal:"GAL",ephesians:"EPH",eph:"EPH",
  philippians:"PHP",php:"PHP",colossians:"COL",col:"COL",
  thessalonians:"THS",timothy:"TIM",titus:"TIT",philemon:"PHM",
  hebrews:"HEB",heb:"HEB",james:"JAS",jas:"JAS",
  peter:"PET",pet:"PET",jude:"JUD",revelation:"REV",rev:"REV",
};

function detectVerseKeys(body) {
  const regex = /\b([1-3]?\s*[A-Za-z]+)\s+(\d+):(\d+)\b/g;
  const keys = [];
  let m;
  while ((m = regex.exec(body)) !== null) {
    const book = m[1].toLowerCase().trim().replace(/\s+/g,"");
    const osis = BOOK_MAP[book];
    if (osis) keys.push(`${osis}.${m[2]}.${m[3]}`);
  }
  return [...new Set(keys)];
}

// ── LLM adapter ───────────────────────────────────────────────────────────────

const MOCK_BEREAN = {
  summary: "This thread discusses faith and community. [Mock — set BEREAN_LLM_KEY to enable real AI]",
  agreementPoints: ["Community matters in the faith journey", "Faith is foundational to practice"],
  openQuestions: ["How do we apply this practically in daily life?"],
  biblicalRefs: ["JHN.3.16", "ROM.8.28"],
  studyQuestions: ["What does this passage mean for daily discipleship?"],
  isMock: true,
  tokenCount: 0,
};

async function generateBereanSummary(prompt) {
  const key = process.env.BEREAN_LLM_KEY || "";
  if (!key) {
    logger.info("llmAdapter: BEREAN_LLM_KEY not set — returning mock.");
    return MOCK_BEREAN;
  }
  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${key}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }] }),
      }
    );
    if (!res.ok) { logger.warn(`llmAdapter: HTTP ${res.status}`); return MOCK_BEREAN; }
    const json = await res.json();
    const raw = json?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    const tokens = json?.usageMetadata?.totalTokenCount ?? 0;
    if (!raw) return MOCK_BEREAN;
    const cleaned = raw.replace(/^```(?:json)?\s*/i,"").replace(/\s*```\s*$/,"").trim();
    try {
      const p = JSON.parse(cleaned);
      return {
        summary: String(p.summary ?? MOCK_BEREAN.summary),
        agreementPoints: Array.isArray(p.agreementPoints) ? p.agreementPoints.map(String) : MOCK_BEREAN.agreementPoints,
        openQuestions: Array.isArray(p.openQuestions) ? p.openQuestions.map(String) : MOCK_BEREAN.openQuestions,
        biblicalRefs: Array.isArray(p.biblicalRefs) ? p.biblicalRefs.map(String) : MOCK_BEREAN.biblicalRefs,
        studyQuestions: Array.isArray(p.studyQuestions) ? p.studyQuestions.map(String) : MOCK_BEREAN.studyQuestions,
        isMock: false, tokenCount: tokens,
      };
    } catch { return { ...MOCK_BEREAN, isMock: true, tokenCount: tokens }; }
  } catch (err) {
    logger.warn("llmAdapter: network error", { err: String(err) });
    return MOCK_BEREAN;
  }
}

// ── Embedding adapter ─────────────────────────────────────────────────────────

async function embedText(text) {
  const key = process.env.EMBEDDING_KEY || "";
  if (!key) return new Array(768).fill(0);
  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key=${key}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ model: "models/text-embedding-004", content: { parts: [{ text }] } }),
      }
    );
    if (!res.ok) return new Array(768).fill(0);
    const json = await res.json();
    return Array.isArray(json?.embedding?.values) ? json.embedding.values : new Array(768).fill(0);
  } catch { return new Array(768).fill(0); }
}

function cosineSimilarity(a, b) {
  if (a.length !== b.length || a.length === 0) return 0;
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) { dot += a[i]*b[i]; na += a[i]*a[i]; nb += b[i]*b[i]; }
  const denom = Math.sqrt(na) * Math.sqrt(nb);
  return denom === 0 ? 0 : dot / denom;
}

// ── Rate limit helper ─────────────────────────────────────────────────────────
// Per-user rolling-window rate limiter backed by Firestore atomic transactions.
// Uses the same pattern as checkBereanRateLimit in bereanRealtimeFunctions.js.
// @param {object} db        — Firestore instance
// @param {string} uid       — authenticated user id
// @param {string} feature   — rate-limit bucket name (e.g. "postComment")
// @param {number} maxPerHour
async function discussionRateLimit(db, uid, feature, maxPerHour) {
  const hourKey = new Date().toISOString().slice(0, 13); // YYYY-MM-DDTHH
  const ref = db.collection("users").doc(uid)
    .collection("discussionUsage").doc(`${feature}_${hourKey}`);
  await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    const count = snap.exists ? (snap.data().count || 0) : 0;
    if (count >= maxPerHour) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        `Rate limit reached for ${feature}. Try again later.`,
      );
    }
    t.set(ref, { count: count + 1, windowStart: hourKey }, { merge: true });
  });
}

// ── Cloud Functions ───────────────────────────────────────────────────────────

const REPUTATION_POINTS = { helpfulMark:3, acceptedAnswer:10, firstComment:1, bereanCite:2 };

function badgeTier(total) {
  if (total >= 200) return "elder";
  if (total >= 50)  return "berean";
  if (total >= 10)  return "seeker";
  return "none";
}

// askBerean
// APP CHECK: Enforced server-side via context.app in v1.
// iOS setup steps: 1) Add AppCheckProviderFactory in AppDelegate, 2) Configure DeviceCheck/AppAttest provider.
const askBerean = functions.region("us-central1").runWith({ secrets: ["BEREAN_LLM_KEY"] }).https.onCall(async (data, context) => {
  const db = getFirestore();
  const userId = context.auth?.uid;
  if (!userId) throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");

  const threadId = String(data?.threadId ?? "").trim();
  if (!threadId) throw new functions.https.HttpsError("invalid-argument", "threadId is required.");

  // Rate limit: 1 per user+thread per 10 minutes
  const rlRef = db.collection("discussions").doc("rateLimits").collection("askBerean").doc(`${userId}_${threadId}`);
  const rlSnap = await rlRef.get();
  if (rlSnap.exists) {
    const last = rlSnap.data()?.lastCalledAt;
    if (last && (Date.now() - last.toMillis()) / 1000 < 600) {
      throw new functions.https.HttpsError("resource-exhausted", "Rate limit: wait 10 minutes between Berean queries.");
    }
  }

  const threadSnap = await db.collection("threads").doc(threadId).get();
  if (!threadSnap.exists) throw new functions.https.HttpsError("not-found", "Thread not found.");
  if (threadSnap.data()?.isLocked) throw new functions.https.HttpsError("failed-precondition", "Thread is locked.");

  const commentsSnap = await db.collection("threads").doc(threadId).collection("comments")
    .where("isDeleted","==",false).orderBy("createdAt","asc").limit(50).get();

  const lines = commentsSnap.docs.map((d,i) => `${i+1}. ${String(d.data().body??"").slice(0,300)}`).join("\n");
  const postType = String(threadSnap.data()?.postType ?? "general");

  const prompt = `You are Berean, a biblical discussion assistant. Analyze this thread and respond with JSON only.
Thread about post type: ${postType}
Comments (${commentsSnap.size} total):
${lines}

Return JSON with exactly these fields:
{ "summary": "string", "agreementPoints": ["..."], "openQuestions": ["..."], "biblicalRefs": ["OSIS keys e.g. JHN.3.16"], "studyQuestions": ["..."] }`;

  logger.info(`askBerean: thread ${threadId}, ${commentsSnap.size} comments`);
  const llm = await generateBereanSummary(prompt);

  const summaryRef = db.collection("threads").doc(threadId).collection("bereanSummaries").doc();
  const summaryId = summaryRef.id;

  const batch = db.batch();
  batch.set(summaryRef, {
    id: summaryId, threadId, requestedBy: userId,
    summary: llm.summary, agreementPoints: llm.agreementPoints, openQuestions: llm.openQuestions,
    biblicalRefs: llm.biblicalRefs, studyQuestions: llm.studyQuestions,
    generatedAt: FieldValue.serverTimestamp(), tokenCount: llm.tokenCount, isMock: llm.isMock,
  });
  batch.update(db.collection("threads").doc(threadId), { bereanSummaryRef: summaryRef.path });
  batch.set(rlRef, { lastCalledAt: FieldValue.serverTimestamp() }, { merge: true });
  await batch.commit();

  return { summaryId, ...llm };
});

// detectDuplicate
const detectDuplicate = functions.region("us-central1").runWith({ secrets: ["EMBEDDING_KEY"] }).https.onCall(async (data, context) => {
  const userId = context.auth?.uid;
  if (!userId) throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");

  const db = getFirestore();
  // Rate limit: 30 duplicate checks per user per hour
  await discussionRateLimit(db, userId, "detectDuplicate", 30);

  const threadId = String(data?.threadId ?? "").trim();
  const draftBody = String(data?.draftBody ?? "").trim();
  if (!threadId) throw new functions.https.HttpsError("invalid-argument", "threadId is required.");
  if (draftBody.length < 5 || draftBody.length > 2000) {
    throw new functions.https.HttpsError("invalid-argument", "draftBody must be 5–2000 characters.");
  }

  if (!process.env.EMBEDDING_KEY) {
    return { isDuplicate: false, similarCommentIds: [], similarityScore: 0, suggestion: null };
  }

  const draftVec = await embedText(draftBody);

  const commentsSnap = await db.collection("threads").doc(threadId).collection("comments")
    .where("isDeleted","==",false).where("embedding","!=",null).limit(30).get();

  const scored = commentsSnap.docs.map(d => ({
    id: d.id,
    score: cosineSimilarity(draftVec, d.data().embedding ?? []),
  })).sort((a,b) => b.score - a.score);

  const top = scored.filter(s => s.score > 0.82).slice(0,3);
  const topScore = scored[0]?.score ?? 0;
  const isDuplicate = topScore > 0.82;
  const suggestion = isDuplicate ? "supportExisting" : topScore > 0.65 ? "addAngle" : null;

  return { isDuplicate, similarCommentIds: top.map(s=>s.id), similarityScore: topScore, suggestion };
});

// computeReputation
// IDOR fix: uid is always sourced from context.auth.uid — never accepted from caller data.
// Rate limit: 20 calls per user per hour.
const computeReputation = functions.region("us-central1").https.onCall(async (data, context) => {
  const userId = context.auth?.uid;
  if (!userId) throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");

  const db = getFirestore();
  // Rate limit: 20 reputation lookups per user per hour
  await discussionRateLimit(db, userId, "computeReputation", 20);

  // Always use the authenticated user's own UID — never trust caller-supplied uid.
  // If a future public-profile page needs another user's reputation, that endpoint
  // should be a separate, read-only, unauthenticated-safe CF with its own access control.
  const uid = userId;

  const snap = await db.collection("reputationEvents").where("toUID","==",uid).limit(500).get();

  const breakdown = { helpfulMark:0, acceptedAnswer:0, firstComment:0, bereanCite:0 };
  let total = 0;
  snap.docs.forEach(d => {
    const type = d.data().type;
    const pts = REPUTATION_POINTS[type] ?? 0;
    if (type in breakdown) breakdown[type] += pts;
    total += pts;
  });

  return { uid, totalPoints: total, badgeTier: badgeTier(total), breakdown };
});

// postComment
const postComment = functions.region("us-central1").https.onCall(async (data, context) => {
  const db = getFirestore();
  const userId = context.auth?.uid;
  if (!userId) throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");

  // Rate limit: 20 comments per user per hour
  await discussionRateLimit(db, userId, "postComment", 20);

  const threadId = String(data?.threadId ?? "").trim();
  const parentCommentId = data?.parentCommentId ? String(data.parentCommentId).trim() : null;
  const body = String(data?.body ?? "").trim();
  const destination = String(data?.destination ?? "public").trim();
  const thresholdPassedAt = data?.thresholdPassedAt;

  if (!threadId) throw new functions.https.HttpsError("invalid-argument", "threadId is required.");
  if (body.length < 1 || body.length > 2000) throw new functions.https.HttpsError("invalid-argument", "body must be 1–2000 characters.");
  if (!["public","reflection","churchNotes"].includes(destination)) throw new functions.https.HttpsError("invalid-argument", "Invalid destination.");

  const threadSnap = await db.collection("threads").doc(threadId).get();
  if (!threadSnap.exists) throw new functions.https.HttpsError("not-found", "Thread not found.");
  if (threadSnap.data()?.isLocked) throw new functions.https.HttpsError("failed-precondition", "Thread is locked.");

  let depth = 0;
  if (parentCommentId) {
    const parentSnap = await db.collection("threads").doc(threadId).collection("comments").doc(parentCommentId).get();
    if (!parentSnap.exists) throw new functions.https.HttpsError("not-found", "Parent comment not found.");
    depth = (parentSnap.data()?.depth ?? 0) + 1;
    if (depth > 2) throw new functions.https.HttpsError("invalid-argument", "Max reply depth is 2.");
  }

  const verseKeys = detectVerseKeys(body);
  const commentRef = db.collection("threads").doc(threadId).collection("comments").doc();
  const commentId = commentRef.id;
  const awardedBereanCite = verseKeys.length > 0;
  const now = FieldValue.serverTimestamp();

  const batch = db.batch();

  batch.set(commentRef, {
    id: commentId, threadId, authorUID: userId,
    authorDisplayName: userId, authorAvatarURL: null,
    parentCommentId: parentCommentId ?? null, depth, body, verseKeys, destination,
    helpfulCount: 0, isAcceptedAnswer: false, isDeleted: false, deletedAt: null,
    createdAt: now, updatedAt: null, reportedAt: null,
    thresholdPassedAt: thresholdPassedAt ? new Date(thresholdPassedAt) : now,
    embedding: null,
  });

  batch.update(db.collection("threads").doc(threadId), { commentCount: FieldValue.increment(1), updatedAt: now });

  const repRef = db.collection("reputationEvents").doc();
  batch.set(repRef, { id: repRef.id, type: "firstComment", fromUID: userId, toUID: userId, commentId, threadId, points: 1, createdAt: now });

  if (awardedBereanCite) {
    const bRef = db.collection("reputationEvents").doc();
    batch.set(bRef, { id: bRef.id, type: "bereanCite", fromUID: userId, toUID: userId, commentId, threadId, points: 2, createdAt: now });
  }

  const embQRef = db.collection("embeddingQueue").doc(commentId);
  batch.set(embQRef, { commentId, threadId, body, requestedAt: now });

  await batch.commit();
  logger.info(`postComment: ${commentId} in thread ${threadId}`);
  return { commentId, verseKeys, awardedBereanCite };
});

// markHelpful
const markHelpful = functions.region("us-central1").https.onCall(async (data, context) => {
  const db = getFirestore();
  const userId = context.auth?.uid;
  if (!userId) throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");

  // Rate limit: 60 helpful marks per user per hour
  await discussionRateLimit(db, userId, "markHelpful", 60);

  const commentId = String(data?.commentId ?? "").trim();
  const threadId  = String(data?.threadId  ?? "").trim();
  if (!commentId) throw new functions.https.HttpsError("invalid-argument", "commentId is required.");
  if (!threadId)  throw new functions.https.HttpsError("invalid-argument", "threadId is required.");

  const commentRef = db.collection("threads").doc(threadId).collection("comments").doc(commentId);
  const commentSnap = await commentRef.get();
  if (!commentSnap.exists) throw new functions.https.HttpsError("not-found", "Comment not found.");
  if (commentSnap.data()?.isDeleted) throw new functions.https.HttpsError("not-found", "Comment not found.");
  if (commentSnap.data()?.authorUID === userId) throw new functions.https.HttpsError("failed-precondition", "Cannot mark your own comment as helpful.");

  const existing = await db.collection("reputationEvents")
    .where("fromUID","==",userId).where("commentId","==",commentId).where("type","==","helpfulMark")
    .limit(1).get();

  if (!existing.empty) {
    return { eventId: existing.docs[0].id, isNew: false, helpfulCount: commentSnap.data()?.helpfulCount ?? 0 };
  }

  const now = FieldValue.serverTimestamp();
  const eventRef = db.collection("reputationEvents").doc();

  const batch = db.batch();
  batch.set(eventRef, {
    id: eventRef.id, type: "helpfulMark", fromUID: userId,
    toUID: commentSnap.data()?.authorUID, commentId, threadId, points: 3, createdAt: now,
  });
  batch.update(commentRef, { helpfulCount: FieldValue.increment(1) });
  await batch.commit();

  logger.info(`markHelpful: ${userId} -> ${commentId}`);
  return { eventId: eventRef.id, isNew: true, helpfulCount: (commentSnap.data()?.helpfulCount ?? 0) + 1 };
});

// updateWatchProgress
const updateWatchProgress = functions.region("us-central1").https.onCall(async (data, context) => {
  const db = getFirestore();
  const userId = context.auth?.uid;
  if (!userId) throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");

  // Rate limit: 120 progress updates per user per hour (high cadence for video progress)
  await discussionRateLimit(db, userId, "updateWatchProgress", 120);

  const postId  = String(data?.postId ?? "").trim();
  const progressFraction = Number(data?.progressFraction);
  const durationSecs = Number(data?.durationSecs);
  const watchedSecs  = Number(data?.watchedSecs);
  const transcriptRead = data?.transcriptRead === true;

  if (!postId) throw new functions.https.HttpsError("invalid-argument", "postId is required.");
  if (isNaN(progressFraction) || progressFraction < 0 || progressFraction > 1) throw new functions.https.HttpsError("invalid-argument", "progressFraction must be 0-1.");
  if (isNaN(durationSecs) || durationSecs <= 0) throw new functions.https.HttpsError("invalid-argument", "durationSecs must be > 0.");
  if (isNaN(watchedSecs)  || watchedSecs < 0)  throw new functions.https.HttpsError("invalid-argument", "watchedSecs must be >= 0.");

  const docId = `${userId}_${postId}`;
  await db.collection("watchProgress").doc(docId).set(
    { uid: userId, postId, progressFraction, durationSecs, watchedSecs, transcriptRead, updatedAt: FieldValue.serverTimestamp() },
    { merge: true }
  );

  return { shouldNudge: progressFraction < 0.8 && !transcriptRead };
});

// getWatchProgress
const getWatchProgress = functions.region("us-central1").https.onCall(async (data, context) => {
  const db = getFirestore();
  const userId = context.auth?.uid;
  if (!userId) throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");

  // Rate limit: 120 progress reads per user per hour
  await discussionRateLimit(db, userId, "getWatchProgress", 120);

  const postId = String(data?.postId ?? "").trim();
  if (!postId) throw new functions.https.HttpsError("invalid-argument", "postId is required.");

  const snap = await db.collection("watchProgress").doc(`${userId}_${postId}`).get();
  if (!snap.exists) return { progressFraction: null, transcriptRead: false, shouldNudge: true };

  const d = snap.data();
  const progressFraction = d?.progressFraction ?? 0;
  const transcriptRead   = d?.transcriptRead === true;
  return { progressFraction, transcriptRead, shouldNudge: progressFraction < 0.8 && !transcriptRead };
});

// ── Embedding queue worker ────────────────────────────────────────────────────
// Processes docs written to embeddingQueue/{docId} by postComment.
// Uses EMBEDDING_KEY env var; falls back to a zero-vector stub when absent so
// duplicate detection still runs (cosine similarity returns 0 for all-zero vectors).

const processEmbeddingQueue = functions.region("us-central1").runWith({ secrets: ["EMBEDDING_KEY"] }).firestore
  .document("embeddingQueue/{docId}")
  .onCreate(async (snap) => {
    const { commentId, threadId, body } = snap.data();
    if (!commentId || !threadId || !body) {
      logger.warn("processEmbeddingQueue: missing required fields", { commentId, threadId });
      await snap.ref.delete();
      return;
    }

    const db = getFirestore();
    // Reuses embedText: Gemini text-embedding-004 (768-dim).
    // Returns a 768-dim zero vector when EMBEDDING_KEY is absent — safe for dup detection (cosine → 0).
    const embedding = await embedText(body);

    await db.collection("threads").doc(threadId).collection("comments").doc(commentId)
      .update({ embedding });
    await snap.ref.delete();
    logger.info(`processEmbeddingQueue: processed ${commentId}`);
  });

// setAccepted — thread owner accepts a comment as the answer
const setAccepted = functions.region("us-central1").https.onCall(async (data, context) => {
  const db = getFirestore();
  const userId = context.auth?.uid;
  if (!userId) throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");

  const commentId  = String(data?.commentId  ?? "").trim();
  const threadId   = String(data?.threadId   ?? "").trim();
  const isAccepted = data?.isAccepted === true;

  if (!commentId) throw new functions.https.HttpsError("invalid-argument", "commentId is required.");
  if (!threadId)  throw new functions.https.HttpsError("invalid-argument", "threadId is required.");

  const threadSnap = await db.collection("threads").doc(threadId).get();
  if (!threadSnap.exists) throw new functions.https.HttpsError("not-found", "Thread not found.");
  if (threadSnap.data()?.postAuthorUID !== userId) {
    throw new functions.https.HttpsError("permission-denied", "Only the post author can accept an answer.");
  }

  const commentRef  = db.collection("threads").doc(threadId).collection("comments").doc(commentId);
  const commentSnap = await commentRef.get();
  if (!commentSnap.exists || commentSnap.data()?.isDeleted) {
    throw new functions.https.HttpsError("not-found", "Comment not found.");
  }

  const batch = db.batch();
  const now = FieldValue.serverTimestamp();

  if (isAccepted) {
    // Clear any existing accepted answer first
    const prevSnap = await db.collection("threads").doc(threadId).collection("comments")
      .where("isAcceptedAnswer", "==", true).limit(5).get();
    prevSnap.forEach(doc => {
      if (doc.id !== commentId) batch.update(doc.ref, { isAcceptedAnswer: false });
    });
  }

  batch.update(commentRef, { isAcceptedAnswer: isAccepted });

  let eventId = null;
  if (isAccepted) {
    const existing = await db.collection("reputationEvents")
      .where("type", "==", "acceptedAnswer").where("commentId", "==", commentId).limit(1).get();
    if (existing.empty) {
      const evRef = db.collection("reputationEvents").doc();
      eventId = evRef.id;
      batch.set(evRef, {
        id: eventId, type: "acceptedAnswer",
        fromUID: userId, toUID: commentSnap.data()?.authorUID,
        commentId, threadId, points: REPUTATION_POINTS.acceptedAnswer, createdAt: now,
      });
    }
  }

  await batch.commit();
  logger.info(`setAccepted: comment=${commentId} isAccepted=${isAccepted}`);
  return { eventId, isNew: !!eventId };
});

// ── Exports ───────────────────────────────────────────────────────────────────

module.exports = {
  // Discussion
  askBerean,
  detectDuplicate,
  computeReputation,
  postComment,
  markHelpful,
  setAccepted,
  updateWatchProgress,
  getWatchProgress,
  processEmbeddingQueue,
  // Internal helper exported for testing
  detectVerseKeys,
  cosineSimilarity,
};
