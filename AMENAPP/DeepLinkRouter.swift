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
            
        case "conversation":
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

        case "guardian":
            // What's New "Guardian Family Safe Sharing" CTA → Settings (Guardian section).
            return .settings(section: "guardian")

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
            selectedTab = 2  // Messages tab
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
            selectedTab = 2
        case .groupJoin:
            selectedTab = 2  // Messages tab (group join flow lives there)
        case .notifications:
            selectedTab = 2  // Notifications tab
        case .messages:
            selectedTab = 2  // Messages tab
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

// =====================================================================
// MARK: - Interaction Foundation (Phase B, from the §13 interaction audit)
// =====================================================================
//
// Single source of truth for two cross-cutting concerns the audit surfaced
// repeatedly across surfaces. Housed alongside DeepLinkRouter (the existing
// coordinator) so it lands in an indexed in-target file rather than an
// unverified new synced-folder file.
//
//   • ToastCoordinator — one app-wide toast queue. Motivated by the pervasive
//     "silent failure" finding (try? / catch { dlog } / errorMessage never
//     rendered). Lightweight feedback belongs here, not in a full modal.
//   • ModalCoordinator — one-active-at-a-time modal arbitration. Motivated by
//     the modal-stacking / recursive-sheet findings.
//   • AmenInteractionStateMachine — the reusable control lifecycle from §4,
//     with valid-transition enforcement so UI never desyncs from backend.
//
// Pure infrastructure: changes no behavior until a surface consumes it
// (Phase C). Names are unique app-wide (verified — no shadowing).

// MARK: Interaction State Machine (§4)

/// The lifecycle every critical/animated control moves through.
/// Invalid transitions are ignored safely (never crash, never desync).
public enum AmenInteractionState: String, Equatable, Sendable {
    case idle
    case pressed
    case expanding
    case expanded
    case loading
    case success
    case failed
    case disabled
    case collapsing
    case cancelled

    /// The states this state may legally transition to.
    var allowedNext: Set<AmenInteractionState> {
        switch self {
        case .idle:       return [.pressed, .loading, .disabled, .expanding]
        case .pressed:    return [.expanding, .loading, .idle, .cancelled, .disabled]
        case .expanding:  return [.expanded, .cancelled, .collapsing]
        case .expanded:   return [.loading, .collapsing, .cancelled, .idle]
        case .loading:    return [.success, .failed, .cancelled]
        case .success:    return [.idle, .collapsing]
        case .failed:     return [.idle, .loading, .collapsing]      // retry allowed
        case .disabled:   return [.idle]
        case .collapsing: return [.idle, .cancelled]
        case .cancelled:  return [.idle]
        }
    }

    var isTerminalForGesture: Bool { self == .idle || self == .disabled }
}

/// Observable driver for a single control's interaction lifecycle.
/// Reset on view disappear so animation state never outlives the view (§4).
@MainActor
public final class AmenInteractionStateMachine: ObservableObject {
    @Published public private(set) var state: AmenInteractionState = .idle

    public init(initial: AmenInteractionState = .idle) {
        self.state = initial
    }

    /// Attempt a transition. Returns true if it was legal and applied.
    /// Illegal transitions are ignored (logged in DEBUG), never fatal.
    @discardableResult
    public func transition(to next: AmenInteractionState) -> Bool {
        guard state.allowedNext.contains(next) else {
            #if DEBUG
            print("⚠️ AmenInteractionStateMachine: ignored illegal \(state.rawValue) → \(next.rawValue)")
            #endif
            return false
        }
        state = next
        return true
    }

    /// Hard reset — call from `.onDisappear`.
    public func reset() { state = .idle }

    public var isBusy: Bool { state == .loading || state == .expanding || state == .collapsing }
}

// MARK: Toast Coordinator

public struct AmenToastModel: Identifiable, Equatable {
    public enum Kind: Equatable {
        case info       // neutral
        case success    // green = state/status (two-accent contract)
        case failure    // calm, non-punitive — never playful on errors
    }
    public let id = UUID()
    public let kind: Kind
    public let message: String
    public let actionTitle: String?

    public init(kind: Kind, message: String, actionTitle: String? = nil) {
        self.kind = kind
        self.message = message
        self.actionTitle = actionTitle
    }

    public static func == (lhs: AmenToastModel, rhs: AmenToastModel) -> Bool { lhs.id == rhs.id }
}

/// App-wide single toast queue. Use for lightweight feedback (success, recoverable
/// failure) instead of a modal. Replaces the scattered silent-failure pattern.
@MainActor
public final class ToastCoordinator: ObservableObject {
    public static let shared = ToastCoordinator()

    @Published public private(set) var current: AmenToastModel?
    private var queue: [AmenToastModel] = []
    private var dismissTask: Task<Void, Never>?
    private let visibleDuration: Duration = .seconds(3)

    private init() {}

    public func show(_ toast: AmenToastModel) {
        if current == nil {
            present(toast)
        } else if current != toast {
            queue.append(toast)
        }
    }

    /// Convenience for the most common case the audit calls for.
    public func failure(_ message: String, actionTitle: String? = nil) {
        show(AmenToastModel(kind: .failure, message: message, actionTitle: actionTitle))
    }

    public func success(_ message: String) {
        show(AmenToastModel(kind: .success, message: message))
    }

    public func dismissCurrent() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        if !queue.isEmpty {
            present(queue.removeFirst())
        }
    }

    private func present(_ toast: AmenToastModel) {
        current = toast
        dismissTask?.cancel()
        let duration = visibleDuration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismissCurrent()
        }
    }
}

// MARK: Modal Coordinator

/// The kinds of exclusive surfaces the app may show. Only ONE may be active at a
/// time (§4): no modal stacking, no sheet-behind-alert, no paywall/permission
/// conflict, no recursive sheet-over-sheet.
public enum AmenModalKind: Equatable, Identifiable {
    case sheet(id: String)
    case alert(id: String)
    case paywall(id: String)
    case permission(id: String)
    case destructiveConfirm(id: String)

    public var id: String {
        switch self {
        case .sheet(let id):              return "sheet:\(id)"
        case .alert(let id):              return "alert:\(id)"
        case .paywall(let id):            return "paywall:\(id)"
        case .permission(let id):         return "permission:\(id)"
        case .destructiveConfirm(let id): return "confirm:\(id)"
        }
    }
}

/// Arbitrates exclusive modal presentation app-wide. A request while something is
/// already presented is rejected (returns false) rather than stacked. Navigation
/// should call `reset()` so a stale modal can't survive a route change.
@MainActor
public final class ModalCoordinator: ObservableObject {
    public static let shared = ModalCoordinator()

    @Published public private(set) var active: AmenModalKind?

    private init() {}

    /// Request to present. Returns false if another modal is already active.
    @discardableResult
    public func present(_ kind: AmenModalKind) -> Bool {
        guard active == nil else {
            #if DEBUG
            print("⚠️ ModalCoordinator: rejected \(kind.id) — \(active?.id ?? "?") already active")
            #endif
            return false
        }
        active = kind
        return true
    }

    /// Dismiss only if `kind` is the active one (prevents racing dismissals).
    public func dismiss(_ kind: AmenModalKind) {
        if active == kind { active = nil }
    }

    public func dismissActive() { active = nil }

    /// Clear on navigation so no hidden modal Boolean is left true (§4).
    public func reset() { active = nil }

    public var isPresenting: Bool { active != nil }
}

// MARK: Navigation Coordinator
//
// NOTE: `DeepLinkRouter` (above) already IS the app's navigation coordinator —
// it owns `navigationPath`, `selectedTab`, the route/destination enums, and
// `navigate()`. Per the audit's "extend, don't fork" rule we do NOT add a second
// NavigationCoordinator. Phase C surfaces route through `DeepLinkRouter.shared`.

// MARK: Button Action Router

/// Central dispatch for button actions, with built-in duplicate-tap prevention.
/// Replaces ad-hoc per-view in-flight booleans and prevents the double-submit /
/// double-append findings (forum reply, comment heart, join, RSVP, visit-plan).
@MainActor
public final class ButtonActionRouter: ObservableObject {
    public static let shared = ButtonActionRouter()

    @Published public private(set) var inFlight: Set<String> = []
    private var lastFired: [String: ContinuousClock.Instant] = [:]
    private let debounceInterval: Duration = .milliseconds(350)
    private let clock = ContinuousClock()

    private init() {}

    /// Run an async action keyed by `id`. No-ops if the same id is already in
    /// flight or was fired within the debounce window. Always clears in-flight.
    public func perform(_ id: String, action: @escaping () async -> Void) {
        if inFlight.contains(id) { return }
        if let last = lastFired[id], last.duration(to: clock.now) < debounceInterval { return }
        lastFired[id] = clock.now
        inFlight.insert(id)
        Task { [weak self] in
            await action()
            self?.inFlight.remove(id)
        }
    }

    public func isInFlight(_ id: String) -> Bool { inFlight.contains(id) }
}

// MARK: Paywall Coordinator

/// AMEN subscription tiers, low→high. `Comparable` so a feature can require a
/// minimum tier.
public enum AmenTier: String, Comparable, Sendable, CaseIterable {
    case free, amenPlus, amenPro, creatorPro, churchPro

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: AmenTier, rhs: AmenTier) -> Bool { lhs.rank < rhs.rank }
}

public struct AmenPaywallRequest: Identifiable, Equatable {
    public let id = UUID()
    public let requiredTier: AmenTier
    public let feature: String

    public init(requiredTier: AmenTier, feature: String) {
        self.requiredTier = requiredTier
        self.feature = feature
    }

    public static func == (lhs: AmenPaywallRequest, rhs: AmenPaywallRequest) -> Bool { lhs.id == rhs.id }
}

/// THE single paywall entry point. Resolves the ≥5 fragmented upgrade/paywall
/// surfaces (AmenAccountPaywallView, inline PaywallOverlay, AmenSubscriptionPaywall,
/// AmenFeatureGateView, SignUp TierCard) into one. Present only after clear intent
/// — never preemptively, never with dark-pattern timing (CalmCap).
@MainActor
public final class PaywallCoordinator: ObservableObject {
    public static let shared = PaywallCoordinator()

    @Published public private(set) var request: AmenPaywallRequest?

    private init() {}

    public func present(requiredTier: AmenTier, feature: String) {
        guard request == nil else { return }   // one paywall at a time
        request = AmenPaywallRequest(requiredTier: requiredTier, feature: feature)
    }

    public func dismiss() { request = nil }

    public var isPresenting: Bool { request != nil }
}

// MARK: Permission Coordinator

public enum AmenPermissionKind: String, Sendable {
    case location, notifications, calendar, camera, microphone, photos, contacts
}

public struct AmenPermissionPrime: Identifiable, Equatable {
    public let id = UUID()
    public let kind: AmenPermissionKind
    public let rationale: String      // shown BEFORE the system prompt

    public static func == (lhs: AmenPermissionPrime, rhs: AmenPermissionPrime) -> Bool { lhs.id == rhs.id }
}

/// Contextual permission flow: show a calm rationale first, fire the OS prompt
/// only when the user accepts the priming sheet. Directly addresses the
/// onboarding "Enable Notifications fires the system prompt with no explanation /
/// silently advances when already denied" finding. Framework calls stay at the
/// call site (passed as `systemRequest`) so this stays dependency-light.
@MainActor
public final class PermissionCoordinator: ObservableObject {
    public static let shared = PermissionCoordinator()

    @Published public private(set) var prime: AmenPermissionPrime?
    private var pendingRequest: (() -> Void)?

    private init() {}

    public func requestWithRationale(
        _ kind: AmenPermissionKind,
        rationale: String,
        systemRequest: @escaping () -> Void
    ) {
        guard prime == nil else { return }
        pendingRequest = systemRequest
        prime = AmenPermissionPrime(kind: kind, rationale: rationale)
    }

    /// User accepted the priming sheet → fire the actual system prompt once.
    public func confirmPrime() {
        let req = pendingRequest
        prime = nil
        pendingRequest = nil
        req?()
    }

    public func cancelPrime() {
        prime = nil
        pendingRequest = nil
    }
}
