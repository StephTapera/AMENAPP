/**
 * amenRouting.config.js — Single source of truth for callModel({ task, ... })
 *
 * Fail policies:
 *   "fail_closed"  — on chain exhaustion, return a safe error/queue.
 *                    NEVER downgrade safety or fabricate. Used for pastoral,
 *                    scripture-grounded, and all moderation tasks.
 *   "failover"     — try providers in order until one succeeds.
 *   "degrade"      — return the documented degradeResult on chain exhaustion.
 *
 * Every route, regardless of task:
 *   auth + App Check + Cloudflare protection + rate limit enforced by the
 *   calling Firebase Function.  callModel() adds: NVIDIA input/output guards,
 *   Pinecone retrieval, citation validation, structured logging, and cost guards.
 *
 * Provider model IDs are resolved here; feature code NEVER hardcodes a provider.
 */

"use strict";

const PROVIDERS = {
  claude:     { id: "anthropic", model: "claude-opus-4-7",          role: "safe reasoning" },
  claudeFast: { id: "anthropic", model: "claude-sonnet-4-6",        role: "safe reasoning (cheaper)" },
  openai:     { id: "openai",    model: "gpt-4o",                   role: "advanced reasoning" },
  openaiAdv:  { id: "openai",    model: "o4-mini",                  role: "advanced reasoning (heavy)" },
  gemini:     { id: "google",    model: "gemini-2.0-flash",         role: "multimodal / fast" },
  geminiPro:  { id: "google",    model: "gemini-2.0-flash-thinking", role: "multimodal / heavy" },
  nvidia:     { id: "nvidia",    model: "nvidia/llama-3.1-nemoguard-8b-content-safety", role: "guardrails + moderation" },
  pinecone:   { id: "pinecone",  model: "vector-index",             role: "memory / retrieval" },
  algolia:    { id: "algolia",   model: "search-index",             role: "keyword search" },
};

// ── ROUTING TABLE ────────────────────────────────────────────────────────────
//
// inputGuard:      run NVIDIA safety check on user input before model call
// outputGuard:     run NVIDIA safety check on model output before returning
// retrieval:       "pinecone" — fetch context chunks before model call
// requireCitations: response must contain at least one verifiable scripture ref
// degradeResult:   value returned when fail === "degrade" and chain is exhausted
//
// NVIDIA guard tasks (guard_input / guard_output) deliberately set
// inputGuard: false to avoid infinite recursion.

const ROUTING = {

  // ── SAFETY GATE ────────────────────────────────────────────────────────────
  // fail_closed: if the guard cannot run, the content does NOT pass.
  guard_input: {
    primary: "nvidia", chain: ["nvidia"],
    fail: "fail_closed", inputGuard: false, outputGuard: false,
  },
  guard_output: {
    primary: "nvidia", chain: ["nvidia"],
    fail: "fail_closed", inputGuard: false, outputGuard: false,
  },
  moderate_content: {
    primary: "nvidia", chain: ["nvidia"],
    fail: "fail_closed",
    note: "block / queue on failure — never auto-approve",
  },
  pii_detect: {
    primary: "nvidia", chain: ["nvidia"],
    fail: "fail_closed",
  },
  deepfake_detect: {
    primary: "nvidia", chain: ["nvidia"],
    fail: "fail_closed",
  },

  // ── PASTORAL / SCRIPTURE ───────────────────────────────────────────────────
  // Claude only; fail_closed — retry Claude with backoff, then return graceful
  // "try again" — never route to another provider.
  berean_answer: {
    primary: "claude", chain: ["claude"],
    fail: "fail_closed", inputGuard: true, outputGuard: true,
    retrieval: "pinecone", requireCitations: true,
  },
  berean_explain: {
    primary: "claude", chain: ["claude"],
    fail: "fail_closed", inputGuard: true, outputGuard: true,
    retrieval: "pinecone", requireCitations: true,
  },
  verse_context: {
    primary: "claude", chain: ["claude"],
    fail: "fail_closed", outputGuard: true,
    retrieval: "pinecone", requireCitations: true,
  },
  prayer_generate: {
    primary: "claude", chain: ["claude"],
    fail: "fail_closed", outputGuard: true,
  },
  prayer_rewrite: {
    primary: "claude", chain: ["claude"],
    fail: "fail_closed", outputGuard: true,
  },
  comment_coach: {
    primary: "claude", chain: ["claude"],
    fail: "fail_closed", outputGuard: true,
    note: "harsh / impulsive rewrite suggestions",
  },
  devotional_generate: {
    primary: "claudeFast", chain: ["claudeFast", "claude"],
    fail: "fail_closed", outputGuard: true,
  },
  pastoral_reply: {
    primary: "claude", chain: ["claude"],
    fail: "fail_closed", outputGuard: true,
  },

  // ── ADVANCED REASONING ─────────────────────────────────────────────────────
  // failover OpenAI ↔ Claude; both capable & safe.
  study_plan: {
    primary: "openai", chain: ["openai", "claude"],
    fail: "failover", outputGuard: true, retrieval: "pinecone",
  },
  deep_analysis: {
    primary: "openai", chain: ["openai", "claude"],
    fail: "failover", outputGuard: true, retrieval: "pinecone",
  },
  cross_reference: {
    primary: "openai", chain: ["openai", "claude"],
    fail: "failover", outputGuard: true,
    retrieval: "pinecone", requireCitations: true,
  },
  long_synthesis: {
    primary: "openai", chain: ["openai", "claude"],
    fail: "failover", outputGuard: true,
  },

  // ── MULTIMODAL / FAST ──────────────────────────────────────────────────────
  // Gemini primary; degrade to documented fallback where full failure is safe.
  vision_understand: {
    primary: "gemini", chain: ["gemini", "geminiPro"],
    fail: "failover", inputGuard: true, outputGuard: true,
  },
  video_summary: {
    primary: "geminiPro", chain: ["geminiPro", "gemini"],
    fail: "failover", outputGuard: true,
  },
  screenshot_understand: {
    primary: "gemini", chain: ["gemini"],
    fail: "failover", inputGuard: true, outputGuard: true,
  },
  media_alt_text: {
    primary: "gemini", chain: ["gemini"],
    fail: "degrade", degradeResult: { altText: "", flagged: true },
    note: "degrade to empty alt + flag; never block on missing alt text",
  },
  quick_summary: {
    primary: "gemini", chain: ["gemini", "openai"],
    fail: "failover", outputGuard: true,
  },
  scripture_detect: {
    primary: "gemini", chain: ["gemini"],
    fail: "degrade", degradeResult: { references: [] },
    note: "regex pre-pass always runs; degrade to regex-only on AI failure",
  },
  asr_transcribe: {
    primary: "gemini", chain: ["gemini"],
    fail: "fail_closed",
    note: "no fabricated transcript — fail_closed",
  },
  tts_generate: {
    primary: "gemini", chain: ["gemini"],
    fail: "degrade", degradeResult: null,
    note: "degrade to text-only display",
  },
  daily_brief: {
    primary: "gemini", chain: ["gemini", "openai"],
    fail: "failover", outputGuard: true,
  },

  // ── RETRIEVAL & SEARCH ─────────────────────────────────────────────────────
  vector_retrieve: {
    primary: "pinecone", chain: ["pinecone"],
    fail: "fail_closed",
    note: "dependent grounded tasks fail_closed if this fails — never fabricate",
  },
  ai_memory_read: {
    primary: "pinecone", chain: ["pinecone"],
    fail: "degrade", degradeResult: [],
    note: "degrade to no-memory prompt; NEVER cross-user",
  },
  ai_memory_write: {
    primary: "pinecone", chain: ["pinecone"],
    fail: "degrade",
    note: "queue retry via Cloud Tasks on failure",
  },
  universal_search: {
    primary: "algolia", chain: ["algolia"],
    fail: "degrade", degradeResult: { hits: [] },
    note: "degrade to Firestore query",
  },
};

module.exports = { PROVIDERS, ROUTING };
