//
//  NotificationAggregationService.swift
//  AMENAPP
//
//  Production-grade notification aggregation and batching system
//  Instagram/Threads-level notification grouping and foreground suppression
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit
import Combine

/// Manages intelligent notification aggregation, batching, and foreground suppression
@MainActor
final class NotificationAggregationService: ObservableObject {
    
    static let shared = NotificationAggregationService()
    
    private let db = Firestore.firestore()
    
    // MARK: - Foreground Suppression State
    
    /// Track which screen user is currently viewing
    @Published private(set) var currentScreen: AppScreen = .none
    
    /// Track active post/conversation IDs to suppress notifications for
    @Published private(set) var activePostId: String?
    @Published private(set) var activeConversationId: String?
    @Published private(set) var activeProfileUserId: String?
    
    enum AppScreen: Equatable {
        case none
        case home
        case notifications
        case messages
        case profile(userId: String)
        case post(postId: String)
        case conversation(conversationId: String)
    }
    
    // MARK: - Recent Notification Tracking (for aggregation windows)
    
    private var recentNotifications: [String: [Date]] = [:]  // key: type_targetId, value: timestamps
    private let aggregationWindow: TimeInterval = 30 * 60  // 10-30 min window (30 min = 1800 seconds)
    
    // MARK: - Initialization
    
    private init() {
        setupScreenObservers()
    }
    
    // MARK: - Screen State Tracking
    
    /// Call this when user navigates to a new screen
    func updateCurrentScreen(_ screen: AppScreen) {
        guard currentScreen != screen else { return }
        currentScreen = screen
        
        switch screen {
        case .post(let postId):
            activePostId = postId
        case .conversation(let conversationId):
            activeConversationId = conversationId
        case .profile(let userId):
            activeProfileUserId = userId
        default:
            activePostId = nil
            activeConversationId = nil
            activeProfileUserId = nil
        }
        
        dlog("📱 Current screen updated: \(screen)")
    }
    
    /// Check if notification should be suppressed based on current screen
    func shouldSuppressNotification(_ notification: AppNotification) -> Bool {
        // ✅ SUPPRESS ALL NOTIFICATIONS WHEN USER IS VIEWING THAT CONTENT
        
        switch currentScreen {
        case .post(let postId):
            // Suppress notifications about this post
            if notification.postId == postId {
                dlog("🔕 Suppressing notification: user viewing post \(postId)")
                return true
            }
            
        case .conversation(let conversationId):
            // Suppress message notifications for this conversation
            if (notification.type == .message || notification.type == .messageRequest)
                && notification.conversationId == conversationId {
                dlog("🔕 Suppressing message notification: user in active conversation \(conversationId)")
                return true
            }
            
        case .notifications:
            // Don't suppress in notifications view - user wants to see updates
            return false
            
        case .messages:
            // Suppress ALL message notifications when in messages view
            if notification.type == .message || notification.type == .messageRequest {
                dlog("🔕 Suppressing message notification: user in messages view")
                return true
            }
            
        case .profile(let userId):
            // Suppress notifications from this user's actions
            if notification.actorId == userId {
                dlog("🔕 Suppressing notification: user viewing profile of actor")
                return true
            }
            
        default:
            break
        }
        
        return false
    }
    
    /// Check if this is a self-generated action that should be suppressed
    func isSelfAction(_ notification: AppNotification) -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        
        // ✅ SUPPRESS ALL SELF-GENERATED NOTIFICATIONS
        if notification.actorId == currentUserId {
            dlog("🔕 Suppressing self-action notification: \(notification.type.rawValue)")
            return true
        }
        
        return false
    }
    
    /// Check if notification should be blocked due to privacy rules
    func shouldBlockNotification(_ notification: AppNotification) async -> Bool {
        guard let actorId = notification.actorId,
              let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }
        
        // ✅ BLOCK NOTIFICATIONS FROM BLOCKED USERS
        do {
            // Check if actor is blocked
            let blockedDoc = try await db.collection("users")
                .document(currentUserId)
                .collection("blocked")
                .document(actorId)
                .getDocument()
            
            if blockedDoc.exists {
                dlog("🚫 Blocking notification from blocked user: \(actorId)")
                return true
            }
            
            // Check if actor has blocked current user
            let blockedByDoc = try await db.collection("users")
                .document(actorId)
                .collection("blocked")
                .document(currentUserId)
                .getDocument()
            
            if blockedByDoc.exists {
                dlog("🚫 Blocking notification from user who blocked you: \(actorId)")
                return true
            }
            
        } catch {
            dlog("⚠️ Error checking block status: \(error)")
            // Don't block on error - fail open
        }
        
        return false
    }
    
    // MARK: - Aggregation Windows
    
    /// Check if notification should be aggregated with recent ones
    func shouldAggregateNotification(
        _ notification: AppNotification,
        existingNotifications: [AppNotification]
    ) -> String? {
        let now = Date()
        
        // Generate aggregation key based on type and target
        let aggregationKey: String
        if let postId = notification.postId {
            // Group by type + post (e.g., all likes on post X)
            aggregationKey = "\(notification.type.rawValue)_\(postId)"
        } else {
            // Group by type only (e.g., all follow notifications)
            aggregationKey = notification.type.rawValue
        }
        
        // Check if there are recent notifications of this type
        let recentOfType = existingNotifications.filter { existingNotif in
            // Match by type and target
            if let existingPostId = existingNotif.postId, let currentPostId = notification.postId {
                return existingNotif.type == notification.type && existingPostId == currentPostId
            } else {
                return existingNotif.type == notification.type
            }
        }
        
        // If there are recent notifications within the aggregation window, return the key
        for existingNotif in recentOfType {
            let timeSinceNotification = now.timeIntervalSince(existingNotif.createdAt.dateValue())
            if timeSinceNotification <= aggregationWindow {
                dlog("📊 Aggregation opportunity: \(aggregationKey) within \(Int(timeSinceNotification))s")
                return aggregationKey
            }
        }
        
        return nil
    }
    
    /// Generate aggregated notification text (Instagram-style)
    func generateAggregatedText(
        for notifications: [AppNotification]
    ) -> String {
        guard let firstNotification = notifications.first else { return "" }
        
        let type = firstNotification.type
        let count = notifications.count
        
        if count == 1 {
            let notif = notifications[0]
            return "\(notif.actorName ?? "Someone") \(notif.actionText)"
        } else if count == 2 {
            let name1 = notifications[0].actorName ?? "Someone"
            let name2 = notifications[1].actorName ?? "someone"
            return "\(name1) and \(name2) \(type == .amen ? "liked" : type == .comment ? "commented on" : "interacted with") your post"
        } else {
            let firstName = notifications[0].actorName ?? "Someone"
            let othersCount = count - 1
            
            switch type {
            case .amen:
                return "\(firstName) and \(othersCount) others liked your post"
            case .comment:
                return "\(firstName) and \(othersCount) others commented on your post"
            case .follow:
                return "\(firstName) and \(othersCount) others started following you"
            default:
                return "\(firstName) and \(othersCount) others \(notifications[0].actionText)"
            }
        }
    }
    
    // MARK: - Setup Observers
    
    private func setupScreenObservers() {
        // Listen for app foreground/background events
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            dlog("🔆 App entering foreground")
            // Reset screen tracking
            Task { @MainActor [weak self] in self?.currentScreen = .none }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            dlog("🌙 App entering background")
            Task { @MainActor [weak self] in self?.currentScreen = .none }
        }
    }
}

// MARK: - Screen Tracking Extension

extension NotificationAggregationService {
    /// Convenience method to track post viewing
    func trackPostViewing(_ postId: String?) {
        if let postId = postId {
            updateCurrentScreen(.post(postId: postId))
        } else {
            updateCurrentScreen(.home)
        }
    }
    
    /// Convenience method to track conversation viewing
    func trackConversationViewing(_ conversationId: String?) {
        if let conversationId = conversationId {
            updateCurrentScreen(.conversation(conversationId: conversationId))
        } else {
            updateCurrentScreen(.messages)
        }
    }
    
    /// Convenience method to track profile viewing
    func trackProfileViewing(_ userId: String?) {
        if let userId = userId {
            updateCurrentScreen(.profile(userId: userId))
        } else {
            updateCurrentScreen(.home)
        }
    }
}
