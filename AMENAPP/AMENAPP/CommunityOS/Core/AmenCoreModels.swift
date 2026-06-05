// AmenCoreModels.swift
// AMEN App — CommunityOS / Core
//
// Phase 1 — Agent A1 (Core Platform Architecture)
// Full implementation of C1 Object Model Contract.
//
// AUTHORING RULES:
//   - Protocols, enums, and structs only in this file.
//   - No service classes, no @Published, no Combine.
//   - ContentAudience and ContentModerationStatus are consumed from existing
//     files (ContentOSModels.swift, TrueSourceModels.swift) — not redefined here.
//   - AmenEdge struct is defined in CommunityOS/Graph/AmenEdgeStore.swift —
//     not redefined here; EdgeType and EdgeVisibility enums are new here.
//   - OPEN: items replicate unresolved questions from C1 contract.

import Foundation
import FirebaseFirestore

// MARK: - ObjectType

/// String discriminator for every AMEN canonical object type.
/// Encoded in Firestore `_type` fields and in AmenEdge fromType/toType.
///
/// NOTE: Does not include `moment` — ONEMoment is managed by the ONE OS module.
/// ActionThread is owned by ActionThreadModels.swift; listed here for edge resolution only.
enum ObjectType: String, Codable, Sendable, CaseIterable {
    case user                   = "user"
    case organization           = "organization"
    case church                 = "church"
    case team                   = "team"
    case space                  = "space"               // Covenant / Amen Space
    case post                   = "post"
    case prayer                 = "prayer"
    case discussion             = "discussion"          // ObjectDiscussionRoom
    case study                  = "study"
    case event                  = "event"
    case volunteerOpportunity   = "volunteerOpportunity"
    case mentorship             = "mentorship"
    case job                    = "job"
    case churchNote             = "churchNote"
    case bereanInsight          = "bereanInsight"
    case mediaObject            = "mediaObject"
    case actionThread           = "actionThread"
    // OPEN (OQ-1): Moment is listed in C1 but managed by ONE OS; exclude here
    //              until OQ-1 (Post vs Moment unification) is resolved.
}

// MARK: - ObjectCapability

/// The complete closed set of capabilities any object can expose.
/// New verbs require a C1 contract change before being added here.
enum ObjectCapability: String, Codable, Sendable, CaseIterable {
    case view       = "view"
    case discuss    = "discuss"
    case pray       = "pray"
    case study      = "study"
    case share      = "share"
    case save       = "save"
    case invite     = "invite"
    case followUp   = "followUp"

    /// Returns the resolved capability set for a given object type.
    /// Maps directly to the C1 §2 capability table.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func capabilities(for type: ObjectType) -> [ObjectCapability] {
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
            // OPEN (OQ-6): Share is listed in C1 table but mentorship is intentionally
            //              private (ONEWitness). Blocked here pending product decision.
            return [.view, .discuss, .pray, .study, .invite, .followUp]
        case .job:
            return [.view, .discuss, .share, .save, .followUp]
        case .churchNote:
            // OPEN (OQ-5): Discuss capability omitted per current UI; may be unlocked
            //              once ChurchNotes become first-class Discussion surfaces.
            return [.view, .pray, .study, .share, .save, .followUp]
        case .bereanInsight:
            return [.view, .discuss, .pray, .study, .share, .save]
        case .mediaObject:
            return [.view, .discuss, .pray, .share, .save]
        case .actionThread:
            return [.view, .discuss, .pray, .invite, .followUp]
        }
    }
}

// MARK: - EdgeType

/// The type of relationship between two objects in the /edges collection.
/// All edge writes must use one of these canonical types.
///
/// OPEN (OQ-17): `follows` may duplicate /socialGraph/{uid}/following.
///               Confirm whether this edges-layer "follows" replaces or
///               overlays the legacy follow subcollection before writing to both.
/// OPEN (OQ-16): `praysFor` edge ownership — client-written or CF-only?
///               Client writes currently open surface area for spam / fake prayer counts.
enum EdgeType: String, Codable, Sendable, CaseIterable {
    case belongsTo      = "belongsTo"   // Object is owned/hosted by another
    case spawnedFrom    = "spawnedFrom" // Object was created via a transform
    case links          = "links"       // Loose contextual association
    case follows        = "follows"     // Directional follow subscription
    case praysFor       = "praysFor"    // Active prayer for a Prayer or User
}

// MARK: - EdgeVisibility

/// Visibility scope for edges in the /edges collection.
enum EdgeVisibility: String, Codable, Sendable {
    case `public`   = "public"   // Visible to anyone who can read both endpoint objects
    case members    = "members"  // Visible to members of a shared Space or Church
    case `private`  = "private"  // Visible only to the createdBy user
}

// MARK: - VerificationState

/// Used on AmenUser, AmenOrganization, and AmenChurch.
enum VerificationState: String, Codable, Sendable {
    case none       = "none"
    case pending    = "pending"
    case verified   = "verified"
}

// MARK: - AmenObject Protocol

/// Base protocol every AMEN canonical object must conform to.
/// All fields are server-set timestamps; iOS client never writes createdAt/updatedAt.
protocol AmenObject: Identifiable, Codable, Sendable {
    var id: String { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var createdBy: String { get }   // Firebase Auth UID of creating user
    var isDeleted: Bool { get }
}

// MARK: - SpawnableObject Protocol

/// Extends AmenObject for objects that can be created *from* another object via
/// a C2 transform intent. `provenance` is immutable after creation.
///
/// OPEN (OQ-15): Rename `Provenance` to `SpawnProvenance` throughout to avoid
///               collision with ONEProvenanceLabel (media authenticity). Decision
///               required before stubs are consumed by all feature agents.
protocol SpawnableObject: AmenObject {
    var provenance: SpawnProvenance? { get }
    // nil provenance = root-originated; no parent object.
}

// MARK: - SpawnProvenance

/// Immutable spawn-chain record. Written once at object creation by Cloud Function
/// or server-side trigger. The iOS client NEVER writes `createdAt`.
///
/// Named `SpawnProvenance` to distinguish from `ONEProvenanceLabel` (media authenticity
/// tracked in ONE/Core/ONEProvenanceModels.swift).
///
/// OPEN (OQ-15): Original C1 contract named this `Provenance`. Renamed here to
///               `SpawnProvenance` to resolve the collision. Broadcast change to
///               all dependent agents before consuming.
struct SpawnProvenance: Codable, Equatable, Sendable {
    /// ObjectType raw value of the parent object, e.g. "post". "direct" for root objects.
    let sourceType: String
    /// Firestore document path of the parent, e.g. "/posts/abc123". nil for root objects.
    let sourceRef: String?
    /// UID of the user who owns the parent object. nil for root objects.
    let sourceOwnerId: String?
    /// C2 Intent raw value that triggered the spawn, e.g. "discuss", "pray", "direct".
    let intent: String
    /// Server-set creation timestamp. Never written by iOS client.
    let createdAt: Date
}

// MARK: - PostVisibility

/// Visibility levels for AmenPost. Distinct from ContentAudience (which governs
/// audience reach) — PostVisibility governs who can see the post at all.
enum PostVisibility: String, Codable, Sendable {
    case `public`   = "public"
    case followers  = "followers"
    case church     = "church"
    case space      = "space"
    case `private`  = "private"
}

// MARK: - PrayerVisibility

/// Aliased from CovenantPrayerRequest.PrayerVisibility for consistency across modules.
enum PrayerVisibility: String, Codable, Sendable {
    case `public`       = "public"
    case membersOnly    = "members_only"
    case anonymous      = "anonymous"
    case `private`      = "private"
}

// MARK: - PrayerStatus

enum PrayerStatus: String, Codable, Sendable {
    case open       = "open"
    case updated    = "updated"
    case answered   = "answered"
    case closed     = "closed"
}

// MARK: - DiscussionRoomType

/// Aliased from ObjectDiscussionRoom.ObjectDiscussionRoomType.
/// OPEN (OQ-4): objectDiscussionRooms path is not namespaced by objectType,
///              risking ID collisions. Recommended path:
///              /objectDiscussionRooms/{objectType}_{canonicalObjectId}/rooms/{roomId}
enum DiscussionRoomType: String, Codable, Sendable {
    case discussion = "discussion"
    case prayer     = "prayer"
    case studyGroup = "study_group"
}

// MARK: - StudyType

enum StudyType: String, Codable, Sendable {
    case plan   = "plan"
    case room   = "room"
}

// MARK: - MentorshipStatus

enum MentorshipStatus: String, Codable, Sendable {
    case requested  = "requested"
    case active     = "active"
    case paused     = "paused"
    case completed  = "completed"
}

// MARK: - JobType

/// OPEN: JobType enum values not finalized with product team. Placeholder values below.
///       Confirm before authoring JobModels.swift (OQ-14).
enum JobType: String, Codable, Sendable {
    case fullTime   = "full_time"
    case partTime   = "part_time"
    case contract   = "contract"
    case volunteer  = "volunteer"
    case internship = "internship"
}

// MARK: - OrgType

enum OrgType: String, Codable, Sendable, CaseIterable {
    case church     = "church"
    case school     = "school"
    case university = "university"
    case business   = "business"
    case ministry   = "ministry"
    case team       = "team"
    case creator    = "creator"
    case nonprofit  = "nonprofit"
}

// MARK: - OrgEntitlementPlan

enum OrgEntitlementPlan: String, Codable, Sendable {
    case free           = "free"
    case communityPro   = "communityPro"
    case churchPro      = "churchPro"
    case orgPro         = "orgPro"
    case enterprise     = "enterprise"
}

// MARK: - OrgPrivacyLevel

enum OrgPrivacyLevel: String, Codable, Sendable {
    case `public`   = "public"
    case members    = "members"
    case `private`  = "private"
}

// MARK: - AmenUser

/// Authenticated user account. Non-spawnable (no provenance).
/// Stored at /users/{uid}.
///
/// NOTE: Complex type fields (ONEPrivacyMirrorLevel, ONEPresenceState, etc.) are
/// typed as String here to avoid import cycles with ONE OS module. Feature agents
/// consuming those fields should cast to the appropriate ONE types.
struct AmenUser: AmenObject {
    let id: String                          // = Firebase Auth uid
    var displayName: String
    var avatarURL: String?
    var bio: String?
    /// Server-set age tier. Never written by client. "tierD"|"tierC"|"tierB"|"blocked".
    var ageTier: String
    /// OPEN: ageTier enforcement contract not yet defined. Server must set and protect.
    var privacyMirror: String               // ONEPrivacyMirrorLevel raw value
    var presenceState: String               // ONEPresenceState raw value
    var entitlement: String                 // ONEEntitlement raw value
    var reachBudgetRemaining: Int           // replenishes weekly; default 20
    var isMemorialized: Bool
    var legacyDirectiveID: String?
    var persona: String?                    // UserPersona raw value
    var faithJourneyStage: String?          // FaithJourneyStage raw value
    var denomination: String?               // Denomination raw value
    var verificationState: VerificationState
    let createdBy: String                   // = id (self-created)
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenOrganization

/// Church, ministry, nonprofit, business, etc.
/// OPEN (OQ-2): Confirm Church is a parallel top-level type and not an OrgType.church sub-type.
/// Stored at /organizations/{orgId}.
struct AmenOrganization: AmenObject {
    let id: String
    var orgType: OrgType
    var name: String
    var slug: String
    var description: String?
    var logoURL: String?
    var coverURL: String?
    var verificationState: VerificationState
    var entitlementPlan: OrgEntitlementPlan
    var adminIds: [String]                  // Firebase Auth UIDs
    var privacyLevel: OrgPrivacyLevel
    var trustScore: Double                  // 0.0–1.0
    var websiteUrl: String?
    var donationUrl: String?
    var isActive: Bool
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenChurch

/// Verified church entity used in trust/discovery/church-notes flows.
/// Distinct from AmenOrganization per C1 §1 — parallel top-level type.
/// OPEN (OQ-2): Confirm this is NOT a sub-type of AmenOrganization.
/// OPEN (OQ-9): Who claims a Church record — platform admin or verified leader?
///              CreatorVerificationRequest.church type should link to this claim flow.
/// Stored at /churches/{churchId}.
struct AmenChurch: AmenObject {
    let id: String
    var name: String
    var address: String?
    var city: String?
    var state: String?
    var zipCode: String?
    var denomination: String?               // Denomination raw value
    var website: String?
    var logoURL: String?
    var memberCount: Int                    // denormalized
    var isVerified: Bool
    var isActive: Bool
    var claimedBy: String?                  // uid of claiming pastor/admin
    var verificationState: VerificationState
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenTeam

/// Internal team within a Church or Space.
/// Stored at /teams/{teamId}.
struct AmenTeam: AmenObject {
    let id: String
    var name: String
    var description: String?
    var churchId: String?                   // denormalized FK; edge also exists in /edges
    var spaceId: String?                    // denormalized FK
    var memberCount: Int                    // denormalized
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
    var memberCount: Int                    // denormalized
    var paidMemberCount: Int               // denormalized
    var isPublic: Bool
    var isPaused: Bool
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenPost

/// Public/semi-public feed item. SpawnableObject — can be spawned from another object.
/// OPEN (OQ-1): Confirm Post and Moment remain separate (current default).
/// Stored at /posts/{postId}.
struct AmenPost: SpawnableObject {
    let id: String
    let authorId: String
    var authorDisplayName: String           // denormalized; updated by CF fan-out
    var authorAvatarURL: String?            // denormalized; updated by CF fan-out
    var body: String
    var mediaAttachments: [String]          // mediaObject IDs or Storage URLs
    var scriptureRefs: [String]
    var tags: [String]
    // NOTE: Uses ContentAudience from ContentOSModels.swift (same target).
    var audience: ContentAudience
    var visibility: PostVisibility
    var spaceId: String?
    var churchId: String?
    var likeCount: Int                      // denormalized; CF-updated
    var commentCount: Int                   // denormalized; CF-updated
    var prayerCount: Int                    // denormalized; CF-updated
    // NOTE: Uses ContentModerationStatus from TrueSourceModels.swift (same target).
    var moderationStatus: ContentModerationStatus
    var capabilities: [ObjectCapability]   // resolved set for display
    let provenance: SpawnProvenance?
    let createdBy: String                   // = authorId
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var deletedAt: Date?
}

// MARK: - AmenPrayer

/// Prayer request or group prayer room.
/// OPEN: Prayer `roomId` and `sourceMessageId` suggest a message-spawn path;
///       confirm whether these fields require a C2 transform or direct creation.
/// Stored at /prayers/{prayerId}.
struct AmenPrayer: SpawnableObject {
    let id: String
    let authorUserId: String
    var authorDisplayName: String           // denormalized; updated by CF fan-out
    var body: String
    var visibility: PrayerVisibility
    var prayedCount: Int                    // denormalized; CF-updated
    var followUpRequested: Bool
    var status: PrayerStatus
    var covenantId: String?
    var roomId: String?
    var sourceMessageId: String?
    var lastUpdateAt: Date?
    let provenance: SpawnProvenance?
    let createdBy: String                   // = authorUserId
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenDiscussion

/// Threaded discussion room anchored on a canonical object.
/// OPEN (OQ-4): /objectDiscussionRooms path not namespaced by type —
///              ID collision risk. Recommended: /{objectType}_{canonicalObjectId}/rooms/{id}.
/// OPEN (OQ-8): Discussion messages have no pagination contract. Default 50/page
///              before live launch.
/// Stored at /objectDiscussionRooms/{canonicalObjectId}/rooms/{roomId}.
struct AmenDiscussion: SpawnableObject {
    let id: String
    let canonicalObjectId: String
    var canonicalObjectTitle: String        // denormalized
    let canonicalObjectType: ObjectType    // [C1-new] type discriminator on parent
    let roomType: DiscussionRoomType
    var participantCount: Int              // denormalized; CF-updated
    var messageCount: Int                  // denormalized; CF-updated
    var lastMessage: String?               // denormalized
    var lastMessageAt: Date?               // denormalized
    let provenance: SpawnProvenance?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenStudy

/// Bible study plan or room.
/// OPEN (OQ-10): No standalone Study model exists in main source tree.
///               Author StudyModels.swift before study features ship.
/// Stored at /studies/{studyId}.
struct AmenStudy: SpawnableObject {
    let id: String
    var title: String
    var description: String
    let authorUid: String
    var studyType: StudyType
    var passages: [String]                 // scripture references
    var weekCount: Int
    var isPublic: Bool
    var spaceId: String?
    var churchId: String?
    var audience: ContentAudience
    let provenance: SpawnProvenance?
    let createdBy: String                  // = authorUid
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenEvent

/// Calendar event associated with a Church, Space, or Organization.
/// OPEN (OQ-11): No standalone Event model exists in main source tree.
///               Author EventModels.swift before event features ship.
/// OPEN: GeoPoint (locationCoords) redacted before public publication per TS-a security rule.
///       Stored as String here to avoid Firestore GeoPoint import complexity.
/// Stored at /events/{eventId}.
struct AmenEvent: SpawnableObject {
    let id: String
    var title: String
    var description: String
    let organizerId: String
    let organizerType: ObjectType          // .user | .church | .space
    var startAt: Date
    var endAt: Date?
    var locationText: String?
    var isVirtual: Bool
    var streamURL: String?
    var rsvpCount: Int                     // denormalized; CF-updated via RSVP edge
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
/// OPEN (OQ-12): No VolunteerOpportunity model exists in main source tree.
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
    var causeCategory: String              // GivingCause raw value
    var requiredSkills: [String]
    var applicationUrl: String?
    /// Always "amenInbox" — raw email/phone never stored on public object.
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
/// OPEN (OQ-13): No Mentorship model exists in main source tree.
///               Author MentorshipModels.swift before mentorship features ship.
/// OPEN (OQ-6): Share capability blocked at capabilities(for:) — mentorship is
///              intentionally private (ONEWitness pattern). Review before unlocking.
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
/// OPEN (OQ-14): JobModels.swift found in git worktrees but absent from main source tree.
///               Locate or re-author before Job features ship.
/// Stored at /jobs/{jobId}.
struct AmenJob: SpawnableObject {
    let id: String
    var title: String
    var description: String
    let organizationId: String
    let organizationType: ObjectType       // .church | .organization
    var location: String?
    var isRemote: Bool
    var jobType: JobType
    var salaryRange: String?
    var applicationUrl: String?
    /// Always "amenInbox" — raw contact info never stored on public object.
    let contactMethod: String
    var expiresAt: Date?
    let provenance: SpawnProvenance?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenChurchNote

/// Sermon or service notes captured by a user (audio, OCR, or typed).
/// OPEN (OQ-5): Discuss capability omitted pending product decision on whether
///              ChurchNotes become first-class Discussion surfaces.
/// Stored at /users/{uid}/churchNotes/{noteId}.
struct AmenChurchNote: SpawnableObject {
    let id: String
    let userId: String
    var noteType: String                   // LivingEntryType raw value
    var title: String
    var body: String
    var churchId: String?
    var churchName: String?                // denormalized
    var sermonTitle: String?
    var scriptureRefs: [String]
    var tags: [String]
    var state: String                      // LivingEntryState raw value
    var reflectionPrompt: String?
    var reflectionAnswer: String?
    var aiSummary: String?
    let provenance: SpawnProvenance?
    let createdBy: String                  // = userId
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
    var intent: String                     // BereanRequestIntent raw value
    var risk: String                       // BereanRequestRisk raw value
    var scriptureRefs: [String]
    let provenance: SpawnProvenance?
    let createdBy: String                  // = userId
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenMediaObject

/// Audio, video, image, or document attachment.
/// OPEN (OQ-3): Consider making MediaObject spawnable when AI-generated —
///              flagged as a traceability gap in AI audit.
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
    let createdBy: String                  // = ownerUid
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - AmenActionThreadRef

/// Reference stub for ActionThread — the full implementation lives in
/// ActionThreadModels.swift. This type exists only to enable capability
/// and edge resolution for ActionThread objects without replacing the original.
struct AmenActionThreadRef: SpawnableObject {
    let id: String
    let createdBy: String
    let createdAt: Date
    let updatedAt: Date
    let isDeleted: Bool
    let provenance: SpawnProvenance?
}
