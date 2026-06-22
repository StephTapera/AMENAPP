// AmenCoreModels.swift
// contracts/stubs/AmenCoreModels.swift
//
// Phase 0 Contract C1 — Core Object Model Stubs
// Version: 1.0.0  |  Date: 2026-06-05
//
// RULES:
//   - Structs, enums, protocols ONLY.
//   - No method bodies, no service classes, no @Published, no computed logic.
//   - Every spawnable object carries provenance: Provenance (immutable, server-set).
//   - Mark open decisions with // OPEN: <question>
//   - Field names preserved from existing codebase where they exist.
//
// OPEN: Rename "Provenance" -> "SpawnProvenance" throughout to avoid collision
//       with ONEProvenanceLabel (media authenticity, in ONE/Core/ONEProvenanceModels.swift).
//       Decision needed before stubs are consumed by feature agents.

import Foundation

// MARK: - ObjectType Discriminator

/// String discriminator used in AmenEdge.fromType / toType and in Firestore `_type` fields.
enum ObjectType: String, Codable, Sendable, CaseIterable {
    case user               = "user"
    case organization       = "organization"
    case church             = "church"
    case team               = "team"
    case space              = "space"           // Covenant / Amen Space
    case post               = "post"
    case prayer             = "prayer"
    case discussion         = "discussion"      // ObjectDiscussionRoom
    case study              = "study"
    case event              = "event"
    case volunteerOpportunity = "volunteerOpportunity"
    case mentorship         = "mentorship"
    case job                = "job"
    case churchNote         = "churchNote"
    case bereanInsight      = "bereanInsight"
    case mediaObject        = "mediaObject"
    case moment             = "moment"          // ONE Moment
    case actionThread       = "actionThread"
}

// MARK: - ObjectCapability

/// The complete set of verbs an object can expose. No object may expose capabilities
/// outside this enum. New verbs require a C1 contract revision.
enum ObjectCapability: String, Codable, Sendable, CaseIterable {
    case view       = "view"
    case discuss    = "discuss"
    case pray       = "pray"
    case study      = "study"
    case share      = "share"
    case save       = "save"
    case invite     = "invite"
    case followUp   = "followUp"
}

// MARK: - AmenObject Protocol

/// Base protocol for all AMEN canonical objects.
protocol AmenObject: Identifiable, Codable, Sendable {
    var id: String { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var createdBy: String { get }   // uid of creating user
    var isDeleted: Bool { get }
}

// MARK: - SpawnableObject Protocol

/// Extends AmenObject for all objects that can be created *from* another object.
/// `provenance` is written once at creation; never mutated thereafter.
protocol SpawnableObject: AmenObject {
    var provenance: Provenance? { get }
    // nil provenance = root-originated (no parent object)
}

// MARK: - Provenance Struct

/// Immutable spawn-chain record. Set once at object creation by Cloud Function
/// or server-side trigger. The iOS client NEVER writes createdAt.
///
/// OPEN: Rename to SpawnProvenance to avoid collision with ONEProvenanceLabel.
struct Provenance: Codable, Equatable, Sendable {
    /// ObjectType raw value of the parent, e.g. "post". "direct" for root objects.
    let sourceType: String
    /// Firestore document path of the parent object, e.g. "/posts/abc123". nil for root.
    let sourceRef: String?
    /// UID of the user who owns the parent object. nil for root.
    let sourceOwnerId: String?
    /// C2 intent raw value that triggered the spawn, e.g. "discuss", "pray", "direct".
    let intent: String
    /// Server-set creation timestamp. Never written by iOS client.
    let createdAt: Date
}

// MARK: - AmenEdge

/// Many-to-many relationship document stored in /edges/{edgeId}.
struct AmenEdge: AmenObject {
    let id: String
    let fromRef: String         // Firestore document path of source object
    let fromType: ObjectType
    let toRef: String           // Firestore document path of target object
    let toType: ObjectType
    let edgeType: EdgeType
    let createdBy: String       // uid
    let visibility: EdgeVisibility
    let createdAt: Date
    let updatedAt: Date
    let isDeleted: Bool
}

enum EdgeType: String, Codable, Sendable, CaseIterable {
    case belongsTo      = "belongsTo"   // Object is owned/hosted by another
    case spawnedFrom    = "spawnedFrom" // Object was created via a transform
    case links          = "links"       // Loose contextual association
    case follows        = "follows"     // Directional follow subscription
    // OPEN: Does "follows" duplicate /socialGraph/{uid}/following? Confirm before writing.
    case praysFor       = "praysFor"    // Active prayer for a Prayer or User
    // OPEN: Should praysFor edges be client-written or CF-only to prevent spam?
}

enum EdgeVisibility: String, Codable, Sendable {
    case `public`   = "public"   // Visible to anyone who can read both endpoints
    case members    = "members"  // Visible to members of a shared Space or Church
    case `private`  = "private"  // Visible only to createdBy user
}

// MARK: - User

struct AmenUser: AmenObject {
    let id: String                          // = Firebase Auth uid
    var displayName: String
    var avatarURL: String?
    var bio: String?
    // OPEN: ageTier set by server. Define AgeTier enum and server-enforcement contract.
    var ageTier: String                     // "tierD"|"tierC"|"tierB"|"blocked"
    var privacyMirror: ONEPrivacyMirrorLevel
    var presenceState: ONEPresenceState
    var entitlement: ONEEntitlement
    var reachBudgetRemaining: Int           // replenishes weekly; default 20
    var isMemorialized: Bool
    var legacyDirectiveID: String?
    var persona: UserPersona?
    var faithJourneyStage: FaithJourneyStage?
    var denomination: Denomination?
    var profileIdentity: UserProfileIdentity
    var verificationState: VerificationState
    let createdBy: String                   // = id (self-created)
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

enum VerificationState: String, Codable, Sendable {
    case none       = "none"
    case pending    = "pending"
    case verified   = "verified"
}

// MARK: - Organization

struct AmenOrganization: AmenObject {
    let id: String
    let _type: ObjectType               // always .organization
    var orgType: OrgType
    var name: String
    var slug: String
    var description: String?
    var logoURL: String?
    var coverURL: String?
    var verificationState: VerificationState
    var entitlementPlan: OrgEntitlementPlan
    var adminIds: [String]              // uids
    var privacyLevel: OrgPrivacyLevel
    var causeCategories: [GivingCause]
    var trustBadges: [TrustBadge]
    var trustScore: Double
    var transparency: OrgTransparency?
    var websiteUrl: String?
    var donationUrl: String?
    var isActive: Bool
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

enum OrgType: String, Codable, Sendable, CaseIterable {
    case church         = "church"
    case school         = "school"
    case university     = "university"
    case business       = "business"
    case ministry       = "ministry"
    case team           = "team"
    case creator        = "creator"
    case nonprofit      = "nonprofit"
}

enum OrgEntitlementPlan: String, Codable, Sendable {
    case free           = "free"
    case communityPro   = "communityPro"
    case churchPro      = "churchPro"
    case orgPro         = "orgPro"
    case enterprise     = "enterprise"
}

enum OrgPrivacyLevel: String, Codable, Sendable {
    case `public`   = "public"
    case members    = "members"
    case `private`  = "private"
}

// MARK: - Church

/// Distinct from Organization — verified church entity used in trust, discovery, and
/// church notes flows.
/// OPEN: Confirm Church is a parallel top-level type and not an OrgType.church sub-type.
struct AmenChurch: AmenObject {
    let id: String
    var name: String
    var address: String?
    var city: String?
    var state: String?
    var zipCode: String?
    var denomination: Denomination?
    var website: String?
    var logoURL: String?
    var trustBadges: [TrustBadgeType]
    var memberCount: Int                // denormalized
    var isVerified: Bool
    var isActive: Bool
    var claimedBy: String?              // uid of claiming pastor/admin
    var verificationState: VerificationState
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - Team

struct AmenTeam: AmenObject {
    let id: String
    var name: String
    var description: String?
    var churchId: String?               // denormalized FK; edge also exists
    var spaceId: String?                // denormalized FK
    var memberCount: Int                // denormalized
    var isPrivate: Bool
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - Space (Covenant)

struct AmenSpace: AmenObject {
    let id: String
    var name: String
    var tagline: String
    var description: String
    var coverImageURL: String?
    var avatarURL: String?
    var tiers: [CovenantTier]
    var operatingMode: CovenantOperatingMode
    var trustBadges: [TrustBadgeType]
    var memberCount: Int                // denormalized
    var paidMemberCount: Int            // denormalized
    var isPublic: Bool
    var isPaused: Bool
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - Post

struct AmenPost: SpawnableObject {
    let id: String
    let authorId: String
    var authorDisplayName: String       // denormalized
    var authorAvatarURL: String?        // denormalized
    var body: String
    var mediaAttachments: [String]      // mediaObject IDs or Storage URLs
    var scriptureRefs: [String]
    var tags: [String]
    var audience: ContentAudience
    var visibility: PostVisibility
    var spaceId: String?
    var churchId: String?
    var likeCount: Int                  // denormalized
    var commentCount: Int               // denormalized
    var prayerCount: Int                // denormalized
    var moderationStatus: ContentModerationStatus
    var capabilities: [ObjectCapability]    // resolved capability set for display
    let provenance: Provenance?
    let createdBy: String               // = authorId
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var deletedAt: Date?
}

enum PostVisibility: String, Codable, Sendable {
    case `public`   = "public"
    case followers  = "followers"
    case church     = "church"
    case space      = "space"
    case `private`  = "private"
}

enum ContentAudience: String, Codable, Sendable {
    case everyone       = "everyone"
    case followers      = "followers"
    case church         = "church"
    case space          = "space"
    case closeFriends   = "closeFriends"
    case onlyMe         = "onlyMe"
}

enum ContentModerationStatus: String, Codable, Sendable {
    case pending    = "pending"
    case approved   = "approved"
    case flagged    = "flagged"
    case blocked    = "blocked"
    case appealing  = "appealing"
}

// MARK: - Prayer

struct AmenPrayer: SpawnableObject {
    let id: String
    let authorUserId: String
    var authorDisplayName: String       // denormalized
    var body: String
    var visibility: PrayerVisibility
    var prayedCount: Int                // denormalized
    var followUpRequested: Bool
    var status: PrayerStatus
    var covenantId: String?
    var roomId: String?
    var sourceMessageId: String?
    var lastUpdateAt: Date?
    let provenance: Provenance?
    let createdBy: String               // = authorUserId
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

/// Aliased from CovenantPrayerRequest.PrayerVisibility to maintain consistency.
enum PrayerVisibility: String, Codable, Sendable {
    case `public`       = "public"
    case membersOnly    = "members_only"
    case anonymous      = "anonymous"
    case `private`      = "private"
}

/// Aliased from CovenantPrayerRequest.PrayerStatus.
enum PrayerStatus: String, Codable, Sendable {
    case open       = "open"
    case updated    = "updated"
    case answered   = "answered"
    case closed     = "closed"
}

// MARK: - Discussion (ObjectDiscussionRoom)

struct AmenDiscussion: SpawnableObject {
    let id: String
    let canonicalObjectId: String
    var canonicalObjectTitle: String    // denormalized
    let canonicalObjectType: ObjectType // [C1-new] type discriminator on parent
    let roomType: DiscussionRoomType
    var participantCount: Int           // denormalized
    var messageCount: Int               // denormalized
    var lastMessage: String?            // denormalized
    var lastMessageAt: Date?            // denormalized
    let provenance: Provenance?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

/// Aliased from ObjectDiscussionRoom.ObjectDiscussionRoomType.
enum DiscussionRoomType: String, Codable, Sendable {
    case discussion = "discussion"
    case prayer     = "prayer"
    case studyGroup = "study_group"
}

// MARK: - Study

/// OPEN: No standalone Study model exists in main source tree.
/// This stub is synthetic — author StudyModels.swift before study features ship.
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
    let provenance: Provenance?
    let createdBy: String               // = authorUid
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

enum StudyType: String, Codable, Sendable {
    case plan   = "plan"
    case room   = "room"
}

// MARK: - Event

/// OPEN: No standalone Event model exists in main source tree.
/// This stub is synthetic — author EventModels.swift before event features ship.
struct AmenEvent: SpawnableObject {
    let id: String
    var title: String
    var description: String
    let organizerId: String
    let organizerType: ObjectType       // "user"|"church"|"space"
    var startAt: Date
    var endAt: Date?
    var locationText: String?
    // OPEN: GeoPoint redacted before public publication per TS-a security rule.
    var isVirtual: Bool
    var streamURL: String?
    var rsvpCount: Int                  // denormalized
    var audience: ContentAudience
    var spaceId: String?
    var churchId: String?
    let provenance: Provenance?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - VolunteerOpportunity

/// OPEN: No VolunteerOpportunity model exists in main source tree.
/// This stub is synthetic — author VolunteerOpportunityModels.swift before volunteer features ship.
struct AmenVolunteerOpportunity: SpawnableObject {
    let id: String
    var title: String
    var description: String
    let organizationId: String
    var churchId: String?
    var location: String?
    var isRemote: Bool
    var causeCategory: GivingCause
    var requiredSkills: [String]
    var applicationUrl: String?
    /// Always "amenInbox" — raw email/phone never stored on public object.
    let contactMethod: String
    var expiresAt: Date?
    let provenance: Provenance?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - Mentorship

/// OPEN: No Mentorship model exists in main source tree.
/// Implied by OpenToSignal.mentorship and RelationshipType.mentor/mentee.
/// Author MentorshipModels.swift.
struct AmenMentorship: SpawnableObject {
    let id: String
    let mentorUid: String
    let menteeUid: String
    var status: MentorshipStatus
    var focus: String?
    var scriptureTheme: String?
    var sessionCount: Int
    var nextSessionAt: Date?
    let provenance: Provenance?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

enum MentorshipStatus: String, Codable, Sendable {
    case requested  = "requested"
    case active     = "active"
    case paused     = "paused"
    case completed  = "completed"
}

// MARK: - Job

/// OPEN: JobModels.swift found in git worktrees but absent from main source tree. Locate or re-author.
/// OPEN: JobType enum is not defined in any current source file. Placeholder below.
struct AmenJob: SpawnableObject {
    let id: String
    var title: String
    var description: String
    let organizationId: String
    let organizationType: ObjectType    // "church"|"organization"
    var location: String?
    var isRemote: Bool
    var jobType: JobType
    var salaryRange: String?
    var applicationUrl: String?
    /// Always "amenInbox" — raw contact info never stored on public object.
    let contactMethod: String
    var expiresAt: Date?
    let provenance: Provenance?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

/// OPEN: Define JobType values with product team before authoring JobModels.swift.
enum JobType: String, Codable, Sendable {
    case fullTime   = "full_time"
    case partTime   = "part_time"
    case contract   = "contract"
    case volunteer  = "volunteer"
    case internship = "internship"
}

// MARK: - ChurchNote

/// Synthesized from LivingEntry, LivingEntryModels.swift, ChurchNotesIntelligenceModels.swift.
/// Stored at /users/{uid}/churchNotes/{noteId}
struct AmenChurchNote: SpawnableObject {
    let id: String
    let userId: String
    var type: LivingEntryType           // .churchNote | .sermonInsight
    var title: String
    var body: String
    var churchId: String?
    var churchName: String?             // denormalized
    var sermonTitle: String?
    var scriptureRefs: [String]
    var tags: [String]
    var anchors: [CNAnchorType]
    var posture: CNPostureSignal?
    var sermonBridge: CNSermonBridge?
    var state: LivingEntryState
    var reflectionPrompt: String?
    var reflectionAnswer: String?
    var aiSummary: String?
    let provenance: Provenance?
    let createdBy: String               // = userId
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - BereanInsight

/// Stored at /users/{uid}/bereanInsights/{insightId}
struct AmenBereanInsight: SpawnableObject {
    let id: String
    let userId: String
    var requestText: String
    var responseText: String
    var intent: BereanRequestIntent
    var risk: BereanRequestRisk
    var scriptureRefs: [String]
    var studyOutline: BereanStudyOutline?
    var provenanceRecord: BereanProvenanceRecord
    let provenance: Provenance?
    let createdBy: String               // = userId
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - MediaObject

/// Stored at /mediaObjects/{mediaId}
/// Not spawnable (no provenance) — but OPEN: consider making it spawnable for AI-generated media.
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
    var sourceType: MediaProvenance.MediaSourceType
    var syntheticStatus: MediaProvenance.SyntheticMediaStatus
    var contentCredentials: MediaProvenance.ContentCredentialsStatus
    var aiEvents: [ProvenanceAIEvent]
    var editEvents: [ProvenanceEditEvent]
    var disclosureRequired: Bool
    var disclosureSatisfied: Bool
    var moderationStatus: String
    let createdBy: String               // = ownerUid
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

// MARK: - Moment (ONE)

/// ONE Private Social Moment. Uses ONEProvenanceLabel for media authenticity and
/// optionally Provenance for spawn chain (when spawned from another object).
///
/// OPEN: ONEMoment does not currently carry isDeleted. Added here as [C1-new].
/// OPEN: Confirm Moment.provenance (spawn chain) vs. Moment.provenanceLabel (media authenticity)
///       naming is acceptable before consuming this stub in feature code.
struct AmenMoment: SpawnableObject {
    let id: String
    let authorUID: String
    let type: ONEMomentType
    var privacy: ONEPrivacyContract
    let content: ONEMomentContent
    let provenanceLabel: ONEProvenanceLabel   // media authenticity (from ONE/Core/)
    let consentDNA: ONEConsentDNA
    var reachBudget: ONEReachBudget?
    let isE2E: Bool
    var expiresAt: Date?
    var permanentAt: Date?
    var reportedAt: Date?
    let provenance: Provenance?              // spawn chain (nil for root moments)
    let createdBy: String                    // = authorUID
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool                      // [C1-new] not in current ONEMoment
}

// MARK: - ActionThread (existing — stub only, do not replace)

/// Existing type — do not author a new model. This stub exists only to make
/// ActionThread conform to AmenObject + SpawnableObject for edge/capability resolution.
/// Full implementation in ActionThreadModels.swift.
struct AmenActionThreadRef: SpawnableObject {
    let id: String
    let createdBy: String
    let createdAt: Date
    let updatedAt: Date
    let isDeleted: Bool
    let provenance: Provenance?
    // All other fields come from ActionThreadModels.swift
}

// MARK: - Type Aliases (for cross-referencing existing models)
//
// The types below are used in the stubs above but are fully defined in existing
// AMENAPP source files. Listed here for reference only — do not redefine.
//
// From ONEUserModels.swift:
//   ONEPrivacyMirrorLevel, ONEPresenceState, ONEEntitlement, ONEEntitlementTier
//
// From ONEPrivacyModels.swift:
//   ONEPrivacyContract, ONEAudienceScope, ONELifetimePolicy, ONEMomentPermissions,
//   ONESafetySettings, ONEConsentDNA
//
// From ONEProvenanceModels.swift:
//   ONEProvenanceLabel, ONEProvenanceClass, ONEReachBudget
//
// From ONEMomentModels.swift:
//   ONEMomentType, ONEMomentContent, ONETextPayload, ONEImagePayload, ONEVideoPayload,
//   ONEAudioPayload, ONELocationPayload, ONEAlbumPayload, ONEEncryptedPayload
//
// From CovenantModels.swift:
//   CovenantTier, CovenantOperatingMode, TrustBadgeType
//
// From ProfileIdentityModels.swift:
//   UserPersona, FaithJourneyStage, Denomination, UserProfileIdentity
//
// From GivingModels.swift:
//   GivingCause, TrustBadge, OrgTransparency
//
// From LivingEntryModels.swift:
//   LivingEntryType, LivingEntryState
//
// From ChurchNotesIntelligenceModels.swift:
//   CNAnchorType, CNPostureSignal, CNSermonBridge
//
// From BereanGrokModels.swift:
//   BereanRequestIntent, BereanRequestRisk, BereanStudyOutline, BereanProvenanceRecord
//
// From SocialOSModels.swift:
//   MediaProvenance (MediaSourceType, ContentCredentialsStatus, SyntheticMediaStatus),
//   ProvenanceAIEvent, ProvenanceEditEvent
