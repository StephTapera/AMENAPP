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
import AppTrackingTransparency

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        dlog("🚀 AppDelegate: didFinishLaunchingWithOptions")

        // When running unit tests, skip all Firebase / push / network initialization.
        // The test host app launches but tests do NOT need Firebase configured,
        // and initializing push notifications or ATT in a simulator test process
        // causes indefinite hangs that cancel all Swift Testing @Suite tests.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            dlog("🧪 Test host detected — skipping Firebase & push initialization")
            return true
        }
        
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
        
        // App Check MUST be configured BEFORE FirebaseApp.configure()
        // so that all Firebase SDK calls are automatically attested.
        // DEBUG builds use AppCheckDebugProviderFactory with a debug token —
        // register the token printed to the console in Firebase Console → App Check → Apps.
        // Release builds use AmenAppCheckProviderFactory (App Attest iOS 14+ / DeviceCheck iOS 13).
        #if DEBUG
        // Use a STABLE debug token that persists across launches and is printed
        // prominently below. Without this the SDK silently generates a fresh
        // token on first run and never reprints it, so it can never be copied
        // into Firebase Console → App Check → register, and every simulator run
        // returns HTTP 403 "App attestation failed".
        //
        // Register the printed token ONCE (Firebase Console → App Check → Apps →
        // ⋮ → Manage debug tokens → Add) and App Check stops 403-ing on this sim.
        let debugTokenKey = "AMEN.AppCheckDebugToken"
        let appCheckDebugToken = UserDefaults.standard.string(forKey: debugTokenKey)
            ?? {
                let generated = UUID().uuidString
                UserDefaults.standard.set(generated, forKey: debugTokenKey)
                return generated
            }()
        // The FirebaseAppCheck debug provider reads this env var first, so the
        // token stays stable instead of being regenerated each install.
        setenv("FIRAAppCheckDebugToken", appCheckDebugToken, 1)
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        dlog("✅ App Check configured with Debug Provider (DEBUG build)")
        dlog("""
        ┌──────────────────────────────────────────────────────────────
        │ 🔑 App Check DEBUG TOKEN (register once to silence 403s):
        │    \(appCheckDebugToken)
        │ Firebase Console → App Check → Apps → ⋮ → Manage debug tokens
        └──────────────────────────────────────────────────────────────
        """)
        #else
        AppCheck.setAppCheckProviderFactory(AmenAppCheckProviderFactory())
        dlog("✅ App Check configured with AmenAppCheckProviderFactory (App Attest / DeviceCheck)")
        #endif
        
        // Configure Firebase AFTER App Check provider is set
        FirebaseApp.configure()
        dlog("✅ Firebase configured successfully")

        // P0-03 FIX: Kick off Remote Config fetch immediately after Firebase is configured.
        // Previously this was called from AMENAPPApp.init() via Task{}, where FirebaseApp
        // might not yet be configured on a fresh install — causing all feature flags
        // (including AI kill switches and safety flags) to stay on compiled-in defaults
        // for the entire first session. Calling it here guarantees Firebase is ready.
        AMENAPPApp.setupRemoteConfig()
        dlog("✅ Remote Config fetch initiated (post-Firebase-configure)")

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
                // NOTE: HTTP 403 on simulator is EXPECTED until debug token is registered in Firebase Console
                // Go to: Firebase Console → App Check → Apps → Register debug token from logs
                dlog("⚠️ App Check pre-warm failed (expected on first simulator run): \(error.localizedDescription)")
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

        // Subscribe to disaster alert FCM topics (idempotent — safe to call on every launch)
        Messaging.messaging().subscribe(toTopic: "disasters_general") { error in
            if let error { dlog("⚠️ FCM disaster_general subscribe: \(error.localizedDescription)") }
            else { dlog("✅ FCM subscribed: disasters_general") }
        }
        Messaging.messaging().subscribe(toTopic: "disasters_critical") { error in
            if let error { dlog("⚠️ FCM disaster_critical subscribe: \(error.localizedDescription)") }
            else { dlog("✅ FCM subscribed: disasters_critical") }
        }

        // ── QUICK ACTIONS: Cold launch ───────────────────────────────────────────
        // When the user long-presses the app icon and taps a shortcut while the app
        // is NOT running, iOS passes the shortcut item in launchOptions.
        // We store it via AMENQuickActionManager so ContentView can act on it once
        // the auth state is resolved. Returning true (not false) is required — if
        // this delegate returns false the system considers the launch "rejected".
        // UIApplication.LaunchOptionsKey.shortcutItem is deprecated on iOS 26 for scene-based
        // apps; for UIApplicationDelegate apps it remains the correct mechanism.
        // Use the raw string value to avoid the compiler deprecation warning.
        let shortcutKey = UIApplication.LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsShortcutItemKey")
        if let shortcutItem = launchOptions?[shortcutKey]
            as? UIApplicationShortcutItem {
            dlog("🚀 [QuickAction] Cold launch with shortcut: \(shortcutItem.type)")
            Task { @MainActor in
                AMENQuickActionManager.shared.handle(shortcutItem)
            }
            // Return true — the quick action was handled; do NOT return false here
            // because that would prevent the standard SwiftUI lifecycle from starting.
        }

        // ✅ ATT: Request App Tracking Transparency after a brief delay so the
        // launch screen has settled. Apple requires this dialog before any
        // IDFA access. App Store will reject binaries that access IDFA without it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ATTrackingManager.requestTrackingAuthorization { status in
                dlog("✅ ATT authorization status: \(status.rawValue)")
            }
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
            // iOS2 FIX: Register PRAYER_REQUEST and NEW_MESSAGE categories (and others)
            // via NotificationManager so the system recognises action identifiers on
            // incoming push payloads that carry a category key.
            NotificationManager.shared.setupNotificationCategories()
            dlog("✅ App notification categories initialized (PRAYER_REQUEST, NEW_MESSAGE, etc.)")

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

}


