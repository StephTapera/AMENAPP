/**
 * ailTransform.js — Accessibility Intelligence Layer unified transform callable.
 *
 * Source of truth for contracts: functions/ail/ail.contracts.ts.
 * Routes EXCLUSIVELY through callModel (functions/router/callModel.js) using the
 * 10 AIL task entries in functions/router/amenRouting.config.js. No parallel AI
 * stack; no provider names here.
 *
 * SECURITY (fail-closed gates):
 *   1. Firebase Auth required.
 *   2. App Check enforced.
 *   3. Per-user rate limit (generous — accessibility is free at every tier; crisis bypasses it).
 *   4. Secrets via defineSecret only.
 *
 * TRANSFORM SEMANTICS (fail-OPEN to original — iron rule 3):
 *   The router applies each route's fail policy. explain_scripture is fail_closed
 *   at the MODEL level (cite-or-refuse — NEVER fabricate scripture explanation);
 *   all other AIL tasks degrade. In BOTH the blocked and degraded cases this
 *   callable returns { failOpen: true } so the iOS client renders the ORIGINAL
 *   content with a quiet "unavailable" state. The callable therefore never throws
 *   on a transform failure — only on the security gates above. This is the exact
 *   inverse of checkContentSafety, which fails closed.
 *
 * NO tier checks anywhere (accessibility is free at every tier).
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret }       = require("firebase-functions/params");
const logger                 = require("firebase-functions/logger");
const crypto                 = require("crypto");
const admin                  = require("firebase-admin");
const { enforceRateLimit }   = require("../rateLimiter");
const { callModel }          = require("../router/callModel");

// Providers the AIL routes can touch: claude/claudeFast (Anthropic), gemini/geminiPro
// (Gemini key fetched at runtime by the router), pinecone (explain_scripture retrieval),
// nvidia (input/output guards). Gemini key intentionally not declared (see routerCallable).
const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const NVIDIA_API_KEY    = defineSecret("NVIDIA_API_KEY");
const PINECONE_API_KEY  = defineSecret("PINECONE_API_KEY");
const PINECONE_HOST     = defineSecret("PINECONE_HOST");

// ── AIL tasks this callable accepts (callModel-routable; speech tasks excluded) ──
const AIL_TASKS = new Set([
  "translate", "simplify", "explain_scripture", "tone_hint",
  "reply_care_check", "cooldown_rewrite", "describe_image",
  "summarize_audio", "reentry_summary", "sensitivity_classify",
]);

// Per-task system prompts. Iron rules are encoded directly in the prompts.
const SYSTEM_PROMPTS = {
  translate: [
    "You translate user-generated faith-community text into the requested language.",
    "Translate meaning faithfully and naturally; preserve tone. Do NOT add or remove content.",
    "If the text contains an idiom, slang, or a scripture-phrase, add a short culture note.",
    "Respond with JSON only: { text: string, sourceLang: string, cultureNotes: [{ phrase, note, kind }] }.",
    "kind is one of: idiom | slang | scripture_phrase | cultural. Never translate verse text itself if quoted — translate surrounding words only.",
  ].join("\n"),
  simplify: [
    "You rewrite NON-SCRIPTURE text at a simpler reading level while preserving meaning and tone.",
    "NEVER simplify, re-level, or paraphrase quoted Bible verse text — leave any quoted verse exactly as-is.",
    "Respond with JSON only: { text: string }.",
  ].join("\n"),
  explain_scripture: [
    "You explain a Bible passage in plain language. This is EXPLANATION, not Scripture.",
    "You may quote ONLY open-licensed translations: BSB, WEB, or KJV. Never quote ESV/NIV/NLT/NASB/CSB/NKJV.",
    "Never rewrite or paraphrase the canonical verse text. Cite specific verse references.",
    "If you cannot ground the explanation in cited open-licensed scripture, refuse rather than fabricate.",
    "Respond with JSON only: { text: string }  where text is the plain-language explanation.",
  ].join("\n"),
  tone_hint: [
    "You give a HEDGED, gentle tone hint for the user's OWN draft text, on demand.",
    "Phrase as 'This may read as…'. Never assert intent. Be brief and non-judgmental.",
    "Respond with JSON only: { text: string }.",
  ].join("\n"),
  reply_care_check: [
    "You are a pre-send 'reply with care' check. The user is about to send this. Advisory ONLY — never blocks.",
    "If the draft seems impulsive/harsh, offer one gentle, dismissible suggestion. Otherwise approve.",
    "Respond with JSON only: { text: string }  (empty text means 'looks caring, no nudge').",
  ].join("\n"),
  cooldown_rewrite: [
    "You suggest a calmer rewrite of a heated draft. Suggestion only — the user always decides; never blocks.",
    "Preserve the user's point; soften the delivery. Respond with JSON only: { text: string }.",
  ].join("\n"),
  describe_image: [
    "You write alt text describing an image's scene, actions, objects, and any text visible IN the image.",
    "NEVER name or identify people. NEVER estimate age/identity, especially of minors.",
    "Describe what is visible, not who. Respond with JSON only: { text: string }.",
  ].join("\n"),
  summarize_audio: [
    "You summarize a transcript of audio/video into: the main point, any action/ask, and the overall tone.",
    "Be concise and faithful. Respond with JSON only: { text: string }.",
  ].join("\n"),
  reentry_summary: [
    "You write a QUALITATIVE re-entry summary of what changed while the user was away.",
    "NEVER use numeric counts ('12 new comments'). Describe qualitatively ('Sarah answered your question').",
    "Respond with JSON only: { text: string }.",
  ].join("\n"),
  sensitivity_classify: [
    "You classify whether text touches user-flagged sensitive topics for an OPTIONAL blur.",
    "Topics: grief, conflict, politics, trauma, graphic. Never blur crisis-help content.",
    "Respond with JSON only: { sensitive: boolean, topics: string[] }.",
  ].join("\n"),
};

const db = () => admin.firestore();
const CACHE_TTL_HOURS_PUBLIC = 720;
const MAX_INPUT_CHARS = 8000;

/** Content-hash cache doc id so an edit to the source invalidates the entry. */
function cacheDocId(input, task, lang, level) {
  const contentId = crypto.createHash("sha256").update(input).digest("hex").slice(0, 32);
  return `${contentId}_${task}_${lang || "auto"}_${level || "original"}`;
}

/** Parse the model's JSON output defensively; returns {} on failure. */
function parseModelJson(output) {
  if (typeof output !== "string") return {};
  try { return JSON.parse(output); } catch { /* fall through */ }
  // Tolerate code fences / surrounding prose.
  const match = output.match(/\{[\s\S]*\}/);
  if (match) { try { return JSON.parse(match[0]); } catch { /* ignore */ } }
  return {};
}

const failOpen = (crisisBypass = false) => ({ failOpen: true, crisisBypass });

exports.ailTransform = onCall(
  {
    region: "us-east1",  // us-central1 quota exhausted as of 2026-06-13; see docs/FUNCTION_INVENTORY.md Interim Region Table
    enforceAppCheck: true,           // App Check required (security fail-closed)
    timeoutSeconds: 30,
    memory: "256MiB",
    secrets: [ANTHROPIC_API_KEY, NVIDIA_API_KEY, PINECONE_API_KEY, PINECONE_HOST],
  },
  async (request) => {
    // ── 1. Auth (fail closed) ─────────────────────────────────────────────────
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = request.auth.uid;

    // ── 2. Validate input ─────────────────────────────────────────────────────
    const {
      task,
      input,
      originalRef,
      targetLang,
      readingLevel,
      isDirectMessage = false,
      crisisContext = false,
    } = request.data ?? {};

    if (!task || !AIL_TASKS.has(task)) {
      throw new HttpsError("invalid-argument", `task must be one of: ${[...AIL_TASKS].join(", ")}.`);
    }
    if (!input || typeof input !== "string" || input.trim().length < 1) {
      throw new HttpsError("invalid-argument", "input is required and must be a non-empty string.");
    }
    if (input.length > MAX_INPUT_CHARS) {
      throw new HttpsError("invalid-argument", `input exceeds the ${MAX_INPUT_CHARS} character limit.`);
    }
    const refOut = typeof originalRef === "string" ? originalRef : "";

    // ── 3. Rate limit — generous; crisis bypasses entirely (iron rule 3) ───────
    // On exceed we throw resource-exhausted; the iOS client treats ANY error as
    // fail-open (renders the original). Accessibility is never tier-gated.
    if (!crisisContext) {
      try {
        await enforceRateLimit(uid, "ailTransform", 120, 3600); // 120/hour/user
      } catch (err) {
        if (err instanceof HttpsError) throw err;
        logger.error("ailTransform: rate-limiter error (non-fatal)", { uid, error: err.message });
      }
    }

    const lang = typeof targetLang === "string" ? targetLang : "";
    const level = typeof readingLevel === "string" ? readingLevel : "";

    // ── 4. Cache read (public content only; DM & crisis never cached) ──────────
    const cacheable = !isDirectMessage && !crisisContext;
    const docId = cacheDocId(input, task, lang, level);
    if (cacheable) {
      try {
        const snap = await db().collection("transformCache").doc(docId).get();
        if (snap.exists) {
          const data = snap.data();
          const notExpired = !data.expiresAt || data.expiresAt.toMillis() > Date.now();
          if (notExpired && data.result) {
            logger.info("ailTransform: cache hit", { uid, task });
            return data.result;
          }
        }
      } catch (err) {
        logger.warn("ailTransform: cache read failed (continuing)", { task, error: err.message });
      }
    }

    // ── 5. Route through callModel ─────────────────────────────────────────────
    const contextParts = [];
    if (lang) contextParts.push(`Target language: ${lang}`);
    if (level) contextParts.push(`Target reading level: ${level}`);
    if (crisisContext) contextParts.push("CRISIS CONTEXT: prioritize clarity and care.");

    let result;
    try {
      result = await callModel({
        task,
        input,
        systemPrompt: SYSTEM_PROMPTS[task],
        context: contextParts.join("\n") || undefined,
        userId: uid,
        // explain_scripture uses Pinecone retrieval; namespace mirrors berean grounding.
        namespace: task === "explain_scripture" ? "berean" : undefined,
      });
    } catch (err) {
      logger.error("ailTransform: callModel threw — failing open", { uid, task, error: err.message });
      return failOpen(crisisContext);
    }

    // blocked (incl. explain_scripture cite-or-refuse) OR degraded ⇒ fail OPEN to original.
    if (result.blocked || result.degraded || result.output == null) {
      logger.info("ailTransform: fail-open to original", {
        uid, task, blocked: !!result.blocked, degraded: !!result.degraded, reason: result.reason,
      });
      return failOpen(crisisContext);
    }

    // ── 6. Shape the A11yTransformResult ───────────────────────────────────────
    const parsed = parseModelJson(result.output);
    const response = {
      task,
      output: typeof parsed.text === "string" ? parsed.text : String(result.output),
      provenance: "ai_generated",
      confidence: "medium",
      originalRef: refOut,
      failOpen: false,
      crisisBypass: !!crisisContext,
    };
    if (lang) response.targetLang = lang;
    if (parsed.sourceLang) response.sourceLang = parsed.sourceLang;
    if (Array.isArray(parsed.cultureNotes)) {
      response.cultureNotes = parsed.cultureNotes
        .filter((n) => n && typeof n.phrase === "string" && typeof n.note === "string")
        .map((n) => ({ phrase: n.phrase, note: n.note, kind: n.kind || "cultural" }));
    }
    // sensitivity_classify carries its structured verdict alongside text.
    if (task === "sensitivity_classify") {
      response.sensitive = !!parsed.sensitive;
      response.topics = Array.isArray(parsed.topics) ? parsed.topics : [];
    }

    // ── 7. Cache write (public only; server-write; TTL) ────────────────────────
    if (cacheable) {
      try {
        const expiresAt = admin.firestore.Timestamp.fromMillis(
          Date.now() + CACHE_TTL_HOURS_PUBLIC * 3600 * 1000
        );
        await db().collection("transformCache").doc(docId).set({
          result: response,
          task,
          lang: lang || null,
          level: level || null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt,
        });
      } catch (err) {
        logger.warn("ailTransform: cache write failed (non-fatal)", { task, error: err.message });
      }
    }

    return response;
  },
);
