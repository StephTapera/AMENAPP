/**
 * connectorMeta.ts — Plain-language copy + scope/surface metadata for each connector.
 * OWNER: Phase 2 Agent A. No colors here (those live in styles.ts); copy only.
 */

import {
  ConnectorId,
  ConnectorScope,
  GrantSurface,
} from '../connectedIntelligence.contracts';

export interface ConnectorMeta {
  id: ConnectorId;
  title: string;
  /** Monochrome line-icon glyph (kept simple; SF-style line marks). */
  icon: string;
  tagline: string;
  /** Plain-language "What Amen can see" bullet list. */
  whatAmenCanSee: string[];
  /** Plain-language "What Amen will NOT do" reassurance bullets. */
  whatAmenWontDo: string[];
  examplePrompts: string[];
  /** Scopes this connector supports (UI only shows these). */
  supportedScopes: ConnectorScope[];
  isNew: boolean;
}

export const SCOPE_LABELS: Record<ConnectorScope, { label: string; help: string }> = {
  [ConnectorScope.read_metadata]: {
    label: 'Read titles & times',
    help: 'See item titles, dates, and times — never the full content.',
  },
  [ConnectorScope.read_content]: {
    label: 'Read content',
    help: 'See the full content of items so Amen can summarize them.',
  },
  [ConnectorScope.write_draft]: {
    label: 'Prepare drafts',
    help: 'Prepare drafts for you to review. Nothing is sent or saved without you.',
  },
  [ConnectorScope.write_commit]: {
    label: 'Make changes (needs confirmation)',
    help: 'Make a change in the connected app. Always asks you first, every time.',
  },
};

export const SURFACE_LABELS: Record<GrantSurface, { label: string; help: string }> = {
  [GrantSurface.berean]: {
    label: 'Berean chat',
    help: 'Use this connector when you ask Berean a question.',
  },
  [GrantSurface.daily_brief]: {
    label: 'Daily brief',
    help: 'Include items in your morning brief.',
  },
  [GrantSurface.notebooks]: {
    label: 'Notebooks',
    help: 'Pull items into your notebooks.',
  },
  [GrantSurface.scheduled_actions]: {
    label: 'Reminders & scheduled actions',
    help: 'Use this connector for reminders and scheduled tasks.',
  },
  [GrantSurface.action_sheet]: {
    label: 'Quick actions',
    help: 'Show this connector in the quick-action menu on a response.',
  },
};

export const CONNECTOR_META: Record<ConnectorId, ConnectorMeta> = {
  [ConnectorId.calendar]: {
    id: ConnectorId.calendar,
    title: 'Calendar',
    icon: '▢',
    tagline: 'Reminders and your daily brief — on your terms.',
    whatAmenCanSee: [
      'Your upcoming event titles, dates, and times.',
      'Only summaries are kept — the full event stays in your calendar.',
    ],
    whatAmenWontDo: [
      'Read who you meet with or your private notes unless you allow content.',
      'Add or change anything without asking you first.',
    ],
    examplePrompts: [
      'What do I have coming up this week?',
      'Remind me to pray for Sunday’s sermon prep.',
    ],
    supportedScopes: [
      ConnectorScope.read_metadata,
      ConnectorScope.read_content,
      ConnectorScope.write_draft,
      ConnectorScope.write_commit,
    ],
    isNew: true,
  },
  [ConnectorId.music]: {
    id: ConnectorId.music,
    title: 'Music',
    icon: '◇',
    tagline: 'Worship and reflection playlists, matched to your moment.',
    whatAmenCanSee: [
      'Your saved worship playlists and recently played songs.',
      'Only titles and artists are used — never your listening identity.',
    ],
    whatAmenWontDo: [
      'Post what you listen to anywhere.',
      'Change your playback or library without asking.',
    ],
    examplePrompts: [
      'Suggest a worship song for this Psalm.',
      'Build a reflective playlist for my quiet time.',
    ],
    supportedScopes: [ConnectorScope.read_metadata, ConnectorScope.read_content],
    isNew: true,
  },
  [ConnectorId.bible]: {
    id: ConnectorId.bible,
    title: 'Bible',
    icon: '▤',
    tagline: 'Open-licensed Scripture, already built in.',
    whatAmenCanSee: [
      'The open-license translations you read (BSB, WEB, KJV).',
      'Nothing leaves the app — Scripture lookups are local to Amen.',
    ],
    whatAmenWontDo: [
      'Share your reading with anyone.',
      'Use a paid translation without a licensed agreement.',
    ],
    examplePrompts: [
      'Show me John 3:16 in BSB.',
      'Read Psalm 23 to me.',
    ],
    supportedScopes: [ConnectorScope.read_content],
    isNew: false,
  },
  [ConnectorId.church_mgmt]: {
    id: ConnectorId.church_mgmt,
    title: 'Church',
    icon: '⬚',
    tagline: 'Your church calendar and sermon library.',
    whatAmenCanSee: [
      'Your church’s public events and sermon archive.',
      'Only what your church has shared — nothing private.',
    ],
    whatAmenWontDo: [
      'Access giving or member records.',
      'Make changes to your church’s systems.',
    ],
    examplePrompts: [
      'When is the next church event?',
      'Summarize last Sunday’s sermon.',
    ],
    supportedScopes: [ConnectorScope.read_metadata, ConnectorScope.read_content],
    isNew: false,
  },
};

export const ORDERED_CONNECTORS: ConnectorId[] = [
  ConnectorId.calendar,
  ConnectorId.music,
  ConnectorId.bible,
  ConnectorId.church_mgmt,
];
