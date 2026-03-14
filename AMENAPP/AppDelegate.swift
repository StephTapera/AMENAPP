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
import FirebaseCrashlytics
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        dlog("🚀 AppDelegate: didFinishLaunchingWithOptions")
        
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
        // be suppressed any other way. App dlog() calls go to stdout, so they are unaffected.
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
        dlog("✅ App Check configured with Debug Provider (simulator)")
        #else
        let providerFactory = AppCheckAppAttestProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        dlog("✅ App Check configured with App Attest Provider (real device)")
        #endif
        
        // Configure Firebase AFTER App Check provider is set
        FirebaseApp.configure()
        dlog("✅ Firebase configured successfully")

        // ✅ Initialize Crashlytics for production crash monitoring
        // Must be called after FirebaseApp.configure()
        // Crashlytics automatically collects crashes; this enables it and sets
        // collection to true explicitly so we have a clear record in code.
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        dlog("✅ Crashlytics initialized (crash reporting active)")
        
        // Pre-warm App Check token at launch so it's ready by the time user taps sign up.
        // This moves the attestation delay (can be several seconds) out of the auth flow.
        Task {
            do {
                let token = try await AppCheck.appCheck().token(forcingRefresh: false)
                dlog("✅ App Check token pre-warmed: \(token.token.prefix(20))...")
            } catch {
                // Non-fatal — SDK will fall back to placeholder token when unenforced
                dlog("⚠️ App Check pre-warm failed (monitoring mode will handle): \(error.localizedDescription)")
            }
        }
        
        // Configure Firestore settings IMMEDIATELY after Firebase.configure()
        // This must happen before any Firestore access
        let firestoreSettings = FirestoreSettings()
        // Cap Firestore disk cache at 150 MB. Unlimited cache grows unboundedly and
        // creates privacy risk (cached data survives sign-out). 150 MB is generous
        // for normal usage while protecting storage and privacy.
        let cacheSizeBytes: Int64 = 150 * 1024 * 1024  // 150 MB
        firestoreSettings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: cacheSizeBytes))
        Firestore.firestore().settings = firestoreSettings
        dlog("✅ Firestore settings configured (persistence enabled, 150 MB cache cap)")
        
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
            dlog("✅ Firebase Realtime Database offline persistence enabled (50MB cache)")
            dlog("✅ Realtime Database URL: \(databaseURL)")
        } else {
            dlog("✅ Firebase Realtime Database offline persistence enabled (50MB cache, default URL)")
        }
        
        // Setup push notifications
        setupPushNotifications()

        // ── QUICK ACTIONS: Cold launch ───────────────────────────────────────────
        // When the user long-presses the app icon and taps a shortcut while the app
        // is NOT running, iOS passes the shortcut item in launchOptions.
        // We store it via AMENQuickActionManager so ContentView can act on it once
        // the auth state is resolved. Returning true (not false) is required — if
        // this delegate returns false the system considers the launch "rejected".
        // UIApplicationLaunchOptionsKey.shortcutItem is deprecated on iOS 26+.
        // This app uses UIApplicationDelegate (not UIScene), so this remains correct.
        if let shortcutItem = launchOptions?[UIApplication.LaunchOptionsKey.shortcutItem]
            as? UIApplicationShortcutItem {
            dlog("🚀 [QuickAction] Cold launch with shortcut: \(shortcutItem.type)")
            Task { @MainActor in
                AMENQuickActionManager.shared.handle(shortcutItem)
            }
            // Return true — the quick action was handled; do NOT return false here
            // because that would prevent the standard SwiftUI lifecycle from starting.
        }

        return true
    }

    // MARK: - Quick Actions: Warm / Foreground launch

    /// Called when the user selects a quick action while the app IS already running
    /// (either in the foreground or suspended in background).
    /// This method MUST call completionHandler(true) — the system kills the app
    /// if completionHandler is not called within the expected time window.
    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        dlog("⚡️ [QuickAction] Foreground shortcut: \(shortcutItem.type)")
        Task { @MainActor in
            AMENQuickActionManager.shared.handle(shortcutItem)
            completionHandler(true)
        }
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
        
        dlog("✅ Push notification delegates configured")
        
        // Initialize notification categories
        Task { @MainActor in
            // Church notifications (Find Church feature)
            ChurchNotificationManager.shared.setupNotificationCategories()
            dlog("✅ Church notification categories initialized")
            
            // Visit Plan notifications (First Visit Companion feature)
            ChurchVisitNotificationScheduler.setupVisitPlanNotificationCategories()
            dlog("✅ Visit Plan notification categories initialized")
        }
        
        // ✅ PHASE 1: Register for remote notifications
        UIApplication.shared.registerForRemoteNotifications()
        dlog("✅ Registered for remote notifications")
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

    // P1 FIX: Return a scene configuration that uses ActivityTrackingSceneDelegate,
    // which overrides the UIWindow class to ActivityTrackingWindow. This ensures all
    // touches call SessionTimeoutManager.recordActivity() so active users are never
    // incorrectly timed out while typing or scrolling.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: connectingSceneSession.configuration.name,
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = ActivityTrackingSceneDelegate.self
        return config
    }
}
// MARK: - Activity Tracking Scene Delegate
//
// Replaces the default UIWindow with ActivityTrackingWindow so touches always
// reset the inactivity timer regardless of which view receives them.

final class ActivityTrackingSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let trackingWindow = ActivityTrackingWindow(windowScene: windowScene)
        trackingWindow.makeKeyAndVisible()
        self.window = trackingWindow
    }
}

