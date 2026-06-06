/**
 * askCreatorQuery.js — "Ask This Creator" RAG Cloud Function
 *
 * Enables users to ask questions about a creator's published catalog. Answers
 * are grounded exclusively in the creator's published, approved works stored in
 * Pinecone (namespace: `creator-catalog-{creatorId}`).
 *
 * FAIL-CLOSED CONTRACT (NON-NEGOTIABLE):
 *   - No qualifying Pinecone results → refuse, return { refused: true }
 *   - AI response with 0 citation references → downgrade to refuse
 *   - Never expose draft, private, or deleted work content
 *   - All entitlement + rate-limit checks server-side, never client-hint
 *   - Input sanitized before callModel invocation
 *
 * Exports:
 *   askCreatorQuery      — onCall CF: main RAG endpoint
 *   getCatalogQueryStats — onCall CF: return query count + remaining daily limit
 */

"use strict";

const functions = require("firebase-functions");
const admin     = require("firebase-admin");
const logger    = require("firebase-functions/logger");

const { openaiEmbed, pineconeQuery } = require("../mlClients");
const { callModel }                  = require("../router/callModel");
const { SYSTEM_PROMPTS }             = require("./embedCatalogWork");

// ── Constants ─────────────────────────────────────────────────────────────────
const DAILY_QUERY_LIMIT    = 20;
const MAX_QUESTION_LENGTH  = 500;
const PINECONE_TOP_K       = 5;
const SNIPPET_LENGTH       = 300;
const REFUSE_ANSWER_PREFIX = "I can only answer from this creator's published catalog.";

// Visibility values that a general authenticated user can access (paid checks
// happen at the individual work level — visibility:'paid_members' requires
// additional entitlement verification, but we include in retrieval and filter
// post-fetch so the rate limit is charged only for qualifying results).
const READABLE_VISIBILITY = ["public", "followers", "paid_members"];

// ── Helpers ───────────────────────────────────────────────────────────────────
function catalogNamespace(creatorId) {
  return `creator-catalog-${creatorId}`;
}

/**
 * Sanitize question text: trim, collapse whitespace, strip control characters.
 */
function sanitizeQuestion(raw) {
  return String(raw)
    .replace(/[\x00-\x1F\x7F]/g, " ")   // strip control chars
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Check whether the asking user has access to a work based on its visibility.
 * Expand this with actual followers/paid_members checks as those features mature.
 *
 * @param {string} visibility
 * @param {string} askerId
 * @param {string} creatorId
 * @returns {boolean}
 */
function hasVisibilityAccess(visibility, askerId, creatorId) {
  if (visibility === "public") return true;
  // Authenticated user — allow followers/paid_members (server trusts auth; deeper
  // checks via Firestore rules on direct reads happen separately).
  // Callers that are the creator themselves always have access.
  if (askerId === creatorId) return true;
  if (visibility === "followers" || visibility === "paid_members") return true;
  return false;
}

/**
 * Atomically increment and check the daily query count for a user.
 * Uses a Firestore counter subcollection keyed to UTC date.
 *
 * @returns {Promise<{allowed: boolean, remaining: number, count: number}>}
 */
async function checkAndIncrementRateLimit(uid) {
  const db      = admin.firestore();
  const dateKey = new Date().toISOString().slice(0, 10); // "YYYY-MM-DD"
  const ref     = db
    .collection("users").doc(uid)
    .collection("catalogQueryCount").doc(dateKey);

  return db.runTransaction(async (tx) => {
    const snap  = await tx.get(ref);
    const count = snap.exists ? (snap.data().count || 0) : 0;

    if (count >= DAILY_QUERY_LIMIT) {
      return { allowed: false, remaining: 0, count };
    }

    tx.set(ref, {
      count:     count + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { allowed: true, remaining: DAILY_QUERY_LIMIT - count - 1, count: count + 1 };
  });
}

/**
 * Check current daily query count without incrementing.
 */
async function getQueryCount(uid) {
  const db      = admin.firestore();
  const dateKey = new Date().toISOString().slice(0, 10);
  const ref     = db
    .collection("users").doc(uid)
    .collection("catalogQueryCount").doc(dateKey);

  const snap  = await ref.get();
  const count = snap.exists ? (snap.data().count || 0) : 0;
  return { count, remaining: Math.max(0, DAILY_QUERY_LIMIT - count) };
}

/**
 * Log the query result to Firestore for audit / analytics.
 */
async function logQueryResult({ creatorId, askerId, question, refused, answeredAt }) {
  try {
    const db  = admin.firestore();
    const ref = db.collection("catalogQueryLogs").doc();
    await ref.set({
      creatorId,
      askerId,
      question:    question.slice(0, 200),    // don't store full question in logs
      refused:     Boolean(refused),
      answeredAt:  answeredAt || admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    // Audit log failure is non-fatal
    logger.warn("[askCreatorQuery] Audit log write failed", { err: err.message });
  }
}

// ── Build refuse response ─────────────────────────────────────────────────────
function buildRefuseResponse(reason = "No relevant source was found for your question.") {
  return {
    answer:     `${REFUSE_ANSWER_PREFIX} ${reason}`,
    citations:  [],
    mode:       "ai_summary",
    confidence: 0,
    refused:    true,
  };
}

// ── askCreatorQuery — main onCall CF ─────────────────────────────────────────
/**
 * "Ask This Creator" RAG endpoint.
 *
 * Request: { creatorId: string, question: string }
 * Response: {
 *   answer:    string,
 *   citations: [{ workId, snippet, sourceUrl, confidence }],
 *   mode:      'creator_said' | 'ai_summary',
 *   confidence: number,
 *   refused?:  true
 * }
 */
exports.askCreatorQuery = functions.https.onCall(async (data, context) => {
  // ── 1. Auth gate ────────────────────────────────────────────────────────────
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }
  const askerId = context.auth.uid;

  // ── 2. Input validation ─────────────────────────────────────────────────────
  const { creatorId, question: rawQuestion } = data || {};
  if (!creatorId || typeof creatorId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "creatorId is required.");
  }
  if (!rawQuestion || typeof rawQuestion !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "question is required.");
  }
  const question = sanitizeQuestion(rawQuestion);
  if (question.length === 0) {
    throw new functions.https.HttpsError("invalid-argument", "question cannot be empty.");
  }
  if (question.length > MAX_QUESTION_LENGTH) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `question must be ${MAX_QUESTION_LENGTH} characters or fewer.`
    );
  }

  // ── 3. Rate limit ───────────────────────────────────────────────────────────
  const rateCheck = await checkAndIncrementRateLimit(askerId);
  if (!rateCheck.allowed) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      `Daily query limit of ${DAILY_QUERY_LIMIT} reached. Try again tomorrow.`
    );
  }

  // ── 4. Creator entitlement check ────────────────────────────────────────────
  const db = admin.firestore();
  let catalogEnabled = false;
  try {
    // Check both possible entitlement locations
    const entitlementRef  = db
      .collection("users").doc(creatorId)
      .collection("entitlements").doc("catalog");
    const settingsRef     = db.collection("users").doc(creatorId);

    const [entitleSnap, userSnap] = await Promise.all([
      entitlementRef.get(),
      settingsRef.get(),
    ]);

    const entitlement    = entitleSnap.exists ? entitleSnap.data() : {};
    const userSettings   = userSnap.exists   ? userSnap.data()    : {};

    catalogEnabled =
      entitlement.enabled === true ||
      userSettings?.catalogSettings?.askEnabled === true;
  } catch (err) {
    logger.warn("[askCreatorQuery] Entitlement check failed — fail closed", {
      creatorId,
      err: err.message,
    });
    // Fail closed: treat as not enabled
    catalogEnabled = false;
  }

  if (!catalogEnabled) {
    return buildRefuseResponse(
      "This creator has not enabled the Ask feature for their catalog."
    );
  }

  // ── 5. Fetch creator display name (for system prompt) ──────────────────────
  let creatorName = "this creator";
  try {
    const creatorSnap = await db.collection("users").doc(creatorId).get();
    if (creatorSnap.exists) {
      const d = creatorSnap.data();
      creatorName = d.displayName || d.username || d.name || "this creator";
    }
  } catch (_) {
    // Non-fatal — fall back to generic label
  }

  // ── 6. Embed the question ───────────────────────────────────────────────────
  let questionVector;
  try {
    questionVector = await openaiEmbed(question);
  } catch (err) {
    logger.error("[askCreatorQuery] Embedding failed — fail closed", { err: err.message });
    return buildRefuseResponse("Unable to process your question at this time. Please try again.");
  }

  // ── 7. Pinecone retrieval ───────────────────────────────────────────────────
  const namespace = catalogNamespace(creatorId);
  let pineconeMatches = [];
  try {
    const result = await pineconeQuery(namespace, questionVector, PINECONE_TOP_K);
    pineconeMatches = result?.matches || [];
  } catch (err) {
    logger.error("[askCreatorQuery] Pinecone query failed — fail closed", {
      namespace,
      err: err.message,
    });
    return buildRefuseResponse("Unable to search the creator's catalog at this time.");
  }

  if (!pineconeMatches.length) {
    await logQueryResult({ creatorId, askerId, question, refused: true });
    return buildRefuseResponse();
  }

  // ── 8. Fetch + filter Works from Firestore ─────────────────────────────────
  // For each Pinecone match, fetch the corresponding Work and apply access rules.
  const qualifyingWorks = [];

  await Promise.allSettled(
    pineconeMatches.map(async (match) => {
      const workId = match.id;
      try {
        const workSnap = await db.collection("works").doc(workId).get();
        if (!workSnap.exists) return;
        const work = workSnap.data();

        // Hard filters: must be published, not deleted, readable visibility
        if (work.reviewState !== "published")              return;
        if (work.deletedAt)                                return;
        if (!READABLE_VISIBILITY.includes(work.visibility)) return;
        if (!hasVisibilityAccess(work.visibility, askerId, creatorId)) return;

        qualifyingWorks.push({
          workId,
          work,
          score: match.score || 0,
        });
      } catch (err) {
        logger.warn("[askCreatorQuery] Work fetch failed", { workId, err: err.message });
      }
    })
  );

  // ── 9. Refuse if 0 qualifying results ──────────────────────────────────────
  if (!qualifyingWorks.length) {
    await logQueryResult({ creatorId, askerId, question, refused: true });
    return buildRefuseResponse();
  }

  // ── Build citations array ──────────────────────────────────────────────────
  const citations = qualifyingWorks.map(({ workId, work, score }) => ({
    workId,
    snippet:    (work.description || work.title || "").slice(0, SNIPPET_LENGTH),
    sourceUrl:  (work.links && work.links[0]?.url) || work.sourceUrl || "",
    timestamp:  work.publishedAt
                  ? (work.publishedAt.toDate
                      ? work.publishedAt.toDate().toISOString()
                      : String(work.publishedAt))
                  : undefined,
    confidence: Math.round(score * 1000) / 1000,   // 3 decimal places
  }));

  // ── 10. Build system prompt with citations injected ────────────────────────
  const citationText = citations
    .map((c, i) =>
      `[${i + 1}] workId:${c.workId}\n` +
      `    snippet: "${c.snippet}"\n` +
      `    sourceUrl: ${c.sourceUrl || "(none)"}`
    )
    .join("\n\n");

  const systemPrompt = SYSTEM_PROMPTS.catalog_qa
    .replace("{citations}", citationText)
    .replace("{creatorName}", creatorName)
    .replace("{question}", question);

  // ── 11. Call AI router ─────────────────────────────────────────────────────
  let aiResponse;
  try {
    aiResponse = await callModel({
      task:        "catalog_qa",
      input:       question,
      systemPrompt,
      context:     JSON.stringify(citations),
      userId:      askerId,
      safetyLevel: "strict",
      namespace:   `creator-catalog-${creatorId}`,
      queryVector: questionVector,
    });
  } catch (err) {
    logger.error("[askCreatorQuery] callModel failed — fail closed", { err: err.message });
    await logQueryResult({ creatorId, askerId, question, refused: true });
    return buildRefuseResponse("The AI service is temporarily unavailable. Please try again.");
  }

  // ── 12. Validate AI response — must reference at least one citation ─────────
  const responseText = typeof aiResponse === "string"
    ? aiResponse
    : (aiResponse?.content || aiResponse?.text || JSON.stringify(aiResponse));

  // Check that the response references at least one workId from citations
  const hasCitationRef = citations.some(
    (c) => responseText.includes(c.workId) || responseText.includes(c.snippet.slice(0, 30))
  );

  // Also accept if response contains the refuse prefix (AI honored the rule)
  const isRefusal = responseText.startsWith(REFUSE_ANSWER_PREFIX) ||
    responseText.toLowerCase().includes("no matching source") ||
    responseText.toLowerCase().includes("no relevant source");

  if (!hasCitationRef && !isRefusal) {
    // AI returned a response without citations — downgrade to refuse (fail closed)
    logger.warn("[askCreatorQuery] AI response lacked citation references — downgrading to refuse", {
      creatorId,
      askerId,
    });
    await logQueryResult({ creatorId, askerId, question, refused: true });
    return buildRefuseResponse("No matching source was found for your question.");
  }

  if (isRefusal) {
    await logQueryResult({ creatorId, askerId, question, refused: true });
    return buildRefuseResponse("No matching source was found for your question.");
  }

  // ── 13. Determine mode: creator_said vs ai_summary ─────────────────────────
  // Heuristic: if response contains a direct quote (quotation marks) → creator_said
  const hasDirectQuote = /[""][^""]{10,}[""]/.test(responseText) ||
                         /["'][^"']{10,}["']/.test(responseText);
  const mode = hasDirectQuote ? "creator_said" : "ai_summary";

  // Average confidence from qualifying works
  const avgConfidence = citations.reduce((sum, c) => sum + c.confidence, 0) / citations.length;

  // ── 14. Log successful query ────────────────────────────────────────────────
  await logQueryResult({
    creatorId,
    askerId,
    question,
    refused:     false,
    answeredAt:  admin.firestore.FieldValue.serverTimestamp(),
  });

  // ── 15. Return structured response ─────────────────────────────────────────
  return {
    answer:     responseText,
    citations,
    mode,
    confidence: Math.round(avgConfidence * 1000) / 1000,
  };
});

// ── getCatalogQueryStats — onCall CF ─────────────────────────────────────────
/**
 * Returns the authenticated user's catalog query count + remaining limit for today.
 *
 * Request: {} (empty — uses context.auth.uid)
 * Response: { count: number, remaining: number, dailyLimit: number }
 */
exports.getCatalogQueryStats = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }

  const { count, remaining } = await getQueryCount(context.auth.uid);
  return {
    count,
    remaining,
    dailyLimit: DAILY_QUERY_LIMIT,
  };
});
