//
//  PushNotificationHandler.swift
//  AMENAPP
//
//  Handles incoming push notifications and deep linking
//

import Foundation
import UIKit
import UserNotifications
import FirebaseMessaging

@MainActor
class PushNotificationHandler: NSObject, ObservableObject {
    static let shared = PushNotificationHandler()
    
    @Published var pendingDeepLink: NotificationDeepLink?
    
    private override init() {
        super.init()
    }
    
    /// Handle notification when app is in foreground
    func handleForegroundNotification(_ notification: UNNotification) {
        let userInfo = notification.request.content.userInfo
        
        print("📬 Received foreground notification")
        print("   Title:", notification.request.content.title)
        print("   Body:", notification.request.content.body)
        print("   UserInfo:", userInfo)
        
        // Update badge count
        if let badge = notification.request.content.badge?.intValue {
            UIApplication.shared.applicationIconBadgeNumber = badge
        }
        
        // Refresh notifications
        NotificationService.shared.startListening()
    }
    
    /// Handle notification tap (user tapped notification)
    func handleNotificationTap(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        
        print("👆 User tapped notification")
        print("   UserInfo:", userInfo)
        
        // Extract notification data
        guard let type = userInfo["type"] as? String else {
            print("⚠️ No notification type found")
            return
        }
        
        // Create deep link based on notification type
        switch type {
        case "follow", "follow_request_accepted":
            if let actorId = userInfo["actorId"] as? String {
                pendingDeepLink = .profile(userId: actorId)
            }
            
        case "amen", "comment", "reply", "mention":
            if let postId = userInfo["postId"] as? String {
                pendingDeepLink = .post(postId: postId)
            }
            
        case "message_request_accepted":
            if let actorId = userInfo["actorId"] as? String {
                pendingDeepLink = .conversation(userId: actorId)
            }
            
        default:
            print("⚠️ Unknown notification type:", type)
        }
        
        // Mark notification as read if we have the ID
        if let notificationId = userInfo["notificationId"] as? String {
            Task {
                try? await NotificationService.shared.markAsRead(notificationId)
            }
        }
    }
    
    /// Save FCM token to Firestore
    func saveFCMToken(_ token: String, for userId: String) async throws {
        print("💾 Saving FCM token to Firestore")
        print("   User ID:", userId)
        print("   Token:", token)
        
        let db = FirebaseManager.shared.firestore
        
        try await db.collection("users").document(userId).updateData([
            "fcmToken": token,
            "fcmTokenUpdatedAt": FirebaseManager.shared.serverTimestamp
        ])
        
        print("✅ FCM token saved successfully")
    }
    
    /// Remove FCM token on sign out
    func removeFCMToken(for userId: String) async {
        print("🗑️ Removing FCM token from Firestore")
        print("   User ID:", userId)
        
        let db = FirebaseManager.shared.firestore
        
        do {
            try await db.collection("users").document(userId).updateData([
                "fcmToken": FieldValue.delete()
            ])
            print("✅ FCM token removed successfully")
        } catch {
            print("❌ Failed to remove FCM token:", error)
        }
    }
}

// MARK: - Deep Link Types

enum NotificationDeepLink: Equatable {
    case profile(userId: String)
    case post(postId: String)
    case conversation(userId: String)
    case notifications
    
    var navigationPath: String {
        switch self {
        case .profile(let userId):
            return "profile_\(userId)"
        case .post(let postId):
            return "post_\(postId)"
        case .conversation(let userId):
            return "conversation_\(userId)"
        case .notifications:
            return "notifications"
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationHandler: UNUserNotificationCenterDelegate {
    /// Called when notification arrives while app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            handleForegroundNotification(notification)
        }
        
        // Show banner, badge, and sound even when app is in foreground
        completionHandler([.banner, .badge, .sound])
    }
    
    /// Called when user taps notification
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            handleNotificationTap(response)
        }
        
        completionHandler()
    }
}

// MARK: - MessagingDelegate

extension PushNotificationHandler: MessagingDelegate {
    /// Called when FCM token is refreshed
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("🔄 FCM Token refreshed")
        
        guard let token = fcmToken else {
            print("⚠️ No FCM token received")
            return
        }
        
        print("   New token:", token)
        
        // Save token to Firestore
        Task { @MainActor in
            guard let userId = FirebaseManager.shared.currentUser?.uid else {
                print("⚠️ No authenticated user to save FCM token")
                return
            }
            
            try? await saveFCMToken(token, for: userId)
        }
    }
}
