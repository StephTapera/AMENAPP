/**
 * contracts.ts — Berean v1 single source of truth
 * Phase 1 contract freeze. All Phase 2 agents import from here; never redefine.
 *
 * FROZEN: 2026-06-07
 * OWNER: Phase 1 Contract Agent
 */

// ─────────────────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────────────────

export type Visibility =
  | 'public'        // Books, music, sermons, podcasts
  | 'followers'     // Personal teachings, extra notes
  | 'paid'          // Courses, study guides, premium content
  | 'organization'  // Church / business / team resources
  | 'private';      // Drafts, uploads, unpublished — DEFAULT for all Berean output

export type Domain =
  | 'scripture'
  | 'prayer'
  | 'devotional'
  | 'theology'
  | 'pastoral'
  | 'study'
  | 'church_notes'
  | 'reflection'
  | 'discovery'
  | 'admin'
  | 'giving'
  | 'safety'
  | 'general'
  | 'crisis';

export type TruthLevel = 'grounded' | 'inferred' | 'refused';

export interface SourceRef {
  type: 'scripture' | 'commentary' | 'catechism' | 'church_document' | 'web';
  label: string;      // e.g. "John 3:16 (BSB)" or "Westminster Confession §5"
  url?: string;       // optional deep link
}

export interface Provenance {
  sources: SourceRef[];
  truthLevel: TruthLevel;
}

export type CapabilityTier = 'free' | 'plus' | 'pro'; // depth/cost only — NEVER safety

export type Plan = 'free' | 'plus' | 'pro';

export type VoicePersona = 'still' | 'warm' | 'clear' | 'plain'; // reverent — NOT "Buttery"

export type VoiceMode = 'hands_free' | 'push_to_talk';

export type VoiceSpeed = 'slow' | 'normal' | 'fast';

export type ConnectorType = 'bible' | 'church_calendar' | 'giving' | 'sermon_library';

export type SafetyLevel = 'standard' | 'pastoral' | 'minor' | 'crisis';

export type RefusalReason =
  | 'no_grounded_source'
  | 'crisis_handoff'
  | 'minor_scope'
  | 'capability_disabled'
  | 'moderation_blocked'
  | 'provider_unavailable';

// ─────────────────────────────────────────────────────────────────────────────
// callModel SIGNATURE (frozen)
// ─────────────────────────────────────────────────────────────────────────────

export interface BereanCallModelParams {
  task: Domain;
  input: string;
  context: BereanContext;
  userId: string;
  safetyLevel: SafetyLevel;
}

export interface BereanCallModelResult {
  text: string;
  provenance: Provenance;
  refusal?: RefusalReason;
  blocked?: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// BereanContext — injected into every callModel call
// ─────────────────────────────────────────────────────────────────────────────

export interface BereanContext {
  userId: string;
  plan: Plan;
  safetyLevel: SafetyLevel;
  minorScoped: boolean;
  capabilities: BereanCapabilities;
  /** Relevant memory summaries fetched from berean/{uid}/memory before this call */
  memoryContext?: MemorySummary[];
  /** Connector data injected for this call (e.g. today's reading plan passage) */
  connectorContext?: ConnectorContext;
}

export interface MemorySummary {
  domain: Domain;
  summary: string;
  pinned: boolean;
  refs: SourceRef[];
}

export interface ConnectorContext {
  type: ConnectorType;
  data: Record<string, unknown>;
}

// ─────────────────────────────────────────────────────────────────────────────
// Firestore schema types (frozen, collection: berean/{userId}/...)
// ─────────────────────────────────────────────────────────────────────────────

export interface BereanMemoryDoc {
  domain: Domain;
  summary: string;
  refs: SourceRef[];
  pinned: boolean;
  visibility: Visibility;     // default 'private'
  createdAt: unknown;         // Firestore Timestamp
  softDeleted: boolean;       // soft-delete only — hard deletes denied
}

export interface BereanThreadDoc {
  domain: Domain;
  title: string;
  lastMessageAt: unknown;
  visibility: Visibility;
}

export interface BereanMessageDoc {
  threadId: string;
  role: 'user' | 'assistant';
  text: string;
  provenance: Provenance;
  safetyLevel: SafetyLevel;
  createdAt: unknown;
}

export interface BereanUsageDoc {
  sessionPct: number;          // 0–100
  weeklyPct: number;           // 0–100
  creditsUsed: number;
  creditsCap: number;
  safetyExempt: true;          // always true — safety actions never counted
  resetsAt: unknown;           // Firestore Timestamp
}

export interface BereanCapabilities {
  memory: boolean;
  proactive: boolean;
  voice: boolean;
  minorScoped: boolean;
  connectors: {
    bible: boolean;
    church_calendar: boolean;
    giving: boolean;
    sermon_library: boolean;
  };
}

export interface BereanConnectorDoc {
  type: ConnectorType;
  status: 'active' | 'revoked' | 'pending';
  providerId: string;
  scopes: string[];
  connectedAt: unknown;
}

export interface CreditConfigDoc {
  costByDomain: Record<Domain, number>;
  capByPlan: Record<Plan, number>;
  safetyExemptDomains: Array<'safety' | 'crisis'>;
}

export interface VoiceConfigDoc {
  personas: VoicePersona[];
  speeds: VoiceSpeed[];
  languages: string[];
}

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS (frozen) — white/light Apple-native Liquid Glass
// ─────────────────────────────────────────────────────────────────────────────

export const tokens = {
  bg:        '#F4F4F2',
  card:      '#FFFFFF',
  shadow:    '0 1px 3px rgba(0,0,0,0.06), 0 8px 24px rgba(0,0,0,0.04)',
  text:      '#0A0A0A',
  textSub:   '#6B6B6B',
  divider:   '#E6E6E3',
  accent:    '#007AFF',   // iOS system blue — selection/checkmarks only
  glassPill: 'rgba(20,20,20,0.55)',
  radius:    20,
} as const;

// FORBIDDEN tokens — reject on sight:
// cosmic-dark gradients, '#C9A84C', '#FFD97D', '#7B68EE', Cormorant Garamond

// ─────────────────────────────────────────────────────────────────────────────
// ROUTING TASK MAP — maps Domain → callModel task string
// ─────────────────────────────────────────────────────────────────────────────

export const DOMAIN_TO_TASK: Record<Domain, string> = {
  scripture:    'berean_answer',
  prayer:       'prayer_generate',
  devotional:   'berean_explain',
  theology:     'berean_perspective',
  pastoral:     'berean_answer',
  study:        'berean_explain',
  church_notes: 'berean_explain',
  reflection:   'prayer_rewrite',
  discovery:    'berean_proactive',
  admin:        'berean_explain',
  giving:       'berean_explain',
  safety:       'guard_input',        // safety tier — never metered
  general:      'berean_explain',
  crisis:       'crisis_handoff',     // human gate — AI answer suppressed
};

// ─────────────────────────────────────────────────────────────────────────────
// MINOR GUARD
// ─────────────────────────────────────────────────────────────────────────────

/** Domains blocked for minor-scoped accounts */
export const MINOR_BLOCKED_DOMAINS: Domain[] = ['discovery', 'admin', 'giving'];

/** Connectors blocked for minor-scoped accounts */
export const MINOR_BLOCKED_CONNECTORS: ConnectorType[] = [
  'giving', 'sermon_library',
];

/** Visibility levels blocked for minor writes */
export const MINOR_BLOCKED_VISIBILITY: Visibility[] = ['public', 'organization'];

// ─────────────────────────────────────────────────────────────────────────────
// HUMAN GATES — scaffold only, never auto-implement
// ─────────────────────────────────────────────────────────────────────────────

export type HumanGateReason =
  | 'MINOR_GRAPH_DATA'   // any graph data touching a minor account
  | 'CRISIS_CONTENT'     // crisis handoff content (T&S owns response queue)
  | 'CSAM_SIGNAL';       // route through ncmecReporter.js pipeline

export interface HumanGatePayload {
  reason: HumanGateReason;
  userId: string;
  timestamp: string;
  /** opaque context passed to T&S — no AI-authored content here */
  context: Record<string, string>;
}
