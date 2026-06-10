/**
 * connectedIntelligence.contracts.ts — AMEN Connected Intelligence v1
 *
 * FROZEN ❄ — Phase 2 agents may not modify. Connected Intelligence v1.
 * OWNER: Agent 1 (Contract Author). Single source of truth for the 6 Phase 2 surfaces.
 *
 * Binds to the frozen Berean contract (src/berean/contracts.ts). Canonical types
 * (Domain, Plan, CapabilityTier, Provenance, SourceRef, TruthLevel) are IMPORTED —
 * never redefined here. The Domain union is FROZEN at 14 values and is NOT extended;
 * every @mention folds into one of those existing values (see MENTION_ROUTING).
 *
 * Enum VALUES below are transcribed verbatim from the swarm spec §4.1/§4.2 — the only
 * deviations are the two locked human decisions:
 *   1. Drive + Canva connectors DROPPED → absent from ConnectorId and ToolMention.
 *   2. @mention → Domain folding (no enum extension) → see MENTION_ROUTING.
 *   3. TrustProfile DROPPED from v1 — not defined or referenced anywhere.
 *
 * Firestore timestamp convention matches berean/contracts.ts (`unknown` at rest —
 * a Firestore Timestamp, serialized to epoch-ms on the client). Aliased as `Timestamp`
 * so the interfaces read exactly like the spec.
 */

import type {
  Provenance,
  SourceRef,
  TruthLevel,
  Plan,
  CapabilityTier,
  Domain,
} from '../berean/contracts';

// Re-export the bound canonical types so Phase 2 surfaces import from one place.
export type { Provenance, SourceRef, TruthLevel, Plan, CapabilityTier, Domain };

/** Firestore Timestamp at rest (matches berean/contracts.ts convention). */
export type Timestamp = unknown;

// ─────────────────────────────────────────────────────────────────────────────
// §4.1 — NEW ENUMS (additive; do NOT extend the frozen Domain union)
// Values are verbatim from spec §4.1. Drive + Canva intentionally absent (Decision #1).
// ─────────────────────────────────────────────────────────────────────────────

/** Faith-native connectors only. NO drive/canva — ever (Decision #1). */
export enum ConnectorId {
  calendar = 'calendar',          // Google Calendar v1; Apple EventKit at SwiftUI parity
  music = 'music',                // Spotify v1; Apple Music later — provider behind adapter
  bible = 'bible',                // ALIAS to existing BibleProvider adapter — no new integration
  church_mgmt = 'church_mgmt',    // ALIAS to existing church_calendar/sermon_library — no new integration
}

/** Generic grant scopes. `write_commit` requires ConfirmationGate at grant AND each use. */
export enum ConnectorScope {
  read_metadata = 'read_metadata',
  read_content = 'read_content',
  write_draft = 'write_draft',
  write_commit = 'write_commit',
}

/** The consuming surfaces a grant may be scoped to (per-surface permissioning). */
export enum GrantSurface {
  berean = 'berean',
  daily_brief = 'daily_brief',
  notebooks = 'notebooks',
  scheduled_actions = 'scheduled_actions',
  action_sheet = 'action_sheet',
}

/** @mention tokens in the Berean composer. NO drive/canva (Decision #1). */
export enum ToolMention {
  bible = 'bible',
  prayer = 'prayer',
  calendar = 'calendar',
  notes = 'notes',
  sermon = 'sermon',
  music = 'music',
  church = 'church',
}

/** Notebook kinds. */
export enum NotebookKind {
  sermon = 'sermon',
  study = 'study',
  prayer_journal = 'prayer_journal',
  project = 'project',
  group = 'group',
  event = 'event',
}

/**
 * Response-action taxonomy for the action sheet (spec §4.1, verbatim).
 * Deferred values exist in the enum (frozen) but ship config-flagged OFF with their
 * buttons ABSENT from the UI — see connectedIntelligence.config.ts → actionSheet.deferred.
 */
export enum ResponseAction {
  // Knowledge
  save_to_note = 'save_to_note',
  add_to_notebook = 'add_to_notebook',
  add_to_prayer_journal = 'add_to_prayer_journal',
  // Community
  add_to_space = 'add_to_space',
  discuss_in_space = 'discuss_in_space',
  send_to_friend = 'send_to_friend',
  ask_my_church = 'ask_my_church',
  ask_my_group = 'ask_my_group',
  ask_my_notes = 'ask_my_notes',
  // AI transforms
  simplify = 'simplify',
  deep_dive = 'deep_dive',
  challenge_this = 'challenge_this',
  show_sources = 'show_sources',
  verify_scripture = 'verify_scripture',
  generate_questions = 'generate_questions',
  // Action
  create_task = 'create_task',
  add_to_calendar = 'add_to_calendar',
  build_plan = 'build_plan',
  create_poll = 'create_poll',
  turn_into_post = 'turn_into_post',
  turn_into_carousel = 'turn_into_carousel',
  // Memory
  remember_this = 'remember_this',
  forget_this = 'forget_this',
  why_remembered = 'why_remembered',
  show_related = 'show_related',
  // Continuity
  continue_later = 'continue_later',
  // DEFERRED — frozen in enum, but config-flagged OFF and ABSENT from UI in v1:
  turn_into_video_script = 'turn_into_video_script',
  turn_into_podcast = 'turn_into_podcast',
  create_infographic = 'create_infographic',
  create_presentation = 'create_presentation',
  create_flyer = 'create_flyer',
}

export enum ScheduleKind {
  reminder = 'reminder',
  digest = 'digest',
  follow_up = 'follow_up',
}

/** NO autonomous external writes at v1 — ceiling is drafts_for_approval. */
export enum ScheduleWriteRisk {
  read_only = 'read_only',
  drafts_for_approval = 'drafts_for_approval',
}

export enum BriefSection {
  events = 'events',
  messages_needing_attention = 'messages_needing_attention',
  prayer_updates = 'prayer_updates',
  saved_verse = 'saved_verse',
  follow_ups = 'follow_ups',
  community = 'community',
}

// ─────────────────────────────────────────────────────────────────────────────
// §4.2 — CORE INTERFACES (verbatim from spec; Provenance is the canonical import)
// ─────────────────────────────────────────────────────────────────────────────

export interface ConnectorGrant {
  uid: string;
  connectorId: ConnectorId;
  scopes: ConnectorScope[];               // write_commit requires ConfirmationGate at grant time AND at each use
  surfaces: GrantSurface[];               // per-surface permissioning: "Calendar for reminders, not recommendations"
                                          //   = surfaces:['scheduled_actions'] minus ['berean']
  grantedAt: Timestamp;
  expiresAt: Timestamp | null;            // temporary grants supported
  status: 'active' | 'revoked' | 'error';
  minorBlocked: true;                     // literal true — schema-level assertion; rules reject grant docs for minors
}

/** The ONLY shape connector data may enter a prompt in. */
export interface ContextItem {
  source: ConnectorId | 'amen_native';
  provenance: Provenance;                 // canonical
  surface: GrantSurface;
  fetchedAt: Timestamp;
  summaryOnly: boolean;                   // raw third-party content never persists; summaries + pointers only
  payload: string;
  pointer: string | null;                 // deep link back to source of truth
}

export interface MemoryItem {
  uid: string;
  text: string;
  origin: 'explicit_remember' | 'imported_note' | 'imported_highlight'; // v1: NO passive-inference origin exists
  sourcePointer: string | null;
  createdAt: Timestamp;
  deletedAt: Timestamp | null;            // soft delete; hard purge job runs after retention window
}

export interface Notebook {
  id: string;
  uid: string;
  kind: NotebookKind;
  title: string;
  sourceRefs: Array<{ type: 'note' | 'sermon' | 'verse_range' | 'doc' | 'chat_checkpoint'; pointer: string }>;
  pineconeNamespace: string;              // per-notebook namespace; fail-closed: no index ⇒ refuse, never ungrounded
  sharedWithSpaceId: string | null;       // group notebooks
  createdAt: Timestamp;
  deletedAt: Timestamp | null;
}

export interface ScheduledAction {
  id: string;
  uid: string;
  kind: ScheduleKind;
  rrule: string;
  humanReadable: string;
  prompt: string;                         // what the agent does each run
  writeRisk: ScheduleWriteRisk;           // read_only ⇒ cards; drafts_for_approval ⇒ drafts behind ConfirmationGate
  surfaces: GrantSurface[];
  sabbathSuppressed: boolean;             // default true; safety/crisis kinds may not be scheduled (route to Guardian)
  dryRun: boolean;                        // default true on creation; first N runs render "would have done X" cards
  aegisReviewId: string | null;           // feature ships disabled until populated in config
  status: 'active' | 'paused' | 'dry_run' | 'deleted';
}

export interface BriefCard {
  uid: string;
  date: string;                           // one per user per day, generated on-demand (pull), cached
  sections: Array<{ section: BriefSection; items: ContextItem[] }>;
  maxItemsTotal: 9;                       // hard cap, contract-level
  sabbathSuppressed: boolean;
  minorMode: boolean;                     // true ⇒ zero connector-sourced items
}

// ─────────────────────────────────────────────────────────────────────────────
// §4.4 — MENTION_ROUTING (Decision #2: @mention → Domain folding, NO enum extension)
//
// Folding map (locked):
//   bible    → scripture     prayer → prayer       notes → church_notes
//   calendar → church_notes  sermon → study        music → general       church → admin
//
// provider tiers:
//   'claude-exclusive'    — Claude-only, fail_closed (scripture/pastoral). No fallover, any tier.
//   'rag-grounded'        — retrieval-grounded, refuse-if-no-index (notes/sermon/notebooks).
//   'tool-orchestration'  — degrade-gracefully (calendar/music/church connectors).
//
// taskKey values are REAL keys present in functions/router/amenRouting.config.js.
// ─────────────────────────────────────────────────────────────────────────────

export const MENTION_ROUTING: Record<
  ToolMention,
  { domain: Domain; taskKey: string; provider: 'claude-exclusive' | 'rag-grounded' | 'tool-orchestration' }
> = {
  [ToolMention.bible]:    { domain: 'scripture',    taskKey: 'berean_answer',   provider: 'claude-exclusive' },
  [ToolMention.prayer]:   { domain: 'prayer',       taskKey: 'prayer_generate', provider: 'claude-exclusive' },
  [ToolMention.notes]:    { domain: 'church_notes', taskKey: 'berean_explain',  provider: 'rag-grounded' },
  [ToolMention.calendar]: { domain: 'church_notes', taskKey: 'daily_brief',     provider: 'tool-orchestration' },
  [ToolMention.sermon]:   { domain: 'study',        taskKey: 'berean_explain',  provider: 'rag-grounded' },
  [ToolMention.music]:    { domain: 'general',      taskKey: 'berean_explain',  provider: 'tool-orchestration' },
  [ToolMention.church]:   { domain: 'admin',        taskKey: 'berean_explain',  provider: 'tool-orchestration' },
};

// ─────────────────────────────────────────────────────────────────────────────
// CONNECTOR_ALIASES — map new ConnectorId values onto existing code paths.
// bible       → existing BibleProvider adapter (ConnectorType 'bible')
// church_mgmt → existing church_calendar / sermon_library connector types
// calendar + music → NEW providers (Phase 2 builds adapters/CFs; httpsCallable, zero client keys).
// ─────────────────────────────────────────────────────────────────────────────

export const CONNECTOR_ALIASES: Record<
  ConnectorId,
  {
    existingConnectorType: Array<'bible' | 'church_calendar' | 'giving' | 'sermon_library'> | null;
    isNew: boolean;
    note: string;
  }
> = {
  [ConnectorId.bible]: {
    existingConnectorType: ['bible'],
    isNew: false,
    note: 'Reuses src/berean/connectors/BibleProvider.ts (getBibleProvider) + bereanBibleLookup CF. Zero new code path.',
  },
  [ConnectorId.church_mgmt]: {
    existingConnectorType: ['church_calendar', 'sermon_library'],
    isNew: false,
    note: 'Reuses existing church_calendar + sermon_library connector types/state. Zero new code path.',
  },
  [ConnectorId.calendar]: {
    existingConnectorType: null,
    isNew: true,
    note: 'NEW provider. Phase 2 builds CalendarProvider adapter + CF (httpsCallable, zero client keys).',
  },
  [ConnectorId.music]: {
    existingConnectorType: null,
    isNew: true,
    note: 'NEW provider. Phase 2 builds MusicProvider adapter + CF (httpsCallable, zero client keys).',
  },
};
