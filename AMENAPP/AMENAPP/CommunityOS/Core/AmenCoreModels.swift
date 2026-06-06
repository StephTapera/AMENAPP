// AmenCoreModels.swift
// AMEN App — CommunityOS / Core
//
// Phase 1 — Agent A1 (Core Platform Architecture)
// Full C1 Object Model: protocols and domain-object structs.
//
// SHARED TYPES (do NOT redefine here):
//   AmenObjectType, AmenIntent, SpawnProvenance, ObjectCapability,
//   AmenEdgeType, AmenRole  →  CommunityObjectTypes.swift
//   ModerationTier, TransformError, TransformResult  →  TransformEngine.swift
//   ContentAudience         →  ContentOSModels.swift
//   ContentModerationStatus →  TrueSourceModels.swift
//   AmenEdge, EdgeService   →  Core/EdgeService.swift
//   AmenEdgeStore           →  Graph/AmenEdgeStore.swift

import Foundation
import FirebaseFirestore

// VerificationState is defined in CommunityOS/Org/OrgProfileModels.swift (canonical)

// MARK: - AmenPostVisibility

/// Who can see an AmenPost at all (distinct from ContentAudience, which governs reach).
/// Named AmenPostVisibility to avoid collision with legacy PostVisibility in PostsManager.swift.
enum AmenPostVisibility: String, Codable, Sendable {
    case `public`  = "public"
    case followers = "followers"
    case church    = "church"
    case space     = "space"
    case `private` = "private"
}

// MARK: - PrayerVisibility

/// Prayer-specific visibility tiers.
enum PrayerVisibility: String, Codable, Sendable {
    case `public`    = "public"
    case membersOnly = "members_only"
    case anonymous   = "anonymous"
    case `private`   = "private"
}

// PrayerStatus is defined in CommunityOS/Prayer/PrayerModels.swift (canonical, with display helpers)
// DiscussionRoomType is defined in CommunityOS/Discussion/DiscussionModels.swift (canonical, 8 cases)

// MARK: - StudyType

enum StudyType: String, Codable, Sendable {
    case plan = "plan"
    case room = "room"
}

// MARK: - MentorshipStatus

enum MentorshipStatus: String, Codable, Sendable {
    case requested = "requested"
    case active    = "active"
    case paused    = "paused"
    case completed = "completed"
}

// JobType is defined in AMENAPP/JobModels.swift (canonical, 11 cases including ministryStaff, churchStaff, etc.)

// OrgType is defined in CommunityOS/Org/OrgProfileModels.swift (canonical, with display helpers)

// MARK: - OrgEntitlementPlan

enum OrgEntitlementPlan: String, Codable, Sendable {
    case free         = "free"
    case communityPro = "communityPro"
    case churchPro    = "churchPro"
    case orgPro       = "orgPro"
    case enterprise   = "enterprise"
}

// MARK: - OrgPrivacyLevel

enum OrgPrivacyLevel: String, Codable, Sendable {
    case `public`  = "public"
    case members   = "members"
    case `private` = "private"
}

// MARK: - AmenObject Protocol

/// Base protocol every AMEN canonical object must conform to.
/// Fields reflect the C1 §5 schema. Timestamps are server-set; iOS never writes them.
protocol AmenObject: Identifiable, Codable {
    var id: String { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var createdBy: String { get }   // Firebase Auth UID of creating user
    var isDeleted: Bool { get }
}

// MARK: - SpawnableObject Protocol

/// Extends AmenObject for objects created *from* another via a C2 transform.
/// `provenance` is immutable after creation; nil = root-originated (no parent).
///
/// Uses `SpawnProvenance` (defined in CommunityObjectTypes.swift) to avoid
/// collision with `ONEProvenanceLabel` (media authenticity in ONE/Core/).
/// OPEN (OQ-15): Confirm `SpawnProvenance` name is broadcast to all feature agents.
protocol SpawnableObject: AmenObject {
    var provenance: SpawnProvenance? { get }
}

// MARK: - AmenUser

/// Authenticated user account. Non-spawnable (no provenance).
/// Stored at /users/{uid}.
///
/// Complex ONE-module fields (privacyMirror, presenceState, entitlement) stored
/// as raw strings to avoid import cycles with the ONE OS module. Feature code
/// consuming those fields should cast to the appropriate ONE types.
struct AmenUser: AmenObject {
    let id: String                       // = Firebase Auth uid
    var displayName: String
    var avatarURL: String?
    var bio: String?
    /// Server-set age tier. Never written by the client.
    /// Values: "tierD" | "tierC" | "tierB" | "blocked".
    var ageTier: String
    var privacyMirror: String            // ONEPrivacyMirrorLevel raw value
    var presenceState: String            // ONEPresenceState raw value
    var entitlement: String              // ONEEntitlement raw value
    var reachBudgetRemaining: Int        // replenishes weekly; default 20
    var isMemorialized: Bool
    var legacyDirectiveID: String?
    var persona: String?                 // UserPersona raw value
    var faithJourneyStage: String?       // FaithJourneyStage raw value
    var denomination: String?            // Denomination raw value
    var verificationState: VerificationState
    let createdBy: String                // = id (self-created)
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// AmenOrganization is defined in CommunityOS/Organization/AmenOrganizationModels.swift (canonical, richer fields)

// MARK: - AmenChurch

/// Verified church entity for trust/discovery/church-notes flows.
/// Distinct from AmenOrganization per C1 §1 — parallel top-level type.
/// OPEN (OQ-2): Confirm NOT a sub-type of AmenOrganization.
/// OPEN (OQ-9): Who claims a Church record — platform admin or verified leader?
///              Link CreatorVerificationRequest.church to this claim flow.
/// Stored at /churches/{churchId}.
struct AmenChurch: AmenObject {
    let id: String
    var name: String
    var address: String?
    var city: String?
    var state: String?
    var zipCode: String?
    var denomination: String?            // Denomination raw value
    var website: String?
    var logoURL: String?
    var memberCount: Int                 // denormalized
    var isVerified: Bool
    var isActive: Bool
    var claimedBy: String?               // uid of claiming pastor/admin
    var verificationState: VerificationState
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenTeam

/// Internal team within a Church or Space. Stored at /teams/{teamId}.
struct AmenTeam: AmenObject {
    let id: String
    var name: String
    var description: String?
    var churchId: String?                // denormalized FK; edge also exists in /edges
    var spaceId: String?                 // denormalized FK
    var memberCount: Int                 // denormalized
    var isPrivate: Bool
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenSpace

/// Amen Space / Covenant — community hub. Stored at /covenants/{spaceId}.
struct AmenSpace: AmenObject {
    let id: String
    var name: String
    var tagline: String
    var description: String
    var coverImageURL: String?
    var avatarURL: String?
    var memberCount: Int                 // denormalized
    var paidMemberCount: Int            // denormalized
    var isPublic: Bool
    var isPaused: Bool
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenPost

/// Public/semi-public feed item. SpawnableObject.
/// OPEN (OQ-1): Confirm Post and Moment remain separate types (current default).
/// Stored at /posts/{postId}.
struct AmenPost: SpawnableObject {
    let id: String
    let authorId: String
    var authorDisplayName: String        // denormalized; CF fan-out updates this
    var authorAvatarURL: String?         // denormalized; CF fan-out updates this
    var body: String
    var mediaAttachments: [String]       // mediaObject IDs or Firebase Storage URLs
    var scriptureRefs: [String]
    var tags: [String]
    // ContentAudience from ContentOSModels.swift
    var audience: ContentAudience
    var visibility: AmenPostVisibility
    var spaceId: String?
    var churchId: String?
    var likeCount: Int                   // denormalized; CF-updated
    var commentCount: Int                // denormalized; CF-updated
    var prayerCount: Int                 // denormalized; CF-updated
    // ContentModerationStatus from TrueSourceModels.swift
    var moderationStatus: ContentModerationStatus
    var capabilities: [ObjectCapability] // resolved set for display
    let provenance: SpawnProvenance?
    let createdBy: String                // = authorId
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var deletedAt: Date?
}

// MARK: - AmenPrayer

/// Prayer request or group prayer room. Stored at /prayers/{prayerId}.
struct AmenPrayer: SpawnableObject {
    let id: String
    let authorUserId: String
    var authorDisplayName: String        // denormalized; CF fan-out updates this
    var body: String
    var visibility: PrayerVisibility
    var prayedCount: Int                 // denormalized; CF-updated
    var followUpRequested: Bool
    var status: PrayerStatus
    var covenantId: String?
    var roomId: String?
    var sourceMessageId: String?
    var lastUpdateAt: Date?
    let provenance: SpawnProvenance?
    let createdBy: String                // = authorUserId
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenDiscussion

/// Threaded discussion room anchored on a canonical object.
/// OPEN (OQ-4): /objectDiscussionRooms path not namespaced by objectType —
///              ID collision risk. Recommended: /{objectType}_{canonicalObjectId}/rooms/{id}.
/// OPEN (OQ-8): No pagination contract for Discussion messages. Default 50/page before launch.
/// Stored at /objectDiscussionRooms/{canonicalObjectId}/rooms/{roomId}.
struct AmenDiscussion: SpawnableObject {
    let id: String
    let canonicalObjectId: String
    var canonicalObjectTitle: String     // denormalized
    let canonicalObjectType: AmenObjectType // [C1-new] type discriminator on parent
    let roomType: DiscussionRoomType
    var participantCount: Int            // denormalized; CF-updated
    var messageCount: Int               // denormalized; CF-updated
    var lastMessage: String?            // denormalized
    var lastMessageAt: Date?            // denormalized
    let provenance: SpawnProvenance?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenStudy

/// Bible study plan or room.
/// OPEN (OQ-10): No standalone Study model in main source tree.
///               Author StudyModels.swift before study features ship.
/// Stored at /studies/{studyId}.
struct AmenStudy: SpawnableObject {
    let id: String
    var title: String
    var description: String
    let authorUid: String
    var studyType: StudyType
    var passages: [String]              // scripture references
    var weekCount: Int
    var isPublic: Bool
    var spaceId: String?
    var churchId: String?
    var audience: ContentAudience
    let provenance: SpawnProvenance?
    let createdBy: String               // = authorUid
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenEvent

/// Calendar event. Stored at /events/{eventId}.
/// OPEN (OQ-11): No standalone Event model in main source tree.
///               Author EventModels.swift before event features ship.
/// OPEN: locationCoords (GeoPoint) redacted before public publication per TS-a security rule;
///       stored as locationText String only.
struct AmenEvent: SpawnableObject {
    let id: String
    var title: String
    var description: String
    let organizerId: String
    let organizerType: AmenObjectType    // .user | .church | .space
    var startAt: Date
    var endAt: Date?
    var locationText: String?
    var isVirtual: Bool
    var streamURL: String?
    var rsvpCount: Int                  // denormalized; CF-updated via RSVP edge
    var audience: ContentAudience
    var spaceId: String?
    var churchId: String?
    let provenance: SpawnProvenance?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenVolunteerOpportunity

/// Volunteer position at a Church or Organization.
/// OPEN (OQ-12): No VolunteerOpportunity model in main source tree.
///               Author VolunteerOpportunityModels.swift before volunteer features ship.
/// Stored at /volunteerOpportunities/{id}.
struct AmenVolunteerOpportunity: SpawnableObject {
    let id: String
    var title: String
    var description: String
    let organizationId: String
    var churchId: String?
    var location: String?
    var isRemote: Bool
    var causeCategory: String            // GivingCause raw value
    var requiredSkills: [String]
    var applicationUrl: String?
    /// Always "amenInbox" — raw contact info never stored on this public object.
    let contactMethod: String
    var expiresAt: Date?
    let provenance: SpawnProvenance?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenMentorship

/// Mentorship pairing or request.
/// OPEN (OQ-13): No Mentorship model in main source tree.
///               Author MentorshipModels.swift before mentorship features ship.
/// OPEN (OQ-6): Share capability intentionally blocked — mentorship is private.
///              Confirm at capability layer before unlocking.
/// Stored at /mentorships/{id}.
struct AmenMentorship: SpawnableObject {
    let id: String
    let mentorUid: String
    let menteeUid: String
    var status: MentorshipStatus
    var focus: String?
    var scriptureTheme: String?
    var sessionCount: Int
    var nextSessionAt: Date?
    let provenance: SpawnProvenance?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenJob

/// Ministry job or internship posting.
/// OPEN (OQ-14): JobModels.swift absent from main source tree. Locate or re-author.
/// Stored at /jobs/{jobId}.
struct AmenJob: SpawnableObject {
    let id: String
    var title: String
    var description: String
    let organizationId: String
    let organizationType: AmenObjectType // .church | .organization
    var location: String?
    var isRemote: Bool
    var jobType: JobType
    var salaryRange: String?
    var applicationUrl: String?
    /// Always "amenInbox" — raw contact info never stored on this public object.
    let contactMethod: String
    var expiresAt: Date?
    let provenance: SpawnProvenance?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenChurchNote

/// Sermon/service notes captured by a user (audio, OCR, or typed).
/// OPEN (OQ-5): Discuss capability currently omitted. Unlock when ChurchNotes
///              become first-class Discussion surfaces.
/// Stored at /users/{uid}/churchNotes/{noteId}.
struct AmenChurchNote: SpawnableObject {
    let id: String
    let userId: String
    var noteType: String                 // LivingEntryType raw value
    var title: String
    var body: String
    var churchId: String?
    var churchName: String?             // denormalized
    var sermonTitle: String?
    var scriptureRefs: [String]
    var tags: [String]
    var state: String                   // LivingEntryState raw value
    var reflectionPrompt: String?
    var reflectionAnswer: String?
    var aiSummary: String?
    let provenance: SpawnProvenance?
    let createdBy: String               // = userId
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenBereanInsight

/// AI-generated scripture study output from Berean.
/// Stored at /users/{uid}/bereanInsights/{insightId}.
struct AmenBereanInsight: SpawnableObject {
    let id: String
    let userId: String
    var requestText: String
    var responseText: String
    var intent: String                  // BereanRequestIntent raw value
    var risk: String                    // BereanRequestRisk raw value
    var scriptureRefs: [String]
    let provenance: SpawnProvenance?
    let createdBy: String               // = userId
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenMediaObject

/// Audio, video, image, or document attachment.
/// Non-spawnable (no provenance).
/// OPEN (OQ-3): Consider making spawnable when AI-generated (traceability gap per AI audit).
/// Stored at /mediaObjects/{mediaId}.
struct AmenMediaObject: AmenObject {
    let id: String
    let ownerUid: String
    var storageURL: String
    var thumbnailURL: String?
    var mimeType: String
    var durationSeconds: Double?
    var widthPx: Int?
    var heightPx: Int?
    var altText: String?
    var captionsURL: String?
    var moderationStatus: String
    let createdBy: String               // = ownerUid
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenActionThreadRef

/// Protocol-conformance stub for ActionThread. The full model lives in
/// ActionThreadModels.swift. Used only for capability/edge resolution.
struct AmenActionThreadRef: SpawnableObject {
    let id: String
    let createdBy: String
    let createdAt: Date
    let updatedAt: Date
    let isDeleted: Bool
    let provenance: SpawnProvenance?
}

// MARK: - ObjectCapability + capabilities(for:) extension
//
// ObjectCapability enum is defined in CommunityObjectTypes.swift.
// This extension adds the static capabilities(for:) mapping from C1 §2.

extension ObjectCapability {

    /// Returns the resolved capability set for a given object type per C1 §2 table.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func capabilities(for type: AmenObjectType) -> [ObjectCapability] {
        switch type {
        case .user:
            return [.view, .pray, .share, .invite]
        case .organization:
            return [.view, .discuss, .pray, .share, .save, .invite]
        case .church:
            return [.view, .discuss, .pray, .study, .share, .save, .invite, .followUp]
        case .team:
            return [.view, .discuss, .pray, .share, .invite, .followUp]
        case .space:
            return [.view, .discuss, .pray, .study, .share, .invite, .followUp]
        case .post:
            return [.view, .discuss, .pray, .share, .save]
        case .prayer:
            return [.view, .discuss, .pray, .share, .save, .followUp]
        case .discussion:
            return [.view, .discuss, .pray, .share, .invite]
        case .study:
            return [.view, .discuss, .pray, .study, .share, .save, .invite, .followUp]
        case .event:
            return [.view, .discuss, .pray, .share, .save, .invite, .followUp]
        case .volunteerOpportunity:
            return [.view, .discuss, .pray, .share, .save, .invite, .followUp]
        case .mentorship:
            // OPEN (OQ-6): Share blocked; mentorship is intentionally private.
            return [.view, .discuss, .pray, .study, .invite, .followUp]
        case .job:
            return [.view, .discuss, .share, .save, .followUp]
        case .churchNote:
            // OPEN (OQ-5): Discuss omitted until ChurchNotes are first-class Discussion surfaces.
            return [.view, .pray, .study, .share, .save, .followUp]
        case .bereanInsight:
            return [.view, .discuss, .pray, .study, .share, .save]
        case .mediaObject:
            return [.view, .discuss, .pray, .share, .save]
        case .moment:
            return [.view, .pray, .share]
        case .actionThread:
            return [.view, .discuss, .pray, .invite, .followUp]
        }
    }
}
