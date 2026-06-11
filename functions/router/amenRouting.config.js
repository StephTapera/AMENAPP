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

  // ── CONTEXT SYSTEM — Universal Migration extractor (Wave 3) ─────────────────
  // extractContextFacets CF routes here. Input is C59-sanitized, inert-wrapped
  // import text (DATA, never instructions); output is structured FacetCandidate[]
  // (free-text length-capped). fail_closed: never fabricate a facet, never salvage
  // from prose. inputGuard runs NeMo on the imported body before extraction.
  context_extract: {
    primary: "claude", chain: ["claude", "openai"],
    fail: "fail_closed", inputGuard: true,
    note: "structured facet extraction; fail_closed — no fabricated facets",
  },
  // Wave 4: "Why this community fits you" explanation. fail_closed → deterministic
  // template fallback in the CF (never fabricates a fit reason).
  context_match_explain: {
    primary: "claude", chain: ["claude", "openai"],
    fail: "fail_closed", outputGuard: true,
    note: "community match explanation; fail_closed — CF falls back to template",
  },
  // Wave 4: contextual introduction draft from public/groups facets only. Never auto-posts.
  context_intro: {
    primary: "claude", chain: ["claude", "openai"],
    fail: "fail_closed", outputGuard: true,
    note: "introduction draft; fail_closed — empty draft, never fabricated",
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

  // ── CATALOG Q&A (RAG) ──────────────────────────────────────────────────────
  // "Ask This Creator" — grounded answers from creator's published catalog only.
  // fail_closed: if Pinecone retrieval fails or returns 0 qualifying results,
  // refuse — never fabricate a quote or belief.
  // Namespace per creator: `creator-catalog-{creatorId}` (appended by caller).
  catalog_qa: {
    primary: "claude", chain: ["claude", "openai"],
    fail: "fail_closed", inputGuard: true, outputGuard: true,
    retrieval: "pinecone",
    safetyLevel: "strict",
    systemPromptKey: "catalog_qa",
    requiredContext: ["creatorId", "citations"],
    namespace: "creator-catalog",   // caller appends -{creatorId}
    note: "fail_closed — refuse with no-source message if 0 citations; NEVER fabricate",
  },

  // ── BEREAN v1 — INTELLIGENCE TASKS ────────────────────────────────────────
  // Added Phase 1 contract freeze (2026-06-07).

  // Crisis: detection only → human handoff scaffold. AI answer SUPPRESSED.
  // HUMAN GATE: T&S owns the response queue. Never route AI output to user.
  crisis_handoff: {
    primary: "nvidia", chain: ["nvidia"],
    fail: "fail_closed", inputGuard: false, outputGuard: false,
    humanGate: true,
    note: "detect crisis signal only — suppresses AI answer, surfaces real human resources",
  },

  // Multi-perspective theology: labeled traditions, cite each. Claude only.
  berean_perspective: {
    primary: "claude", chain: ["claude"],
    fail: "fail_closed", inputGuard: true, outputGuard: true,
    retrieval: "pinecone", requireCitations: true,
    note: "return labeled traditions/views on contested questions — not a single verdict",
  },

  // Memory summarization: auto-summarize prayer requests, reading plan, church, last reflection.
  // Pinecone write on success. Fail_closed so bad summaries are not persisted.
  berean_memory_summarize: {
    primary: "claude", chain: ["claude"],
    fail: "fail_closed", outputGuard: true,
    note: "summarize user activity for memory injection — never cross-user",
  },

  // Proactive formation: surfaced only when context warrants — never engagement-bait.
  berean_proactive: {
    primary: "claudeFast", chain: ["claudeFast", "claude"],
    fail: "degrade", degradeResult: null,
    outputGuard: true,
    note: "degrade to no-suggestion rather than low-quality nudge",
  },

  // Bible provider lookup — open-licensed translations (BSB/WEB/KJV) via BibleProvider adapter.
  berean_bible_lookup: {
    primary: "pinecone", chain: ["pinecone"],
    fail: "fail_closed",
    note: "BSB/WEB/KJV only; YouVersion blocked until written confirmation",
  },

  // Voice TTS — Berean-specific; keys server-side only.
  berean_voice_tts: {
    primary: "gemini", chain: ["gemini"],
    fail: "degrade", degradeResult: null,
    note: "degrade to text-only; no engagement re-prompt on session end",
  },

  // Voice STT — Berean-specific; no fabricated transcript on failure.
  berean_voice_stt: {
    primary: "gemini", chain: ["gemini"],
    fail: "fail_closed",
    note: "fail_closed — no fabricated transcript",
  },

  // ── SELAH: BEREAN DISCERNMENT ──────────────────────────────────────────────
  // Wired by final wiring agent 2026-06-07. Source of truth: selah.contracts.ts
  // §SECTION 4 — DISCERNMENT_ROUTING + SELAH_CORPUS_RETRIEVAL_ROUTING.
  //
  // discernment: Claude-only, no fallover to any other provider. NeMo guards
  // both input and output. fail_closed: retry with backoff [500ms, 1500ms, 4000ms];
  // graceful refused response if all retries fail — never fabricate.
  //
  // selah_corpus_retrieve: Pinecone only, per-user private namespace
  // (`selah-notes-{uid}`). No cross-user retrieval. fail gracefully with empty.
  discernment: {
    primary: "claude", chain: ["claude"],           // Claude-only, NO fallover
    fail: "fail_closed", inputGuard: true, outputGuard: true,
    requireCitations: true,
    safetyLevel: "high",
    retryConfig: { maxAttempts: 3, backoffMs: [500, 1500, 4000] },
    note: "Pastoral/discernment — Claude-only, no fallover to any other provider.",
  },
  selah_corpus_retrieve: {
    primary: "pinecone", chain: ["pinecone"],
    fail: "degrade", degradeResult: [],
    note: "User private namespace only (`selah-notes-{uid}`) — no cross-user retrieval ever.",
  },

  // ── SABBATH MODE — BEREAN GUIDE ────────────────────────────────────────────
  // Claude-only; fail_closed — no fallover to any other model, ever.
  // All tasks route exclusively through bereanChatProxy.
  // Guide mode enforced: system prompt leads, never answers.
  // NeMo moderation required for communal-visible output (family_questions, devotional).
  // Private tasks (sabbath_guide, sermon_prep, reflection_prompt) skip moderation.
  // Phase 2D — Berean Sabbath Guide (2026-06-07)
  sabbath_guide: {
    primary: "claude", chain: ["claude"],
    fail: "fail_closed", outputGuard: true,
    failClosed: true, fallover: false, guideMode: true,
    note: "private — prayer/heart-prep guide; no NeMo; fail closed",
  },
  family_questions: {
    primary: "claude", chain: ["claude"],
    fail: "fail_closed", outputGuard: true,
    failClosed: true, fallover: false, requiresNemo: true,
    note: "communal-visible — must pass NeMo before return; fail closed",
  },
  sermon_prep: {
    primary: "claude", chain: ["claude"],
    fail: "fail_closed", outputGuard: true,
    failClosed: true, fallover: false,
    note: "private — post-service reflection; no NeMo; fail closed",
  },
  devotional: {
    primary: "claude", chain: ["claude"],
    fail: "fail_closed", outputGuard: true,
    failClosed: true, fallover: false, requiresNemo: true,
    note: "communal-visible — must pass NeMo before return; fail closed",
  },
  reflection_prompt: {
    primary: "claude", chain: ["claude"],
    fail: "fail_closed", outputGuard: false,
    failClosed: true, fallover: false, private: true,
    note: "strictly private — never moderated, never aggregated, never shown to others",
  },

  // ── ACCESSIBILITY INTELLIGENCE LAYER (AIL) ─────────────────────────────────
  // Phase 1 contract freeze (2026-06-09). Source of truth: functions/ail/ail.contracts.ts
  // §SECTION 7 — AIL_ROUTING_ADDITIONS.
  //
  // Failure model is DISTINCT from moderation: AIL transforms FAIL OPEN to the
  // ORIGINAL content (fail:"degrade", degradeResult:{ failOpen:true }) — the caller
  // renders the original with a quiet "unavailable" state. The ONE exception is
  // explain_scripture (Claude-only, fail_closed, cite-or-refuse — never fabricate).
  // Accessibility is free at every tier; these routes carry NO tier gating.
  // Claude-only tasks use chain:["claude"] with NO fallover (iron rules 2/8).

  translate: {
    primary: "claudeFast", chain: ["claudeFast", "claude"],
    fail: "degrade", degradeResult: { failOpen: true },
    outputGuard: true,
    note: "AIL C1 — general text only; fail OPEN to original; scripture NEVER routed here",
  },
  simplify: {
    primary: "claudeFast", chain: ["claudeFast", "claude"],
    fail: "degrade", degradeResult: { failOpen: true },
    outputGuard: true,
    note: "AIL C2 — non-scripture text only; fail OPEN to original",
  },
  explain_scripture: {
    primary: "claude", chain: ["claude"],            // Claude-only, NO fallover
    fail: "fail_closed", inputGuard: true, outputGuard: true,
    retrieval: "pinecone", requireCitations: true,
    safetyLevel: "high",
    note: "AIL — explanation ALONGSIDE canonical verse; BSB/WEB/KJV only; cite-or-refuse",
  },
  tone_hint: {
    primary: "claude", chain: ["claude"],
    fail: "degrade", degradeResult: { failOpen: true },
    outputGuard: true,
    note: "AIL C3 — opt-in, on-demand, hedged; suppressed on Guardian-flagged content; degrade to no-hint",
  },
  reply_care_check: {
    primary: "claude", chain: ["claude"],
    fail: "degrade", degradeResult: { failOpen: true },
    outputGuard: true,
    note: "AIL C10 — suggests only; ZERO shared path with NeMo; never blocks a send",
  },
  cooldown_rewrite: {
    primary: "claude", chain: ["claude"],
    fail: "degrade", degradeResult: { failOpen: true },
    outputGuard: true,
    note: "AIL C11 — suggested rewrite; always dismissible; never blocks",
  },
  describe_image: {
    primary: "gemini", chain: ["gemini", "geminiPro"],
    fail: "degrade", degradeResult: { description: "", flagged: true, failOpen: true },
    inputGuard: true, outputGuard: true,
    note: "AIL C5 — scene/action/object/text-in-image ONLY; never names/identifies people or minors",
  },
  summarize_audio: {
    primary: "geminiPro", chain: ["geminiPro", "gemini"],
    fail: "degrade", degradeResult: { failOpen: true },
    outputGuard: true,
    note: "AIL C6 — main point / action / tone; fail OPEN",
  },
  reentry_summary: {
    primary: "claudeFast", chain: ["claudeFast", "claude"],
    fail: "degrade", degradeResult: { failOpen: true },
    outputGuard: true,
    note: "AIL C14 — qualitative ONLY, never numeric counts; degrade to no-summary",
  },
  sensitivity_classify: {
    primary: "gemini", chain: ["gemini"],
    fail: "degrade", degradeResult: { topics: [], sensitive: false, failOpen: true },
    note: "AIL C12 — user-policy blur classifier; degrade ⇒ do NOT blur; crisis-help never blurred",
  },
};

// ── CONNECTED INTELLIGENCE v1 config ──────────────────────────────────────────
// Server-side mirror of src/features/connectedIntelligence.config.ts. These values
// are editable without an app update. SAFETY INVARIANT: safety/crisis tasks BYPASS
// every cap/limit below (consistent with BereanUsageDoc.safetyExempt === true).
//
// scheduledActions.enabled stays false and aegisReviewId stays null until an Aegis
// capability review lands. The onSchedule runner (scheduledFunctions.js) also reads
// SCHEDULED_ACTIONS_ENABLED / SCHEDULED_ACTIONS_AEGIS_REVIEW_ID from env and no-ops
// while the gate is shut — this config block is the client-mirrored source of truth.
const CONNECTED_INTELLIGENCE = {
  connectors: {
    calendar: { enabled: true },   // Google Calendar v1 (Apple EventKit at SwiftUI parity)
    music:    { enabled: true },   // Spotify v1 (Apple Music later, behind MusicProvider)
  },
  brief: {
    maxItems: 9,
    generateAfterLocalHour: 5,
    pushEnabled: false,            // pull-based home card ONLY — never a push notification
  },
  notebooks: {
    maxSourcesFree: 10,
    maxSourcesPlus: 100,
    maxNotebooksFree: 3,
  },
  scheduledActions: {
    enabled: false,                // hard-off until Aegis review (DO NOT flip here)
    aegisReviewId: null,
    dryRunCount: 3,
    maxActiveFree: 2,
    maxActivePlus: 10,
  },
  actionSheet: {
    // Deferred action-sheet outcomes — all false in v1 (UI-absent, not disabled).
    deferred: {
      turn_into_podcast: false,
      turn_into_video_script: false,
      create_infographic: false,
      create_presentation: false,
      create_flyer: false,
    },
  },
  limits: {
    // NOTE: safety + crisis domains are EXEMPT from these caps (never metered).
    dailyPromptsFree: 25,
    dailyPromptsPlus: 200,
    connectorRequestsPerDay: 100,
  },
};

module.exports = { PROVIDERS, ROUTING, CONNECTED_INTELLIGENCE };
