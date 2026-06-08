/**
 * callModel({ task, input, systemPrompt, context, userId, safetyLevel,
 *             featureFlags, namespace, queryVector })
 *
 * Centralized AI router for AMEN. Provider choice is config-driven (amenRouting.config.js);
 * feature code NEVER hardcodes a provider name or API endpoint.
 *
 * Pipeline for every call:
 *   1. Feature-flag gate
 *   2. NVIDIA input guardrail (if route.inputGuard)
 *   3. Pinecone retrieval (if route.retrieval === "pinecone")
 *   4. Primary provider call (Claude / OpenAI / Gemini / NVIDIA / Pinecone / Algolia)
 *   5. Fail policy on error (fail_closed | failover | degrade)
 *   6. Citation validation (if route.requireCitations)
 *   7. NVIDIA output guardrail (if route.outputGuard)
 *   8. Structured log: provider, task, latency, moderation decision
 *
 * Fail policies:
 *   fail_closed  — block and return safe error; never fabricate or downgrade safety
 *   failover     — try providers in chain order until one succeeds
 *   degrade      — return route.degradeResult (documented reduced-capability result)
 *
 * Secrets are resolved lazily via getSecret() which caches in-process.
 * This module is a library, not a Firebase Function — import it inside onCall handlers.
 */

"use strict";

const logger = require("firebase-functions/logger");
const { getSecret, pineconeQuery, pineconeUpsert } = require("../mlClients");
const { PROVIDERS, ROUTING } = require("./amenRouting.config");

// ── CONSTANTS ────────────────────────────────────────────────────────────────

const NVIDIA_NIM_URL   = "https://integrate.api.nvidia.com/v1/chat/completions";
const ANTHROPIC_URL    = "https://api.anthropic.com/v1/messages";
const OPENAI_URL       = "https://api.openai.com/v1/chat/completions";
const ANTHROPIC_VERSION = "2023-06-01";

const DEFAULT_MAX_TOKENS  = 1024;
const DEFAULT_TEMPERATURE = 0.7;
const CALL_TIMEOUT_MS     = 30_000;   // 30 s per provider call
const GUARD_TIMEOUT_MS    = 10_000;   // 10 s for NVIDIA guard (keep tight)

// ── SCRIPTURE CITATION VALIDATOR ─────────────────────────────────────────────
// Matches "Book Chapter:Verse" — used to enforce requireCitations.
// Partial book abbreviations included (Gen, Exod, Ps, etc.).

const SCRIPTURE_RE = /\b(?:Genesis|Exodus|Leviticus|Numbers|Deuteronomy|Joshua|Judges|Ruth|(?:1|2)\s*Samuel|(?:1|2)\s*Kings|(?:1|2)\s*Chronicles|Ezra|Nehemiah|Esther|Job|Psalms?|Proverbs|Ecclesiastes|Song of Solomon|Isaiah|Jeremiah|Lamentations|Ezekiel|Daniel|Hosea|Joel|Amos|Obadiah|Jonah|Micah|Nahum|Habakkuk|Zephaniah|Haggai|Zechariah|Malachi|Matthew|Mark|Luke|John|Acts|Romans|(?:1|2)\s*Corinthians|Galatians|Ephesians|Philippians|Colossians|(?:1|2)\s*Thessalonians|(?:1|2)\s*Timothy|Titus|Philemon|Hebrews|James|(?:1|2)\s*Peter|(?:1|2|3)\s*John|Jude|Revelation|Gen|Exod?|Lev|Num|Deut?|Josh|Judg|Sam|Kgs|Chr|Ezr|Neh|Est|Ps|Prov|Eccl|Isa|Jer|Lam|Ezek?|Dan|Hos|Obad|Jon|Mic|Nah|Hab|Zeph|Hag|Zech|Mal|Matt?|Mk|Lk|Jn|Rom|Cor|Gal|Eph|Phil|Col|Thess?|Tim|Tit|Phlm|Heb|Jas|Pet|Rev)\s+\d+:\d+/gi;

function validateCitations(text) {
  const matches = text.match(SCRIPTURE_RE) ?? [];
  return { valid: matches.length > 0, citations: matches };
}

// ── PROVIDER ADAPTERS ────────────────────────────────────────────────────────

/**
 * Call Anthropic Claude via direct fetch (no SDK — matches existing project style).
 * System prompt is passed as a top-level field per Anthropic's Messages API.
 */
async function callClaude({ model, systemPrompt, userMessage, maxTokens = DEFAULT_MAX_TOKENS, temperature = DEFAULT_TEMPERATURE }) {
  const apiKey = await getSecret("ANTHROPIC_API_KEY");
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY secret not available");

  const body = {
    model,
    max_tokens: maxTokens,
    temperature,
    messages: [{ role: "user", content: userMessage }],
  };
  if (systemPrompt) body.system = systemPrompt;

  const res = await fetch(ANTHROPIC_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
  });

  if (!res.ok) {
    const errText = await res.text().catch(() => "");
    throw new Error(`Claude ${res.status}: ${errText.slice(0, 200)}`);
  }
  const data = await res.json();
  return data.content?.[0]?.text ?? "";
}

/**
 * Call OpenAI chat completions via direct fetch.
 * System prompt is the first message with role "system".
 */
async function callOpenAI({ model, systemPrompt, userMessage, maxTokens = DEFAULT_MAX_TOKENS, temperature = DEFAULT_TEMPERATURE }) {
  const apiKey = await getSecret("OPENAI_API_KEY");
  if (!apiKey) throw new Error("OPENAI_API_KEY secret not available");

  const messages = [];
  if (systemPrompt) messages.push({ role: "system", content: systemPrompt });
  messages.push({ role: "user", content: userMessage });

  const res = await fetch(OPENAI_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({ model, messages, max_tokens: maxTokens, temperature }),
    signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
  });

  if (!res.ok) {
    const errText = await res.text().catch(() => "");
    throw new Error(`OpenAI ${res.status}: ${errText.slice(0, 200)}`);
  }
  const data = await res.json();
  return data.choices?.[0]?.message?.content ?? "";
}

/**
 * Call Google Gemini via the @google/generative-ai SDK.
 * Combines system prompt + user message into a single content string for Flash.
 */
async function callGemini({ model, systemPrompt, userMessage }) {
  const apiKey = await getSecret("GEMINI_API_KEY");
  if (!apiKey) throw new Error("GEMINI_API_KEY secret not available");

  const { GoogleGenerativeAI } = require("@google/generative-ai");
  const genAI = new GoogleGenerativeAI(apiKey);
  const genModel = genAI.getGenerativeModel({ model });

  const parts = systemPrompt
    ? `${systemPrompt}\n\n${userMessage}`
    : userMessage;

  const result = await genModel.generateContent({
    contents: [{ role: "user", parts: [{ text: parts }] }],
  });
  return result.response.text();
}

/**
 * Call NVIDIA NeMo Guard for input/output safety checks.
 * Returns { safe: boolean, categories: string }.
 * NEVER throws on AI error — returns { safe: false, categories: "guard_error" } to
 * enforce fail-closed semantics from the caller.
 */
async function callNvidiaGuard(text) {
  const apiKey = await getSecret("NVIDIA_API_KEY");
  if (!apiKey) {
    logger.warn("callModel: NVIDIA_API_KEY unavailable — guard failing closed");
    return { safe: false, categories: "guard_unavailable" };
  }

  try {
    const res = await fetch(NVIDIA_NIM_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: PROVIDERS.nvidia.model,
        messages: [{ role: "user", content: text }],
        max_tokens: 120,
        temperature: 0,
      }),
      signal: AbortSignal.timeout(GUARD_TIMEOUT_MS),
    });

    if (!res.ok) return { safe: false, categories: `guard_http_${res.status}` };

    const data = await res.json();
    const raw = data.choices?.[0]?.message?.content ?? "";

    // NeMo returns structured JSON: {"User Safety": "safe"|"unsafe", "Safety Categories": "..."}
    try {
      const parsed = JSON.parse(raw);
      const isSafe = (parsed["User Safety"] ?? "").toLowerCase() === "safe";
      return { safe: isSafe, categories: parsed["Safety Categories"] ?? "" };
    } catch {
      // Plain-text fallback: look for "safe" / "unsafe"
      const lower = raw.toLowerCase();
      const isSafe = lower.includes("safe") && !lower.includes("unsafe");
      return { safe: isSafe, categories: raw.slice(0, 120) };
    }
  } catch (err) {
    logger.error("callModel: NVIDIA guard threw", { error: err.message });
    return { safe: false, categories: "guard_error" };
  }
}

// ── PINECONE ADAPTERS ─────────────────────────────────────────────────────────

/**
 * Retrieve top-K chunks from Pinecone for a given namespace + query vector.
 * Returns array of text strings from match metadata, or [] on error.
 */
async function retrieveFromPinecone(namespace, queryVector, topK = 5) {
  try {
    const result = await pineconeQuery(namespace, queryVector, topK);
    return (result?.matches ?? [])
      .map((m) => m.metadata?.text ?? "")
      .filter(Boolean);
  } catch (err) {
    throw new Error(`Pinecone retrieval failed: ${err.message}`);
  }
}

// ── ALGOLIA ADAPTER ───────────────────────────────────────────────────────────
// Uses the Algolia REST Search API directly (same direct-fetch pattern as all
// other providers in this file — no SDK, no new npm dependency).
// Private-content protection: algoliaSync.js never indexes privacy==="private"
// posts; further per-user facetFilters can be added to the body if needed.

async function searchAlgolia(query) {
  const appId   = process.env.ALGOLIA_APP_ID        || await getSecret("ALGOLIA_APP_ID");
  const apiKey  = process.env.ALGOLIA_ADMIN_API_KEY  || await getSecret("ALGOLIA_ADMIN_API_KEY");
  const idxName = process.env.ALGOLIA_INDEX_NAME     || await getSecret("ALGOLIA_INDEX_NAME") || "posts";

  if (!appId || !apiKey) throw new Error("Algolia credentials not available");

  const url = `https://${appId}-dsn.algolia.net/1/indexes/${encodeURIComponent(idxName)}/query`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Algolia-Application-Id": appId,
      "X-Algolia-API-Key": apiKey,
    },
    body: JSON.stringify({
      query,
      hitsPerPage: 20,
      attributesToRetrieve: ["objectID", "text", "authorId", "authorName", "category", "createdAt"],
    }),
    signal: AbortSignal.timeout(10_000),
  });

  if (!res.ok) throw new Error(`Algolia search ${res.status}: ${await res.text().catch(() => "")}`);
  const data = await res.json();
  return { hits: data.hits ?? [] };
}

// ── DISPATCH PER PROVIDER KEY ─────────────────────────────────────────────────

async function dispatchProvider(providerKey, { systemPrompt, userMessage }) {
  const p = PROVIDERS[providerKey];
  if (!p) throw new Error(`callModel: unknown provider key "${providerKey}"`);

  switch (p.id) {
    case "anthropic":
      return callClaude({ model: p.model, systemPrompt, userMessage });
    case "openai":
      return callOpenAI({ model: p.model, systemPrompt, userMessage });
    case "google":
      return callGemini({ model: p.model, systemPrompt, userMessage });
    case "nvidia":
      // When dispatched as primary (guard tasks), run the guard and return structured result.
      return callNvidiaGuard(userMessage);
    case "pinecone":
      // Pinecone as primary task (vector_retrieve, ai_memory_*) — not a text generation.
      throw new Error("Pinecone tasks must be handled by the caller; use retrieveFromPinecone()");
    case "algolia":
      return searchAlgolia(userMessage);
    default:
      throw new Error(`callModel: no handler for provider id "${p.id}"`);
  }
}

// ── MAIN EXPORTED FUNCTION ────────────────────────────────────────────────────

/**
 * callModel({ task, input, systemPrompt, context, userId, safetyLevel,
 *             featureFlags, namespace, queryVector })
 *
 * @param {object}   opts
 * @param {string}   opts.task         — Key from ROUTING (e.g. "berean_answer")
 * @param {string}   opts.input        — Raw user input text
 * @param {string}  [opts.systemPrompt]— Task-specific system prompt (caller may override)
 * @param {string}  [opts.context]     — Extra context injected into system prompt
 * @param {string}   opts.userId       — Authenticated UID (required for audit logs)
 * @param {string}  [opts.safetyLevel] — "strict"|"standard"|"relaxed" (default: "standard")
 * @param {object}  [opts.featureFlags]— Map of task → boolean; false disables that task
 * @param {string}  [opts.namespace]   — Pinecone namespace for retrieval
 * @param {number[]} [opts.queryVector]— Embedding vector for Pinecone search
 *
 * @returns {Promise<CallModelResult>}
 *
 * CallModelResult:
 *   { output: string, provider: string, task: string, latencyMs: number }       — success
 *   { output: null, blocked: true, reason: string, ... }                        — blocked
 *   { output: any,  degraded: true, task: string }                              — degraded
 */
async function callModel({
  task,
  input,
  systemPrompt,
  context,
  userId,
  safetyLevel = "standard",
  featureFlags = {},
  namespace,
  queryVector,
}) {
  const startMs = Date.now();
  const route = ROUTING[task];

  // ── Guard: task must exist ────────────────────────────────────────────────
  if (!route) {
    logger.error("callModel: unknown task", { task, userId });
    throw new Error(`callModel: unknown task "${task}"`);
  }

  // ── Guard: feature flag ───────────────────────────────────────────────────
  if (featureFlags[task] === false) {
    logger.info("callModel: task disabled by feature flag", { task, userId });
    return { output: null, blocked: true, reason: "feature_disabled", task };
  }

  logger.info("callModel.start", {
    task,
    userId,
    primary: route.primary,
    safetyLevel,
    hasQueryVector: !!queryVector,
  });

  // ── Step 1: NVIDIA input guardrail ───────────────────────────────────────
  if (route.inputGuard) {
    const guard = await callNvidiaGuard(input);
    if (!guard.safe) {
      logger.warn("callModel: input blocked by NVIDIA guard", { task, userId, categories: guard.categories });
      return {
        output: null,
        blocked: true,
        reason: "input_guard_failed",
        categories: guard.categories,
        provider: "nvidia",
        task,
        latencyMs: Date.now() - startMs,
      };
    }
  }

  // ── Step 2: Pinecone retrieval ────────────────────────────────────────────
  let retrievedContext = "";
  if (route.retrieval === "pinecone" && queryVector && namespace) {
    try {
      const chunks = await retrieveFromPinecone(namespace, queryVector, 5);
      retrievedContext = chunks.join("\n\n");
    } catch (err) {
      if (route.requireCitations) {
        // Grounded tasks can't answer without retrieval — fail closed.
        logger.error("callModel: Pinecone retrieval failed (fail_closed — citations required)", {
          task, userId, error: err.message,
        });
        return {
          output: null,
          blocked: true,
          reason: "retrieval_failed",
          provider: "pinecone",
          task,
          latencyMs: Date.now() - startMs,
        };
      }
      logger.warn("callModel: Pinecone retrieval failed (degrading to no-context)", { task, userId, error: err.message });
    }
  }

  // ── Step 3: Build effective system prompt ─────────────────────────────────
  const contextParts = [];
  if (retrievedContext) contextParts.push(`RETRIEVED CONTEXT:\n${retrievedContext}`);
  if (context)          contextParts.push(`ADDITIONAL CONTEXT:\n${context}`);

  const effectiveSystem = contextParts.length > 0
    ? `${systemPrompt ?? "You are a helpful assistant."}\n\n${contextParts.join("\n\n")}`
    : (systemPrompt ?? "You are a helpful assistant.");

  // ── Step 4: Try providers per fail policy ─────────────────────────────────
  let output = null;
  let usedProvider = null;
  let lastError = null;

  for (const providerKey of route.chain) {
    try {
      output = await dispatchProvider(providerKey, {
        systemPrompt: effectiveSystem,
        userMessage: input,
      });
      usedProvider = providerKey;
      break;
    } catch (err) {
      lastError = err;
      logger.warn("callModel: provider failed", {
        task, userId, provider: providerKey, error: err.message,
      });
      if (route.fail === "fail_closed") {
        // Do NOT try next provider for pastoral / safety tasks.
        break;
      }
      // For "failover": continue to next in chain.
    }
  }

  // ── Fail-policy resolution when all providers failed ─────────────────────
  if (output === null) {
    if (route.fail === "degrade") {
      logger.warn("callModel: all providers failed — degrading", { task, userId });
      return {
        output: route.degradeResult ?? null,
        degraded: true,
        task,
        latencyMs: Date.now() - startMs,
      };
    }
    // fail_closed or failover exhausted
    logger.error("callModel: chain exhausted", {
      task, userId, failPolicy: route.fail, error: lastError?.message,
    });
    return {
      output: null,
      blocked: true,
      reason: "provider_unavailable",
      task,
      latencyMs: Date.now() - startMs,
    };
  }

  // ── Step 5: Citation validation ───────────────────────────────────────────
  if (route.requireCitations) {
    // For NVIDIA guard tasks, output is a structured object — skip text citation check.
    const outputText = typeof output === "string" ? output : JSON.stringify(output);
    const citationCheck = validateCitations(outputText);
    if (!citationCheck.valid) {
      logger.warn("callModel: response lacks scripture citations (fail_closed)", {
        task, userId, provider: usedProvider,
      });
      return {
        output: null,
        blocked: true,
        reason: "citations_required",
        task,
        provider: usedProvider,
        latencyMs: Date.now() - startMs,
      };
    }
  }

  // ── Step 6: NVIDIA output guardrail ──────────────────────────────────────
  if (route.outputGuard && typeof output === "string") {
    const guard = await callNvidiaGuard(output);
    if (!guard.safe) {
      logger.warn("callModel: output blocked by NVIDIA guard", {
        task, userId, provider: usedProvider, categories: guard.categories,
      });
      return {
        output: null,
        blocked: true,
        reason: "output_guard_failed",
        categories: guard.categories,
        provider: usedProvider,
        task,
        latencyMs: Date.now() - startMs,
      };
    }
  }

  // ── Step 7: Structured success log ───────────────────────────────────────
  const latencyMs = Date.now() - startMs;
  logger.info("callModel.complete", {
    task,
    userId,
    provider: usedProvider,
    providerModel: PROVIDERS[usedProvider]?.model,
    latencyMs,
    inputGuardApplied: !!route.inputGuard,
    outputGuardApplied: !!route.outputGuard,
    retrievalApplied: !!(route.retrieval && queryVector),
    citationsValidated: !!route.requireCitations,
  });

  return { output, provider: usedProvider, task, latencyMs };
}

// ── NAMED EXPORTS ─────────────────────────────────────────────────────────────

module.exports = {
  callModel,
  // Expose internals for unit testing only — do NOT use in feature code.
  _internal: {
    callClaude,
    callOpenAI,
    callGemini,
    callNvidiaGuard,
    retrieveFromPinecone,
    validateCitations,
    ROUTING,
    PROVIDERS,
  },
};
