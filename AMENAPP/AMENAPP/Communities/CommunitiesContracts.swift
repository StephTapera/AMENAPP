//  CommunitiesContracts.swift
//  AMEN — Amen Communities · Wave 0 · Swift mirror of Backend/functions/src/contracts/communities.ts
//
//  AIL convention: TypeScript is the source of truth. This file MIRRORS communities.ts field-for-field
//  (camelCase fields). Type NAMES are namespaced under `CommunityKit` to avoid collisions with existing
//  ad-hoc structs in the app target (CommunityPost / CommunityEvent / CommunityResource /
//  CommunityHealthSnapshot already exist as view-local types). Field names still mirror the TS exactly.
//  TS interface → Swift type mapping: Community→CommunityKit.Community, CommunityMembership→.Membership,
//  CommunityPost→.Post, CommunityEvent→.Event, etc. Do NOT change a type/field without changing the TS
//  and re-freezing.
//
//  FOUNDER RULING (2026-06-20, hybrid): a NEW free/secular/faith topic-first Community. Public model is
//  tier-free; membership/role/room ops internally delegate to existing Covenant machinery (Wave 1).
//  Reuses existing Post / GUARDIAN / glass / DM / NotificationService — never a parallel stack.
//
//  PRIVACY-CORE zone tags (Z1 PUBLIC · Z2 MEMBER · Z3 PERSONAL · Z4 SENSITIVE · Z5 INTERNAL).
//  Optional properties use synthesized Codable (missing key → nil; decode-if-present) so Firestore-
//  decoded objects don't go inert when a field is absent.

import Foundation

/// Caseless-enum namespace for the Amen Communities Wave 0 contract layer.
enum CommunityKit {

    // MARK: - §1 Enums (modes, policies, roles)

    enum Visibility: String, Codable, CaseIterable, Sendable {
        case `public`, `private`, local, unlisted
    }

    enum JoinPolicy: String, Codable, CaseIterable, Sendable {
        case open, requestToJoin, inviteOnly, closed
    }

    enum PostPolicy: String, Codable, CaseIterable, Sendable {
        case allMembers, trustedAndAbove, moderatorsOnly, leadersOnly
    }

    enum CommentPolicy: String, Codable, CaseIterable, Sendable {
        case allMembers, membersOnly, moderatorsOnly, off
    }

    enum Governance: String, Codable, CaseIterable, Sendable {
        case none, orgManaged, schoolManaged, churchManaged, creatorLed
    }

    enum AgeRating: String, Codable, CaseIterable, Sendable {
        case everyone, teen, adult
    }

    enum LocationMode: String, Codable, CaseIterable, Sendable {
        case none, fuzzyRegion
    }

    enum VerifiedStatus: String, Codable, CaseIterable, Sendable {
        case none, verified, official
    }

    enum Role: String, Codable, CaseIterable, Sendable {
        case owner, admin, moderator, trustedMember, verifiedExpert, creator
        case orgStaff, member, guest, limitedMember, mutedMember
    }

    enum MembershipStatus: String, Codable, CaseIterable, Sendable {
        case active, pending, invited, left, banned, limited
    }

    enum NotificationLevel: String, Codable, CaseIterable, Sendable {
        case all, highlights, mentions, quiet
    }

    enum ProfileVisibility: String, Codable, CaseIterable, Sendable {
        case showPublicly, followersOnly, hide, selected
    }

    // MARK: - §2 Community

    struct Community: Codable, Identifiable, Equatable, Sendable {
        let id: String                  // Z1
        var name: String                // Z1
        var slug: String                // Z1
        var iconUrl: String?            // Z1
        var bannerUrl: String?          // Z1
        var description: String         // Z1
        var category: String            // Z1
        var tags: [String]              // Z1
        var visibility: Visibility      // Z1
        var joinPolicy: JoinPolicy      // Z1
        var postPolicy: PostPolicy      // Z2
        var commentPolicy: CommentPolicy // Z2
        var governance: Governance      // Z1
        var ageRating: AgeRating        // Z4
        var locationMode: LocationMode  // Z4
        var approximateRegion: String?  // Z4 — coarse only, never coordinates (CI3)
        var sensitive: Bool             // Z2
        var anonymousPostingAllowed: Bool // Z2
        var ownerId: String             // Z1
        var verifiedStatus: VerifiedStatus // Z1
        var healthScore: Double         // Z5 — INTERNAL ONLY (CI1)
        var memberCount: Int            // Z1 — display count, not status (CI2)
        var onlineCount: Int            // Z1
        var recentPostCount: Int        // Z1
        var flairRequired: Bool         // Z2
        var createdAt: Double           // Z1 — epoch ms
        var updatedAt: Double           // Z1
        var machineryRef: String?       // Z5 — INTERNAL ONLY (Covenant-machinery backing)
    }

    // MARK: - §3 Membership, flair, rules

    struct Membership: Codable, Identifiable, Equatable, Sendable {
        let id: String                          // Z1
        var communityId: String                 // Z1
        var userId: String                      // Z3
        var role: Role                          // Z2
        var status: MembershipStatus            // Z2
        var flair: String?                      // Z2
        var notificationLevel: NotificationLevel // Z3
        var profileVisibility: ProfileVisibility // Z3
        var joinedAt: Double                    // Z3 — epoch ms
        var lastActiveAt: Double                // Z3
    }

    struct FlairOption: Codable, Identifiable, Equatable, Sendable {
        let id: String          // Z1
        var communityId: String // Z1
        var label: String       // Z1
        var roleHint: Role?     // Z2
        var custom: Bool        // Z1
        var enabled: Bool       // Z1
    }

    enum RuleSeverity: String, Codable, CaseIterable, Sendable {
        case info, warning, removable, ban
    }

    struct Rule: Codable, Identifiable, Equatable, Sendable {
        let id: String              // Z1
        var communityId: String     // Z1
        var title: String           // Z1
        var description: String     // Z1
        var severity: RuleSeverity  // Z1
        var enabled: Bool           // Z1
        var order: Int              // Z1
    }

    // MARK: - §4 Post (reuses existing platform Post via FK postId)

    enum PostModerationState: String, Codable, CaseIterable, Sendable {
        case visible, held, removed, shadowLimited
    }

    struct Post: Codable, Identifiable, Equatable, Sendable {
        let id: String                          // Z1
        var communityId: String                 // Z1
        var postId: String                      // Z2 — FK to existing Post
        var pinned: Bool                        // Z2
        var sortScore: Double                   // Z5 — INTERNAL ranking input
        var moderationState: PostModerationState // Z2 (advisory; human-gated — CI4)
        var createdAt: Double                   // Z1
    }

    // MARK: - §5 Invites

    enum InviteStatus: String, Codable, CaseIterable, Sendable {
        case pending, accepted, declined, expired, revoked
    }

    struct Invite: Codable, Identifiable, Equatable, Sendable {
        let id: String              // Z1
        var communityId: String     // Z1
        var inviterId: String       // Z3
        var inviteeId: String       // Z3
        var status: InviteStatus    // Z2
        var createdAt: Double       // Z1
        var expiresAt: Double?      // Z1
    }

    // MARK: - §6 Reports + moderation actions (route into existing GUARDIAN — CI4)

    enum ReportTargetType: String, Codable, CaseIterable, Sendable {
        case post, comment, member, community, message, resource, event
    }

    enum ReportReason: String, Codable, CaseIterable, Sendable {
        case harassment, doxxing, sexualContent, spam, scam, hate
        case selfHarmConcern, childSafetyRisk, impersonation
        case misinformationRisk, sensitiveLocationExposure, other
    }

    enum ReportStatus: String, Codable, CaseIterable, Sendable {
        case open, triaged, actioned, dismissed
    }

    struct Report: Codable, Identifiable, Equatable, Sendable {
        let id: String                  // Z1
        var communityId: String         // Z1
        var reporterId: String          // Z3
        var targetType: ReportTargetType // Z2
        var targetId: String            // Z2
        var reason: ReportReason        // Z2
        var details: String?            // Z4
        var status: ReportStatus        // Z5
        var createdAt: Double           // Z1
    }

    enum ModerationActionType: String, Codable, CaseIterable, Sendable {
        case warn, removePost, limitMember, muteMember, removeMember, ban
        case pin, unpin, lockThread, approve, dismissReport
    }

    struct ModerationAction: Codable, Identifiable, Equatable, Sendable {
        let id: String                      // Z1
        var communityId: String             // Z1
        var moderatorId: String             // Z5
        var actionType: ModerationActionType // Z5
        var targetType: ReportTargetType    // Z5
        var targetId: String                // Z5
        var reason: String                  // Z5
        var createdAt: Double               // Z5
    }

    // MARK: - §7 Resources + Events

    enum ResourceType: String, Codable, CaseIterable, Sendable {
        case link, doc, video, playlist, guide, faq, starterPack, safetyDoc
    }

    struct Resource: Codable, Identifiable, Equatable, Sendable {
        let id: String              // Z1
        var communityId: String     // Z1
        var type: ResourceType      // Z1
        var title: String           // Z1
        var url: String             // Z1
        var description: String?    // Z1
        var pinned: Bool            // Z2
        var createdBy: String       // Z3
        var createdAt: Double       // Z1
    }

    enum EventKind: String, Codable, CaseIterable, Sendable {
        case meetup, livestream, studySession, volunteerOp
        case classSession = "class"
        case ama, localEvent, groupCall
    }

    /// Real-time audio/video (livestream/groupCall) = CONTRACT-AND-STUB ONLY this build (Gather family).
    /// No WebRTC/LiveKit transport ships. `url` is external/fuzzy only (CI3).
    struct Event: Codable, Identifiable, Equatable, Sendable {
        let id: String              // Z1
        var communityId: String     // Z1
        var kind: EventKind         // Z1
        var title: String           // Z1
        var description: String     // Z1
        var startTime: Double       // Z1 — epoch ms UTC
        var endTime: Double?        // Z1
        var locationMode: LocationMode // Z4
        var approximateRegion: String? // Z4 — coarse only (CI3)
        var url: String?            // Z1 — external link; NOT a live-audio transport (stub)
        var hostId: String          // Z3
        var liveAudioStub: Bool     // invariant marker — always true; live audio disabled this build
    }

    // MARK: - §8 Health + Reputation (Z5 INTERNAL; advisory — CI1/CI2)

    /// Admin/moderator-private. NEVER decoded into a member-facing surface (CI1). Advisory only.
    struct HealthSnapshot: Codable, Equatable, Sendable {
        var communityId: String         // Z5
        var spamIndex: Double           // Z5
        var reportRate: Double          // Z5
        var modResponseTimeSec: Double  // Z5
        var retentionRate: Double       // Z5
        var helpfulReplyRate: Double    // Z5
        var toxicityIndex: Double       // Z5
        var engagementQuality: Double   // Z5
        var burnoutRisk: Double         // Z5
        var computedAt: Double          // Z5
    }

    enum HelpfulnessSignal: String, Codable, CaseIterable, Sendable {
        case helpfulReply, trustedAnswer, resourceContributor, eventHost
        case welcomer, moderatorVerified, conflictResolution, volunteerFulfilled
    }

    struct ReputationEntry: Codable, Identifiable, Equatable, Sendable {
        let id: String                  // Z5 (append-only ledger row)
        var communityId: String         // Z5
        var userId: String              // Z3
        var signal: HelpfulnessSignal   // Z5
        var sourceRef: String?          // Z5
        var createdAt: Double           // Z5
    }

    // MARK: - §9 Recommendations / Safe-Join Preview (explainable — CI6)

    struct Recommendation: Codable, Equatable, Sendable {
        var communityId: String // Z1
        var reason: String      // Z1 — human-readable "why" (CI6)
        var score: Double       // Z5 — INTERNAL ranking input
    }

    enum ModerationLevel: String, Codable, CaseIterable, Sendable {
        case light, standard, strict
    }

    struct SafeJoinPreview: Codable, Equatable, Sendable {
        var communityId: String         // Z1
        var rulesSummary: String        // Z1
        var moderationLevel: ModerationLevel // Z1
        var ageRating: AgeRating        // Z1
        var visibility: Visibility      // Z1
        var whoCanSeePosts: String      // Z1
        var postsHitMainFeed: Bool      // Z1
        var dataVisibilityNote: String  // Z1
    }

    // MARK: - §10 Callable request/response envelopes (types only — no logic in Wave 0)

    enum FeedSort: String, Codable, CaseIterable, Sendable {
        case top, latest, questions, resources, events
    }

    struct SearchRequest: Codable, Sendable { var query: String; var category: String?; var cursor: String?; var limit: Int? }
    struct SearchResult: Codable, Sendable { var communities: [Community]; var nextCursor: String? }

    struct TrendingResult: Codable, Sendable { var communities: [Community] }
    struct RecommendedResult: Codable, Sendable { var recommendations: [Recommendation]; var communities: [Community] }

    struct CreateRequest: Codable, Sendable {
        var name: String
        var slug: String?
        var description: String
        var category: String
        var tags: [String]?
        var visibility: Visibility
        var joinPolicy: JoinPolicy
        var postPolicy: PostPolicy
        var commentPolicy: CommentPolicy
        var governance: Governance?
        var ageRating: AgeRating
        var locationMode: LocationMode?
        var approximateRegion: String?
        var sensitive: Bool?
        var anonymousPostingAllowed: Bool?
        var flairRequired: Bool?
    }
    struct CreateResult: Codable, Sendable { var community: Community }

    struct GetRequest: Codable, Sendable { var id: String }
    struct GetResult: Codable, Sendable { var community: Community; var membership: Membership?; var safeJoinPreview: SafeJoinPreview }

    struct JoinRequest: Codable, Sendable { var id: String; var flair: String? }
    struct JoinResult: Codable, Sendable { var membership: Membership }

    struct RequestJoinRequest: Codable, Sendable { var id: String; var message: String? }
    struct RequestJoinResult: Codable, Sendable { var membership: Membership }

    struct LeaveRequest: Codable, Sendable { var id: String }
    struct LeaveResult: Codable, Sendable { var ok: Bool }

    struct InviteRequest: Codable, Sendable { var id: String; var inviteeId: String }
    struct InviteResult: Codable, Sendable { var invite: Invite }

    struct SetFlairRequest: Codable, Sendable { var id: String; var flair: String }
    struct SetFlairResult: Codable, Sendable { var membership: Membership }

    struct AddToProfileRequest: Codable, Sendable { var id: String; var profileVisibility: ProfileVisibility }
    struct AddToProfileResult: Codable, Sendable { var membership: Membership }
    struct RemoveFromProfileRequest: Codable, Sendable { var id: String }
    struct RemoveFromProfileResult: Codable, Sendable { var ok: Bool }

    struct FeedRequest: Codable, Sendable { var id: String; var sort: FeedSort?; var cursor: String?; var limit: Int? }
    struct FeedResult: Codable, Sendable { var items: [Post]; var postIds: [String]; var nextCursor: String? }

    struct CreatePostRequest: Codable, Sendable { var id: String; var postId: String; var asQuestion: Bool?; var anonymous: Bool? }
    struct CreatePostResult: Codable, Sendable { var communityPost: Post }

    struct ReportRequest: Codable, Sendable {
        var id: String
        var targetType: ReportTargetType
        var targetId: String
        var reason: ReportReason
        var details: String?
    }
    struct ReportResult: Codable, Sendable { var report: Report }

    struct ModerationQueueRequest: Codable, Sendable { var id: String; var cursor: String?; var limit: Int? }
    struct ModerationQueueResult: Codable, Sendable { var reports: [Report]; var nextCursor: String? }

    struct ModerationActionRequest: Codable, Sendable {
        var id: String
        var actionType: ModerationActionType
        var targetType: ReportTargetType
        var targetId: String
        var reason: String
    }
    struct ModerationActionResult: Codable, Sendable { var action: ModerationAction }

    struct UserCommunitiesRequest: Codable, Sendable { var userId: String }
    struct UserCommunitiesResult: Codable, Sendable {
        var featured: [Community]
        var created: [Community]
        var joined: [Community]
        var moderating: [Community]
    }
}
