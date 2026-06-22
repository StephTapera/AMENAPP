// creatorProfileTypes.ts
// AMEN — Creator Profiles (ministry hubs: Apple Music Artist Page + Threads + Liquid Glass)
// Wave 0 FROZEN: 2026-06-18
// SOURCE OF TRUTH. Swift mirror lives at AMENAPP/AMENAPP/CreatorProfiles/CreatorProfilesContracts.swift
// — field names must match 1:1. Any change requires a contract-change note + re-freeze in WAVE0_FREEZE.md.
//
// Namespacing note: the `CreatorHub*` prefix is deliberate. The names `CreatorProfile`
// (economic-graph model, AMENAPP/CreatorProfile.swift), `CommunityPost`
// (AMENAPP/Media/AmenMediaCommunityRoomView.swift) and `PrayerRequest`
// (AMENAPP/AMENAPP/CommunityOS/Prayer/PrayerModels.swift) are ALREADY TAKEN.
// The existing `creator` codebase domain (CreatorProjectPayload, CreatorAsset, …)
// is a *video editing studio*, NOT this ministry-hub feature. Do not collide with it.
//
// Wire conventions (match Backend/functions/src/discovery/contracts.ts ↔ DiscoveryContracts.swift):
//   - All timestamps are ISO-8601 strings on the wire (Swift decodes with .iso8601).
//   - No `any` / [String:Any] escape hatches. Discriminated unions carry a `type` + `data`.
//   - Money is integer minor units (cents) + ISO-4217 currency code.

// ───────────────────────────────────────────────────────────────────────────
// MARK: Shared primitives
// ───────────────────────────────────────────────────────────────────────────

/** MEDIA-GATE / moderation lifecycle. Fail-closed: nothing is public until `approved`. */
export type CreatorHubModerationStatus =
    | "quarantined"   // MEDIA-GATE has not cleared this object yet — never servable
    | "pending"       // submitted, awaiting creator/moderator review — never public
    | "approved"      // cleared — public-readable
    | "rejected"      // denied — stays inaccessible
    | "hidden";       // approved then hidden by creator/moderator

export type CreatorHubAudienceTag = "general" | "youth" | "kids" | "mixed";

export interface CreatorHubMediaRef {
    kind: "image" | "video" | "audio";
    storagePath: string;              // gs:// path under creators/{creatorId}/… — gated by Storage rules + MEDIA-GATE
    aspectRatio?: string;             // "16:9", "1:1", …
    durationSec?: number;             // video/audio only
    moderation: CreatorHubModerationStatus;   // client refuses to render non-approved media
}

export interface CreatorHubLink {
    label: string;
    url: string;
    kind: "website" | "giving" | "youtube" | "podcast" | "social" | "app" | "other";
}

export interface CreatorHubGeo {
    latitude: number;
    longitude: number;
    locationName?: string;
}

export interface CreatorHubTicketing {
    isTicketed: boolean;
    priceCents?: number;
    currency?: string;                // ISO-4217
    url?: string;
}

/** Anti-addictive pacing. Mirrors the existing CalmCap (DiscoveryContracts.swift) field-for-field. */
export interface CreatorHubCalmCap {
    maxShelves: number;
    maxItemsPerShelf: number;
    infiniteScroll: boolean;          // ALWAYS false in v1
    sessionSoftLimitSeconds: number;
}

export const CREATOR_HUB_CALMCAP_V1: CreatorHubCalmCap = {
    maxShelves: 8,
    maxItemsPerShelf: 12,
    infiniteScroll: false,
    sessionSoftLimitSeconds: 900,
};

// ───────────────────────────────────────────────────────────────────────────
// MARK: Profile
// ───────────────────────────────────────────────────────────────────────────

export type CreatorHubBadge = "live" | "nextEvent" | "prayer" | "resource" | "verified";

export interface CreatorHubProfile {
    id: string;
    displayName: string;
    handle: string;                   // "@pastormike"
    roleLabels: string[];             // ["Pastor", "Author"]
    verified: boolean;
    heroMedia?: CreatorHubMediaRef;
    badges: CreatorHubBadge[];
    links: CreatorHubLink[];
    audienceTag: CreatorHubAudienceTag;   // COPPA-relevant; child-directed surfaces gated until counsel sign-off
    calmCapProfile: CreatorHubCalmCap;
}

// ───────────────────────────────────────────────────────────────────────────
// MARK: Events
// ───────────────────────────────────────────────────────────────────────────

export type CreatorHubEventType =
    | "sermon" | "bibleStudy" | "worshipNight" | "conference" | "class"
    | "prayerMeeting" | "livestream" | "revival" | "webinar" | "mentorship" | "smallGroup";

export type CreatorHubEventStatus = "draft" | "scheduled" | "live" | "ended" | "canceled";

export interface CreatorHubEvent {
    id: string;
    creatorId: string;
    type: CreatorHubEventType;
    title: string;
    startsAt: string;                 // ISO-8601 UTC
    timeZone: string;                 // IANA tz, e.g. "America/Chicago"
    endsAt?: string;                  // ISO-8601 UTC
    geo?: CreatorHubGeo;
    registrationUrl?: string;
    ticketing?: CreatorHubTicketing;
    livestreamRef?: string;
    capacity?: number;
    speakers: string[];               // creatorIds / user handles
    status: CreatorHubEventStatus;
}

// ───────────────────────────────────────────────────────────────────────────
// MARK: Teachings
// ───────────────────────────────────────────────────────────────────────────

export interface CreatorHubTeaching {
    id: string;
    creatorId: string;
    title: string;
    video?: CreatorHubMediaRef;
    audio?: CreatorHubMediaRef;
    transcriptRef?: string;           // ref into the transcript store; transport behind a flag (§3)
    notes?: string;
    outline: string[];
    scriptureRefs: string[];          // ["John 3:16", "Rom 8:28"]
    topics: string[];
    series?: string;
    speakers: string[];
    aiSummaryRef?: string;
    durationSec: number;
}

// ───────────────────────────────────────────────────────────────────────────
// MARK: Resources
// ───────────────────────────────────────────────────────────────────────────

export type CreatorHubResourceKind =
    | "pdf" | "book" | "worksheet" | "slides" | "devotional"
    | "readingPlan" | "studyGuide" | "course" | "link";

export interface CreatorHubResource {
    id: string;
    creatorId: string;
    kind: CreatorHubResourceKind;
    title: string;
    fileRef?: CreatorHubMediaRef;
    externalUrl?: string;
    topics: string[];
}

// ───────────────────────────────────────────────────────────────────────────
// MARK: Courses
// ───────────────────────────────────────────────────────────────────────────

export type CreatorHubProgressModel = "linear" | "freeform";

export interface CreatorHubLesson {
    id: string;
    title: string;
    teachingRef?: string;
    durationSec?: number;
}

export interface CreatorHubCourseModule {
    id: string;
    title: string;
    lessons: CreatorHubLesson[];
}

export interface CreatorHubCourse {
    id: string;
    creatorId: string;
    title: string;
    modules: CreatorHubCourseModule[];
    progressModel: CreatorHubProgressModel;
}

// ───────────────────────────────────────────────────────────────────────────
// MARK: Prayer board (moderated)
// ───────────────────────────────────────────────────────────────────────────

export interface CreatorHubPrayerRequest {
    id: string;
    creatorId: string;
    authorId: string;
    body: string;
    isPrivate: boolean;
    status: CreatorHubModerationStatus;   // forced to "pending" on create; public only when "approved" && !isPrivate
    prayedCount: number;
    praiseReport?: string;
}

// ───────────────────────────────────────────────────────────────────────────
// MARK: Community (moderated)
// ───────────────────────────────────────────────────────────────────────────

export type CreatorHubCommunityKind = "question" | "testimony" | "studyNote" | "eventDiscussion";

export interface CreatorHubCommunityPost {
    id: string;
    creatorId: string;
    authorId: string;
    kind: CreatorHubCommunityKind;
    body: string;
    parentRef?: string;               // reply threading
    status: CreatorHubModerationStatus;   // forced to "pending" on create; public only when "approved"
}

// ───────────────────────────────────────────────────────────────────────────
// MARK: Follow / subscription
// ───────────────────────────────────────────────────────────────────────────

export type CreatorHubFollowCategory =
    | "teachings" | "events" | "prayer" | "resources" | "music" | "courses" | "livestreams";

export interface CreatorHubFollow {
    userId: string;
    creatorId: string;
    categories: CreatorHubFollowCategory[];   // granular smart-follow → FCM topics
}

// ───────────────────────────────────────────────────────────────────────────
// MARK: Kingdom Metrics (derived, server-write only)
// ───────────────────────────────────────────────────────────────────────────

export interface CreatorHubMetrics {
    creatorId: string;
    peopleDiscipled: number;
    prayersReceived: number;
    prayersPrayed: number;
    answeredReports: number;
    plansCompleted: number;
    notesCreated: number;
    studySessions: number;
    groupsLaunched: number;
    resourcesDownloaded: number;
    retentionSignal: number;          // 0…1 — privacy-respecting aggregate, no per-user tracking
    communityHealthSignal: number;    // 0…1
}

// ───────────────────────────────────────────────────────────────────────────
// MARK: Assembly payload (the one round-trip — assembleCreatorProfile)
// ───────────────────────────────────────────────────────────────────────────

export type CreatorHubModuleKind =
    | "overview" | "events" | "teachings" | "resources"
    | "prayer" | "community" | "courses" | "askAI";

/** Server-resolved hero state. Discriminated union: { type, data }. */
export type CreatorHubHeroState =
    | { type: "live"; data: { event: CreatorHubEvent } }
    | { type: "nextEvent"; data: { event: CreatorHubEvent } }
    | { type: "latestTeaching"; data: { teaching: CreatorHubTeaching } }
    | { type: "prayer"; data: { openRequests: number } }
    | { type: "resource"; data: { resource: CreatorHubResource } }
    | { type: "idle"; data: Record<string, never> };

/** Server-selected featured module — "what matters right now". Discriminated union. */
export type CreatorHubFeaturedModule =
    | { type: "live"; data: { event: CreatorHubEvent } }
    | { type: "nextEvent"; data: { event: CreatorHubEvent } }
    | { type: "latestTeaching"; data: { teaching: CreatorHubTeaching } }
    | { type: "newResource"; data: { resource: CreatorHubResource } }
    | { type: "featuredCourse"; data: { course: CreatorHubCourse } };

export interface CreatorHubPillCounts {
    events: number;
    teachings: number;
    resources: number;
    prayer: number;
    community: number;
    courses: number;
}

/** First page of each module (CalmCap-bounded). Cursors feed pageCreatorModule. */
export interface CreatorHubFirstPages {
    events: CreatorHubEvent[];
    teachings: CreatorHubTeaching[];
    resources: CreatorHubResource[];
    prayer: CreatorHubPrayerRequest[];
    community: CreatorHubCommunityPost[];
    courses: CreatorHubCourse[];
    cursors: Partial<Record<CreatorHubModuleKind, string>>;   // module → next-page cursor
}

/** The single object returned by assembleCreatorProfile. One round trip → first paint. */
export interface CreatorHubProfilePayload {
    profile: CreatorHubProfile;
    heroState: CreatorHubHeroState;
    featuredModule: CreatorHubFeaturedModule | null;
    pillCounts: CreatorHubPillCounts;
    firstPages: CreatorHubFirstPages;
    calmCap: CreatorHubCalmCap;
    viewerFollows: boolean;
    assembledAt: string;              // ISO-8601 UTC
}

/** Cursor-paginated module page (pageCreatorModule). Items are the module's element type. */
export interface CreatorHubModulePage<T> {
    module: CreatorHubModuleKind;
    items: T[];
    nextCursor?: string;              // absent → end of list
}

// ───────────────────────────────────────────────────────────────────────────
// MARK: AI Creator Assistant (grounded, cited, refuse-on-unsupported)
// ───────────────────────────────────────────────────────────────────────────

export type CreatorHubCitationSource = "teaching" | "resource" | "event" | "course";

export interface CreatorHubCitation {
    sourceType: CreatorHubCitationSource;
    sourceId: string;
    path?: string;                    // e.g. resource page / outline path
    timestampSec?: number;            // teaching/audio timestamp the user can jump to
}

export interface CreatorHubAssistantQuery {
    creatorId: string;
    query: string;
    sessionId?: string;
}

export interface CreatorHubAssistantAnswer {
    answer: string;
    citations: CreatorHubCitation[];  // mandatory whenever refused === false
    refused: boolean;
    refusalReason?: string;           // populated when refused === true
}

// ───────────────────────────────────────────────────────────────────────────
// MARK: Feature-flag manifest — ALL DEFAULT OFF (Remote Config keys)
// ───────────────────────────────────────────────────────────────────────────
// Mirror keys: AMENAPP/AMENAPP/CreatorProfiles/CreatorProfilesContracts.swift (CreatorHubFlags)
// + remoteconfig.template.json (human merge step — see WAVE0_FREEZE.md).

export const CREATOR_HUB_FLAGS = {
    profilesEnabled:        "creator_profiles_enabled",
    eventsEnabled:          "creator_events_enabled",
    teachingSearchEnabled:  "creator_teaching_search_enabled",
    resourcesEnabled:       "creator_resources_enabled",
    prayerBoardEnabled:     "creator_prayer_board_enabled",
    communityEnabled:       "creator_community_enabled",
    aiAssistantEnabled:     "creator_ai_assistant_enabled",
    liveModeEnabled:        "creator_live_mode_enabled",
    supportDonationsEnabled: "creator_support_donations_enabled",
    voiceConsumptionEnabled: "creator_voice_consumption_enabled",
} as const;

export type CreatorHubFlagKey = (typeof CREATOR_HUB_FLAGS)[keyof typeof CREATOR_HUB_FLAGS];

/** Safe defaults: every flag OFF. Server functions no-op/deny when their flag is OFF. */
export const CREATOR_HUB_FLAG_DEFAULTS: Record<CreatorHubFlagKey, boolean> = {
    creator_profiles_enabled: false,
    creator_events_enabled: false,
    creator_teaching_search_enabled: false,
    creator_resources_enabled: false,
    creator_prayer_board_enabled: false,
    creator_community_enabled: false,
    creator_ai_assistant_enabled: false,
    creator_live_mode_enabled: false,
    creator_support_donations_enabled: false,
    creator_voice_consumption_enabled: false,
};
