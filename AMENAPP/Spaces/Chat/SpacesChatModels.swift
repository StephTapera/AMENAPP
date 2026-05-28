// SpacesChatModels.swift
// AMENAPP — Spaces v2 Chat Layer (Agent B)
//
// Data contracts for thread lists, messages, reactions, typing indicators,
// and read state. These are the canonical Spaces Chat models; do not redefine
// in any other agent-owned file.
//
// Naming note: types are prefixed "SpacesChat" to avoid collision with
// pre-existing MessageModels.swift (TypingIndicator) and
// AMENAPP/Spaces/SpacesModels.swift (SpaceMessage, SpaceMessageAttachment).
//
// Firestore paths:
//   spaces/{spaceId}/threads/{threadId}
//   spaces/{spaceId}/threads/{threadId}/messages/{messageId}
//   spaces/{spaceId}/threads/{threadId}/readStates/{userId}
//   RTDB:  typing/{spaceId}/{threadId}/{userId}

import Foundation

// MARK: - Thread Filter

/// Drives the All / VIP / Unreads / External tab row in the thread list.
/// Agent C imports `ThreadFilter` from this module via `FilterTabData.swift`.
enum ThreadFilter: String, CaseIterable, Identifiable {
    case all      = "all"
    case vip      = "vip"
    case unreads  = "unreads"
    case external = "external"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:      return "All"
        case .vip:      return "VIP"
        case .unreads:  return "Unreads"
        case .external: return "External"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .all:      return "All threads"
        case .vip:      return "VIP threads"
        case .unreads:  return "Unread threads"
        case .external: return "Threads with external members"
        }
    }
}

// MARK: - Thread Summary

/// Represents one thread row in the thread list.
/// Powers All / Unreads (unreadCount > 0) / External (hasExternalMembers) filters.
/// VIP filtering is applied by `SpacesChatService` against `vipThreadIds`.
struct ThreadSummary: Codable, Identifiable {
    var id: String
    var spaceId: String
    var title: String
    var createdBy: String
    var createdAt: Date
    var lastMessageAt: Date
    var lastMessagePreview: String?
    var unreadCount: Int
    /// true when at least one member of this thread has a non-nil homeCommunityId
    var hasExternalMembers: Bool
}

// MARK: - SpacesChatMessage

/// A single message inside a Spaces v2 thread.
/// `isDeleted` messages must render as "This message was removed." — never hidden.
/// `authorHomeCommunityId != nil` signals an external (cross-community) author.
struct SpacesChatMessage: Codable, Identifiable {
    var id: String
    var threadId: String
    var spaceId: String
    var authorId: String
    var authorDisplayName: String
    var authorAvatarURL: String?
    /// nil = member of the owning community; non-nil = external/linked member
    var authorHomeCommunityId: String?
    var body: String
    var createdAt: Date
    var editedAt: Date?
    /// emoji → [userId] — updated via atomic arrayUnion / arrayRemove
    var reactions: [String: [String]]
    var attachments: [SpacesChatAttachment]
    /// Soft-delete sentinel. NEVER hard-delete. Always render "removed" placeholder.
    var isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, threadId, spaceId
        case authorId, authorDisplayName, authorAvatarURL, authorHomeCommunityId
        case body, createdAt, editedAt
        case reactions, attachments, isDeleted
    }
}

// MARK: - SpacesChatAttachment

enum SpacesChatAttachmentType: String, Codable {
    case image  = "image"
    case video  = "video"
    case file   = "file"
    case audio  = "audio"
}

struct SpacesChatAttachment: Codable, Identifiable {
    var id: String
    var type: SpacesChatAttachmentType
    var url: String
    var thumbnailURL: String?
    var fileName: String?
    var fileSizeBytes: Int?
}

// MARK: - SpacesChatTypingIndicator

/// Ephemeral presence signal from RTDB `typing/{spaceId}/{threadId}/{userId}`.
/// Auto-expires after 5 s via RTDB TTL rules pattern.
struct SpacesChatTypingIndicator {
    var userId: String
    var displayName: String
    var timestamp: Date
}

// MARK: - SpacesChatReadState

/// Persisted to `spaces/{spaceId}/threads/{threadId}/readStates/{userId}`.
struct SpacesChatReadState: Codable {
    var threadId: String
    var userId: String
    var lastReadMessageId: String
    var lastReadAt: Date
}
