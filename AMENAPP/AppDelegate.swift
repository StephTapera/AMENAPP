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
import FirebaseAuth
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

        #if targetEnvironment(simulator)
        // ✅ Suppress simulator-only system noise:
        //   - CoreTelephony XPC errors (no cellular radio in simulator)
        //   - nw_connection "unconnected" warnings (network framework noise)
        //   - IOSurface / quic / QUIC packet queue warnings
        setenv("CFNETWORK_DIAGNOSTICS", "0", 1)
        setenv("ACTIVITY_LOG_STDERR", "0", 1)
        UserDefaults.standard.set(false, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
        // Redirect stderr to /dev/null to silence kernel/framework noise that cannot
        // be suppressed any other way. App print() calls go to stdout, so they are unaffected.
        if let devNull = fopen("/dev/null", "w") {
            dup2(fileno(devNull), STDERR_FILENO)
            fclose(devNull)
        }
        #endif
        
        // ✅ App Check MUST be configured BEFORE FirebaseApp.configure()
        // Simulator uses the debug provider; real devices use App Attest.
        #if targetEnvironment(simulator)
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        print("✅ App Check configured with Debug Provider (simulator)")
        #else
        let providerFactory = AppCheckAppAttestProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        print("✅ App Check configured with App Attest Provider (real device)")
        #endif
        
        // Configure Firebase AFTER App Check provider is set
        FirebaseApp.configure()
        print("✅ Firebase configured successfully")
        
        // Pre-warm App Check token at launch so it's ready by the time user taps sign up.
        // This moves the attestation delay (can be several seconds) out of the auth flow.
        Task {
            do {
                let token = try await AppCheck.appCheck().token(forcingRefresh: false)
                print("✅ App Check token pre-warmed: \(token.token.prefix(20))...")
            } catch {
                // Non-fatal — SDK will fall back to placeholder token when unenforced
                print("⚠️ App Check pre-warm failed (monitoring mode will handle): \(error.localizedDescription)")
            }
        }
        
        // Configure Firestore settings IMMEDIATELY after Firebase.configure()
        // This must happen before any Firestore access
        let firestoreSettings = FirestoreSettings()
        // Use the modern cacheSettings API (replaces deprecated isPersistenceEnabled + cacheSizeBytes)
        firestoreSettings.cacheSettings = PersistentCacheSettings(sizeBytes: FirestoreCacheSizeUnlimited as NSNumber)
        Firestore.firestore().settings = firestoreSettings
        print("✅ Firestore settings configured (persistence enabled, unlimited cache)")
        
        // ✅ Enable Firebase Realtime Database offline persistence
        // IMPORTANT: isPersistenceEnabled must be set on the SAME instance that singletons
        // will use. All singletons call Database.database() (no URL), which returns the
        // default instance. We always configure the default instance here.
        // If a URL is specified in GoogleService-Info.plist, Database.database() will
        // automatically use it — no need to call Database.database(url:) separately.
        let defaultDatabase = Database.database()
        defaultDatabase.isPersistenceEnabled = true
        defaultDatabase.persistenceCacheSizeBytes = 50 * 1024 * 1024  // 50MB cache
        if let databaseURL = FirebaseApp.app()?.options.databaseURL {
            print("✅ Firebase Realtime Database offline persistence enabled (50MB cache)")
            print("✅ Realtime Database URL: \(databaseURL)")
        } else {
            print("✅ Firebase Realtime Database offline persistence enabled (50MB cache, default URL)")
        }
        
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
        
        // Initialize notification categories
        Task { @MainActor in
            // Church notifications (Find Church feature)
            ChurchNotificationManager.shared.setupNotificationCategories()
            print("✅ Church notification categories initialized")
            
            // Visit Plan notifications (First Visit Companion feature)
            ChurchVisitNotificationScheduler.setupVisitPlanNotificationCategories()
            print("✅ Visit Plan notification categories initialized")
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
        // ✅ Forward phone auth notifications to FirebaseAuth (must be first)
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        
        Task { @MainActor in
            PushNotificationManager.shared.updateBadgeCount()
        }
        
        completionHandler(.newData)
    }
}
