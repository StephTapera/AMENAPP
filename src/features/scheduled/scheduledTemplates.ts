/**
 * scheduledTemplates.ts — AMEN Connected Intelligence v1, Phase 2 (Agent E)
 *
 * Natural-language → ScheduledAction PREVIEW. This is the deterministic parser
 * the creation flow runs BEFORE any write: it produces an rrule + humanReadable
 * + writeRisk so the user confirms a concrete, legible action — never a black box.
 *
 * HARD CEILINGS (honored here, structurally):
 *   • writeRisk ∈ { read_only, drafts_for_approval } — the enum has nothing else,
 *     so no autonomous external write is even expressible.
 *   • ScheduleKind ∈ { reminder, digest, follow_up } — safety/crisis are NOT in
 *     the enum, so they are structurally un-schedulable here (route to Guardian).
 *
 * Imports the FROZEN contracts; never redefines a contract type.
 */

import {
  ScheduledAction,
  ScheduleKind,
  ScheduleWriteRisk,
  GrantSurface,
} from '../connectedIntelligence.contracts';

// ─────────────────────────────────────────────────────────────────────────────
// PREVIEW shape — everything needed to render a confirmation card. This is NOT
// a persisted doc; it is the parsed proposal the user confirms or edits.
// ─────────────────────────────────────────────────────────────────────────────

export interface ScheduledActionPreview {
  templateId: string;
  kind: ScheduleKind;
  rrule: string;
  humanReadable: string;
  prompt: string;
  writeRisk: ScheduleWriteRisk;
  surfaces: GrantSurface[];
  /** Default true per spec; digest kinds may NOT override to false (no digest spam). */
  sabbathSuppressed: boolean;
  /** True ⇒ Sabbath override is structurally disallowed for this template. */
  sabbathOverrideLocked: boolean;
  /** Care-framed templates carry an explicit consent requirement before activation. */
  requiresConsent: boolean;
  /** User-facing one-liner shown beneath the title. */
  blurb: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// TEMPLATES — the six shipped scheduled-action shapes. Each is a pure factory so
// the preview is reproducible and inspectable.
// ─────────────────────────────────────────────────────────────────────────────

export interface TemplateDef {
  id: string;
  title: string;
  blurb: string;
  /** Keywords the NL parser matches against (lowercased, substring). */
  keywords: string[];
  build: () => ScheduledActionPreview;
}

const READ_ONLY = ScheduleWriteRisk.read_only;
const DRAFTS = ScheduleWriteRisk.drafts_for_approval;

export const TEMPLATES: TemplateDef[] = [
  {
    id: 'daily_prayer_reminder',
    title: 'Daily prayer reminder',
    blurb: 'A gentle nudge each morning to pause and pray.',
    keywords: ['daily prayer', 'pray every day', 'morning prayer', 'prayer reminder'],
    build: () => ({
      templateId: 'daily_prayer_reminder',
      kind: ScheduleKind.reminder,
      rrule: 'FREQ=DAILY;BYHOUR=7;BYMINUTE=0',
      humanReadable: 'Every day at 7:00 AM',
      prompt:
        'Offer a short, warm prompt to pause and pray, drawn from the person’s ' +
        'saved prayer list. Surface as a private card only.',
      writeRisk: READ_ONLY,
      surfaces: [GrantSurface.scheduled_actions],
      sabbathSuppressed: true,
      sabbathOverrideLocked: false,
      requiresConsent: false,
      blurb: 'A gentle nudge each morning to pause and pray.',
    }),
  },
  {
    id: 'weekly_reading_plan',
    title: 'Weekly reading plan',
    blurb: 'Your next passage, delivered at the start of each week.',
    keywords: ['reading plan', 'weekly reading', 'bible plan', 'reading reminder'],
    build: () => ({
      templateId: 'weekly_reading_plan',
      kind: ScheduleKind.reminder,
      rrule: 'FREQ=WEEKLY;BYDAY=MO;BYHOUR=8;BYMINUTE=0',
      humanReadable: 'Every Monday at 8:00 AM',
      prompt:
        'Surface this week’s passage from the active reading plan, with a one-line ' +
        'framing question. Private card; no external write.',
      writeRisk: READ_ONLY,
      surfaces: [GrantSurface.scheduled_actions],
      sabbathSuppressed: true,
      sabbathOverrideLocked: false,
      requiresConsent: false,
      blurb: 'Your next passage, delivered at the start of each week.',
    }),
  },
  {
    id: 'friday_group_digest',
    title: 'Friday group digest',
    blurb: 'A weekly recap of your group’s discussion, ready to share.',
    keywords: ['group digest', 'weekly digest', 'friday digest', 'group recap'],
    build: () => ({
      templateId: 'friday_group_digest',
      kind: ScheduleKind.digest,
      rrule: 'FREQ=WEEKLY;BYDAY=FR;BYHOUR=16;BYMINUTE=0',
      humanReadable: 'Every Friday at 4:00 PM',
      prompt:
        'Draft a warm recap of the group’s week — highlights, shared verses, and ' +
        'upcoming items. Produce a DRAFT for the leader to review and send.',
      writeRisk: DRAFTS,
      surfaces: [GrantSurface.scheduled_actions],
      // Digest kinds: Sabbath suppression is LOCKED on (no digest spam on rest day).
      sabbathSuppressed: true,
      sabbathOverrideLocked: true,
      requiresConsent: false,
      blurb: 'A weekly recap of your group’s discussion, ready to share.',
    }),
  },
  {
    id: 'sunday_service_reminder',
    title: 'Sunday service reminder',
    blurb: 'A reminder before your church gathers.',
    keywords: ['service reminder', 'sunday service', 'church reminder', 'gathering reminder'],
    build: () => ({
      templateId: 'sunday_service_reminder',
      kind: ScheduleKind.reminder,
      rrule: 'FREQ=WEEKLY;BYDAY=SU;BYHOUR=8;BYMINUTE=0',
      humanReadable: 'Every Sunday at 8:00 AM',
      prompt:
        'Remind the person of today’s service time and theme, drawn from the ' +
        'church calendar connector. Private card only.',
      writeRisk: READ_ONLY,
      surfaces: [GrantSurface.scheduled_actions],
      // Sunday IS the Sabbath for most: this reminder is allowed to run on it.
      sabbathSuppressed: false,
      sabbathOverrideLocked: false,
      requiresConsent: false,
      blurb: 'A reminder before your church gathers.',
    }),
  },
  {
    id: 'event_follow_up',
    title: 'Event follow-up',
    blurb: 'A draft thank-you and next-step note after an event.',
    keywords: ['follow up', 'follow-up', 'event followup', 'thank you note', 'after event'],
    build: () => ({
      templateId: 'event_follow_up',
      kind: ScheduleKind.follow_up,
      rrule: 'FREQ=DAILY;COUNT=1;BYHOUR=10;BYMINUTE=0',
      humanReadable: 'Once, the morning after the event',
      prompt:
        'Draft a brief, warm follow-up for attendees of the most recent event — ' +
        'thanks, one takeaway, one next step. Produce a DRAFT for approval.',
      writeRisk: DRAFTS,
      surfaces: [GrantSurface.scheduled_actions],
      sabbathSuppressed: true,
      sabbathOverrideLocked: false,
      requiresConsent: false,
      blurb: 'A draft thank-you and next-step note after an event.',
    }),
  },
  {
    id: 'care_prayer_follow_up',
    title: 'Quietly surface prayer requests awaiting care',
    // CARE framing — NOT shaming. A PRIVATE card to the requester's circle leader,
    // WITH consent. No public "unanswered" surface. No counts. No leaderboard.
    blurb:
      'A private nudge to a circle leader when a prayer request may need a gentle ' +
      'follow-up. Shared only with consent — never public, never counted.',
    keywords: ['prayer follow', 'awaiting follow', 'care prayer', 'check on prayer', 'unanswered prayer'],
    build: () => ({
      templateId: 'care_prayer_follow_up',
      kind: ScheduleKind.follow_up,
      rrule: 'FREQ=WEEKLY;BYDAY=WE;BYHOUR=9;BYMINUTE=0',
      humanReadable: 'Every Wednesday at 9:00 AM',
      prompt:
        'For prayer requests the requester has consented to share with their circle ' +
        'leader, draft ONE private, pastoral note suggesting a gentle personal ' +
        'check-in. Frame as care. Do NOT enumerate, count, or rank requests. Do NOT ' +
        'surface anything publicly. Produce a DRAFT for the leader.',
      writeRisk: DRAFTS,
      surfaces: [GrantSurface.scheduled_actions],
      sabbathSuppressed: true,
      sabbathOverrideLocked: true,
      // Consent is non-negotiable for this template.
      requiresConsent: true,
      blurb:
        'A private nudge to a circle leader when a prayer request may need a gentle ' +
        'follow-up. Shared only with consent — never public, never counted.',
    }),
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// NL PARSER — deterministic, transparent. Matches free text to a template, then
// returns its preview. Falls back to a daily reminder so the preview is always
// a concrete, confirmable proposal (never a silent no-op).
// ─────────────────────────────────────────────────────────────────────────────

export function templateById(id: string): TemplateDef | undefined {
  return TEMPLATES.find((t) => t.id === id);
}

export function parseNaturalLanguage(text: string): ScheduledActionPreview {
  const lower = text.trim().toLowerCase();

  if (lower.length > 0) {
    for (const tpl of TEMPLATES) {
      if (tpl.keywords.some((k) => lower.includes(k))) {
        return tpl.build();
      }
    }
    // Soft heuristics for bare day/time phrasing.
    if (lower.includes('digest') || lower.includes('recap')) {
      return templateById('friday_group_digest')!.build();
    }
    if (lower.includes('reading') || lower.includes('passage')) {
      return templateById('weekly_reading_plan')!.build();
    }
    if (lower.includes('sunday') || lower.includes('service')) {
      return templateById('sunday_service_reminder')!.build();
    }
  }

  // Default: a safe, read-only daily prayer reminder.
  return templateById('daily_prayer_reminder')!.build();
}

/**
 * Promote a confirmed preview into the persisted ScheduledAction shape.
 * Every new action starts dryRun=true and status='dry_run' (spec: first N runs
 * render "would have done X" cards). aegisReviewId comes from config at write time.
 */
export function previewToAction(
  preview: ScheduledActionPreview,
  uid: string,
  aegisReviewId: string | null,
): Omit<ScheduledAction, 'id'> {
  return {
    uid,
    kind: preview.kind,
    rrule: preview.rrule,
    humanReadable: preview.humanReadable,
    prompt: preview.prompt,
    writeRisk: preview.writeRisk,
    surfaces: preview.surfaces,
    sabbathSuppressed: preview.sabbathSuppressed,
    dryRun: true,
    aegisReviewId,
    status: 'dry_run',
  };
}
