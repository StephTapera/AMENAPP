// church.ts — Find a Church v2 data contracts (SOURCE OF TRUTH)
//
// Wave 0 contract freeze per FIND_CHURCH_V2_SPEC.md §2–§4.
// Swift mirrors these EXACTLY (Codable, identical field names, camelCase).
// Any code that disagrees with this file is wrong, not the reverse.
//
// Region: us-east1. Project: amen-5e359.
// Nothing here is wired to a function body yet — contracts only.

// ---------------------------------------------------------------------------
// shared
// ---------------------------------------------------------------------------

export type Denomination =
  | "non_denominational" | "baptist" | "methodist" | "presbyterian"
  | "lutheran" | "pentecostal" | "catholic" | "orthodox" | "anglican"
  | "reformed" | "anabaptist" | "bible_church" | "other";

export interface GeoPointH {
  lat: number;
  lng: number;
  geohash: string;        // geofire-common encodeGeohash(), precision 9
}

export type WorshipStyle = "traditional" | "contemporary" | "blended" | "liturgical";

// ---------------------------------------------------------------------------
// service times — churches/{churchId}/serviceTimes/{id}
// ---------------------------------------------------------------------------

export interface ServiceTime {
  id: string;
  dayOfWeek: 0 | 1 | 2 | 3 | 4 | 5 | 6;   // 0 = Sunday
  startLocal: string;            // "10:30" 24h
  durationMinutes: number;
  timezone: string;              // IANA, e.g. "America/Chicago"
  language: string;              // ISO-639-1, e.g. "en","es"
  style?: WorshipStyle;
  isOnline: boolean;
  livestreamUrl?: string | null;
  childCheckIn: boolean;
}

// ---------------------------------------------------------------------------
// safety (first-class)
// ---------------------------------------------------------------------------

export interface ChurchSafety {
  hasChildSafetyPolicy: boolean;
  childSafetyPolicyUrl?: string | null;
  backgroundCheckPolicy: "all_volunteers" | "child_facing" | "none" | "unspecified";
}

export interface ChurchAccessibility {
  wheelchair: boolean;
  hearingLoop: boolean;
  aslInterpreted: boolean;
  parking: "lot" | "street" | "garage" | "none" | "unspecified";
}

export type VerificationStatus = "unverified" | "pending" | "verified" | "rejected";
export type ReportState = "clear" | "under_review" | "restricted";

// ---------------------------------------------------------------------------
// core doc — churches/{churchId}
// ---------------------------------------------------------------------------

export interface Church {
  id: string;
  name: string;
  denomination: Denomination;
  bio?: string;
  statementOfFaithUrl?: string | null;

  location: GeoPointH;
  address: { line1: string; city: string; region: string; postal: string; country: string };
  approxLocationOnly: boolean;   // if true, never expose exact lat/lng to clients; snap to ~1km

  // media — EVERY ref MUST have passed MEDIA-GATE before becoming non-null/visible
  heroMediaRef?: string | null;          // storage path; gated
  heroMediaState: "none" | "pending_gate" | "approved" | "blocked";

  ministries: string[];          // controlled vocab below (Ministry)
  languages: string[];
  accessibility: ChurchAccessibility;
  safety: ChurchSafety;

  verification: {
    status: VerificationStatus;
    method?: "domain" | "doc" | "manual" | null;
    verifiedAt?: number | null;   // epoch ms; SERVER-ONLY writable
  };
  reportState: ReportState;       // SERVER/moderator-only writable

  profileCompleteness: number;    // 0..1, computed server-side
  followerCount: number;          // honest count, not inflated

  websiteUrl?: string | null;
  socialLinks?: Record<string, string>;
  givingUrl?: string | null;
  contactEmail?: string | null;   // org contact, never a user PII surface

  createdAt: number;
  updatedAt: number;
}

// Controlled vocabulary for Church.ministries[] and the 'ministries' subcollection key.
export type MinistryKey =
  | "kids" | "youth" | "young_adults" | "mens" | "womens"
  | "recovery" | "prayer" | "worship" | "counseling" | "spanish";

// ---------------------------------------------------------------------------
// subcollections (defined here in the same freeze commit — spec §2 tail)
// ---------------------------------------------------------------------------

// churches/{churchId}/ministries/{id}
export interface Ministry {
  id: string;
  key: MinistryKey;
  title: string;
  description?: string;
  ageRange?: string | null;       // e.g. "0-5", "12-18"
  meetsLabel?: string | null;     // e.g. "Sundays 9:00 AM"
  contactEmail?: string | null;   // org contact, never user PII
}

// churches/{churchId}/smallGroups/{id}
export interface SmallGroup {
  id: string;
  churchId: string;
  title: string;
  type: string;                   // "bible_study","mens","womens","recovery","prayer", ...
  description?: string;
  meetsLabel: string;             // "Wednesdays 7:00 PM"
  location?: GeoPointH | null;    // may be off-campus; coarsened like churches
  isOnline: boolean;
  language: string;
  childFriendly: boolean;
  createdAt: number;
  updatedAt: number;
}

// churches/{churchId}/events/{id}
export interface ChurchEvent {
  id: string;
  churchId: string;
  title: string;
  description?: string;
  kind: string;                   // "service","worship_night","conference","outreach", ...
  startsAtIso: string;            // ISO-8601 with tz offset
  endsAtIso?: string | null;
  location?: GeoPointH | null;
  isOnline: boolean;
  registrationUrl?: string | null;
  createdAt: number;
  updatedAt: number;
}

// churches/{churchId}/sermons/{id}
export interface Sermon {
  id: string;
  churchId: string;
  title: string;
  speaker?: string | null;
  series?: string | null;
  scriptureRefs: string[];
  datePreachedIso?: string | null;
  // media is gated like all church UGC
  thumbnailMediaRef?: string | null;
  thumbnailMediaState: "none" | "pending_gate" | "approved" | "blocked";
  audioUrl?: string | null;
  videoUrl?: string | null;
  createdAt: number;
  updatedAt: number;
}

// churches/{churchId}/admins/{uid}
export type ChurchAdminRole = "owner" | "pastor" | "executive_admin" | "editor";
export interface ChurchAdmin {
  uid: string;
  churchId: string;
  role: ChurchAdminRole;
  addedAt: number;
}

// ---------------------------------------------------------------------------
// user-owned subdocs (users/{uid}/...) — owner-only
// ---------------------------------------------------------------------------

// users/{uid}/savedChurches/{churchId}
export interface SavedChurch {
  churchId: string;
  savedAt: number;
}

// users/{uid}/churchSearchHistory/{id}
export interface ChurchSearchHistoryEntry {
  id: string;
  term: string;
  resultChurchId?: string | null;
  searchedAt: number;
}

// users/{uid}/churchPreferences (singleton)
export interface ChurchPreferences {
  denominations: Denomination[];
  ministries: MinistryKey[];
  languages: string[];
  worshipStyles: WorshipStyle[];
  accessibilityNeeds: {
    wheelchair: boolean;
    hearingLoop: boolean;
    aslInterpreted: boolean;
  };
  privateSearch: boolean;         // when true, recordChurchSearch writes nothing
  updatedAt: number;
}

// users/{uid}/visitPlans/{id} — PRIVATE by default; mirrored only per §5.3
export interface VisitPlan {
  id: string;
  churchId: string;
  serviceTimeId?: string | null;
  plannedForIso: string;          // ISO-8601 with tz offset
  partySize?: number | null;
  notes?: string | null;
  sharedWithChurch: boolean;      // ALWAYS false for minors; see §5.2
  createdAt: number;
  updatedAt: number;
}

// churches/{churchId}/visitorIntents/{id}
// WRITTEN ONLY BY THE planVisit CLOUD FUNCTION. Client writes are denied in rules.
// Only created when: church verified AND user opt-in AND non-minor (§5.3).
// NEVER contains minor identity/contact/intent (§5.2).
export interface VisitorIntent {
  id: string;
  visitPlanId: string;
  // intentionally coarse — no exact location, no minor PII ever
  plannedForIso: string;
  partySize?: number | null;
  createdAt: number;
}

// ---------------------------------------------------------------------------
// reports & verification requests
// ---------------------------------------------------------------------------

export type ReportReason =
  | "misleading_profile" | "impersonation" | "child_safety_concern"
  | "inappropriate_media" | "spam" | "other";

// churchReports/{id} — create by any authed user; read/update moderators only
export interface ChurchReport {
  id: string;
  churchId: string;
  reporterUid: string;            // SERVER-resolved from auth, never client-supplied
  reason: ReportReason;
  details?: string | null;
  // child_safety_concern follows the ABSOLUTE-STOP escalation path, not the normal queue
  state: "open" | "escalated" | "actioned" | "dismissed";
  createdAt: number;
}

// churchVerificationRequests/{id} — create by claiming admin; read by self + moderators
export interface ChurchVerificationRequestDoc {
  id: string;
  churchId: string;
  requesterUid: string;           // SERVER-resolved
  method: "domain" | "doc" | "manual";
  evidenceUrl?: string | null;
  status: VerificationStatus;     // server-managed
  createdAt: number;
}

// ---------------------------------------------------------------------------
// discovery request/response (the brain)
// ---------------------------------------------------------------------------

export interface ChurchFilter {
  key:
    | "near_me" | "open_sunday" | "service_today" | "kids" | "youth"
    | "young_adults" | "small_groups" | "bible_study" | "worship_night"
    | "online_service" | "denomination" | "non_denominational" | "verified"
    | "accessible" | "spanish_service" | "live_stream" | "counseling"
    | "parking" | "events";
  value?: string;                 // e.g. denomination value when key==='denomination'
}

export interface ChurchDiscoveryRequest {
  center: { lat: number; lng: number };
  radiusMeters: number;           // clamp server-side to [1000, 80000]
  filters: ChurchFilter[];
  nowIso: string;                 // client clock, for "today/soon"; server still validates
  sessionId: string;
  // user identity, preferences, isMinor resolved SERVER-SIDE from auth — never trusted from client
}

export interface ChurchMatch {
  churchId: string;
  distanceMeters: number;         // already coarsened if approxLocationOnly
  score: number;
  whyMatched: string[];           // human-readable transparent reasons, max 3
  nextService?: { serviceTimeId: string; startsInMinutes: number; isOnline: boolean } | null;
  openNow: boolean;
  verified: boolean;
  badges: ("verified" | "kids_safe_policy" | "accessible" | "spanish" | "livestream" | "new")[];
}

export interface GuideCard {
  id: string;
  title: string;                  // "Churches With Wednesday Night Bible Study"
  subtitle?: string;
  coverMediaRef?: string | null;  // gated
  churchIds: string[];
  source: "editorial" | "algorithmic";
}

export interface SmallGroupMatch {
  groupId: string;
  churchId: string;
  title: string;
  type: string;
  distanceMeters: number;
  meetsLabel: string;
}

export interface EventMatch {
  eventId: string;
  churchId: string;
  title: string;
  startsAtIso: string;
  distanceMeters: number;
  kind: string;
}

export type DiscoverySection =
  | { kind: "nearby"; items: ChurchMatch[] }
  | { kind: "services_today"; items: ChurchMatch[] }
  | { kind: "suggested"; items: ChurchMatch[] }
  | { kind: "small_groups"; items: SmallGroupMatch[] }
  | { kind: "events"; items: EventMatch[] }
  | { kind: "guides"; items: GuideCard[] };

export interface ChurchDiscoveryResponse {
  contextChip: { dayLabel: string; soonCount: number; radiusLabel: string } | null;
  sections: DiscoverySection[];
  calmCap: { maxItemsPerSection: number; infiniteScroll: false };
}

// ---------------------------------------------------------------------------
// callable request/response shapes — spec §3
// ---------------------------------------------------------------------------

export interface SearchChurchesRequest {
  q: string;
  center: { lat: number; lng: number };
  radiusMeters: number;
  filters: ChurchFilter[];
  page: number;
}

export interface SearchChurchesResponse {
  items: ChurchMatch[];
  nextPage: number | null;
}

// getChurchProfile — hydrated profile
export interface ChurchProfile {
  church: Church;
  serviceTimes: ServiceTime[];
  ministries: Ministry[];
  upcomingEvents: ChurchEvent[];
  sermons: Sermon[];
}

export interface PlanVisitRequest {
  churchId: string;
  serviceTimeId?: string | null;
  plannedForIso: string;
  partySize?: number | null;
  notes?: string | null;
  shareWithChurch: boolean;       // honored only if church verified AND non-minor (§5.3)
}

export interface PlanVisitResponse {
  visitPlanId: string;
  sharedWithChurch: boolean;
}

export interface ChurchVerificationRequest {
  churchId: string;
  method: "domain" | "doc" | "manual";
  evidenceUrl?: string | null;
}

export interface ChurchClaimRequest {
  churchId?: string | null;       // null when claiming a not-yet-listed church
  proposedName?: string | null;
  role: ChurchAdminRole;
  contactEmail: string;
  evidenceUrl?: string | null;
}
