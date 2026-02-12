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
import FirebaseAppCheck
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        print("🚀 AppDelegate: didFinishLaunchingWithOptions")
        
        // ✅ Suppress noisy system logging (network framework, CoreTelephony XPC, etc.)
        setenv("OS_ACTIVITY_MODE", "disable", 1)
        setenv("OS_ACTIVITY_DT_MODE", "NO", 1)
        
        // ✅ Suppress CoreTelephony XPC errors (simulator-only issue)
        #if targetEnvironment(simulator)
        UserDefaults.standard.set(false, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
        #endif
        
        // Configure Firebase FIRST
        FirebaseApp.configure()
        print("✅ Firebase configured successfully")
        
        // Configure App Check AFTER Firebase.configure()
        #if DEBUG
        // ✅ For DEBUG builds: Use Debug provider (simulator-friendly)
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        print("✅ App Check configured with Debug Provider (development mode)")
        
        // Get and display the debug token for Firebase Console registration
        Task {
            do {
                let token = try await AppCheck.appCheck().token(forcingRefresh: false)
                print("🔑 App Check Debug Token: \(token.token)")
                print("📝 Add this token to Firebase Console → App Check → Apps → Debug Tokens")
            } catch {
                print("⚠️ App Check token error (expected in simulator): \(error.localizedDescription)")
                print("💡 This is normal - App Check will use placeholder tokens in debug mode")
            }
        }
        #else
        // ✅ For PRODUCTION builds: Use DeviceCheck provider
        // NOTE: You must register your app in Firebase Console → App Check before releasing
        let providerFactory = DeviceCheckProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        print("✅ App Check configured with DeviceCheck Provider (production mode)")
        print("⚠️ IMPORTANT: Ensure app is registered in Firebase Console → App Check")
        #endif
        
        // Configure Firestore settings IMMEDIATELY after Firebase.configure()
        // This must happen before any Firestore access
        let firestoreSettings = FirestoreSettings()
        firestoreSettings.isPersistenceEnabled = true
        // Use the modern cacheSettings API (not the deprecated cacheSizeBytes)
        firestoreSettings.cacheSettings = PersistentCacheSettings(sizeBytes: FirestoreCacheSizeUnlimited as NSNumber)
        Firestore.firestore().settings = firestoreSettings
        print("✅ Firestore settings configured (persistence enabled, unlimited cache)")
        
        // ✅ Enable Firebase Realtime Database offline persistence
        // This must be called AFTER Firebase.configure() and BEFORE any database operations
        // CRITICAL: Enable persistence on the CORRECT database instance with the URL
        let databaseURL = "https://amen-5e359-default-rtdb.firebaseio.com"
        let database = Database.database(url: databaseURL)
        database.isPersistenceEnabled = true
        database.persistenceCacheSizeBytes = 50 * 1024 * 1024  // 50MB cache
        print("✅ Firebase Realtime Database offline persistence enabled (50MB cache)")
        print("✅ Realtime Database URL configured: \(databaseURL)")
        
        // Setup push notifications
        setupPushNotifications()
        
        return true
    }
    
    // MARK: - Push Notification Setup
    
    private func setupPushNotifications() {
        let center = UNUserNotificationCenter.current()
        
        // Use composite delegate that handles both Firebase and Church notifications
        center.delegate = CompositeNotificationDelegate.shared
        
        // Set FCM delegate - PushNotificationManager conforms to MessagingDelegate
        Messaging.messaging().delegate = PushNotificationManager.shared as MessagingDelegate
        
        // Setup FCM token
        PushNotificationManager.shared.setupFCMToken()
        
        print("✅ Push notification delegates configured")
        
        // Initialize church notification categories (for Find Church feature)
        Task { @MainActor in
            ChurchNotificationManager.shared.setupNotificationCategories()
            print("✅ Church notification categories initialized")
        }
        
        // ✅ PHASE 1: Register for remote notifications
        UIApplication.shared.registerForRemoteNotifications()
        print("✅ Registered for remote notifications")
    }
    
    // MARK: - Handle Remote Notifications
    // Note: didRegisterForRemoteNotificationsWithDeviceToken and 
    // didFailToRegisterForRemoteNotificationsWithError are defined in AppDelegate+Messaging.swift
    
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
