/**
 * index.ts — Public exports for the Berean composer @mention layer.
 *
 * Agent D (@Tool Mentions) — Connected Intelligence Phase 2.
 *
 * Primary entry point: <MentionComposer/>. Drop it where the raw input row lived in
 * BereanApp.tsx → ChatScreen. See HANDOFF.md for the exact attach point.
 *
 * OWNER: Agent D. Create-only under src/features/berean/composer/**.
 */

// ── Components ────────────────────────────────────────────────────────────────
export { MentionComposer, type MentionComposerProps } from './MentionComposer';
export { MentionPicker } from './MentionPicker';
export { DegradedChip } from './DegradedChip';
export { CalendarDraftCard } from './CalendarDraftCard';

// ── Orchestration hook ────────────────────────────────────────────────────────
export {
  useMentionComposer,
  type UseMentionComposerParams,
  type MentionComposerState,
  type SubmitOutcome,
  type PickerItem,
  type PickerLoadState,
  type DegradedSignal,
  type DraftPending,
} from './useMentionComposer';

// ── Pure logic (parser / routing / config) ────────────────────────────────────
export {
  detectTrigger,
  applyMentionSelection,
  parseMessage,
  classifyCalendarIntent,
  isToolOrchestrationTurn,
  type ActiveTrigger,
  type ParsedMessage,
  type ParsedMention,
  type CalendarIntent,
} from './mentionParser';

export {
  MENTION_DESCRIPTORS,
  MENTION_ORDER,
  descriptorForToken,
  type MentionDescriptor,
  type MentionGating,
  type MentionProvider,
} from './mentionConfig';

// ── Services (injectable seams) ───────────────────────────────────────────────
export {
  grantsReader,
  makeGrantsReader,
  grantUnlocksBerean,
  defaultGrantLoader,
  type GrantsReader,
  type GrantLoader,
  type ConnectorAvailability,
} from './grantsReader';

export {
  contextGatherer,
  makeContextGatherer,
  buildEnrichedInput,
  type ContextGatherer,
  type GatherResult,
  type GatherStatus,
} from './contextGatherer';

export {
  calendarDraftService,
  makeCalendarDraftService,
  type CalendarDraftService,
  type CalendarDraft,
  type DraftResult,
  type CommitResult,
} from './calendarDraftService';
