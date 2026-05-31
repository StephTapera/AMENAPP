// OrgSpaceHierarchyContract.swift
// AMEN — SPACES_CONNECT_V1 / Phase −1 Contracts
//
// FROZEN 2026-05-31. Do not edit without SpacesConnect-Phase0 authorization.
//
// ─── Firestore Schema ────────────────────────────────────────────────────────
//
//  /orgs/{orgId}
//    name:        String
//    orgType:     OrgType  (string enum)
//    slug:        String   (unique URL-safe handle, e.g. "grace-community-church")
//    verified:    Bool     (trust-layer verification badge)
//    avatarURL:   String?
//    ownerUid:    String   (SERVER-OWNED on create)
//    settings:    Map      (arbitrary org-level config)
//    createdAt:   Timestamp (SERVER-OWNED)
//    updatedAt:   Timestamp (SERVER-OWNED)
//
//  /orgs/{orgId}/spaces/{spaceId}
//    name:        String
//    spaceType:   OrgSpaceKind  (Group|Team|Department|Ministry|Project|Event)
//    description: String?
//    memberCount: Int      (denormalized counter, SERVER-OWNED)
//    visibility:  SpaceVisibility
//    settings:    Map
//    createdBy:   String   (SERVER-OWNED on create)
//    createdAt:   Timestamp (SERVER-OWNED)
//    updatedAt:   Timestamp (SERVER-OWNED)
//
//  /orgs/{orgId}/spaces/{spaceId}/members/{uid}
//    role:        SpaceRole   (string enum)
//    joinedAt:    Timestamp   (SERVER-OWNED)
//    permissions: [String]    (fine-grained overrides, e.g. ["canPin", "canModerate"])
//
//  orgType ∈ {church, business, school, family, ministry, nonprofit, sports, network}
//  This enum is the primary behavior-driver for:
//    - UX labels   ("Ask a Pastor" vs "Ask an Expert" vs "Ask a Coach")
//    - AI routing  (SelectionIntentContract orgActionMap)
//    - Knowledge namespacing (KnowledgeContract vectorNamespace)
//    - Feature flag gating (church-only liturgical features, etc.)
//
// ─── Naming Conflicts ────────────────────────────────────────────────────────
//
//  CONFLICT: `OrganizationType` already exists in
//    ContextualExperiences/Models/ContextualExperienceModels.swift
//    Cases: church, school, university, ministry, business, enterprise, nonprofit,
//           prayerGroup, creatorCommunity, campus
//    This contract defines `OrgType` (NOT `OrganizationType`) to avoid a
//    redeclaration error. Agents must use OrgType; never re-import OrganizationType
//    for SpacesConnect surfaces.
//
//  CONFLICT: `ConversationOSOrgType` exists in
//    AMENAPP/ConversationOS/AmenConversationOSModels.swift
//    Cases: church, school, business, enterprise, ministry, creatorCommunity,
//           prayerGroup, studyGroup, leadershipTeam, event, operationalTeam
//    This contract does NOT alias or extend ConversationOSOrgType. They are
//    independent type systems for different features.
//
//  CONFLICT: `OrgSpaceType` exists in
//    OrgWorkspace/AmenOrgOnboardingFlow.swift
//    Cases: church, school, ministry, smallGroup, enterprise
//    That type drives the onboarding UI only. `OrgType` in this contract is the
//    Firestore-authoritative org classification. The onboarding wizard should
//    map OrgSpaceType → OrgType when persisting to Firestore.
//
//  CONFLICT: `SpaceMemberRole` + `CommunityRole` exist in
//    Spaces/SpacesModels.swift
//    This contract defines `SpaceRole` for OrgSpace membership. It is distinct
//    from SpaceMemberRole (which uses owner/admin/member) — SpaceRole adds
//    moderator and guest roles required by the org hierarchy.
//
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import FirebaseFirestore

// MARK: - OrgType

/// Primary org classification. Drives all per-use-case behavior downstream:
/// UX labels, AI routing, knowledge namespace, feature flags.
///
/// Named `OrgType` (not `OrganizationType`) to avoid conflict with
/// ContextualExperiences/Models/ContextualExperienceModels.swift.
enum OrgType: String, Codable, CaseIterable, Hashable {
    case church
    case business
    case school
    case family
    case ministry
    case nonprofit
    case sports
    case network
}

// MARK: - OrgSpaceKind

/// The functional type of a Space within an Org.
/// Distinct from `AmenSpace.SpaceType` (chat|bibleStudy|group|announcement)
/// which drives the Spaces module render mode.
/// OrgSpaceKind drives the org management surface (team channels, departments, etc.).
enum OrgSpaceKind: String, Codable, CaseIterable, Hashable {
    /// A general-purpose group (default, maps to any org type).
    case group           = "Group"
    /// A functional team (business/school/sports).
    case team            = "Team"
    /// An organizational department.
    case department      = "Department"
    /// A ministry or outreach unit (church/ministry/nonprofit).
    case ministry        = "Ministry"
    /// A time-bounded working group or task force.
    case project         = "Project"
    /// A single scheduled or recurring event-based Space.
    case event           = "Event"
}

// MARK: - SpaceVisibility

/// Visibility of an OrgSpace to non-members.
enum SpaceVisibility: String, Codable, CaseIterable, Hashable {
    /// Anyone in the org can discover and request to join.
    case open
    /// Discoverable but membership requires admin invite.
    case inviteOnly      = "invite_only"
    /// Hidden from listings; join only via direct link.
    case secret
}

// MARK: - SpaceRole

/// Membership role within a single OrgSpace.
///
/// Named `SpaceRole` (not `SpaceMemberRole`) to avoid conflict with
/// `SpaceMemberRole` in Spaces/SpacesModels.swift.
enum SpaceRole: String, Codable, CaseIterable, Hashable {
    /// Full ownership and settings control.
    case owner
    /// Can manage members and content but not delete the space.
    case admin
    /// Can moderate messages (pin, remove, mute members).
    case moderator
    /// Standard member with read/write access.
    case member
    /// Read-only observer (e.g. auditor, external reviewer).
    case guest
}

// MARK: - OrgSettings

/// Arbitrary org-level configuration persisted as a Firestore Map.
/// Well-known keys listed below; agents may extend.
///
/// Well-known keys:
///   allowGuestSpaces:     "true"|"false"  — whether guest-role spaces are permitted
///   defaultSpaceRole:     SpaceRole.rawValue — role assigned on org join
///   aiEnabled:            "true"|"false"  — whether Berean AI features are active org-wide
///   liturgicalCalendar:   "true"|"false"  — church-only: show liturgical features
///   denomination:         String          — church-only denomination hint for AI
typealias OrgSettings = [String: String]

// MARK: - OrgSpaceSettings

/// Arbitrary space-level configuration as a Firestore Map.
/// Well-known keys:
///   knowledgeIndexEnabled: "true"|"false" — whether content is indexed to Pinecone
///   autoArchiveAfterDays:  String         — event-only: auto-archive countdown
///   bereanAiEnabled:       "true"|"false" — whether Berean AI bar is visible in this space
typealias OrgSpaceSettings = [String: String]

// MARK: - OrgDocument

/// Top-level org document at `/orgs/{orgId}`.
struct OrgDocument: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    var name: String
    var orgType: OrgType
    var slug: String
    var verified: Bool
    var avatarURL: String?

    /// UID of the org owner. SERVER-OWNED on create.
    var ownerUid: String

    var settings: OrgSettings

    /// SERVER-OWNED timestamps.
    var createdAt: Timestamp
    var updatedAt: Timestamp

    var orgId: String { id ?? "" }

    static func == (lhs: OrgDocument, rhs: OrgDocument) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - OrgSpace

/// A Space inside an org at `/orgs/{orgId}/spaces/{spaceId}`.
///
/// Note: This is the *org management layer* Space — it coexists with
/// `AmenSpace` (in Spaces/SpacesModels.swift) which represents the
/// Slack-like chat/study room. A single OrgSpace may reference an
/// `AmenSpace` spaceId via `settings["amenSpaceId"]` to link them.
struct OrgSpace: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    var orgId: String
    var name: String
    var spaceType: OrgSpaceKind
    var description: String?

    /// Denormalized member count. SERVER-OWNED.
    var memberCount: Int

    var visibility: SpaceVisibility
    var settings: OrgSpaceSettings

    /// SERVER-OWNED on create.
    var createdBy: String
    var createdAt: Timestamp
    var updatedAt: Timestamp

    var spaceId: String { id ?? "" }

    static func == (lhs: OrgSpace, rhs: OrgSpace) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - OrgSpaceMembership

/// Membership record at `/orgs/{orgId}/spaces/{spaceId}/members/{uid}`.
/// `@DocumentID id` = the member's uid.
struct OrgSpaceMembership: Identifiable, Codable {
    @DocumentID var id: String?   // = member uid

    var role: SpaceRole

    /// Fine-grained capability overrides (e.g. ["canPin", "canModerate", "canPublish"]).
    var permissions: [String]

    /// SERVER-OWNED.
    var joinedAt: Timestamp

    var uid: String { id ?? "" }

    enum CodingKeys: String, CodingKey {
        case id, role, permissions, joinedAt
    }
}

// MARK: - OrgHierarchyServiceProtocol

/// Contract for reading/writing the Org + OrgSpace hierarchy.
/// Implementation in OrgHierarchyService (Phase 0+).
protocol OrgHierarchyServiceProtocol {
    /// Fetch a single org document.
    func fetchOrg(orgId: String) async throws -> OrgDocument

    /// Fetch all spaces within an org (paginated).
    func fetchSpaces(
        orgId: String,
        after cursor: DocumentSnapshot?
    ) async throws -> (spaces: [OrgSpace], cursor: DocumentSnapshot?, hasMore: Bool)

    /// Fetch membership for a uid across all org spaces.
    func fetchMemberships(
        orgId: String,
        uid: String
    ) async throws -> [OrgSpaceMembership]

    /// Create a new OrgSpace inside an org. Returns the generated spaceId.
    func createSpace(
        orgId: String,
        space: OrgSpace
    ) async throws -> String

    /// Add or update a member's role in an OrgSpace.
    func upsertMember(
        orgId: String,
        spaceId: String,
        membership: OrgSpaceMembership
    ) async throws

    /// Remove a member from an OrgSpace.
    func removeMember(
        orgId: String,
        spaceId: String,
        uid: String
    ) async throws
}
