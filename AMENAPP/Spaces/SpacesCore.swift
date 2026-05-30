// SpacesCore.swift
// AMENAPP — Phase 0: Frozen Data Contracts
//
// All parallel agents (A–G) build against these types exclusively.
// Changing any public interface requires an orchestrator decision and
// an update to SPACES_CONTRACTS.md.
//
// Architecture rules:
//   - AMENSpace (Space.swift) is preserved as-is for backward compat.
//     AmenSpaceV2 is the Phase 0 forward contract.
//   - AmenSpaceType already exists in AmenSpacesIntelligenceModels.swift.
//     It is re-exported here via typealias; agents import SpacesCore only.
//   - Fields marked SERVER-OWNED must never be written from client code.
//     They are set exclusively by Cloud Function callables.
//   - All AI operations go through BereanCoreService, never direct API calls.

import Foundation
import FirebaseFirestore

// MARK: - Re-exports (single import point for agents)

/// Re-exported from AmenSpacesIntelligenceModels.swift — do not redefine.
typealias SpaceType = AmenSpaceType
typealias SpacePresenceMode = AmenPresenceUIMode

// MARK: - AMENSurface extension (add spaces surface)

extension AMENSurface {
    // Declared here to avoid modifying BereanCoreService.swift.
    // The raw value intentionally matches the pattern of existing cases.
    static let spacesRoom    = "spaces_room"
    static let spacesDM      = "spaces_dm"
    static let spacesDigest  = "spaces_digest"
}

// MARK: - Space Visibility

enum AmenSpaceVisibility: String, Codable, CaseIterable {
    case open       = "open"         // any signed-in user may join
    case gated      = "gated"        // request-to-join, admin approves
    case inviteOnly = "invite_only"  // must be invited
    case secret     = "secret"       // hidden from discovery, invite-only
}

// MARK: - Moderation Level

/// Drives GUARDIAN tuning per Space. Computed server-side from AmenSpaceCovenant.
enum AmenModerationLevel: String, Codable, CaseIterable {
    case open       = "open"        // minimal filtering
    case family     = "family"      // family-safe default
    case youth      = "youth"       // strict youth protection
    case academic   = "academic"    // scholarly discourse
    case restricted = "restricted"  // admin-moderated, invite-only

    var displayName: String {
        switch self {
        case .open:       return "Open"
        case .family:     return "Family Safe"
        case .youth:      return "Youth Safe"
        case .academic:   return "Academic"
        case .restricted: return "Restricted"
        }
    }

    var guardianSensitivity: Double {
        switch self {
        case .open:       return 0.50
        case .family:     return 0.65
        case .youth:      return 0.85
        case .academic:   return 0.60
        case .restricted: return 0.75
        }
    }
}

// MARK: - Space DNA

/// Generative configuration produced by Berean AI on Space creation.
/// Client reads for display. All writes go through createSpace / updateSpaceDNA callable.
struct AmenSpaceDNA: Codable {
    var defaultChannels: [AmenRoomTemplate]
    var rituals: [AmenSpaceRitual]
    var defaultRoles: [AmenSpaceRoleType]
    var suggestedReadingPlanId: String?
    var suggestedCovenantId: String?
    var version: Int
    var generatedAt: Date?
    var generatedBy: String?        // callable name / Berean agent ID — SERVER-OWNED
}

struct AmenRoomTemplate: Codable, Identifiable {
    var id: String
    var name: String
    var kind: AmenRoomKind
    var description: String
    var isPinned: Bool
}

struct AmenSpaceRitual: Codable, Identifiable {
    var id: String
    var name: String
    var description: String
    /// Cadence key: "weekly_sunday", "daily", "monthly_first", etc.
    var cadence: String
    var suggestedMode: AmenPresenceUIMode
}

// MARK: - Space Covenant

/// Community values that anchor GUARDIAN moderation tuning for this Space.
/// Client may write `values`, `prohibitedTopics`, `moderationLevel`.
/// Server owns `guardianThresholds`.
struct AmenSpaceCovenant: Codable {
    var values: [String]
    var prohibitedTopics: [String]
    var moderationLevel: AmenModerationLevel
    var lastAgreedBy: String?
    var lastAgreedAt: Date?
    var guardianThresholds: AmenGuardianThresholds? // SERVER-OWNED
}

struct AmenGuardianThresholds: Codable {
    var toxicityThreshold: Double   // 0..1  SERVER-OWNED
    var spamThreshold: Double       // SERVER-OWNED
    var requiresApproval: Bool      // SERVER-OWNED
}

// MARK: - Space Rhythm

/// Learned cadence used by the rhythm-aware notification engine (Agent F).
/// Entirely server-owned; client reads for display only.
struct AmenSpaceRhythm: Codable {
    var peakDaysOfWeek: [Int]           // 0=Sun..6=Sat  SERVER-OWNED
    var peakHoursOfDay: [Int]           // 0..23          SERVER-OWNED
    var averageDailyMessages: Double    // SERVER-OWNED
    var currentMode: AmenPresenceUIMode // SERVER-OWNED
    var lastComputedAt: Date?           // SERVER-OWNED
}

// MARK: - AmenSpaceV2 (Phase 0 Forward Contract)

/// The full Space model. AMENSpace (Space.swift) is kept for existing views.
/// All new views and all agents build against AmenSpaceV2.
struct AmenSpaceV2: Identifiable, Codable {
    @DocumentID var id: String?

    // Core identity
    var name: String
    var description: String
    var type: AmenSpaceType
    var visibility: AmenSpaceVisibility

    // Hierarchy / composition
    var parentSpaceId: String?      // non-nil → child Space in a composed hierarchy
    var orgId: String?              // non-nil → org-scoped Space
    var churchId: String?           // non-nil → church-scoped Space

    // Intelligence namespace
    /// Pinecone / SemanticEmbeddingService namespace for per-Space vector isolation.
    /// Assigned by createSpace callable. SERVER-OWNED — never write from client.
    var memoryNamespace: String?

    // Generative configuration
    var dna: AmenSpaceDNA?
    var covenant: AmenSpaceCovenant?
    var theologyDocId: String?      // ref to the Space's living theology/story doc
    var rhythm: AmenSpaceRhythm?

    // Metadata
    var memberCount: Int
    var createdBy: String
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?            // soft delete sentinel

    // Safety — SERVER-OWNED
    var safetyStatus: String?       // "active" | "flagged" | "suspended"  SERVER-OWNED
    var guardianCovenantId: String? // GUARDIAN moderation config ref         SERVER-OWNED

    // Discovery
    var coverImageURL: String?
    var aiDetectedTopics: [String]  // SERVER-OWNED

    // Bridge — used for compatibility with AMENSpace-based UI
    var weeklyActiveUsers: Int?

    var isDeleted: Bool { deletedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, name, description, type, visibility
        case parentSpaceId, orgId, churchId, memoryNamespace
        case dna, covenant, theologyDocId, rhythm
        case memberCount, createdBy, createdAt, updatedAt, deletedAt
        case safetyStatus, guardianCovenantId
        case coverImageURL, aiDetectedTopics, weeklyActiveUsers
    }

    /// Bridge: convert a legacy AMENSpace for display in V2 surfaces.
    static func from(_ legacy: AMENSpace) -> AmenSpaceV2 {
        AmenSpaceV2(
            name: legacy.name,
            description: legacy.description,
            type: .churchMinistry,
            visibility: .open,
            memberCount: legacy.memberCount,
            createdBy: "",
            createdAt: legacy.createdAt,
            coverImageURL: legacy.coverImageURL,
            aiDetectedTopics: legacy.aiDetectedTopics,
            weeklyActiveUsers: legacy.weeklyActiveUsers
        )
    }
}

// MARK: - Room Kind

enum AmenRoomKind: String, Codable, CaseIterable {
    case persistent    = "persistent"     // standard channel
    case ephemeral     = "ephemeral"      // auto-dissolves → Living Memory artifact
    case announcements = "announcements"  // admin-post only
    case prayerWall    = "prayer_wall"
    case studyRoom     = "study_room"
    case privateRoom   = "private_room"   // role-gated

    var icon: String {
        switch self {
        case .persistent:    return "bubble.left.and.bubble.right.fill"
        case .ephemeral:     return "timer"
        case .announcements: return "megaphone.fill"
        case .prayerWall:    return "hands.sparkles.fill"
        case .studyRoom:     return "books.vertical.fill"
        case .privateRoom:   return "lock.fill"
        }
    }
}

// MARK: - Room

struct AmenRoom: Identifiable, Codable {
    @DocumentID var id: String?
    var spaceId: String
    var name: String
    var kind: AmenRoomKind
    var description: String?
    var requiredRole: AmenSpaceRoleType?    // nil = any member may read/post
    var createdBy: String
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?
    var isPinned: Bool
    var isArchived: Bool
    var messageCount: Int

    // Ephemeral rooms only
    var expiresAt: Date?
    /// ID of the Living Memory node created on dissolution. SERVER-OWNED.
    var summaryArtifactId: String?

    // Safety — SERVER-OWNED
    var safetyStatus: String?

    var isDeleted: Bool { deletedAt != nil }
    var isEphemeral: Bool { kind == .ephemeral }

    enum CodingKeys: String, CodingKey {
        case id, spaceId, name, kind, description, requiredRole
        case createdBy, createdAt, updatedAt, deletedAt
        case isPinned, isArchived, messageCount
        case expiresAt, summaryArtifactId, safetyStatus
    }
}

// MARK: - Room Post / Message

struct AmenRoomPost: Identifiable, Codable {
    @DocumentID var id: String?
    var roomId: String
    var spaceId: String
    var authorId: String
    var body: String
    var mediaRefs: [String]
    var mentionedUserIds: [String]
    var replyToId: String?
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    // Server-owned safety & intelligence — never set from client
    var guardianStatus: String?     // "approved" | "flagged" | "removed"  SERVER-OWNED
    var embeddingRef: String?       // Pinecone vector ref                  SERVER-OWNED
    var aiTopics: [String]          // extracted topics                     SERVER-OWNED
    var scriptureRefs: [String]     // detected scripture refs              SERVER-OWNED

    var isDeleted: Bool { deletedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, roomId, spaceId, authorId, body
        case mediaRefs, mentionedUserIds, replyToId
        case createdAt, updatedAt, deletedAt
        case guardianStatus, embeddingRef, aiTopics, scriptureRefs
    }
}

// MARK: - Roles

enum AmenSpaceRoleType: String, Codable, CaseIterable {
    // Universal
    case owner              = "owner"
    case admin              = "admin"
    case moderator          = "moderator"
    case member             = "member"
    case guest              = "guest"

    // Ministry-specific
    case pastor             = "pastor"
    case elder              = "elder"
    case deacon             = "deacon"
    case worshipLeader      = "worship_leader"

    // Education
    case teacher            = "teacher"
    case student            = "student"
    case teachingAssistant  = "teaching_assistant"

    // Community
    case mentor             = "mentor"
    case mentee             = "mentee"
    case volunteer          = "volunteer"
    case prayerLeader       = "prayer_leader"

    // Creator / Business
    case creator            = "creator"
    case contributor        = "contributor"

    var canPost: Bool               { self != .guest }
    var canModerate: Bool           { [.owner, .admin, .moderator, .pastor, .elder].contains(self) }
    var canManageMembers: Bool      { [.owner, .admin, .pastor].contains(self) }
    var canManageSpace: Bool        { [.owner, .admin].contains(self) }

    var displayName: String {
        switch self {
        case .owner:             return "Owner"
        case .admin:             return "Admin"
        case .moderator:         return "Moderator"
        case .member:            return "Member"
        case .guest:             return "Guest"
        case .pastor:            return "Pastor"
        case .elder:             return "Elder"
        case .deacon:            return "Deacon"
        case .worshipLeader:     return "Worship Leader"
        case .teacher:           return "Teacher"
        case .student:           return "Student"
        case .teachingAssistant: return "Teaching Assistant"
        case .mentor:            return "Mentor"
        case .mentee:            return "Mentee"
        case .volunteer:         return "Volunteer"
        case .prayerLeader:      return "Prayer Leader"
        case .creator:           return "Creator"
        case .contributor:       return "Contributor"
        }
    }

    var icon: String {
        switch self {
        case .owner:             return "crown.fill"
        case .admin:             return "shield.fill"
        case .moderator:         return "eye.fill"
        case .member:            return "person.fill"
        case .guest:             return "person.badge.clock"
        case .pastor:            return "cross.fill"
        case .elder:             return "star.fill"
        case .deacon:            return "hands.sparkles.fill"
        case .worshipLeader:     return "music.note"
        case .teacher:           return "graduationcap.fill"
        case .student:           return "books.vertical.fill"
        case .teachingAssistant: return "person.2.fill"
        case .mentor:            return "person.wave.2.fill"
        case .mentee:            return "person.fill"
        case .volunteer:         return "hand.raised.fill"
        case .prayerLeader:      return "hands.sparkles.fill"
        case .creator:           return "paintbrush.fill"
        case .contributor:       return "pencil"
        }
    }
}

struct AmenSpaceRole: Identifiable, Codable {
    @DocumentID var id: String?
    var spaceId: String
    var userId: String
    var role: AmenSpaceRoleType
    var assignedBy: String
    var assignedAt: Date?
    var expiresAt: Date?

    var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return Date() > exp
    }
}

// MARK: - Spiritual Gifts

enum AmenGiftType: String, Codable, CaseIterable {
    case teaching       = "teaching"
    case leadership     = "leadership"
    case mercy          = "mercy"
    case service        = "service"
    case giving         = "giving"
    case encouragement  = "encouragement"
    case wisdom         = "wisdom"
    case knowledge      = "knowledge"
    case faith          = "faith"
    case intercession   = "intercession"
    case evangelism     = "evangelism"
    case administration = "administration"
    case discernment    = "discernment"
    case hospitality    = "hospitality"
    case prophecy       = "prophecy"
    case worship        = "worship"

    var displayName: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .teaching:       return "text.book.closed.fill"
        case .leadership:     return "person.badge.shield.checkmark.fill"
        case .mercy:          return "heart.fill"
        case .service:        return "hand.raised.fill"
        case .giving:         return "gift.fill"
        case .encouragement:  return "sun.max.fill"
        case .wisdom:         return "scale.3d"
        case .knowledge:      return "magnifyingglass.circle.fill"
        case .faith:          return "cross.fill"
        case .intercession:   return "hands.sparkles.fill"
        case .evangelism:     return "megaphone.fill"
        case .administration: return "gearshape.fill"
        case .discernment:    return "eye.fill"
        case .hospitality:    return "house.fill"
        case .prophecy:       return "sparkles"
        case .worship:        return "music.note"
        }
    }
}

// MARK: - Scoped Profile

/// The controlled identity projection a user presents inside a specific Space.
/// User-writable (their own profile only). Never cross-Space readable without a grant.
struct AmenScopedProfile: Codable {
    var displayName: String?            // override global display name in this Space
    var bio: String?                    // Space-specific bio
    var visibleGifts: [AmenGiftType]    // gifts the user chooses to surface here
    var isAnonymous: Bool               // present as "Anonymous Member"
    var showsPrayerActivity: Bool       // opt-in: show "Praying" presence
    var showsStudyActivity: Bool        // opt-in: show "Studying" presence
    var joinedAt: Date?

    static let defaultOpen = AmenScopedProfile(
        displayName: nil,
        bio: nil,
        visibleGifts: [],
        isAnonymous: false,
        showsPrayerActivity: false,
        showsStudyActivity: false
    )
}

// MARK: - Membership V2

enum AmenMembershipStatus: String, Codable {
    case active    = "active"
    case pending   = "pending"    // awaiting admin approval
    case invited   = "invited"    // invitation sent, not yet accepted
    case suspended = "suspended"  // admin action
    case banned    = "banned"     // admin action
    case left      = "left"       // voluntarily left
}

struct AmenSpaceMembershipV2: Identifiable, Codable {
    @DocumentID var id: String?
    var spaceId: String
    var userId: String
    var status: AmenMembershipStatus
    var roles: [AmenSpaceRoleType]
    var gifts: [AmenGiftType]
    var scopedProfile: AmenScopedProfile
    var joinedAt: Date?
    var lastSeenAt: Date?
    var notificationsEnabled: Bool

    // Server-owned — never written by client
    var contributionScore: Double?  // SERVER-OWNED
    var trustLevel: String?         // "new" | "established" | "trusted"  SERVER-OWNED

    var hasAdminAccess: Bool        { roles.contains(where: \.canManageSpace) }
    var hasModerationAccess: Bool   { roles.contains(where: \.canModerate) }
    var canPost: Bool               { roles.contains(where: \.canPost) && status == .active }

    enum CodingKeys: String, CodingKey {
        case id, spaceId, userId, status, roles, gifts, scopedProfile
        case joinedAt, lastSeenAt, notificationsEnabled
        case contributionScore, trustLevel
    }
}

// MARK: - Presence

enum AmenSpacePresenceState: String, Codable, CaseIterable {
    case available    = "available"
    case studying     = "studying"
    case praying      = "praying"
    case inEvent      = "in_event"
    case hosting      = "hosting"
    case inClass      = "in_class"
    case mentoring    = "mentoring"
    case doNotDisturb = "do_not_disturb"
    case offline      = "offline"

    var icon: String {
        switch self {
        case .available:    return "circle.fill"
        case .studying:     return "books.vertical.fill"
        case .praying:      return "hands.sparkles.fill"
        case .inEvent:      return "calendar.badge.checkmark"
        case .hosting:      return "house.fill"
        case .inClass:      return "graduationcap.fill"
        case .mentoring:    return "person.wave.2.fill"
        case .doNotDisturb: return "moon.fill"
        case .offline:      return "circle"
        }
    }

    var displayName: String {
        switch self {
        case .available:    return "Available"
        case .studying:     return "Studying"
        case .praying:      return "Praying"
        case .inEvent:      return "In Event"
        case .hosting:      return "Hosting"
        case .inClass:      return "In Class"
        case .mentoring:    return "Mentoring"
        case .doNotDisturb: return "Do Not Disturb"
        case .offline:      return "Offline"
        }
    }
}

struct AmenSpacePresence: Codable {
    var userId: String
    var spaceId: String
    var state: AmenSpacePresenceState
    var updatedAt: Date?
    var expiresAt: Date?    // auto-revert to offline after TTL (server enforces)
}

// MARK: - Space AI Context

/// Passed to BereanCoreService calls that are Space-scoped.
/// Agents construct this; BereanCoreService routes it.
struct AmenSpaceAIContext {
    let spaceId: String
    let roomId: String?
    let requestingUserId: String
    /// Per-Space Pinecone namespace from AmenSpaceV2.memoryNamespace.
    /// Nil if the Space was created before embedding seeding was deployed.
    let memoryNamespace: String?
    let spaceType: AmenSpaceType
    let moderationLevel: AmenModerationLevel

    var isEmbeddingAvailable: Bool { memoryNamespace != nil }
}

// MARK: - Cloud Function Callable Names (Phase 0 contracts)

/// Canonical callable names. All Spaces write operations go through these.
/// Never write Spaces data directly from Firestore client.
enum SpacesCallable: String {
    case createSpace         = "createSpace"
    case joinSpace           = "joinSpace"
    case leaveSpace          = "leaveSpace"
    case updateSpaceSettings = "updateSpaceSettings"
    case updateSpaceDNA      = "updateSpaceDNA"
    case updateSpaceCovenant = "updateSpaceCovenant"
    case postToRoom          = "postToRoom"
    case deleteRoomPost      = "deleteRoomPost"
    case createRoom          = "createRoom"
    case archiveRoom         = "archiveRoom"
    case updateMemberRole    = "updateMemberRole"
    case updateScopedProfile = "updateScopedProfile"
    case updatePresence      = "updatePresence"
    case bereanSpaceInvoke   = "bereanSpaceInvoke"     // @mention / DM Berean in a Space
    case dissolveEphemeralRoom = "dissolveEphemeralRoom"
    case generateSpaceDNA    = "generateSpaceDNA"      // AI DNA generation
    case createSpacePrayerRequest = "createSpacePrayerRequest"

    // Spaces v2 — Community & Monetization
    case createCommunity              = "createCommunity"
    case linkCommunity                = "linkCommunity"           // Agent F uses
    case acceptCommunityLink          = "acceptCommunityLink"     // Agent F uses
    case revokeCommunityLink          = "revokeCommunityLink"     // Agent F uses
    case purchaseSpaceAccess          = "purchaseSpaceAccess"     // Agent E uses
    case grantAccess                  = "grantAccess"             // Agent E uses (admin comp)
    case revokeAccess                 = "revokeAccess"            // Agent E uses
    case stripeWebhookEntitlement     = "stripeWebhookEntitlement" // backend only, documents intent
    case reviewSpace                  = "reviewSpace"               // admin: approve/reject pendingReview spaces
}

// MARK: - Space Body Renderer Protocol

protocol SpaceBodyRenderer {
    static var renderedType: SpaceV2Type { get }
}
