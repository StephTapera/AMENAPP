import SwiftUI
import Foundation
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// NAV-02 RESOLVED — Both schemes now handle an identical set of routes.
//
// DeepLinkRouter.parse()    — accepts amen://   (DeepLinkRoute enum)
// NotificationDeepLinkRouter.handleURL() — accepts amen:// AND amenapp://
//                                          (NavigationDestination enum)
//
// Both parsers cover: post, user/profile, church, conversation/messages,
// category, search, settings, comment, chat, group/join, notifications,
// messages, prayer, church-note, intelligence.
//
// Future work: merge into a single UnifiedDeepLinkRouter that shares one
// destination model (Phase 2).
// ─────────────────────────────────────────────────────────────────────────────

/// Central routing system for deep links and in-app navigation
/// Handles: Push notifications, Universal Links, in-app navigation
@MainActor
class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    
    // MARK: - Published State
    
    @Published var activeRoute: DeepLinkRoute?
    @Published var navigationPath: [DeepLinkDestination] = []
    @Published var selectedTab: Int = 0
    
    // MARK: - Route Types
    
    enum DeepLinkRoute: Equatable {
        case post(id: String, highlightCommentId: String? = nil)
        case userProfile(userId: String)
        case church(churchId: String)
        case conversation(conversationId: String, highlightMessageId: String? = nil)
        case notification(notificationId: String)
        case category(String)  // #OPENTABLE, Testimonies, Prayer
        case search(query: String)
        case settings(section: String? = nil)
        /// Deep link from Reply Assist island: open comment thread with pre-filled reply text.
        /// prefill is percent-decoded when parsed; the composer should populate but NOT auto-send.
        case comment(postId: String, commentId: String?, prefill: String?)
        /// Deep link from Reply Assist island: open DM thread with pre-filled reply text.
        case chat(threadId: String, prefill: String?)
        /// Group join link (token-authenticated invite).
        case groupJoin(token: String)
        /// Navigate directly to the Notifications tab.
        case notifications
        /// Navigate directly to the Messages tab.
        case messages
        /// Open a specific prayer request.
        case prayer(prayerId: String)
        /// Open a specific church note.
        case churchNote(noteId: String)
        /// Open the intelligence/Berean brief card.
        case intelligence(cardId: String?)
        /// Open a specific Space (community). Lands on the Spaces hub tab.
        case space(spaceId: String)
        /// Open a church event. Interim destination — routes to the church/resources
        /// surface until a dedicated event detail surface exists (see navigate()).
        case event(eventId: String)
    }
    
    enum DeepLinkDestination: Hashable {
        case post(id: String)
        case userProfile(userId: String)
        case church(churchId: String)
        case conversation(conversationId: String)
        case settings
    }
    
    // MARK: - Parse Deep Link
    
    /// Parse URL into a route
    /// Supports:
    /// - amen://post/{id}
    /// - amen://post/{id}/comment/{commentId}
    /// - amen://user/{userId}
    /// - amen://church/{churchId}
    /// - amen://conversation/{id}
    /// - amen://conversation/{id}/message/{messageId}
    /// - amen://category/{name}
    func parse(url: URL) -> DeepLinkRoute? {
        guard url.scheme == "amen" else { return nil }
        
        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        
        switch host {
        case "post":
            guard let postId = pathComponents.first else { return nil }
            let commentId = queryItems?.first(where: { $0.name == "comment" })?.value
            return .post(id: postId, highlightCommentId: commentId)
            
        case "user", "profile":
            guard let userId = pathComponents.first else { return nil }
            return .userProfile(userId: userId)
            
        case "church":
            guard let churchId = pathComponents.first else { return nil }
            return .church(churchId: churchId)
            
        case "conversation", "messages":
            guard let conversationId = pathComponents.first else { return nil }
            let messageId = queryItems?.first(where: { $0.name == "message" })?.value
            return .conversation(conversationId: conversationId, highlightMessageId: messageId)
            
        case "category":
            guard let category = pathComponents.first else { return nil }
            return .category(category)
            
        case "search":
            let query = queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            return .search(query: query)
            
        case "settings":
            let section = pathComponents.first
            return .settings(section: section)

        case "comment":
            // amen://comment?postId=...&commentId=...&prefill=...
            let postId    = queryItems?.first(where: { $0.name == "postId" })?.value ?? ""
            let commentId = queryItems?.first(where: { $0.name == "commentId" })?.value
            let prefill   = queryItems?.first(where: { $0.name == "prefill" })?.value
                                       .flatMap { $0.removingPercentEncoding }
            guard !postId.isEmpty else { return nil }
            return .comment(postId: postId, commentId: commentId, prefill: prefill)

        case "chat":
            // amen://chat?threadId=...&prefill=...
            let threadId = queryItems?.first(where: { $0.name == "threadId" })?.value ?? ""
            let prefill  = queryItems?.first(where: { $0.name == "prefill" })?.value
                                      .flatMap { $0.removingPercentEncoding }
            guard !threadId.isEmpty else { return nil }
            return .chat(threadId: threadId, prefill: prefill)

        case "group":
            // amen://group/join?token=...
            guard pathComponents.first == "join",
                  let token = queryItems?.first(where: { $0.name == "token" })?.value,
                  !token.isEmpty else { return nil }
            return .groupJoin(token: token)

        case "notifications":
            return .notifications

        case "messages":
            return .messages

        case "prayer":
            guard let prayerId = pathComponents.first else { return nil }
            return .prayer(prayerId: prayerId)

        case "church-note":
            guard let noteId = pathComponents.first else { return nil }
            return .churchNote(noteId: noteId)

        case "intelligence":
            // amen://intelligence or amen://intelligence/card/{cardId}
            let cardId = pathComponents.count >= 2 && pathComponents[0] == "card"
                ? pathComponents[1]
                : pathComponents.first
            return .intelligence(cardId: cardId)

        case "space":
            // amen://space/{spaceId}
            guard let spaceId = pathComponents.first else { return nil }
            return .space(spaceId: spaceId)

        case "event":
            // amen://event/{eventId}
            guard let eventId = pathComponents.first else { return nil }
            return .event(eventId: eventId)

        default:
            return nil
        }
    }
    
    // MARK: - Navigate

    /// Navigate to a route.
    /// When Shabbat Mode is active, blocked routes are redirected to tab 3 (Resources)
    /// and a gate view is displayed instead of the blocked content.
    func navigate(to route: DeepLinkRoute) {
        // ── Shabbat gate ───────────────────────────────────────────────────
        let feature = route.requiredFeature
        if case .blocked(let reason) = AppAccessController.shared.canAccess(feature) {
            ShabbatModeService.shared.logBlocked(feature: feature, route: route.analyticsLabel)
            dlog("🚫 DeepLinkRouter: blocked \(reason.errorCode) for route \(route.analyticsLabel)")
            // Route to permitted tab (Resources = 3) and let the gate overlay handle UX
            selectedTab = 3
            // Signal ContentView to show the gate banner
            NotificationCenter.default.post(
                name: .shabbatDeepLinkBlocked,
                object: nil,
                userInfo: ["blockedRoute": route.analyticsLabel]
            )
            return
        }
        // ──────────────────────────────────────────────────────────────────

        // Set active route (triggers UI updates)
        activeRoute = route

        // Switch to appropriate tab
        switch route {
        case .post, .userProfile, .category, .church:
            selectedTab = 0  // Home/Feed tab
        case .conversation:
            selectedTab = 3  // Messages tab
        case .notification:
            selectedTab = 2  // Notifications tab
        case .search:
            selectedTab = 1  // Search tab
        case .settings:
            selectedTab = 5  // Profile tab (index 5); was incorrectly 4 (Notifications) — NAV-01 fix
        case .comment:
            // Open the post's comment thread (home tab, then push post detail)
            selectedTab = 0
        case .chat:
            // Open the DM thread directly
            selectedTab = 3
        case .groupJoin:
            selectedTab = 3  // Messages tab (group join flow lives there)
        case .notifications:
            selectedTab = 2  // Notifications tab
        case .messages:
            selectedTab = 3  // Messages tab
        case .prayer, .churchNote:
            selectedTab = 3  // Resources tab (index 3)
        case .intelligence:
            selectedTab = 7  // Intelligence Brief tab
        case .space:
            selectedTab = 6  // Spaces hub (AmenConnectSpacesHubView)
        case .event:
            // INTERIM DESTINATION — dedicated church-event surface TBD. Church
            // events live in the Resources surface; land there scoped via activeRoute.
            selectedTab = 3
        }
        // End the reply activity since user opened the destination
        LiveActivityManager.shared.endReplyActivity(reason: .userOpened)
    }
    
    /// Navigate from URL string
    func navigate(to urlString: String) {
        guard let url = URL(string: urlString),
              let route = parse(url: url) else {
            return
        }
        navigate(to: route)
    }
    
    /// Generate deep link URL for a route
    func generateURL(for route: DeepLinkRoute) -> URL? {
        var components = URLComponents()
        components.scheme = "amen"
        
        switch route {
        case .post(let id, let commentId):
            components.host = "post"
            components.path = "/\(id)"
            if let commentId = commentId {
                components.queryItems = [URLQueryItem(name: "comment", value: commentId)]
            }
            
        case .userProfile(let userId):
            components.host = "user"
            components.path = "/\(userId)"
            
        case .church(let churchId):
            components.host = "church"
            components.path = "/\(churchId)"
            
        case .conversation(let conversationId, let messageId):
            components.host = "conversation"
            components.path = "/\(conversationId)"
            if let messageId = messageId {
                components.queryItems = [URLQueryItem(name: "message", value: messageId)]
            }
            
        case .category(let name):
            components.host = "category"
            components.path = "/\(name)"
            
        case .search(let query):
            components.host = "search"
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            
        case .notification(let notificationId):
            components.host = "notification"
            components.path = "/\(notificationId)"
            
        case .settings(let section):
            components.host = "settings"
            if let section = section {
                components.path = "/\(section)"
            }

        case .comment(let postId, let commentId, let prefill):
            components.host = "comment"
            var items = [URLQueryItem(name: "postId", value: postId)]
            if let commentId { items.append(URLQueryItem(name: "commentId", value: commentId)) }
            if let prefill   { items.append(URLQueryItem(name: "prefill", value: prefill)) }
            components.queryItems = items

        case .chat(let threadId, let prefill):
            components.host = "chat"
            var items = [URLQueryItem(name: "threadId", value: threadId)]
            if let prefill { items.append(URLQueryItem(name: "prefill", value: prefill)) }
            components.queryItems = items

        case .groupJoin(let token):
            components.host = "group"
            components.path = "/join"
            components.queryItems = [URLQueryItem(name: "token", value: token)]

        case .notifications:
            components.host = "notifications"

        case .messages:
            components.host = "messages"

        case .prayer(let prayerId):
            components.host = "prayer"
            components.path = "/\(prayerId)"

        case .churchNote(let noteId):
            components.host = "church-note"
            components.path = "/\(noteId)"

        case .intelligence(let cardId):
            components.host = "intelligence"
            if let cardId {
                components.path = "/card/\(cardId)"
            }

        case .space(let spaceId):
            components.host = "space"
            components.path = "/\(spaceId)"

        case .event(let eventId):
            components.host = "event"
            components.path = "/\(eventId)"
        }

        return components.url
    }
    
    /// Clear current route
    func clearRoute() {
        activeRoute = nil
    }
    
    /// Push destination onto navigation stack
    func push(_ destination: DeepLinkDestination) {
        navigationPath.append(destination)
    }
    
    /// Pop current destination
    func pop() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }
    
    /// Clear entire navigation stack
    func popToRoot() {
        navigationPath.removeAll()
    }
}

// MARK: - SwiftUI Modifier

extension View {
    /// Handle deep links for this view
    func handleDeepLinks() -> some View {
        self.modifier(DeepLinkHandler())
    }
}

struct DeepLinkHandler: ViewModifier {
    @ObservedObject private var router = DeepLinkRouter.shared

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                if let route = router.parse(url: url) {
                    router.navigate(to: route)
                }
            }
    }
}

// MARK: - DeepLinkRoute + Shabbat helpers

extension DeepLinkRouter.DeepLinkRoute {
    /// The AppFeature that this route requires access to.
    var requiredFeature: AppFeature {
        switch self {
        case .post, .category, .comment:
            return .feed
        case .userProfile:
            return .profileBrowse
        case .church:
            return .findChurch        // church deep links are allowed
        case .conversation, .chat, .messages, .groupJoin:
            return .messages
        case .notification, .notifications:
            return .notifications
        case .search:
            return .search
        case .settings:
            return .settings          // always allowed
        case .prayer, .churchNote:
            return .feed              // prayer/church notes live in the resources feed
        case .intelligence:
            return .feed
        case .space:
            return .messages         // Spaces are conversational/community — gate like messages
        case .event:
            return .findChurch       // church-published events — allowed like church
        }
    }

    /// Human-readable label used in analytics events.
    var analyticsLabel: String {
        switch self {
        case .post(let id, _):           return "post/\(id)"
        case .userProfile(let id):       return "user/\(id)"
        case .church(let id):            return "church/\(id)"
        case .conversation(let id, _):   return "conversation/\(id)"
        case .notification(let id):      return "notification/\(id)"
        case .category(let name):        return "category/\(name)"
        case .search(let q):             return "search/\(q)"
        case .settings(let s):           return "settings/\(s ?? "root")"
        case .comment(let pid, _, _):    return "comment/\(pid)"
        case .chat(let tid, _):          return "chat/\(tid)"
        case .groupJoin(let t):          return "group/join/\(t.prefix(8))..."
        case .notifications:             return "notifications"
        case .messages:                  return "messages"
        case .prayer(let id):            return "prayer/\(id)"
        case .churchNote(let id):        return "church-note/\(id)"
        case .intelligence(let id):      return "intelligence/\(id ?? "root")"
        case .space(let id):             return "space/\(id)"
        case .event(let id):             return "event/\(id)"
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted when a deep link is blocked by Shabbat Mode.
    static let shabbatDeepLinkBlocked = Notification.Name("shabbatDeepLinkBlocked")
}
