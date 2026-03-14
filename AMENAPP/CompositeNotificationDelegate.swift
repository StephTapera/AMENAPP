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
import UIKit
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
            // Message notifications - always suppress in foreground (handled by UnifiedChatView)
            if typeString == "message" || typeString == "message_request" {
                completionHandler([])
                return
            }
            
            // ✅ P0-6 FIX: Filter notifications from blocked users
            if let actorId = userInfo["actorId"] as? String {
                if shouldFilterNotification(actorId: actorId) {
                    completionHandler([])
                    return
                }
            }
        }
        
        // ✅ Suppress system banner for social notifications — the custom
        // InAppNotificationBanner (Instagram-style heads-up) replaces it.
        // Still update badge and play sound so the user knows something arrived.
        completionHandler([.badge, .sound])
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
        
        let userInfo = response.notification.request.content.userInfo

        // Handle specific actions for church notifications
        if actionIdentifier == "GET_DIRECTIONS" {
            print("   Opening directions to church")
            // Open Maps with church location from notification payload
            if let latStr = userInfo["churchLat"] as? String,
               let lngStr = userInfo["churchLng"] as? String,
               let lat = Double(latStr), let lng = Double(lngStr),
               let mapsURL = URL(string: "maps://?daddr=\(lat),\(lng)&dirflg=d"),
               UIApplication.shared.canOpenURL(mapsURL) {
                UIApplication.shared.open(mapsURL)
            } else if let address = userInfo["churchAddress"] as? String,
                      let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let mapsURL = URL(string: "maps://?daddr=\(encoded)&dirflg=d") {
                UIApplication.shared.open(mapsURL)
            }
            // Also switch to Find Church tab
            NotificationCenter.default.post(name: .navigateToFindChurch, object: nil)
        } else if actionIdentifier == UNNotificationDefaultActionIdentifier {
            // User tapped the notification body — navigate to Find Church tab
            print("   Opening church details")
            NotificationCenter.default.post(name: .navigateToFindChurch, object: nil)
        }
    }
    
    // MARK: - Handle Push Notification Tap
    
    private func handlePushNotificationTap(response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        
        print("📱 Push notification tapped, routing via NotificationDeepLinkRouter")
        
        // Route to the correct screen using the deep link router
        NotificationDeepLinkRouter.shared.routeFromPushPayload(userInfo)
        
        // Update badge count
        Task { @MainActor in
            PushNotificationManager.shared.updateBadgeCount()
        }
    }
}
