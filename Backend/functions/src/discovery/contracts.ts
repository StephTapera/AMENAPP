// contracts.ts
// AMEN Connect Discovery Engine — TypeScript mirror of DiscoveryContracts.swift
// Wave 0 FROZEN: 2026-06-14
// Field names must match Swift side field-for-field.
// Any change requires contract-change note + re-freeze.

// ── Server-driven feed ──────────────────────────────────────────────

export interface DiscoveryFeed {
  generatedAt: string;          // ISO8601
  hero: HeroCandidate[];
  shelves: DiscoveryShelf[];    // Swift type: DiscoveryShelf (renamed to avoid SwiftUI collision)
  calmCap: CalmCap;
  feedToken: string;
}

export interface CalmCap {
  maxShelves: number;
  maxItemsPerShelf: number;
  infiniteScroll: false;        // always false v1 — client asserts this
  sessionSoftLimitSeconds: number;
}

export const CALM_CAP_V1: CalmCap = {
  maxShelves: 8,
  maxItemsPerShelf: 12,
  infiniteScroll: false,
  sessionSoftLimitSeconds: 900,
};

export interface HeroCandidate {
  id: string;
  card: DiscoveryCard;
  backgroundHint: AdaptiveBackground;
}

export interface DiscoveryShelf {
  id: string;
  kind: ShelfKind;
  title: string;
  subtitle?: string;
  style: ShelfStyle;
  items: DiscoveryCard[];
}

export type ShelfKind =
  | "liveNow"
  | "recommended"
  | "nearbyChurches"
  | "eventsThisWeek"
  | "friendsActive"
  | "trendingDiscussions"
  | "newCommunities"
  | "prayerRooms";

export type ShelfStyle = "carousel" | "featured" | "grid" | "mapBacked";

// ── Adaptive card ───────────────────────────────────────────────────

export interface DiscoveryCard {
  id: string;
  type: DiscoveryCardType;
  title: string;
  subtitle?: string;
  payload: CardPayload;
  reason: WhyShown;
  safety: SafetyStamp;          // REQUIRED — client refuses to render without this
  glassTint: GlassTint;
}

export type DiscoveryCardType =
  | "bibleStudy"
  | "prayerRoom"
  | "church"
  | "event"
  | "discussion"
  | "space"
  | "audioRoom";

// Discriminated union — type + data mirrors Swift DiscoveryCardPayload
export type CardPayload =
  | { type: "bibleStudy"; data: BibleStudyCard }
  | { type: "prayerRoom"; data: PrayerRoomCard }
  | { type: "church";     data: ChurchCard }
  | { type: "event";      data: EventCard }
  | { type: "discussion"; data: DiscussionCard }
  | { type: "space";      data: SpaceCard }
  | { type: "audioRoom";  data: AudioRoomCard };

// ── Concrete payload types ──────────────────────────────────────────

export interface BibleStudyCard {
  verseRef: string;
  passagePreview: string;
  readingProgress?: number;     // 0.0–1.0; omit if no prior engagement
}

export interface PrayerRoomCard {
  liveCount: number;
  activeRequests: number;
  speakerIds: string[];
}

export interface ChurchCard {
  serviceTimes: string[];
  denomination?: string;
  latitude: number;
  longitude: number;
  distanceMeters?: number;
}

export interface EventCard {
  startsAt: string;             // ISO8601
  rsvpState: RSVPState;
  speakerIds: string[];
}

export type RSVPState = "none" | "going" | "maybe" | "notGoing";

export interface DiscussionCard {
  replyCount: number;
  lastActivityAt: string;       // ISO8601
  topicTags: string[];
}

export interface SpaceCard {
  memberCount: number;
  growth7d: number;
  latestTopic?: string;
}

export interface AudioRoomCard {
  liveCount: number;
  speakerIds: string[];
  waveformSeed: number;
}

// ── Explainability ──────────────────────────────────────────────────

export interface WhyShown {
  kind: ReasonKind;
  detail: string;
}

export type ReasonKind =
  | "followedInterest"
  | "nearYou"
  | "friendJoined"
  | "trending"
  | "freshForYou"
  | "continueReading";

// ── Safety ──────────────────────────────────────────────────────────

export interface SafetyStamp {
  clearedBy: "GUARDIAN" | "AEGIS";
  registryVersion: string;
  clearedAt: string;            // ISO8601
}

// ── Visuals ─────────────────────────────────────────────────────────

export type AdaptiveBackground =
  | "prayerWarm"
  | "parchment"
  | "worshipGradient"
  | "eventBrand"
  | "neutral";

export interface GlassTint {
  hex: string;
  intensity: number;            // 0…1
}

// ── Search ──────────────────────────────────────────────────────────

export interface DiscoverySearchResult {
  suggested: DiscoveryCard[];
  browseShelves: DiscoveryShelf[];
  matches: DiscoveryCard[];
}

// ── Internal ranking types (not exposed to client) ──────────────────

export interface Candidate {
  id: string;
  type: DiscoveryCardType;
  sourceData: Record<string, unknown>;
  features: CandidateFeatures;
}

export interface CandidateFeatures {
  relevanceScore: number;           // 0-1 from interests/vectors
  freshnessScore: number;           // 0-1 decay function
  friendAffinityScore: number;      // 0-1 mutual-follow signal
  localProximityScore: number;      // 0-1 geohash distance
  scriptureContinuityScore: number; // 0-1 reading progress context
  formationScore?: number;          // computed by ranker; undefined pre-ranking
}

// Formation weights — explicitly zero for engagement signals
export const FORMATION_WEIGHTS = {
  relevance:           0.35,
  freshness:           0.20,
  friendAffinity:      0.20,
  localProximity:      0.15,
  scriptureContinuity: 0.10,
  // engagement (dwell, clicks, shares): FORBIDDEN — must stay 0
} as const;
