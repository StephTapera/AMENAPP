import Foundation

// MARK: - Covenant Route
// Typed navigation destinations for the Covenant NavigationStack.
// All routes are Hashable so they can be pushed onto [CovenantRoute].

enum CovenantRoute: Hashable {
    case discovery
    case creatorHub(creatorId: String)
    case covenantHub(covenantId: String)
    case room(covenantId: String, roomId: String)
    case post(covenantId: String, postId: String)
    case event(covenantId: String, eventId: String)
    case digest(covenantId: String)
    case manage(covenantId: String)
    case analytics(covenantId: String)
    case moderation(covenantId: String)
    case memberDirectory(covenantId: String)
    case contentCalendar(covenantId: String)
    case verification
    case story(covenantId: String, storyId: String)
}

// MARK: - Deep Link → CovenantRoute

extension CovenantDeepLinkRoute {
    /// Maps every `CovenantDeepLinkRoute` case to the canonical `CovenantRoute`
    /// used by the NavigationStack. Called by `AmenCovenantViewModel.handleDeepLink(_:)`.
    var covenantRoute: CovenantRoute {
        switch self {
        case .covenantHome(let id):
            return .covenantHub(covenantId: id)
        case .room(let cid, let rid):
            return .room(covenantId: cid, roomId: rid)
        case .post(let cid, let pid):
            return .post(covenantId: cid, postId: pid)
        case .event(let cid, let eid):
            return .event(covenantId: cid, eventId: eid)
        case .creator(let id):
            return .creatorHub(creatorId: id)
        case .digest(let id):
            return .digest(covenantId: id)
        }
    }
}
