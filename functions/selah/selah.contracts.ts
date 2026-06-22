/**
 * selah.contracts.ts — FROZEN CONTRACT FILE
 *
 * Authored by Phase 1 Contract Freeze Agent, 2026-06-07.
 * DO NOT EDIT without updating all consuming agents (A, B, C, D, E).
 *
 * This file owns:
 * - Discernment types and interfaces
 * - SelahNote personal corpus type
 * - Firestore path constants
 * - Routing config additions (to be applied to amenRouting.config.js by wiring agent)
 * - Feature flag names
 * - Liquid Glass design tokens (§1–§9 from Appendix A)
 * - Validation/enforcement helpers
 *
 * Integration contract items (DO NOT REDEFINE — import from intelligence/contracts.js):
 * - TruthLevel
 * - Domain (fourteen-value enum)
 * - TrustProfile
 * - Plan
 * - CapabilityTier
 *
 * HARD LEGAL CONSTRAINT: OpenTranslation ('BSB' | 'WEB' | 'KJV') are the ONLY translations
 * permitted in AI citation paths. Licensed translations (ESV, NIV, NLT, NASB, etc.) may only
 * appear in the human reader path (SelahNote.translationRead) and must never flow into
 * any AI engine, discernment check, or Pinecone namespace.
 *
 * HUMAN GATE: selah.discernmentSharing flag requires explicit human approval before production.
 */

// =============================================================================
// SECTION 1 — INTEGRATION CONTRACT IMPORTS (reference only — do not redefine)
// =============================================================================
//
// The following types are imported from intelligence/contracts.js at runtime.
// They are NOT redefined here. Any consuming agent must import them directly:
//
//   import { TruthLevel, Domain } from '../intelligence/contracts.js';
//   import { TrustProfile, Plan, CapabilityTier } from '../intelligence/contracts.js';
//
// - TruthLevel        — scalar truth-confidence enum used across the intelligence layer
// - Domain            — fourteen-value enum spanning all Berean knowledge domains
// - TrustProfile      — user trust posture composite from the integration contract
// - Plan              — subscription/capability plan from the integration contract
// - CapabilityTier    — gating tier from the integration contract
//
// =============================================================================


// =============================================================================
// SECTION 2 — CORE ENUMS & TYPES
// =============================================================================

/** Which surface the discernment check was initiated from. */
export type DiscernmentSourceType =
  | 'comment'
  | 'post'
  | 'space_message'
  | 'pasted_text'
  | 'selah_note'
  | 'verse';

/** Whether the discernment pipeline completed or was stopped. Fail-closed: refused is the safe default. */
export type DiscernmentStatus = 'grounded' | 'refused'; // fail closed

/** The theological verdict for a grounded discernment check. */
export type DiscernmentVerdict =
  | 'aligns'
  | 'diverges'
  | 'contested'
  | 'insufficient';

/**
 * Open-license Bible translations permitted in AI citation paths.
 * HARD CONSTRAINT: only BSB/WEB/KJV may appear here.
 * Licensed versions (ESV, NIV, NLT, NASB, etc.) are NEVER permitted in this type
 * and must never be passed to the AI engine, discernment check, or Pinecone namespace.
 */
export type OpenTranslation = 'BSB' | 'WEB' | 'KJV'; // quoting engine ONLY — licensed versions never appear here

/** Classification of the theological or factual nature of a claim. */
export type ClaimClass =
  | 'doctrinal'
  | 'ethical'
  | 'historical'
  | 'devotional'
  | 'unverifiable';

/** Visibility of a discernment check result. Defaults to 'private'. */
export type Visibility = 'private' | 'shared'; // private-first default

/** A single Bible citation. Translation MUST be an open-licensed version. */
export interface Citation {
  reference: string;
  translation: OpenTranslation; // HARD CONSTRAINT: only BSB/WEB/KJV; reject anything else
  text: string;
}

/** A discrete theological or factual claim extracted from the source text. */
export interface Claim {
  text: string;
  classification: ClaimClass;
}

/** A single theological tradition's perspective on a contested claim. */
export interface Perspective {
  tradition: string;
  summary: string;
  citations: Citation[];
}

/**
 * DiscernmentCheck — the primary output of the Berean discernment pipeline.
 *
 * Invariants:
 * - status === 'refused'  => verdict is null, citations is empty, refusalReason is set
 * - status === 'grounded' => verdict is non-null
 * - perspectives is populated only when verdict === 'contested'
 * - citations contains ONLY open-licensed text (BSB/WEB/KJV)
 * - deletedAt is the ONLY delete mechanism; hard-delete is forbidden
 */
export interface DiscernmentCheck {
  id: string;
  sourceType: DiscernmentSourceType;
  sourceRef: string | null;    // id of internal object, else null
  inputText: string;           // post-moderation text
  status: DiscernmentStatus;   // 'refused' => verdict/citations/perspectives are null/empty
  verdict: DiscernmentVerdict | null;
  claims: Claim[];
  citations: Citation[];       // open-licensed text only; hard legal constraint
  perspectives: Perspective[]; // populated when verdict === 'contested'
  refusalReason: string | null; // set when status === 'refused'
  truthLevel: string;          // TruthLevel from integration contract
  createdBy: string;           // uid
  visibility: Visibility;      // defaults to 'private'
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;    // soft-delete ONLY; no hard-delete path
}

/**
 * SelahNote — personal corpus unit.
 *
 * Notes are the atomic units of the user's private study corpus.
 * translationRead may be any version the user reads (including licensed),
 * but it is for display ONLY and must NEVER be passed to the AI citation path.
 * deletedAt is the ONLY delete mechanism; hard-delete is forbidden.
 */
export interface SelahNote {   // personal corpus unit
  id: string;
  userId: string;
  verseRef: string;
  translationRead: string;     // may be a licensed version (for display only — NEVER passed to AI citation path)
  kind: 'highlight' | 'note' | 'question' | 'prayer';
  color: string | null;        // verse highlight palette: cyan/amber/pink/lavender
  body: string | null;
  indexedToCorpus: boolean;    // true when synced to user's private Pinecone namespace
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;    // soft-delete only
}


// =============================================================================
// SECTION 3 — FIRESTORE SCHEMA CONSTANTS
// =============================================================================

/**
 * Frozen Firestore collection and document path builders.
 *
 * Access rules (enforced in Firestore rules + Cloud Functions):
 * - selahNotes: read/write by owner (uid) only
 * - discernmentChecks: read by createdBy; when shared, read by thread participants
 * - Hard rule: deletedAt is the only delete mechanism; no document deletion
 */
export const FIRESTORE_PATHS = {
  selahNotes: (uid: string) => `users/${uid}/selahNotes`,
  selahNote: (uid: string, noteId: string) => `users/${uid}/selahNotes/${noteId}`,
  discernmentChecks: () => `discernmentChecks`,
  discernmentCheck: (checkId: string) => `discernmentChecks/${checkId}`,
} as const;


// =============================================================================
// SECTION 4 — ROUTING CONFIG ADDITIONS
// =============================================================================
//
// These must be added to functions/router/amenRouting.config.js by the wiring agent.
// They are frozen here as the source of truth.

/**
 * Routing config for the discernment task.
 * Claude-only, no fallover. NeMo guards both input and output.
 * fail_closed: if all retries fail, return a graceful error — never fabricate.
 */
export const DISCERNMENT_ROUTING = {
  task: 'discernment',
  primary: 'claude',          // Claude-only, no fallover
  chain: ['claude'],
  failPolicy: 'fail_closed',  // retry with backoff; graceful error if all retries fail
  safetyLevel: 'high',
  inputGuard: true,           // NeMo runs first, before Claude
  outputGuard: true,
  requireCitations: true,     // fail_closed if zero open-licensed citations
  retryConfig: {
    maxAttempts: 3,
    backoffMs: [500, 1500, 4000],
  },
  notes: 'Pastoral/discernment tasks are Claude-only with NO fallover to any other provider.',
} as const;

/**
 * Routing config for Selah personal corpus retrieval via Pinecone.
 * Uses a per-user private namespace. Cross-user retrieval is strictly forbidden.
 * fail gracefully with empty result rather than fabricated content.
 */
export const SELAH_CORPUS_RETRIEVAL_ROUTING = {
  task: 'selah_corpus_retrieve',
  primary: 'pinecone',
  chain: ['pinecone'],
  failPolicy: 'return_empty',  // fail gracefully: empty result, not fabricated content
  pineconeNamespace: (uid: string) => `selah-notes-${uid}`,
  notes: 'User private namespace — no cross-user retrieval ever.',
} as const;

/** Default translation to use in the discernment/citation engine when none is specified. */
export const DEFAULT_DISCERNMENT_TRANSLATION: OpenTranslation = 'BSB';


// =============================================================================
// SECTION 5 — FEATURE FLAGS
// =============================================================================
//
// Flag names are frozen here. Values are managed in Firebase Remote Config.
// HUMAN GATE: selah.discernmentSharing requires explicit human approval before prod.

export const FEATURE_FLAGS = {
  selahPersonalCorpus: 'selah.personalCorpus',    // enables note → Pinecone indexing
  selahDiscernment: 'selah.discernment',           // enables Berean check feature
  selahDiscernmentSharing: 'selah.discernmentSharing', // HUMAN GATE required before enabling in prod
} as const;


// =============================================================================
// SECTION 6 — LIQUID GLASS DESIGN TOKENS
// =============================================================================
//
// Design tokens for Selah Liquid Glass surfaces.
// Targeting iOS 26.1 refinement: more frosted/opaque, legibility-first, minimal color bleed.
// All Selah UI agents (A and D) consume these; none may hardcode glass values.

export const GLASS_TOKENS = {
  // §1 Foundations
  pageBackground: '#F2F2F3',           // neutral light gray, never pure white behind cards
  textPrimary: '#0A0A0A',
  textSecondary: '#8A8A8E',

  // §2 Floating white card
  cardFill: '#FFFFFF',
  cardRadius: 28,
  cardShadowAmbient: '0 12px 40px rgba(0,0,0,0.10)',
  cardShadowTight: '0 2px 8px rgba(0,0,0,0.04)',
  cardPadding: { min: 20, max: 24 },

  // §3 Photo hero + dark glass pill
  heroScrimGradient: 'linear-gradient(transparent, rgba(0,0,0,0.65))',
  heroScrimHeight: '45%',              // percentage of hero height
  darkGlassPill: 'rgba(20,20,20,0.40)',
  darkGlassPillBlur: 20,              // px, backdrop-filter: blur()
  darkGlassPillPadding: { vertical: 14, horizontal: 22 },

  // §4 Light frosted glass (toolbars, nav, pills — iOS 26.1 more opaque)
  lightGlassFill: 'rgba(255,255,255,0.72)',
  lightGlassBlur: 24,                 // px
  lightGlassSaturate: 1.2,
  lightGlassHairlineTop: '1px rgba(255,255,255,0.6)',
  lightGlassShadow: '0 1px 4px rgba(0,0,0,0.06)',
  minTapTarget: 44,                   // px

  // §5 Native segmented control
  segmentTrack: '#E6E6E8',
  segmentSelected: '#FFFFFF',
  segmentSelectedShadow: '0 1px 3px rgba(0,0,0,0.12)',
  segmentUnselectedLabel: '#8A8A8E',

  // §6 Liquid Glass context menu
  contextMenuFill: 'rgba(250,250,250,0.80)',
  contextMenuBlur: 30,                // px
  contextMenuRadius: 20,

  // §7 Discernment result card
  citationBlockFill: '#F5F5F6',
  citationBlockRadius: 16,

  // §8 Verse highlight palette (reader only — exempt from color ban)
  highlightColors: {
    cyan: 'rgba(100,200,220,0.25)',
    amber: 'rgba(255,180,50,0.25)',
    pink: 'rgba(255,100,150,0.20)',
    lavender: 'rgba(160,130,255,0.22)',
  },

  // FORBIDDEN (never use in Selah UI):
  // - '#C9A84C' or '#FFD97D' (gold)
  // - '#7B68EE' (accent purple)
  // - Cosmic dark gradients
  // - Cormorant Garamond font
} as const;


// =============================================================================
// SECTION 7 — VALIDATION HELPERS
// =============================================================================

/**
 * Enforces the open-translation hard rule.
 * Throws if the translation is not BSB, WEB, or KJV.
 * Call this at every boundary where text enters the AI citation path.
 */
export function assertOpenTranslation(translation: string): asserts translation is OpenTranslation {
  const allowed: OpenTranslation[] = ['BSB', 'WEB', 'KJV'];
  if (!allowed.includes(translation as OpenTranslation)) {
    throw new Error(
      `HARD CONTRACT VIOLATION: Translation "${translation}" is not open-licensed. ` +
      `Only BSB/WEB/KJV may appear in AI citation paths. Licensed versions (ESV, NIV, NLT, etc.) ` +
      `are restricted to the human reader path and must never be passed to the AI engine.`
    );
  }
}

/**
 * Enforces soft-delete-only semantics.
 * Throws if a hard-delete operation is attempted on a Selah document.
 * Call this in any Cloud Function that receives a delete operation name.
 */
export function assertSoftDeleteOnly(operation: string): void {
  if (operation === 'delete' || operation === 'hardDelete') {
    throw new Error(
      `HARD CONTRACT VIOLATION: Hard delete is forbidden in Selah. ` +
      `Set deletedAt to the current timestamp instead.`
    );
  }
}

/**
 * Validates the internal consistency of a DiscernmentCheck before write.
 * Enforces fail-closed invariants:
 * - 'refused' status => verdict null, citations empty, refusalReason present
 * - 'grounded' status => verdict non-null
 */
export function validateDiscernmentCheck(check: Partial<DiscernmentCheck>): void {
  if (check.status === 'refused') {
    if (check.verdict != null) throw new Error('Contract violation: refused check must have null verdict');
    if (check.citations && check.citations.length > 0) throw new Error('Contract violation: refused check must have empty citations');
    if (!check.refusalReason) throw new Error('Contract violation: refused check must have a refusalReason');
  }
  if (check.status === 'grounded' && !check.verdict) {
    throw new Error('Contract violation: grounded check must have a verdict');
  }
}
