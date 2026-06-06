// AmenDiscussionModels.swift
// AMEN App — Community OS / Discussion OS (A6) Phase 2
//
// Extended domain models for the full Discussion OS.
// These types ADD to (never replace) the existing DiscussionModels.swift types.
//
// Relationship map:
//   DiscussionRoom       (DiscussionModels.swift)   → ObjectHub-scoped stub room
//   AmenDiscussionRoom   (this file)                → Full 7-type room with privacy,
//                                                     participation control, moderation hooks
//   DiscussionMessage    (this file)                → Per-message model with threading + moderation
//
// Contract references:
//   C1 §5 (AmenDiscussion schema), C2 §4.2 (room type mapping),
//   C2 §2.3 (privacy defaults), C5 (security rules), C1-new §3 (SpawnProvenance)
//
// SpawnProvenance is defined in CommunityObjectTypes.swift — imported transitively.
// SpawnableObject is defined in AmenCoreModels.swift.

import Foundation
import FirebaseFirestore

// MARK: - AmenDiscussionRoomType

/// Seven functional room types for the full Discussion OS.
/// Distinct from `DiscussionRoomType` (AmenCoreModels.swift, 3 cases) and
/// `DiscussionRoom.DiscussionRoomType` in DiscussionModels.swift — this is the
/// authoritative Phase 2 taxonomy mapping to C2 §4.2.
enum AmenDiscussionRoomType: String, Codable, CaseIterable, Hashable, Sendable {
    case general         = "general"
    case bibleStudy      = "bible_study"
    case prayer          = "prayer"
    case mentorship      = "mentorship"
    case planning        = "planning"
    case supportGroup    = "support_group"
    case churchLeadership = "church_leadership"

    // MARK: Display

    var displayName: String {
        switch self {
        case .general:          return "Discussion"
        case .bibleStudy:       return "Bible Study"
        case .prayer:           return "Prayer"
        case .mentorship:       return "Mentorship"
        case .planning:         return "Planning"
        case .supportGroup:     return "Support Group"
        case .churchLeadership: return "Leadership"
        }
    }

    /// SF Symbol representing this room type in chips and list rows.
    var systemImage: String {
        switch self {
        case .general:          return "bubble.left.and.bubble.right"
        case .bibleStudy:       return "book.closed"
        case .prayer:           return "hands.sparkles"
        case .mentorship:       return "person.badge.key"
        case .planning:         return "list.bullet.clipboard"
        case .supportGroup:     return "person.3"
        case .churchLeadership: return "crown"
        }
    }

    /// Default privacy level per C2 §2.3.
    /// General and Bible Study default public; sensitive types default private.
    var defaultPrivacyLevel: AmenDiscussionPrivacyLevel {
        switch self {
        case .general:          return .public
        case .bibleStudy:       return .public
        case .prayer:           return .church
        case .mentorship:       return .trustedCircle
        case .planning:         return .space
        case .supportGroup:     return .private
        case .churchLeadership: return .private
        }
    }

    /// When true, the Firestore security rule requires verified membership before read/write.
    /// Enforcement is server-side; this flag drives UI gating only.
    var requiresMembership: Bool {
        switch self {
        case .general, .bibleStudy:
            return false
        case .prayer, .planning:
            return false
        case .mentorship, .supportGroup, .churchLeadership:
            return true
        }
    }

    /// Placeholder text for the reply composer for each room type.
    var composerPlaceholder: String {
        switch self {
        case .general:          return "Share your perspective…"
        case .bibleStudy:       return "Share your insight…"
        case .prayer:           return "Share a prayer…"
        case .mentorship:       return "Ask or share…"
        case .planning:         return "Add to the plan…"
        case .supportGroup:     return "You're safe here…"
        case .churchLeadership: return "Share with the team…"
        }
    }
}

// MARK: - AmenDiscussionPrivacyLevel

/// Who can read and participate in an AmenDiscussionRoom.
/// Enforced server-side by Firestore security rules (C5).
/// `trustedCircle` — membership list enforced server-side only; never computed client-side.
enum AmenDiscussionPrivacyLevel: String, Codable, CaseIterable, Hashable, Sendable {
    /// Visible and joinable by all authenticated users.
    case `public`      = "public"
    /// Visible and joinable by verified members of the linked church.
    case church        = "church"
    /// Visible and joinable by members of the linked Space/Covenant.
    case space         = "space"
    /// Visible and joinable only by users in `participantIds`.
    /// Membership is enforced by Firestore rules — never derived client-side.
    case trustedCircle = "trusted_circle"
    /// Visible only to the creator and moderators.
    case `private`     = "private"

    var displayName: String {
        switch self {
        case .public:       return "Public"
        case .church:       return "Church"
        case .space:        return "Space Members"
        case .trustedCircle: return "Trusted Circle"
        case .private:      return "Private"
        }
    }

    var systemImage: String {
        switch self {
        case .public:       return "globe"
        case .church:       return "building.columns"
        case .space:        return "square.stack.3d.up"
        case .trustedCircle: return "person.2.badge.key"
        case .private:      return "lock"
        }
    }
}

// MARK: - AmenDiscussionParticipationControl

/// How new messages enter the room.
enum AmenDiscussionParticipationControl: String, Codable, Hashable, Sendable {
    /// Anyone who can read the room can post immediately.
    case open       = "open"
    /// New messages are held pending moderator approval before becoming visible.
    case moderated  = "moderated"
    /// Only moderator-approved participants (in `participantIds`) may post.
    case curated    = "curated"
    /// No replies allowed. Announcement-only — host posts only.
    case readonly   = "readonly"

    var displayName: String {
        switch self {
        case .open:      return "Open"
        case .moderated: return "Moderated"
        case .curated:   return "Curated"
        case .readonly:  return "Read Only"
        }
    }
}

// MARK: - DiscussionMessage

/// A single message in an AmenDiscussionRoom.
/// Stored at: /amenDiscussionRooms/{roomId}/messages/{messageId}
///
/// Threading: replies set `parentMessageId` to the parent message's id.
/// Moderation: when `isModerated == true`, the message body is replaced by
/// a "Pending review" placeholder in the UI — the raw body is only visible
/// to the author and moderators.
/// Soft-delete: `isDeleted: true` — document is never hard-deleted.
struct DiscussionMessage: Codable, Identifiable, Sendable {
    /// Firestore document ID
    var id: String
    /// Parent room document ID
    var discussionId: String
    /// Firebase Auth UID of the message author
    var authorId: String
    /// Message body text — max 2 000 characters (enforced by CF)
    var body: String
    /// Non-nil when this message is a direct reply to another message (threading)
    var parentMessageId: String?
    /// Denormalised reply count updated by a CF trigger on message create/delete
    var replyCount: Int
    /// True when the message is held for moderator review.
    /// When true, the UI shows a "Pending review" placeholder to all users except
    /// the author and moderators.
    var isModerated: Bool
    /// Shown only to the author and moderators when `isModerated == true`
    var moderationNote: String?
    /// Non-nil when this message was spawned from (or cites) another canonical object,
    /// e.g. a Berean insight or a Scripture reference.
    var provenance: SpawnProvenance?
    /// Server-assigned; never written by the client.
    var createdAt: Date
    /// Server-assigned; never written by the client.
    var updatedAt: Date
    /// Soft-delete flag. Always `false` on creation; set to `true` on delete.
    var isDeleted: Bool
    /// References to media objects attached to this message (mediaObject IDs or Storage URLs).
    var attachmentRefs: [String]

    // MARK: - Computed

    /// True if this message is a threaded reply to another message.
    var isReply: Bool { parentMessageId != nil }

    /// Returns the display body for the given viewer.
    /// Moderators and the author see the raw body even when moderated.
    func visibleBody(viewerId: String, isModerator: Bool) -> String {
        if isModerated && viewerId != authorId && !isModerator {
            return "This message is pending review."
        }
        return body
    }
}

// MARK: - AmenDiscussionRoom

/// A full structured discussion room anchored on any canonical object.
/// Stored at: /amenDiscussionRooms/{roomId}
///
/// This is the Phase 2 richer counterpart to `DiscussionRoom` (DiscussionModels.swift).
/// `DiscussionRoom` is retained for ObjectHub-scoped rooms; `AmenDiscussionRoom` is used
/// for the full Discussion OS surface (AmenDiscussionRoomListView + AmenDiscussionThreadView).
///
/// Conforms to `SpawnableObject` (AmenCoreModels.swift) — provenance is required and
/// immutable after creation.
struct AmenDiscussionRoom: AmenObject, SpawnableObject, Hashable {
    /// Firestore document ID
    var id: String
    /// Human-readable title set by the creator
    var title: String
    /// Optional longer description of the room's purpose
    var description: String
    /// Functional type driving UI treatment, moderation defaults, and privacy defaults
    var type: AmenDiscussionRoomType
    /// Privacy level: who can read and join
    var privacyLevel: AmenDiscussionPrivacyLevel
    /// Participation control: how messages enter the room
    var participationControl: AmenDiscussionParticipationControl
    /// Firestore document path of the object that spawned this room, e.g. "/posts/abc"
    var sourceContextRef: String?
    /// AmenObjectType raw value of the spawning object, e.g. "post" or "event"
    var sourceContextType: String?
    /// Immutable provenance block. Nil for rooms created without a source object.
    /// When non-nil, sourceType "direct" denotes a root-created room.
    var provenance: SpawnProvenance?
    /// UIDs of participants explicitly added to this room.
    /// Used for `trustedCircle` and `curated` access enforcement.
    /// Never shown as a public count in the UI — anti-vanity.
    var participantIds: [String]
    /// Denormalised message count. Updated by a CF trigger.
    /// NOT shown publicly in the UI — anti-engagement rule.
    var messageCount: Int
    /// Timestamp of the most recent message, used for sort order.
    var lastMessageAt: Date?
    /// Short AI-generated summary from Berean (nil until Berean has processed the room)
    var summaryText: String?
    /// Berean-generated suggested follow-up questions shown as chips below the thread
    var followUpPrompts: [String]
    /// UIDs of moderators for this room
    var moderatorIds: [String]
    /// Firebase Auth UID of the creating user
    var createdBy: String
    /// Server-assigned creation timestamp
    var createdAt: Date
    /// Server-assigned last-updated timestamp
    var updatedAt: Date
    /// Soft-delete flag
    var isDeleted: Bool
    /// When true, the room is pinned at the top of the list for its context
    var isPinned: Bool

    // MARK: - Computed

    /// True when this room was spawned from another object (non-direct provenance)
    var hasProvenance: Bool {
        guard let p = provenance else { return false }
        return p.sourceType != "direct"
    }

    /// True when there are explicitly-added participants beyond the creator
    var hasParticipants: Bool { participantIds.count > 1 }

    /// True when the room is read-only (readonly control or deleted)
    var isReadOnly: Bool {
        participationControl == .readonly || isDeleted
    }
}

// AmenDiscussionRoom conforms to AmenObject + SpawnableObject in its primary declaration.
