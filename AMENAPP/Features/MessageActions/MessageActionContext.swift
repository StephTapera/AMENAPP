import Foundation

// MARK: - Message Surface

/// The conversational surface a message lives in.
enum MessageSurface: Equatable {
    case group(groupId: String)
    case discussion(discussionId: String)
    case amenConnect(dmId: String)

    /// The context document ID (groupId, discussionId, or dmId).
    var contextId: String {
        switch self {
        case .group(let id):       return id
        case .discussion(let id):  return id
        case .amenConnect(let id): return id
        }
    }

    /// True for group-chat and discussion surfaces; false for DMs.
    var isGroupLike: Bool {
        switch self {
        case .group, .discussion: return true
        case .amenConnect:        return false
        }
    }

    /// String token used in Firestore paths and deep links.
    var surfaceType: String {
        switch self {
        case .group:       return "group"
        case .discussion:  return "discussion"
        case .amenConnect: return "amenConnect"
        }
    }

    /// Re-hydrate from raw strings stored on AppMessage.
    init?(surfaceType: String, contextId: String) {
        switch surfaceType {
        case "group":       self = .group(groupId: contextId)
        case "discussion":  self = .discussion(discussionId: contextId)
        case "amenConnect": self = .amenConnect(dmId: contextId)
        default:            return nil
        }
    }
}

// MARK: - Message User Role

/// Four-tier role hierarchy used by the action capability matrix.
/// Callers convert their `ChurchRole` via `MessageUserRole.from(_:)`.
enum MessageUserRole: Equatable {
    /// Regular community member — no moderation powers.
    case member
    /// Pastor or moderator — can pin, remove others' messages.
    case leader
    /// Admin, media manager, or events manager — can announce + leader abilities.
    case admin
    /// Group/channel owner — all abilities.
    case owner

    var canPin: Bool        { self != .member }
    var canAnnounce: Bool   { self == .admin || self == .owner }
    var canRemoveOthers: Bool { self != .member }

    static func from(_ churchRole: ChurchRole?) -> MessageUserRole {
        switch churchRole {
        case .owner:                              return .owner
        case .admin, .mediaManager, .eventsManager: return .admin
        case .pastor, .moderator:                 return .leader
        case nil:                                 return .member
        }
    }
}

// MARK: - Message Action Context

/// Everything needed to compute which actions are available for a message.
/// Callers supply the per-user state fields (isSaved, hasPrayed, isMutedThread)
/// so the capability matrix stays a pure function of its inputs.
struct MessageActionContext {
    let message: AppMessage
    let surface: MessageSurface
    let currentUserId: String
    let currentUserRole: MessageUserRole

    // Per-user live state — set by the presenter before invoking the matrix.
    var isSaved: Bool = false
    var hasPrayed: Bool = false
    var isMutedThread: Bool = false

    // MARK: - Derived

    var isOwnMessage: Bool {
        message.senderId == currentUserId
    }

    /// True when the message carries the "system" tag (join/leave/pin notices).
    var isSystemMessage: Bool {
        message.tags.contains("system")
    }

    /// True when message is tagged as a prayer request.
    var isPrayerTagged: Bool {
        message.tags.contains("prayerRequest")
    }

    /// True when the message was sent within the 15-minute edit window.
    var isWithinEditWindow: Bool {
        guard let cutoff = Calendar.current.date(
            byAdding: .minute, value: 15, to: message.timestamp
        ) else { return false }
        return Date() < cutoff
    }
}
