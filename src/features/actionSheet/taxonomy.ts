/**
 * src/features/actionSheet/taxonomy.ts
 *
 * The Response Action taxonomy → grouped descriptors for the sheet, plus the
 * deferred-filter that removes (NOT disables) config-flagged-off actions.
 *
 * Deferred actions whose config flag is false are ABSENT from the descriptor
 * list entirely — they never render as disabled buttons.
 *
 * OWNER: Agent F (Response Action Sheet). Connected Intelligence v1.
 */

import { ResponseAction } from '../connectedIntelligence.contracts';
import { connectedIntelligence } from '../connectedIntelligence.config';
import type { ActionDescriptor, ActionGroup } from './types';

// The full v1 taxonomy. Deferred entries are listed but filtered out at runtime
// when their config flag is false (which is the v1 default for all five).
const ALL_ACTIONS: ActionDescriptor[] = [
  // ── Knowledge ──────────────────────────────────────────────────────────────
  { action: ResponseAction.save_to_note,          group: 'Knowledge', label: 'Save to note',        icon: '🗒', pill: true },
  { action: ResponseAction.add_to_notebook,       group: 'Knowledge', label: 'Add to notebook',     icon: '📓' },
  { action: ResponseAction.add_to_prayer_journal, group: 'Knowledge', label: 'Add to prayer journal', icon: '🙏' },

  // ── Community ──────────────────────────────────────────────────────────────
  { action: ResponseAction.add_to_space,    group: 'Community', label: 'Add to a Space', icon: '⊕' },
  { action: ResponseAction.discuss_in_space, group: 'Community', label: 'Discuss in Space', icon: '💬', pill: true },
  { action: ResponseAction.send_to_friend,  group: 'Community', label: 'Send to a friend', icon: '➤' },
  { action: ResponseAction.ask_my_church,   group: 'Community', label: 'Ask my church', icon: '⛪' },
  { action: ResponseAction.ask_my_group,    group: 'Community', label: 'Ask my group', icon: '👥' },
  { action: ResponseAction.ask_my_notes,    group: 'Community', label: 'Ask my notes', icon: '🔎' },

  // ── AI transforms ──────────────────────────────────────────────────────────
  { action: ResponseAction.simplify,           group: 'AI transforms', label: 'Simplify', icon: '◔' },
  { action: ResponseAction.deep_dive,          group: 'AI transforms', label: 'Deep dive', icon: '◎' },
  { action: ResponseAction.challenge_this,     group: 'AI transforms', label: 'Challenge this', icon: '⚖' },
  { action: ResponseAction.show_sources,       group: 'AI transforms', label: 'Show sources', icon: '❡' },
  { action: ResponseAction.verify_scripture,   group: 'AI transforms', label: 'Verify scripture', icon: '✓' },
  { action: ResponseAction.generate_questions, group: 'AI transforms', label: 'Generate questions', icon: '?' },

  // ── Action ─────────────────────────────────────────────────────────────────
  { action: ResponseAction.create_task,       group: 'Action', label: 'Create task', icon: '☑' },
  { action: ResponseAction.add_to_calendar,   group: 'Action', label: 'Add to calendar', icon: '📅' },
  { action: ResponseAction.build_plan,        group: 'Action', label: 'Build a plan', icon: '🗂' },
  { action: ResponseAction.create_poll,       group: 'Action', label: 'Create a poll', icon: '📊' },
  { action: ResponseAction.turn_into_post,    group: 'Action', label: 'Turn into post', icon: '✎', pill: true },
  { action: ResponseAction.turn_into_carousel, group: 'Action', label: 'Turn into carousel', icon: '▦' },

  // ── Memory ─────────────────────────────────────────────────────────────────
  { action: ResponseAction.remember_this,  group: 'Memory', label: 'Remember this', icon: '★', pill: true },
  { action: ResponseAction.forget_this,    group: 'Memory', label: 'Forget this', icon: '☆' },
  { action: ResponseAction.why_remembered, group: 'Memory', label: 'Why remembered?', icon: 'ⓘ' },
  { action: ResponseAction.show_related,   group: 'Memory', label: 'Show related', icon: '⋈' },

  // ── Continuity ─────────────────────────────────────────────────────────────
  { action: ResponseAction.continue_later, group: 'Continuity', label: 'Continue later', icon: '⏱', pill: true },

  // ── DEFERRED (config.actionSheet.deferred — all false in v1 ⇒ filtered out) ──
  { action: ResponseAction.turn_into_video_script, group: 'Action', label: 'Turn into video script', icon: '🎬' },
  { action: ResponseAction.turn_into_podcast,      group: 'Action', label: 'Turn into podcast', icon: '🎙' },
  { action: ResponseAction.create_infographic,     group: 'Action', label: 'Create infographic', icon: '🖼' },
  { action: ResponseAction.create_presentation,    group: 'Action', label: 'Create presentation', icon: '📽' },
  { action: ResponseAction.create_flyer,           group: 'Action', label: 'Create flyer', icon: '🪧' },
];

/** Map of deferred action → its config flag value. */
const DEFERRED = connectedIntelligence.actionSheet.deferred;

/** True when an action is a deferred outcome whose flag is OFF (⇒ absent). */
function isDeferredOff(action: ResponseAction): boolean {
  const flag = (DEFERRED as Record<string, boolean | undefined>)[action];
  // Only the five deferred actions appear in DEFERRED. For all others, undefined.
  return flag === false || (flag === undefined && action in DEFERRED);
}

/**
 * The actions that actually render in v1. Deferred-off actions are removed,
 * not disabled. Pure — no side effects.
 */
export const VISIBLE_ACTIONS: ActionDescriptor[] = ALL_ACTIONS.filter(
  (d) => !(d.action in DEFERRED) || (DEFERRED as Record<string, boolean>)[d.action] === true,
);

/** The quick-access actions shown on the floating pill (subset of VISIBLE_ACTIONS). */
export const PILL_ACTIONS: ActionDescriptor[] = VISIBLE_ACTIONS.filter((d) => d.pill);

/** Group order for the expanded sheet. */
export const GROUP_ORDER: ActionGroup[] = [
  'Knowledge', 'Community', 'AI transforms', 'Action', 'Memory', 'Continuity',
];

/** Visible actions grouped for the sheet, in display order. */
export function groupedActions(): Array<{ group: ActionGroup; items: ActionDescriptor[] }> {
  return GROUP_ORDER.map((group) => ({
    group,
    items: VISIBLE_ACTIONS.filter((d) => d.group === group),
  })).filter((g) => g.items.length > 0);
}

// Re-export for callers that want to assert nothing deferred leaked through.
export { isDeferredOff };
