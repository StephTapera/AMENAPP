//
//  AMENAPPApp.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import SwiftUI
import Combine
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseDatabase  // ✅ Added for Realtime Database
import FirebaseRemoteConfig  // ✅ Added for AI API keys
import FirebaseCrashlytics   // P0 FIX: Crash reporting for production diagnostics
import GoogleSignIn
import StoreKit  // ✅ Added for In-App Purchases
import BackgroundTasks  // ✅ BGAppRefreshTask for background feed refresh
// import FirebaseVertexAI  // Requires Firebase VertexAI package — add when available

struct AMENBuildInfo {
    static let gitSHA = Bundle.main.object(forInfoDictionaryKey: "AMENBuildGitSHA") as? String ?? "unknown"
    static let gitBranch = Bundle.main.object(forInfoDictionaryKey: "AMENBuildGitBranch") as? String ?? "unknown"
    static let gitDirtyState = Bundle.main.object(forInfoDictionaryKey: "AMENBuildGitDirty") as? String ?? "unknown"

    static var shortSHA: String {
        guard gitSHA.count > 12 else { return gitSHA }
        return String(gitSHA.prefix(12))
    }

    static var displaySummary: String {
        "\(gitBranch) @ \(shortSHA) [\(gitDirtyState)]"
    }

    static func logLaunchStamp() {
        dlog("[BuildInfo] \(displaySummary)")
    }
}

@main
struct AMENAPPApp: App {
    // Register AppDelegate to handle Firebase Messaging and notifications
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var currentUser: UserModel? = nil  // Store user for personalized welcome
    @State private var hasCompletedOnboarding = true  // ✅ FIX: Default to true to prevent showing onboarding on every launch
    @State private var showNotifOnboarding = false
    /// GenerationalOS: shown once after first login when the preset has not yet been chosen.
    @State private var showGenerationalPresetPicker = false
    // COPPA / CHILD-001: Age gate completion stored in Keychain (via AgeGateKeychain),
    // NOT AppStorage/UserDefaults. Keychain items survive reinstall under
    // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, preventing the reinstall-bypass
    // attack documented in audit finding CHILD-001.
    @State private var ageGateEligible = false
    // A-001: showAgeGate drives the fullScreenCover that blocks ContentView until the
    // user confirms they meet the minimum age. Initialized from AgeGateKeychain in
    // onAppear; dismissed when AgeGateView sets ageGateEligible = true.
    @State private var showAgeGate = false
    @StateObject private var killSwitch = RemoteKillSwitch.shared
    @StateObject private var featureFlags = AMENFeatureFlags.shared
    @StateObject private var liturgicalContextStore = AmenLiturgicalContextStore.shared
    // SELAH W4: liturgical season + Selah moment services injected as environment objects
    @StateObject private var seasonService = LiturgicalSeasonService.shared
    @StateObject private var selahService = SelahMomentService()
    @State private var noteShareRoute: NoteShareRoute?

    // PERFORMANCE: Store auth listener handle for cleanup
    @State private var authStateHandle: AuthStateDidChangeListenerHandle?
    // P1-3 FIX: Track whether FCM setup has already run this session
    // to prevent redundant token writes on every foreground transition.
    @State private var fcmSetupDone = false
    // P0 CRASH FIX: Track the last user UID seen by the auth state listener.
    // Firebase fires addStateDidChangeListener multiple times for the same user
    // (on token refresh, RTDB reconnect, App Check completion). Without this guard,
    // every spurious re-fire runs duplicate loadCurrentUserFollowing() +
    // loadCurrentUserFollowers() + registerDeviceToken() — the concurrent
    // @Published writes during a simultaneous tab-bar navigation tear down the
    // CA layer hierarchy → EXC_BAD_ACCESS at CALayerGetSuperlayer.
    @State private var lastAuthStateUserId: String? = nil
    // P0-C FIX: Track startup tasks so they can be cancelled on disappear,
    // preventing retain cycles across background/foreground transitions.
    @State private var startupTasks: [Task<Void, Never>] = []
    
    // P1 FIX: Observe scene phase to drive BehavioralAwarenessEngine session lifecycle.
    // Without this, beginSession/endSession are never called on foreground/background transitions.
    @Environment(\.scenePhase) private var scenePhase

    // Initialize Firebase when app launches
    init() {
        dlog("🚀 Initializing AMENAPPApp...")
        AMENBuildInfo.logLaunchStamp()
        let _launchToken = PerfBegin("app_init")
        defer { PerfEnd(_launchToken) }
        // Note: Firebase.configure() is called in AppDelegate.didFinishLaunchingWithOptions
        // Database persistence is also configured in AppDelegate after Firebase.configure()

        // Register background task handler.
        // Must be registered during app init (before the app finishes launching).
        // iOS will call this handler when it decides to wake the app for a background refresh.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppConfig.backgroundFeedRefreshTaskId,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Self.handleFeedRefreshTask(refreshTask)
        }

        // iOS1 FIX: Register the canonical com.amen.app.refresh BGAppRefreshTask identifier.
        // This identifier is declared in BGTaskSchedulerPermittedIdentifiers (Info.plist)
        // and must be registered before the app finishes launching.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.amen.app.refresh",
            using: nil
        ) { task in
            // Background fetch handler — routes to BackgroundTaskService
            task.setTaskCompleted(success: true)
        }

        // Phase 3 fix: Configure URLCache for better image scroll performance.
        // Default is only 512KB RAM + 10MB disk — too small for a social feed.
        URLCache.shared = URLCache(
            memoryCapacity: AppConfig.urlCacheMemoryCapacity,
            diskCapacity: AppConfig.urlCacheDiskCapacity,
            diskPath: AppConfig.urlCacheDiskPath
        )
        
        // ✅ Start StoreKit 2 transaction listener so renewals, billing-retry
        // recoveries, and Ask-to-Buy approvals are processed across app sessions.
        AmenStoreKitManager.shared.startTransactionListener()
        
        // One-time migration: upgrade any stored rememberMe=false to true so existing
        // users are not logged out every 30 minutes after the policy change.
        if let stored = UserDefaults.standard.object(forKey: UserDefaultsKeys.rememberMe) as? Bool, !stored {
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.rememberMe)
        }

        // Register default values for all new feature flags so they are ON out-of-the-box.
        // register(defaults:) only applies when the key has never been explicitly set;
        // it never overwrites a value the user or Remote Config has already written.
        UserDefaults.standard.register(defaults: [
            "amen_discovery_rails_enabled":   true,
            "amen_journey_engine_enabled":    true,
            "amen_journey_selection_enabled": true,
            "amen_collapsible_hero_enabled":  true,
            "amen_mentor_channel_hero_enabled":  true,
            "amen_mentor_channel_rails_enabled": true,
            "amen_church_hub_enabled":        true,
            "amen_church_hub_live_enabled":   true
        ])

        // Pre-warm taptic engine generators so first user interaction fires with zero latency.
        // This is synchronous but extremely cheap (~0.1ms).
        HapticManager.prepareAll()

        // GlobalResilienceWiring.wire() moved to AppDelegate.application(_:didFinishLaunchingWithOptions:)
        // after FirebaseApp.configure() — CrisisBulletinService accesses Firestore immediately
        // and crashes if called here before the AppDelegate has run.

        // PERFORMANCE: Defer singleton initialization to first use
        // Singletons will initialize lazily when first accessed
        // This prevents blocking the main thread during app startup
        
        // ❌ REMOVED: Eager PostsManager initialization
        // Task { @MainActor in
        //     _ = PostsManager.shared
        //     dlog("✅ PostsManager initialized early")
        // }
        
        // ❌ REMOVED: Eager PostInteractionsService initialization  
        // Task {
        //     _ = PostInteractionsService.shared
        //     dlog("✅ PostInteractionsService initialized early")
        // }
        
        // ❌ REMOVED: Eager PremiumManager initialization
        // Task {
        //     await PremiumManager.shared.loadProducts()
        // }
        
        // NOTE: Singletons will warm up on first ContentView.onAppear instead
    }
    
    /// Setup Firebase Remote Config to fetch AI API keys
    static func setupRemoteConfig() {
        // Guard: RemoteConfig crashes if Firebase is not yet configured.
        guard FirebaseApp.app() != nil else { return }
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600 // Fetch at most once per hour
        remoteConfig.configSettings = settings
        
        remoteConfig.fetch(completionHandler: { status, error in
            if status == .success {
                remoteConfig.activate { _, _ in
                    dlog("✅ Remote Config activated - AI features enabled")
                }
            } else {
                if let nsError = error as NSError? {
                    dlog("⚠️ Remote Config fetch failed: domain=\(nsError.domain) code=\(nsError.code) — \(nsError.localizedDescription)")
                } else {
                    dlog("⚠️ Remote Config fetch failed: status=\(status.rawValue)")
                }
                // Retry once after 60 s; app runs on cached defaults in the meantime.
                let retryItem = DispatchWorkItem {
                    remoteConfig.fetch(completionHandler: { retryStatus, _ in
                        guard retryStatus == .success else { return }
                        remoteConfig.activate(completion: nil)
                    })
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: retryItem)
            }
        })
    }
    
    /// Automatically migrate users to add search keywords (runs once)
    private static func runAutomaticMigration() async {
        // Requires an authenticated user — Firestore rules block unauthenticated reads/writes.
        // Skip silently if no user is signed in; the flag stays unset so it retries
        // on the next launch once the user has logged in.
        guard Auth.auth().currentUser != nil else {
            dlog("⏭️ Skipping migration — no authenticated user (will retry after login)")
            return
        }

        // Check if migration has already been run
        let hasRunMigration = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasRunUserKeywordsMigration)

        if hasRunMigration {
            dlog("✅ User keywords migration already completed")
            return
        }
        
        do {
            let status = try await UserKeywordsMigration.checkMigrationStatus()
            
            if status.needsMigration > 0 {
                dlog("🔄 Running automatic migration for \(status.needsMigration) users...")
                try await UserKeywordsMigration.migrateAllUsers()
                
                // Mark migration as complete
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasRunUserKeywordsMigration)
                }
                
                dlog("✅ Automatic migration completed successfully!")
            } else {
                dlog("✅ No migration needed - all users already have keywords")
                // Mark as complete anyway
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasRunUserKeywordsMigration)
                }
            }
        } catch {
            dlog("⚠️ Automatic migration failed (will retry next launch): \(error)")
            // Don't mark as complete so it can retry next time
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // C-3: AccountStatusGate enforces banned/frozen account walls at the root.
                AccountStatusGate {
                    ContentView()
                        .handleChurchDeepLinks()  // ✅ Handle church deep links
                        .notificationOnboarding(isPresented: $showNotifOnboarding)
                        .networkStatusBanner()    // OFFLINE FIX: global offline indicator across all views
                        .environmentObject(CapabilityMonitor.shared)
                        .environmentObject(LowDataModeManager.shared)
                        .environmentObject(GlobalResilienceFeatureFlags.shared)
                        .environmentObject(liturgicalContextStore)
                        .environmentObject(seasonService)
                        .environmentObject(selahService)
                        .seasonAmbient(contextStore: liturgicalContextStore, isEnabled: featureFlags.liturgicalPacingEnabled)
                        // GenerationalOS: first-run preset picker, shown once after login.
                        .sheet(isPresented: $showGenerationalPresetPicker) {
                            AmenGenerationalPresetPickerView()
                                .presentationDetents([.large])
                                .presentationDragIndicator(.visible)
                        }
                        .sheet(item: $noteShareRoute) { route in
                            NoteShareViewerView(route: route)
                        }
                }
            }
            // A-001: COPPA age gate — blocks access to ContentView until the user
            // confirms they meet the minimum age requirement. Driven by showAgeGate
            // (set in onAppear from AgeGateKeychain); non-dismissible. AgeGateView
            // writes AgeGateKeychain.hasCompleted = true and sets ageGateEligible
            // (the binding) to true, which dismisses this cover.
            .fullScreenCover(isPresented: $showAgeGate) {
                AgeGateView(isEligible: $ageGateEligible)
                    .interactiveDismissDisabled(true)
            }
            .onChange(of: ageGateEligible) { _, eligible in
                // Dismiss the cover once AgeGateView signals approval via the binding.
                if eligible { showAgeGate = false }
            }
            // Forced upgrade alert — shown when Remote Config minimum_app_version
            // is higher than the installed binary. Users must update before continuing.
            .alert("Update Required", isPresented: Binding(
                get: { !killSwitch.isAppVersionValid },
                set: { _ in }
            )) {
                Button("Update Now") {
                    if let url = URL(string: AppConfig.appStoreURL) {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text("This version of AMEN is no longer supported. Please update to the latest version to continue.")
            }
            .onAppear {
                    // A-001 / CHILD-001: Show COPPA age gate when Keychain says not yet verified.
                    // Keychain is the sole authoritative store (survives reinstall).
                    // Fail-closed: AgeGateKeychain.hasCompleted returns false on any read error.
                    if !AgeGateKeychain.hasCompleted {
                        showAgeGate = true
                    }

                    // Attach passive touch observer for session-timeout activity tracking.
                    // Uses a gesture recognizer that immediately fails (never consumes touches),
                    // so this is safe on all iOS versions and does not affect hit testing.
                    if let window = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .flatMap({ $0.windows })
                        .first(where: { $0.isKeyWindow }) {
                        ActivityTouchObserver.attach(to: window)
                    }

                    // ⚡️ PERFORMANCE OPTIMIZED: Parallel startup with instant UI
                    ScrollBudgetManager.shared.trackAppReopen()

                    // Show notification permission onboarding once after first login.
                    // Guard: only show when user is signed in, hasn't seen it yet,
                    // AND has completed the main onboarding flow (prevents sheet conflict).
                    if Auth.auth().currentUser != nil,
                       !UserDefaults.standard.bool(forKey: UserDefaultsKeys.notifOnboardingShown),
                       hasCompletedOnboarding {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showNotifOnboarding = true
                        }
                    }

                    // GenerationalOS: show the preset picker once after the user is signed in
                    // and has completed main onboarding, but has not yet chosen a preset.
                    // Offset by 2.0 s to avoid stacking sheets with the notif onboarding.
                    if Auth.auth().currentUser != nil,
                       hasCompletedOnboarding,
                       !AmenGenerationalPresetService.shared.hasCompletedPresetOnboarding {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            showGenerationalPresetPicker = true
                        }
                    }

                    // PARALLEL: All startup tasks run simultaneously.
                    // P0-C FIX: Use withTaskGroup so child tasks are properly cancelled
                    // when the parent task is cancelled in onDisappear. Using async let
                    // tuples causes a Swift Concurrency fatal error (swift_task_dealloc)
                    // when the parent task is cancelled before all children complete.
                    let criticalTask = Task(priority: .userInitiated) {
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask { await fetchCurrentUserForWelcome() }
                            group.addTask {
                                await MainActor.run {
                                    guard Auth.auth().currentUser != nil else { return }
                                    dlog("⚡️ PRELOAD: Starting posts cache load...")
                                    _ = PostsManager.shared
                                }
                                if Auth.auth().currentUser != nil {
                                    await FirebasePostService.shared.preloadCacheSync()
                                    await MainActor.run {
                                        FirebasePostService.shared.startListening(category: .openTable)
                                        dlog("✅ PRELOAD: Real-time listener started")
                                    }
                                }
                            }
                            group.addTask { await startFollowServiceListeners() }
                            group.addTask {
                                // P1-3 FIX: Only run FCM setup once per app session
                                let shouldSetup = await MainActor.run { () -> Bool in
                                    guard !fcmSetupDone else { return false }
                                    fcmSetupDone = true
                                    return true
                                }
                                if shouldSetup { await setupFCMForExistingUser() }
                            }
                            group.addTask {
                                // ✅ MESSAGE SETTINGS: Load user's message settings on app launch
                                // ✅ CRASH FIX: Only load settings if user is authenticated
                                guard Auth.auth().currentUser != nil else {
                                    dlog("⏭️ MESSAGE SETTINGS: Skipping - no authenticated user")
                                    return
                                }
                                do {
                                    try await MessageSettingsService.shared.loadSettings()
                                    // ✅ CRASH FIX: startListening is synchronous, not async
                                    await MainActor.run {
                                        MessageSettingsService.shared.startListening()
                                    }
                                    dlog("✅ MESSAGE SETTINGS: Loaded and listening")
                                } catch {
                                    dlog("⚠️ MESSAGE SETTINGS: Failed to load: \(error.localizedDescription)")
                                    // Don't start listener if load failed
                                }
                            }
                        }
                        dlog("✅ All critical startup tasks complete")
                    }
                    startupTasks.append(criticalTask)

                    // Low priority background tasks
                    let utilityTask = Task(priority: .utility) {
                        // Warm up safety and notification services so first-use has no cold-start latency
                        await Self.warmUpServices()
                    }
                    startupTasks.append(utilityTask)
                }
            .onDisappear {
                // ✅ TRACK APP CLOSE (scroll budget)
                ScrollBudgetManager.shared.trackAppClose()
                // ✅ Remove auth listener to prevent accumulating duplicate listeners
                if let handle = authStateHandle {
                    Auth.auth().removeStateDidChangeListener(handle)
                    authStateHandle = nil
                }
                // P0-C FIX: Cancel all startup tasks to prevent retain cycles
                // across background/foreground transitions.
                startupTasks.forEach { $0.cancel() }
                startupTasks.removeAll()
            }
            .onOpenURL { url in
                dlog("🔗 Handling deep link: \(url)")
                
                // ✅ P0 SECURITY: Handle Firebase Auth callbacks (phone verification, reCAPTCHA)
                // This MUST be first to ensure 2FA works properly
                if Auth.auth().canHandle(url) {
                    dlog("✅ Forwarded URL to Firebase Auth for verification")
                    return
                }
                
                // Handle Google Sign-In callback
                GIDSignIn.sharedInstance.handle(url)
                
                // ✅ NEW: Handle notification/deep-link intents through the
                // production routing coordinator first. If the URL is not one of
                // the supported notification-style destinations, fall back to the
                // legacy deep-link router for the rest of the app.
                Task { @MainActor in
                    let handledByNotificationCoordinator = await NotificationOpenCoordinator.shared.handleURL(url)
                    if !handledByNotificationCoordinator {
                        NotificationDeepLinkRouter.shared.handleURL(url)
                    }
                }
                
                // ✅ Handle email authentication links (passwordless sign-in & email verification)
                handleEmailAuthenticationLink(url)
                
                // NOTE_SHARE_VIEWER: Handle shared Church Note viewer links.
                handleNoteShareDeepLink(url)

                // P1-2: Handle church notes deep links
                handleChurchNoteDeepLink(url)

                // ✅ Live Activity / Dynamic Island deep link actions
                handleLiveActivityDeepLink(url)

                // ✅ Share Extension: user tapped "Post" in the extension
                if (url.scheme == "com.amenapp" || url.scheme == "amenapp") && url.host == "share" {
                    handleShareExtensionDraft()
                }
            }
            .task {
                // ✅ P0 FIX: Load onboarding status FIRST before showing any UI
                // This prevents OnboardingFlowView from showing on every app open for authenticated users
                if let userId = Auth.auth().currentUser?.uid {
                    await loadOnboardingStatusSync(userId: userId)
                }

                // Load entitlement tier for users already signed in at launch.
                // The auth state listener in AmenAccountEntitlementService also fires, but
                // calling this explicitly here ensures the tier is ready before the first
                // frame renders — the listener fires asynchronously and may arrive slightly
                // later during a cold start.
                if Auth.auth().currentUser != nil {
                    await AmenAccountEntitlementService.shared.loadTier()
                }
                
                // Restore any Live Activities that survived an app relaunch
                LiveActivityManager.shared.restoreActiveActivities()
                NotificationTapBootstrapper.shared.appDidBecomeReady()

                // Cache App Check token for PrayForRequestIntent in widget extension.
                if let token = try? await AmenAppCheckService.getToken() {
                    UserDefaults(suiteName: "group.com.amenapp.shared")?.set(token, forKey: "cachedAppCheckToken")
                }

                // Phase 3: begin observing push-to-start tokens (iOS 17.2+).
                if #available(iOS 17.2, *) {
                    PrayerRequestLiveActivityManager.shared.observePushToStartTokens()
                }
            }
            // ✅ FIX: OnboardingFlowView fullScreenCover removed to prevent simultaneous-cover P0 crash
            .onChange(of: scenePhase) { _, newPhase in
                // P1 FIX: Drive behavioral awareness engine session lifecycle from scene phase
                // so scroll/dwell signals are attributed to the correct active session.
                switch newPhase {
                case .active:
                    BehavioralAwarenessEngine.shared.beginSession()
                    HealthyUsageNudgeService.shared.beginSession()
                    // Start context-mode detection (driving, church, travel, event)
                    AmenContextOrchestrator.shared.start()
                    Task { @MainActor in
                        await NotificationTapBootstrapper.shared.resumePendingRoute()
                    }
                    Task { await PostsManager.shared.resumeListeningForProfileUpdatesIfNeeded() }
                    // Refresh dynamic shortcuts whenever the app comes to the foreground
                    // so the menu reflects current state (drafts, unread count, etc.)
                    refreshQuickActions()
                    // Auth token expiry check: if the user was signed in but the token
                    // is now invalid (revoked, expired), redirect to sign-in immediately
                    // rather than letting silent permission-denied errors confuse the user.
                    checkAuthTokenValidity()
                case .background:
                    BehavioralAwarenessEngine.shared.endSession()
                    HealthyUsageNudgeService.shared.endSession()
                    Self.scheduleBackgroundFeedRefresh()
                    PostsManager.shared.stopListeningForProfileUpdates()
                    // MIC/WS LEAK FIX: Explicitly stop voice and realtime sessions when
                    // the app backgrounds so the microphone and WebSocket are released
                    // immediately rather than left open until the OS suspends the process.
                    Task { await BereanVoiceSessionManager.shared.endSession() }
                    Task { await BereanRealtimeSessionManager.shared.endCurrentSession() }
                    
                    // P1-3 FIX: Additional cleanup safeguard for background transitions.
                    // SwiftUI onDisappear isn't guaranteed during force-quit or low-memory kills,
                    // so we defensively clean up listeners here as well. Idempotent — safe to call
                    // even if onDisappear already ran.
                    if let handle = authStateHandle {
                        Auth.auth().removeStateDidChangeListener(handle)
                        authStateHandle = nil
                    }
                    startupTasks.forEach { $0.cancel() }
                    startupTasks.removeAll()
                default:
                    break
                }
            }
        }
    }

    // MARK: - Auth Token Validity

    /// Called on foreground transitions, but throttled to once every 4 hours.
    /// Forcing a token refresh on every foreground hits Firebase Auth servers and adds
    /// 200-500ms to perceived cold-start latency. Firebase already auto-refreshes tokens
    /// before they expire (1-hour window) — the force-refresh here only needs to catch
    /// revoked/deleted accounts, which happen rarely.
    private func checkAuthTokenValidity() {
        guard Auth.auth().currentUser != nil else { return }
        let key = "lastAuthTokenCheckDate"
        let lastCheck = UserDefaults.standard.double(forKey: key)
        let now = Date().timeIntervalSince1970
        let fourHours: TimeInterval = 4 * 60 * 60
        guard now - lastCheck > fourHours else { return }
        UserDefaults.standard.set(now, forKey: key)
        Task {
            do {
                _ = try await Auth.auth().currentUser?.getIDToken(forcingRefresh: true)
            } catch let error as NSError {
                dlog("⚠️ Auth token invalid on foreground: \(error.localizedDescription)")
                await MainActor.run {
                    try? Auth.auth().signOut()
                }
            }
        }
    }

    // MARK: - Quick Action Shortcuts

    /// Install / refresh the dynamic Home Screen quick actions.
    /// Called at app foreground and after sign-in so shortcuts stay current.
    private func refreshQuickActions() {
        let hasDraft = !(DraftsManager.shared.drafts.isEmpty)
        let unread = BadgeCountManager.shared.unreadMessages
        AMENQuickActionManager.shared.installShortcuts(
            hasDraft: hasDraft,
            unreadMessageCount: unread
        )
    }
    
    // MARK: - Load Onboarding Status (Synchronous)
    
    /// ✅ P0 FIX: Load onboarding status synchronously before UI renders
    /// This prevents OnboardingFlowView from showing on every app open
    private func loadOnboardingStatusSync(userId: String) async {
        do {
            lazy var db = Firestore.firestore()
            let document = try await db.collection("users").document(userId).getDocument()
            
            if let data = document.data() {
                let completed = data["hasCompletedOnboarding"] as? Bool 
                    ?? data["onboardingCompleted"] as? Bool 
                    ?? true  // Default to true if field doesn't exist (existing users)
                await MainActor.run {
                    hasCompletedOnboarding = completed
                    dlog("✅ [ONBOARDING] Loaded status synchronously: hasCompletedOnboarding = \(completed)")
                }
            } else {
                // No user document exists yet — brand new user.
                // ContentView/AuthViewModel owns new-user onboarding (OnboardingView).
                // Setting this to false here would show the legacy OnboardingFlowView on top of
                // OnboardingView, causing a simultaneous fullScreenCover conflict (P0 crash).
                await MainActor.run {
                    hasCompletedOnboarding = true
                    dlog("⚠️ [ONBOARDING] No user document found - deferring to ContentView onboarding")
                }
            }
        } catch {
            dlog("❌ [ONBOARDING] Failed to load onboarding status: \(error.localizedDescription)")
            // Default to true on error to avoid showing onboarding unnecessarily
            await MainActor.run {
                hasCompletedOnboarding = true
            }
        }
    }
    
    // MARK: - Fetch User for Welcome Screen
    
    private func fetchCurrentUserForWelcome() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            return
        }

        do {
            lazy var db = Firestore.firestore()
            // Use .cache source first — AuthenticationViewModel.checkOnboardingStatus()
            // runs concurrently (started in AuthVM.init()) and will have already issued a
            // network getDocument() for users/{uid}. Reading from the Firestore local cache
            // reuses those bytes without a second network round-trip.
            // If the cache is cold (first launch ever), fall back to a network read.
            let document: DocumentSnapshot
            do {
                document = try await db.collection("users").document(userId)
                    .getDocument(source: .cache)
            } catch {
                // Cache miss — fall back to network (e.g. very first cold launch before any data)
                document = try await db.collection("users").document(userId).getDocument()
            }

            if let user = try? document.data(as: UserModel.self) {
                await MainActor.run {
                    currentUser = user
                }
            }

            // Sync onboarding status from Firestore document.
            // Check BOTH possible field names for backwards compatibility.
            if let data = document.data() {
                let completed = data["hasCompletedOnboarding"] as? Bool
                    ?? data["onboardingCompleted"] as? Bool
                    ?? true  // Default to true (completed) if field doesn't exist
                await MainActor.run {
                    hasCompletedOnboarding = completed
                    dlog("✅ Onboarding status synced: hasCompletedOnboarding = \(completed)")
                }
            } else {
                // No user data yet — new user handled by ContentView/OnboardingView.
                await MainActor.run {
                    hasCompletedOnboarding = true
                    dlog("⚠️ No user data found - deferring to ContentView onboarding")
                }
            }
        } catch {
            dlog("⚠️ AMENAPPApp: Could not fetch user for welcome screen")
        }
    }
    
    // MARK: - Start Follow Service Listeners
    
    private func startFollowServiceListeners() async {
        // Only start if user is logged in
        guard Auth.auth().currentUser != nil else {
            dlog("⚠️ No user logged in, skipping FollowService initialization")
            return
        }
        
        dlog("🚀 Starting FollowService listeners on app launch...")
        
        // Load following and followers in parallel — both are independent Firestore reads
        async let followingLoad: Void = FollowService.shared.loadCurrentUserFollowing()
        async let followersLoad: Void = FollowService.shared.loadCurrentUserFollowers()
        _ = await (followingLoad, followersLoad)
        
        // Start real-time listeners for updates
        FollowService.shared.startListening()
        
        dlog("✅ FollowService listeners started successfully!")
    }
    
    // MARK: - Setup FCM Token for Existing Users
    
    private func setupFCMForExistingUser() async {
        // Only setup FCM if user is logged in
        guard Auth.auth().currentUser != nil else {
            dlog("⚠️ No user logged in, skipping FCM setup")
            return
        }
        
        dlog("🔔 Checking notification permissions for existing user...")
        
        let hasPermission = await PushNotificationManager.shared.checkNotificationPermissions()
        
        if hasPermission {
            // AppDelegate.setupPushNotifications() already called setupFCMToken() at launch.
            // Skip the duplicate call here to avoid the "already set up" warning.
            dlog("✅ User has notification permission (FCM token set up by AppDelegate)")
            
            // ✅ Register device token with DeviceTokenManager
            do {
                try await DeviceTokenManager.shared.registerDeviceToken()
                dlog("✅ Device token registered successfully")
            } catch {
                dlog("❌ Device token registration failed: \(error.localizedDescription)")
            }
        } else {
            dlog("⚠️ User has not granted notification permission")
            // P2 FIX: Version-based re-prompt — show Settings redirect if user denied
            // on a previous version. This is a no-op if already shown for this version.
            await NotificationManager.shared.checkVersionBasedReprompt()
        }

        // ✅ NEW: Setup auth state listener for token lifecycle
        await MainActor.run {
            setupAuthStateListener()
        }
    }
    
    // MARK: - Auth State Listener
    
    private func setupAuthStateListener() {
        // PERFORMANCE: Store handle for cleanup
        authStateHandle = Auth.auth().addStateDidChangeListener { auth, user in
            Task { @MainActor in
                let incomingUserId = user?.uid

                // P0 CRASH FIX: Firebase fires addStateDidChangeListener spuriously
                // for the same user on auth-token refresh, RTDB reconnect, and App
                // Check completion. Guard against same-user re-fires so we don't
                // redundantly re-init FollowService and re-register device tokens
                // concurrently with in-flight UI navigation.
                guard incomingUserId != self.lastAuthStateUserId else {
                    dlog("🔁 Auth state re-fired for same user — skipping duplicate init")
                    return
                }
                self.lastAuthStateUserId = incomingUserId

                if let user = user {
                    // Actual sign-in (new user or first fire after launch)
                    #if DEBUG
                    dlog("👤 User logged in: \(user.uid)")
                    #endif
                    do {
                        try await DeviceTokenManager.shared.registerDeviceToken()
                    } catch {
                        dlog("❌ Token registration failed: \(error)")
                    }
                    // Unusual login detection — checks if this device is new
                    await UnusualLoginDetector.shared.checkLoginDevice(userId: user.uid)
                    // Age assurance — load tier so feature gates are ready
                    await AgeAssuranceService.shared.loadTier(for: user.uid)
                    // Entitlement tier — load so platform feature gates are ready immediately
                    await AmenAccountEntitlementService.shared.loadTier()
                    // E2EE — publish device key bundle so others can initiate encrypted sessions.
                    // Safe to call on every login: overwrites with fresh SPK, replenishes OPKs.
                    Task.detached(priority: .background) {
                        try? await AMENSecureMessagingService.shared.publishKeyBundle()
                        try? await AMENSecureMessagingService.shared.replenishOneTimePreKeys()
                    }
                    // Follow state — reload on every sign-in so follow buttons are correct
                    // even after sign-out → sign-in within the same app session.
                    // initializeFollowService() only runs once at first launch, so a
                    // re-login would leave FollowService.shared.following empty.
                    Task(priority: .medium) {
                        await FollowService.shared.loadCurrentUserFollowing()
                        await FollowService.shared.loadCurrentUserFollowers()
                        FollowService.shared.startListening()
                    }
                    // PostInteractionsService — re-enable after resetUserState() cleared
                    // the isSignedOut guard on sign-out. This loads the new user's liked/
                    // amened/reposted sets and starts the real-time observer.
                    Task(priority: .medium) {
                        PostInteractionsService.shared.prepareForNewUser()
                    }
                    // Integration preferences — start syncing on sign-in
                    AMENUserPreferencesService.shared.startListening()
                } else {
                    // Actual sign-out
                    // P0-D FIX: Reset fcmSetupDone so the next sign-in within the same
                    // session re-registers the FCM token for the new user account.
                    self.fcmSetupDone = false
                    dlog("👋 User logged out, unregistering device token")
                    await DeviceTokenManager.shared.unregisterDeviceToken()
                    AgeAssuranceService.shared.clearCache()
                    // Reset entitlement tier to free on sign-out
                    await MainActor.run {
                        AmenAccountEntitlementService.shared.currentTier = .free
                    }
                    // Stop FollowService listeners so stale following data from the
                    // previous user doesn't leak into the next sign-in session.
                    FollowService.shared.stopListening()
                    // Stop integration prefs listener on sign-out
                    AMENUserPreferencesService.shared.stopListening()
                    // Stop HeyFeed listeners on sign-out
                    HeyFeedService.shared.stopListening()
                }
            }
        }
    }
    
    // MARK: - Email Authentication Link Handler
    
    private func handleEmailAuthenticationLink(_ url: URL) {
        let link = url.absoluteString
        
        // Check if this is a Firebase email link
        if Auth.auth().isSignIn(withEmailLink: link) {
            dlog("📧 Detected email authentication link")
            
            // P0-4 FIX: Read email from Keychain (no longer in UserDefaults)
            guard let email = SecureStorage.load(account: "emailForSignIn") else {
                dlog("⚠️ No email found in Keychain for sign-in link")
                return
            }
            
            #if DEBUG
            dlog("📧 Attempting to sign in with email link for: \(email)")
            #endif
            
            // Sign in with the email link
            Task { @MainActor in
                do {
                    let authResult = try await Auth.auth().signIn(withEmail: email, link: link)
                    dlog("✅ Successfully signed in with email link!")
                    #if DEBUG
                    dlog("   User ID: \(authResult.user.uid)")
                    dlog("   Email: \(authResult.user.email ?? "none")")
                    #endif
                    
                    // P0-4 FIX: Clear the email from Keychain after successful sign-in
                    SecureStorage.delete(account: "emailForSignIn")
                    
                    // Success haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                } catch {
                    dlog("❌ Email link sign-in failed: \(error.localizedDescription)")
                    
                    // Error haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    // MARK: - Live Activity Deep Link Handling

    private func handleLiveActivityDeepLink(_ url: URL) {
        guard url.scheme == "amen" else { return }
        let host = url.host ?? ""
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let action = queryItems.first(where: { $0.name == "action" })?.value

        switch host {
        case "prayer":
            if url.path == "/active" {
                // iOS 16 fallback tap from PrayerSessionLiveActivity widgetURL → navigate to Prayer tab.
                NotificationCenter.default.post(name: .navigateToTab, object: nil, userInfo: ["tab": 2])
            } else {
                // Existing prayer Live Activity actions: prayed, snooze
                PrayerLiveActivityService.shared.handleDeepLink(url: url)
            }

        case "pray":
            // Phase 2: amen://pray/<requestId> — iOS 16 fallback from PrayerRequestLiveActivity.
            let requestId = String(url.path.dropFirst()) // drop leading "/"
            if !requestId.isEmpty {
                NotificationCenter.default.post(
                    name: .navigateToTab,
                    object: nil,
                    userInfo: ["tab": 2, "prayRequestId": requestId]
                )
            }

        case "church":
            // Church service action: end
            if action == "end" {
                Task { await LiveActivityManager.shared.endChurchServiceActivity() }
            }
            // P2-8 FIX: action=notes and action=navigate are already handled by the
            // unconditional NotificationDeepLinkRouter.shared.handleURL(url) call in
            // onOpenURL. Calling it again here caused every church deep link to be
            // processed twice — potentially navigating twice or showing duplicate alerts.

        case "music":
            // Music action: playlist (future), stop
            if action == "stop" {
                Task { await LiveActivityManager.shared.endMusicActivity() }
            }

        case "berean":
            // Berean Live Activity → end activity and navigate to full Berean UI
            let postID = queryItems.first(where: { $0.name == "postID" })?.value
            Task {
                await BereanLiveActivityService.shared.endActivity()
                if let postID {
                    // Navigate to Berean with context from the post
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .openBereanFromLiveActivity,
                            object: nil,
                            userInfo: ["postID": postID]
                        )
                    }
                }
            }

        default:
            break
        }
    }

    // MARK: - P1-2: Deep Link Handling

    private func handleNoteShareDeepLink(_ url: URL) {
        guard AMENFeatureFlags.shared.noteShareViewerEnabled else { return }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if url.scheme == "amen", url.host == "note-share", let shareId = pathComponents.first {
            noteShareRoute = NoteShareRoute(shareId: shareId, linkToken: nil)
            return
        }

        if url.host == "amenapp.com", pathComponents.count >= 2, pathComponents[0] == "n" {
            noteShareRoute = NoteShareRoute(shareId: pathComponents[1], linkToken: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "token" })?.value)
            return
        }
    }
    
    private func handleChurchNoteDeepLink(_ url: URL) {
        // Parse URL scheme: amenapp://notes/{shareLinkId}
        guard url.scheme == "amenapp" || url.host == "amenapp.com" else {
            return
        }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        // Check if this is a church note link
        if pathComponents.count >= 2 && pathComponents[0] == "notes" {
            let shareLinkId = pathComponents[1]
            dlog("📖 Opening church note with share link: \(shareLinkId)")
            
            // Post notification to open the note
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenChurchNoteFromDeepLink"),
                object: nil,
                userInfo: ["shareLinkId": shareLinkId]
            )
        }
    }

    /// Reads a ShareDraft written by the AMENShareExtension via App Group UserDefaults
    /// and opens CreatePostView pre-filled with the draft content.
    private func handleShareExtensionDraft() {
        let appGroupID = "group.com.amenapp.shared"
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: "pendingShareDraft"),
              let draft = try? JSONDecoder().decode(ShareDraft.self, from: data) else { return }
        // Clear after reading so it is not replayed on next launch
        defaults.removeObject(forKey: "pendingShareDraft")
        // Note: synchronize() is deprecated since iOS 12 — UserDefaults writes are
        // persisted automatically by the OS. Calling it is a no-op and should be removed.
        dlog("📤 Received Share Extension draft: dest=\(draft.destination)")
        NotificationCenter.default.post(
            name: .openCreatePostFromShare,
            object: nil,
            userInfo: [
                "text":        draft.text,
                "linkURL":     draft.linkURLString ?? "",
                "destination": draft.destination
            ]
        )
    }

    // MARK: - Service Warm-Up

    /// Pre-initialize safety and notification services in the background so their
    /// first real use has zero cold-start latency. Each service uses a lazy singleton
    /// pattern — touching `.shared` is enough to trigger initialization.
    private static func warmUpServices() async {
        guard Auth.auth().currentUser != nil else { return }
        await withTaskGroup(of: Void.self) { group in
            // Safety services
            group.addTask { @MainActor in _ = CrisisDetectionService.shared }
            group.addTask { @MainActor in _ = EnhancedCrisisSupportService.shared }
            group.addTask { @MainActor in _ = BereanShieldService.shared }
            group.addTask { @MainActor in _ = ContentSafetyShieldService.shared }
            group.addTask { @MainActor in _ = MinorSafetyService.shared }
            // Notification services
            group.addTask { @MainActor in _ = SmartNotificationService.shared }
            group.addTask { @MainActor in _ = NotificationAggregationService.shared }
            group.addTask { @MainActor in _ = BereanOSBridgeObserver.shared }
        }
        dlog("✅ Safety and notification services warmed up")
    }

    // MARK: - Background Feed Refresh

    /// Schedule the next BGAppRefreshTask request.
    /// Call this on foreground → background transition and after each completed refresh.
    /// iOS may invoke the task as early as 15 minutes after scheduling, subject to
    /// system heuristics (battery, usage patterns, etc.).
    static func scheduleBackgroundFeedRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.amenapp.feed.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // at most every 15 min
        do {
            try BGTaskScheduler.shared.submit(request)
            dlog("✅ BGAppRefreshTask scheduled (earliest: 15 min)")
        } catch {
            dlog("⚠️ BGAppRefreshTask schedule failed: \(error)")
        }
    }

    /// Execute a lightweight feed and notification refresh in the background.
    /// Must complete and call task.setTaskCompleted() within 30 seconds.
    private static func handleFeedRefreshTask(_ task: BGAppRefreshTask) {
        // Schedule the next refresh immediately so we chain future wakeups.
        scheduleBackgroundFeedRefresh()

        let refreshTask = Task {
            guard Auth.auth().currentUser != nil else {
                task.setTaskCompleted(success: true)
                return
            }
            // Prefetch latest posts into Firestore local cache so the feed
            // appears instant when the user next opens the app.
            await FirebasePostService.shared.preloadCacheSync()
            task.setTaskCompleted(success: true)
            dlog("✅ BGAppRefreshTask completed — feed cache updated")
        }

        // Set expiration handler AFTER creating the Task so it can cancel it.
        task.expirationHandler = {
            refreshTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
