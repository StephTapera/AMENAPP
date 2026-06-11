/**
 * routerCallable.js — Firebase callable wrappers that expose the callModel router.
 *
 * callModelTest   — lightweight test/debug callable (admin-only, require custom claim)
 * callModelBerean — production Berean answer callable (replaces bereanBibleQA direct calls)
 *                   This is the reference migration pattern: feature callables should
 *                   import callModel and route through it instead of calling providers directly.
 *
 * SECURITY: Every callable enforces:
 *   1. Firebase Auth (request.auth)
 *   2. Per-user rate limit via enforceRateLimit
 *   3. Input size cap (prevents prompt-stuffing)
 *   4. Secrets via defineSecret (never in response / logs)
 *
 * MIGRATION GUIDE — to wire an existing function through callModel:
 *   const { callModel } = require("./router/callModel");
 *   const result = await callModel({ task: "berean_answer", input: ..., userId: uid, ... });
 *   if (result.blocked) throw new HttpsError("failed-precondition", result.reason);
 *   return { content: result.output, provider: result.provider };
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret }       = require("firebase-functions/params");
const logger                 = require("firebase-functions/logger");
const { enforceRateLimit }   = require("./rateLimiter");
const { callModel }          = require("./router/callModel");

// Secrets injected by the Firebase runtime into process.env for each function.
// GEMINI_API_KEY is intentionally NOT declared here — the callModel router fetches
// it at runtime via getSecret() → Secret Manager if it exists.  Declaring it here
// would fail the deploy when the secret is absent from the project.
const ANTHROPIC_API_KEY  = defineSecret("ANTHROPIC_API_KEY");
const OPENAI_API_KEY     = defineSecret("OPENAI_API_KEY");
const NVIDIA_API_KEY     = defineSecret("NVIDIA_API_KEY");
const PINECONE_API_KEY   = defineSecret("PINECONE_API_KEY");
const PINECONE_HOST      = defineSecret("PINECONE_HOST");
const ALGOLIA_APP_ID     = defineSecret("ALGOLIA_APP_ID");
const ALGOLIA_ADMIN_KEY  = defineSecret("ALGOLIA_ADMIN_API_KEY");
const ALGOLIA_INDEX_NAME = defineSecret("ALGOLIA_INDEX_NAME");

// ── SHARED HELPERS ────────────────────────────────────────────────────────────

function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

function requireAdminClaim(request) {
  if (!request.auth?.token?.admin) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
}

function requireInputSize(text, maxChars = 4000) {
  if (!text || typeof text !== "string") {
    throw new HttpsError("invalid-argument", "input must be a non-empty string.");
  }
  if (text.length > maxChars) {
    throw new HttpsError("invalid-argument", `input exceeds ${maxChars} character limit.`);
  }
}

/**
 * Map a callModel result to an HttpsError when the router blocked the request.
 */
function handleRouterBlock(result) {
  if (!result.blocked) return;
  const reasonMap = {
    input_guard_failed:      ["failed-precondition", "Content did not pass safety review."],
    output_guard_failed:     ["failed-precondition", "Generated response did not pass safety review."],
    citations_required:      ["failed-precondition", "Unable to provide a grounded answer right now. Try again."],
    retrieval_failed:        ["unavailable",          "Knowledge base temporarily unavailable. Try again."],
    provider_unavailable:    ["unavailable",          "AI service temporarily unavailable. Try again shortly."],
    provider_chain_exhausted:["unavailable",          "AI service temporarily unavailable. Try again shortly."],
    feature_disabled:        ["failed-precondition",  "This feature is currently disabled."],
  };
  const [code, message] = reasonMap[result.reason] ?? ["internal", "Request could not be completed."];
  throw new HttpsError(code, message);
}

// ── callModelTest ─────────────────────────────────────────────────────────────
// Admin-only debug callable. Accepts any valid task key + input and returns the
// full router result including provider metadata. Never use in production UI.

exports.callModelTest = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 60,
    secrets: [ANTHROPIC_API_KEY, OPENAI_API_KEY, NVIDIA_API_KEY, PINECONE_API_KEY, PINECONE_HOST],
  },
  async (request) => {
    const uid = requireAuth(request);
    requireAdminClaim(request);

    const { task, input, systemPrompt, namespace } = request.data;
    if (!task || !input) throw new HttpsError("invalid-argument", "task and input are required.");
    requireInputSize(input, 2000);

    await enforceRateLimit(uid, "callModelTest", 20, 3600);

    logger.info("callModelTest", { uid, task });

    const result = await callModel({
      task,
      input,
      systemPrompt,
      userId: uid,
      namespace,
    });

    return {
      task: result.task,
      provider: result.provider,
      output: result.output,
      blocked: result.blocked ?? false,
      reason: result.reason,
      degraded: result.degraded ?? false,
      latencyMs: result.latencyMs,
    };
  },
);

// ── callModelBerean ───────────────────────────────────────────────────────────
// Production Berean answer callable — routes through the router with
// fail_closed + NVIDIA guards + Pinecone retrieval + citation validation.
// This is the reference implementation for how existing berean functions
// should be migrated to use the centralized router.

exports.callModelBerean = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 60,
    secrets: [ANTHROPIC_API_KEY, NVIDIA_API_KEY, PINECONE_API_KEY, PINECONE_HOST],
  },
  async (request) => {
    const uid = requireAuth(request);

    const { question, namespace = "berean", queryVector } = request.data;
    if (!question) throw new HttpsError("invalid-argument", "question is required.");
    requireInputSize(question, 1000);

    // 15 grounded answers per user per hour
    await enforceRateLimit(uid, "callModelBerean", 15, 3600);

    const systemPrompt = [
      "You are Berean, a scripture-grounded AI assistant for the AMEN faith community.",
      "Always cite specific Bible verses (e.g. John 3:16, Romans 8:28) to ground your answers.",
      "Clearly separate Scripture from interpretation. Flag uncertain answers.",
      "Never fabricate verse references. If you cannot ground an answer, say so honestly.",
      "Be pastoral, encouraging, and concise. Never manipulate or assert unsupported doctrine.",
    ].join("\n");

    const result = await callModel({
      task: "berean_answer",
      input: question,
      systemPrompt,
      userId: uid,
      namespace,
      queryVector: queryVector ?? undefined,
    });

    handleRouterBlock(result);

    return {
      answer: result.output,
      provider: result.provider,
      latencyMs: result.latencyMs,
    };
  },
);

// ── callModelCommentCoach ─────────────────────────────────────────────────────
// Comment coaching callable — routes through the router with Claude (fail_closed)
// + NVIDIA output guard. Returns coaching advice before the user posts.

exports.callModelCommentCoach = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 30,
    enforceAppCheck: true,
    secrets: [ANTHROPIC_API_KEY, NVIDIA_API_KEY],
  },
  async (request) => {
    const uid = requireAuth(request);

    const { commentText, postContext } = request.data;
    if (!commentText) throw new HttpsError("invalid-argument", "commentText is required.");
    requireInputSize(commentText, 2000);

    await enforceRateLimit(uid, "callModelCommentCoach", 60, 3600);

    const systemPrompt = [
      "You are a comment coach for a faith community app. Review the user's comment before they post it.",
      "Detect if it's impulsive, harsh, dismissive, or better suited for a private message or mentor conversation.",
      "Respond with JSON only: { action: 'publish'|'nudge'|'block', nudgeMessage?: string, rewriteSuggestion?: string }",
      "action=publish: comment is fine as-is.",
      "action=nudge: gentle suggestion to reconsider tone or channel.",
      "action=block: comment violates community standards (hate, threats, harassment, etc.).",
      "Never auto-post. This is advisory only — the user decides.",
    ].join("\n");

    const contextStr = postContext ? `Post being replied to: "${postContext}"` : "";

    const result = await callModel({
      task: "comment_coach",
      input: commentText,
      systemPrompt,
      context: contextStr,
      userId: uid,
    });

    handleRouterBlock(result);

    // Parse coach JSON; default to 'publish' if parsing fails (NVIDIA keyword gate still ran).
    let coaching = { action: "publish" };
    try {
      const parsed = JSON.parse(result.output ?? "{}");
      if (["publish", "nudge", "block"].includes(parsed.action)) {
        coaching = parsed;
      }
    } catch {
      logger.warn("callModelCommentCoach: failed to parse coach JSON", { uid });
    }

    return { coaching, provider: result.provider, latencyMs: result.latencyMs };
  },
);

// ── callModelDailyBrief ───────────────────────────────────────────────────────
// Daily brief generation — routes through Gemini (fast) with output guard.

exports.callModelDailyBrief = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 45,
    secrets: [OPENAI_API_KEY, NVIDIA_API_KEY],
  },
  async (request) => {
    const uid = requireAuth(request);

    const { userSummary, dateStr } = request.data;
    requireInputSize(userSummary ?? "", 1500);

    // 5 brief generations per user per day
    await enforceRateLimit(uid, "callModelDailyBrief", 5, 86400);

    const systemPrompt = [
      "You are the AMEN Daily Brief generator. Create a warm, personalized morning briefing.",
      "Format: JSON with keys: dailyVerse (reference + text), prayerReminder (string), reflectionQuestion (string), suggestedAction (string), greeting (string).",
      "Keep each field concise (1-3 sentences). Make it encouraging and faith-centered.",
      "Only include the JSON object in your response — no markdown code fences.",
    ].join("\n");

    const input = userSummary
      ? `Generate a daily brief for this user. Context: ${userSummary}. Date: ${dateStr ?? new Date().toDateString()}.`
      : `Generate a daily brief. Date: ${dateStr ?? new Date().toDateString()}.`;

    const result = await callModel({
      task: "daily_brief",
      input,
      systemPrompt,
      userId: uid,
    });

    if (result.degraded) {
      return { degraded: true, brief: null };
    }

    handleRouterBlock(result);

    let brief = null;
    try {
      brief = JSON.parse(result.output ?? "{}");
    } catch {
      brief = { greeting: result.output };
    }

    return { brief, provider: result.provider, latencyMs: result.latencyMs };
  },
);

// ── callModelSearch ───────────────────────────────────────────────────────────
// Universal keyword search via Algolia (permission-aware, private-content protected).
// Secrets are declared here so the runtime injects ALGOLIA_APP_ID etc. into process.env.

exports.callModelSearch = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 20,
    secrets: [ALGOLIA_APP_ID, ALGOLIA_ADMIN_KEY, ALGOLIA_INDEX_NAME],
  },
  async (request) => {
    const uid = requireAuth(request);

    const { query, filters = {} } = request.data;
    if (!query || typeof query !== "string") {
      throw new HttpsError("invalid-argument", "query is required.");
    }
    requireInputSize(query, 500);

    await enforceRateLimit(uid, "callModelSearch", 60, 3600);

    const result = await callModel({
      task: "universal_search",
      input: query,
      userId: uid,
    });

    if (result.degraded) {
      return { hits: [], degraded: true };
    }

    handleRouterBlock(result);

    return { hits: result.output?.hits ?? [], provider: result.provider };
  },
);
