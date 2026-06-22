/**
 * spiritualIntelligenceContracts.ts — Berean Spiritual Intelligence Layer
 * Wave 0 contracts. Frozen after commit; behavior in subsequent waves.
 *
 * AIL rule: TypeScript is source of truth; Swift mirrors in
 * AMENAPP/AIIntelligence/BereanSpiritualIntelligenceContracts.swift.
 *
 * DO NOT import from contracts.ts (Phase 1 frozen).
 * All flags default OFF, fail-closed. No flag flips in this build.
 */

// ─────────────────────────────────────────────────────────────────────────────
// PRIVACY-CORE ZONE CLASSIFICATION
// Single source of truth — imported by all other contract files.
// ─────────────────────────────────────────────────────────────────────────────

export type PrivacyCoreZone =
  | 'public'      // No PII, freely indexable
  | 'functional'  // Needed for product function, encrypted in transit
  | 'preference'  // User preferences, low sensitivity
  | 'behavioral'  // Usage patterns — aggregate only, never exported raw
  | 'sensitive'   // Faith/health adjacent; encrypted at rest
  | 'high'        // Prayer, crisis, confession — AES-256-GCM at rest; user-deletable
  | 'identity';   // Auth credentials, verified identity fields

// ─────────────────────────────────────────────────────────────────────────────
// BEREAN DEPTH AXIS (auto-selected, overridable per-thread)
// UNIFIED ENUM — single source of truth app-wide.
// Five stops support the depth-dial UI; semantic names, not display labels.
// Prior 3-level (Glance/Study/Examine) maps to quick/study/deep.
// ─────────────────────────────────────────────────────────────────────────────

export type BereanDepth =
  | 'quick'        // Single primary source + cross-ref; lowest latency / cost
  | 'study'        // Multi-source, cross-refs, lexicon, commentary snippets
  | 'deep'         // Full retrieval + original-language + church history
  | 'multiSource'  // All study agents + denominational comparison
  | 'research';    // Maximum strictness; citation verification at every step

export type BereanAgentSet =
  | 'base'
  | 'context'
  | 'interpretation'
  | 'lexicon'
  | 'history'
  | 'denomination'
  | 'citation';

export interface BereanDepthBudget {
  depth: BereanDepth;
  retrievalBreadth: 'single' | 'multi' | 'full' | 'exhaustive';
  agentSet: BereanAgentSet[];
  latencyBudgetMs: number;
  tokenCeiling: number;
}

export const DEPTH_BUDGETS: Record<BereanDepth, BereanDepthBudget> = {
  quick:       { depth: 'quick',       retrievalBreadth: 'single',     agentSet: ['base'],                                                          latencyBudgetMs:  3_000, tokenCeiling:  2_000 },
  study:       { depth: 'study',       retrievalBreadth: 'multi',      agentSet: ['base', 'context', 'interpretation'],                             latencyBudgetMs:  8_000, tokenCeiling:  6_000 },
  deep:        { depth: 'deep',        retrievalBreadth: 'full',       agentSet: ['base', 'context', 'interpretation', 'lexicon', 'history'],       latencyBudgetMs: 18_000, tokenCeiling: 14_000 },
  multiSource: { depth: 'multiSource', retrievalBreadth: 'full',       agentSet: ['base', 'context', 'interpretation', 'lexicon', 'history', 'denomination'], latencyBudgetMs: 30_000, tokenCeiling: 22_000 },
  research:    { depth: 'research',    retrievalBreadth: 'exhaustive', agentSet: ['base', 'context', 'interpretation', 'lexicon', 'history', 'denomination', 'citation'], latencyBudgetMs: 60_000, tokenCeiling: 40_000 },
};

// ─────────────────────────────────────────────────────────────────────────────
// INTENT PROPOSAL (mode × depth — auto-selected, shown as a small chip)
// Posture modes live in the existing BereanMode enum in the Phase 1 contracts.
// This adds the orthogonal depth axis; no new mode types are created here.
// ─────────────────────────────────────────────────────────────────────────────

export type BereanPostureMode = 'ask' | 'discern' | 'build' | 'guard' | 'reflect';

export interface IntentProposal {
  mode: BereanPostureMode;
  depth: BereanDepth;
  /** Confidence 0–1; show chip only when >= 0.7 */
  confidence: number;
  /** Human-readable rationale shown in the chip */
  rationale: string;
  readonly autoSelected: true;
}

export interface IntentOverride {
  mode?: BereanPostureMode;
  depth?: BereanDepth;
  threadId: string;
  overriddenAt: number; // epoch ms
}

// ─────────────────────────────────────────────────────────────────────────────
// SCRIPTURE CONNECTOR FRAMEWORK
// Tier A ships now. Tiers B/C are contracts + stubs only.
// ─────────────────────────────────────────────────────────────────────────────

export type ConnectorTier = 'A' | 'B' | 'C';

export type RedistributionKind = 'public_domain' | 'cc' | 'licensed' | 'restricted';

export interface LicenseMetadata {
  name: string;
  redistribution: RedistributionKind;
  attributionRequired: boolean;
  attributionText?: string;
  cacheable: boolean;
  displayLimits?: {
    maxVerses?: number;
    requiresPassageContext?: boolean;
    noFullBibleDump: boolean;
  };
}

export type TranslationCode = string; // e.g. 'BSB', 'NET', 'KJV', 'WEB'

export type ScriptureCapabilityKind =
  | 'passage_lookup'
  | 'cross_references'
  | 'lexicon'           // Original-language data (Greek/Hebrew)
  | 'commentary'
  | 'translator_notes'  // NET Bible famous notes
  | 'strong_numbers'
  | 'morphology'
  | 'search';

export interface ScriptureSource {
  id: string;
  name: string;
  tier: ConnectorTier;
  /** Always false in this build — no flag flips */
  enabled: false;
  defaultTranslation?: TranslationCode;
  availableTranslations: TranslationCode[];
  license: LicenseMetadata;
  /** true = API key must stay server-side only, never in client bundle */
  requiresProxiedKey: boolean;
  capabilities: ScriptureCapabilityKind[];
}

// Seed registry for Tier A sources (behavior wired in Wave 1)
// ESV/NIV/NASB are absent — not free; no YouVersion path.
export const TIER_A_SOURCES: ScriptureSource[] = [
  {
    id: 'free_use_bible_api',
    name: 'Free Use Bible API (AO Lab)',
    tier: 'A',
    enabled: false,
    defaultTranslation: 'BSB', // Berean Standard Bible — public domain since 2023
    availableTranslations: ['BSB', 'KJV', 'WEB', 'YLT', 'ASV'],
    license: { name: 'Public Domain / CC', redistribution: 'public_domain', attributionRequired: false, cacheable: true, displayLimits: { noFullBibleDump: false } },
    requiresProxiedKey: false,
    capabilities: ['passage_lookup', 'cross_references', 'search'],
  },
  {
    id: 'api_bible',
    name: 'API.Bible',
    tier: 'A',
    enabled: false,
    defaultTranslation: 'BSB',
    availableTranslations: ['BSB', 'KJV', 'WEB', 'ASV'],
    license: { name: 'API.Bible Starter (public-domain / CC translations only)', redistribution: 'cc', attributionRequired: true, attributionText: 'Scripture from API.Bible', cacheable: true, displayLimits: { noFullBibleDump: true } },
    requiresProxiedKey: true, // Key must be proxied — never client-side
    capabilities: ['passage_lookup', 'cross_references', 'search'],
  },
  {
    id: 'net_bible',
    name: 'NET Bible (labs.bible.org)',
    tier: 'A',
    enabled: false,
    defaultTranslation: 'NET',
    availableTranslations: ['NET'],
    license: { name: 'NET Bible (free with attribution)', redistribution: 'cc', attributionRequired: true, attributionText: 'Scripture quotations taken from the NET Bible®, https://netbible.com, copyright ©1996-2006 by Biblical Studies Press, L.L.C. All rights reserved.', cacheable: true, displayLimits: { noFullBibleDump: true } },
    requiresProxiedKey: false,
    capabilities: ['passage_lookup', 'translator_notes', 'search'],
  },
  {
    id: 'oshb_sblgnt',
    name: 'Open Original-Language Data (OSHB / SBLGNT / STEPBible)',
    tier: 'A',
    enabled: false,
    availableTranslations: ['BHS', 'SBLGNT'],
    license: { name: 'CC BY 4.0', redistribution: 'cc', attributionRequired: true, attributionText: 'Hebrew: OSHB (Open Scriptures); Greek: SBLGNT / STEPBible TAGNT', cacheable: true, displayLimits: { noFullBibleDump: false } },
    requiresProxiedKey: false,
    capabilities: ['passage_lookup', 'lexicon', 'strong_numbers', 'morphology'],
  },
];

// Tier B stubs — contracts only, no implementation
export type TierBPlatform = 'planning_center' | 'church_center' | 'propresenter' | 'subsplash' | 'tithe_ly';

export interface TierBConnectorStub {
  platform: TierBPlatform;
  tier: 'B';
  enabled: false; // deferred until post-launch
}

// Tier C stubs — productivity OAuth, deferred entirely
export type TierCPlatform = 'google_drive' | 'gmail' | 'google_calendar' | 'notion' | 'slack' | 'canva' | 'figma';

export interface TierCConnectorStub {
  platform: TierCPlatform;
  tier: 'C';
  enabled: false; // deferred to post-launch; no OAuth wired in this build
}

// ─────────────────────────────────────────────────────────────────────────────
// CITATION VERDICT — GUARDIAN capability: Scripture Citation Integrity
// Every verse Berean emits is verified before display. Fail-closed.
// C-next capability number assigned at GUARDIAN registration time.
// ─────────────────────────────────────────────────────────────────────────────

export type CitationResult =
  | 'verified'      // Quotation matches source text within acceptable variance
  | 'flagged'       // Quotation differs materially from source
  | 'fabricated'    // Reference not found in any connected source
  | 'unverifiable'  // Source unavailable — fail-closed: treat as fabricated
  | 'paraphrase';   // Intentional paraphrase; must be labeled as such

export interface CitationVerdict {
  reference: string;       // e.g. "Romans 8:28"
  quotation: string;       // The text Berean is about to emit
  result: CitationResult;
  sourceId: string;        // Which ScriptureSource was checked
  translation: TranslationCode;
  actualText?: string;     // Present when result is flagged/fabricated
  confidence: number;      // 0.0–1.0
  checkedAt: number;       // epoch ms
  depth: BereanDepth;      // Strictness scales with depth
}

// Fail-closed guard: any non-verified result blocks emission or forces visible flag
export function isCitationBlocking(verdict: CitationVerdict): boolean {
  return verdict.result === 'flagged'
      || verdict.result === 'fabricated'
      || verdict.result === 'unverifiable';
}

// ─────────────────────────────────────────────────────────────────────────────
// BEREAN MEMORY RECORD (zone-classified; sensitive fields encrypted at rest)
// User can inspect and delete all memory. Flag OFF for launch.
// ─────────────────────────────────────────────────────────────────────────────

export type MemoryField =
  | 'preferredTranslation'  // zone: preference
  | 'studyStyle'            // zone: preference
  | 'theologicalLean'       // zone: sensitive
  | 'denominationalLean'    // zone: sensitive
  | 'readingHabits'         // zone: behavioral
  | 'prayerHistory';        // zone: high — encrypted at rest

export const MEMORY_FIELD_ZONES: Record<MemoryField, PrivacyCoreZone> = {
  preferredTranslation: 'preference',
  studyStyle:           'preference',
  theologicalLean:      'sensitive',
  denominationalLean:   'sensitive',
  readingHabits:        'behavioral',
  prayerHistory:        'high',
};

export interface BereanMemoryRecord {
  id: string;
  uid: string;
  field: MemoryField;
  zone: PrivacyCoreZone;
  /** Encrypted blob (AES-256-GCM) when zone === 'high'; plaintext otherwise */
  value: string;
  encryptedAtRest: boolean; // MUST be true when zone === 'high'
  createdAt: number;
  updatedAt: number;
  /** Invariants — always true; never false */
  readonly userCanInspect: true;
  readonly userCanDelete: true;
}
