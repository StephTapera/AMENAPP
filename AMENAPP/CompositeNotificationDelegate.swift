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
import FirebaseAuth
import FirebaseFirestore

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
        
        // ✅ ENHANCED SMART SUPPRESSION: Check all notification types
        if let typeString = userInfo["type"] as? String {
            // Message notifications - always suppress in foreground
            if typeString == "message" || typeString == "message_request" {
                print("🔕 Suppressing message notification (foreground)")
                completionHandler([])
                return
            }
            
            // ✅ P0-6 FIX: Filter notifications from blocked users
            if let actorId = userInfo["actorId"] as? String {
                if shouldFilterNotification(actorId: actorId) {
                    print("🔕 Filtering notification from blocked user: \(actorId)")
                    completionHandler([])
                    return
                }
            }
        }
        
        // Show notification with banner, sound, and badge
        completionHandler([.banner, .sound, .badge])
    }
    
    /// Helper to check if notification should be filtered (blocked user)
    private func shouldFilterNotification(actorId: String?) -> Bool {
        guard let actorId = actorId else { return false }
        return BlockService.shared.blockedUsers.contains(actorId)
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
