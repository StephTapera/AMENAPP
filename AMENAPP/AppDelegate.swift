//
//  AppDelegate.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//
//  Handles Firebase initialization and push notification setup
//

import UIKit
import FirebaseCore
import FirebaseMessaging
import FirebaseDatabase
import FirebaseFirestore
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        print("🚀 AppDelegate: didFinishLaunchingWithOptions")
        
        // Configure Firebase
        FirebaseApp.configure()
        print("✅ Firebase configured successfully")
        
        // Configure Firestore settings IMMEDIATELY after Firebase.configure()
        // This must happen before any Firestore access
        let firestoreSettings = FirestoreSettings()
        firestoreSettings.isPersistenceEnabled = true
        // Use the modern cacheSettings API (not the deprecated cacheSizeBytes)
        firestoreSettings.cacheSettings = PersistentCacheSettings(sizeBytes: FirestoreCacheSizeUnlimited as NSNumber)
        Firestore.firestore().settings = firestoreSettings
        print("✅ Firestore settings configured (persistence enabled, unlimited cache)")
        
        // Configure Realtime Database URL
        // NOTE: Persistence must be enabled BEFORE first access to the database
        // This is done in RealtimeDatabaseService to ensure correct timing
        let databaseURL = "https://amen-5e359-default-rtdb.firebaseio.com"
        print("✅ Realtime Database URL: \(databaseURL)")
        
        // Setup push notifications
        setupPushNotifications()
        
        return true
    }
    
    // MARK: - Push Notification Setup
    
    private func setupPushNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = PushNotificationManager.shared
        
        // Set FCM delegate
        Messaging.messaging().delegate = PushNotificationManager.shared
        
        print("✅ Push notification delegates configured")
    }
    
    // MARK: - Remote Notification Registration
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("📱 AppDelegate: didRegisterForRemoteNotifications")
        
        Task { @MainActor in
            PushNotificationManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
        
        // Pass to FCM
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ AppDelegate: didFailToRegisterForRemoteNotifications")
        
        Task { @MainActor in
            PushNotificationManager.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }
    
    // MARK: - Handle Remote Notifications
    
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("📬 AppDelegate: didReceiveRemoteNotification")
        print("   User Info: \(userInfo)")
        
        // Handle notification data
        if let messageID = userInfo["gcm.message_id"] as? String {
            print("   Message ID: \(messageID)")
        }
        
        Task { @MainActor in
            PushNotificationManager.shared.updateBadgeCount()
        }
        
        completionHandler(.newData)
    }
}
