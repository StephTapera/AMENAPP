//
//  NotificationDeepLinkRouter.swift
//  AMENAPP
//
//  Production-grade deep link routing for notifications
//  Handles navigation to posts, comments, threads, profiles, conversations
//

import Foundation
import SwiftUI
import Combine

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
        case notifications
        case messages
        case prayer(prayerId: String)
        case churchNote(noteId: String)
        case job(jobId: String)
        case event(eventId: String)
        case studioProfile(creatorId: String)

        static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
            switch (lhs, rhs) {
            case (.post(let id1, let comment1), .post(let id2, let comment2)):
                return id1 == id2 && comment1 == comment2
            case (.profile(let id1), .profile(let id2)):
                return id1 == id2
            case (.conversation(let id1, let msg1), .conversation(let id2, let msg2)):
                return id1 == id2 && msg1 == msg2
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
        
        print("🔗 Routing notification to: \(destination)")
        
        // Track engagement for smart notification engine
        SmartNotificationEngine.shared.recordNotificationInteraction(notification)
        
        // Navigate
        performNavigation(to: destination)
    }
    
    /// Route from push notification payload
    func routeFromPushPayload(_ userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else {
            print("⚠️ No type in push notification payload")
            return
        }
        
        print("🔗 Routing push notification: \(type)")
        
        let destination: NavigationDestination
        
        switch type {
        case "follow", "followRequestAccepted":
            if let actorId = userInfo["actorId"] as? String {
                destination = .profile(userId: actorId)
            } else {
                destination = .notifications
            }
            
        case "comment", "reply":
            if let postId = userInfo["postId"] as? String {
                let commentId = userInfo["commentId"] as? String
                destination = .post(postId: postId, scrollToCommentId: commentId)
            } else {
                destination = .notifications
            }
            
        case "mention":
            if let postId = userInfo["postId"] as? String {
                destination = .post(postId: postId)
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
            
        default:
            destination = .notifications
        }
        
        performNavigation(to: destination)
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
            
        case .churchNoteShared:
            if let noteId = notification.noteId {
                return .churchNote(noteId: noteId)
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

        // P1 FIX: Debounce rapid navigation requests. If two notifications arrive
        // within 0.6s and the first destination hasn't been consumed yet, queue the
        // second. It will be processed by clearDestination() after the UI settles.
        if now.timeIntervalSince(lastNavigationTime) < navigationDebounceInterval,
           activeDestination != nil {
            pendingNavigation = destination
            print("⏸️ Debounced navigation (rapid arrival): \(destination)")
            return
        }

        lastNavigationTime = now

        if isAppReady() {
            activeDestination = destination
            print("✅ Navigating to: \(destination)")
        } else {
            // Queue navigation for when app is ready
            pendingNavigation = destination
            print("⏸️ Queued navigation (app not ready): \(destination)")
        }
    }

    /// Call this when app is ready to handle navigation
    func appDidBecomeReady() {
        if let pending = pendingNavigation {
            print("▶️ Processing pending navigation: \(pending)")
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
                print("▶️ Processing queued navigation: \(queued)")
            }
        }
    }

    /// Public entry point for direct navigation (e.g., from NotificationsView deep link handling)
    func navigate(to destination: NavigationDestination) {
        performNavigation(to: destination)
    }
    
    private func isAppReady() -> Bool {
        // Check if root view is loaded and user is authenticated
        // This is a simple check - in production you might have more sophisticated logic
        return true  // For now, assume app is always ready
    }
    
    // MARK: - URL Scheme Support (for external deep links)
    
    /// Handle deep link URL (e.g., amenapp://post/abc123)
    func handleURL(_ url: URL) {
        guard url.scheme == "amenapp" else {
            print("⚠️ Unknown URL scheme: \(url.scheme ?? "nil")")
            return
        }
        
        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        print("🔗 Handling deep link: \(host) with path: \(pathComponents)")
        
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
            
        default:
            print("⚠️ Unknown deep link host: \(host)")
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

    func body(content: Content) -> some View {
        content
            .onChange(of: router.activeDestination) { _, newDestination in
                guard let destination = newDestination else { return }

                // Handle navigation based on destination.
                // Tab layout: 0=Home, 1=Discovery, 2=Messages, 3=Resources, 4=Notifications, 5=Profile
                switch destination {
                case .post(let postId, let scrollToCommentId):
                    selectedTab = 0  // Switch to Home tab
                    // Give the tab a moment to appear, then post notification for HomeView to open post detail
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        NotificationCenter.default.post(
                            name: .openPostFromNotification,
                            object: nil,
                            userInfo: ["postId": postId, "scrollToCommentId": scrollToCommentId as Any]
                        )
                    }
                case .profile(let userId):
                    selectedTab = 5  // Switch to Profile tab
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        NotificationCenter.default.post(
                            name: .openProfileFromNotification,
                            object: nil,
                            userInfo: ["userId": userId]
                        )
                    }
                case .conversation(let conversationId, _):
                    selectedTab = 2  // Switch to Messages tab
                    // Trigger MessagingCoordinator to open the specific conversation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        NotificationCenter.default.post(
                            name: .openConversation,
                            object: nil,
                            userInfo: ["conversationId": conversationId]
                        )
                    }
                case .messages:
                    selectedTab = 2  // Messages tab
                case .notifications:
                    selectedTab = 4  // Notifications tab
                case .prayer, .churchNote:
                    // Routed to Resources tab which contains Prayer and Church Notes
                    selectedTab = 3
                }

                // Clear destination after handling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    router.clearDestination()
                }
            }
    }
}

extension View {
    func handleNotificationNavigation(selectedTab: Binding<Int>) -> some View {
        modifier(NotificationNavigationHandler(selectedTab: selectedTab))
    }
}
