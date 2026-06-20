// contracts/communities.ts
// AMEN — Amen Communities · Wave 0 · TypeScript source of truth.
// FROZEN: 2026-06-20. Swift side (CommunitiesContracts.swift) mirrors this field-for-field
// (camelCase, matching volunteer.ts/connect.ts). Any change requires a contract-change note
// + re-freeze before parallel work resumes.
//
// WHAT THIS IS: a NEW, free (no IAP), secular+faith, topic-first joinable "Community" object.
// FOUNDER RULING (2026-06-20, Option C / hybrid): the PUBLIC model + UI here are distinct and
// tier-free, but membership/role/room operations INTERNALLY DELEGATE to the existing Covenant
// machinery (refactored tier-agnostic in Wave 1). This is NOT a second group stack — it reuses
// Covenant's join/leave/role-check code paths and routes content→existing Post system,
// moderation→GUARDIAN, share→existing DM, notifications→NotificationService.
//
// PRIVACY-ZONE convention (PRIVACY-CORE; see Docs/privacy-model.md — there is NO literal Z1–Z5
// enum, this is a tagging discipline mapped to the app's visibility/precedence model):
//   Z1 PUBLIC      — safe to expose to unauthenticated/anyone (e.g. community name, slug).
//   Z2 MEMBER      — visible to community members per visibility/joinPolicy.
//   Z3 PERSONAL    — tied to a specific user; respects their profileVisibility/account.
//   Z4 SENSITIVE   — minor-safety / location / health-adjacent; fuzzy-only, fail-closed.
//   Z5 INTERNAL    — admin/moderator-private or server-only; NEVER rendered to a member.
//
// SAFETY INVARIANTS (server-enforced in Wave 1+; client re-asserts):
//   • CI1 Health is INTERNAL — CommunityHealthSnapshot is Z5; never serialized to a member client.
//   • CI2 No vanity surfaced — memberCount/onlineCount are display counts only; NO like/follower
//          totals as status, NO public per-person leaderboards. Reputation = contribution-derived.
//   • CI3 Location is fuzzy-only — approximateRegion is a coarse label; exact GPS is never stored
//          or returned anywhere. locationMode never carries precise coordinates.
//   • CI4 Moderation is advisory + human-gated — reports/AI verdicts route into the EXISTING
//          GUARDIAN queue; nothing auto-punishes a user. "Intelligence proposes, people decide."
//   • CI5 Minor-safety fail-closed — minor↔adult interaction surfaces stay disabled until COPPA
//          sign-off; ageRating gates membership; csam_hash_scan_enabled stays permanently OFF.
//   • CI6 Recommendations are explainable — every recommendation carries a human-readable `reason`.

// ════════════════════════════════════════════════════════════════════
// §1 — Enums (modes, policies, roles)
// ════════════════════════════════════════════════════════════════════

/** Top-level discoverability of a community. Z1 (the value is public metadata). */
export type CommunityVisibility = "public" | "private" | "local" | "unlisted";

/** How a user becomes a member. "closed" = no new members. */
export type CommunityJoinPolicy = "open" | "requestToJoin" | "inviteOnly" | "closed";

/** Who may create posts. "announcement" read-only mode = leadersOnly. */
export type CommunityPostPolicy = "allMembers" | "trustedAndAbove" | "moderatorsOnly" | "leadersOnly";

/** Who may comment on community posts. */
export type CommunityCommentPolicy = "allMembers" | "membersOnly" | "moderatorsOnly" | "off";

/** External governance binding (org/school/church/creator-managed modes). "none" = self-governed. */
export type CommunityGovernance = "none" | "orgManaged" | "schoolManaged" | "churchManaged" | "creatorLed";

/** Minor-safety gate. Default "everyone". "adult" communities are unavailable to minor accounts (CI5). */
export type CommunityAgeRating = "everyone" | "teen" | "adult";

/** Location coupling. NEVER exact (CI3). "fuzzyRegion" exposes only a coarse approximateRegion. */
export type CommunityLocationMode = "none" | "fuzzyRegion";

/** Verification badge state. Z1. Display-only; does not grant capability. */
export type CommunityVerifiedStatus = "none" | "verified" | "official";

/** Member roles. Capabilities, not cosmetics. Maps onto the canonical AmenRole at the machinery layer. */
export type CommunityRole =
  | "owner"
  | "admin"
  | "moderator"
  | "trustedMember"
  | "verifiedExpert"
  | "creator"
  | "orgStaff"
  | "member"
  | "guest"
  | "limitedMember"
  | "mutedMember";

/** Membership lifecycle. */
export type CommunityMembershipStatus =
  | "active"
  | "pending"     // requestToJoin awaiting approval
  | "invited"     // invite issued, not yet accepted
  | "left"
  | "banned"
  | "limited";    // new-member posting limits / anti-raid

/** Per-member notification posture (anti-addiction: quiet is a first-class choice). */
export type CommunityNotificationLevel = "all" | "highlights" | "mentions" | "quiet";

/** How a member's membership shows on their profile (CommunityProfileSection). Z3. */
export type CommunityProfileVisibility = "showPublicly" | "followersOnly" | "hide" | "selected";

// ════════════════════════════════════════════════════════════════════
// §2 — Community  (the joinable topic group)
// ════════════════════════════════════════════════════════════════════

export interface Community {
  id: string;                              // Z1
  name: string;                            // Z1
  slug: string;                            // Z1 — unique, url-safe
  iconUrl?: string;                        // Z1
  bannerUrl?: string;                      // Z1
  description: string;                     // Z1
  category: string;                        // Z1 — e.g. "tech","design","health","family","faith"
  tags: string[];                          // Z1
  visibility: CommunityVisibility;         // Z1
  joinPolicy: CommunityJoinPolicy;         // Z1
  postPolicy: CommunityPostPolicy;         // Z2
  commentPolicy: CommunityCommentPolicy;   // Z2
  governance: CommunityGovernance;         // Z1
  ageRating: CommunityAgeRating;           // Z4 (CI5)
  locationMode: CommunityLocationMode;     // Z4 (CI3)
  approximateRegion?: string;              // Z4 — coarse label only, never coordinates (CI3)
  sensitive: boolean;                      // Z2 — support/sensitive community (extra care, anon allowed)
  anonymousPostingAllowed: boolean;        // Z2 — safe anon only where mods explicitly enable it
  ownerId: string;                         // Z1
  verifiedStatus: CommunityVerifiedStatus; // Z1
  healthScore: number;                     // Z5 — INTERNAL ONLY (CI1); never render to members
  memberCount: number;                     // Z1 — display count, not status (CI2)
  onlineCount: number;                     // Z1 — display count (CI2)
  recentPostCount: number;                 // Z1
  flairRequired: boolean;                  // Z2 — community may require flair before posting
  createdAt: number;                       // Z1 — epoch ms
  updatedAt: number;                       // Z1
  // Hybrid delegation (CI / ruling): server-only pointer to the Covenant-machinery backing this
  // community's membership/rooms. NOT a paid Covenant; tier-free. Never exposed to members.
  machineryRef?: string;                   // Z5 — INTERNAL ONLY
}

// ════════════════════════════════════════════════════════════════════
// §3 — Membership, flair, rules
// ════════════════════════════════════════════════════════════════════

export interface CommunityMembership {
  id: string;                                  // Z1 (doc id)
  communityId: string;                         // Z1
  userId: string;                              // Z3
  role: CommunityRole;                         // Z2
  status: CommunityMembershipStatus;           // Z2
  flair?: string;                              // Z2 — flairId chosen by member (moderation-safe)
  notificationLevel: CommunityNotificationLevel; // Z3
  profileVisibility: CommunityProfileVisibility;  // Z3 (CommunityProfileSection)
  joinedAt: number;                            // Z3 — epoch ms
  lastActiveAt: number;                        // Z3
}

/** A selectable flair (role badge) a community offers. Moderation-safe labels only. */
export interface CommunityFlairOption {
  id: string;                 // Z1
  communityId: string;        // Z1
  label: string;              // Z1 — e.g. "Member","Creator","Mentor","Student","Leader","Volunteer","Verified Expert"
  roleHint?: CommunityRole;   // Z2 — optional association
  custom: boolean;            // Z1 — mod-enabled custom flair
  enabled: boolean;           // Z1
}

export type CommunityRuleSeverity = "info" | "warning" | "removable" | "ban";

export interface CommunityRule {
  id: string;                       // Z1
  communityId: string;              // Z1
  title: string;                    // Z1
  description: string;              // Z1
  severity: CommunityRuleSeverity;  // Z1
  enabled: boolean;                 // Z1
  order: number;                    // Z1
}

// ════════════════════════════════════════════════════════════════════
// §4 — CommunityPost  (REUSES existing Post — never a parallel post stack)
// ════════════════════════════════════════════════════════════════════

export type CommunityPostModerationState = "visible" | "held" | "removed" | "shadowLimited";

/** Join record linking an existing platform Post to a community. `postId` FK → existing Post. */
export interface CommunityPost {
  id: string;                                  // Z1 (doc id)
  communityId: string;                         // Z1
  postId: string;                              // Z2 — FK to the existing Post; Post.communityId mirrors this
  pinned: boolean;                             // Z2
  sortScore: number;                           // Z5 — INTERNAL ranking input (health-aware, de-ranks rage-bait)
  moderationState: CommunityPostModerationState; // Z2 (advisory states; human-gated — CI4)
  createdAt: number;                           // Z1
}

// ════════════════════════════════════════════════════════════════════
// §5 — Invites
// ════════════════════════════════════════════════════════════════════

export type CommunityInviteStatus = "pending" | "accepted" | "declined" | "expired" | "revoked";

export interface CommunityInvite {
  id: string;                       // Z1
  communityId: string;              // Z1
  inviterId: string;                // Z3
  inviteeId: string;                // Z3
  status: CommunityInviteStatus;    // Z2
  createdAt: number;                // Z1
  expiresAt?: number;               // Z1
}

// ════════════════════════════════════════════════════════════════════
// §6 — Reports + moderation actions  (route into EXISTING GUARDIAN — CI4)
// ════════════════════════════════════════════════════════════════════

export type CommunityReportTargetType = "post" | "comment" | "member" | "community" | "message" | "resource" | "event";

/** Report categories the smart queue auto-prioritizes. No method-naming for self-harm anywhere. */
export type CommunityReportReason =
  | "harassment"
  | "doxxing"
  | "sexualContent"
  | "spam"
  | "scam"
  | "hate"
  | "selfHarmConcern"
  | "childSafetyRisk"
  | "impersonation"
  | "misinformationRisk"
  | "sensitiveLocationExposure"
  | "other";

export type CommunityReportStatus = "open" | "triaged" | "actioned" | "dismissed";

/** A report. Routes into the EXISTING guardianReviewQueue; never auto-acts on a user (CI4). */
export interface CommunityReport {
  id: string;                          // Z1
  communityId: string;                 // Z1
  reporterId: string;                  // Z3 (reporter identity protected from target)
  targetType: CommunityReportTargetType; // Z2
  targetId: string;                    // Z2
  reason: CommunityReportReason;       // Z2
  details?: string;                    // Z4 — free text; sanitized
  status: CommunityReportStatus;       // Z5 — moderation-private workflow state
  createdAt: number;                   // Z1
}

export type CommunityModerationActionType =
  | "warn"
  | "removePost"
  | "limitMember"
  | "muteMember"
  | "removeMember"
  | "ban"
  | "pin"
  | "unpin"
  | "lockThread"
  | "approve"
  | "dismissReport";

/** A moderator action record (audit log; ban-evasion + impersonation tracking live atop this). Z5. */
export interface CommunityModerationAction {
  id: string;                              // Z1
  communityId: string;                     // Z1
  moderatorId: string;                     // Z5 — moderator-private
  actionType: CommunityModerationActionType; // Z5
  targetType: CommunityReportTargetType;   // Z5
  targetId: string;                        // Z5
  reason: string;                          // Z5
  createdAt: number;                       // Z5
}

// ════════════════════════════════════════════════════════════════════
// §7 — Resources + Events
// ════════════════════════════════════════════════════════════════════

export type CommunityResourceType = "link" | "doc" | "video" | "playlist" | "guide" | "faq" | "starterPack" | "safetyDoc";

export interface CommunityResource {
  id: string;                       // Z1
  communityId: string;              // Z1
  type: CommunityResourceType;      // Z1
  title: string;                    // Z1
  url: string;                      // Z1
  description?: string;             // Z1
  pinned: boolean;                  // Z2
  createdBy: string;                // Z3
  createdAt: number;                // Z1
}

export type CommunityEventKind = "meetup" | "livestream" | "studySession" | "volunteerOp" | "class" | "ama" | "localEvent" | "groupCall";

/** A community event. REAL-TIME AUDIO/VIDEO (livestream/groupCall) = CONTRACT-AND-STUB ONLY in this
 *  build (the "Gather" verb-family). No WebRTC/LiveKit transport ships. url is external/fuzzy only (CI3). */
export interface CommunityEvent {
  id: string;                       // Z1
  communityId: string;              // Z1
  kind: CommunityEventKind;         // Z1
  title: string;                    // Z1
  description: string;              // Z1
  startTime: number;                // Z1 — epoch ms (UTC)
  endTime?: number;                 // Z1
  locationMode: CommunityLocationMode; // Z4 (CI3)
  approximateRegion?: string;       // Z4 — coarse only (CI3)
  url?: string;                     // Z1 — external link; NOT a live-audio transport (stub)
  hostId: string;                   // Z3
  liveAudioStub: true;              // invariant marker — live audio is stubbed/disabled this build
}

// ════════════════════════════════════════════════════════════════════
// §8 — Health + Reputation  (Z5 INTERNAL; advisory — CI1/CI2)
// ════════════════════════════════════════════════════════════════════

/** Admin/moderator-private health snapshot. NEVER serialized to a member client (CI1). Advisory only. */
export interface CommunityHealthSnapshot {
  communityId: string;              // Z5
  spamIndex: number;                // Z5
  reportRate: number;               // Z5
  modResponseTimeSec: number;       // Z5
  retentionRate: number;            // Z5
  helpfulReplyRate: number;         // Z5
  toxicityIndex: number;            // Z5
  engagementQuality: number;        // Z5
  burnoutRisk: number;              // Z5
  computedAt: number;               // Z5
}

/** Contribution-derived reputation signals — NOT popularity (CI2). Mostly admin-private; the only
 *  member-visible surface is a non-numeric "contributor"-tier label decided later, never a leaderboard. */
export type CommunityHelpfulnessSignal =
  | "helpfulReply"
  | "trustedAnswer"
  | "resourceContributor"
  | "eventHost"
  | "welcomer"
  | "moderatorVerified"
  | "conflictResolution"
  | "volunteerFulfilled";

export interface CommunityReputationEntry {
  id: string;                       // Z5 (append-only ledger row)
  communityId: string;              // Z5
  userId: string;                   // Z3
  signal: CommunityHelpfulnessSignal; // Z5
  sourceRef?: string;               // Z5 — what earned it (postId/eventId/commitmentId)
  createdAt: number;                // Z5
}

// ════════════════════════════════════════════════════════════════════
// §9 — Recommendations / Safe-Join Preview  (explainable — CI6)
// ════════════════════════════════════════════════════════════════════

/** A recommendation always carries a human-readable `reason` (CI6). score is INTERNAL. */
export interface CommunityRecommendation {
  communityId: string;              // Z1
  reason: string;                   // Z1 — e.g. "Because you follow design creators"
  score: number;                    // Z5 — INTERNAL ranking input
}

/** Shown BEFORE joining so the decision is informed. All Z1/Z2 (no internal scores). */
export interface SafeJoinPreview {
  communityId: string;              // Z1
  rulesSummary: string;             // Z1
  moderationLevel: "light" | "standard" | "strict"; // Z1
  ageRating: CommunityAgeRating;    // Z1
  visibility: CommunityVisibility;  // Z1
  whoCanSeePosts: string;           // Z1 — plain-language
  postsHitMainFeed: boolean;        // Z1
  dataVisibilityNote: string;       // Z1 — plain-language privacy note
}

// ════════════════════════════════════════════════════════════════════
// §10 — Callable request/response envelopes (§8 of the build prompt)
//        Types only — NO logic in Wave 0. Backend = Wave 1, us-east1, per-function deploy.
// ════════════════════════════════════════════════════════════════════

export interface ListCursor { cursor?: string; limit?: number; } // scalable pagination

export interface SearchCommunitiesRequest { query: string; category?: string; cursor?: string; limit?: number; }
export interface SearchCommunitiesResult { communities: Community[]; nextCursor: string | null; }

export interface TrendingCommunitiesResult { communities: Community[]; } // health-aware, de-ranks rage-bait
export interface RecommendedCommunitiesResult { recommendations: CommunityRecommendation[]; communities: Community[]; }

export interface CreateCommunityRequest {
  name: string; slug?: string; description: string; category: string; tags?: string[];
  visibility: CommunityVisibility; joinPolicy: CommunityJoinPolicy; postPolicy: CommunityPostPolicy;
  commentPolicy: CommunityCommentPolicy; governance?: CommunityGovernance; ageRating: CommunityAgeRating;
  locationMode?: CommunityLocationMode; approximateRegion?: string; sensitive?: boolean;
  anonymousPostingAllowed?: boolean; flairRequired?: boolean;
}
export interface CreateCommunityResult { community: Community; }

export interface GetCommunityRequest { id: string; }
export interface GetCommunityResult { community: Community; membership: CommunityMembership | null; safeJoinPreview: SafeJoinPreview; }

export interface PatchCommunityRequest { id: string; patch: Partial<Pick<Community,
  "name" | "description" | "category" | "tags" | "visibility" | "joinPolicy" | "postPolicy" |
  "commentPolicy" | "governance" | "ageRating" | "locationMode" | "approximateRegion" |
  "sensitive" | "anonymousPostingAllowed" | "flairRequired" | "iconUrl" | "bannerUrl">>; }
export interface PatchCommunityResult { community: Community; }

export interface JoinCommunityRequest { id: string; flair?: string; }
export interface JoinCommunityResult { membership: CommunityMembership; }

export interface RequestJoinCommunityRequest { id: string; message?: string; }
export interface RequestJoinCommunityResult { membership: CommunityMembership; } // status: "pending"

export interface LeaveCommunityRequest { id: string; }
export interface LeaveCommunityResult { ok: true; }

export interface InviteToCommunityRequest { id: string; inviteeId: string; }
export interface InviteToCommunityResult { invite: CommunityInvite; }

export interface SetCommunityFlairRequest { id: string; flair: string; }
export interface SetCommunityFlairResult { membership: CommunityMembership; }

export interface AddToProfileRequest { id: string; profileVisibility: CommunityProfileVisibility; }
export interface AddToProfileResult { membership: CommunityMembership; }
export interface RemoveFromProfileRequest { id: string; }
export interface RemoveFromProfileResult { ok: true; }

export interface CommunityFeedRequest { id: string; sort?: "top" | "latest" | "questions" | "resources" | "events"; cursor?: string; limit?: number; }
/** Feed returns the join records + their FK postIds; the client hydrates via the existing Post system. */
export interface CommunityFeedResult { items: CommunityPost[]; postIds: string[]; nextCursor: string | null; }

export interface CreateCommunityPostRequest { id: string; postId: string; asQuestion?: boolean; anonymous?: boolean; }
export interface CreateCommunityPostResult { communityPost: CommunityPost; }

export interface ReportToCommunityRequest {
  id: string; targetType: CommunityReportTargetType; targetId: string;
  reason: CommunityReportReason; details?: string;
}
export interface ReportToCommunityResult { report: CommunityReport; } // routed into GUARDIAN (CI4)

export interface GetModerationQueueRequest { id: string; cursor?: string; limit?: number; }
export interface GetModerationQueueResult { reports: CommunityReport[]; nextCursor: string | null; }

export interface ModerationActionRequest {
  id: string; actionType: CommunityModerationActionType;
  targetType: CommunityReportTargetType; targetId: string; reason: string;
}
export interface ModerationActionResult { action: CommunityModerationAction; }

export interface GetUserCommunitiesRequest { userId: string; }
export interface GetUserCommunitiesResult {
  featured: Community[]; created: Community[]; joined: Community[]; moderating: Community[];
}
