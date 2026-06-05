// DiscussionModels.swift
// AMEN App — Community OS / Discussion OS (A6)
//
// Domain models for Discussion Rooms and their provenance.
// These types are separate from the legacy DiscussionThread* types in DiscussionThreadView.swift,
// which represent post-level comment threads.
// DiscussionRoom represents a structured room that can be spawned from ANY canonical object.
//
// Contract references:
//   C1 §5 (Discussion schema), C2 §4.2 (Room type mapping), C2 §2.3 (privacy defaults)
//   OQ-15: Named SpawnProvenance here to avoid collision with ONEProvenanceLabel.

import Foundation

// MARK: - SpawnProvenance

/// Immutable record of which canonical object a spawnable object was created from.
/// Written at creation time by the server and never updated.
/// Named SpawnProvenance (not Provenance) to avoid collision with ONEProvenanceLabel.
/// Mirrors the C1 §3a Provenance struct definition.
struct SpawnProvenance: Codable, Equatable, Hashable {
    /// ObjectType raw value of the source, e.g. "post", "bereanInsight", "direct"
    let sourceType: String
    /// Firestore document path of the source object, e.g. "/posts/abc123"; nil for root objects
    let sourceRef: String?
    /// UID of the original object's owner; nil when source type does not have an owner
    let sourceOwnerId: String?
    /// C2 Intent raw value that triggered the spawn, e.g. "discuss", "pray", "direct"
    let intent: String
    /// Server-assigned creation timestamp — never set by the iOS client
    let createdAt: Date

    /// Human-readable display name for the source type, used in the provenance banner.
    var sourceTypeDisplayName: String {
        switch sourceType {
        case "post":                 return "Post"
        case "prayer", "prayer_request": return "Prayer Request"
        case "berean_insight":       return "Berean Insight"
        case "church_note":          return "Church Note"
        case "sermon", "sermon_clip": return "Sermon"
        case "event":                return "Event"
        case "scripture_reference":  return "Scripture"
        case "space_object":         return "Space"
        case "organization_object":  return "Organization"
        case "media_object":         return "Media"
        case "message":              return "Message"
        case "job":                  return "Job"
        case "mentorship_request":   return "Mentorship"
        case "direct":               return "Direct"
        default:                     return sourceType.capitalized
        }
    }

    /// SF Symbol name for the source type icon shown in the provenance banner.
    var sourceTypeSystemImage: String {
        switch sourceType {
        case "post":                 return "doc.richtext"
        case "prayer", "prayer_request": return "hands.sparkles"
        case "berean_insight":       return "sparkle"
        case "church_note":          return "note.text"
        case "sermon", "sermon_clip": return "film.stack"
        case "event":                return "calendar"
        case "scripture_reference":  return "book.closed"
        case "space_object":         return "square.stack.3d.up"
        case "organization_object":  return "building.columns"
        case "media_object":         return "photo.on.rectangle"
        case "message":              return "bubble.left"
        case "job":                  return "briefcase"
        case "mentorship_request":   return "person.badge.key"
        default:                     return "link"
        }
    }
}

// MARK: - DiscussionRoomType

/// The functional type of a discussion room.
/// Maps to C2 §4.2 room type mapping and C1 ObjectDiscussionRoom.roomType.
enum DiscussionRoomType: String, Codable, CaseIterable {
    case general        = "discussion"
    case bibleStudy     = "study_group"
    case prayer         = "prayer"
    case mentorship     = "mentorship"
    case planning       = "planning"
    case supportGroup   = "support_group"
    case church         = "church"
    case leadership     = "leadership"

    var displayName: String {
        switch self {
        case .general:      return "Discussion"
        case .bibleStudy:   return "Bible Study"
        case .prayer:       return "Prayer"
        case .mentorship:   return "Mentorship"
        case .planning:     return "Planning"
        case .supportGroup: return "Support Group"
        case .church:       return "Church"
        case .leadership:   return "Leadership"
        }
    }

    var systemImage: String {
        switch self {
        case .general:      return "bubble.left.and.bubble.right"
        case .bibleStudy:   return "book.closed"
        case .prayer:       return "hands.sparkles"
        case .mentorship:   return "person.badge.key"
        case .planning:     return "list.bullet.clipboard"
        case .supportGroup: return "person.3"
        case .church:       return "building.columns"
        case .leadership:   return "crown"
        }
    }
}

// MARK: - DiscussionRoom

/// A structured discussion room that can be anchored on any canonical object.
/// Stored at: /objectDiscussionRooms/{canonicalObjectId}/rooms/{roomId}
/// See C1 §5 (Discussion schema).
struct DiscussionRoom: Identifiable, Codable {
    /// Firestore document ID for this room
    let id: String
    /// Human-readable title of the discussion room
    let title: String
    /// The functional type of this room — drives UI treatment and moderation
    let discussionType: DiscussionRoomType
    /// UID of the user who created / hosts the room
    let hostId: String
    /// UIDs of all current participants
    var participantIds: [String]
    /// ContentAudience raw value — e.g. "space_members", "church_only", "public_feed"
    /// Stored as String (not the enum) so this file has no ContentOSModels dependency.
    let audience: String
    /// Denormalized thread count — updated by CF trigger on message create/delete
    var threadCount: Int
    /// Short AI-generated or host-written summary of the room's current discussion state
    var summaryText: String?
    /// Immutable provenance block — present when the room was spawned from another object
    let provenance: SpawnProvenance?
    /// When true, the room is read-only; new messages cannot be posted
    var isLocked: Bool
    /// Firestore Timestamp encoded as Date; written server-side
    let createdAt: Date

    // MARK: - Computed

    /// True when this room was spawned from another object (not created directly)
    var hasProvenance: Bool { provenance != nil }

    /// True when there are participants beyond just the host
    var hasParticipants: Bool { participantIds.count > 1 }
}
