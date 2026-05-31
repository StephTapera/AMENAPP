//
//  AppDelegate+Messaging.swift
//  AMENAPP
//
//  AppDelegate extension for messaging and push notifications
//  Add these methods to your existing AppDelegate
//

import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

// MARK: - Push Notification Setup

extension AppDelegate {

    /// Handle successful APNS token registration
    func application(_ application: UIApplication, 
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Pass device token to FCM — must be set before FCM token is fetched
        Messaging.messaging().apnsToken = deviceToken
        dlog("✅ APNS token registered")
        
        // If FCM token hasn't been obtained yet (race: APNS arrived after initial fetch),
        // retry the token fetch now that APNS is available.
        PushNotificationManager.shared.retryFCMTokenIfNeeded()
    }
    
    /// Handle failed APNS token registration
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if targetEnvironment(simulator)
        // Simulator has no APNS hardware — registration always fails here.
        dlog("⚠️ Remote notification registration unavailable on simulator (expected): \(error.localizedDescription)")
        #else
        dlog("❌ Failed to register for remote notifications: \(error)")
        #endif
    }
}

// MARK: - Notification Handling
// Note: Notification delegate methods are handled by CompositeNotificationDelegate
// which is set in setupMessaging(). The CompositeNotificationDelegate coordinates
// between PushNotificationManager and ChurchNotificationManager.
//
// If you need custom notification handling in AppDelegate, you can extend
// CompositeNotificationDelegate or PushNotificationManager instead.


