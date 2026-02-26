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
// import FirebaseVertexAI  // TODO: Add Firebase VertexAI package later to enable AI features

@main
struct AMENAPPApp: App {
    // Register AppDelegate to handle Firebase Messaging and notifications
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var showWelcomeScreen = true  // Enabled - Show black AMEN welcome screen on app launch
    @State private var currentUser: UserModel? = nil  // Store user for personalized welcome
    
    // PERFORMANCE: Store auth listener handle for cleanup
    @State private var authStateHandle: AuthStateDidChangeListenerHandle?
    
    // Initialize Firebase when app launches
    init() {
        print("🚀 Initializing AMENAPPApp...")
        // Note: Firebase.configure() is called in AppDelegate.didFinishLaunchingWithOptions
        // Database persistence is also configured in AppDelegate after Firebase.configure()
        
        // ✅ Initialize Firebase Remote Config for AI API keys
        Task {
            Self.setupRemoteConfig()
        }
        
        // PERFORMANCE: Defer singleton initialization to first use
        // Singletons will initialize lazily when first accessed
        // This prevents blocking the main thread during app startup
        
        // ❌ REMOVED: Eager PostsManager initialization
        // Task { @MainActor in
        //     _ = PostsManager.shared
        //     print("✅ PostsManager initialized early")
        // }
        
        // ❌ REMOVED: Eager PostInteractionsService initialization  
        // Task {
        //     _ = PostInteractionsService.shared
        //     print("✅ PostInteractionsService initialized early")
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
                    print("✅ Remote Config activated - AI features enabled")
                }
            } else {
                print("⚠️ Remote Config fetch failed: \(error?.localizedDescription ?? "unknown")")
            }
        }
    }
    
    /// Automatically migrate users to add search keywords (runs once)
    private static func runAutomaticMigration() async {
        // Check if migration has already been run
        let hasRunMigration = UserDefaults.standard.bool(forKey: "hasRunUserKeywordsMigration")
        
        if hasRunMigration {
            print("✅ User keywords migration already completed")
            return
        }
        
        do {
            let status = try await UserKeywordsMigration.checkMigrationStatus()
            
            if status.needsMigration > 0 {
                print("🔄 Running automatic migration for \(status.needsMigration) users...")
                try await UserKeywordsMigration.migrateAllUsers()
                
                // Mark migration as complete
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: "hasRunUserKeywordsMigration")
                }
                
                print("✅ Automatic migration completed successfully!")
            } else {
                print("✅ No migration needed - all users already have keywords")
                // Mark as complete anyway
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: "hasRunUserKeywordsMigration")
                }
            }
        } catch {
            print("⚠️ Automatic migration failed (will retry next launch): \(error)")
            // Don't mark as complete so it can retry next time
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                
                if showWelcomeScreen {
                    WelcomeScreenView(isPresented: $showWelcomeScreen)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                // PERFORMANCE FIX: Defer all non-critical startup work
                // Only track app reopen immediately (lightweight, synchronous)
                ScrollBudgetManager.shared.trackAppReopen()
                
                // Defer everything else to background with priority staging
                Task(priority: .high) {
                    // High priority: User-visible data for welcome screen
                    await fetchCurrentUserForWelcome()
                    
                    // THREADS-STYLE: Preload posts during splash screen animation
                    // This makes posts appear instantly when ContentView loads
                    if Auth.auth().currentUser != nil {
                        print("⚡️ PRELOAD: Starting posts cache load during splash...")
                        _ = PostsManager.shared  // Initialize immediately
                        await FirebasePostService.shared.preloadCacheSync()
                        
                        // P0 FIX: Start real-time listener immediately (single source of truth)
                        await MainActor.run {
                            FirebasePostService.shared.startListening(category: .openTable)
                            print("✅ PRELOAD: Real-time listener started for OpenTable")
                        }
                    }
                }
                
                Task(priority: .medium) {
                    // Medium priority: Real-time listeners (needed soon but not immediately)
                    await startFollowServiceListeners()
                    await setupFCMForExistingUser()
                }
                
                Task(priority: .low) {
                    // Low priority: Background optimization tasks
                    await cacheCurrentUserProfile()
                    await Self.runAutomaticMigration()
                }
            }
            .onDisappear {
                // ✅ TRACK APP CLOSE (scroll budget)
                ScrollBudgetManager.shared.trackAppClose()
            }
            .onOpenURL { url in
                print("🔗 Handling deep link: \(url)")
                
                // ✅ P0 SECURITY: Handle Firebase Auth callbacks (phone verification, reCAPTCHA)
                // This MUST be first to ensure 2FA works properly
                if Auth.auth().canHandle(url) {
                    print("✅ Forwarded URL to Firebase Auth for verification")
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
            }
        }
    }
    
    // MARK: - Fetch User for Welcome Screen
    
    private func fetchCurrentUserForWelcome() {
        guard let userId = Auth.auth().currentUser?.uid else {
            return
        }
        
        Task {
            do {
                let db = Firestore.firestore()
                let document = try await db.collection("users").document(userId).getDocument()
                
                if let user = try? document.data(as: UserModel.self) {
                    await MainActor.run {
                        currentUser = user
                    }
                }
            } catch {
                print("⚠️ AMENAPPApp: Could not fetch user for welcome screen")
            }
        }
    }
    
    // MARK: - Start Follow Service Listeners
    
    private func startFollowServiceListeners() async {
        // Only start if user is logged in
        guard Auth.auth().currentUser != nil else {
            print("⚠️ No user logged in, skipping FollowService initialization")
            return
        }
        
        print("🚀 Starting FollowService listeners on app launch...")
        
        // Load current user's following and followers
        await FollowService.shared.loadCurrentUserFollowing()
        await FollowService.shared.loadCurrentUserFollowers()
        
        // Start real-time listeners for updates
        await FollowService.shared.startListening()
        
        print("✅ FollowService listeners started successfully!")
    }
    
    // MARK: - Setup FCM Token for Existing Users
    
    private func setupFCMForExistingUser() async {
        // Only setup FCM if user is logged in
        guard Auth.auth().currentUser != nil else {
            print("⚠️ No user logged in, skipping FCM setup")
            return
        }
        
        print("🔔 Checking notification permissions for existing user...")
        
        let hasPermission = await PushNotificationManager.shared.checkNotificationPermissions()
        
        if hasPermission {
            print("✅ User has notification permission, setting up FCM token...")
            await MainActor.run {
                PushNotificationManager.shared.setupFCMToken()
            }
            
            // ✅ NEW: Register device token with DeviceTokenManager
            do {
                try await DeviceTokenManager.shared.registerDeviceToken()
                print("✅ Device token registered successfully")
            } catch {
                print("❌ Device token registration failed: \(error.localizedDescription)")
            }
        } else {
            print("⚠️ User has not granted notification permission")
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
                if let user = user {
                    // User logged in - register token
                    print("👤 User logged in: \(user.uid)")
                    do {
                        try await DeviceTokenManager.shared.registerDeviceToken()
                    } catch {
                        print("❌ Token registration failed: \(error)")
                    }
                } else {
                    // User logged out - unregister token
                    print("👋 User logged out, unregistering device token")
                    await DeviceTokenManager.shared.unregisterDeviceToken()
                }
            }
        }
    }
    
    // MARK: - Cache Current User Profile
    
    private func cacheCurrentUserProfile() async {
        // Only cache if user is logged in
        guard Auth.auth().currentUser != nil else {
            print("⚠️ No user logged in, skipping profile cache")
            return
        }
        
        print("👤 Caching current user profile data...")
        
        // Cache current user's profile data for fast post creation
        await UserProfileImageCache.shared.cacheCurrentUserProfile()
        
        print("✅ User profile cached!")
    }
    
    // MARK: - Email Authentication Link Handler
    
    private func handleEmailAuthenticationLink(_ url: URL) {
        let link = url.absoluteString
        
        // Check if this is a Firebase email link
        if Auth.auth().isSignIn(withEmailLink: link) {
            print("📧 Detected email authentication link")
            
            // Get the email from UserDefaults (saved when link was sent)
            guard let email = UserDefaults.standard.string(forKey: "emailForSignIn") else {
                print("⚠️ No email found in UserDefaults for sign-in link")
                return
            }
            
            print("📧 Attempting to sign in with email link for: \(email)")
            
            // Sign in with the email link
            Task { @MainActor in
                do {
                    let authResult = try await Auth.auth().signIn(withEmail: email, link: link)
                    print("✅ Successfully signed in with email link!")
                    print("   User ID: \(authResult.user.uid)")
                    print("   Email: \(authResult.user.email ?? "none")")
                    
                    // Clear the email from UserDefaults
                    UserDefaults.standard.removeObject(forKey: "emailForSignIn")
                    
                    // Success haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                } catch {
                    print("❌ Email link sign-in failed: \(error.localizedDescription)")
                    
                    // Error haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
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
            print("📖 Opening church note with share link: \(shareLinkId)")
            
            // Post notification to open the note
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenChurchNoteFromDeepLink"),
                object: nil,
                userInfo: ["shareLinkId": shareLinkId]
            )
        }
    }
}
