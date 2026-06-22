/**
 * mentionConfig.ts — Static metadata for every @mention token in the Berean composer.
 *
 * Agent D (@Tool Mentions) — Connected Intelligence Phase 2.
 *
 * Each ToolMention folds into a Domain + taskKey + provider tier (from the FROZEN
 * MENTION_ROUTING). This file adds the UI-only metadata MENTION_ROUTING does not carry:
 * trigger token, display label, glyph, one-line description, gating class, and (for
 * connector-backed mentions) the ConnectorId whose grant unlocks it.
 *
 * GATING:
 *   - 'ungated'   → @bible @prayer @notes @sermon @church : ALWAYS in the picker.
 *   - 'connector' → @calendar @music : in the picker ONLY when an active, berean-scoped,
 *                   unexpired ConnectorGrant exists (see grantsReader). Minor ⇒ never.
 *
 * Note: @church folds to the `admin` domain via tool-orchestration but reuses the
 * existing church_mgmt alias (church_calendar / sermon_library) — it is NOT grant-gated
 * here; it degrades gracefully on connector error like any tool-orchestration mention.
 *
 * OWNER: Agent D. Create-only under src/features/berean/composer/**.
 */

import {
  ToolMention,
  ConnectorId,
  MENTION_ROUTING,
  type Domain,
} from '../../connectedIntelligence.contracts';

export type MentionGating = 'ungated' | 'connector';
export type MentionProvider = 'claude-exclusive' | 'rag-grounded' | 'tool-orchestration';

export interface MentionDescriptor {
  mention: ToolMention;
  /** The literal typed after `@`, e.g. "bible". Matched case-insensitively. */
  token: string;
  label: string;
  /** Plain unicode glyph — no emoji-heavy or palette-coupled iconography. */
  glyph: string;
  description: string;
  domain: Domain;
  taskKey: string;
  provider: MentionProvider;
  gating: MentionGating;
  /** Present only for gating === 'connector'. */
  connectorId: ConnectorId | null;
}

/**
 * Single source of mention UI metadata. domain/taskKey/provider are pulled from the
 * FROZEN MENTION_ROUTING so this file can never drift from the contract.
 */
export const MENTION_DESCRIPTORS: Record<ToolMention, MentionDescriptor> = {
  [ToolMention.bible]: {
    mention: ToolMention.bible,
    token: 'bible',
    label: 'Bible',
    glyph: '✝',
    description: 'Scripture — grounded, Claude-exclusive',
    domain: MENTION_ROUTING[ToolMention.bible].domain,
    taskKey: MENTION_ROUTING[ToolMention.bible].taskKey,
    provider: MENTION_ROUTING[ToolMention.bible].provider,
    gating: 'ungated',
    connectorId: null,
  },
  [ToolMention.prayer]: {
    mention: ToolMention.prayer,
    token: 'prayer',
    label: 'Prayer',
    glyph: '🕊',
    description: 'Write or shape a prayer',
    domain: MENTION_ROUTING[ToolMention.prayer].domain,
    taskKey: MENTION_ROUTING[ToolMention.prayer].taskKey,
    provider: MENTION_ROUTING[ToolMention.prayer].provider,
    gating: 'ungated',
    connectorId: null,
  },
  [ToolMention.notes]: {
    mention: ToolMention.notes,
    token: 'notes',
    label: 'My Notes',
    glyph: '❒',
    description: 'Grounded in your church notes',
    domain: MENTION_ROUTING[ToolMention.notes].domain,
    taskKey: MENTION_ROUTING[ToolMention.notes].taskKey,
    provider: MENTION_ROUTING[ToolMention.notes].provider,
    gating: 'ungated',
    connectorId: null,
  },
  [ToolMention.sermon]: {
    mention: ToolMention.sermon,
    token: 'sermon',
    label: 'Sermons',
    glyph: '◍',
    description: 'Grounded in your sermon library',
    domain: MENTION_ROUTING[ToolMention.sermon].domain,
    taskKey: MENTION_ROUTING[ToolMention.sermon].taskKey,
    provider: MENTION_ROUTING[ToolMention.sermon].provider,
    gating: 'ungated',
    connectorId: null,
  },
  [ToolMention.church]: {
    mention: ToolMention.church,
    token: 'church',
    label: 'My Church',
    glyph: '⛪',
    description: 'Church calendar & library',
    domain: MENTION_ROUTING[ToolMention.church].domain,
    taskKey: MENTION_ROUTING[ToolMention.church].taskKey,
    provider: MENTION_ROUTING[ToolMention.church].provider,
    gating: 'ungated',
    connectorId: null,
  },
  [ToolMention.calendar]: {
    mention: ToolMention.calendar,
    token: 'calendar',
    label: 'Calendar',
    glyph: '▦',
    description: 'Your schedule — connect required',
    domain: MENTION_ROUTING[ToolMention.calendar].domain,
    taskKey: MENTION_ROUTING[ToolMention.calendar].taskKey,
    provider: MENTION_ROUTING[ToolMention.calendar].provider,
    gating: 'connector',
    connectorId: ConnectorId.calendar,
  },
  [ToolMention.music]: {
    mention: ToolMention.music,
    token: 'music',
    label: 'Music',
    glyph: '♪',
    description: 'Worship & playlists — connect required',
    domain: MENTION_ROUTING[ToolMention.music].domain,
    taskKey: MENTION_ROUTING[ToolMention.music].taskKey,
    provider: MENTION_ROUTING[ToolMention.music].provider,
    gating: 'connector',
    connectorId: ConnectorId.music,
  },
};

/** Stable display order for the picker. */
export const MENTION_ORDER: ToolMention[] = [
  ToolMention.bible,
  ToolMention.prayer,
  ToolMention.notes,
  ToolMention.sermon,
  ToolMention.church,
  ToolMention.calendar,
  ToolMention.music,
];

/** Lookup a descriptor by the raw token typed after `@` (case-insensitive). */
export function descriptorForToken(token: string): MentionDescriptor | null {
  const lower = token.toLowerCase();
  for (const m of MENTION_ORDER) {
    if (MENTION_DESCRIPTORS[m].token === lower) return MENTION_DESCRIPTORS[m];
  }
  return null;
}
