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
        if notification.request.content.categoryIdentifier.contains("church") ||
           notification.request.content.categoryIdentifier.contains("SERVICE_REMINDER") {
            // Show church notifications with banner, sound, and badge
            completionHandler([.banner, .sound, .badge])
            return
        }
        
        // ✅ SMART NOTIFICATION HANDLING: Suppress FCM push notifications when app is in foreground
        // The in-app Firestore notification will be shown instead via NotificationService
        // This prevents duplicate notifications (FCM push + Firestore document)
        
        // Check if this is a message notification
        if let notificationType = userInfo["type"] as? String {
            if notificationType == "message" || notificationType == "message_request" {
                print("🔕 Suppressing FCM message notification (app in foreground - Firestore notification will show instead)")
                // Don't show the FCM push notification banner
                completionHandler([])
                return
            }
        }
        
        // For other notification types, show them with banner, sound, and badge
        completionHandler([.banner, .sound, .badge])
    }
    
    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        
        // Check if this is a church notification
        if categoryIdentifier.contains("church") || categoryIdentifier.contains("SERVICE_REMINDER") {
            // Handle church notification tap
            handleChurchNotificationTap(response: response)
            completionHandler()
        } else {
            // Handle Firebase push notification tap
            handlePushNotificationTap(response: response)
            completionHandler()
        }
    }
    
    // MARK: - Handle Church Notification Tap
    
    private func handleChurchNotificationTap(response: UNNotificationResponse) {
        let actionIdentifier = response.actionIdentifier
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        
        print("⛪️ Church notification tapped")
        print("   Category: \(categoryIdentifier)")
        print("   Action: \(actionIdentifier)")
        
        // Handle specific actions for church notifications
        if actionIdentifier == "GET_DIRECTIONS" {
            print("   Opening directions to church")
            // TODO: Extract church data and open Maps
        } else if actionIdentifier == UNNotificationDefaultActionIdentifier {
            // User tapped the notification itself (not an action button)
            print("   Opening church details")
            // TODO: Navigate to church details or FindChurchView
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
