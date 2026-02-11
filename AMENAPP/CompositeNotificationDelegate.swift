//
//  CompositeNotificationDelegate.swift
//  AMENAPP
//
//  Created by Assistant on 2/2/26.
//
//  Composite delegate that handles both Firebase push notifications
//  and local church notifications
//

import UserNotifications
import FirebaseMessaging

@MainActor
class CompositeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CompositeNotificationDelegate()
    
    private override init() {
        super.init()
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    /// Handle notification presentation when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        
        // Check if this is a church notification by looking at the category
        if notification.request.content.categoryIdentifier.contains("church") {
            // Delegate to ChurchNotificationManager
            ChurchNotificationManager.shared.userNotificationCenter(
                center,
                willPresent: notification,
                withCompletionHandler: completionHandler
            )
        } else {
            // This is a Firebase push notification - show it
            completionHandler([.banner, .sound, .badge])
        }
    }
    
    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Check if this is a church notification
        if response.notification.request.content.categoryIdentifier.contains("church") {
            // Delegate to ChurchNotificationManager
            ChurchNotificationManager.shared.userNotificationCenter(
                center,
                didReceive: response,
                withCompletionHandler: completionHandler
            )
        } else {
            // Handle Firebase push notification tap
            handlePushNotificationTap(response: response)
            completionHandler()
        }
    }
    
    // MARK: - Handle Push Notification Tap
    
    private func handlePushNotificationTap(response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        
        print("📱 Push notification tapped")
        print("   User Info: \(userInfo)")
        
        // Extract notification type and handle accordingly
        if let notificationType = userInfo["type"] as? String {
            switch notificationType {
            case "new_follower":
                print("   Type: New Follower")
                // Navigate to profile or followers list
                
            case "new_like":
                print("   Type: New Like")
                // Navigate to the liked post
                
            case "new_comment":
                print("   Type: New Comment")
                // Navigate to the post with comment
                
            case "new_message":
                print("   Type: New Message")
                // Navigate to messages
                
            default:
                print("   Type: Unknown (\(notificationType))")
            }
        }
        
        // Update badge count
        Task { @MainActor in
            PushNotificationManager.shared.updateBadgeCount()
        }
    }
}
