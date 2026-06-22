// Ambient OS contract definitions.
// FROZEN v1. Mirrors AMENAPP/AmbientOS/AmbientContracts.swift.

export type AmbientMode = "default" | "driving" | "atChurch";

export interface PrayerRef {
    id: string;
    title: string;
    deepLink: string;
    createdAt: string;
}

export interface NoteRef {
    id: string;
    title: string;
    deepLink: string;
    editedAt: string;
}

export interface ThreadRef {
    id: string;
    title: string;
    deepLink: string;
    lastMessageAt: string;
}

export interface EventRef {
    id: string;
    title: string;
    deepLink: string;
    startsAt: string;
    endsAt?: string;
}

export interface BroadcastRef {
    id: string;
    title: string;
    deepLink: string;
    scheduledAt: string;
}

export interface AmbientUser {
    id: string;
    firstName: string;
    localTime: string;
    tz: string;
}

export interface AmbientPrayer {
    awaitingResponse: PrayerRef[];
    openRequests: number;
}

export interface AmbientNotes {
    unfinished: NoteRef[];
    lastEditedAt?: string;
}

export interface AmbientMessages {
    needingFollowUp: ThreadRef[];
    unreadThreads: number;
}

export interface AmbientCalendar {
    today: EventRef[];
    nextEvent?: EventRef;
}

export interface AmbientChurch {
    upcomingEvents: EventRef[];
    nextService?: EventRef;
}

export interface AmbientSelah {
    streakDays: number;
    resumeAt?: {
        book: string;
        chapter: number;
        deepLink: string;
    };
}

export interface AmbientArise {
    upcomingBroadcasts: BroadcastRef[];
}

export interface AmbientBereanSuggestion {
    kind: "study" | "pray" | "reflect";
    label: string;
    deepLink: string;
}

export interface AmbientContext {
    generatedAt: string;
    user: AmbientUser;
    prayer: AmbientPrayer;
    notes: AmbientNotes;
    messages: AmbientMessages;
    calendar: AmbientCalendar;
    church: AmbientChurch;
    selah: AmbientSelah;
    arise: AmbientArise;
    bereanSuggestion?: AmbientBereanSuggestion;
    /** v1 is explicit-signal only: manual toggle, CarPlay, or at-church calendar tag. */
    mode: AmbientMode;
}

export interface AmbientSummary {
    greetingProse: string;
    actions: PriorityAction[];
}

export type ActionTier = "high" | "medium" | "low";
export type ActionSource = "prayer" | "note" | "message" | "church" | "selah" | "berean";

export interface PriorityAction {
    id: string;
    tier: ActionTier;
    title: string;
    source: ActionSource;
    deepLink: string;
    scheduledAt?: string;
}

export type ComposerChip = "photo" | "churchNote" | "event" | "prayerRequest" | "sermon" | "scripture";
export type ComposerPostType = "PrayerRequest" | "Testimony" | "ChurchNote";

export interface SmartComposerIntent {
    chips: ComposerChip[];
    postType?: ComposerPostType;
}
