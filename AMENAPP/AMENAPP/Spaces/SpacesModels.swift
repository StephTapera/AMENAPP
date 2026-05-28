// SpacesModels.swift
// AMENAPP — Spaces Data Layer
//
// Swift model types for AMEN Spaces:
// Community → Space → Thread/Study hierarchy.
//
// Schema authority: spaces-spec/00_MASTER_CONTRACT.md §2
// These structs are the iOS seam Agents B–F build against.
// Fields marked // SERVER-OWNED must never be written from client code.
//
// IMPORTANT: `communityId` on Space and Community refers to `amenCommunities`
// (a new top-level collection), NOT the legacy `/communities` Ark collection.

import Foundation
import FirebaseFirestore

// MARK: - Community

/// Represents an `amenCommunities/{communityId}` document.
/// A Community is the billing + branding identity: church, Bible study,
/// family, small group, or ministry. No "church" field names used.
struct SpacesCommunity: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    var name: String
    var handle: String
    var avatarURL: String?
    var ownerUserId: String          // SERVER-OWNED on create
    var stripeConnectAccountId: String?  // SERVER-OWNED
    var createdAt: Timestamp         // SERVER-OWNED

    // Convenience — not in Firestore, derived from @DocumentID
    var communityId: String { id ?? "" }

    static func == (lhs: SpacesCommunity, rhs: SpacesCommunity) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Community Member

/// `amenCommunities/{communityId}/members/{userId}`
struct CommunityMember: Identifiable, Codable {
    @DocumentID var id: String?   // = userId

    var role: CommunityRole
    var joinedAt: Timestamp

    enum CodingKeys: String, CodingKey {
        case id, role, joinedAt
    }
}

enum CommunityRole: String, Codable, CaseIterable {
    case owner, admin, member
}

// MARK: - Community Link

/// `amenCommunities/{communityId}/links/{linkId}`
/// Represents a cross-community sharing relationship.
/// Money never crosses a link (v1) — only access and conversation.
struct CommunityLink: Identifiable, Codable {
    @DocumentID var id: String?   // = linkId

    var otherCommunityId: String
    var status: LinkStatus
    var scope: String             // human-readable description of what is shared
    var createdBy: String         // userId
    var createdAt: Timestamp      // SERVER-OWNED
    var updatedAt: Timestamp      // SERVER-OWNED

    enum LinkStatus: String, Codable, CaseIterable {
        case pending, active, revoked
    }
}

// MARK: - Space

/// `spaces/{spaceId}`
/// A typed room inside a Community. Access gate lives here.
/// Render mode is driven by `type`.
struct AmenSpace: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    var communityId: String           // denormalized parent (→ amenCommunities)
    var type: SpaceType
    var title: String
    var description: String?
    var avatarURL: String?
    var createdBy: String             // SERVER-OWNED on create
    var createdAt: Timestamp          // SERVER-OWNED
    var accessPolicy: AccessPolicy
    var priceConfig: SpacePriceConfig?   // null when free
    var sharedWith: [String]          // communityIds denormalized for badge/banner render

    var spaceId: String { id ?? "" }

    // MARK: - Nested Types

    enum SpaceType: String, Codable, CaseIterable {
        case chat, bibleStudy, group, announcement
    }

    enum AccessPolicy: String, Codable, CaseIterable {
        case free, oneTime, recurring
        var isPaid: Bool { self != .free }
    }

    static func == (lhs: AmenSpace, rhs: AmenSpace) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Space Price Config

struct SpacePriceConfig: Codable, Equatable {
    var amountCents: Int
    var currency: String      // e.g. "usd"
    var interval: String?     // "month" | "year" | nil for one-time
}

// MARK: - Space Member

/// `spaces/{spaceId}/members/{userId}`
struct SpaceMember: Identifiable, Codable {
    @DocumentID var id: String?    // = userId

    var role: SpaceMemberRole
    var homeCommunityId: String    // "" = same community as Space; set for external members
    var access: SpaceAccess
    var joinedAt: Timestamp

    enum CodingKeys: String, CodingKey {
        case id, role, homeCommunityId, access, joinedAt
    }
}

enum SpaceMemberRole: String, Codable, CaseIterable {
    case owner, admin, member
}

enum SpaceAccess: String, Codable, CaseIterable {
    case granted, none
}

// MARK: - Thread

/// `spaces/{spaceId}/threads/{threadId}`
/// Used for `chat` and `group` Space types.
struct SpaceThread: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    var spaceId: String
    var title: String?
    var createdBy: String
    var createdAt: Timestamp
    var lastMessageAt: Timestamp

    var threadId: String { id ?? "" }

    static func == (lhs: SpaceThread, rhs: SpaceThread) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Message

/// `spaces/{spaceId}/threads/{threadId}/messages/{messageId}`
/// NEVER hard-delete. Use status = .deleted.
struct SpaceMessage: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    var authorId: String
    var body: String
    var createdAt: Timestamp
    var editedAt: Timestamp?
    var reactions: [String: [String]]   // emoji → [userId]
    var attachments: [SpaceMessageAttachment]
    var status: MessageStatus           // SERVER-OWNED for deletion

    var messageId: String { id ?? "" }

    enum MessageStatus: String, Codable {
        case active, deleted
        // NEVER call hard-delete — flip status to .deleted
    }

    static func == (lhs: SpaceMessage, rhs: SpaceMessage) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Message Attachment

struct SpaceMessageAttachment: Codable, Equatable {
    var type: String      // "image" | "audio" | "document" | "link"
    var url: String
    var metadata: [String: String]
}

// MARK: - Study

/// `spaces/{spaceId}/studies/{studyId}`
/// Used for `bibleStudy` Space type.
struct SpaceStudy: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    var spaceId: String
    var title: String
    var passageRefs: [String]    // e.g. ["John 3:16-17", "Romans 8:1"]
    var cadence: String?         // e.g. "weekly", "daily"
    var createdBy: String
    var createdAt: Timestamp

    var studyId: String { id ?? "" }

    static func == (lhs: SpaceStudy, rhs: SpaceStudy) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Study Block

/// `spaces/{spaceId}/studies/{studyId}/blocks/{blockId}`
/// Reuses the Smart Church Notes block model + render modes.
struct StudyBlock: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    // Core block fields (mirroring SCN block editor contract)
    var type: StudyBlockType
    var content: String
    var sortOrder: Int
    var createdBy: String
    var createdAt: Timestamp
    var updatedAt: Timestamp

    // Optional render-mode fields
    var scriptureRef: String?
    var renderMode: String?      // "default" | "large" | "callout"
    var metadata: [String: String]?

    var blockId: String { id ?? "" }

    enum StudyBlockType: String, Codable, CaseIterable {
        case text, scripture, question, reflection, prayer, image, audio, heading, divider
    }

    static func == (lhs: StudyBlock, rhs: StudyBlock) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Entitlement

/// `entitlements/{userId}_{spaceId}`
/// FLAT top-level collection. One row per {user, space}.
/// This is the paywall source of truth — gated with a single get() in rules.
/// NEVER hard-delete. Lapsed subscription → flip status to .expired.
struct SpaceEntitlement: Identifiable, Codable {
    @DocumentID var id: String?    // = "{userId}_{spaceId}"

    var userId: String
    var spaceId: String
    var status: EntitlementStatus
    var source: EntitlementSource
    var stripeSubId: String?       // SERVER-OWNED
    var expiresAt: Timestamp?      // nil = lifetime
    var updatedAt: Timestamp       // SERVER-OWNED

    var entitlementId: String { id ?? "\(userId)_\(spaceId)" }
    var isAccessible: Bool { status == .active || status == .grace }

    enum EntitlementStatus: String, Codable, CaseIterable {
        case active, grace, expired
    }

    enum EntitlementSource: String, Codable, CaseIterable {
        case purchase, grant
    }
}
