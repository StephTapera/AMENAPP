//
//  NotificationDeepLinkRouter.swift
//  AMENAPP
//
//  Production-grade deep link routing for notifications
//  Handles navigation to posts, comments, threads, profiles, conversations
//

// ─────────────────────────────────────────────────────────────────────────────
// NAV-02 RESOLVED — Both schemes now handle an identical set of routes.
//
// handleURL() now accepts both "amen://" and "amenapp://" schemes.
// Routes ported from amen://: church, category, user, search, settings,
//   comment, chat (in addition to the existing amenapp:// set).
// Routes ported to DeepLinkRouter: group/join, notifications, messages,
//   prayer, church-note, intelligence.
//
// Future work: merge into a single UnifiedDeepLinkRouter (Phase 2).
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

/// Handles deep linking from notifications to specific app screens
@MainActor
final class NotificationDeepLinkRouter: ObservableObject {
    
    static let shared = NotificationDeepLinkRouter()
    
    // MARK: - Navigation State
    
    /// Active navigation destination (used by root ContentView)
    @Published var activeDestination: NavigationDestination?
    
    /// Pending navigation (queued while app is launching)
    private var pendingNavigation: NavigationDestination?
    
    enum NavigationDestination: Equatable {
        case post(postId: String, scrollToCommentId: String? = nil)
        case profile(userId: String)
        case conversation(conversationId: String, messageId: String? = nil)
        case groupJoinLink(token: String)
        case notifications
        case messages
        case prayer(prayerId: String)
        case churchNote(noteId: String)
        case job(jobId: String)
        case event(eventId: String)
        case studioProfile(creatorId: String)
        case intelligence(cardId: String? = nil)
        /// Opens the Discovery / Search tab (tab 1).
        case discovery
        /// Opens the Profile tab where Settings is accessible (tab 5).
        case settings
        /// Opens the Resources tab where Find a Church lives (tab 3).
        case church

        static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
            switch (lhs, rhs) {
            case (.post(let id1, let comment1), .post(let id2, let comment2)):
                return id1 == id2 && comment1 == comment2
            case (.profile(let id1), .profile(let id2)):
                return id1 == id2
            case (.conversation(let id1, let msg1), .conversation(let id2, let msg2)):
                return id1 == id2 && msg1 == msg2
            case (.groupJoinLink(let t1), .groupJoinLink(let t2)):
                return t1 == t2
            case (.notifications, .notifications), (.messages, .messages):
                return true
            case (.prayer(let id1), .prayer(let id2)):
                return id1 == id2
            case (.churchNote(let id1), .churchNote(let id2)):
                return id1 == id2
            case (.job(let id1), .job(let id2)):
                return id1 == id2
            case (.event(let id1), .event(let id2)):
                return id1 == id2
            case (.studioProfile(let id1), .studioProfile(let id2)):
                return id1 == id2
            case (.intelligence(let id1), .intelligence(let id2)):
                return id1 == id2
            case (.discovery, .discovery), (.settings, .settings), (.church, .church):
                return true
            default:
                return false
            }
        }
    }
    
    private init() {}
    
    // MARK: - Route Notification
    
    /// Route notification to appropriate screen
    func route(_ notification: AppNotification) {
        let destination = determineDestination(for: notification)
        
        dlog("🔗 Routing notification to: \(destination)")
        
        // Track engagement for smart notification engine
        SmartNotificationEngine.shared.recordNotificationInteraction(notification)
        
        // Navigate
        performNavigation(to: destination)
    }
    
    /// Route from push notification payload
    func routeFromPushPayload(_ userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else {
            dlog("⚠️ No type in push notification payload")
            return
        }
        
        dlog("🔗 Routing push notification: \(type)")
        
        let destination: NavigationDestination
        
        switch type {
        case "follow", "followRequestAccepted":
            if let actorId = userInfo["actorId"] as? String {
                destination = .profile(userId: actorId)
            } else {
                destination = .notifications
            }
            
        case "comment":
            if let postId = userInfo["postId"] as? String {
                let commentId = userInfo["commentId"] as? String
                // Pre-load comment focus so PostDetailView scrolls to target on appear
                if let commentId {
                    CommentFocusCoordinator.shared.set(scrollTarget: commentId, highlight: commentId)
                }
                destination = .post(postId: postId, scrollToCommentId: commentId)
            } else {
                destination = .notifications
            }

        case "reply":
            if let postId = userInfo["postId"] as? String {
                let replyId = userInfo["commentId"] as? String
                let parentId = userInfo["parentCommentId"] as? String
                if let replyId {
                    CommentFocusCoordinator.shared.set(
                        scrollTarget: replyId,
                        highlight: replyId,
                        expandThread: parentId
                    )
                }
                destination = .post(postId: postId, scrollToCommentId: replyId)
            } else {
                destination = .notifications
            }

        case "mention":
            if let postId = userInfo["postId"] as? String {
                let commentId = userInfo["commentId"] as? String
                if let commentId {
                    CommentFocusCoordinator.shared.set(scrollTarget: commentId, highlight: commentId)
                }
                destination = .post(postId: postId, scrollToCommentId: commentId)
            } else {
                destination = .notifications
            }
            
        case "amen", "repost":
            if let postId = userInfo["postId"] as? String {
                destination = .post(postId: postId)
            } else {
                destination = .notifications
            }
            
        case "message", "messageRequest":
            if let conversationId = userInfo["conversationId"] as? String {
                let messageId = userInfo["messageId"] as? String
                destination = .conversation(conversationId: conversationId, messageId: messageId)
            } else {
                destination = .messages
            }
            
        case "messageRequestAccepted":
            if let conversationId = userInfo["conversationId"] as? String {
                destination = .conversation(conversationId: conversationId)
            } else {
                destination = .messages
            }
            
        case "prayerReminder", "prayerAnswered":
            if let prayerId = userInfo["prayerId"] as? String {
                destination = .prayer(prayerId: prayerId)
            } else {
                destination = .notifications
            }
            
        case "churchNoteShared":
            if let noteId = userInfo["noteId"] as? String {
                destination = .churchNote(noteId: noteId)
            } else {
                destination = .notifications
            }

        case "intelligenceBrief", "intelligenceCard":
            let cardId = userInfo["cardId"] as? String
            destination = .intelligence(cardId: cardId)

        default:
            destination = .notifications
        }

        // ✅ FIX: Verify content exists before navigating — graceful fallback
        // if the post/conversation was deleted after the notification was sent.
        verifyAndNavigate(to: destination)
    }
    
    // MARK: - Determine Destination
    
    private func determineDestination(for notification: AppNotification) -> NavigationDestination {
        switch notification.type {
        case .follow, .followRequestAccepted:
            if let actorId = notification.actorId {
                return .profile(userId: actorId)
            }
            return .notifications
            
        case .amen, .repost:
            if let postId = notification.postId {
                return .post(postId: postId)
            }
            return .notifications
            
        case .comment, .reply:
            if let postId = notification.postId {
                return .post(postId: postId, scrollToCommentId: notification.commentId)
            }
            return .notifications
            
        case .mention:
            if let postId = notification.postId {
                return .post(postId: postId)
            }
            return .notifications
            
        case .message, .messageRequest:
            if let conversationId = notification.conversationId {
                return .conversation(conversationId: conversationId)
            }
            return .messages
            
        case .messageRequestAccepted:
            if let conversationId = notification.conversationId {
                return .conversation(conversationId: conversationId)
            }
            return .messages
            
        case .prayerReminder, .prayerAnswered:
            if let prayerId = notification.prayerId {
                return .prayer(prayerId: prayerId)
            }
            return .notifications
            
        case .churchNoteShared, .churchNoteReplied:
            if let noteId = notification.noteId {
                return .churchNote(noteId: noteId)
            }
            return .notifications

        case .prayerSupported:
            if let prayerId = notification.prayerId {
                return .prayer(prayerId: prayerId)
            }
            return .notifications

        case .actionThreadInvite, .actionThreadUpdate, .actionThreadReminder:
            if let postId = notification.postId {
                return .post(postId: postId)
            }
            return .notifications

        case .unknown:
            return .notifications
        }
    }
    
    // MARK: - Navigation

    /// Minimum interval between navigation events. Rapid notifications arriving
    /// within this window are queued rather than overwriting the active destination.
    private var lastNavigationTime: Date = .distantPast
    private let navigationDebounceInterval: TimeInterval = 0.6

    private func performNavigation(to destination: NavigationDestination) {
        let now = Date()

        // FIX #11: Guard against routing before authentication is complete.
        // A notification tap can call this method before Firebase Auth has resolved
        // the session (e.g. during auto-login splash or cold start). Firing activeDestination
        // while !isAuthenticated causes navigation into protected screens before the
        // auth state listener has set isAuthenticated=true, resulting in blank/unauthenticated views.
        // Queue unconditionally until both appReady AND auth are confirmed.
        guard Auth.auth().currentUser != nil else {
            pendingNavigation = destination
            dlog("⏸️ Queued navigation (auth not ready): \(destination)")
            return
        }

        // P1 FIX: Debounce rapid navigation requests. If two notifications arrive
        // within 0.6s and the first destination hasn't been consumed yet, queue the
        // second. It will be processed by clearDestination() after the UI settles.
        if now.timeIntervalSince(lastNavigationTime) < navigationDebounceInterval,
           activeDestination != nil {
            pendingNavigation = destination
            dlog("⏸️ Debounced navigation (rapid arrival): \(destination)")
            return
        }

        lastNavigationTime = now

        if isAppReady() {
            activeDestination = destination
            dlog("✅ Navigating to: \(destination)")
        } else {
            // Queue navigation for when app is ready
            pendingNavigation = destination
            dlog("⏸️ Queued navigation (app not ready): \(destination)")
        }
    }

    /// Call this when app is ready to handle navigation
    func appDidBecomeReady() {
        // FIX #11: Only release queued deep links if the user is still authenticated.
        // markAppReady() is called from mainContent.onAppear which is inside the
        // isAuthenticated branch, but race conditions can cause appReady to be set
        // before the auth token is fully stable. Re-checking here is safe and cheap.
        guard Auth.auth().currentUser != nil else {
            dlog("⏸️ appDidBecomeReady: auth not ready yet — holding pending navigation")
            return
        }
        if let pending = pendingNavigation {
            dlog("▶️ Processing pending navigation: \(pending)")
            activeDestination = pending
            pendingNavigation = nil
        }
    }

    /// Clear active destination (call after navigation completes).
    /// Also processes any queued (debounced) navigation.
    func clearDestination() {
        activeDestination = nil
        // Process any queued navigation after a short settle delay
        if let queued = pendingNavigation {
            pendingNavigation = nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s settle
                self.activeDestination = queued
                self.lastNavigationTime = Date()
                dlog("▶️ Processing queued navigation: \(queued)")
            }
        }
    }

    /// Public entry point for direct navigation (e.g., from NotificationsView deep link handling)
    func navigate(to destination: NavigationDestination) {
        performNavigation(to: destination)
    }

    /// ✅ FIX: Navigate only if the target content still exists in Firestore.
    /// If the post or conversation was deleted, fall back to .notifications
    /// instead of navigating to a dead view. Prevents the "push says X, screen
    /// shows nothing" trust-erosion pattern.
    func verifyAndNavigate(to destination: NavigationDestination) {
        Task {
            let verified = await contentExists(for: destination)
            let resolved = verified ? destination : .notifications
            if !verified {
                dlog("⚠️ Deep link target no longer exists — redirecting to notifications")
            }
            performNavigation(to: resolved)
        }
    }

    private func contentExists(for destination: NavigationDestination) async -> Bool {
        lazy var db = Firestore.firestore()
        switch destination {
        case .post(let postId, _):
            let doc = try? await db.collection("posts").document(postId).getDocument()
            return doc?.exists ?? false
        case .conversation(let conversationId, _):
            let doc = try? await db.collection("conversations").document(conversationId).getDocument()
            return doc?.exists ?? false
        default:
            return true  // Profiles, settings, notifications don't need existence checks
        }
    }
    
    /// True once the user is authenticated and the root navigation tree is mounted.
    /// Call `appDidBecomeReady()` from ContentView.onAppear (after auth resolves) to release
    /// any queued cold-start routes.
    private var appReady = false

    private func isAppReady() -> Bool { appReady }

    /// Override for testing or explicit opt-in.
    func markAppReady() {
        guard !appReady else { return }
        appReady = true
        appDidBecomeReady()
    }
    
    // MARK: - URL Scheme Support (for external deep links)
    
    /// Handle deep link URL (e.g., amenapp://post/abc123 or https://amenapp.com/group/join?token=...)
    func handleURL(_ url: URL) {
        // Support universal links (https://amenapp.com/...) alongside custom scheme
        if url.scheme == "https" || url.scheme == "http" {
            guard let host = url.host, host.hasSuffix("amenapp.com") else {
                dlog("⚠️ Unknown universal link host: \(url.host ?? "nil")")
                return
            }
            // Universal links use path as the route: https://amenapp.com/group/join?token=...
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if pathComponents.count >= 2, pathComponents[0] == "group", pathComponents[1] == "join",
               let token = url.queryParameters["token"], !token.isEmpty {
                let destination = NavigationDestination.groupJoinLink(token: token)
                dlog("🔗 Universal link → groupJoinLink(token: \(token.prefix(8))...)")
                navigate(to: destination)
            }
            return
        }
        
        guard url.scheme == "amenapp" || url.scheme == "amen" else {
            dlog("⚠️ Unknown URL scheme: \(url.scheme ?? "nil")")
            return
        }
        
        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        dlog("🔗 Handling deep link: \(host) with path: \(pathComponents)")
        
        let destination: NavigationDestination
        
        switch host {
        case "post":
            if let postId = pathComponents.first {
                let commentId = url.queryParameters["commentId"]
                destination = .post(postId: postId, scrollToCommentId: commentId)
            } else {
                destination = .notifications
            }
            
        case "profile":
            if let userId = pathComponents.first {
                destination = .profile(userId: userId)
            } else {
                destination = .notifications
            }
            
        case "conversation":
            if let conversationId = pathComponents.first {
                let messageId = url.queryParameters["messageId"]
                destination = .conversation(conversationId: conversationId, messageId: messageId)
            } else {
                destination = .messages
            }
            
        case "group":
            // Handle group invite links: amenapp://group/join?token=...
            if pathComponents.first == "join", let token = url.queryParameters["token"], !token.isEmpty {
                destination = .groupJoinLink(token: token)
            } else {
                destination = .messages
            }
            
        case "notifications":
            destination = .notifications
            
        case "messages":
            destination = .messages
            
        case "prayer":
            if let prayerId = pathComponents.first {
                destination = .prayer(prayerId: prayerId)
            } else {
                destination = .notifications
            }
            
        case "church-note":
            if let noteId = pathComponents.first {
                destination = .churchNote(noteId: noteId)
            } else {
                destination = .notifications
            }

        case "intelligence":
            // amenapp://intelligence or amenapp://intelligence/card/{cardId}
            let cardId = pathComponents.count >= 2 && pathComponents[0] == "card"
                ? pathComponents[1]
                : pathComponents.first
            destination = .intelligence(cardId: cardId)

        // ─── Routes ported from amen:// scheme ──────────────────────────────
        case "church":
            // amen://church/{churchId} — open Resources tab where Find a Church lives.
            destination = .church

        case "category":
            // amen://category/{name} — open the Discovery / Search tab
            destination = .discovery

        case "user":
            // amen://user/{userId} — alias for "profile"
            if let userId = pathComponents.first {
                destination = .profile(userId: userId)
            } else {
                destination = .notifications
            }

        case "search":
            // amen://search?q=... — open Discovery / Search tab (tab 1)
            destination = .discovery

        case "settings":
            // amen://settings[/{section}] — open Profile tab where Settings is accessible
            destination = .settings

        case "comment":
            // amen://comment?postId=...&commentId=...&prefill=...
            if let postId = url.queryParameters["postId"], !postId.isEmpty {
                let commentId = url.queryParameters["commentId"]
                if let commentId {
                    CommentFocusCoordinator.shared.set(scrollTarget: commentId, highlight: commentId)
                }
                destination = .post(postId: postId, scrollToCommentId: commentId)
            } else {
                destination = .notifications
            }

        case "chat":
            // amen://chat?threadId=...&prefill=...
            if let threadId = url.queryParameters["threadId"], !threadId.isEmpty {
                destination = .conversation(conversationId: threadId)
            } else {
                destination = .messages
            }
        // ────────────────────────────────────────────────────────────────────

        default:
            dlog("⚠️ Unknown deep link host: \(host)")
            destination = .notifications
        }
        
        performNavigation(to: destination)
    }
}

// MARK: - URL Extension

extension URL {
    var queryParameters: [String: String] {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return [:]
        }
        
        var params: [String: String] = [:]
        for item in queryItems {
            params[item.name] = item.value
        }
        return params
    }
}

// MARK: - SwiftUI View Modifier for Navigation Handling

struct NotificationNavigationHandler: ViewModifier {
    @ObservedObject var router = NotificationDeepLinkRouter.shared
    @Binding var selectedTab: Int  // Reference to tab selection binding
    @State private var pendingAction: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .onChange(of: router.activeDestination) { _, newDestination in
                guard let destination = newDestination else { return }

                // Handle navigation based on destination.
                // Tab layout: 0=Home, 1=Discovery, 2=Messages, 3=Resources, 4=Notifications, 5=Profile
                switch destination {
                case .post(let postId, let scrollToCommentId):
                    selectedTab = 0  // Switch to Home tab
                    // ✅ FIX: Wait for next run loop cycle (view already rendered)
                    // This ensures tab switch completes before posting notification
                    pendingAction = {
                        NotificationCenter.default.post(
                            name: .openPostFromNotification,
                            object: nil,
                            userInfo: ["postId": postId, "scrollToCommentId": scrollToCommentId as Any]
                        )
                    }
                    
                case .profile(let userId):
                    selectedTab = 5  // Switch to Profile tab
                    pendingAction = {
                        NotificationCenter.default.post(
                            name: .openProfileFromNotification,
                            object: nil,
                            userInfo: ["userId": userId]
                        )
                    }
                    
                case .conversation(let conversationId, _):
                    selectedTab = 2  // Switch to Messages tab
                    pendingAction = {
                        NotificationCenter.default.post(
                            name: .openConversation,
                            object: nil,
                            userInfo: ["conversationId": conversationId]
                        )
                    }
                    
                case .messages:
                    selectedTab = 2  // Messages tab
                    pendingAction = nil
                    
                case .notifications:
                    selectedTab = 4  // Notifications tab
                    pendingAction = nil
                    
                case .prayer, .churchNote:
                    // Routed to Resources tab which contains Prayer and Church Notes
                    selectedTab = 3
                    pendingAction = nil
                    
                case .job:
                    // Jobs are accessible via AMEN Connect (Resources tab)
                    selectedTab = 3
                    pendingAction = nil
                    
                case .event:
                    // Events are accessible via Resources tab
                    selectedTab = 3
                    pendingAction = nil
                    
                case .studioProfile:
                    // Studio profiles are accessible via Resources tab
                    selectedTab = 3
                    pendingAction = nil
                    
                case .groupJoinLink(let token):
                    selectedTab = 2  // Switch to Messages tab
                    pendingAction = {
                        NotificationCenter.default.post(
                            name: .openGroupJoinLink,
                            object: nil,
                            userInfo: ["token": token]
                        )
                    }

                case .intelligence:
                    selectedTab = 7  // Switch to Intelligence Brief tab
                    pendingAction = nil

                case .discovery:
                    selectedTab = 1  // Discovery / Search tab
                    pendingAction = nil

                case .settings:
                    selectedTab = 5  // Profile tab — Settings reachable from here
                    pendingAction = nil

                case .church:
                    selectedTab = 3  // Resources tab — Find a Church lives here
                    pendingAction = nil
                }

                // Clear destination after handling
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s for tab transition
                    router.clearDestination()
                }
            }
            .onChange(of: selectedTab) { oldTab, newTab in
                // ✅ FIX: Execute pending action when tab finishes switching
                // This ensures the target view is mounted before we post notification
                if let action = pendingAction {
                    Task { @MainActor in
                        // Wait one more run loop for view to fully appear
                        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                        action()
                        pendingAction = nil
                    }
                }
            }
    }
}

extension View {
    func handleNotificationNavigation(selectedTab: Binding<Int>) -> some View {
        modifier(NotificationNavigationHandler(selectedTab: selectedTab))
    }
}
