// contracts/connect.ts
// AMEN Connect V1 — Church Intelligence Layer · TypeScript mirror (source of truth).
// Wave 0 FROZEN: 2026-06-18. Spec authority: AMEN_CONNECT_V1_SPEC.md.
// Swift side (ConnectContracts.swift) must mirror these field-for-field.
// Any change requires a contract-change note + re-freeze before parallel work resumes.
//
// TOPOLOGY NOTE: Connect deploys under the `creator` codebase (Backend/functions/),
// alongside the sibling engine it mirrors (discovery/assembleDiscoveryFeed.ts) and the
// existing amenConnect.ts. The spec's literal `functions/src/contracts/connect.ts`
// resolves to THIS path per the repo's actual deploy topology (CLAUDE.md §Backend).
//
// SAFETY INVARIANTS (spec §5 — enforced server-side in-function, re-asserted in rules):
//   • No NextAction/section/card ever carries another member's data.
//   • A minor's PII is guardian-only — never to a non-guardian, never individual-granularity
//     in any analytics/dashboard/pulse/matchmaking.
//   • Child reads require an ACTIVE verified guardian link to that specific child.
//   • Uploaded media is MEDIA-GATE fail-closed (mediaRef null until approved).
//   • CalmCap: no guilt mechanics, no streaks, no FOMO, no engine-spawned re-engagement.

// ════════════════════════════════════════════════════════════════════
// §3 — CHURCH INTELLIGENCE LAYER · assembleConnectHome (V1 spine)
// ════════════════════════════════════════════════════════════════════

export type NextActionKind =
  | "attend_service"
  | "check_in_kids"
  | "join_group"
  | "rsvp_event"
  | "volunteer"
  | "watch_sermon"
  | "follow_up_prayer"
  | "read_resource"
  | "connect_person"
  | "complete_profile"
  | "plan_visit";

export interface NextAction {
  id: string;
  kind: NextActionKind;
  title: string;                 // "Men's Bible Study tonight"
  subtitle?: string;             // "7:00 PM · Building B"
  whyShown: string[];            // transparent reasons, max 3
  priority: number;              // server-ranked
  primaryActionLabel: string;    // "RSVP" | "Check In" | "Join" | "Pray"
  deepLink: string;              // amen:// route
  startsInMinutes?: number | null;
  mediaRef?: string | null;      // MEDIA-GATE; null until approved
  // INVARIANT: never carries another member's data; never a minor's PII to a non-guardian.
}

export interface ConnectHomeRequest {
  churchId: string;              // the member's own church
  nowIso: string;
  sessionId: string;
}

export interface PrayerUpdate {
  requestId: string;
  title: string;
  status: "active" | "answered";
  followerCount: number;
  authorIsMinor: boolean;        // gate: minor-authored requests never surface author PII
  answeredAt?: string | null;    // ISO8601
}

export interface SermonRef {
  id: string;
  title: string;
  series?: string;
  lengthMinutes?: number;
  topic?: string;
  mediaRef?: string | null;      // MEDIA-GATE; null until approved
}

export interface VolunteerNeed {
  id: string;
  ministryName: string;
  role: string;
  meets: string;                 // human-readable cadence
  // Pastoral framing, opt-in. Burnout-flagged members are excluded upstream (§8).
}

export interface ResourceRef {
  id: string;
  kind: "sermon" | "course" | "devotional" | "pdf";
  title: string;
  topic?: string;
  reason?: string;               // "based on your prayer about anxiety"
  mediaRef?: string | null;      // MEDIA-GATE; null until approved
}

export type ConnectSection =
  | { kind: "prayer_updates"; items: PrayerUpdate[] }
  | { kind: "new_sermon"; items: SermonRef[] }
  | { kind: "volunteer_needs"; items: VolunteerNeed[] }   // pastoral framing, opt-in
  | { kind: "for_you_resources"; items: ResourceRef[] };

// CalmCap shape for the intelligence layer (distinct from discovery CalmCap).
export interface ConnectCalmCap {
  maxActions: number;
  infiniteScroll: false;         // always false v1 — client asserts this
  guiltMechanics: false;         // always false — pastoral, not extractive
}

export interface ConnectHomeResponse {
  greeting: { name: string; dayLabel: string };           // "Good Morning, Steph"
  upNext: NextAction[];                                    // capped by calmCap.maxActions
  sections: ConnectSection[];
  calmCap: ConnectCalmCap;
}

export const CONNECT_CALM_CAP_V1: ConnectCalmCap = {
  maxActions: 5,
  infiniteScroll: false,
  guiltMechanics: false,
};

// Ranking inputs — documented, auditable weights (spec §3). Sibling of FORMATION_WEIGHTS.
// Engagement signals (dwell, clicks, opens, retention) are FORBIDDEN and must stay 0.
// "groupInactivity" is PASTORAL (gentle re-invitation), never punitive/guilt.
export const CONNECT_RANKING_WEIGHTS = {
  serviceEventSoonness:    0.28,  // imminent service/event the member can act on
  lifeStageMinistryFit:    0.22,  // life-stage + ministry match
  priorParticipation:      0.18,  // what they've already engaged with
  prayerFollowupDue:       0.16,  // follow-ups they asked to track
  unfinishedProfile:       0.08,  // gentle completion nudge
  groupInactivityPastoral: 0.08,  // pastoral re-invitation, NOT "you haven't served in 3 weeks"
  // engagement (dwell, clicks, opens, retention): FORBIDDEN — must stay 0
} as const;

// ════════════════════════════════════════════════════════════════════
// §4 — AI CHURCH CONCIERGE · askChurchConcierge (V1)
// ════════════════════════════════════════════════════════════════════

export interface ConciergeRequest {
  churchId: string;
  query: string;                 // "Where do I drop off my kids Sunday?"
  childContextId?: string;       // honored ONLY if requester is a verified guardian of that child
}

export interface ConciergeFact {
  label: string;
  value: string;
  status?: "ok" | "warn";
}

export interface ConciergeAction {
  label: string;
  deepLink: string;
}

export interface ConciergeCard {
  title: string;                 // "Kids Check-In"
  summary: string;               // "Check-in opens 9:30 AM in Building B…"
  facts: ConciergeFact[];
  actions?: ConciergeAction[];
  sources: string[];             // record IDs that answered — REQUIRED, no hallucinated facts
  // HARD RULES: refuses other-member queries; never reveals a minor's data to a non-guardian;
  // child facts only when childContextId resolves to a verified guardian link;
  // allergy/medical flags are guardian-only and NEVER logged to analytics.
}

// ════════════════════════════════════════════════════════════════════
// §7 — OTHER V1 CALLABLE SIGNATURES (request/response shapes)
// ════════════════════════════════════════════════════════════════════

export interface MinistryRec {
  id: string;
  name: string;
  meets: string;
  openSpots?: number;
  lifeStage?: string;
  leaderAvatarRef?: string | null; // MEDIA-GATE; null until approved
  whyShown: string[];
}

export interface RecommendMinistriesRequest {
  churchId: string;
  lifeStageAnswers?: Record<string, string>;
}

export type VisitPhase = "before" | "day_of" | "after";

export interface VisitAssistantCard {
  phase: VisitPhase;
  title: string;
  steps: Array<{
    id: string;
    label: string;
    detail?: string;
    deepLink?: string;
    guardianGated: boolean;        // child-related steps render only to a verified guardian
  }>;
}

export interface VisitAssistantRequest {
  churchId: string;
  phase: VisitPhase;
  serviceTimeId?: string;
}

export interface PrayerFollowRequest {
  requestId: string;
  follow: boolean;
}

export interface MarkPrayerAnsweredRequest {
  requestId: string;
  testimony?: string;
}

export interface ForYouResourcesRequest {
  churchId: string;
  seed?: "prayer" | "sermon" | "topic";
  topic?: string;
}

// ════════════════════════════════════════════════════════════════════
// §5.1 — VERIFIED GUARDIAN LINK PRIMITIVE (build first; safety foundation)
// ════════════════════════════════════════════════════════════════════

// State machine: pending → verified | revoked. Only `verified` unlocks any child read.
// Transitions are server-only; the client may never write `status`/`verifiedAt`.
export type GuardianLinkStatus = "pending" | "verified" | "revoked";

// Evidence for a guardian claim. The actual verification policy (which evidence is
// sufficient) is enforced server-side and is intentionally NOT client-trusted.
export interface GuardianEvidence {
  kind: "staff_attested" | "pickup_code" | "invite_acceptance";
  // staff_attested  → a verified church admin/staff vouches for the relationship
  // pickup_code     → guardian presents the child's numeric pickup-authorization code (§5.3)
  // invite_acceptance → child/co-guardian account accepts a guardian invite
  reference?: string;            // opaque server-resolved reference (e.g. inviteId, attestationId)
}

export interface GuardianLink {
  id: string;
  churchId: string;
  guardianUid: string;
  childId: string;
  status: GuardianLinkStatus;    // SERVER-ONLY
  verifiedAt?: string | null;    // ISO8601 — SERVER-ONLY
  createdAt: string;             // ISO8601
}

export interface RequestGuardianLinkRequest {
  churchId: string;
  childId: string;
  evidence: GuardianEvidence;
}

export interface RequestGuardianLinkResponse {
  linkId: string;
  status: "pending";             // requestGuardianLink always returns pending; verification is async/server
}

// Child reads ONLY via a guardian-verified function. 403 unless an ACTIVE verified link exists.
export interface GetChildCheckInStatusRequest {
  childId: string;
}

export interface ChildStatus {
  childId: string;
  checkedIn: boolean;
  ageGroup?: string;             // guardian-only
  building?: string;             // guardian-only
  pickupCode?: string;           // guardian-only; access-control-grade
  // allergies/medical are SENSITIVE — returned only to a verified guardian, never logged.
  allergies?: string[];
}

// ════════════════════════════════════════════════════════════════════
// §6 — DATA MODEL (V1 core) · server-authoritative field markers
// ════════════════════════════════════════════════════════════════════

// members/{churchId}_{uid}
export interface MemberRecord {
  churchId: string;
  uid: string;
  roles: string[];               // SERVER-ONLY (custom-claim mirrored)
  lifeStage?: string;
  joinedAt: string;              // ISO8601
}

// children/{churchId}_{childId} — guardian-only reads, never client-readable except via verified fn
export interface ChildRecord {
  churchId: string;
  childId: string;
  ageGroup: string;
  allergies: string[];           // SENSITIVE PII — guardian-only
  emergencyContacts: string[];   // operational, need-to-know
}

// prayerRequests/{id}
export type PrayerScope = "private" | "group" | "church";
export interface PrayerRequestRecord {
  id: string;
  scope: PrayerScope;
  authorIsMinor: boolean;
  followers: string[];
  answered: boolean;             // SERVER-ONLY (verified via markPrayerAnswered)
  answeredAt?: string | null;    // ISO8601 — SERVER-ONLY
}

// checkIns/{churchId}/{sessionId}/{childId} — operational, minimal retention, never client-readable
export interface CheckInRecord {
  churchId: string;
  sessionId: string;
  childId: string;
  pickupCode: string;            // numeric pickup-authorization code (§5.3)
  authorizedPickup: string[];    // authorized-guardian list; access-control-grade
}
