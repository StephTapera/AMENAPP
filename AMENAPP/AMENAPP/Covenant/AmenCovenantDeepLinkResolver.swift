import Foundation
import UIKit

// MARK: - Covenant Deep Link Resolver
// Handles amen:// scheme routing for Covenant OS deep links.
// Routes: covenant, room, post, event, creator, digest.

final class AmenCovenantDeepLinkResolver {
    static let shared = AmenCovenantDeepLinkResolver()

    // Navigation callback — set by the root coordinator / NavigationStack host
    var onRoute: ((CovenantDeepLinkRoute) -> Void)?

    private init() {}

    // MARK: - URL Parsing

    func handle(_ url: URL) -> Bool {
        guard url.scheme == "amen", let route = parse(url) else { return false }
        resolve(route)
        return true
    }

    func parse(_ url: URL) -> CovenantDeepLinkRoute? {
        // amen://covenant/{covenantId}
        // amen://covenant/{covenantId}/room/{roomId}
        // amen://covenant/{covenantId}/post/{postId}
        // amen://covenant/{covenantId}/event/{eventId}
        // amen://creator/{creatorId}
        // amen://digest/{digestId}
        let components = url.pathComponents.filter { $0 != "/" }
        let host = url.host ?? ""

        switch host {
        case "covenant":
            guard let cid = components.first else { return nil }
            if components.count >= 3 {
                switch components[1] {
                case "room":  return .room(covenantId: cid, roomId: components[2])
                case "post":  return .post(covenantId: cid, postId: components[2])
                case "event": return .event(covenantId: cid, eventId: components[2])
                default: break
                }
            }
            return .covenantHome(covenantId: cid)
        case "creator":
            guard let cid = components.first else { return nil }
            return .creator(creatorId: cid)
        case "digest":
            guard let did = components.first else { return nil }
            return .digest(digestId: did)
        default:
            return nil
        }
    }

    // MARK: - Resolve from string (activity deepLink field)

    func resolve(_ deepLinkString: String) {
        guard let url = URL(string: deepLinkString),
              let route = parse(url) else { return }
        resolve(route)
    }

    func resolve(_ route: CovenantDeepLinkRoute) {
        // Post to NotificationCenter so any listening NavigationStack can respond
        NotificationCenter.default.post(
            name: .amenCovenantDeepLink,
            object: nil,
            userInfo: ["route": route]
        )
        onRoute?(route)
    }

    // MARK: - Build URLs

    func url(for route: CovenantDeepLinkRoute) -> URL? {
        let str: String
        switch route {
        case .covenantHome(let cid):           str = "amen://covenant/\(cid)"
        case .room(let cid, let rid):          str = "amen://covenant/\(cid)/room/\(rid)"
        case .post(let cid, let pid):          str = "amen://covenant/\(cid)/post/\(pid)"
        case .event(let cid, let eid):         str = "amen://covenant/\(cid)/event/\(eid)"
        case .creator(let cid):                str = "amen://creator/\(cid)"
        case .digest(let did):                 str = "amen://digest/\(did)"
        }
        return URL(string: str)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let amenCovenantDeepLink = Notification.Name("amenCovenantDeepLink")
}
