/**
 * ail.contracts.ts — FROZEN CONTRACT FILE (Accessibility Intelligence Layer)
 *
 * Authored by Phase 1 Contract Freeze, 2026-06-09. Branch: feature/ail.
 * DO NOT EDIT without re-broadcasting to all consuming agents (A2–A8).
 * Additive-only after broadcast.
 *
 * This file owns:
 * - A11yTask / ReadingLevel / A11yProvenance / SensitivityTopic enums
 * - A11yProfile, CaptionStyle, CultureNote, CaptionTrack, ImageDescription,
 *   A11yTransformResult interfaces
 * - Firestore path builders (a11yProfile; captions as media subcollection)
 * - Routing config additions (source of truth; applied to amenRouting.config.js)
 * - SpeechProvider adapter interface
 * - Feature-flag names (reconciled with the shipped "System 15" flag block)
 * - Validation/enforcement helpers
 *
 * ── ARCHITECTURE NOTE (resolved Phase 0) ──────────────────────────────────────
 * The original spec referenced three "engines" (Intent/Visual/Knowledge) on a
 * shared "ContextGraph". NEITHER EXISTS in this repo. The real architecture is a
 * single config-driven router: callModel({ task, input, systemPrompt, context,
 * userId, safetyLevel, featureFlags, namespace }) in functions/router/callModel.js,
 * dispatched by ROUTING[task] in functions/router/amenRouting.config.js.
 * Therefore every AIL capability is a callModel TASK (not an engine). describe_image
 * and summarize_audio are bound as new task entries, not engine references.
 *
 * ── THREE DISTINCT FAILURE BEHAVIORS (do not conflate) ────────────────────────
 *   moderation  → FAIL_CLOSED  (NeMo; content does not pass on guard failure)
 *   usage caps  → DEGRADE      (graceful reduction)
 *   AIL transforms → DEGRADE_TO_ORIGINAL  (show original + quiet "unavailable"; safe behavior, NOT a security fail-open)
 * In amenRouting.config.js terms, AIL fail-open is expressed as fail:"degrade"
 * with a degradeResult of { failOpen: true } — the caller then renders the
 * ORIGINAL content. The single exception is explain_scripture (cite-or-refuse,
 * fail_closed — never fabricate, never fallover). Crisis context bypasses all
 * AIL caps and limits.
 *
 * ── HARD LEGAL/THEOLOGICAL CONSTRAINT ─────────────────────────────────────────
 * Scripture text is canonical and untouchable. SIMPLIFY and TRANSLATE NEVER
 * rewrite/re-level/paraphrase verse text. Plain-language EXPLANATION renders
 * alongside the canonical verse, labeled "Explanation — not Scripture", routes to
 * Claude ONLY, cite-or-refuse, no fallover, and quotes BSB/WEB/KJV only
 * (reuse assertOpenTranslation from ../selah/selah.contracts.ts at the citation
 * boundary).
 */

"use strict";

// =============================================================================
// SECTION 1 — TASK & LEVEL ENUMS
// =============================================================================

/**
 * The AIL capability surface, expressed as callModel tasks.
 * Each maps to a ROUTING[...] entry in amenRouting.config.js (see SECTION 4),
 * except CAPTION_LIVE/CAPTION_RECORDED which are SpeechProvider-adapter bound.
 */
export enum A11yTask {
  TRANSLATE = 'translate',                 // C1 — includes cultureNotes[]
  SIMPLIFY = 'simplify',                   // C2 — non-scripture text only
  EXPLAIN_SCRIPTURE = 'explain_scripture', // C2 (scripture) — Claude-only, cite-or-refuse
  TONE_HINT = 'tone_hint',                 // C3 — opt-in, on-demand, hedged
  CAPTION_LIVE = 'caption_live',           // C4 — SpeechProvider on-device
  CAPTION_RECORDED = 'caption_recorded',   // C4 — SpeechProvider server ASR
  DESCRIBE_IMAGE = 'describe_image',       // C5 — alt-text; no identity/facial claims
  SUMMARIZE_AUDIO = 'summarize_audio',     // C6 — main point / action / tone
  REENTRY_SUMMARY = 'reentry_summary',     // C14 — qualitative, NO counts
  REPLY_CARE_CHECK = 'reply_care_check',   // C10 — pre-send nudge, dismissible
  COOLDOWN_REWRITE = 'cooldown_rewrite',   // C11 — suggested rewrite, never blocks
  SENSITIVITY_CLASSIFY = 'sensitivity_classify', // C12 — user-policy blur classifier
}

/** Tasks that MUST route to Claude only with no fallover to any other provider. */
export const CLAUDE_ONLY_TASKS: ReadonlyArray<A11yTask> = [
  A11yTask.EXPLAIN_SCRIPTURE,
  A11yTask.TONE_HINT,
  A11yTask.REPLY_CARE_CHECK,
  A11yTask.COOLDOWN_REWRITE,
];

/** The single AIL task that fails CLOSED (cite-or-refuse). All others fail OPEN. */
export const FAIL_CLOSED_TASKS: ReadonlyArray<A11yTask> = [A11yTask.EXPLAIN_SCRIPTURE];

/** Tasks handled by the SpeechProvider adapter, NOT by callModel. */
export const SPEECH_ADAPTER_TASKS: ReadonlyArray<A11yTask> = [
  A11yTask.CAPTION_LIVE,
  A11yTask.CAPTION_RECORDED,
];

/** C2 reading levels. ORIGINAL is always the fail-open fallback. */
export enum ReadingLevel {
  ORIGINAL = 'original',
  SIMPLE = 'simple',
  VERY_SIMPLE = 'very_simple',
  SUMMARY = 'summary',
}

/** C12 user-selectable sensitivity topics for the emotional-safety filter. */
export enum SensitivityTopic {
  GRIEF = 'grief',
  CONFLICT = 'conflict',
  POLITICS = 'politics',
  TRAUMA = 'trauma',
  GRAPHIC = 'graphic',
}

// =============================================================================
// SECTION 2 — PROVENANCE (net-new, same family as ONEProvenanceClass)
// =============================================================================

/**
 * Transform-authorship provenance for AIL output. This is NET-NEW: the existing
 * provenance systems (Swift ONEProvenanceClass {captured, edited, aiAssisted,
 * synthetic, unknown}; backend provenanceFunctions.js sourceType) describe MEDIA
 * CAPTURE, not text-transform authorship. Per the Lead decision, provenance
 * "remains one family" — A11yProvenance is the transform-authorship facet of the
 * same family, and maps onto ONEProvenanceClass via toONEProvenanceClass().
 *
 * Every AIL transform output carries one of these AND a resolvable originalRef so
 * the UI can always offer one-tap "View original". Creator editing of generated
 * alt text flips AI_GENERATED → AI_HUMAN_EDITED.
 */
export enum A11yProvenance {
  AI_GENERATED = 'ai_generated',     // model-authored, unedited
  AI_HUMAN_EDITED = 'ai_human_edited', // model draft, human-corrected (e.g. creator alt text)
  HUMAN = 'human',                   // fully human-authored (original content)
}

/** ONEProvenanceClass mirror (Swift truth: captured/edited/aiAssisted/synthetic/unknown). */
export type ONEProvenanceClass =
  | 'captured' | 'edited' | 'aiAssisted' | 'synthetic' | 'unknown';

/** Map AIL transform provenance onto the canonical media-provenance family. */
export function toONEProvenanceClass(p: A11yProvenance): ONEProvenanceClass {
  switch (p) {
    case A11yProvenance.AI_GENERATED:    return 'synthetic';   // model-authored text
    case A11yProvenance.AI_HUMAN_EDITED: return 'aiAssisted';  // model + human edit
    case A11yProvenance.HUMAN:           return 'edited';      // human authorship
    default:                             return 'unknown';
  }
}

// =============================================================================
// SECTION 3 — VALUE TYPES
// =============================================================================

/** C1 idiom/slang/scripture-phrase tooltip attached to a translation. */
export interface CultureNote {
  phrase: string;          // the source phrase the note explains
  note: string;            // plain-language explanation
  kind: 'idiom' | 'slang' | 'scripture_phrase' | 'cultural';
}

/** C4 caption rendering preferences (user-controlled, lives in A11yProfile). */
export interface CaptionStyle {
  size: 'small' | 'medium' | 'large' | 'xl';
  background: 'none' | 'dim' | 'solid';      // 'solid' is the Reduce-Transparency fallback
  highContrast: boolean;
  speed: 'slow' | 'normal' | 'fast';         // reveal pacing for recorded playback
  placement: 'bottom' | 'top';
}

/** C4 recorded-caption artifact. Stored as a subcollection under the parent media doc. */
export interface CaptionTrack {
  mediaId: string;
  lang: string;                  // BCP-47
  cues: CaptionCue[];
  provenance: A11yProvenance;    // AI_GENERATED until a creator edits → AI_HUMAN_EDITED
  moderationStatus: 'pending' | 'approved' | 'flagged';
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;      // soft-delete only
}

export interface CaptionCue {
  startMs: number;
  endMs: number;
  text: string;
}

/** C5 image description / alt text. Never names or identifies people (iron rule 6). */
export interface ImageDescription {
  mediaId: string;
  text: string;                  // scene/action/object/text-in-image only
  provenance: A11yProvenance;    // AI_GENERATED → AI_HUMAN_EDITED when creator edits
  confidence: 'high' | 'medium' | 'low';
  flagged: boolean;              // true on degrade (empty/low-quality) — fail open
}

// =============================================================================
// SECTION 4 — USER PROFILE (users/{uid}/settings/a11yProfile)
// =============================================================================

/**
 * Per-user accessibility profile. Owner read/write ONLY.
 *
 * FORBIDDEN FIELDS — must be rejected by Firestore rules schema validation and by
 * assertNoForbiddenProfileFields(): no motor metrics, no miss rates, no tremor /
 * dwell / input-timing data, no inferred conditions or diagnoses. C9 touch-target
 * calibration runs ON-DEVICE ONLY; only the resulting target-size PREFERENCE
 * (largerTouchTargets) is ever persisted. Raw motor input never leaves the device.
 */
export interface A11yProfile {
  readingLevel: ReadingLevel;            // default ORIGINAL
  autoTranslate: boolean;                // default false
  toneHintsEnabled: boolean;             // default false (opt-in, iron rule 7)
  captionStyle: CaptionStyle;
  calmMode: boolean;                     // C13 — extends AmenSimpleModeService
  largerTouchTargets: 'off' | 'large' | 'xl'; // explicit; calibration on-device only
  sensitivityFilters: SensitivityTopic[];     // C12 user policy
  voiceNavEnabled: boolean;              // C7
}

/** Allowed keys — anything outside this set is a forbidden field and must be denied. */
export const A11Y_PROFILE_ALLOWED_KEYS: ReadonlyArray<keyof A11yProfile> = [
  'readingLevel', 'autoTranslate', 'toneHintsEnabled', 'captionStyle',
  'calmMode', 'largerTouchTargets', 'sensitivityFilters', 'voiceNavEnabled',
];

export const DEFAULT_A11Y_PROFILE: A11yProfile = {
  readingLevel: ReadingLevel.ORIGINAL,
  autoTranslate: false,
  toneHintsEnabled: false,
  captionStyle: {
    size: 'medium', background: 'dim', highContrast: false,
    speed: 'normal', placement: 'bottom',
  },
  calmMode: false,
  largerTouchTargets: 'off',
  sensitivityFilters: [],
  voiceNavEnabled: false,
};

// =============================================================================
// SECTION 5 — TRANSFORM RESULT (callModel → caller → UI)
// =============================================================================

/**
 * The unified return shape of the ailTransform callable. `output` is a string for
 * text tasks, CaptionTrack for caption tasks, ImageDescription for describe_image.
 * confidence === 'low' ⇒ UI shows a hedge. originalRef is ALWAYS resolvable so the
 * UI can offer one-tap "View original". On fail-open, failOpen === true and the
 * caller renders the original content with a quiet "unavailable" state.
 */
export interface A11yTransformResult {
  task: A11yTask;
  output: string | CaptionTrack | ImageDescription | null;
  provenance: A11yProvenance;
  sourceLang?: string;
  targetLang?: string;
  cultureNotes?: CultureNote[];
  confidence: 'high' | 'medium' | 'low';
  originalRef: string;                   // resolvable id/path of original content
  failOpen?: boolean;                    // true ⇒ render original + "unavailable"
  crisisBypass?: boolean;                // true ⇒ produced under crisis-context bypass
}

// =============================================================================
// SECTION 6 — FIRESTORE SCHEMA CONSTANTS
// =============================================================================
//
// Exactly the surfaces below — no other new collections.
//   a11yProfile     : users/{uid}/settings/a11yProfile (owner read/write only)
//   transformCache  : transformCache/{contentId}/{cacheKey} (server-write only,
//                     TTL, content-hash keyed; DM transforms NEVER cached)
//   captions        : SUBCOLLECTION under the parent media doc, inheriting the
//                     parent's read/visibility/encryption tier (Lead decision #4).
//                     Parent media docs today: posts/{postId}/mediaMeta/{mediaId}.
//
// C14 re-entry summaries compute from existing thread data at READ time — no
// per-user read-cursor analytics collection is created.

export const FIRESTORE_PATHS = {
  // Profile
  a11yProfile: (uid: string) => `users/${uid}/settings/a11yProfile`,

  // Transform cache (public content only; DM never cached — see DM_TRANSFORMS_CACHEABLE)
  transformCacheDoc: (contentId: string) => `transformCache/${contentId}`,
  transformCacheKey: (task: A11yTask, lang: string, level: ReadingLevel) =>
    `${task}_${lang}_${level}`,

  // Captions as a subcollection of the parent media document (inherits parent perms)
  captionsCollection: (parentMediaDocPath: string) => `${parentMediaDocPath}/captions`,
  captionDoc: (parentMediaDocPath: string, captionId: string) =>
    `${parentMediaDocPath}/captions/${captionId}`,
} as const;

/** Server-side cache TTL. DM = 0 (never cached). */
export const CACHE_TTL_HOURS = { public: 720, dm: 0 } as const;
export const DM_TRANSFORMS_CACHEABLE = false;

/**
 * Firestore rules contract for the captions subcollection (Lead decision #4):
 * deny-by-default; reads scoped EXACTLY to whoever can read the parent media doc;
 * writes server-only (Cloud Functions / Admin SDK), except a creator edit that
 * flips provenance → AI_HUMAN_EDITED, which still routes through the callable.
 * The A2/A7 rules PR must show this match block nested under the parent path so it
 * inherits the parent's read predicate verbatim.
 */
export const CAPTIONS_RULES_CONTRACT =
  'match /{parentMedia=**}/captions/{captionId} { ' +
  'allow read: if <parent media read predicate>; ' +
  'allow write: if false; /* server-only via ailTransform callable */ }';

// =============================================================================
// SECTION 7 — ROUTING CONFIG ADDITIONS (source of truth)
// =============================================================================
//
// Applied to functions/router/amenRouting.config.js by Phase 1 (this freeze).
// Frozen here as the canonical source. Fail semantics:
//   - AIL transforms FAIL OPEN: fail:"degrade", degradeResult:{ failOpen:true }
//     ⇒ caller renders ORIGINAL content with a quiet "unavailable" state.
//   - explain_scripture is the EXCEPTION: Claude-only, fail_closed, cite-or-refuse.
//   - Claude-only tasks (CLAUDE_ONLY_TASKS) use chain:["claude"] — NO other provider.
// These ride the EXISTING NeMo input/output guard gateway and the cite-or-refuse
// pattern already used by berean_answer/berean_explain — no parallel safety stack.

export const AIL_ROUTING_ADDITIONS = {
  // C1 — general text translation (non-scripture). Fail open to original.
  translate: {
    primary: 'claudeFast', chain: ['claudeFast', 'claude'],
    fail: 'degrade', degradeResult: { failOpen: true },
    outputGuard: true,
    note: 'AIL C1; fail OPEN to original. Scripture NEVER routed here.',
  },
  // C2 — simplify non-scripture text. Fail open to original.
  simplify: {
    primary: 'claudeFast', chain: ['claudeFast', 'claude'],
    fail: 'degrade', degradeResult: { failOpen: true },
    outputGuard: true,
    note: 'AIL C2; non-scripture only; fail OPEN to original.',
  },
  // C2 (scripture) — explanation ALONGSIDE canonical verse. Claude-only, cite-or-refuse.
  explain_scripture: {
    primary: 'claude', chain: ['claude'],
    fail: 'fail_closed', inputGuard: true, outputGuard: true,
    retrieval: 'pinecone', requireCitations: true,
    safetyLevel: 'high',
    note: 'AIL; Claude-only NO fallover; BSB/WEB/KJV only; refuse rather than fabricate. Mirrors berean_explain.',
  },
  // C3 — tone hint, hedged, opt-in. Claude-only; degrade to NO hint (fail open).
  tone_hint: {
    primary: 'claude', chain: ['claude'],
    fail: 'degrade', degradeResult: { failOpen: true },
    outputGuard: true,
    note: 'AIL C3; Claude-only; on-demand; suppressed on Guardian-flagged content; degrade to no-hint.',
  },
  // C10 — reply-with-care pre-send nudge. Claude-only; degrade to no-nudge (never blocks).
  reply_care_check: {
    primary: 'claude', chain: ['claude'],
    fail: 'degrade', degradeResult: { failOpen: true },
    outputGuard: true,
    note: 'AIL C10; suggests only; ZERO shared code path with NeMo; never blocks a send.',
  },
  // C11 — cooldown assist suggested rewrite. Claude-only; degrade to no-suggestion.
  cooldown_rewrite: {
    primary: 'claude', chain: ['claude'],
    fail: 'degrade', degradeResult: { failOpen: true },
    outputGuard: true,
    note: 'AIL C11; suggested rewrite; always dismissible; never blocks.',
  },
  // C5 — image description / alt text. New task (Lead decision #1). No identity/facial claims.
  describe_image: {
    primary: 'gemini', chain: ['gemini', 'geminiPro'],
    fail: 'degrade', degradeResult: { description: '', flagged: true, failOpen: true },
    inputGuard: true, outputGuard: true,
    note: 'AIL C5; scene/action/object/text-in-image ONLY; never names/identifies people or minors.',
  },
  // C6 — audio/video summary (main point / action / tone). New task (Lead decision #1).
  summarize_audio: {
    primary: 'geminiPro', chain: ['geminiPro', 'gemini'],
    fail: 'degrade', degradeResult: { failOpen: true },
    outputGuard: true,
    note: 'AIL C6; main point / action / tone; fail OPEN.',
  },
  // C14 — qualitative re-entry summary. NO counts (iron rule 10). Degrade to no-summary.
  reentry_summary: {
    primary: 'claudeFast', chain: ['claudeFast', 'claude'],
    fail: 'degrade', degradeResult: { failOpen: true },
    outputGuard: true,
    note: 'AIL C14; qualitative only, NEVER numeric novelty counts; degrade to no-summary.',
  },
  // C12 — sensitivity classifier for user-policy blur. Degrade to not-sensitive (fail open = show).
  sensitivity_classify: {
    primary: 'gemini', chain: ['gemini'],
    fail: 'degrade', degradeResult: { topics: [], sensitive: false, failOpen: true },
    note: 'AIL C12; user-policy driven; degrade ⇒ do NOT blur; crisis-help content never blurred.',
  },
  // NOTE: caption_live / caption_recorded are SpeechProvider-adapter bound (SECTION 8),
  // NOT callModel routes. Recorded server ASR may reuse the existing asr_transcribe route.
} as const;

// =============================================================================
// SECTION 8 — SpeechProvider ADAPTER INTERFACE
// =============================================================================
//
// Same pattern as BibleProvider (functions/selah/bibleProviderAdapter.js). Live
// captioning binds to ON-DEVICE Apple Speech (cost/latency/privacy); recorded
// media binds to a SERVER ASR implementation behind the adapter. No vendor names
// in views. Implementations are provided in Phase 2 (A4 owns the client surface;
// the server ASR sits behind A2's callable). caption_live never reaches a server.

export type SpeechMode = 'on_device' | 'server';

export interface SpeechTranscribeRequest {
  mediaId?: string;          // recorded media id (server mode)
  lang: string;              // BCP-47 target
  mode: SpeechMode;
}

export interface SpeechProvider {
  /** Live, on-device streaming captions (Apple Speech). Never hits a server. */
  startLiveCaptions(lang: string, onCue: (cue: CaptionCue) => void): Promise<void>;
  stopLiveCaptions(): Promise<void>;
  /** Recorded-media transcription behind the server ASR adapter. */
  transcribeRecorded(req: SpeechTranscribeRequest): Promise<CaptionTrack>;
}

// =============================================================================
// SECTION 9 — FEATURE FLAGS (reconcile with shipped "System 15" block)
// =============================================================================
//
// The app already ships a 15-flag "System 15: Accessibility Intelligence Layer"
// block in AMENFeatureFlags.swift. AIL REUSES those flags — it does NOT add a
// parallel set. The mapping below binds each capability to an EXISTING flag where
// one exists; only the genuinely-new gates are added (kept default OFF until A8
// verification + your checkpoint). Phase 2 reconciliation is mandatory.

export const FEATURE_FLAGS = {
  // Master gate (existing)
  master: 'accessibilityIntelligenceEnabled',          // EXISTS
  // C1/C2 (existing)
  translate: 'meaningAwareTranslationEnabled',          // EXISTS (C1)
  readingLevel: 'readabilityLayerEnabled',              // EXISTS (C2)
  // C13 (existing — AmenSimpleModeService)
  calmMode: 'naturalModeEnabled',                       // EXISTS (maps to Simple/Calm mode)
  // Genuinely-new gates (ADD, default OFF until checkpoint)
  toneHints: 'ailToneHintsEnabled',                     // NEW (C3)
  imageDescribe: 'ailImageDescribeEnabled',             // NEW (C5)
  audioSummary: 'ailAudioSummaryEnabled',               // NEW (C6)
  voiceNav: 'ailVoiceNavEnabled',                       // NEW (C7)
  commentIntent: 'ailCommentIntentEnabled',             // NEW (C8)
  largerTargets: 'ailLargerTouchTargetsEnabled',        // NEW (C9)
  replyCare: 'ailReplyCareEnabled',                     // NEW (C10)
  cooldownAssist: 'ailCooldownAssistEnabled',           // NEW (C11)
  safetyFilter: 'ailEmotionalSafetyFilterEnabled',      // NEW (C12)
  reentry: 'ailReentrySummaryEnabled',                  // NEW (C14)
} as const;

// =============================================================================
// SECTION 10 — VALIDATION / ENFORCEMENT HELPERS
// =============================================================================

/** Throws if a forbidden field would be persisted to a11yProfile (iron rule 5). */
export function assertNoForbiddenProfileFields(payload: Record<string, unknown>): void {
  const allowed = new Set<string>(A11Y_PROFILE_ALLOWED_KEYS as readonly string[]);
  for (const key of Object.keys(payload)) {
    if (!allowed.has(key)) {
      throw new Error(
        `AIL CONTRACT VIOLATION: forbidden a11yProfile field "${key}". ` +
        `No motor metrics, miss rates, input-timing, or inferred conditions may be stored. ` +
        `Calibration is on-device only; persist the target-size preference only.`
      );
    }
  }
}

/** Throws if a Claude-only task is given any non-Claude provider chain (iron rules 2/8). */
export function assertClaudeOnly(task: A11yTask, chain: string[]): void {
  if (CLAUDE_ONLY_TASKS.includes(task)) {
    const offending = chain.filter((p) => p !== 'claude' && p !== 'claudeFast');
    if (chain.includes('claude') === false || offending.length > 0) {
      throw new Error(
        `AIL CONTRACT VIOLATION: task "${task}" is Claude-only with NO fallover. ` +
        `Chain must be ["claude"]; got [${chain.join(', ')}].`
      );
    }
  }
}

/** True if this task fails OPEN to original (everything except explain_scripture). */
export function failsOpen(task: A11yTask): boolean {
  return !FAIL_CLOSED_TASKS.includes(task);
}

/**
 * Guards iron rule 1: NO user-facing tier gating in AIL paths. Callers must pass
 * the reason for any tier read; only 'batch_precompute_cost_throttle' is allowed,
 * and it must NEVER deny a live user request.
 */
export function assertNoUserFacingTierGate(reason: string): void {
  if (reason !== 'batch_precompute_cost_throttle') {
    throw new Error(
      `AIL CONTRACT VIOLATION: tier checks are forbidden in AIL paths (accessibility is ` +
      `free at every tier). Only cost-throttling batch precompute may read tier, and it ` +
      `must never deny a user. Got reason="${reason}".`
    );
  }
}
