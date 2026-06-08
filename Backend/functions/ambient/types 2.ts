// types.ts — Ambient OS · TypeScript contract definitions
// FROZEN v1 · 2026-06-01
// Mirror of AmbientContracts.swift §2.1–2.5.
// Orchestrator owns. Do NOT edit. File change requests to Orchestrator.

// ─── §2.1 AmbientContext ────────────────────────────────────────────────────

export type AmbientMode = "default" | "driving" | "atChurch";

export interface PrayerRef { id: string; title: string; deepLink: string; createdAt: string; }
export interface NoteRef   { id: string; title: string; deepLink: string; editedAt: string; }
export interface ThreadRef { id: string; title: string; deepLink: string; lastMessageAt: string; }
export interface EventRef  { id: string; title: string; deepLink: string; startsAt: string; endsAt?: string; }
export interface BroadcastRef { id: string; title: string; deepLink: string; scheduledAt: string; }

export interface AmbientUser    { id: string; firstName: string; localTime: string; tz: string; }
export interface AmbientPrayer  { awaitingResponse: PrayerRef[]; openRequests: number; }
export interface AmbientNotes   { unfinished: NoteRef[]; lastEditedAt?: string; }
export interface AmbientMessages{ needingFollowUp: ThreadRef[]; unreadThreads: number; }
export interface AmbientCalendar{ today: EventRef[]; nextEvent?: EventRef; }
export interface AmbientChurch  { upcomingEvents: EventRef[]; nextService?: EventRef; }
export interface AmbientSelah   { streakDays: number; resumeAt?: { book: string; chapter: number; deepLink: string }; }
export interface AmbientArise   { upcomingBroadcasts: BroadcastRef[]; }

export interface AmbientBereanSuggestion {
  kind: "study" | "pray" | "reflect";
  label: string;
  deepLink: string;
}

export interface AmbientContext {
  generatedAt: string;       // ISO 8601
  user: AmbientUser;
  prayer: AmbientPrayer;
  notes: AmbientNotes;
  messages: AmbientMessages;
  calendar: AmbientCalendar;
  church: AmbientChurch;
  selah: AmbientSelah;
  arise: AmbientArise;
  bereanSuggestion?: AmbientBereanSuggestion;
  /** v1: set only by manual toggle | CarPlay | tagged calendar event. NO sensor inference. */
  mode: AmbientMode;
}

// ─── §2.2 AmbientSummary ────────────────────────────────────────────────────

export interface AmbientSummary {
  greetingProse: string;
  actions: PriorityAction[];
}

// ─── §2.3 PriorityAction ────────────────────────────────────────────────────

export type ActionTier   = "high" | "medium" | "low";
export type ActionSource = "prayer" | "note" | "message" | "church" | "selah" | "berean";

export interface PriorityAction {
  id: string;
  tier: ActionTier;
  title: string;
  source: ActionSource;
  deepLink: string;
  /** Present → timeline slot; absent → "Unscheduled" bucket. */
  scheduledAt?: string;      // ISO 8601
}

// ─── §2.5 SmartComposerIntent ───────────────────────────────────────────────

export type ComposerChip    = "photo" | "churchNote" | "event" | "prayerRequest" | "sermon" | "scripture";
export type ComposerPostType= "PrayerRequest" | "Testimony" | "ChurchNote";

export interface SmartComposerIntent {
  chips: ComposerChip[];
  postType?: ComposerPostType;
}
