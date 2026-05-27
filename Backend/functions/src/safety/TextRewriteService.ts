/**
 * TextRewriteService.ts
 *
 * AI-assisted "Rewrite Instead" service for the Amen Safety OS.
 *
 * WHY THIS EXISTS:
 *   When content moderation blocks a user's post, comment, or message, a hard
 *   rejection is demoralizing and teaches nothing. This service pairs with
 *   TextModerationService to offer a constructive alternative: Claude suggests
 *   healthier rephrasing so the user can still participate in the community.
 *
 * CALLABLES:
 *   requestTextRewrite      — Called after a moderation block. Returns 2 alternative
 *                             phrasings tailored to the detected harm category.
 *   getToneCheckSuggestion  — Called proactively before submission. Returns a single
 *                             reframing suggestion if the text could be more
 *                             constructive for a faith community, or null if the
 *                             text is already good.
 *
 * EXPORTED HELPER:
 *   suggestRewrite          — Internal async helper for other backend services to
 *                             obtain rewrite suggestions without going through a
 *                             callable boundary.
 *
 * PRIVACY:
 *   The user's original text is NEVER written to Firestore or to any log.
 *   Audit entries record only uid, harmCategoryId, contentType, and timestamp.
 *
 * RATE LIMITS:
 *   requestTextRewrite      — 10 rewrites per user per hour
 *   getToneCheckSuggestion  — 30 tone checks per user per hour
 *
 * MODEL:
 *   claude-3-haiku-20240307 — fast and cost-effective for short rewrite tasks.
 *   Credentials read from process.env.ANTHROPIC_API_KEY (never from the client).
 *
 * FAILURE MODE:
 *   All Claude calls fail gracefully. If the model is unavailable or returns
 *   unparseable output, empty suggestions and a generic rationale are returned
 *   rather than throwing. The user can always edit manually.
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import axios from "axios";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Constants ────────────────────────────────────────────────────────────────

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const CLAUDE_MODEL = "claude-3-haiku-20240307";
const MAX_TOKENS = 400;

/** Max input text length (characters) accepted by both callables. */
const MAX_TEXT_LENGTH = 2000;

/** Max harmCategoryId string length. */
const MAX_HARM_CATEGORY_ID_LENGTH = 50;

/** Rewrites collection — stores request metadata (NOT original text). */
const REWRITE_LOGS_COLLECTION = "textRewriteLogs";

/** Rate-limit collection path mirrors rateLimit.ts convention for rewrite windows. */
const REWRITE_RATE_LIMIT_COLLECTION = "rewriteRateLimits";

/** Max rewrites allowed per hour for requestTextRewrite. */
const REWRITE_HOURLY_MAX = 10;

/** Max tone checks allowed per hour for getToneCheckSuggestion. */
const TONE_CHECK_HOURLY_MAX = 30;

/** Window duration: 1 hour in milliseconds. */
const WINDOW_MS = 3_600_000;

// ─── Exported Result Type ─────────────────────────────────────────────────────

export interface TextRewriteResult {
  suggestions: string[];
  rationale: string;
  harmCategoryId: string;
}

// ─── Internal Types ───────────────────────────────────────────────────────────

interface TextRewriteRequest {
  text: string;
  harmCategoryId: string;
  contentType: string;
}

interface ToneCheckRequest {
  text: string;
  contentType: string;
}

interface ToneCheckResult {
  suggestion: string | null;
  reason: string | null;
}

/** Expected shape of Claude's JSON response for rewrite requests. */
interface ClaudeRewritePayload {
  suggestions: string[];
  rationale: string;
}

/** Expected shape of Claude's JSON response for tone-check requests. */
interface ClaudeTonePayload {
  suggestion: string | null;
  reason: string | null;
}

/** Sliding-window rate-limit document stored in Firestore. */
interface RateLimitWindow {
  count: number;
  windowEnd: number;
  uid: string;
}

// ─── Anthropic API Helper ─────────────────────────────────────────────────────

interface AnthropicMessage {
  role: "user";
  content: string;
}

interface AnthropicRequest {
  model: string;
  max_tokens: number;
  system: string;
  messages: AnthropicMessage[];
}

interface AnthropicContentBlock {
  type: string;
  text?: string;
}

interface AnthropicResponse {
  content: AnthropicContentBlock[];
}

/**
 * Calls the Anthropic Claude API with the given system and user prompts.
 * Returns the raw text content of the first content block, or null if the
 * call fails or the response is empty.
 *
 * Never throws — callers must handle a null return as a graceful degradation.
 */
async function callClaude(systemPrompt: string, userPrompt: string): Promise<string | null> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    logger.warn("[TextRewriteService] ANTHROPIC_API_KEY is not set — skipping Claude call.");
    return null;
  }

  const body: AnthropicRequest = {
    model: CLAUDE_MODEL,
    max_tokens: MAX_TOKENS,
    system: systemPrompt,
    messages: [{ role: "user", content: userPrompt }],
  };

  try {
    const response = await axios.post<AnthropicResponse>(
      ANTHROPIC_API_URL,
      body,
      {
        headers: {
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
          "content-type": "application/json",
        },
        timeout: 8000,
      }
    );

    const block = response.data.content?.[0];
    if (block?.type === "text" && typeof block.text === "string" && block.text.trim().length > 0) {
      return block.text.trim();
    }

    logger.warn("[TextRewriteService] Claude response was empty or had no text block.");
    return null;
  } catch (err) {
    logger.warn("[TextRewriteService] Claude API call failed — failing gracefully.", err);
    return null;
  }
}

/**
 * Strips markdown code fences that Claude sometimes wraps JSON in,
 * then parses and returns the object. Returns null on any parse failure.
 */
function parseClaudeJson<T>(raw: string): T | null {
  const cleaned = raw
    .replace(/^```(?:json)?\s*/m, "")
    .replace(/\s*```$/m, "")
    .trim();

  try {
    return JSON.parse(cleaned) as T;
  } catch {
    logger.warn("[TextRewriteService] Failed to parse Claude JSON.", { preview: raw.slice(0, 200) });
    return null;
  }
}

// ─── Rate Limiting ────────────────────────────────────────────────────────────

/**
 * Enforces a per-user sliding-window rate limit stored in:
 *   rewriteRateLimits/{uid}/windows/{windowId}
 *
 * Uses a Firestore transaction to atomically read and increment the counter.
 * Throws HttpsError("resource-exhausted") if the limit is exceeded.
 *
 * @param uid       Authenticated user UID.
 * @param limitName Logical name embedded in the window document ID (e.g. "rewrite").
 * @param maxCalls  Maximum allowed calls within the 1-hour window.
 */
async function enforceRewriteRateLimit(
  uid: string,
  limitName: string,
  maxCalls: number
): Promise<void> {
  const now = Date.now();
  const windowStart = Math.floor(now / WINDOW_MS) * WINDOW_MS;
  const windowEnd = windowStart + WINDOW_MS;
  const windowId = `${limitName}_${windowStart}`;

  const ref = db
    .collection(REWRITE_RATE_LIMIT_COLLECTION)
    .doc(uid)
    .collection("windows")
    .doc(windowId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? (snap.data() as RateLimitWindow) : null;

    // If the stored window has expired, treat count as zero.
    const currentCount = data && data.windowEnd > now ? data.count : 0;

    if (currentCount >= maxCalls) {
      const retryAfterSec = Math.ceil((windowEnd - now) / 1000);
      logger.warn(
        `[TextRewriteService] Rate limit exceeded — uid=${uid} limit=${limitName} ` +
        `count=${currentCount}/${maxCalls}`
      );
      throw new HttpsError(
        "resource-exhausted",
        `Too many rewrite requests. Please wait ${retryAfterSec} seconds before trying again.`
      );
    }

    tx.set(ref, {
      count: currentCount + 1,
      windowEnd,
      uid,
    } satisfies RateLimitWindow);
  });
}

// ─── Audit Logging ────────────────────────────────────────────────────────────

/**
 * Writes an audit entry for a rewrite request.
 * The user's original text is deliberately excluded for privacy.
 */
async function logRewriteRequest(
  uid: string,
  harmCategoryId: string,
  contentType: string
): Promise<void> {
  try {
    await db.collection(REWRITE_LOGS_COLLECTION).add({
      uid,
      harmCategoryId,
      contentType,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    // Non-fatal — a logging failure must never surface to the caller.
    logger.warn("[TextRewriteService] Failed to write rewrite audit log.", err);
  }
}

// ─── Rewrite Prompt Builders ──────────────────────────────────────────────────

const REWRITE_SYSTEM_PROMPT =
  "You are a compassionate communication coach helping someone express themselves in a healthier, " +
  "more constructive way. The platform is a faith-based community. Never reproduce harmful content. " +
  "Return ONLY a JSON object.";

/**
 * Builds the user-facing prompt for the rewrite callable.
 * Instructs Claude to return exactly two alternative phrasings.
 */
function buildRewriteUserPrompt(harmCategoryId: string, text: string): string {
  return (
    `A message was flagged for the following concern: "${harmCategoryId}".\n\n` +
    `Help the user express their underlying thought or feeling in a way that is kind, ` +
    `constructive, and appropriate for a faith-based community.\n\n` +
    `Original message length: ${text.length} characters (content withheld for safety).\n\n` +
    `Provide exactly 2 alternative phrasings. ` +
    `Return ONLY a JSON object in this exact shape:\n` +
    `{ "suggestions": ["<option 1>", "<option 2>"], "rationale": "<one sentence explaining the concern>" }\n\n` +
    `Here is the original message:\n"""\n${text}\n"""`
  );
}

const TONE_SYSTEM_PROMPT =
  "You are a compassionate communication coach helping someone express themselves in a healthier, " +
  "more constructive way. The platform is a faith-based community. Never reproduce harmful content. " +
  "Return ONLY a JSON object.";

/**
 * Builds the user-facing prompt for the tone-check callable.
 * Claude should return null fields if the text is already fine.
 */
function buildToneCheckUserPrompt(text: string, contentType: string): string {
  return (
    `Review the following ${contentType} message for tone. ` +
    `If it is already kind, respectful, and appropriate for a faith-based community, ` +
    `return { "suggestion": null, "reason": null }.\n\n` +
    `If it could be expressed more constructively without changing the meaning, ` +
    `suggest ONE improved phrasing and explain why in one sentence.\n\n` +
    `Return ONLY a JSON object in this exact shape:\n` +
    `{ "suggestion": "<improved phrasing or null>", "reason": "<one sentence or null>" }\n\n` +
    `Message to review:\n"""\n${text}\n"""`
  );
}

// ─── Exported Async Helper ────────────────────────────────────────────────────

/**
 * suggestRewrite
 *
 * Internal helper called by other backend services (e.g. moderation triggers)
 * when they want to immediately surface alternative phrasings alongside a block.
 *
 * Does NOT enforce rate limits or write audit logs — those are the caller's
 * responsibility. Never throws; returns an empty array if Claude is unavailable.
 *
 * @param text           The text that was blocked (used for context only; not logged).
 * @param harmCategoryId The harm category that triggered the block.
 * @returns              Up to 2 suggested alternative phrasings, or [] on failure.
 */
export async function suggestRewrite(text: string, harmCategoryId: string): Promise<string[]> {
  if (!text || text.trim().length === 0) return [];

  const userPrompt = buildRewriteUserPrompt(harmCategoryId, text);
  const raw = await callClaude(REWRITE_SYSTEM_PROMPT, userPrompt);

  if (!raw) return [];

  const parsed = parseClaudeJson<ClaudeRewritePayload>(raw);
  if (!parsed || !Array.isArray(parsed.suggestions)) return [];

  return parsed.suggestions.filter((s) => typeof s === "string" && s.trim().length > 0);
}

// ─── Callables ────────────────────────────────────────────────────────────────

/**
 * requestTextRewrite
 *
 * Called by the iOS app when a user's content is blocked by moderation.
 * Returns two alternative phrasings and a brief rationale so the user can
 * understand the concern and participate constructively.
 *
 * Input:
 *   text           — The blocked text (≤ 2000 chars).
 *   harmCategoryId — The harm category that triggered the block (≤ 50 chars).
 *   contentType    — Surface the content was posted to (e.g. "post", "comment").
 *
 * Output: TextRewriteResult
 *   suggestions    — Array of 0–2 rewritten alternatives (empty on Claude failure).
 *   rationale      — One-sentence explanation of the concern.
 *   harmCategoryId — Echo of the input harmCategoryId.
 */
export const requestTextRewrite = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<TextRewriteRequest>): Promise<TextRewriteResult> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const { text, harmCategoryId, contentType } = request.data;

    // ── Input validation ──────────────────────────────────────────────────────
    if (typeof text !== "string" || text.trim().length === 0) {
      throw new HttpsError("invalid-argument", "text is required.");
    }
    if (text.length > MAX_TEXT_LENGTH) {
      throw new HttpsError(
        "invalid-argument",
        `text must be ${MAX_TEXT_LENGTH} characters or fewer.`
      );
    }
    if (typeof harmCategoryId !== "string" || harmCategoryId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "harmCategoryId is required.");
    }
    if (harmCategoryId.length > MAX_HARM_CATEGORY_ID_LENGTH) {
      throw new HttpsError(
        "invalid-argument",
        `harmCategoryId must be ${MAX_HARM_CATEGORY_ID_LENGTH} characters or fewer.`
      );
    }
    if (typeof contentType !== "string" || contentType.trim().length === 0) {
      throw new HttpsError("invalid-argument", "contentType is required.");
    }

    // ── Rate limit ────────────────────────────────────────────────────────────
    await enforceRewriteRateLimit(uid, "rewrite", REWRITE_HOURLY_MAX);

    // ── Audit log (no original text stored) ──────────────────────────────────
    await logRewriteRequest(uid, harmCategoryId, contentType);

    // ── Claude call ───────────────────────────────────────────────────────────
    const userPrompt = buildRewriteUserPrompt(harmCategoryId, text);
    const raw = await callClaude(REWRITE_SYSTEM_PROMPT, userPrompt);

    if (!raw) {
      // Graceful fallback: Claude unavailable
      logger.info(`[TextRewriteService] requestTextRewrite — Claude unavailable, returning fallback. uid=${uid}`);
      return {
        suggestions: [],
        rationale:
          "We were unable to generate suggestions right now. Please edit your message to " +
          "ensure it is kind and constructive before reposting.",
        harmCategoryId,
      };
    }

    const parsed = parseClaudeJson<ClaudeRewritePayload>(raw);

    if (!parsed || !Array.isArray(parsed.suggestions)) {
      logger.warn(`[TextRewriteService] requestTextRewrite — unparseable Claude response. uid=${uid}`);
      return {
        suggestions: [],
        rationale:
          "We were unable to generate suggestions right now. Please edit your message " +
          "manually and try again.",
        harmCategoryId,
      };
    }

    const suggestions = parsed.suggestions
      .filter((s) => typeof s === "string" && s.trim().length > 0)
      .slice(0, 2);

    const rationale =
      typeof parsed.rationale === "string" && parsed.rationale.trim().length > 0
        ? parsed.rationale
        : "Your message was flagged by our content policy. The suggestions above offer a " +
          "more constructive way to share your thoughts.";

    return { suggestions, rationale, harmCategoryId };
  }
);

/**
 * getToneCheckSuggestion
 *
 * A lighter, proactive tone coach that can be called before submission
 * (no content block required). If the text is already respectful and on-topic
 * for a faith community, Claude returns null for both fields and this function
 * returns { suggestion: null, reason: null }.
 *
 * Input:
 *   text        — The text to review (≤ 2000 chars).
 *   contentType — Surface context (e.g. "post", "comment", "dm").
 *
 * Output: ToneCheckResult
 *   suggestion  — A single rewritten alternative, or null if text is already good.
 *   reason      — A one-sentence coaching note, or null if text is already good.
 */
export const getToneCheckSuggestion = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<ToneCheckRequest>): Promise<ToneCheckResult> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const { text, contentType } = request.data;

    // ── Input validation ──────────────────────────────────────────────────────
    if (typeof text !== "string" || text.trim().length === 0) {
      throw new HttpsError("invalid-argument", "text is required.");
    }
    if (text.length > MAX_TEXT_LENGTH) {
      throw new HttpsError(
        "invalid-argument",
        `text must be ${MAX_TEXT_LENGTH} characters or fewer.`
      );
    }
    if (typeof contentType !== "string" || contentType.trim().length === 0) {
      throw new HttpsError("invalid-argument", "contentType is required.");
    }

    // ── Rate limit ────────────────────────────────────────────────────────────
    await enforceRewriteRateLimit(uid, "tone_check", TONE_CHECK_HOURLY_MAX);

    // ── Claude call ───────────────────────────────────────────────────────────
    const userPrompt = buildToneCheckUserPrompt(text, contentType);
    const raw = await callClaude(TONE_SYSTEM_PROMPT, userPrompt);

    if (!raw) {
      // Graceful fallback: Claude unavailable — treat as "text is fine"
      logger.info(`[TextRewriteService] getToneCheckSuggestion — Claude unavailable, returning null. uid=${uid}`);
      return { suggestion: null, reason: null };
    }

    const parsed = parseClaudeJson<ClaudeTonePayload>(raw);

    if (!parsed) {
      logger.warn(`[TextRewriteService] getToneCheckSuggestion — unparseable Claude response. uid=${uid}`);
      return { suggestion: null, reason: null };
    }

    const suggestion =
      typeof parsed.suggestion === "string" && parsed.suggestion.trim().length > 0
        ? parsed.suggestion.trim()
        : null;

    const reason =
      typeof parsed.reason === "string" && parsed.reason.trim().length > 0
        ? parsed.reason.trim()
        : null;

    // If Claude returned a suggestion but no reason (or vice versa), normalise to both-or-neither.
    if (suggestion === null || reason === null) {
      return { suggestion: null, reason: null };
    }

    return { suggestion, reason };
  }
);

// ─── Report Rewrite Outcome ──────────────────────────────────────────────────

/**
 * reportRewriteOutcome
 *
 * Called by iOS when the user accepts or dismisses a rewrite suggestion.
 * Stores the outcome (accepted/dismissed) for product analytics.
 * Never stores original text or the specific suggestion content.
 *
 * Input: { accepted: boolean, harmCategoryId: string, contentType: string }
 * Output: { recorded: true }
 */
export const reportRewriteOutcome = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{ accepted: boolean; harmCategoryId: string; contentType: string }>) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    const { accepted, harmCategoryId, contentType } = request.data;

    if (typeof accepted !== "boolean") {
      throw new HttpsError("invalid-argument", "accepted must be a boolean.");
    }
    if (typeof harmCategoryId !== "string" || harmCategoryId.length === 0) {
      throw new HttpsError("invalid-argument", "harmCategoryId is required.");
    }
    if (typeof contentType !== "string" || contentType.length === 0) {
      throw new HttpsError("invalid-argument", "contentType is required.");
    }

    try {
      await db.collection("rewriteOutcomes").add({
        uid,
        accepted,
        harmCategoryId: harmCategoryId.slice(0, 50),
        contentType: contentType.slice(0, 50),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      logger.warn("[TextRewriteService] Failed to write outcome log.", err);
    }

    return { recorded: true };
  }
);
