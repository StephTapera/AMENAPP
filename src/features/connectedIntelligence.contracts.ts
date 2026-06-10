/**
 * connectedIntelligence.contracts.ts — AMEN Connected Intelligence v1
 *
 * FROZEN ❄ — Phase 2 agents may not modify. Connected Intelligence v1.
 * OWNER: Agent 1 (Contract Author). Single source of truth for the 6 Phase 2 surfaces.
 *
 * Binds to the frozen Berean contract (src/berean/contracts.ts). Canonical enums
 * (Domain, Plan, CapabilityTier, Provenance, SourceRef, TruthLevel) are imported —
 * NEVER redefined here. The Domain union is FROZEN at 14 values and is NOT extended;
 * every @mention folds into one of those existing values (see MENTION_ROUTING).
 *
 * Firestore timestamp convention: matches the Berean contract — `unknown` at rest
 * (a Firestore Timestamp; serialized to epoch-ms on the client when read).
 *
 * HUMAN DECISIONS encoded here (locked):
 *   1. Drive + Canva connectors DROPPED. ConnectorId = calendar | music | bible | church_mgmt only.
 *   2. @mention → Domain folding (no enum extension). See MENTION_ROUTING.
 *   3. TrustProfile DROPPED from v1 — not defined or referenced anywhere.
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

// ─────────────────────────────────────────────────────────────────────────────
// §4.1 — NEW ENUMS (additive; do not extend the frozen Domain union)
// Drive + Canva intentionally absent (Decision #1).
// ─────────────────────────────────────────────────────────────────────────────

/** Faith-native connectors only. NO drive/canva — ever. */
export enum ConnectorId {
  Calendar = 'calendar',
  Music = 'music',
  Bible = 'bible',
  ChurchMgmt = 'church_mgmt',
}

/** OAuth-style permission scopes a grant may request. */
export enum ConnectorScope {
  ReadEvents = 'read_events',
  WriteEvents = 'write_events',
  ReadPlaylists = 'read_playlists',
  ReadBible = 'read_bible',
  ReadMembership = 'read_membership',
  ReadSermons = 'read_sermons',
}

/** Where the grant consent UI was presented. */
export enum GrantSurface {
  Settings = 'settings',
  Composer = 'composer',
  Brief = 'brief',
  Notebook = 'notebook',
  Mention = 'mention',
}

/** @mention tokens. NO drive/canva (Decision #1). */
export enum ToolMention {
  Bible = 'bible',
  Prayer = 'prayer',
  Calendar = 'calendar',
  Notes = 'notes',
  Sermon = 'sermon',
  Music = 'music',
  Church = 'church',
}

/** Notebook source classes. */
export enum NotebookKind {
  StudySources = 'study_sources',
  SermonPrep = 'sermon_prep',
  PrayerJournal = 'prayer_journal',
  ChurchNotes = 'church_notes',
}

/**
 * Action sheet outcomes. Deferred values ship in the enum but are UI-absent in v1
 * (gated false in connectedIntelligence.config.ts → actionSheet.deferred).
 */
export enum ResponseAction {
  SaveToNotebook = 'save_to_notebook',
  PinToMemory = 'pin_to_memory',
  ShareToSpace = 'share_to_space',
  ScheduleReminder = 'schedule_reminder',
  // ── DEFERRED (UI-absent in v1) ──
  TurnIntoPodcast = 'turn_into_podcast',
  TurnIntoVideoScript = 'turn_into_video_script',
  CreateInfographic = 'create_infographic',
  CreatePresentation = 'create_presentation',
  CreateFlyer = 'create_flyer',
}

/** Kinds of scheduled action. */
export enum ScheduleKind {
  Reminder = 'reminder',
  ReadingPlanNudge = 'reading_plan_nudge',
  PrayerPrompt = 'prayer_prompt',
  BriefDelivery = 'brief_delivery',
}

/** Write-risk tier for a scheduled action (drives Aegis review + dry-run count). */
export enum ScheduleWriteRisk {
  None = 'none',         // read-only / in-app surface
  Low = 'low',           // local notification only
  External = 'external', // writes to a connected external system (calendar) — Aegis-gated
}

/** Sections that may appear in the Daily Brief. */
export enum BriefSection {
  Verse = 'verse',
  Prayer = 'prayer',
  ReadingPlan = 'reading_plan',
  ChurchEvents = 'church_events',
  Reflection = 'reflection',
  Followups = 'followups',
}

// ─────────────────────────────────────────────────────────────────────────────
// §4.2 — CORE INTERFACES
// Timestamp fields typed `unknown` (Firestore Timestamp), matching berean/contracts.ts.
// ─────────────────────────────────────────────────────────────────────────────

/** A user's grant to a connected faith-native provider. */
export interface ConnectorGrant {
  connectorId: ConnectorId;
  scopes: ConnectorScope[];
  grantedVia: GrantSurface;
  status: 'active' | 'revoked' | 'pending';
  /** Provider display id (e.g. the BibleProvider adapter id, or a calendar provider). */
  providerId: string;
  grantedAt: unknown;      // Firestore Timestamp
  revokedAt?: unknown;     // Firestore Timestamp — soft revoke
  /** True if this grant was blocked/auto-revoked because the account is minor-scoped. */
  minorBlocked: boolean;
}

/** A retrieved context chunk injected into a model call. */
export interface ContextItem {
  id: string;
  domain: Domain;
  source: SourceRef;
  text: string;
  /** Connector this context came from, if any. */
  connectorId?: ConnectorId;
  truthLevel: TruthLevel;
  retrievedAt: unknown;    // Firestore Timestamp
}

/**
 * A memory item. v1 EXTENDS the existing store `berean/{uid}/memory/{memoryId}`
 * (shape BereanMemoryDoc) — this is NOT a parallel store. Fields here are a superset
 * view used by Connected Intelligence surfaces; persistence stays in memory.ts.
 */
export interface MemoryItem {
  id: string;
  domain: Domain;
  summary: string;
  refs: SourceRef[];
  pinned: boolean;
  visibility: 'public' | 'followers' | 'paid' | 'organization' | 'private';
  createdAt: unknown;      // Firestore Timestamp
  softDeleted: boolean;
}

/** A notebook: a bounded collection of sources for grounded study/prep. */
export interface Notebook {
  id: string;
  ownerId: string;
  kind: NotebookKind;
  title: string;
  /** Source refs that scope this notebook's grounded answers. */
  sources: SourceRef[];
  sourceCount: number;
  /** Optional Space share — uses existing membership (isSpaceMember). */
  sharedSpaceId?: string;
  createdAt: unknown;      // Firestore Timestamp
  updatedAt: unknown;      // Firestore Timestamp
  softDeleted: boolean;
}

/**
 * A scheduled action. Execution fields are SERVER-ONLY (clients never write them).
 * `enabled: false` in v1 config — these persist but do not fire until Aegis review.
 */
export interface ScheduledAction {
  id: string;
  ownerId: string;
  kind: ScheduleKind;
  writeRisk: ScheduleWriteRisk;
  /** ISO-8601 RRULE or one-shot ISO timestamp. */
  schedule: string;
  /** Connector targeted by the action (calendar writes), if external. */
  connectorId?: ConnectorId;
  active: boolean;
  // ── SERVER-ONLY execution fields (rules deny client writes) ──
  lastRunAt?: unknown;     // Firestore Timestamp
  nextRunAt?: unknown;     // Firestore Timestamp
  dryRunsRemaining: number;
  aegisReviewId: string | null;
  createdAt: unknown;      // Firestore Timestamp
}

/** A single card in the Daily Brief. */
export interface BriefCard {
  id: string;
  section: BriefSection;
  domain: Domain;
  title: string;
  body: string;
  provenance: Provenance;
  /** Action affordances offered on this card. */
  actions: ResponseAction[];
  connectorId?: ConnectorId;
}

// ─────────────────────────────────────────────────────────────────────────────
// §4.4 — MENTION_ROUTING (Decision #2: @mention → Domain folding, NO enum extension)
//
// Folding map (locked):
//   bible    → scripture     prayer → prayer       notes → church_notes
//   calendar → church_notes  sermon → study        music → general
//   church   → admin
//
// provider tiers:
//   'claude-exclusive'    — Claude-only, fail_closed (scripture/pastoral). No fallover.
//   'rag-grounded'        — retrieval-grounded, refuse-if-no-index (notes/notebooks).
//   'tool-orchestration'  — degrade-gracefully (calendar/music connectors).
//
// taskKey values are REAL keys present in functions/router/amenRouting.config.js.
// ─────────────────────────────────────────────────────────────────────────────

export const MENTION_ROUTING: Record<
  ToolMention,
  { domain: Domain; taskKey: string; provider: 'claude-exclusive' | 'rag-grounded' | 'tool-orchestration' }
> = {
  [ToolMention.Bible]:    { domain: 'scripture',    taskKey: 'berean_answer',   provider: 'claude-exclusive' },
  [ToolMention.Prayer]:   { domain: 'prayer',       taskKey: 'prayer_generate', provider: 'claude-exclusive' },
  [ToolMention.Notes]:    { domain: 'church_notes', taskKey: 'berean_explain',  provider: 'rag-grounded' },
  [ToolMention.Calendar]: { domain: 'church_notes', taskKey: 'daily_brief',     provider: 'tool-orchestration' },
  [ToolMention.Sermon]:   { domain: 'study',        taskKey: 'berean_explain',  provider: 'rag-grounded' },
  [ToolMention.Music]:    { domain: 'general',      taskKey: 'berean_explain',  provider: 'tool-orchestration' },
  [ToolMention.Church]:   { domain: 'admin',        taskKey: 'berean_explain',  provider: 'tool-orchestration' },
};

// ─────────────────────────────────────────────────────────────────────────────
// CONNECTOR_ALIASES — map new ConnectorId values onto existing code paths.
// bible       → existing BibleProvider adapter (ConnectorType 'bible')
// church_mgmt → existing church_calendar / sermon_library connector types
// calendar + music → NEW providers (Phase 2 Agent C/E build the adapters/CFs).
//
// `existingConnectorType` reuses the frozen Berean ConnectorType union so no new
// Firestore connector path is created for aliased connectors.
// ─────────────────────────────────────────────────────────────────────────────

export const CONNECTOR_ALIASES: Record<
  ConnectorId,
  {
    /** Existing Berean ConnectorType(s) reused, or null for brand-new providers. */
    existingConnectorType: Array<'bible' | 'church_calendar' | 'giving' | 'sermon_library'> | null;
    isNew: boolean;
    note: string;
  }
> = {
  [ConnectorId.Bible]: {
    existingConnectorType: ['bible'],
    isNew: false,
    note: 'Reuses src/berean/connectors/BibleProvider.ts (getBibleProvider) + bereanBibleLookup CF. Zero new code path.',
  },
  [ConnectorId.ChurchMgmt]: {
    existingConnectorType: ['church_calendar', 'sermon_library'],
    isNew: false,
    note: 'Reuses existing church_calendar + sermon_library connector types/state. Zero new code path.',
  },
  [ConnectorId.Calendar]: {
    existingConnectorType: null,
    isNew: true,
    note: 'NEW provider. Phase 2 Agent builds CalendarProvider adapter + CF (httpsCallable, zero client keys).',
  },
  [ConnectorId.Music]: {
    existingConnectorType: null,
    isNew: true,
    note: 'NEW provider. Phase 2 Agent builds MusicProvider adapter + CF (httpsCallable, zero client keys).',
  },
};
