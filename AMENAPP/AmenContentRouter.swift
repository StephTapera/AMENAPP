// AmenContentRouter.swift
// AMENAPP
// Universal content routing — maps ContentNode to destination views and deep links.

import SwiftUI

// MARK: - Legacy route (kept for compatibility)

enum AmenContentRoute: Equatable {
    case postPreview(Post)
    case fallback(ContentNode)
}

struct AmenContentRouter {
    static func route(_ node: ContentNode) -> AmenContentRoute {
        switch node.type {
        case .post, .note, .discussion, .aiSession, .churchNote, .selah, .design, .video,
             .comment, .reply, .mediaPost, .prayerPost, .testimonyPost, .scripturePost:
            return .postPreview(node.toPostPreview())
        }
    }
}

// MARK: - Universal Destination

enum AmenContentDestination: Hashable {
    case post(postId: String)
    case churchNote(noteId: String)
    case prayer(prayerId: String)
    case mediaPost(postId: String, mediaIndex: Int)
    case verse(reference: String)
    case covenantRoom(covenantId: String, roomId: String)
    case bereanSession(sessionId: String)
    case selahItem(itemId: String)
    case profile(userId: String)
    case unknown
}

// MARK: - Router Service

@MainActor
final class AmenUniversalContentRouter: ObservableObject {
    static let shared = AmenUniversalContentRouter()

    func destination(for contentNode: ContentNode) -> AmenContentDestination {
        switch contentNode.type {
        case .post, .discussion:          return .post(postId: contentNode.id)
        case .churchNote:                 return .churchNote(noteId: contentNode.id)
        case .prayerPost:                 return .prayer(prayerId: contentNode.id)
        case .mediaPost, .video:          return .mediaPost(postId: contentNode.id, mediaIndex: 0)
        case .scripturePost:
            let ref = contentNode.title ?? contentNode.text ?? ""
            return .verse(reference: ref)
        case .selah:                      return .selahItem(itemId: contentNode.id)
        default:                          return .post(postId: contentNode.id)
        }
    }

    func destination(forEntityType type: String, id: String) -> AmenContentDestination {
        switch type {
        case "post":       return .post(postId: id)
        case "churchNote": return .churchNote(noteId: id)
        case "prayer":     return .prayer(prayerId: id)
        case "media":      return .mediaPost(postId: id, mediaIndex: 0)
        case "berean":     return .bereanSession(sessionId: id)
        case "selah":      return .selahItem(itemId: id)
        case "profile":    return .profile(userId: id)
        default:           return .unknown
        }
    }

    /// Parses `amen://host/path` deep links.
    func destination(from url: URL) -> AmenContentDestination {
        guard url.scheme == "amen" else { return .unknown }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host {
        case "post":          return parts.first.map { .post(postId: $0) } ?? .unknown
        case "churchnote":    return parts.first.map { .churchNote(noteId: $0) } ?? .unknown
        case "prayer":        return parts.first.map { .prayer(prayerId: $0) } ?? .unknown
        case "media":
            guard let postId = parts.first else { return .unknown }
            return .mediaPost(postId: postId, mediaIndex: parts.count > 1 ? Int(parts[1]) ?? 0 : 0)
        case "berean":        return parts.first.map { .bereanSession(sessionId: $0) } ?? .unknown
        case "selah":         return parts.first.map { .selahItem(itemId: $0) } ?? .unknown
        case "profile", "user": return parts.first.map { .profile(userId: $0) } ?? .unknown
        default:              return .unknown
        }
    }
}
