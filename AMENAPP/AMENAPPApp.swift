//
//  AMENAPPApp.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseDatabase  // ✅ Added for Realtime Database
import FirebaseRemoteConfig  // ✅ Added for AI API keys
import GoogleSignIn
import StoreKit  // ✅ Added for In-App Purchases
import BackgroundTasks  // ✅ BGAppRefreshTask for background feed refresh
// import FirebaseVertexAI  // TODO: Add Firebase VertexAI package later to enable AI features

@main
struct AMENAPPApp: App {
    // Register AppDelegate to handle Firebase Messaging and notifications
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var currentUser: UserModel? = nil  // Store user for personalized welcome
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showNotifOnboarding = false

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
        let _launchToken = PerfBegin("app_init")
        defer { PerfEnd(_launchToken) }
        // Note: Firebase.configure() is called in AppDelegate.didFinishLaunchingWithOptions
        // Database persistence is also configured in AppDelegate after Firebase.configure()

        // Register background task handler.
        // Must be registered during app init (before the app finishes launching).
        // iOS will call this handler when it decides to wake the app for a background refresh.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.amenapp.feed.refresh",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Self.handleFeedRefreshTask(refreshTask)
        }

        // Phase 3 fix: Configure URLCache for better image scroll performance.
        // Default is only 512KB RAM + 10MB disk — too small for a social feed.
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,   // 64 MB RAM
            diskCapacity:  256 * 1024 * 1024,   // 256 MB disk
            diskPath: "amen_url_cache"
        )
        
        // ✅ Initialize Firebase Remote Config for AI API keys
        Task {
            Self.setupRemoteConfig()
        }
        
        // One-time migration: upgrade any stored rememberMe=false to true so existing
        // users are not logged out every 30 minutes after the policy change.
        if let stored = UserDefaults.standard.object(forKey: "rememberMe") as? Bool, !stored {
            UserDefaults.standard.set(true, forKey: "rememberMe")
        }

        // Pre-warm taptic engine generators so first user interaction fires with zero latency.
        // This is synchronous but extremely cheap (~0.1ms).
        HapticManager.prepareAll()

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
    private static func setupRemoteConfig() {
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600 // Fetch at most once per hour
        remoteConfig.configSettings = settings
        
        remoteConfig.fetch { status, error in
            if status == .success {
                remoteConfig.activate { _, _ in
                    dlog("✅ Remote Config activated - AI features enabled")
                }
            } else {
                dlog("⚠️ Remote Config fetch failed: \(error?.localizedDescription ?? "unknown")")
            }
        }
    }
    
    /// Automatically migrate users to add search keywords (runs once)
    private static func runAutomaticMigration() async {
        // Check if migration has already been run
        let hasRunMigration = UserDefaults.standard.bool(forKey: "hasRunUserKeywordsMigration")
        
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
                    UserDefaults.standard.set(true, forKey: "hasRunUserKeywordsMigration")
                }
                
                dlog("✅ Automatic migration completed successfully!")
            } else {
                dlog("✅ No migration needed - all users already have keywords")
                // Mark as complete anyway
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: "hasRunUserKeywordsMigration")
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
                ContentView()
                    .handleChurchDeepLinks()  // ✅ Handle church deep links
                    .notificationOnboarding(isPresented: $showNotifOnboarding)

                // ✅ P0-1: Under-13 hard block — full-screen gate when ageTier is "blocked".
                // Overlays all app content and prevents any interaction. The only available
                // action is signing out. The gate disappears automatically when the user
                // signs out (ageTier resets to tierB, isLoaded = false).
                if AgeAssuranceService.shared.isLoaded && AgeAssuranceService.shared.tier == .blocked {
                    AccountLockedView()
                        .transition(.opacity)
                        .zIndex(99)
                }
            }
            .onAppear {
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
                    // Guard: only show when user is signed in and hasn't seen it yet.
                    if Auth.auth().currentUser != nil,
                       !UserDefaults.standard.bool(forKey: "notifOnboardingShown") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showNotifOnboarding = true
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
                        }
                        dlog("✅ All critical startup tasks complete")
                    }
                    startupTasks.append(criticalTask)

                    // Low priority background tasks
                    let utilityTask = Task(priority: .utility) {
                        await cacheCurrentUserProfile()
                        await Self.runAutomaticMigration()
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
                
                // ✅ NEW: Handle notification deep links
                NotificationDeepLinkRouter.shared.handleURL(url)
                
                // ✅ Handle email authentication links (passwordless sign-in & email verification)
                handleEmailAuthenticationLink(url)
                
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
                // Restore any Live Activities that survived an app relaunch
                LiveActivityManager.shared.restoreActiveActivities()
            }
            // Show supplementary interest/follow onboarding once after account creation.
            // This is separate from the username/profile OnboardingView in ContentView.
            // Gated by a simple @AppStorage bool so it only shows once per device install.
            .fullScreenCover(isPresented: Binding(
                get: { Auth.auth().currentUser != nil && !hasCompletedOnboarding },
                set: { _ in }
            )) {
                OnboardingFlowView()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // P1 FIX: Drive behavioral awareness engine session lifecycle from scene phase
                // so scroll/dwell signals are attributed to the correct active session.
                switch newPhase {
                case .active:
                    BehavioralAwarenessEngine.shared.beginSession()
                    // Refresh dynamic shortcuts whenever the app comes to the foreground
                    // so the menu reflects current state (drafts, unread count, etc.)
                    refreshQuickActions()
                    // Auth token expiry check: if the user was signed in but the token
                    // is now invalid (revoked, expired), redirect to sign-in immediately
                    // rather than letting silent permission-denied errors confuse the user.
                    checkAuthTokenValidity()
                case .background:
                    BehavioralAwarenessEngine.shared.endSession()
                    Self.scheduleBackgroundFeedRefresh()
                    Task { await PostsManager.shared.stopListeningForProfileUpdates() }
                default:
                    break
                }
            }
        }
    }

    // MARK: - Auth Token Validity

    /// Called on every foreground transition. Forces a token refresh and signs out
    /// if the token can no longer be refreshed (revoked session, banned account, etc.).
    private func checkAuthTokenValidity() {
        guard Auth.auth().currentUser != nil else { return }
        Task {
            do {
                // forceRefresh: true — contacts Firebase Auth servers to verify the token.
                // Will throw if the refresh token has been revoked or the account deleted.
                _ = try await Auth.auth().currentUser?.getIDToken(forcingRefresh: true)
            } catch let error as NSError {
                // FIRAuthErrorCodeUserNotFound, FIRAuthErrorCodeUserDisabled,
                // FIRAuthErrorCodeTokenExpired all land here.
                dlog("⚠️ Auth token invalid on foreground: \(error.localizedDescription)")
                await MainActor.run {
                    try? Auth.auth().signOut()
                    // ContentView observes Auth.auth().currentUser and will redirect to sign-in
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
    
    // MARK: - Fetch User for Welcome Screen
    
    private func fetchCurrentUserForWelcome() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            return
        }
        
        do {
            let db = Firestore.firestore()
            let document = try await db.collection("users").document(userId).getDocument()
            
            if let user = try? document.data(as: UserModel.self) {
                await MainActor.run {
                    currentUser = user
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
                    // Integration preferences — start syncing on sign-in
                    AMENUserPreferencesService.shared.startListening()
                } else {
                    // Actual sign-out
                    // P0-D FIX: Reset fcmSetupDone so the next sign-in within the same
                    // session re-registers the FCM token for the new user account.
                    self.fcmSetupDone = false
                    dlog("👋 User logged out, unregistering device token")
                    await DeviceTokenManager.shared.unregisterDeviceToken()
                    AgeAssuranceService.shared.reset()
                    // Stop FollowService listeners so stale following data from the
                    // previous user doesn't leak into the next sign-in session.
                    FollowService.shared.stopListening()
                    // Stop integration prefs listener on sign-out
                    AMENUserPreferencesService.shared.stopListening()
                }
            }
        }
    }
    
    // MARK: - Cache Current User Profile
    
    private func cacheCurrentUserProfile() async {
        // Only cache if user is logged in
        guard Auth.auth().currentUser != nil else {
            dlog("⚠️ No user logged in, skipping profile cache")
            return
        }
        
        dlog("👤 Caching current user profile data...")
        
        // Cache current user's profile data for fast post creation
        await UserProfileImageCache.shared.cacheCurrentUserProfile()
        
        dlog("✅ User profile cached!")
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
            // Prayer Live Activity actions: prayed, snooze
            PrayerLiveActivityService.shared.handleDeepLink(url: url)

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
            group.addTask { _ = CrisisDetectionService.shared }
            group.addTask { _ = EnhancedCrisisSupportService.shared }
            group.addTask { _ = BereanShieldService.shared }
            group.addTask { _ = ContentSafetyShieldService.shared }
            group.addTask { _ = MinorSafetyService.shared }
            // Notification services
            group.addTask { _ = SmartNotificationService.shared }
            group.addTask { _ = NotificationAggregationService.shared }
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

        task.expirationHandler = {
            // iOS is revoking our budget — mark incomplete so the system knows
            // we didn't finish (may affect future scheduling heuristics).
            task.setTaskCompleted(success: false)
        }

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

        task.expirationHandler = {
            refreshTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
