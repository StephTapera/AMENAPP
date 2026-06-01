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
#if canImport(GoogleMaps)
import GoogleMaps
#endif

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
        
        // ✅ App Check MUST be configured BEFORE FirebaseApp.configure()
        // Simulator uses the debug provider; real devices use App Attest.
        #if targetEnvironment(simulator)
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        dlog("✅ App Check configured with Debug Provider (simulator)")
        #if DEBUG
        print("═══════════════════════════════════════════════════════")
        print("APP CHECK SETUP: Register your debug token at:")
        print("Firebase Console → App Check → Apps → AMENAPP → Debug tokens")
        print("The token is logged by the Firebase SDK as:")
        print("[Firebase/AppCheck][I-FAA001016] Firebase App Check debug token: <UUID>")
        print("Until registered, App Check exchanges return 403 and Remote Config fetches fail.")
        print("═══════════════════════════════════════════════════════")
        #endif
        #else
        let providerFactory = AppCheckAppAttestProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        dlog("✅ App Check configured with App Attest Provider (real device)")
        #endif
        
        // Configure Firebase AFTER App Check provider is set
        FirebaseApp.configure()
        dlog("✅ Firebase configured successfully")

        // Initialize Google Maps SDK.
        // Key is stored in Info.plist under AMEN_GOOGLE_MAPS_API_KEY (restricted to bundle ID).
        // Never hardcode the key here — always read from Info.plist.
        // Only compiled when GoogleMaps product is linked to the target.
        #if canImport(GoogleMaps)
        if let googleMapsKey = Bundle.main.object(forInfoDictionaryKey: "AMEN_GOOGLE_MAPS_API_KEY") as? String,
           !googleMapsKey.isEmpty {
            GMSServices.provideAPIKey(googleMapsKey)
            dlog("✅ Google Maps SDK initialized")
        } else {
            dlog("⚠️ Google Maps API key not found in Info.plist — in-app map tiles will be unavailable")
        }
        #endif

        // PERF FIX: Warm Tier-0/1 services immediately after Firebase init so they
        // are ready before the first user interaction, avoiding lazy-init jank.
        // ServiceBootstrapper is @MainActor; hop to MainActor via Task so AppDelegate
        // (non-actor) can call it without blocking the launch thread.
        Task { @MainActor in ServiceBootstrapper.shared.bootstrap() }

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

        // Subscribe to disaster alert FCM topics (idempotent — safe to call on every launch).
        // Skip on simulator: no APNS token is available so FCM subscriptions always fail.
        #if !targetEnvironment(simulator)
        Messaging.messaging().subscribe(toTopic: "disasters_general") { error in
            if let error { dlog("⚠️ FCM disaster_general subscribe: \(error.localizedDescription)") }
            else { dlog("✅ FCM subscribed: disasters_general") }
        }
        Messaging.messaging().subscribe(toTopic: "disasters_critical") { error in
            if let error { dlog("⚠️ FCM disaster_critical subscribe: \(error.localizedDescription)") }
            else { dlog("✅ FCM subscribed: disasters_critical") }
        }
        #endif

        // ── QUICK ACTIONS: Cold launch ───────────────────────────────────────────
        // When the user long-presses the app icon and taps a shortcut while the app
        // is NOT running, iOS passes the shortcut item in launchOptions.
        // AMENQuickActionManager.handle(_:) translates the shortcut type into an
        // AppDestination and calls AppNavigationRouter.shared.navigate(to:). The
        // router queues the destination until sceneDidBecomeReady() and authDidBecomeReady()
        // are called from ContentView.mainContent — no race, no drop.
        // Returning true (not false) is required — if this delegate returns false the
        // system considers the launch "rejected".
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

        // ✅ ATT: Moved to AMENAPPApp onAppear task group so the dialog fires
        // after the first meaningful frame renders, not during the launch sequence.

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

        // CompositeNotificationDelegate is the sole UNUserNotificationCenterDelegate —
        // it handles message suppression, blocked-user filtering, and church notification
        // routing. Do NOT assign a second delegate here; it would overwrite this one.
        center.delegate = CompositeNotificationDelegate.shared

        // H-13 FIX: Also assign PushNotificationHandler as the FCM MessagingDelegate so its
        // messaging(_:didReceiveRegistrationToken:) conformance fires and saves tokens to
        // the per-device subcollection (deviceTokens/{token}).
        // PushNotificationManager's MessagingDelegate conformance stays active via
        // PushNotificationManager.shared below if needed; PushNotificationHandler takes
        // ownership of token saving here as it has the better multi-device design.
        Messaging.messaging().delegate = PushNotificationHandler.shared

        // Set FCM delegate - PushNotificationManager conforms to MessagingDelegate
        // (kept for call-sites that depend on PushNotificationManager directly)
        // Messaging.messaging().delegate = PushNotificationManager.shared as MessagingDelegate

        // Setup FCM token
        PushNotificationManager.shared.setupFCMToken()

        dlog("✅ Push notification delegates configured (PushNotificationHandler wired)")
        
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

}


