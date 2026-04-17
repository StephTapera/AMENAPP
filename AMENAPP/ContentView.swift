//
//  ContentView.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import SwiftUI
import Combine
import UIKit
import FirebaseAuth
import FirebaseFirestore

struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel
    @StateObject private var authViewModel: AuthenticationViewModel
    @StateObject private var messagingCoordinator: MessagingCoordinator
    
    // ⚡️ PERFORMANCE OPTIMIZED: Extract specific state instead of observing entire singletons
    // This prevents ContentView from redrawing on every singleton @Published change
    @State private var showSplash: Bool = true     // Splash shown on first unauthenticated load
    @State private var totalBadgeCount: Int = 0
    @State private var showSundayPrompt: Bool = false
    @State private var showTimeoutWarning: Bool = false
    @State private var showFTUE: Bool = false
    @AppStorage("amenAccountTypeOnboardingComplete") private var amenAccountTypeOnboardingComplete: Bool = false
    
    // ⚡️ P1-3 FIX: Extracted specific state from singletons to avoid ContentView
    // redrawing on every @Published change in SessionTimeoutManager, AppReadyStateManager,
    // AppUsageTracker, and SundayChurchFocusManager. Action calls go direct to .shared.
    // Drive the overlay directly off AppReadyStateManager as an @ObservedObject so
    // there is ZERO frame delay between signalSignIn()/signalReady() publishing and the
    // overlay responding. The old @State + onReceive pattern had a 1-frame lag that caused
    // the main screen to briefly appear between signalSignIn() and the @State update.
    @ObservedObject private var appReadyState = AppReadyStateManager.shared
    private var isShowingLoadingScreen: Bool { appReadyState.isShowingLoadingScreen }
    private var shouldShowAccountTypeOnboarding: Bool {
        // ✅ DISABLED: All users get Personal account by default (like Instagram/Threads)
        // Church/Business accounts can be added in settings if needed later
        false
    }
    @State private var showLimitReachedDialog = false
    @State private var showCreatePost: Bool
    @State private var showCreateQuickActions = false
    @Namespace private var createPostNamespace
    @State private var postCardFrame: CGRect? = nil
    @State private var bereanButtonFrame: CGRect? = nil
    @State private var selectedPostCategory: CreatePostView.PostCategory = .openTable
    @State private var showBereanQuickActions = false
    @State private var showBereanAssistantFromMenu = false
    @State private var tabBarBadges = AMENBadgeCounts()
    @AppStorage("currentUserProfileImageURL") private var currentUserProfileImageURL: String = ""
    @State private var postingBarState: PostingBarState = .hidden
    @State private var postingBarCategory: String = ""
    @State private var postingBarPost: Post? = nil
    @State private var savedSearchObserver: NSObjectProtocol?
    @State private var postSuccessObserver: NSObjectProtocol?
    @State private var postingStartedObserver: NSObjectProtocol?
    @State private var postingFailedObserver: NSObjectProtocol?
    @State private var discoverTabObserver: NSObjectProtocol?
    @State private var postingBarDismissTask: Task<Void, Never>? = nil
    @State private var showTabBar = true  // ✅ Control tab bar visibility
    @ObservedObject private var tabScrollBridge = AMENTabBarScrollBridge.shared
    @State private var showCommunityCovenant = false
    @State private var needsCovenantAgreement = false
    // P1-1 FIX: First-post prompt deferred from OnboardingView so it fires after the
    // onboarding→main-app transition completes rather than during view teardown.
    @State private var showFirstPostPrompt = false
    @State private var showCompulsiveReopenRedirect = false
    @State private var compulsiveReopenCount = 0
    
    // ✅ SHEET COORDINATION: Prevents simultaneous modal presentation conflicts
    enum ActiveModal: Identifiable {
        case sundayPrompt
        case authSuccess
        case welcomeToAMEN
        case compulsiveReopenRedirect(Int)
        
        var id: String {
            switch self {
            case .sundayPrompt: return "sundayPrompt"
            case .authSuccess: return "authSuccess"
            case .welcomeToAMEN: return "welcomeToAMEN"
            case .compulsiveReopenRedirect: return "compulsiveReopenRedirect"
            }
        }
    }
    
    @State private var activeModal: ActiveModal?
    // isResolvingAuthState removed: AppReadyStateManager.isShowingLoadingScreen is now
    // pre-set to true on init for cached users, so the overlay covers the entire auth
    // resolution window. There is no separate Screen 1 anymore — one loading screen only.
    // Welcome screen — layered inside the single loading overlay so both exit together.
    @StateObject private var welcomeManager = WelcomeScreenManager()
    // Idempotency gate: prevents core service startup from running more than once
    // per session even if mainContent.onAppear fires multiple times.
    @State private var hasStartedCoreServices = false
    // Guards the Shabbat tab-redirect from firing on cold launch before .task
    // has had a chance to set selectedTab = 0. The first scenePhase .active
    // fires before .task runs, so without this the Shabbat check wins the race
    // and the app opens on Resources instead of Home.
    @State private var hasHandledFirstActivation = false
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Initialize property wrappers - default to HomeView (tab 0) to show OpenTable
        _viewModel = StateObject(wrappedValue: ContentViewModel())
        _authViewModel = StateObject(wrappedValue: AuthenticationViewModel())
        _messagingCoordinator = StateObject(wrappedValue: MessagingCoordinator.shared)
        _showCreatePost = State(initialValue: false)
        
        // Make tab bar smaller and more compact
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor.systemBackground
        
        // Reduce tab bar height by adjusting insets
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.secondaryLabel
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor.label
        
        // Remove titles to make it more compact (use minimum valid font size)
        let emptyFont = UIFont.systemFont(ofSize: 1.0, weight: .regular)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .font: emptyFont,
            .foregroundColor: UIColor.clear
        ]
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .font: emptyFont,
            .foregroundColor: UIColor.clear
        ]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    
    var body: some View {
        Group {
            // ✅ INSTAGRAM/THREADS PATTERN: No loading screen for returning users
            // Authenticated users go straight to main content
            if authViewModel.needs2FAVerification {
                // P0 SECURITY: 2FA verification gate (before email verification)
                TwoFactorVerificationGateView()
                    .environmentObject(authViewModel)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .onAppear {
                        dlog("🚦 [LAUNCH] ContentView → TwoFactorVerificationGateView appeared")
                        AppReadyStateManager.shared.signalReady()
                    }
            } else if !authViewModel.isAuthenticated {
                // Splash → auth landing → sign-in flow
                ZStack {
                    // Landing (underneath)
                    AMENAuthLandingView()
                        .environmentObject(authViewModel)
                        .transition(.opacity)

                    // Splash (on top, fades out after animation completes)
                    if showSplash {
                        // Returning user: premium auto-login splash with cached profile
                        if authViewModel.hasCachedUser {
                            AutoLoginSplashView(
                                cachedUsername: authViewModel.cachedUsername,
                                cachedPhotoURL: authViewModel.cachedPhotoURL,
                                onSuccess: {
                                    // Auth resolved: dismiss splash; auth listener will
                                    // set isAuthenticated = true and show main app
                                    withAnimation(Motion.adaptive(.spring(response: 0.6, dampingFraction: 0.8))) {
                                        showSplash = false
                                    }
                                },
                                onFailure: {
                                    // Timeout / failed: fall through to login screen
                                    withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.85))) {
                                        showSplash = false
                                    }
                                }
                            )
                            .zIndex(1)
                            .transition(.opacity)
                        } else {
                            // New / logged-out user: standard splash
                            SplashView {
                                withAnimation(.easeIn(duration: 0.2)) { showSplash = false }
                            }
                            .zIndex(1)
                            .transition(.opacity)
                        }
                    }
                }
                .onAppear {
                    dlog("🚦 [LAUNCH] ContentView → auth landing appeared (isAuthenticated=false)")
                    if Auth.auth().currentUser == nil {
                        AppReadyStateManager.shared.signalReady()
                    }
                }
            } else if authViewModel.isDeactivated {
                // Account deactivated — show reactivation prompt (user is signed in to Firebase
                // but their profile is hidden; they must explicitly reactivate to proceed)
                ReactivationPromptView(status: authViewModel.deactivationStatus)
                    .environmentObject(authViewModel)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .onAppear {
                        dlog("🚦 [LAUNCH] ContentView → ReactivationPromptView appeared")
                        AppReadyStateManager.shared.signalReady()
                    }
            } else if authViewModel.needsUsernameSelection {
                // Show username selection for social sign-in users (before onboarding)
                UsernameSelectionView()
                    .environmentObject(authViewModel)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
                    .onAppear {
                        dlog("🚦 [LAUNCH] ContentView → UsernameSelectionView appeared")
                        AppReadyStateManager.shared.signalReady()
                    }
                    .onDisappear {
                        // Mark username selection as complete when dismissed
                        authViewModel.completeUsernameSelection()
                    }
            } else if authViewModel.needsOnboarding {
                // Show onboarding flow for new users (before email verification gate,
                // so new sign-ups reach onboarding immediately after account creation)
                OnboardingView()
                    .environmentObject(authViewModel)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .onAppear {
                        dlog("🚦 [LAUNCH] ContentView → OnboardingView appeared")
                        // Onboarding users never reach mainContent, so signalReady() would
                        // never be called there. Clear the loading screen overlay immediately
                        // so it doesn't cover the entire onboarding flow.
                        AppReadyStateManager.shared.signalReady()
                    }
            } else if authViewModel.needsEmailVerification {
                // P0: Email verification gate — shown after onboarding completes
                EmailVerificationGateView()
                    .environmentObject(authViewModel)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .onAppear {
                        dlog("🚦 [LAUNCH] ContentView → EmailVerificationGateView appeared")
                        AppReadyStateManager.shared.signalReady()
                    }
            } else {
                // Main app content
                mainContent
                    .transition(.opacity)
                    .onAppear {
                        dlog("🚦 [LAUNCH] mainContent.onAppear fired (hasStartedCoreServices=\(hasStartedCoreServices))")
                        dlog("🔍 [SCROLL DEBUG] UI State Check:")
                        dlog("   - isShowingLoadingScreen: \(isShowingLoadingScreen)")
                        dlog("   - showTimeoutWarning: \(showTimeoutWarning)")
                        dlog("   - showTabBar: \(showTabBar)")
                        dlog("   - showLimitReachedDialog: \(showLimitReachedDialog)")
                        // Stamp the current app version so the next launch can detect updates.
                        welcomeManager.recordLaunch()

                        // P1-1 FIX: Show first-post welcome prompt if onboarding just completed.
                        // The flag is set by OnboardingView.finishOnboarding() before completeOnboarding()
                        // tears the view down, so the sheet now appears from stable main-app context.
                        if UserDefaults.standard.bool(forKey: "showFirstPostPromptPending") {
                            UserDefaults.standard.removeObject(forKey: "showFirstPostPromptPending")
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 600_000_000) // let transition settle
                                showFirstPostPrompt = true
                            }
                        }

                        // Show cinematic loading screen if this is a fresh sign-in
                        AppReadyStateManager.shared.startIfNeeded()

                        // Idempotency gate: only run core service startup once per session.
                        // mainContent.onAppear can fire on every foreground transition and
                        // navigation event — without this gate each re-appear would spawn
                        // duplicate tasks and listeners.
                        guard !hasStartedCoreServices else { return }
                        hasStartedCoreServices = true

                        // Phase 1 — CRITICAL: feed ready signal (blocks loading overlay)
                        Task(priority: .high) {
                            _ = PostsManager.shared
                            await waitForFeedReady()
                            AppReadyStateManager.shared.signalReady()
                        }

                        // SAFETY: Absolute maximum timeout — loading screen always dismisses
                        Task {
                            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s hard cap
                            AppReadyStateManager.shared.signalReady()
                        }

                        // Phase 2 — NEAR-IMMEDIATE: warm up secondary singletons
                        Task(priority: .medium) {
                            _ = PostInteractionsService.shared
                            await PremiumManager.shared.loadProducts()
                        }

                        // Phase 2b — Start notification listener immediately on auth.
                        // Previously this was in HomeView.onAppear, so it never fired
                        // when the app launched directly into any other tab via push tap.
                        NotificationService.shared.startListening()
                        if let currentUserId = Auth.auth().currentUser?.uid {
                            ChurchInteractionService.shared.startListening(userId: currentUserId)
                        }

                        // Signal the deep-link router that the nav tree is ready.
                        // Any cold-start push notification route queued before this fires now.
                        NotificationDeepLinkRouter.shared.markAppReady()
                        NotificationTapBootstrapper.shared.appDidBecomeReady()

                        // Phase 3 — DEFERRED: non-blocking checks
                        Task(priority: .utility) {
                            await authViewModel.checkEmailVerification()
                        }
                    }
                    .task {
                        // PERFORMANCE FIX: Run migrations in low-priority background task
                        // This prevents blocking the UI during initial render
                        Task(priority: .utility) {
                            // Run user search migration on first launch (production-ready, silent)
                            await runUserSearchMigrationIfNeeded()
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: authViewModel.needs2FAVerification)
        .animation(.easeOut(duration: 0.2), value: authViewModel.isAuthenticated)
        .animation(.easeOut(duration: 0.2), value: authViewModel.isDeactivated)
        .animation(.easeOut(duration: 0.2), value: authViewModel.needsUsernameSelection)
        .animation(.easeOut(duration: 0.2), value: authViewModel.needsOnboarding)
        .animation(.easeOut(duration: 0.2), value: authViewModel.needsEmailVerification)
        // ✅ CONSOLIDATED MODAL PRESENTATIONS (prevents auth flow conflicts)
        .sheet(item: $activeModal) { modal in
            switch modal {
            case .sundayPrompt:
                SundayShabbatPromptView()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            case .authSuccess:
                AuthSuccessCheckmarkView(isPresented: Binding(
                    get: { activeModal != nil },
                    set: { if !$0 { activeModal = nil } }
                ))
            case .welcomeToAMEN:
                WelcomeToAMENView()
                    .onDisappear {
                        authViewModel.dismissWelcomeToAMEN()
                        activeModal = nil
                    }
            case .compulsiveReopenRedirect(let count):
                CompulsiveReopenRedirectView(reopenCount: count)
            }
        }
        .onChange(of: authViewModel.showAuthSuccess) { _, newValue in
            if newValue {
                activeModal = .authSuccess
            }
        }
        .onChange(of: authViewModel.showWelcomeToAMEN) { _, newValue in
            if newValue {
                activeModal = .welcomeToAMEN
            }
        }
        .onChange(of: authViewModel.isAuthenticated) { oldValue, newValue in
            dlog("🚦 [LAUNCH] isAuthenticated changed: \(oldValue) → \(newValue) (needsOnboarding=\(authViewModel.needsOnboarding))")
            // Check if FTUE should be shown when user becomes authenticated
            if newValue && !oldValue {
                // Signal a fresh sign-in so the cinematic loading screen shows
                // when mainContent first appears
                AppReadyStateManager.shared.signalSignIn()

                FTUEManager.shared.checkAndShowFTUE()

                // Start session timeout monitoring (respects Remember Me setting)
                let rememberMe = SessionTimeoutManager.shared.isRememberMeEnabled()
                SessionTimeoutManager.shared.startMonitoring(rememberMe: rememberMe)

                // Install quick actions now that a user is authenticated
                AMENQuickActionManager.shared.installShortcuts(
                    hasDraft: !DraftsManager.shared.drafts.isEmpty,
                    unreadMessageCount: BadgeCountManager.shared.unreadMessages
                )
            } else if !newValue && oldValue {
                // User logged out - stop monitoring and reset startup gate so the
                // next sign-in runs the full core services startup block again.
                SessionTimeoutManager.shared.stopMonitoring()
                hasStartedCoreServices = false
                hasHandledFirstActivation = false

                // Clear quick actions — shortcuts would fail auth gate if user is signed out
                AMENQuickActionManager.shared.clearShortcuts()
            }
        }
        // P3-2 FIX: Removed empty onChange handlers for needsOnboarding and
        // needsUsernameSelection. These were no-ops that still caused body re-evaluations
        // on every change. The animated group above already reacts to these via the
        // .animation() modifiers on the Group, so these handlers were dead code.
        .onChange(of: messagingCoordinator.shouldOpenMessagesTab) { oldValue, newValue in
            if newValue {
                dlog("🚦 [TAB] MessagingCoordinator → selectedTab = 2 (Messages)")
                viewModel.selectedTab = 2  // Switch to Messages tab (now at index 2)
            }
        }
        // ── QUICK ACTIONS: Route consumer ────────────────────────────────────────
        // Watches AMENQuickActionManager.pendingRoute and navigates once mainContent
        // is displayed and the user is authenticated. Works for both cold launches
        // (where the route was stored before auth resolved) and warm launches
        // (where performActionFor fires while the app is already running).
        .onReceive(AMENQuickActionManager.shared.$pendingRoute) { route in
            guard let route else { return }
            handleQuickActionRoute(route)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)

            let isActive = newPhase == .active
            let isLeavingForeground = newPhase == .background || newPhase == .inactive
            if isActive {
                WellnessGuardianService.shared.trackSessionStart()
            } else if isLeavingForeground {
                WellnessGuardianService.shared.trackSessionEnd()
            }
        }
        .overlay {
            WellnessBreakReminderView(wellness: WellnessGuardianService.shared)
        }
        .overlay {
            // Session Timeout Warning
            if showTimeoutWarning {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Dismiss warning on background tap
                        SessionTimeoutManager.shared.extendSession()
                    }
                    .onAppear {
                        dlog("⚠️ [SCROLL DEBUG] Timeout warning overlay appeared - BLOCKS INTERACTION")
                    }

                SessionTimeoutWarningView()
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onChange(of: showTimeoutWarning) { oldValue, newValue in
            dlog("🔄 [SCROLL DEBUG] showTimeoutWarning changed: \(oldValue) → \(newValue)")
        }
        .overlay(alignment: .top) {
            WellnessRiskOverlay()
                .padding(.top, 6)
        }
        // Single launch overlay — covers auth resolution AND post-sign-in data loading.
        // AppLoadingScreen shows the logo + tagline + loading dots all in one view
        // so there is no separate welcome screen stacking that causes background flashes.
        .overlay {
            if isShowingLoadingScreen {
                AppLoadingScreen()
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: 0.35)))
                    .zIndex(10)
                    .allowsHitTesting(false)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { shouldShowAccountTypeOnboarding },
                set: { _ in }
            )
        ) {
            AMENAccountTypeOnboardingView()
        }
    }
    
    @ViewBuilder
    private var selectedTabView: some View {
        // ✅ Shabbat Mode: Gate restricted features
        if SundayChurchFocusManager.shared.shouldGateFeature() && !isAllowedDuringChurchFocus(viewModel.selectedTab) {
            SundayChurchFocusGateView(selectedTab: $viewModel.selectedTab)
                .id("shabbatModeGate")
                .animation(nil, value: viewModel.selectedTab)
        } else {
            ZStack {
                    keepMountedTab(isActive: viewModel.selectedTab == 0) {
                        HomeView(showBereanQuickActions: $showBereanQuickActions, showBereanAssistantFromMenu: $showBereanAssistantFromMenu, selectedPostCategory: $selectedPostCategory)
                            .onAppear {
                                if viewModel.selectedTab == 0 {
                                    NotificationAggregationService.shared.updateCurrentScreen(.home)
                                }
                            }
                            .onChange(of: viewModel.selectedTab) { _, tab in
                                if tab == 0 {
                                    NotificationAggregationService.shared.updateCurrentScreen(.home)
                                }
                            }
                    }

                    keepMountedTab(isActive: viewModel.selectedTab == 1) {
                        AMENDiscoveryView()
                            .id("discovery")
                            .task {
                                NotificationAggregationService.shared.updateCurrentScreen(.none)
                            }
                    }

                    keepMountedTab(isActive: viewModel.selectedTab == 2) {
                        MessagesView()
                            .id("messages")
                            .environmentObject(messagingCoordinator)
                            .task {
                                NotificationAggregationService.shared.updateCurrentScreen(.messages)
                                BadgeCountManager.shared.clearMessages()
                            }
                            .ageGated(feature: .directMessages)
                    }

                    keepMountedTab(isActive: viewModel.selectedTab == 3) {
                        ResourcesView()
                            .id("resources")
                            .task {
                                NotificationAggregationService.shared.updateCurrentScreen(.none)
                            }
                    }

                    keepMountedTab(isActive: viewModel.selectedTab == 4) {
                        AMENNotificationsView()
                            .id("notifications")
                            .task {
                                NotificationAggregationService.shared.updateCurrentScreen(.notifications)
                            }
                    }

                    keepMountedTab(isActive: viewModel.selectedTab == 5) {
                        ProfileView()
                            .environmentObject(authViewModel)
                            .id("profile")
                            .task {
                                let uid = Auth.auth().currentUser?.uid ?? ""
                                NotificationAggregationService.shared.updateCurrentScreen(.profile(userId: uid))
                            }
                    }
                }
                .animation(nil, value: viewModel.selectedTab)
            }
    }

    @ViewBuilder
    private func keepMountedTab<Content: View>(isActive: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
    }
    
    // ✅ Shabbat Mode: Check if tab is allowed during focus window
    private func isAllowedDuringChurchFocus(_ tab: Int) -> Bool {
        // Tab 3 = Resources (contains Church Notes and Find Church)
        // Tab 5 = Profile (contains Settings)
        // All other tabs (Home, People, Messages, Notifications) are restricted
        return tab == 3 || tab == 5
    }
    
    private var mainContentBody: some View {
        ZStack {
            // Main content (takes full screen)
            selectedTabView
                .ignoresSafeArea(.all, edges: .bottom)

            // Email verification banner (appears at top when email not verified)
            if authViewModel.showEmailVerificationBanner {
                VStack {
                    EmailVerificationBanner()
                        .environmentObject(authViewModel)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(997)
                    Spacer()
                }
                .allowsHitTesting(true)
            }

            // Daily limit reached dialog
            if showLimitReachedDialog {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))

                DailyLimitReachedDialog()

                    .transition(.scale(scale: 0.95).combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.8)))
                    .zIndex(999)
            }

            // Threads-style posting bar (appears at bottom while posting / after posted)
            if postingBarState != .hidden {
                VStack {
                    Spacer()
                    ThreadsPostingBar(
                        state: postingBarState,
                        category: postingBarCategory,
                        post: postingBarPost
                    ) {
                        // "View" tapped — navigate to the post and immediately hide
                        postingBarDismissTask?.cancel()
                        postingBarDismissTask = nil
                        if let post = postingBarPost {
                            NotificationCenter.default.post(
                                name: .newPostCreated,
                                object: nil,
                                userInfo: ["post": post, "navigateTo": true, "category": postingBarCategory]
                            )
                        }
                        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.85))) {
                            postingBarState = .hidden
                        }
                    }
                    .padding(.bottom, 84) // just above tab bar
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(998)
                }
            }
        }
        .moderationToast() // ✅ Add moderation toast overlay
        .inAppNotificationBanner() // ✅ Instagram-style heads-up banner for foreground notifications
    }

    private var mainContentWithOverlays: some View {
        mainContentBody
        // P0 FIX: Wire push notification deep links to tab navigation.
        // NotificationDeepLinkRouter.shared publishes activeDestination whenever
        // a push is tapped. This modifier observes it and switches selectedTab.
        .handleNotificationNavigation(selectedTab: $viewModel.selectedTab)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Reserve space for the floating tab bar so ScrollViews don't clip content
            // Always reserve space - tab bar moves offscreen with keyboard instead of disappearing
            Color.clear
                .frame(height: showTabBar ? 74 : 0) // capsule height (54) + bottom padding (10) + extra (10)
                .animation(.easeOut(duration: 0.25), value: showTabBar)
        }
        .overlay(alignment: .bottom) {
            // Always render tab bar, move it offscreen when keyboard appears
            AMENTabBar(
                selectedTab: $viewModel.selectedTab,
                badges: $tabBarBadges,
                onCompose: {
                    tabScrollBridge.expand()
                    selectedPostCategory = .openTable
                    showCreatePost = true
                },
                profilePhotoURL: currentUserProfileImageURL.isEmpty ? nil : currentUserProfileImageURL,
                isMinimized: tabScrollBridge.isMinimized
            )
            .offset(y: showTabBar ? 0 : 150) // Move offscreen when keyboard appears
            .animation(.easeOut(duration: 0.25), value: showTabBar)
            .onChange(of: viewModel.selectedTab) { _, _ in
                tabScrollBridge.expand()
            }
        }
        .overlay(alignment: .bottom) {
            // Audio mini player bar — shown during speech playback
            if AMENFeatureFlags.shared.audioNarrationEnabled {
                AudioMiniPlayerBar()
                    .padding(.bottom, showTabBar ? 80 : 8)
            }
        }
        .overlay(alignment: .top) {
            // Adaptive accessibility suggestion banner
            if AMENFeatureFlags.shared.adaptiveAccessibilityEnabled {
                AccessibilitySuggestionBanner()
                    .padding(.top, 50)
            }
        }
        .overlay {
            // Long press menu as a separate overlay - won't affect tab bar
            createPostQuickActionsOverlay
        }
        .overlay {
            // Berean Bible icon menu as full-screen overlay
            bereanQuickActionsOverlay
        }
        .overlay {
            // FTUE Coach Marks overlay
            if FTUEManager.shared.shouldShowCoachMarks {
                CoachMarkOverlay(
                    ftueManager: FTUEManager.shared,
                    postCardFrame: postCardFrame,
                    bereanButtonFrame: bereanButtonFrame
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                .zIndex(1000)
            }
        }
        .environment(\.tabBarVisible, $showTabBar)  // ✅ Pass visibility to child views
        .environment(\.mainTabSelection, $viewModel.selectedTab)  // ✅ Pass tab selection to child views
        .onPreferenceChange(PostCardFramePreferenceKey.self) { equatableFrame in
            // ✅ FIX: Only update if frame not yet captured OR FTUE is not showing
            // Once FTUE shows, freeze the frame to prevent scroll stuttering
            if let frame = equatableFrame {
                // Only update if we don't have a frame yet, or FTUE is not active
                if postCardFrame == nil || !FTUEManager.shared.shouldShowCoachMarks {
                    postCardFrame = frame.rect
                }
            }
        }
        .onPreferenceChange(BereanButtonFramePreferenceKey.self) { equatableFrame in
            // ✅ FIX: Only update if frame not yet captured OR FTUE is not showing
            // Once FTUE shows, freeze the frame to prevent scroll stuttering
            if let frame = equatableFrame {
                // Only update if we don't have a frame yet, or FTUE is not active
                if bereanButtonFrame == nil || !FTUEManager.shared.shouldShowCoachMarks {
                    bereanButtonFrame = frame.rect
                }
            }
        }
        // Contextual glass sheet — emerges from the compose button with staged content reveal
        .glassContextualSheet(
            isPresented: $showCreatePost,
            sourceId: "composeButton",
            namespace: createPostNamespace
        ) {
            CreatePostView(initialCategory: selectedPostCategory)
        }
        // Berean Dynamic Island — sits above all content, dismisses on outside tap
        .overlay(alignment: .top) {
            BereanDynamicIsland(
                vm: BereanIslandViewModel.shared,
                onOpenFull: {
                    BereanIslandViewModel.shared.onOpenFullSheet?()
                }
            )
            .zIndex(999)
        }
        .environmentObject(AppUsageTracker.shared)
        .environmentObject(NotificationManager.shared)
        .environmentObject(BadgeCountManager.shared)  // ✅ P0-10, P0-11, P0-12: Provide for all child views
        .environmentObject(SundayChurchFocusManager.shared)  // ✅ Shabbat Mode: Provide to all child views
        .environmentObject(FirebaseMessagingService.shared)  // P0-7: Provide for CompactTabBar
        .environmentObject(PostsManager.shared)  // P0-7: Provide for CompactTabBar
        .environmentObject(UserService.shared)  // P0-7: Provide for CompactTabBar
        .environmentObject(NotificationService.shared)  // P0-7: Provide for CompactTabBar
    }

    private var mainContent: some View {
        mainContentWithOverlays
        // ⚡️ PERFORMANCE: Subscribe to specific state changes instead of observing entire singletons
        .onReceive(BadgeCountManager.shared.$totalBadgeCount) { count in
            totalBadgeCount = count
        }
        .onReceive(BadgeCountManager.shared.$unreadMessages) { count in
            tabBarBadges.messages = count
        }
        .onReceive(BadgeCountManager.shared.$unreadNotifications) { count in
            tabBarBadges.notifications = count
        }
        .onReceive(SundayChurchFocusManager.shared.$showSundayPrompt) { show in
            if show {
                activeModal = .sundayPrompt
            }
        }
        .onReceive(FTUEManager.shared.$shouldShowCoachMarks) { show in
            showFTUE = show
        }
        // P1-3: Targeted subscriptions replace @ObservedObject singletons
        .onReceive(SessionTimeoutManager.shared.$showTimeoutWarning) { show in
            showTimeoutWarning = show
        }
        // isShowingLoadingScreen is now a computed var from @ObservedObject appReadyState —
        // no onReceive needed. Logging handled in AppReadyStateManager.signalSignIn/signalReady.
        .onReceive(AppUsageTracker.shared.$showLimitReachedDialog) { show in
            showLimitReachedDialog = show
        }
        .onChange(of: SundayChurchFocusManager.shared.isInChurchFocusWindow) { oldValue, newValue in
            // ✅ Real-time transition: Force re-render when Shabbat state changes
            // Use ShabbatModeService.isShabbatActive (combines isSunday + isEnabled)
            let shabbatActive = ShabbatModeService.shared.isShabbatActiveNow()
            dlog("🚦 [TAB] ChurchFocusWindow changed \(oldValue)→\(newValue), shabbatActive=\(shabbatActive), currentTab=\(viewModel.selectedTab)")
            if shabbatActive && !isAllowedDuringChurchFocus(viewModel.selectedTab) {
                #if DEBUG
                ShabbatAnalytics.logStateTransition(enabled: true, isSunday: true)
                #endif
                dlog("🚦 [TAB] ChurchFocus active → selectedTab = 3 (Resources)")
                viewModel.selectedTab = 3  // Resources (Church Notes/Find Church)
            } else if !shabbatActive && oldValue {
                // Shabbat ended (midnight Sunday→Monday) — allow normal navigation
                #if DEBUG
                ShabbatAnalytics.logStateTransition(enabled: ShabbatModeService.shared.isEnabled, isSunday: false)
                #endif
            }
        }
        // Handle blocked deep links — show gate banner and route to Resources
        .onReceive(NotificationCenter.default.publisher(for: .shabbatDeepLinkBlocked)) { notification in
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                viewModel.selectedTab = 3
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToChurchNotes)) { _ in
            // Navigate to Resources tab (index 3), which contains Church Notes
            viewModel.selectedTab = 3
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToFindChurch)) { _ in
            // Navigate to Resources tab (index 3), which contains Find Church
            viewModel.selectedTab = 3
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSettings)) { _ in
            // Navigate to Profile tab (which contains Settings) — tab index 5
            viewModel.selectedTab = 5
        }
        .onReceive(NotificationCenter.default.publisher(for: .compulsiveReopenDetected)) { notification in
            // Show supportive redirect when compulsive reopening detected
            compulsiveReopenCount = notification.userInfo?["reopenCount"] as? Int ?? 0
            activeModal = .compulsiveReopenRedirect(compulsiveReopenCount)
        }

        .task {
            // Ensure we start on Home tab (OpenTable view)
            dlog("🚦 [TAB] .task → selectedTab = 0 (Home)")
            viewModel.selectedTab = 0
            
            // NOTE: startSession() is called by handleScenePhaseChange(.active) — no duplicate call here
            
            // P0-5: Parallelize cold launch tasks for 3x faster startup
            await runParallelLaunchTasks()
            
            // Start listening to messages for real-time badge updates (after parallel tasks)
            FirebaseMessagingService.shared.startListeningToConversations()
            
            // BadgeCountManager.startRealtimeUpdates() is called by its own
            // auth-state listener (setupAuthStateListener) when the user signs in,
            // so no explicit call is needed here — the guard !isListening inside
            // startRealtimeUpdates() also prevents duplicate listeners.
            
            // 🔒 TRUST-BY-DESIGN: Load privacy settings on app launch
            if let userId = Auth.auth().currentUser?.uid {
                do {
                    try await TrustByDesignService.shared.loadPrivacySettings(userId: userId)
                } catch {
                    // Non-fatal — privacy settings will use defaults
                }
            }
            
            // ✅ Sunday Church Focus: Monitor window changes for real-time transitions
            // (Timer in manager updates every minute)
            
            // Setup notification observers (synchronous, fast)
            setupSavedSearchObserver()
            setupPostSuccessObserver()
            setupDiscoverTabObserver()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCreatePost)) { _ in
            withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8))) {
                showCreatePost = true
            }
        }
        // P1-1 FIX: First-post welcome prompt shown once after onboarding completes.
        // Triggered by the UserDefaults flag set in OnboardingView.finishOnboarding().
        .sheet(isPresented: $showFirstPostPrompt) {
            ONBFirstPostSheet(isPresented: $showFirstPostPrompt)
        }
        .onDisappear {
            // P0-3: Add comprehensive listener cleanup to prevent memory leaks

            // Stop tracking when view disappears
            AppUsageTracker.shared.endSession()
            
            // Stop Firestore listeners
            FirebaseMessagingService.shared.stopListeningToConversations()
            
            // ✅ P0-2 FIX: Stop feed post listeners to prevent memory leak
            FirebasePostService.shared.stopListening()
            
            // ✅ P0-10, P0-11, P0-12 FIX: Stop badge count manager listeners
            BadgeCountManager.shared.stopRealtimeUpdates()

            // Remove notification observers
            if let savedSearchObserver {
                NotificationCenter.default.removeObserver(savedSearchObserver)
                self.savedSearchObserver = nil
            }

            if let postSuccessObserver {
                NotificationCenter.default.removeObserver(postSuccessObserver)
                self.postSuccessObserver = nil
            }

            if let postingStartedObserver {
                NotificationCenter.default.removeObserver(postingStartedObserver)
                self.postingStartedObserver = nil
            }

            if let postingFailedObserver {
                NotificationCenter.default.removeObserver(postingFailedObserver)
                self.postingFailedObserver = nil
            }

            if let discoverTabObserver {
                NotificationCenter.default.removeObserver(discoverTabObserver)
                self.discoverTabObserver = nil
            }
            
        }
    }
    
    private func setupDiscoverTabObserver() {
        guard discoverTabObserver == nil else { return }
        discoverTabObserver = NotificationCenter.default.addObserver(
            forName: .switchToDiscoverTab,
            object: nil,
            queue: .main
        ) { [self] _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.selectedTab = 1
                }
            }
        }
    }
    
    // MARK: - Parallel Launch Tasks

    /// Runs cache warm-up tasks concurrently on app launch.
    /// Extracted to give the Swift type-checker a simpler expression inside the `.task` modifier.
    private func runParallelLaunchTasks() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await UserProfileImageCache.shared.cacheCurrentUserProfile()
            }
            group.addTask {
                await self.setupPushNotifications()
            }
            group.addTask {
                await FirebaseMessagingService.shared.fetchAndCacheCurrentUserName()
            }
        }
    }

    // MARK: - Push Notification Setup
    
    private func setupPushNotifications() async {
        let pushManager = PushNotificationManager.shared
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            // FCM token already set up by AppDelegate at launch — only configure categories here.
            SmartBreakReminderService.shared.setupNotificationCategories()

        case .notDetermined:
            // First time asking — wait 2 s so the user has context before seeing the prompt
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let granted = await pushManager.requestNotificationPermissions()
            if granted {
                // First-time grant: AppDelegate already ran setupFCMToken() at launch, but
                // APNS token may not have been available yet. Trigger it now so the FCM token
                // is registered after the APNS token is confirmed.
                await MainActor.run { pushManager.setupFCMToken() }
                SmartBreakReminderService.shared.setupNotificationCategories()
            }

        case .denied:
            // User has already declined — don't call requestAuthorization again (it's silent
            // but still prints the ❌ log and wastes a round-trip). Silently skip.
            // Notification permission can be prompted later in context (e.g. Settings screen).
            break

        @unknown default:
            break
        }
    }
    
    // MARK: - Saved Search Notification Observer
    
    private func setupSavedSearchObserver() {
        guard savedSearchObserver == nil else { return }

        savedSearchObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("openSavedSearch"),
            object: nil,
            queue: .main
        ) { [self] notification in
            guard notification.userInfo?["savedSearchId"] is String,
                  notification.userInfo?["query"] is String else { return }
            
            Task { @MainActor in
                // Navigate to search tab
                viewModel.selectedTab = 1

                // Haptic feedback
                HapticManager.impact(style: .light)
            }
        }
    }
    
    // MARK: - Post Success Notification Observer
    
    private func setupPostSuccessObserver() {
        guard postSuccessObserver == nil else { return }

        // "Posting..." — fires immediately when user taps Publish
        postingStartedObserver = NotificationCenter.default.addObserver(
            forName: .postingStarted,
            object: nil,
            queue: .main
        ) { [self] notification in
            guard let category = notification.userInfo?["category"] as? String else { return }
            Task { @MainActor in
                postingBarCategory = category
                postingBarPost = nil
                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.85))) {
                    postingBarState = .posting
                }
            }
        }

        // "Posted · View" — fires after Firestore confirms.
        // Guard: skip the navigateTo re-fire that the "View" button emits,
        // which would otherwise reset the bar and restart the dismiss timer.
        postSuccessObserver = NotificationCenter.default.addObserver(
            forName: .newPostCreated,
            object: nil,
            queue: .main
        ) { [self] notification in
            guard let userInfo = notification.userInfo,
                  let category = userInfo["category"] as? String,
                  userInfo["navigateTo"] == nil else { return }  // ignore "View" re-fires
            let post = userInfo["post"] as? Post

            Task { @MainActor in
                postingBarCategory = category
                postingBarPost = post
                withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.85))) {
                    postingBarState = .posted
                }

                // Cancel any in-flight dismiss timer before starting a new one.
                postingBarDismissTask?.cancel()
                postingBarDismissTask = Task {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.85))) {
                            postingBarState = .hidden
                        }
                    }
                }
            }
        }

        // Hide bar immediately on any failure (upload error, moderation block, etc.)
        postingFailedObserver = NotificationCenter.default.addObserver(
            forName: .postingFailed,
            object: nil,
            queue: .main
        ) { [self] _ in
            Task { @MainActor in
                postingBarDismissTask?.cancel()
                postingBarDismissTask = nil
                withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.85))) {
                    postingBarState = .hidden
                }
            }
        }
    }

    // MARK: - Feed Ready Helper

    /// Waits until the feed has posts AND a minimum display time has elapsed,
    /// so the cinematic loading screen always has enough time to animate.
    /// Minimum: 2.5 s (lets the orbital discs complete ~1 full rotation visible).
    /// Maximum: 5 s (graceful timeout on very slow connections).
    private func waitForFeedReady() async {
        let minDisplay: TimeInterval = 0.5   // Always show loading screen at least 500ms
        let maxWait: TimeInterval = 3.0
        let pollInterval: TimeInterval = 0.05
        let start = Date()

        while true {
            let elapsed = Date().timeIntervalSince(start)
            let hasPosts = FirebasePostService.shared.posts.count > 0

            // Wait for both: minimum display time AND posts available
            if hasPosts && elapsed >= minDisplay {
                return
            }

            if elapsed >= maxWait {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    // MARK: - User Search Migration (Production - Runs Silently)
    
    /// Automatically runs user search migration on first app launch (production-ready, silent)
    private func runUserSearchMigrationIfNeeded() async {
        // Check if migration has already run
        guard !UserDefaults.standard.bool(forKey: "hasRunUserSearchMigration_v1") else {
            return
        }
        
        do {
            let status = try await UserSearchMigration.shared.checkStatus()
            
            if status.needsMigration > 0 {
                try await UserSearchMigration.shared.fixAllUsers()
                UserDefaults.standard.set(true, forKey: "hasRunUserSearchMigration_v1")
            } else {
                UserDefaults.standard.set(true, forKey: "hasRunUserSearchMigration_v1")
            }
        } catch {
            // Silent — search fallback handles it
        }
    }
    
    // MARK: - Quick Action Route Handler

    /// Navigate to the destination requested by a Home Screen quick action.
    ///
    /// Called by `.onReceive(AMENQuickActionManager.shared.$pendingRoute)` which fires:
    ///   • On cold launch — as soon as mainContent appears (user is authenticated)
    ///   • On warm launch — immediately when the user selects a shortcut
    ///
    /// The function is only reachable when mainContent is displayed, which means
    /// the user is already past all auth gates and onboarding. If any required
    /// modal is already open we still switch the underlying tab so it's ready
    /// after the modal is dismissed.
    private func handleQuickActionRoute(_ route: AMENAppRoute) {
        // Always consume the route first — prevents re-firing on view re-appear
        AMENQuickActionManager.shared.consumePendingRoute()

        // Small delay so any in-progress navigation animations can settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.85))) {
                switch route {

                case .newPost:
                    // Tab 0 first so the composer opens against the feed background
                    viewModel.selectedTab = 0
                    // Slight additional delay so tab switch completes before sheet opens
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showCreatePost = true
                    }

                case .messages:
                    viewModel.selectedTab = 2

                case .search:
                    viewModel.selectedTab = 1

                case .activity:
                    viewModel.selectedTab = 4

                case .bereanAI:
                    // Berean can open from any tab — switch home first for context
                    viewModel.selectedTab = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showBereanAssistantFromMenu = true
                    }

                case .prayer:
                    // Prayer lives on the Home feed (tab 0) — switch there
                    viewModel.selectedTab = 0

                case .myProfile:
                    viewModel.selectedTab = 5
                }
            }
        }
    }

    // MARK: - Scene Phase Handler

    /// Handle app lifecycle changes for usage tracking
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            AppUsageTracker.shared.startSession()

            // ── Shabbat: re-evaluate immediately on every foreground entry ─
            // The 60-second timer handles in-app transitions; this catches:
            //   • Sat→Sun / Sun→Mon midnight crossings while backgrounded
            //   • DST spring-forward / fall-back overnight
            //   • Return from Control Center after disabling the toggle remotely
            let shabbatNow = ShabbatModeService.shared.isShabbatActiveNow()
            // P2 FIX: Only log the diagnostic event in DEBUG builds to avoid
            // duplicate console noise on every foreground entry in production.
            #if DEBUG
            ShabbatAnalytics.logStateTransition(
                enabled: ShabbatModeService.shared.isEnabled,
                isSunday: ShabbatModeService.shared.isSunday
            )
            #endif
            // LAUNCH FIX: Skip Shabbat tab redirect on the very first activation.
            // On cold launch, scenePhase fires .active before the .task block runs,
            // so the Shabbat check wins the race and opens Resources instead of Home.
            // .task owns the initial tab (sets selectedTab = 0); subsequent foreground
            // re-entries are allowed to redirect to Resources normally.
            if !hasHandledFirstActivation {
                hasHandledFirstActivation = true
                dlog("🚦 [TAB] First activation — skipping Shabbat tab redirect (tab init deferred to .task)")
            } else if shabbatNow && !isAllowedDuringChurchFocus(viewModel.selectedTab) {
                dlog("🚦 [TAB] Shabbat active on foreground — redirecting to Resources (tab 3)")
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.selectedTab = 3
                }
            }
            // ───────────────────────────────────────────────────────────────

        case .inactive:
            break // Don't end session yet, might be temporary

        case .background:
            AppUsageTracker.shared.endSession()

        @unknown default:
            break
        }
    }
    
    // MARK: - Create Post Quick Actions Overlay (iOS-Style Context Menu)
    
    private var createPostQuickActionsOverlay: some View {
        Group {
            if showCreateQuickActions {
                ZStack(alignment: .bottom) {
                    // Dimmed background with blur - tap to dismiss
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .transition(.opacity.animation(.easeOut(duration: 0.15)))
                        .onTapGesture {
                            HapticManager.impact(style: .soft)
                            withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.85))) {
                                showCreateQuickActions = false
                            }
                        }
                    
                    // Menu positioned just above the create button with smart animations
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            createQuickActionButton(
                                icon: "number",
                                title: "OpenTable",
                                delay: 0.0,
                                action: {
                                    HapticManager.impact(style: .light)
                                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.85))) {
                                        showCreateQuickActions = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        selectedPostCategory = .openTable
                                        showCreatePost = true
                                    }
                                }
                            )
                            
                            Divider()
                                .background(Color(white: 0.2))
                            
                            createQuickActionButton(
                                icon: "hands.sparkles",
                                title: "Prayer",
                                delay: 0.05,
                                action: {
                                    HapticManager.impact(style: .light)
                                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.85))) {
                                        showCreateQuickActions = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        selectedPostCategory = .prayer
                                        showCreatePost = true
                                    }
                                }
                            )
                            
                            Divider()
                                .background(Color(white: 0.2))
                            
                            createQuickActionButton(
                                icon: "quote.bubble",
                                title: "Testimony",
                                delay: 0.1,
                                action: {
                                    HapticManager.impact(style: .light)
                                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.85))) {
                                        showCreateQuickActions = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        selectedPostCategory = .testimonies
                                        showCreatePost = true
                                    }
                                }
                            )
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.white.opacity(0.5))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        
                        // Arrow pointing to create button
                        Arrow()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Arrow()
                                    .fill(Color.white.opacity(0.5))
                            )
                            .frame(width: 20, height: 10)
                            .offset(y: -1)
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    }
                    .frame(width: 170)
                    .offset(y: -105) // Position just above tab bar, fully visible
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.75, anchor: .bottom)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: 20)),
                            removal: .scale(scale: 0.9, anchor: .bottom)
                                .combined(with: .opacity)
                        )
                    )
                }
            }
        }
    }
    
    private func createQuickActionButton(icon: String, title: String, delay: Double, action: @escaping () -> Void) -> some View {
        AnimatedQuickActionButton(icon: icon, title: title, delay: delay, action: action)
    }
    
    // MARK: - Berean Quick Actions Overlay (Full Screen)
    
    private var bereanQuickActionsOverlay: some View {
        Group {
            if showBereanQuickActions {
                ZStack(alignment: .topTrailing) {
                    // Dimmed background with blur - tap to dismiss
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .transition(.opacity.animation(.easeOut(duration: 0.15)))
                        .onTapGesture {
                            HapticManager.impact(style: .soft)
                            withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.85))) {
                                showBereanQuickActions = false
                            }
                        }
                    
                    // Menu positioned below Bible icon
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            BereanQuickActionButton(
                                icon: "sparkles",
                                title: "Ask Berean",
                                delay: 0.0,
                                action: {
                                    HapticManager.impact(style: .light)
                                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.85))) {
                                        showBereanQuickActions = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        showBereanAssistantFromMenu = true
                                    }
                                }
                            )
                            
                            Divider()
                                .background(Color(white: 0.2))
                            
                            BereanQuickActionButton(
                                icon: "book.fill",
                                title: "Scripture Study",
                                delay: 0.05,
                                action: {
                                    HapticManager.impact(style: .light)
                                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.85))) {
                                        showBereanQuickActions = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        showBereanAssistantFromMenu = true
                                    }
                                }
                            )
                            
                            Divider()
                                .background(Color(white: 0.2))
                            
                            BereanQuickActionButton(
                                icon: "heart.text.square.fill",
                                title: "Daily Devotion",
                                delay: 0.1,
                                action: {
                                    HapticManager.impact(style: .light)
                                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.85))) {
                                        showBereanQuickActions = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        showBereanAssistantFromMenu = true
                                    }
                                }
                            )
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.white.opacity(0.5))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        
                        // Arrow pointing to button
                        Arrow()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Arrow()
                                    .fill(Color.white.opacity(0.5))
                            )
                            .frame(width: 20, height: 10)
                            .offset(y: -1)
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    }
                    .frame(width: 200)
                    .padding(.top, 60) // Position below status bar
                    .padding(.trailing, 16) // Align with right edge
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.75, anchor: .topTrailing)
                                .combined(with: .opacity)
                                .combined(with: .offset(x: 20, y: -10)),
                            removal: .scale(scale: 0.9, anchor: .topTrailing)
                                .combined(with: .opacity)
                        )
                    )
                }
            }
        }
    }
}

// MARK: - Animated Quick Action Button with Press Effects

struct AnimatedQuickActionButton: View {
    let icon: String
    let title: String
    let delay: Double
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var isAppeared = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(isPressed ? Color.primary.opacity(0.5) : Color.primary)
                    .frame(width: 22)
                
                Text(title)
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundStyle(isPressed ? Color.primary.opacity(0.5) : Color.primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPressed ? Color.black.opacity(0.08) : Color.clear)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .opacity(isAppeared ? 1 : 0)
            .offset(x: isAppeared ? 0 : -10)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeIn(duration: 0.08)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isPressed = false
                    }
                }
        )
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75)).delay(delay)) {
                isAppeared = true
            }
        }
    }
}

// MARK: - Arrow Shape for Context Menu

struct Arrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - 10, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + 10, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Compact Tab Bar (Smaller with Glassmorphic Design)
struct CompactTabBar: View {
    @Binding var selectedTab: Int
    @Binding var showCreatePost: Bool
    @Binding var showCreateQuickActions: Bool
    // P0-7: Use @EnvironmentObject instead of @ObservedObject for singletons
    // This prevents unnecessary view re-creation and improves memory usage
    @EnvironmentObject private var messagingService: FirebaseMessagingService
    @EnvironmentObject private var postsManager: PostsManager
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var notificationService: NotificationService
    // ✅ P0-10, P0-11, P0-12 FIX: Access BadgeCountManager as single source of truth
    @EnvironmentObject private var badgeCountManager: BadgeCountManager
    // ✅ Shabbat Mode: Access church focus manager
    @EnvironmentObject private var churchFocusManager: SundayChurchFocusManager
    @State private var previousUnreadCount: Int = 0
    @State private var badgePulse: Bool = false
    @State private var newPostsBadgePulse: Bool = false
    @State private var lastSeenPostTime: Date = Date()
    @Namespace private var pillNS

    // Tab haptic handled by AMENTabBar's .sensoryFeedback(.selection) — no duplicate needed

    // PERFORMANCE FIX: Navigation tap protection
    @State private var isNavigating = false
    @State private var lastTapTime: Date = .distantPast
    @State private var lastHomeRefreshDate: Date = .distantPast
    @State private var isHomeRefreshInFlight = false
    private let homeAutoRefreshCooldown: TimeInterval = 60

    // ✅ REAL-TIME PROFILE PHOTO UPDATE
    @State private var profilePhotoUpdateTrigger = UUID() // Force AsyncImage to reload
    
    // All tabs in order: Home, People, Messages, Resources, Notifications, Profile
    let allTabs: [(icon: String, tag: Int)] = [
        ("house.fill", 0),
        ("magnifyingglass", 1),
        ("message.fill", 2),
        ("books.vertical.fill", 3),
        ("bell.fill", 4),
        ("person.fill", 5)
    ]
    
    // ✅ P0-10, P0-11, P0-12 FIX: Use BadgeCountManager as single source of truth
    private var totalUnreadCount: Int {
        badgeCountManager.unreadMessages
    }
    
    // Computed property for new posts indicator
    private var hasNewPosts: Bool {
        guard let latestPost = postsManager.allPosts.first else { return false }
        return latestPost.createdAt > lastSeenPostTime
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {

            // ── Floating pill with all nav icons ──
            HStack(spacing: 0) {
                ForEach(Array(allTabs.enumerated()), id: \.element.tag) { _, tab in
                    tabButton(for: tab, isSelected: selectedTab == tab.tag)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(glassmorphicBackground)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 8)
            .shadow(color: .black.opacity(0.15), radius: 4,  x: 0, y: 2)

            // ── Compose button — separate glass circle ──
            createButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 5)
        .onChange(of: totalUnreadCount) { oldValue, newValue in
            // Trigger pulse animation when unread count increases
            if newValue > oldValue {
                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.5))) {
                    badgePulse = true
                }
                
                // Haptic feedback for new message
                HapticManager.notification(type: .success)
                
                // Reset pulse after animation
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    await MainActor.run {
                        withAnimation { badgePulse = false }
                    }
                }
            }
            previousUnreadCount = newValue
        }
        .onChange(of: postsManager.allPosts.count) { oldValue, newValue in
            // Trigger pulse animation when new posts are added
            if newValue > oldValue && selectedTab != 0 {
                // Only show if user is not on Home tab
                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.5))) {
                    newPostsBadgePulse = true
                }

                // Haptic feedback for new post
                HapticManager.notification(type: .success)

                // Reset pulse after animation
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    await MainActor.run {
                        withAnimation { newPostsBadgePulse = false }
                    }
                }
            }
        }
        .onAppear {
            previousUnreadCount = totalUnreadCount
            lastSeenPostTime = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("profilePhotoUpdated"))) { notification in
            // ✅ REAL-TIME UPDATE: Refresh tab bar profile photo immediately
            if let imageURL = notification.userInfo?["profileImageURL"] as? String {
                // Update UserDefaults cache
                if !imageURL.isEmpty {
                    UserDefaults.standard.set(imageURL, forKey: "currentUserProfileImageURL")
                } else {
                    UserDefaults.standard.removeObject(forKey: "currentUserProfileImageURL")
                }

                // Trigger re-render by changing UUID
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    profilePhotoUpdateTrigger = UUID()
                }

                // Success haptic
                HapticManager.impact(style: .light)
            }
        }
    }
    
    // MARK: - Glassmorphic Background

    private var glassmorphicBackground: some View {
        Capsule()
            .fill(Color(white: 0.92))
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Tab Button (Smaller Icon-Only Pill Style)
    
    @ViewBuilder
    private func tabButton(for tab: (icon: String, tag: Int), isSelected: Bool) -> some View {
        Button {
            // If already on this tab, handle same-tab re-tap (scroll to top + refresh)
            if selectedTab == tab.tag {
                if tab.tag == 0 {
                    NotificationCenter.default.post(name: .homeTabTapped, object: nil)
                    HapticManager.impact(style: .light)
                }
                return
            }

            // PERFORMANCE FIX: Debounce rapid taps (300ms window)
            let now = Date()
            guard now.timeIntervalSince(lastTapTime) > 0.3 else {
                return
            }
            lastTapTime = now
            
            // PERFORMANCE FIX: Prevent re-entrant navigation
            guard !isNavigating else {
                return
            }
            
            isNavigating = true
            
            dlog("🚦 [TAB] User tapped tab bar → selectedTab = \(tab.tag) (from \(selectedTab))")
            withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.72))) {
                selectedTab = tab.tag
            }
            
            // Auto-refresh Home feed when switching to Home tab from another tab
            if tab.tag == 0 {
                let shouldRefresh = postsManager.openTablePosts.isEmpty
                    || Date().timeIntervalSince(lastHomeRefreshDate) > homeAutoRefreshCooldown
                if shouldRefresh && !isHomeRefreshInFlight {
                    isHomeRefreshInFlight = true
                    Task {
                        await postsManager.refreshPosts()
                        await MainActor.run {
                            lastHomeRefreshDate = Date()
                            isHomeRefreshInFlight = false
                        }
                    }
                }
                // Mark posts as seen
                lastSeenPostTime = Date()
            }

            // Immediately clear badge dots when user taps into those tabs
            if tab.tag == 2 {
                badgeCountManager.clearMessages()
            }
            // Notifications is tag 4 (bell), not tag 5 (profile)
            if tab.tag == 4 {
                badgeCountManager.clearNotifications()
            }
            
            // Reset navigation guard after animation completes
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                await MainActor.run { isNavigating = false }
            }
        } label: {
            ZStack {
                // ── Sliding active pill — matchedGeometryEffect moves it between tabs ──
                if isSelected {
                    Capsule()
                        .fill(Color(white: 0.24, opacity: 0.95))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                        .matchedGeometryEffect(id: "activePill", in: pillNS)
                }

                // Icon + badge stack
                VStack(spacing: 2) {
                    ZStack(alignment: .topTrailing) {
                        // Selection circle background
                        Circle()
                            .fill(Color.white.opacity(isSelected ? 0.4 : 0))
                            .frame(width: 44, height: 44)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
                        
                        // Profile tab shows user's photo if available
                        if tab.tag == 5 {
                            profileTabContent(isSelected: isSelected)
                        } else {
                            Image(systemName: tab.icon)
                                // Icon pops to semibold + slightly larger when selected
                                .font(.system(
                                    size: isSelected ? 22 : 20,
                                    weight: isSelected ? .semibold : .regular
                                ))
                                .foregroundStyle(.primary)
                                // Scales up ahead of the pill landing (snappier spring)
                                .scaleEffect(isSelected ? 1.12 : 1.0)
                                .animation(
                                    .spring(response: 0.32, dampingFraction: 0.65),
                                    value: isSelected
                                )
                                // Native bounce fires once on selection (iOS 17+)
                                .symbolEffect(.bounce, value: isSelected)
                        }

                        // Messages unread badge
                        if tab.tag == 2 && totalUnreadCount > 0 {
                            SmartMessageBadge(unreadCount: totalUnreadCount, pulse: badgePulse)
                                .offset(x: 2, y: -2)
                        }

                        // Home new-posts dot
                        if tab.tag == 0 && hasNewPosts {
                            UnreadDot(pulse: newPostsBadgePulse)
                                .offset(x: 2, y: -2)
                        }

                        // Notifications dot
                        if tab.tag == 4 && badgeCountManager.unreadNotifications > 0 {
                            UnreadDot(pulse: false)
                                .offset(x: 2, y: -2)
                        }
                    }
                    .offset(y: isSelected ? -2 : 0)
                    .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isSelected)

                    // Gold active dot
                    Circle()
                        .fill(Color(red: 0.788, green: 0.659, blue: 0.298))
                        .frame(width: 4, height: 4)
                        .scaleEffect(isSelected ? 1.0 : 0.01)
                        .opacity(isSelected ? 1.0 : 0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.5), value: isSelected)
                }
                .frame(width: 44, height: 40)
            }
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(tabAccessibilityLabel(for: tab.tag))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func tabAccessibilityLabel(for tag: Int) -> String {
        switch tag {
        case 0: return "Home"
        case 1: return "Discover"
        case 2: return totalUnreadCount > 0 ? "Messages, \(totalUnreadCount) unread" : "Messages"
        case 3: return "Resources"
        case 4: return badgeCountManager.unreadNotifications > 0 ? "Notifications, \(badgeCountManager.unreadNotifications) unread" : "Notifications"
        case 5: return "Profile"
        default: return "Tab"
        }
    }

    // MARK: - Profile Tab Content
    
    @ViewBuilder
    private func profileTabContent(isSelected: Bool) -> some View {
        Group {
            // Try to get profile image URL from UserDefaults cache first (faster)
            let cachedImageURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
            
            if let photoURL = cachedImageURL ?? userService.currentUser?.profileImageURL,
               !photoURL.isEmpty,
               let url = URL(string: photoURL) {
                // User has profile photo - show it
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 26, height: 26)  // Smaller profile photo for compact tab bar
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        isSelected ? Color.primary : Color.secondary.opacity(0.5),
                                        lineWidth: isSelected ? 1.5 : 1
                                    )
                            )
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                            .symbolEffect(.bounce, value: isSelected)
                    case .failure(_):
                        // Fallback to icon if image fails to load
                        Image(systemName: "person.fill")
                            .font(.systemScaled(18, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .symbolEffect(.bounce, value: isSelected)
                    case .empty:
                        // Show loading placeholder
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 26, height: 26)  // Smaller placeholder
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.6)
                            )
                    @unknown default:
                        Image(systemName: "person.fill")
                            .font(.systemScaled(20, weight: isSelected ? .semibold : .medium))  // Smaller icon
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                }
                .id(profilePhotoUpdateTrigger) // ✅ Force reload when UUID changes
            } else {
                // No profile photo - show default icon
                Image(systemName: "person.fill")
                    .font(.systemScaled(20, weight: isSelected ? .semibold : .medium))  // Smaller icon
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .symbolEffect(.bounce, value: isSelected)
            }
        }
        .task {
            // Ensure user data is loaded
            if userService.currentUser == nil {
                await userService.fetchCurrentUser()
            }
        }
    }
    
    // MARK: - Create Button (Smaller with Glassmorphic Touch)
    
    @State private var createButtonScale: CGFloat = 1.0
    
    @State private var isLongPressing = false
    
    private var createButton: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.92))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                .frame(width: 54, height: 54)

            Image(systemName: "plus")
                .font(.systemScaled(22, weight: .semibold))
                .foregroundStyle(.primary)
                // Rotates 45° → 0° on first appear — subtle "unfurl"
                .transition(.opacity)
        }
        .scaleEffect(createButtonScale)
        .brightness(isLongPressing ? 0.06 : 0)
        .animation(.spring(response: 0.22, dampingFraction: 0.55), value: createButtonScale)
        .contentShape(Circle())
        .accessibilityLabel("Create post")
        .accessibilityHint("Tap to compose a new post. Long press for quick options.")
        .onTapGesture {
            // Regular tap - open create post immediately
            
            // PERFORMANCE FIX: Debounce rapid taps
            let now = Date()
            guard now.timeIntervalSince(lastTapTime) > 0.3 else { return }
            lastTapTime = now
            
            // PERFORMANCE FIX: Prevent duplicate sheet presentation
            guard !showCreatePost else { return }
            
            // ✅ Shabbat Mode: Block create post during church focus window
            guard !SundayChurchFocusManager.shared.shouldGateFeature() else {
                // Show Shabbat Mode gate
                NotificationCenter.default.post(name: .showShabbatModeGate, object: nil)
                HapticManager.notification(type: .warning)
                return
            }
            
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.6))) {
                showCreatePost = true
            }
            HapticManager.impact(style: .light)
        }
        .simultaneousGesture(
            // Long press - show quick actions menu (optional feature)
            LongPressGesture(minimumDuration: 0.5)
                .onChanged { _ in
                    if !isLongPressing {
                        isLongPressing = true
                        HapticManager.impact(style: .light)
                        
                        withAnimation(Motion.adaptive(.spring(response: 0.15, dampingFraction: 0.8))) {
                            createButtonScale = 0.9
                        }
                    }
                }
                .onEnded { _ in
                    HapticManager.notification(type: .success)
                    
                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.8))) {
                        createButtonScale = 1.0
                        showCreateQuickActions = true
                    }
                    
                    // Reset after a delay
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        await MainActor.run { isLongPressing = false }
                    }
                }
        )
    }
}

// MARK: - Unread Badge Component

struct UnreadDot: View {
    let pulse: Bool
    
    var body: some View {
        ZStack {
            // Pulse ring (only when pulse is active)
            if pulse {
                Circle()
                    .fill(Color.red.opacity(0.25))
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulse ? 1.8 : 1.0)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 0.6), value: pulse)
            }
            
            // White border ring — separates dot from icon underneath (Instagram-style)
            Circle()
                .fill(Color(UIColor.systemBackground))
                .frame(width: 9, height: 9)
            
            // Main dot
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .scaleEffect(pulse ? 1.15 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pulse)
        }
        // CRITICAL FIX: Color-only indicator. The dot communicates state visually via
        // color alone. The parent tab button already exposes the count through
        // tabAccessibilityLabel (e.g. "Notifications, 3 unread"), so this dot is purely
        // decorative — hide it from the AX tree to avoid redundant/confusing announcements.
        .accessibilityHidden(true)
    }
}

// MARK: - Smart Message Badge (Shows count then transitions to dot)

struct SmartMessageBadge: View {
    let unreadCount: Int
    let pulse: Bool
    @State private var showCount: Bool = true
    
    var body: some View {
        ZStack {
            // Pulse ring (only when pulse active)
            if pulse {
                Circle()
                    .fill(Color.red.opacity(0.25))
                    .frame(width: showCount ? 22 : 14, height: showCount ? 22 : 14)
                    .scaleEffect(pulse ? 1.8 : 1.0)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 0.6), value: pulse)
            }
            
            if showCount && unreadCount > 0 {
                // Count badge with white border
                ZStack {
                    // White border ring
                    Capsule()
                        .fill(Color(UIColor.systemBackground))
                        .frame(width: max(19, CGFloat(unreadCount > 9 ? 23 : 19)), height: 19)
                    
                    Capsule()
                        .fill(Color.red)
                        .frame(width: max(16, CGFloat(unreadCount > 9 ? 20 : 16)), height: 16)
                    
                    Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                        .font(.systemScaled(10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(pulse ? 1.15 : 1.0)
                .transition(.scale.combined(with: .opacity))
            } else {
                // Simple dot matching UnreadDot style
                ZStack {
                    Circle()
                        .fill(Color(UIColor.systemBackground))
                        .frame(width: 9, height: 9)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                }
                .scaleEffect(pulse ? 1.15 : 1.0)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .task(id: unreadCount) {
            // Show count for 2 seconds on appear or whenever unreadCount increases,
            // then transition back to dot. Using .task(id:) automatically cancels
            // the previous sleep when unreadCount changes.
            guard unreadCount > 0 else { return }
            showCount = true
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
                showCount = false
            }
        }
    }
}

// MARK: - Feed Mode

enum LegacyFeedMode: String, CaseIterable {
    case everyone = "Everyone"
    case following = "Following"
    case quiet = "Quiet Mode"

    var icon: String {
        switch self {
        case .everyone:  return "globe"
        case .following: return "person.2"
        case .quiet:     return "bell.slash"
        }
    }
}

struct HomeView: View {
    private struct NotificationPostSheetRoute: Identifiable, Equatable {
        let postId: String
        let scrollToCommentId: String?

        var id: String {
            "\(postId)::\(scrollToCommentId ?? "")"
        }
    }

    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var notificationService = NotificationService.shared
    @ObservedObject private var postsManager = PostsManager.shared  // ✅ FIXED: Use @ObservedObject for singletons
    @State private var isCategoriesExpanded = false
    @State private var selectedFeedMode: LegacyFeedMode = .everyone
    @State private var showFeedModeDropdown = false
    @State private var showCommunitiesSheet = false
    @State private var showBereanAssistant = false
    @Binding var showBereanQuickActions: Bool
    @Binding var showBereanAssistantFromMenu: Bool
    @Binding var selectedPostCategory: CreatePostView.PostCategory
    // Deep link navigation: post opened from a push notification tap
    @State private var notificationPostSheetRoute: NotificationPostSheetRoute?
    #if DEBUG
    @State private var showAdminCleanup = false
    @State private var showMigrationPanel = false  // NEW: Migration panel
    @State private var tapCount = 0
    #endif
    
    // MARK: - Scroll Detection for Dynamic UI (OPTIMIZED)
    @State private var scrollOffset: CGFloat = 0
    @State private var lastScrollOffset: CGFloat = 0
    @State private var showToolbar = true
    @Environment(\.tabBarVisible) private var tabBarVisible  // ✅ Access tab bar visibility
    @State private var lastScrollTime: Date = Date()
    
    // Hysteresis thresholds — hide quickly on downward scroll, restore on upward
    private let scrollUpThreshold: CGFloat = 8   // Restore bar after modest upward scroll
    private let scrollDownThreshold: CGFloat = 18 // Hide bar after 18pts downward movement
    
    // Helper function for adaptive spacing
    private func adaptiveSpacing(for width: CGFloat) -> CGFloat {
        switch width {
        case ..<350: return 4  // Tight spacing on small screens
        case 350..<400: return 6  // Medium spacing
        default: return 8  // Standard spacing
        }
    }
    
    // MARK: - Scroll Handling (P0 FIX: Single source with hysteresis)
    
    private func handleScroll(offset: CGFloat) {
        // ✅ PERFORMANCE FIX: Increased debounce threshold to reduce lag
        // Only process changes > 8pts to reduce excessive UI updates during scroll
        guard abs(offset - scrollOffset) > 8 else { return }
        
        _ = scrollOffset
        scrollOffset = offset
        let delta = offset - lastScrollOffset
        // Always update lastScrollOffset for correct next-delta calculation
        lastScrollOffset = offset
        
        // ✅ INTELLIGENT BANNER: Calculate scroll velocity (points per second)
        let now = Date()
        let timeDelta = now.timeIntervalSince(lastScrollTime)
        if timeDelta > 0.016 { // ~60fps throttle
            let velocity = abs(delta) / CGFloat(timeDelta)
            lastScrollTime = now
            // Notify CaughtUpService about scroll (only for OpenTable feed)
            if viewModel.selectedCategory == "#OPENTABLE" || viewModel.selectedCategory == "" {
                CaughtUpService.shared.onScroll(velocity: velocity, isDragging: true)
            }
        }
        
        // At top (within 20pts of zero) - always show UI, no animation fighting
        if offset > -20 {
            AMENTabBarScrollBridge.shared.expand()
            if !showToolbar || !tabBarVisible.wrappedValue {
                // Single smooth animation without bounce
                withAnimation(.easeOut(duration: 0.2)) {
                    showToolbar = true
                    tabBarVisible.wrappedValue = true
                }
            }
            return
        }
        
        // Scrolling up significantly - show UI
        if delta > scrollUpThreshold {
            AMENTabBarScrollBridge.shared.expand()
            if !showToolbar || !tabBarVisible.wrappedValue {
                withAnimation(.easeOut(duration: 0.2)) {
                    showToolbar = true
                    tabBarVisible.wrappedValue = true
                }
            }
        }
        // Scrolling down past threshold — hide bar quickly for more screen real estate
        else if delta < -scrollDownThreshold && offset < -50 {
            AMENTabBarScrollBridge.shared.minimize()
            if showToolbar || tabBarVisible.wrappedValue {
                withAnimation(.easeOut(duration: 0.15)) {
                    showToolbar = false
                    tabBarVisible.wrappedValue = false
                }
            }
        }
        
        // Auto-collapse category pills when scrolling down
        if delta < -60 && offset < -100 {
            if isCategoriesExpanded {
                withAnimation(.easeOut(duration: 0.15)) {
                    isCategoriesExpanded = false
                }
            }
        }
    }
    
    var body: some View {
        // ✅ REMOVED: FeedDrawerGestureWrapper swipe gesture for Communities
        NavigationStack {
            mainScrollContent
                .navigationTitle("AMEN")
                .navigationBarTitleDisplayMode(.inline)
                // Auto-hide header when scrolling down
                .toolbar(showToolbar ? .visible : .hidden, for: .navigationBar)
                .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // ✅ MERGED: Combined feed mode + communities menu button
                    Menu {
                        Section("Feed Mode") {
                            ForEach(LegacyFeedMode.allCases, id: \.self) { mode in
                                Button {
                                    HapticManager.impact(style: .light)
                                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                        selectedFeedMode = mode
                                    }
                                } label: {
                                    Label(mode.rawValue, systemImage: mode.icon)
                                    if selectedFeedMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Section("Communities") {
                            Button {
                                HapticManager.impact(style: .light)
                                showCommunitiesSheet = true
                            } label: {
                                Label("Browse Communities", systemImage: "person.3.fill")
                            }
                        }
                    } label: {
                        Image(systemName: "person.3.fill")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 22, height: 22)
                            .padding(8)
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            }
                    }
                    .opacity(showToolbar ? 1 : 0)
                }
                    ToolbarItem(placement: .topBarTrailing) {
                        // Search Button - hides with toolbar
                        SearchButton(isVisible: showToolbar, action: {
                            showBereanAssistant = true
                        }, showQuickActions: $showBereanQuickActions)
                    }
                    
                    ToolbarItem(placement: .principal) {
                        Button {
                            // Tap AMEN title - toggle categories expand/collapse
                            withAnimation(Motion.adaptive(.spring(response: 0.15, dampingFraction: 0.8))) {
                                isCategoriesExpanded.toggle()
                            }
                            HapticManager.impact(style: .light)

                            #if DEBUG
                            // Secret admin access: 5 rapid taps (manual counter — no onTapGesture(count:)
                            // which delays every single tap while the system waits to resolve the sequence)
                            tapCount += 1
                            if tapCount >= 5 {
                                tapCount = 0
                                showAdminCleanup = true
                                HapticManager.notification(type: .success)
                            } else {
                                // Reset counter after 1.2 s of inactivity
                                Task {
                                    let snapshot = tapCount
                                    try? await Task.sleep(for: .seconds(1.2))
                                    if tapCount == snapshot { tapCount = 0 }
                                }
                            }
                            #endif
                        } label: {
                            HStack(spacing: 4) {
                                Text("amen")
                                    .font(AMENFont.bold(24))
                                    .foregroundStyle(.primary)
                                Image(systemName: "chevron.up")
                                    .font(.systemScaled(9, weight: .medium))
                                    .foregroundStyle(.primary.opacity(0.6))
                                    .rotationEffect(.degrees(isCategoriesExpanded ? 180 : 0))
                            }
                        }
                    }
                    
                    // People and Notifications removed from toolbar - now in bottom tab bar
                }
                // People and Notifications now accessed via bottom tab bar
                .environment(\.toolbarVisible, $showToolbar)
                .fullScreenCover(isPresented: $showBereanAssistant) {
                    BereanChatView()
                }
                .sheet(isPresented: $showCommunitiesSheet) {
                    FeedCommunitiesSheet(
                        selectedMode: $selectedFeedMode,
                        onDismiss: { showCommunitiesSheet = false }
                    )
                }
                .onChange(of: showBereanAssistantFromMenu) { _, newValue in
                    if newValue {
                        showBereanAssistant = true
                        showBereanAssistantFromMenu = false // Reset
                    }
                }
                // CaughtUpCard redirect actions: switch to Prayer feed or open Berean
                // when the user is caught up and wants to do something purposeful.
                .onReceive(NotificationCenter.default.publisher(for: .caughtUpOpenPrayer)) { _ in
                    withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.82))) {
                        viewModel.selectedCategory = "Prayer"
                        selectedFeedMode = .everyone
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .caughtUpOpenBerean)) { _ in
                    showBereanAssistant = true
                }
                #if DEBUG
                .sheet(isPresented: $showAdminCleanup) {
                    AdminCleanupView()
                }
                .sheet(isPresented: $showMigrationPanel) {
                    UserSearchMigrationView()
                }
                #endif
                // Notification listener started in mainContent.onAppear (not here,
                // so it fires regardless of which tab opens first)
                // Feed mode dropdown overlay
                .overlay(alignment: .topLeading) {
                    if showFeedModeDropdown {
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .contentShape(Rectangle())
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                        showFeedModeDropdown = false
                                    }
                                }
                            FeedModeDropdownMenu(
                                selectedMode: $selectedFeedMode,
                                isVisible: $showFeedModeDropdown
                            )
                            .padding(.top, 50)
                            .padding(.leading, 8)
                        }
                    }
                }
            }
        // Deep link: open a specific post when a push notification is tapped
        .onReceive(NotificationCenter.default.publisher(for: .openPostFromNotification)) { notification in
            if let postId = notification.userInfo?["postId"] as? String {
                let scrollToCommentId = notification.userInfo?["scrollToCommentId"] as? String
                notificationPostSheetRoute = NotificationPostSheetRoute(
                    postId: postId,
                    scrollToCommentId: scrollToCommentId
                )
            }
        }
        .sheet(item: $notificationPostSheetRoute) { route in
            NavigationStack {
                NotificationPostDetailView(postId: route.postId)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: - Computed Properties to help type checker
    
    private var mainScrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 1)
                        .id("top")
                        .onAppear {
                            dlog("📜 [SCROLL DEBUG] ScrollView content appeared - should be scrollable")
                        }
                    
                    // Expandable Category Pills
                    if isCategoriesExpanded {
                        categoryPillsView
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                    }

                    // Feed mode indicator strip — visible when not in Everyone mode
                    if selectedFeedMode != .everyone {
                        FeedModeIndicatorStrip(mode: selectedFeedMode) {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                selectedFeedMode = .everyone
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedFeedMode)
                    }

                    // Subtle collaboration suggestions (only in OpenTable / Everyone mode)
                    if viewModel.selectedCategory == "#OPENTABLE" && selectedFeedMode == .everyone {
                        SubtleCollaborationSuggestionsView()
                            .padding(.top, 8)
                    }
                    
                    // Dynamic Content Based on Selected Category
                    selectedCategoryView
                }
                .padding(.bottom, 100)
            }
            .contentShape(Rectangle())
            .onAppear {
                dlog("📜 [SCROLL DEBUG] Main ScrollView appeared")
            }
            // ✅ DISABLED: Excessive scroll gesture logging causes memory pressure and app kills
            // .simultaneousGesture(
            //     DragGesture(minimumDistance: 0)
            //         .onChanged { value in
            //             dlog("👆 [SCROLL DEBUG] Scroll gesture detected - translation: \(value.translation)")
            //         }
            // )
            // Native scroll offset tracking — does not replace SwiftUI's internal UIScrollViewDelegate
            // ✅ PERFORMANCE FIX: Throttle scroll updates to reduce lag
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, newOffset in
                handleScroll(offset: -newOffset)
            }
            // P0 FIX: Removed .onTapGesture(count: 2) - it was blocking ScrollView scrolling
            // .onTapGesture(count: 2) {
            //     withAnimation(.easeOut(duration: 0.18)) {
            //         proxy.scrollTo("top", anchor: .center)
            //         showToolbar = true
            //         tabBarVisible.wrappedValue = true
            //     }
            //     HapticManager.impact(style: .light)
            // }
            .refreshable {
                await refreshCurrentCategory()
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("top", anchor: .top)
                }
            }
            // Tab bar home button re-tap: scroll to top and refresh feed
            .onReceive(NotificationCenter.default.publisher(for: .homeTabTapped)) { _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("top", anchor: .top)
                    showToolbar = true
                    tabBarVisible.wrappedValue = true
                }
                Task {
                    await refreshCurrentCategory()
                }
            }
        }
    }
    
    // P0 FIX: Removed duplicate handleScrollOffset - now using single handleScroll function
    
    // MARK: - Refresh Handler
    
    /// Refresh the currently selected category
    private func refreshCurrentCategory() async {
        HapticManager.impact(style: .light)
        
        // ✅ INTELLIGENT BANNER: Notify about refresh start (only for OpenTable)
        if viewModel.selectedCategory == "#OPENTABLE" || viewModel.selectedCategory == "" {
            CaughtUpService.shared.onRefreshStarted()
        }
        
        switch viewModel.selectedCategory {
        case "Prayer":
            await PostsManager.shared.fetchFilteredPosts(for: .prayer, filter: "all")
        case "Testimonies":
            await PostsManager.shared.fetchFilteredPosts(for: .testimonies, filter: "all")
        default:
            await PostsManager.shared.refreshPosts()
        }
        
        // ✅ INTELLIGENT BANNER: Notify about refresh finish (only for OpenTable)
        if viewModel.selectedCategory == "#OPENTABLE" || viewModel.selectedCategory == "" {
            let posts = PostsManager.shared.openTablePosts
            CaughtUpService.shared.onRefreshFinished(posts: posts)
        }
        
        NotificationCenter.default.post(name: .feedDidRefresh,
                                        object: nil,
                                        userInfo: ["category": viewModel.selectedCategory])
        HapticManager.notification(type: .success)
    }
    
    private var categoryPillsView: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            
            HStack(spacing: 12) {
                ForEach(viewModel.categories, id: \.self) { category in
                    CategoryPill(
                        title: category,
                        isSelected: viewModel.selectedCategory == category
                    ) {
                        viewModel.selectCategory(category)
                        withAnimation(Motion.adaptive(.spring(response: 0.15, dampingFraction: 0.8))) {
                            isCategoriesExpanded = false
                        }
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity).animation(.spring(response: 0.15, dampingFraction: 0.8)),
            removal: .move(edge: .top).combined(with: .opacity).animation(.spring(response: 0.15, dampingFraction: 0.8))
        ))
    }
    
    private var selectedCategoryView: some View {
        // P0 FIX: Block hit testing on hidden views to prevent scroll blocking.
        // All views stay mounted (prevents listener restart) but hidden views
        // have .allowsHitTesting(false) so they don't intercept gestures.
        ZStack(alignment: .top) {
            // Everyone mode — category-based views
            let isOpenTable = selectedFeedMode == .everyone && (viewModel.selectedCategory == "#OPENTABLE" || viewModel.selectedCategory == "")
            let isTestimonies = selectedFeedMode == .everyone && viewModel.selectedCategory == "Testimonies"
            let isPrayer = selectedFeedMode == .everyone && viewModel.selectedCategory == "Prayer"
            let isFollowing = selectedFeedMode == .following
            let isQuiet = selectedFeedMode == .quiet

            OpenTableView(selectedPostCategory: $selectedPostCategory)
                .opacity(isOpenTable ? 1 : 0)
                .zIndex(isOpenTable ? 1 : 0)
                .allowsHitTesting(isOpenTable)
                .frame(height: isOpenTable ? nil : 0, alignment: .top)
                .clipped()
            TestimoniesView()
                .opacity(isTestimonies ? 1 : 0)
                .zIndex(isTestimonies ? 1 : 0)
                .allowsHitTesting(isTestimonies)
                .frame(height: isTestimonies ? nil : 0, alignment: .top)
                .clipped()
            PrayerView()
                .opacity(isPrayer ? 1 : 0)
                .zIndex(isPrayer ? 1 : 0)
                .allowsHitTesting(isPrayer)
                .frame(height: isPrayer ? nil : 0, alignment: .top)
                .clipped()
            // Following feed mode — posts from accounts the current user follows
            FollowingFeedView()
                .opacity(isFollowing ? 1 : 0)
                .zIndex(isFollowing ? 1 : 0)
                .allowsHitTesting(isFollowing)
                .frame(height: isFollowing ? nil : 0, alignment: .top)
                .clipped()
            // Quiet feed mode — chronological, no algorithmic boost
            QuietFeedView()
                .opacity(isQuiet ? 1 : 0)
                .zIndex(isQuiet ? 1 : 0)
                .allowsHitTesting(isQuiet)
                .frame(height: isQuiet ? nil : 0, alignment: .top)
                .clipped()
        }
        .animation(.easeInOut(duration: 0.15), value: viewModel.selectedCategory)
        .animation(.easeInOut(duration: 0.15), value: selectedFeedMode)
    }
}

// MARK: - Following Feed View

/// Shows only posts from accounts the current user follows.
/// Filters PostsManager.allPosts client-side using FollowService.followingIds.
struct FollowingFeedView: View {
    @ObservedObject private var postsManager = PostsManager.shared
    @ObservedObject private var followService = FollowService.shared

    private var followingPosts: [Post] {
        let ids = followService.following
        guard !ids.isEmpty else { return [] }
        return postsManager.allPosts
            .filter { ids.contains($0.authorId) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if followingPosts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.2")
                        .font(.systemScaled(48))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("Follow people to see their posts here")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 80)
            } else {
                // P0 FIX: Changed from LazyVStack to VStack - LazyVStack doesn't work inside another ScrollView.
                // The parent ScrollView in ContentView handles the scrolling.
                VStack(spacing: 0) {
                    ForEach(followingPosts) { post in
                        PostCard(post: post)

                        if AMENFeatureFlags.shared.postDividerEnabled {
                            FeedPostDivider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Quiet Feed View

/// Chronological feed with no algorithmic boost, ads, or trending injections.
/// Shows a max of ~40 most recent posts.
struct QuietFeedView: View {
    @ObservedObject private var postsManager = PostsManager.shared

    private var quietPosts: [Post] {
        Array(postsManager.allPosts
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(40))
    }

    var body: some View {
        Group {
            if quietPosts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "moon.stars")
                        .font(.systemScaled(48))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("Nothing here yet.\nPosts will appear as they're shared.")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 80)
            } else {
                // P0 FIX: Changed from LazyVStack to VStack - LazyVStack doesn't work inside another ScrollView.
                // The parent ScrollView in ContentView handles the scrolling.
                VStack(spacing: 0) {
                    ForEach(quietPosts) { post in
                        PostCard(post: post)

                        if AMENFeatureFlags.shared.postDividerEnabled {
                            FeedPostDivider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Feed Mode Nav Button

struct FeedModeNavButton: View {
    @Binding var selectedMode: LegacyFeedMode
    @Binding var showDropdown: Bool

    var body: some View {
        Button {
            HapticManager.impact(style: .light)
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                showDropdown.toggle()
            }
        } label: {
            Image(systemName: selectedMode == .everyone ? "person.2" : selectedMode.icon)
                .font(.systemScaled(15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
                .padding(8)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                }
        }
    }
}

// MARK: - Feed Mode Dropdown Menu

struct FeedModeDropdownMenu: View {
    @Binding var selectedMode: LegacyFeedMode
    @Binding var isVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(LegacyFeedMode.allCases, id: \.self) { mode in
                Button {
                    HapticManager.impact(style: .light)
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        selectedMode = mode
                        isVisible = false
                    }
                } label: {
                    HStack(spacing: 12) {
                        // Icon with background for selected state
                        ZStack {
                            if selectedMode == mode {
                                Circle()
                                    .fill(Color.primary.opacity(0.1))
                                    .frame(width: 28, height: 28)
                            }
                            Image(systemName: mode.icon)
                                .font(.systemScaled(14, weight: .medium))
                                .foregroundStyle(selectedMode == mode ? .primary : .secondary)
                        }
                        .frame(width: 28)

                        Text(mode.rawValue)
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(selectedMode == mode ? .primary : .secondary)

                        Spacer()

                        if selectedMode == mode {
                            Image(systemName: "checkmark")
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedMode == mode ? Color.primary.opacity(0.04) : Color.clear)
                    )
                }
                .buttonStyle(.plain)

                if mode != LegacyFeedMode.allCases.last {
                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)
                }
            }
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                )
        )
        .frame(width: 200)
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity),
            removal:   .scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity)
        ))
    }
}

// MARK: - Feed Mode Indicator Strip

struct FeedModeIndicatorStrip: View {
    let mode: LegacyFeedMode
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: mode.icon)
                .font(.systemScaled(12, weight: .medium))
            Text(mode.rawValue)
                .font(AMENFont.semiBold(13))
            Spacer()
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.systemScaled(16))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Search Button with Auto-Hide

struct SearchButton: View {
    let isVisible: Bool
    let action: () -> Void
    @Binding var showQuickActions: Bool
    
    @State private var isPressed = false
    @State private var quickActionButtonScale: CGFloat = 1.0
    @State private var showFirstTimeLongPressHint = false
    @State private var isLongPressing = false
    @AppStorage("hasSeenBereanLongPressHint") private var hasSeenLongPressHint = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                // Berean AI icon - AMEN app logo
                Image("amen-logo")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .padding(8)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    }
                
                // First-time hint badge
                if showFirstTimeLongPressHint {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.6, blue: 0.4), Color(red: 0.6, green: 0.5, blue: 0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 8, height: 8)
                        .offset(x: 12, y: -12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .scaleEffect(quickActionButtonScale)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: quickActionButtonScale)
            .onTapGesture {
                // Regular tap - open Berean AI immediately
                HapticManager.impact(style: .light)
                action()
            }
            .simultaneousGesture(
                // Long press - show quick actions menu (optional feature)
                LongPressGesture(minimumDuration: 0.5)
                    .onChanged { _ in
                        if !isLongPressing {
                            isLongPressing = true
                            HapticManager.impact(style: .light)
                            
                            withAnimation(Motion.adaptive(.spring(response: 0.15, dampingFraction: 0.8))) {
                                quickActionButtonScale = 0.9
                            }
                        }
                    }
                    .onEnded { _ in
                        HapticManager.notification(type: .success)
                        
                        withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.85))) {
                            quickActionButtonScale = 1.0
                            showQuickActions = true
                            showFirstTimeLongPressHint = false
                        }
                        
                        // Mark hint as seen
                        if !hasSeenLongPressHint {
                            hasSeenLongPressHint = true
                        }
                        
                        // Reset after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isLongPressing = false
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isLongPressing {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
            .onAppear {
                // Show long press hint for first-time users
                if !hasSeenLongPressHint {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
                            showFirstTimeLongPressHint = true
                        }
                        
                        // Auto-hide hint after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showFirstTimeLongPressHint = false
                            }
                        }
                    }
                }
            }
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.8)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isVisible)
            .reportBereanButtonFrame()
        }
    }
}

// MARK: - Berean Quick Action Button (iOS-Style with Smart Animations)
struct BereanQuickActionButton: View {
    let icon: String
    let title: String
    let delay: Double
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var isAppeared = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(isPressed ? Color.primary.opacity(0.5) : Color.primary)
                    .frame(width: 22)
                
                Text(title)
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundStyle(isPressed ? Color.primary.opacity(0.5) : Color.primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPressed ? Color.black.opacity(0.08) : Color.clear)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .opacity(isAppeared ? 1 : 0)
            .offset(x: isAppeared ? 0 : 10)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeIn(duration: 0.08)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isPressed = false
                    }
                }
        )
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75)).delay(delay)) {
                isAppeared = true
            }
        }
    }
}

// MARK: - Quick Action Row
struct QuickActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: LinearGradient
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon with gradient
                ZStack {
                    Circle()
                        .fill(gradient.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.systemScaled(18, weight: .medium))
                        .foregroundStyle(gradient)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.systemScaled(12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isPressed ? Color.black.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// ScrollView delegate handler for detecting scroll direction
class ScrollViewDelegateHandler: NSObject, UIScrollViewDelegate {
    private var lastContentOffset: CGFloat = 0
    private var lastUpdateTime: Date = Date.distantPast
    private let onScroll: (CGFloat) -> Void
    private let throttleInterval: TimeInterval = 0.1 // 100ms throttle
    
    init(onScroll: @escaping (CGFloat) -> Void) {
        self.onScroll = onScroll
        super.init()
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let currentOffset = scrollView.contentOffset.y
        let delta = currentOffset - lastContentOffset
        
        // P0 FIX: Always show UI when at top (within bounce threshold)
        // This ensures header/tab bar appear when user scrolls to top
        if currentOffset <= 0 {
            DispatchQueue.main.async {
                self.onScroll(-999) // Special signal: at top, show all UI
            }
            lastContentOffset = currentOffset
            return
        }
        
        // Throttle: Only update if enough time has passed since last update
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= throttleInterval else {
            return
        }
        
        // Only trigger if scrolled more than 5 points
        if abs(delta) > 5 {
            lastContentOffset = currentOffset
            lastUpdateTime = now
            
            // Defer state updates to avoid "Modifying state during view update" error
            DispatchQueue.main.async {
                self.onScroll(delta)
            }
        }
    }
}

// View modifier to attach scroll delegate
struct ScrollViewDelegateModifier: ViewModifier {
    let onScroll: (CGFloat) -> Void
    @State private var delegate: ScrollViewDelegateHandler?
    
    func body(content: Content) -> some View {
        content
            .background(
                ScrollViewDelegateAttacher(delegate: $delegate, onScroll: onScroll)
            )
    }
}

// UIViewRepresentable to find and attach to UIScrollView
struct ScrollViewDelegateAttacher: UIViewRepresentable {
    @Binding var delegate: ScrollViewDelegateHandler?
    let onScroll: (CGFloat) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        
        DispatchQueue.main.async {
            if let scrollView = view.findScrollView() {
                let handler = ScrollViewDelegateHandler(onScroll: onScroll)
                scrollView.delegate = handler
                delegate = handler
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
    }
}

extension UIView {
    func findScrollView() -> UIScrollView? {
        if let scrollView = self as? UIScrollView {
            return scrollView
        }
        
        for subview in superview?.subviews ?? [] {
            if let scrollView = subview as? UIScrollView {
                return scrollView
            }
        }
        
        return superview?.findScrollView()
    }
}

extension View {
    func onScrollViewScroll(_ onScroll: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollViewDelegateModifier(onScroll: onScroll))
    }
}

struct CategoryPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            HapticManager.impact(style: .light)
            action()
        }) {
            Text(title)
                .font(.custom(isSelected ? "OpenSans-Bold" : "OpenSans-SemiBold", size: adaptiveFontSize))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, adaptivePadding)
                .padding(.vertical, adaptiveVerticalPadding)
                .lineLimit(1)
                .background(glassmorphicBackground)
                .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeIn(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
    
    // MARK: - Glassmorphic Background
    
    @ViewBuilder
    private var glassmorphicBackground: some View {
        ZStack {
            if isSelected {
                selectedGlassBackground
            } else {
                unselectedGlassBackground
            }
        }
    }
    
    // Selected state: Frosted glass with inner glow, rim light, and shadow
    private var selectedGlassBackground: some View {
        ZStack {
            // Base frosted glass layer
            Capsule()
                .fill(.ultraThinMaterial)
            
            // Stronger inner glow effect (white from top) - MORE VISIBLE
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.6),
                            Color.white.opacity(0.25),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Enhanced rim light (more prominent highlight on edges)
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.8),
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
            
            // Stronger outer border (black/gray) - MORE VISIBLE
            Capsule()
                .strokeBorder(
                    Color.black.opacity(0.35),
                    lineWidth: 1.5
                )
                .padding(0.5)
        }
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        .shadow(color: .white.opacity(0.2), radius: 6, x: 0, y: -2)
    }
    
    // Unselected state: Subtle glass with minimal styling
    private var unselectedGlassBackground: some View {
        ZStack {
            // Base frosted glass layer (more transparent)
            Capsule()
                .fill(.ultraThinMaterial.opacity(0.5))
            
            // Very subtle gradient
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Subtle border
            Capsule()
                .strokeBorder(
                    Color.black.opacity(0.1),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Adaptive Sizing (Smaller)
    
    private var adaptiveFontSize: CGFloat {
        // Reduced font size for smaller pills
        switch horizontalSizeClass {
        case .compact:
            return 12  // Smaller on iPhone portrait
        default:
            return 13  // Smaller on iPad/landscape
        }
    }
    
    private var adaptivePadding: CGFloat {
        // Reduced horizontal padding for compact design
        switch horizontalSizeClass {
        case .compact:
            return 12
        default:
            return 14
        }
    }
    
    private var adaptiveVerticalPadding: CGFloat {
        // Reduced vertical padding for smaller pills
        return 8
    }
}

struct CommunityCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let backgroundColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(20))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(title)
                    .font(AMENFont.bold(13))
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.black.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 100)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeIn(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Smart Community Card (Compact Liquid Glass Design)

struct SmartCommunityCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let backgroundColor: Color
    let accentColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            HapticManager.impact(style: .light)
            action()
        }) {
            HStack(spacing: 10) {
                // Compact icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .symbolEffect(.bounce, value: isPressed)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AMENFont.bold(13))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(AMENFont.regular(10))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.systemScaled(10, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    // Liquid Glass effect
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                    
                    // Subtle tint overlay
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    iconColor.opacity(0.08),
                                    iconColor.opacity(0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Border
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: iconColor.opacity(0.1), radius: 8, y: 2)
            .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.smooth(duration: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

struct TrendingCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let backgroundColor: Color
    
    @State private var isPressed = false
    @State private var showDetails = false
    
    var body: some View {
        Button {
            showDetails = true
            HapticManager.impact(style: .light)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.systemScaled(24))
                    .foregroundStyle(.primary)
                    .frame(height: 40)
                
                Text(title)
                    .font(AMENFont.bold(12))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 100, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.94 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeIn(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
        .sheet(isPresented: $showDetails) {
            TrendingTopicDetailView(title: title, icon: icon)
        }
    }
}

// MARK: - Trending Topic Detail View

struct TrendingTopicDetailView: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    let icon: String
    
    // Mock data based on topic
    private var topicContent: (description: String, stats: [(String, String)], relatedTopics: [String], resources: [(String, String)]) {
        switch title {
        case "AI & Faith":
            return (
                "Explore how artificial intelligence intersects with Christian faith, ethics, and ministry. Join discussions on using AI responsibly while maintaining biblical values.",
                [
                    ("Active Discussions", "234"),
                    ("Community Members", "1.2K"),
                    ("Resources Shared", "89")
                ],
                ["Tech Ethics", "Digital Ministry", "AI in Bible Study", "Church Innovation"],
                [
                    ("AI Ethics Framework", "Christian guide to AI"),
                    ("Faith & Technology Podcast", "Weekly discussions"),
                    ("AI Ministry Tools", "Practical applications")
                ]
            )
        case "Tech Ethics":
            return (
                "Navigate the ethical implications of technology through a Christian worldview. Discuss privacy, digital rights, and moral responsibility in the tech age.",
                [
                    ("Active Topics", "156"),
                    ("Members", "890"),
                    ("Weekly Posts", "67")
                ],
                ["Data Privacy", "Social Media Ethics", "Digital Stewardship", "Tech Responsibility"],
                [
                    ("Christian Tech Ethics Guide", "Comprehensive resource"),
                    ("Digital Boundaries", "Setting healthy limits"),
                    ("Tech Sabbath Ideas", "Unplug with purpose")
                ]
            )
        case "Startups":
            return (
                "Connect with Christian entrepreneurs building faith-driven businesses. Share ideas, get feedback, and find co-founders who share your values.",
                [
                    ("Active Startups", "78"),
                    ("Founders", "234"),
                    ("Success Stories", "45")
                ],
                ["Faith-Based Business", "Kingdom Entrepreneurship", "Startup Funding", "Mission-Driven Companies"],
                [
                    ("Startup Prayer Group", "Weekly support"),
                    ("Christian Investor Network", "Faith-based funding"),
                    ("Business with Purpose", "Course & mentorship")
                ]
            )
        case "Scripture":
            return (
                "Deep dive into God's Word with community-driven Bible study. Share insights, ask questions, and grow together in understanding.",
                [
                    ("Daily Readers", "567"),
                    ("Study Groups", "89"),
                    ("Verses Discussed", "1.5K")
                ],
                ["Bible Study Methods", "Hermeneutics", "Original Languages", "Devotional Reading"],
                [
                    ("Daily Reading Plan", "1-year Bible plan"),
                    ("Study Tools", "Concordance & lexicons"),
                    ("Verse Memorization", "Scripture memory app")
                ]
            )
        default:
            return (
                "Explore this topic with the community. Share insights, ask questions, and learn together in faith.",
                [
                    ("Active Members", "100+"),
                    ("Discussions", "50+"),
                    ("Resources", "25+")
                ],
                ["Related Topics"],
                [("Community Resources", "Learn more")]
            )
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.05))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: icon)
                                .font(.systemScaled(40))
                                .foregroundStyle(.primary)
                        }
                        
                        Text(title)
                            .font(AMENFont.bold(28))
                            .foregroundStyle(.primary)
                        
                        Text(topicContent.description)
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.black.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    
                    // Stats
                    HStack(spacing: 12) {
                        ForEach(topicContent.stats, id: \.0) { stat in
                            VStack(spacing: 6) {
                                Text(stat.1)
                                    .font(AMENFont.bold(22))
                                    .foregroundStyle(.primary)
                                
                                Text(stat.0)
                                    .font(AMENFont.regular(12))
                                    .foregroundStyle(.black.opacity(0.6))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button {
                            // Join discussion
                        } label: {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                Text("Join Discussion")
                                    .font(AMENFont.bold(16))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.black)
                            .cornerRadius(14)
                        }
                        
                        HStack(spacing: 12) {
                            Button {
                                // Follow topic
                            } label: {
                                HStack {
                                    Image(systemName: "bell.fill")
                                    Text("Follow")
                                        .font(AMENFont.bold(14))
                                }
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white)
                                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                                )
                            }
                            
                            Button {
                                // Share
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                        .font(AMENFont.bold(14))
                                }
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white)
                                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Related Topics
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Related Topics")
                            .font(AMENFont.bold(18))
                            .foregroundStyle(.primary)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(topicContent.relatedTopics, id: \.self) { topic in
                                    Text(topic)
                                        .font(AMENFont.semiBold(13))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(.white)
                                                .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Resources
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Helpful Resources")
                            .font(AMENFont.bold(18))
                            .foregroundStyle(.primary)
                            .padding(.horizontal)
                        
                        VStack(spacing: 10) {
                            ForEach(topicContent.resources, id: \.0) { resource in
                                Button {
                                    // Open resource
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(resource.0)
                                                .font(AMENFont.bold(14))
                                                .foregroundStyle(.primary)
                                            
                                            Text(resource.1)
                                                .font(AMENFont.regular(12))
                                                .foregroundStyle(.black.opacity(0.6))
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.systemScaled(12, weight: .semibold))
                                            .foregroundStyle(.black.opacity(0.3))
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.white)
                                            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 24)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(28))
                            .foregroundStyle(.black.opacity(0.3))
                    }
                }
            }
        }
    }
}

// Old PostCard removed - now using the enhanced version from PostCard.swift

// MARK: - Reaction Button Component

struct ReactionButton: View {
    let icon: String
    let count: Int?
    let isActive: Bool
    let activeColor: Color
    let namespace: Namespace.ID
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(isActive ? .black : .black.opacity(0.5))
                
                if let count = count {
                    Text("\(count)")
                        .font(AMENFont.semiBold(11))
                        .foregroundStyle(isActive ? .black : .black.opacity(0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Color.white : Color.black.opacity(0.05))
                    .shadow(color: isActive ? .black.opacity(0.15) : .clear, radius: 8, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? Color.black.opacity(0.2) : Color.black.opacity(0.1), lineWidth: isActive ? 1.5 : 1)
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeIn(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Format Button Component

struct FormatButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(isActive ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isActive ? Color.blue : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Emoji Picker View

struct EmojiPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var commentText: String
    
    private let emojis = [
        "😊", "😂", "❤️", "🙏", "🔥", "✨", "🎉", "👏",
        "🙌", "💪", "⭐️", "💯", "✅", "🎯", "💡", "📖",
        "🕊️", "✝️", "🌟", "💖", "🌈", "☀️", "🌸", "🦋",
        "🎵", "📿", "⛪️", "🙇", "💫", "🌺", "🌻", "🌷"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 8), spacing: 12) {
                    ForEach(emojis, id: \.self) { emoji in
                        Button {
                            commentText += emoji
                            HapticManager.impact(style: .light)
                            dismiss()
                        } label: {
                            Text(emoji)
                                .font(.systemScaled(32))
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color.gray.opacity(0.1))
                                )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Add Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Comment Card

struct CommentCard: View {
    let comment: TestimonyComment
    @State private var hasAmened = false
    @State private var localAmenCount: Int
    
    init(comment: TestimonyComment) {
        self.comment = comment
        _localAmenCount = State(initialValue: comment.amenCount)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Circle()
                .fill(comment.avatarColor.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(comment.authorInitials)
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(comment.avatarColor)
                )
            
            VStack(alignment: .leading, spacing: 6) {
                // Author and time
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.primary)
                    
                    Text("•")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                    
                    Text(comment.timeAgo)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
                
                // Comment content
                Text(comment.content)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Comment actions
                HStack(spacing: 16) {
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                            hasAmened.toggle()
                            localAmenCount += hasAmened ? 1 : -1
                            
                            HapticManager.impact(style: .light)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "hands.sparkles.fill")
                                .font(.systemScaled(11))
                            if localAmenCount > 0 {
                                Text("\(localAmenCount)")
                                    .font(AMENFont.semiBold(12))
                            }
                        }
                        .foregroundStyle(hasAmened ? Color(red: 1.0, green: 0.84, blue: 0.0) : .secondary)
                    }
                    
                    Button {
                        // Reply action
                    } label: {
                        Text("Reply")
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

// MARK: - Testimony Comment Model

struct TestimonyComment: Identifiable {
    let id = UUID()
    let authorName: String
    let authorInitials: String
    let timeAgo: String
    let content: String
    let amenCount: Int
    let avatarColor: Color
    var replies: [TestimonyComment] = []
    var gifURL: String?
    var isFormatted: Bool = false
}

// MARK: - Full Comments View

struct FullCommentsView: View {
    @Environment(\.dismiss) private var dismiss
    let comments: [TestimonyComment]
    
    @State private var allComments: [TestimonyComment]
    @State private var commentText = ""
    @State private var replyingTo: TestimonyComment?
    @State private var showGIFPicker = false
    @State private var selectedGIF: String?
    @State private var isBold = false
    @State private var isItalic = false
    @FocusState private var isCommentFocused: Bool
    
    init(comments: [TestimonyComment]) {
        self.comments = comments
        _allComments = State(initialValue: comments)
    }
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Comments List
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(allComments) { comment in
                            CommentThreadCard(
                                comment: comment,
                                onReply: { replyTo in
                                    replyingTo = replyTo
                                    isCommentFocused = true
                                },
                                onAddReply: { parent, reply in
                                    addReply(to: parent, reply: reply)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
                
                Spacer()
            }
            
            // Composer at bottom
            VStack {
                Spacer()
                composerView
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.05))
                        )
                }
                
                Spacer()
                
                Text("Comments")
                    .font(AMENFont.bold(18))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Placeholder for symmetry
                Circle()
                    .fill(Color.clear)
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Composer (Liquid Glass Style)
    
    private var composerView: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)
            
            VStack(spacing: 12) {
                // Reply indicator
                if let replyingTo = replyingTo {
                    HStack {
                        Text("Replying to \(replyingTo.authorName)")
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                self.replyingTo = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.systemScaled(14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Liquid Glass Input Container
                HStack(alignment: .center, spacing: 12) {
                    // Avatar
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text("ME")
                                .font(AMENFont.semiBold(11))
                                .foregroundStyle(.white)
                        )
                    
                    // Glass-style text field
                    HStack(spacing: 8) {
                        TextField("Add a comment...", text: $commentText, axis: .vertical)
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.primary)
                            .lineLimit(1...4)
                            .focused($isCommentFocused)
                            .padding(.leading, 16)
                            .padding(.trailing, 8)
                            .padding(.vertical, 12)
                        
                        // Photo/GIF button inside text field
                        if isCommentFocused && commentText.isEmpty {
                            Button {
                                showGIFPicker.toggle()
                                isCommentFocused = false
                            } label: {
                                Image(systemName: "photo")
                                    .font(.systemScaled(18))
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 12)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            // Glass effect background
                            RoundedRectangle(cornerRadius: 24)
                                .fill(.ultraThinMaterial)
                            
                            // Subtle border
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                    )
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                    
                    // Animated Liquid Glass Post Button
                    if !commentText.isEmpty {
                        LiquidGlassPostButton(
                            isEnabled: !commentText.isEmpty,
                            isPublishing: false,
                            isScheduled: false
                        ) {
                            submitComment()
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // Minimal formatting toolbar (only when focused and typing)
                if isCommentFocused && !commentText.isEmpty {
                    minimalToolbarView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(
            ZStack {
                Color(.systemBackground)
                
                // Subtle top shadow for depth
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.02),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 20)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        )
        .sheet(isPresented: $showGIFPicker) {
            GIFPickerView(selectedGIF: $selectedGIF)
        }
    }
    
    // MARK: - Minimal Toolbar
    
    private var minimalToolbarView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Bold
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.7))) {
                        isBold.toggle()
                    }
                } label: {
                    Text("B")
                        .font(AMENFont.bold(14))
                        .foregroundStyle(isBold ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(isBold ? Color.black : Color.gray.opacity(0.1))
                        )
                }
                
                // Italic
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.7))) {
                        isItalic.toggle()
                    }
                } label: {
                    Text("I")
                        .font(.custom("OpenSans-Italic", size: 14))
                        .foregroundStyle(isItalic ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(isItalic ? Color.black : Color.gray.opacity(0.1))
                        )
                }
                
                Divider()
                    .frame(height: 24)
                
                // Emoji
                Button {
                    // Show emoji picker
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.systemScaled(14))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.gray.opacity(0.1))
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
    
    // MARK: - Style Toolbar (Kept for compatibility but simplified)
    
    private var styleToolbarView: some View {
        HStack(spacing: 8) {
            // Bold
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.7))) {
                    isBold.toggle()
                }
            } label: {
                Text("B")
                    .font(AMENFont.bold(14))
                    .foregroundStyle(isBold ? .white : .primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isBold ? Color.black : Color.gray.opacity(0.1))
                    )
            }
            
            // Italic
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.7))) {
                    isItalic.toggle()
                }
            } label: {
                Text("I")
                    .font(.custom("OpenSans-Italic", size: 14))
                    .foregroundStyle(isItalic ? .white : .primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isItalic ? Color.black : Color.gray.opacity(0.1))
                    )
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Actions
    
    private func submitComment() {
        guard !commentText.isEmpty else { return }
        
        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))) {
            let newComment = TestimonyComment(
                authorName: "You",
                authorInitials: "ME",
                timeAgo: "Just now",
                content: commentText,
                amenCount: 0,
                avatarColor: .blue,
                replies: [],
                gifURL: selectedGIF,
                isFormatted: isBold || isItalic
            )
            
            if let replyingTo = replyingTo {
                addReply(to: replyingTo, reply: newComment)
            } else {
                allComments.insert(newComment, at: 0)
            }
            
            commentText = ""
            selectedGIF = nil
            self.replyingTo = nil
            isCommentFocused = false
            
            HapticManager.notification(type: .success)
        }
    }
    
    private func addReply(to parent: TestimonyComment, reply: TestimonyComment) {
        if let index = allComments.firstIndex(where: { $0.id == parent.id }) {
            allComments[index].replies.append(reply)
        }
    }
}

// MARK: - Comment Thread Card

struct CommentThreadCard: View {
    let comment: TestimonyComment
    let onReply: (TestimonyComment) -> Void
    let onAddReply: (TestimonyComment, TestimonyComment) -> Void
    
    @State private var hasAmened = false
    @State private var localAmenCount: Int
    @State private var showReplies = true
    
    init(comment: TestimonyComment, onReply: @escaping (TestimonyComment) -> Void, onAddReply: @escaping (TestimonyComment, TestimonyComment) -> Void) {
        self.comment = comment
        self.onReply = onReply
        self.onAddReply = onAddReply
        _localAmenCount = State(initialValue: comment.amenCount)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main comment
            commentContentView(for: comment, isReply: false)
            
            // Replies
            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))) {
                            showReplies.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showReplies ? "chevron.down" : "chevron.right")
                                .font(.systemScaled(12, weight: .semibold))
                            Text("\(comment.replies.count) \(comment.replies.count == 1 ? "reply" : "replies")")
                                .font(AMENFont.semiBold(13))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.leading, 48)
                        .padding(.vertical, 8)
                    }
                    
                    if showReplies {
                        ForEach(comment.replies) { reply in
                            commentContentView(for: reply, isReply: true)
                                .padding(.leading, 48)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func commentContentView(for comment: TestimonyComment, isReply: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar
                Circle()
                    .fill(comment.avatarColor.opacity(0.2))
                    .frame(width: isReply ? 32 : 40, height: isReply ? 32 : 40)
                    .overlay(
                        Text(comment.authorInitials)
                            .font(.custom("OpenSans-SemiBold", size: isReply ? 11 : 13))
                            .foregroundStyle(comment.avatarColor)
                    )
                
                VStack(alignment: .leading, spacing: 8) {
                    // Header
                    HStack(spacing: 6) {
                        Text(comment.authorName)
                            .font(.custom("OpenSans-SemiBold", size: isReply ? 13 : 14))
                            .foregroundStyle(.primary)
                        
                        Text("•")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                        
                        Text(comment.timeAgo)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Content
                    if comment.isFormatted {
                        Text(comment.content)
                            .font(.custom("OpenSans-Bold", size: isReply ? 13 : 14))
                            .foregroundStyle(.primary)
                    } else {
                        Text(comment.content)
                            .font(.custom("OpenSans-Regular", size: isReply ? 13 : 14))
                            .foregroundStyle(.primary)
                    }
                    
                    // GIF if present
                    if let gifURL = comment.gifURL {
                        CachedAsyncImage(url: URL(string: gifURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 250)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 150)
                        }
                    }
                    
                    // Actions
                    HStack(spacing: 20) {
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                                hasAmened.toggle()
                                localAmenCount += hasAmened ? 1 : -1
                                
                                HapticManager.impact(style: .light)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "hands.sparkles.fill")
                                    .font(.systemScaled(13))
                                if localAmenCount > 0 {
                                    Text("\(localAmenCount)")
                                        .font(AMENFont.semiBold(13))
                                }
                            }
                            .foregroundStyle(hasAmened ? Color(red: 1.0, green: 0.84, blue: 0.0) : .secondary)
                        }
                        
                        Button {
                            onReply(comment)
                            HapticManager.impact(style: .light)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.systemScaled(12))
                                Text("Reply")
                                    .font(AMENFont.semiBold(13))
                            }
                            .foregroundStyle(.secondary)
                        }
                        
                        Menu {
                            Button(role: .destructive) {
                                // Report action
                            } label: {
                                Label("Report", systemImage: "exclamationmark.triangle")
                            }
                            
                            Button {
                                // Share action
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.systemScaled(14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
            }
        }
        .padding(isReply ? 12 : 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
}

// MARK: - GIF Picker View

struct GIFPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedGIF: String?
    
    @State private var searchText = ""
    
    // Sample GIF URLs (in production, you'd use a GIF API like Giphy or Tenor)
    private let sampleGIFs = [
        "https://media.giphy.com/media/26u4cqiYI30juCOGY/giphy.gif",
        "https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.gif",
        "https://media.giphy.com/media/l0HlBO7eyXzSZkJri/giphy.gif",
        "https://media.giphy.com/media/26FLgGTPUDH6UGAbm/giphy.gif",
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search GIFs", text: $searchText)
                        .font(AMENFont.regular(16))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // GIF Grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ], spacing: 8) {
                        ForEach(sampleGIFs, id: \.self) { gifURL in
                            Button {
                                selectedGIF = gifURL
                                dismiss()
                                
                                HapticManager.impact(style: .light)
                            } label: {
                                CachedAsyncImage(url: URL(string: gifURL)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 150)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle("Choose GIF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Testimony Category Model

struct TestimonyCategory: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let backgroundColor: Color
    
    // Equatable conformance - compare by title for logical equality
    static func == (lhs: TestimonyCategory, rhs: TestimonyCategory) -> Bool {
        lhs.title == rhs.title
    }
    
    static let healing = TestimonyCategory(
        icon: "heart.fill",
        color: .pink,
        title: "Healing",
        subtitle: "32 Stories",
        backgroundColor: Color(red: 1.0, green: 0.95, blue: 0.97)
    )
    
    static let career = TestimonyCategory(
        icon: "briefcase.fill",
        color: .green,
        title: "Career",
        subtitle: "45 Stories",
        backgroundColor: Color(red: 0.92, green: 0.99, blue: 0.96)
    )
    
    static let relationship = TestimonyCategory(
        icon: "heart.circle.fill",
        color: .red,
        title: "Relationships",
        subtitle: "28 Stories",
        backgroundColor: Color(red: 1.0, green: 0.93, blue: 0.93)
    )
    
    static let financial = TestimonyCategory(
        icon: "dollarsign.circle.fill",
        color: .orange,
        title: "Financial",
        subtitle: "38 Stories",
        backgroundColor: Color(red: 1.0, green: 0.97, blue: 0.90)
    )
    
    static let spiritual = TestimonyCategory(
        icon: "sparkles",
        color: .purple,
        title: "Spiritual Growth",
        subtitle: "52 Stories",
        backgroundColor: Color(red: 0.96, green: 0.94, blue: 1.0)
    )
    
    static let family = TestimonyCategory(
        icon: "house.fill",
        color: .blue,
        title: "Family",
        subtitle: "41 Stories",
        backgroundColor: Color(red: 0.93, green: 0.95, blue: 1.0)
    )
}

// MARK: - Follow Button

struct FollowButton: View {
    @Binding var isFollowing: Bool
    @State private var isPressed = false
    
    var body: some View {
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                isFollowing.toggle()
                
                HapticManager.impact(style: isFollowing ? .medium : .light)
            }
        } label: {
            buttonContent
                .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeIn(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
    
    private var buttonContent: some View {
        HStack(spacing: 4) {
            if !isFollowing {
                Image(systemName: "plus")
                    .font(.systemScaled(10, weight: .bold))
            }
            Text(isFollowing ? "Following" : "Follow")
                .font(AMENFont.bold(12))
        }
        .foregroundStyle(isFollowing ? Color.secondary : Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(buttonBackground)
    }
    
    private var buttonBackground: some View {
        Capsule()
            .fill(isFollowing ? Color.clear : Color.black)
            .overlay(
                Capsule()
                    .stroke(isFollowing ? Color.secondary.opacity(0.3) : Color.clear, lineWidth: 1)
            )
    }
}

// MARK: - Category Views

// Environment key for toolbar visibility
private struct ToolbarVisibleKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(true)
}

extension EnvironmentValues {
    var toolbarVisible: Binding<Bool> {
        get { self[ToolbarVisibleKey.self] }
        set { self[ToolbarVisibleKey.self] = newValue }
    }
}

/// PreferenceKey for detecting scroll position in the feed LazyVStack
private struct FeedScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct OpenTableView: View {
    @ObservedObject private var postsManager = PostsManager.shared
    @ObservedObject private var feedAlgorithm = HomeFeedAlgorithm.shared
    @ObservedObject private var scrollBudget = ScrollBudgetManager.shared
    @ObservedObject private var feedSession = FeedSessionManager.shared
    @ObservedObject private var caughtUpService = CaughtUpService.shared
    @ObservedObject private var firebasePostService = FirebasePostService.shared
    @ObservedObject private var prefsService = AMENUserPreferencesService.shared
    @State private var showingOlderPosts = false   // true after user taps "View older posts"
    @State private var isRefreshing = false
    @State private var personalizedPosts: [Post] = []
    @State private var hasPersonalized = false // Track if personalization has run
    @State private var show50Banner = false
    @State private var show80Suggestion = false
    @State private var showSoftStop = false
    @State private var showLocked = false
    @State private var softStopExtensions = 0
    @State private var showHeader = true
    @State private var showSessionStopScreen = false
    @State private var sessionCountingEnabled = false  // Delay counting until initial render is done
    @State private var initiallyVisiblePostIds = Set<UUID>()  // Posts visible before first scroll — not counted
    @State private var userHasScrolled = false  // True after user scrolls past initial batch
    @State private var initialScrollY: CGFloat? = nil  // Y position captured at session start for scroll detection
    @State private var isInitialLoad = true  // shows skeleton until first posts arrive

    // MARK: - Composer
    @State private var showCreatePost = false
    @Binding var selectedPostCategory: CreatePostView.PostCategory

    // MARK: - Pagination State
    @State private var visiblePostCount = 20 // Start with 20 posts
    @State private var isLoadingMore = false

    // Phase 4: Cancel in-flight ranking when new posts arrive to avoid stale reorder jank.
    @State private var personalizationTask: Task<Void, Never>?

    // Network error state
    @ObservedObject private var networkMonitor = AMENNetworkMonitor.shared
    @State private var showOfflineBanner = false

    @Environment(\.tabBarVisible) private var tabBarVisible
    
    var body: some View {
        ZStack(alignment: .top) {
            // Nudge banners pinned to the top of the feed (above all content)
            VStack(spacing: 8) {
                RapidRefreshNudgeBanner(isVisible: $caughtUpService.showRapidRefreshNudge)
                DeepScrollNudgeBanner(
                    isVisible: $caughtUpService.showDeepScrollNudge,
                    onDismiss: { caughtUpService.dismissDeepScrollNudge() }
                )
            }
            .padding(.top, 56)
            .zIndex(10)

            VStack(alignment: .leading, spacing: 20) {
            // Header Section (cleaned up - removed grey icon and divider)
                if showHeader {
                    VStack(alignment: .leading, spacing: 4) {
                        
                        HStack {
                            Text("#OPENTABLE")
                                .font(AMENFont.bold(24))
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            // Refresh indicator
                            if isRefreshing {
                                AMENLoadingIndicator(dotSize: 7, spacing: 6, bounceHeight: 8)
                            }
                        }
                        
                        Text("Gather. Share. Grow.")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Daily Verse Banner — show optimistically while prefs load (both default to true).
                // Only hide after load if the user has explicitly turned it off.
                if !prefsService.isLoaded || (prefsService.preferences.widgetsEnabled && prefsService.preferences.dailyVerseWidgetEnabled) {
                    DailyVerseBanner()
                        .padding(.horizontal)
                        .transition(.opacity.animation(.easeIn(duration: 0.2)))
                        .onAppear {
                            dlog("📊 Daily Verse Banner displayed: widgetsEnabled=\(prefsService.preferences.widgetsEnabled), dailyVerseWidgetEnabled=\(prefsService.preferences.dailyVerseWidgetEnabled)")
                        }
                }

                // Feed Composer Row
                FeedComposerRow { showCreatePost = true }
                    .padding(.horizontal)
                    .padding(.top, 4)

                // Feed Section - Dynamic posts from PostsManager (Trending section removed)
                // P0 FIX: Changed from LazyVStack to VStack - LazyVStack doesn't work inside another ScrollView.
                // The parent ScrollView in ContentView handles the scrolling.
                VStack(spacing: 0) {
                    let allPosts = hasPersonalized && !personalizedPosts.isEmpty ? personalizedPosts : postsManager.openTablePosts
                    let displayPosts = Array(allPosts.prefix(visiblePostCount))

                    // Skeleton loader during initial data fetch (before first posts arrive)
                    if isInitialLoad && allPosts.isEmpty {
                        PostListSkeletonView(count: 3)
                    } else {
                    // P0 FIX: Use .id (UUID) instead of .firestoreId for stable ForEach identity
                    // firestoreId can change from UUID fallback to real Firebase ID, causing cell rebuilds
                    ForEach(Array(displayPosts.enumerated()), id: \.element.id) { index, post in
                        feedPostItem(post: post, index: index, displayPosts: displayPosts)

                        // "Suggested for you" rail — injected after the 3rd post, non-intrusive
                        if index == 2 {
                            FeedPostDivider()
                            OpenTableSuggestedRailView()
                                .background(Color(.systemBackground))
                                .padding(.vertical, 8)
                                .clipped()
                            FeedPostDivider()
                        }
                    }

                    // Loading indicator for pagination
                    if isLoadingMore || firebasePostService.isLoadingMore {
                        HStack {
                            Spacer()
                            AMENLoadingIndicator(dotSize: 7, spacing: 6, bounceHeight: 8)
                                .padding(.vertical, 20)
                            Spacer()
                        }
                    }

                    // Caught-up card: shown when all 72-hour posts have been seen
                    if !isInitialLoad && caughtUpService.isCaughtUp && !showingOlderPosts {
                        CaughtUpCard {
                            showingOlderPosts = true
                            caughtUpService.dismissCaughtUp()
                        }
                    }

                    // Offline banner — shown when network drops and feed is empty
                    if showOfflineBanner && allPosts.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "wifi.slash")
                                .font(.systemScaled(14, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("You're offline. Pull down to retry when connected.")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Show empty state only after initial load completes
                    if !isInitialLoad && allPosts.isEmpty && !isRefreshing {
                        EmptyFeedView()
                    }
                    } // end else (skeleton)
                }
                // PostCard handles its own internal horizontal padding — no outer padding needed.
                // Detect scroll: track LazyVStack Y position in global space.
                // When it moves meaningfully, the user has actively scrolled.
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: FeedScrollOffsetKey.self, value: geo.frame(in: .global).minY)
                    }
                )
            }
            .frame(maxWidth: .infinity)
            .onPreferenceChange(FeedScrollOffsetKey.self) { newY in
                guard sessionCountingEnabled, !userHasScrolled else { return }
                // initialScrollY is captured after the first preference fires
                if initialScrollY == nil {
                    initialScrollY = newY
                } else if let origin = initialScrollY, abs(newY - origin) > 50 {
                    // User has scrolled more than 50pts from initial position
                    userHasScrolled = true
                }
            }
        .task {
            // ✅ FIX: Removed duplicate listener - already started in AMENAPPApp.swift:237
            // FirebasePostService.shared.startListening(category: .openTable)

            // Load user interests once
            if !hasPersonalized {
                feedAlgorithm.loadInterests()
                personalizeFeeds()
                hasPersonalized = true
            }

            // If posts already cached (re-appear), dismiss skeleton immediately
            if !postsManager.openTablePosts.isEmpty {
                isInitialLoad = false
            } else {
                // Safety timeout: if no posts arrive within 4 seconds (new user, truly
                // empty feed, slow connection), drop the skeleton so the empty state shows.
                // The fetch continues in the background — pull-to-refresh still works.
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if isInitialLoad {
                    withAnimation(.easeOut(duration: 0.25)) { isInitialLoad = false }
                }
            }
        }
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            withAnimation(.easeOut(duration: 0.25)) {
                showOfflineBanner = !isConnected
            }
        }
        .onAppear {
            // Start scroll budget tracking
            scrollBudget.startScrollSession(inSection: "OpenTable")
            // Start a fresh finite session when feed appears
            feedSession.startNewSession()
            sessionCountingEnabled = false
            userHasScrolled = false
            initiallyVisiblePostIds = []
            initialScrollY = nil
            showingOlderPosts = false
            // Allow initial render to complete, then enable counting
            // Cards only count once userHasScrolled is also true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                sessionCountingEnabled = true
            }
            // Reset seen-post session and reload Firestore seed
            caughtUpService.resetSession()
            
            // ✅ INTELLIGENT BANNER: Start new feed session with current posts
            let allPosts = hasPersonalized && !personalizedPosts.isEmpty ? personalizedPosts : postsManager.openTablePosts
            caughtUpService.startNewFeedSession(posts: allPosts)
        }
        .onDisappear {
            // Don't stop the listener - keep it active for real-time updates
            
            // End scroll budget tracking
            scrollBudget.endScrollSession()

            // Phase 5: Cancel any in-flight personalization task to prevent
            // state mutation after the view leaves the hierarchy.
            personalizationTask?.cancel()
            personalizationTask = nil
        }
        .fullScreenCover(isPresented: $showSessionStopScreen) {
            FeedSessionStopScreen(
                onContinue: {
                    // User deliberately chose to continue — session extended
                    showSessionStopScreen = false
                    // Re-arm counting: reset scroll tracking so initial-render posts aren't re-counted
                    sessionCountingEnabled = false
                    userHasScrolled = false
                    initiallyVisiblePostIds = []
                    initialScrollY = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        sessionCountingEnabled = true
                    }
                },
                onClose: {
                    // User chose to close/reflect — dismiss the feed context
                    showSessionStopScreen = false
                }
            )
        }
        .onChange(of: postsManager.openTablePosts.count) { oldValue, newValue in
            let posts = postsManager.openTablePosts
            if !posts.isEmpty { isInitialLoad = false }
            
            // ✅ INTELLIGENT BANNER: Detect new posts inserted at top
            if oldValue != newValue && newValue > oldValue {
                // New posts were added - figure out which ones
                let newPostCount = newValue - oldValue
                let newPosts = Array(posts.prefix(newPostCount))
                if !newPosts.isEmpty {
                    caughtUpService.onNewPostsInserted(newPosts)
                }
            }
            
            // Only re-personalize if there are new posts
            if oldValue != newValue {
                personalizeFeeds()
            }
            // Update the 72-hour window for caught-up detection
            let cutoff = Date().addingTimeInterval(-72 * 3600)
            let windowIds = Set(posts.compactMap { post -> String? in
                guard post.createdAt > cutoff else { return nil }
                return post.firestoreId
            })
            if !windowIds.isEmpty {
                caughtUpService.setCurrentWindow(postIds: windowIds)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.newPostCreated)) { notification in
            // P1-1 FIX: Optimistic UI update for instant feedback
            guard let userInfo = notification.userInfo,
                  let post = userInfo["post"] as? Post,
                  let isOptimistic = userInfo["isOptimistic"] as? Bool,
                  isOptimistic else {
                return
            }
            
            // Insert at top of appropriate feed based on category
            switch post.category {
            case .openTable:
                if !postsManager.openTablePosts.contains(where: { $0.id == post.id }) {
                    postsManager.openTablePosts.insert(post, at: 0)
                }
            case .testimonies:
                if !postsManager.testimoniesPosts.contains(where: { $0.id == post.id }) {
                    postsManager.testimoniesPosts.insert(post, at: 0)
                }
            case .prayer:
                if !postsManager.prayerPosts.contains(where: { $0.id == post.id }) {
                    postsManager.prayerPosts.insert(post, at: 0)
                }
            case .tip, .funFact:
                if !postsManager.allPosts.contains(where: { $0.id == post.id }) {
                    postsManager.allPosts.insert(post, at: 0)
                }
            }
            
            // Haptic feedback for instant confirmation
            HapticManager.notification(type: .success)
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrollBudget50Reached)) { _ in
            show50Banner = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrollBudget80Reached)) { _ in
            show80Suggestion = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrollBudgetSoftStopReached)) { notification in
            softStopExtensions = notification.userInfo?["extensionsRemaining"] as? Int ?? 0
            showSoftStop = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrollBudgetLocked)) { _ in
            showLocked = true
        }
            
            // 50% usage banner (top overlay)
            if show50Banner {
                ScrollBudget50Banner()
            }
        }
        .sheet(isPresented: $show80Suggestion) {
            ScrollBudget80Suggestion()
        }
        .sheet(isPresented: $showSoftStop) {
            ScrollBudgetSoftStopView(extensionsRemaining: softStopExtensions)
        }
        .fullScreenCover(isPresented: $showLocked) {
            ScrollBudgetLockedView()
        }
        .sheet(isPresented: $showCreatePost) {
            CreatePostView(initialCategory: selectedPostCategory)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Helper to check if post belongs to current user
    
    private func isCurrentUserPost(_ post: Post) -> Bool {
        // Get current user ID from Firebase Auth
        guard let currentUserId = FirebaseManager.shared.currentUser?.uid else {
            return false
        }
        // Compare with post's authorId
        return post.authorId == currentUserId
    }
    
    // MARK: - Feed Post Item Helper
    
    @ViewBuilder
    private func feedPostItem(post: Post, index: Int, displayPosts: [Post]) -> some View {
        PostCard(
            post: post,
            isUserPost: isCurrentUserPost(post)
        )
        .feedItemAppear(id: post.id, delay: min(Double(index) * 0.04, 0.20))
        .if(index == 0) { view in
            view.reportPostCardFrame()
        }
        .onAppear {
            feedAlgorithm.recordInteraction(with: post, type: .view)
            
            if sessionCountingEnabled {
                if !userHasScrolled {
                    initiallyVisiblePostIds.insert(post.id)
                } else if !initiallyVisiblePostIds.contains(post.id) {
                    feedSession.recordCardSeen()
                    if feedSession.isSessionComplete {
                        showSessionStopScreen = true
                    }
                }
            }
            
            if index >= displayPosts.count - 3 && !isLoadingMore {
                loadMorePosts()
            }
        }
        .trackPostVisibility(postId: post.firestoreId) { seenId in
            caughtUpService.markSeen(postId: seenId)
        }
        .trackPostVisibilityForBanner(postId: post.firestoreId) { postId, visibility, dwell in
            caughtUpService.onPostVisibilityChanged(postID: postId, visibility: visibility, dwell: dwell)
        }

        // Threads-style post divider (System 14)
        if AMENFeatureFlags.shared.postDividerEnabled {
            FeedPostDivider()
        }
    }
    
    // MARK: - Personalization
    
    /// Apply smart algorithm to personalize feed.
    /// Tries Cloud Run server-side ranking first (3-second timeout);
    /// falls back to on-device HomeFeedAlgorithm if unavailable.
    private func personalizeFeeds() {
        guard !postsManager.openTablePosts.isEmpty else {
            personalizedPosts = []
            return
        }

        // Phase 4: Cancel any in-flight ranking so a rapid post-count change
        // doesn't produce two competing ranked arrays that cause scroll-jump.
        personalizationTask?.cancel()
        personalizationTask = nil

        // Capture values on main actor before detaching
        let followingIds = FollowService.shared.following
        let posts = postsManager.openTablePosts
        let interests = feedAlgorithm.userInterests
        let capturedCardsServed = feedSession.cardsSeenThisSession
        let capturedSessionCap = feedSession.sessionCap

        personalizationTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return }

            // 1. Try Cloud Run (fast path — returns nil on timeout / no URL configured)
            let sessionResult: FeedAPIService.RankResult? = await FeedAPIService.shared.rankPosts(
                posts,
                interests: interests,
                followingIds: followingIds,
                sessionCardsServed: capturedCardsServed,
                sessionCap: capturedSessionCap
            )

            guard !Task.isCancelled else { return }

            // Apply server-side session exhaustion signal
            if let result = sessionResult, result.sessionExhausted {
                await MainActor.run { feedSession.isSessionComplete = true }
            }

            // 2. Local fallback if Cloud Run unavailable
            // Uses benefit-score model: FinalScore = (ValueScore × TrustScore) − HarmRisk − AddictionRisk
            // Does NOT optimize for engagement, watch time, or session length.
            let ranked: [Post]
            if let r = sessionResult {
                ranked = r.posts
            } else {
                ranked = await feedAlgorithm.benefitRankPosts(
                    posts,
                    for: interests,
                    followingIds: followingIds
                )
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                // Phase 4: Suppress implicit animation so the scroll position
                // doesn't jump when the ranked array replaces the unranked one.
                withAnimation(.none) {
                    personalizedPosts = ranked
                }
            }
        }
    }
    
    // MARK: - Refresh Function
    
    /// Refresh OpenTable posts with pull-to-refresh
    private func refreshOpenTable() async {
        caughtUpService.recordRefresh()
        isRefreshing = true
        
        await postsManager.fetchFilteredPosts(
            for: .openTable,
            filter: "all",
            topicTag: nil
        )
        
        // Haptic feedback on completion
        await MainActor.run {
            isRefreshing = false
            isInitialLoad = false   // Ensure skeleton never re-locks after a pull-to-refresh
            HapticManager.notification(type: .success)
        }
        
        // Reset pagination after refresh
        visiblePostCount = 20
    }
    
    // MARK: - Pagination

    /// Load more posts when user scrolls near the bottom.
    /// - First expands the in-memory visible window.
    /// - When the window reaches the end of the in-memory buffer, fires a real
    ///   Firestore page fetch (FirebasePostService.loadMorePosts) to pull the next
    ///   25 documents from the server using the cursor stored in the service.
    private func loadMorePosts() {
        guard !isLoadingMore && !firebasePostService.isLoadingMore else { return }

        let allPosts = hasPersonalized && !personalizedPosts.isEmpty
            ? personalizedPosts
            : postsManager.openTablePosts

        // Expand the in-memory visible window by 10
        let newCount = min(visiblePostCount + 10, allPosts.count)
        if newCount > visiblePostCount {
            isLoadingMore = true
            visiblePostCount = newCount
            isLoadingMore = false
        }

        // When we've shown all in-memory posts, go fetch the next Firestore page.
        // This appends 25 more posts to postsManager.openTablePosts via the service,
        // which automatically extends allPosts above on the next render pass.
        if visiblePostCount >= allPosts.count && firebasePostService.hasMorePosts {
            // ✅ INTELLIGENT BANNER: Notify about pagination start
            caughtUpService.onPaginationStarted()
            
            Task {
                await firebasePostService.loadMorePosts(category: .openTable)
                
                // ✅ INTELLIGENT BANNER: Notify about pagination finish
                await MainActor.run {
                    caughtUpService.onPaginationFinished()
                }
            }
        }
    }
}

// MARK: - Collapsible Trending Section

struct CollapsibleTrendingSection: View {
    @AppStorage("trendingSectionExpanded") private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with expand/collapse button
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                    isExpanded.toggle()
                }
                
                HapticManager.impact(style: .light)
            } label: {
                HStack {
                    Text("Trending")
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : 180))
                }
                .padding(.horizontal)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Premium Trending Cards - Horizontal Scroll
            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        SmartTrendingCard(
                            icon: "brain.head.profile",
                            iconColor: Color(red: 0.4, green: 0.7, blue: 1.0),
                            title: "AI & Faith",
                            subtitle: "267 discussions",
                            backgroundColor: Color(red: 0.4, green: 0.7, blue: 1.0)
                        )
                        
                        SmartTrendingCard(
                            icon: "shield.checkered",
                            iconColor: Color(red: 0.4, green: 0.85, blue: 0.7),
                            title: "Tech Ethics",
                            subtitle: "189 discussions",
                            backgroundColor: Color(red: 0.4, green: 0.85, blue: 0.7)
                        )
                        
                        SmartTrendingCard(
                            icon: "lightbulb.fill",
                            iconColor: Color(red: 1.0, green: 0.7, blue: 0.4),
                            title: "Startups",
                            subtitle: "342 discussions",
                            backgroundColor: Color(red: 1.0, green: 0.7, blue: 0.4)
                        )
                        
                        SmartTrendingCard(
                            icon: "book.fill",
                            iconColor: Color(red: 0.6, green: 0.5, blue: 1.0),
                            title: "Scripture",
                            subtitle: "524 discussions",
                            backgroundColor: Color(red: 0.6, green: 0.5, blue: 1.0)
                        )
                        
                        SmartTrendingCard(
                            icon: "flame.fill",
                            iconColor: Color(red: 1.0, green: 0.6, blue: 0.7),
                            title: "Hot Takes",
                            subtitle: "412 discussions",
                            backgroundColor: Color(red: 1.0, green: 0.6, blue: 0.7)
                        )
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: 100)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)).animation(.spring(response: 0.3, dampingFraction: 0.8)),
                    removal: .opacity.combined(with: .scale(scale: 0.95)).animation(.spring(response: 0.3, dampingFraction: 0.8))
                ))
            }
        }
    }
}

// MARK: - Collapsible Community Section

// MARK: - Daily Verse Banner (replaces Top Ideas / Spotlight cards)

// MARK: - Pencil Scribble Compose Icon

/// Ballpoint pen silhouette matching the reference icon.
/// Solid filled shape — angled ~40° (tip points lower-left, cap upper-right).
/// Includes: rounded cap, pen barrel, tapered tip, and clip detail on the right side.
/// No underline / scribble. Drawn entirely with SwiftUI Canvas — crisp at any size.
struct BallpointPenIcon: View {
    var size: CGFloat = 24
    var color: Color = .primary

    var body: some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            // ─── MAIN PEN BODY (solid filled silhouette) ──────────────────
            // The pen is angled ~40° from vertical, tip at lower-left,
            // rounded cap at upper-right — matching the reference closely.
            //
            // Layout (normalised, y=0 top):
            //   Cap top-right  ≈ (0.78, 0.08)
            //   Cap top-left   ≈ (0.54, 0.08)
            //   Barrel widens slightly then narrows to tip
            //   Tip point      ≈ (0.18, 0.90)

            let bodyPath = Path { p in
                // === Cap (rounded rectangle top) ===
                // Top-right of cap (rounded corner)
                p.move(to: CGPoint(x: w * 0.72, y: h * 0.06))
                // Top edge of cap — with rounded right corner
                p.addQuadCurve(
                    to:      CGPoint(x: w * 0.82, y: h * 0.14),
                    control: CGPoint(x: w * 0.84, y: h * 0.06)
                )
                // Right side of cap, curving down into barrel
                p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.28))
                // Barrel right side — narrows toward tip
                p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.36))
                // Taper zone — barrel narrows for the lower half
                p.addLine(to: CGPoint(x: w * 0.60, y: h * 0.54))
                // Tip section — right edge converges to point
                p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.76))
                // Sharp tip at the bottom-left
                p.addLine(to: CGPoint(x: w * 0.18, y: h * 0.93))
                // Tip — left edge (tip is a narrow sharp point)
                p.addLine(to: CGPoint(x: w * 0.26, y: h * 0.72))
                // Left barrel side — runs back up, parallel to right side
                p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.50))
                p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.32))
                p.addLine(to: CGPoint(x: w * 0.56, y: h * 0.24))
                // Left cap side
                p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.14))
                // Top-left of cap (rounded left corner)
                p.addQuadCurve(
                    to:      CGPoint(x: w * 0.72, y: h * 0.06),
                    control: CGPoint(x: w * 0.60, y: h * 0.06)
                )
                p.closeSubpath()
            }

            // Solid fill — entire silhouette
            ctx.fill(bodyPath, with: .color(color))

            // ─── CAP GROOVE (band between cap and barrel) ─────────────────
            // A thin light line separates the cap from the barrel, giving the
            // "click-top ballpoint" profile visible in the reference.
            let groovePath = Path { p in
                p.move(to: CGPoint(x: w * 0.56, y: h * 0.24))
                p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.28))
            }
            ctx.stroke(
                groovePath,
                with: .color(Color(white: 1.0, opacity: 0.55)),
                style: StrokeStyle(lineWidth: w * 0.055, lineCap: .round)
            )

            // ─── CLIP (spring clip on right side of barrel) ───────────────
            // Thin curved strip that runs alongside the right edge of the barrel.
            // In the reference this is visible as a raised strip with a small loop at the bottom.
            let clipPath = Path { p in
                // Clip top — joins at barrel below cap groove
                p.move(to: CGPoint(x: w * 0.72, y: h * 0.30))
                // Runs parallel to the right barrel edge, slightly outside
                p.addCurve(
                    to:      CGPoint(x: w * 0.58, y: h * 0.58),
                    control1: CGPoint(x: w * 0.80, y: h * 0.36),
                    control2: CGPoint(x: w * 0.72, y: h * 0.50)
                )
                // Small loop/curl at the bottom of the clip
                p.addQuadCurve(
                    to:      CGPoint(x: w * 0.64, y: h * 0.54),
                    control: CGPoint(x: w * 0.54, y: h * 0.62)
                )
            }
            ctx.stroke(
                clipPath,
                with: .color(Color(white: 1.0, opacity: 0.50)),
                style: StrokeStyle(lineWidth: w * 0.07, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Banner Color Palette

struct BannerColorOption: Identifiable {
    let id: String       // stored in Firestore
    let label: String
    let top: Color
    let bottom: Color
    let shadow: Color
    var isLight: Bool = false  // true for light backgrounds — uses dark checkmark/border

    static let all: [BannerColorOption] = [
        BannerColorOption(
            id: "red",
            label: "Red",
            top:    Color(red: 0.97, green: 0.25, blue: 0.20),
            bottom: Color(red: 0.92, green: 0.18, blue: 0.14),
            shadow: Color(red: 0.92, green: 0.18, blue: 0.14)
        ),
        BannerColorOption(
            id: "midnight",
            label: "Midnight",
            top:    Color(red: 0.10, green: 0.12, blue: 0.28),
            bottom: Color(red: 0.06, green: 0.07, blue: 0.18),
            shadow: Color(red: 0.06, green: 0.07, blue: 0.20)
        ),
        BannerColorOption(
            id: "forest",
            label: "Forest",
            top:    Color(red: 0.10, green: 0.38, blue: 0.22),
            bottom: Color(red: 0.06, green: 0.28, blue: 0.15),
            shadow: Color(red: 0.06, green: 0.28, blue: 0.15)
        ),
        BannerColorOption(
            id: "ocean",
            label: "Ocean",
            top:    Color(red: 0.05, green: 0.35, blue: 0.62),
            bottom: Color(red: 0.03, green: 0.25, blue: 0.48),
            shadow: Color(red: 0.03, green: 0.25, blue: 0.50)
        ),
        BannerColorOption(
            id: "plum",
            label: "Plum",
            top:    Color(red: 0.38, green: 0.12, blue: 0.42),
            bottom: Color(red: 0.28, green: 0.07, blue: 0.32),
            shadow: Color(red: 0.28, green: 0.07, blue: 0.34)
        ),
        // New colors from brand palette
        BannerColorOption(
            id: "deepplum",
            label: "Deep Plum",
            top:    Color(red: 0.220, green: 0.098, blue: 0.196),  // #381932
            bottom: Color(red: 0.165, green: 0.063, blue: 0.149),
            shadow: Color(red: 0.220, green: 0.098, blue: 0.196)
        ),
        BannerColorOption(
            id: "milk",
            label: "Milk",
            top:    Color(red: 1.000, green: 0.953, blue: 0.902),  // #FFF3E6
            bottom: Color(red: 0.980, green: 0.933, blue: 0.882),
            shadow: Color(red: 0.800, green: 0.750, blue: 0.700),
            isLight: true
        ),
        BannerColorOption(
            id: "cyprus",
            label: "Cyprus",
            top:    Color(red: 0.000, green: 0.275, blue: 0.263),  // #004643
            bottom: Color(red: 0.000, green: 0.200, blue: 0.192),
            shadow: Color(red: 0.000, green: 0.275, blue: 0.263)
        ),
        BannerColorOption(
            id: "sanddune",
            label: "Sand Dune",
            top:    Color(red: 0.941, green: 0.929, blue: 0.898),  // #F0EDE5
            bottom: Color(red: 0.910, green: 0.898, blue: 0.863),
            shadow: Color(red: 0.700, green: 0.680, blue: 0.640),
            isLight: true
        ),
        BannerColorOption(
            id: "tomato",
            label: "Tomato",
            top:    Color(red: 0.961, green: 0.196, blue: 0.000),  // #F53200
            bottom: Color(red: 0.902, green: 0.157, blue: 0.000),
            shadow: Color(red: 0.961, green: 0.196, blue: 0.000)
        ),
        BannerColorOption(
            id: "amber",
            label: "Amber",
            top:    Color(red: 0.961, green: 0.529, blue: 0.039),  // #F5870A
            bottom: Color(red: 0.910, green: 0.478, blue: 0.020),
            shadow: Color(red: 0.961, green: 0.529, blue: 0.039)
        ),
        BannerColorOption(
            id: "obsidian",
            label: "Obsidian",
            top:    Color(red: 0.039, green: 0.039, blue: 0.039),  // #0A0A0A
            bottom: Color(red: 0.020, green: 0.020, blue: 0.020),
            shadow: Color(red: 0.000, green: 0.000, blue: 0.000)
        ),
    ]

    static func find(_ id: String?) -> BannerColorOption {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - Banner Color Picker Sheet

struct BannerColorPickerSheet: View {
    @Binding var selectedColorId: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Text("Banner Color")
                .font(AMENFont.bold(17))
                .foregroundStyle(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(BannerColorOption.all) { option in
                        Button {
                            selectedColorId = option.id
                            onSelect(option.id)
                            HapticManager.impact(style: .light)
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [option.top, option.bottom],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 52, height: 52)
                                        .shadow(color: option.shadow.opacity(0.35), radius: 6, y: 3)

                                    if selectedColorId == option.id {
                                        let accentColor: Color = option.isLight ? .black.opacity(0.7) : .white
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(accentColor, lineWidth: 2.5)
                                            .frame(width: 52, height: 52)
                                        Image(systemName: "checkmark")
                                            .font(.systemScaled(14, weight: .bold))
                                            .foregroundStyle(accentColor)
                                    }
                                }
                                Text(option.label)
                                    .font(AMENFont.regular(11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.instantFeedback)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(24)
    }
}

// MARK: - Daily Verse Banner

struct DailyVerseBanner: View {
    @ObservedObject private var verseService = DailyVerseGenkitService.shared
    // OFFLINE FIX: retry AI verse generation when the app returns to foreground
    // and the displayed verse is still just the curated offline fallback.
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var networkMonitor = AMENNetworkMonitor.shared

    var body: some View {
        DailyVerseBannerView(
            verse: verseService.todayVerse,
            isLoading: verseService.isGenerating,
            onLoad: { Task { await verseService.generatePersonalizedDailyVerse() } }
        )
        .task {
            await loadCachedVerseIfNeeded()
        }
        // OFFLINE FIX: When the app moves to active and the verse is a curated fallback
        // (isPersonalized == false), attempt a fresh Cloud Function call now that the
        // network may be available.  Guard on isGenerating to avoid duplicate calls.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active,
               !verseService.isPersonalized,
               networkMonitor.isConnected,
               !verseService.isGenerating {
                Task { _ = await verseService.generatePersonalizedDailyVerse(forceRefresh: true) }
            }
        }
    }

    private func loadCachedVerseIfNeeded() async {
        guard verseService.todayVerse == nil else { return }
        if let data = UserDefaults.standard.data(forKey: "cachedDailyVerse"),
           let date = UserDefaults.standard.object(forKey: "cachedVerseDate") as? Date,
           Calendar.current.isDate(date, inSameDayAs: Date()),
           let verse = try? JSONDecoder().decode(PersonalizedDailyVerse.self, from: data) {
            await MainActor.run {
                verseService.todayVerse = verse
            }
        } else {
            _ = await verseService.generatePersonalizedDailyVerse()
        }
    }
}

// MARK: - Daily Verse Detail Sheet

struct DailyVerseDetailSheet: View {
    let verse: PersonalizedDailyVerse?
    let color: BannerColorOption
    @Environment(\.dismiss) private var dismiss
    @State private var showBerean = false

    private var reference: String {
        verse?.reference ?? "Jeremiah 29:11"
    }

    private var text: String {
        verse?.text ?? "\"For I know the plans I have for you,\" declares the LORD, \"plans to prosper you and not to harm you, plans to give you hope and a future.\""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Verse card
                    VStack(spacing: 16) {
                        Text(text)
                            .font(AMENFont.regular(20))
                            .foregroundStyle(.white)
                            .lineSpacing(6)
                            .multilineTextAlignment(.leading)

                        Text("— \(reference)")
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [color.top, color.bottom],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .padding(.horizontal)

                    // Action buttons
                    VStack(spacing: 12) {
                        Button {
                            showBerean = true
                        } label: {
                            Label("Reflect with Berean", systemImage: "sparkles")
                                .font(AMENFont.semiBold(16))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        ShareLink(item: "\(text)\n\n— \(reference)\n\nShared from AMEN") {
                            Label("Share Verse", systemImage: "square.and.arrow.up")
                                .font(AMENFont.semiBold(16))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(.horizontal)

                    // Reflection prompt
                    if let reflection = verse?.reflection, !reflection.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Today's Reflection")
                                .font(AMENFont.bold(15))
                                .foregroundStyle(.primary)
                            Text(reflection)
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 20)
            }
            .navigationTitle("Daily Verse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AMENFont.semiBold(16))
                }
            }
            .sheet(isPresented: $showBerean) {
                BereanChatView(initialQuery: "Help me reflect on \(reference): \"\(text)\"")
            }
        }
    }
}

struct CollapsibleCommunitySection: View {
    @AppStorage("communitySectionExpanded") private var isExpanded = true
    @Binding var showTopIdeas: Bool
    @Binding var showSpotlight: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with expand/collapse button
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                    isExpanded.toggle()
                }
                
                HapticManager.impact(style: .light)
            } label: {
                HStack {
                    Text("Community")
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : 180))
                }
                .padding(.horizontal)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Community Cards - Liquid Glass Design
            if isExpanded {
                HStack(spacing: 12) {
                    LiquidGlassCommunityCard(
                        icon: "arrow.up",
                        iconColor: Color.white, // White upward arrow
                        backgroundGradientTop: Color(red: 0.40, green: 0.75, blue: 0.95), // Light sky blue
                        backgroundGradientBottom: Color(red: 0.60, green: 0.85, blue: 0.98), // Lighter blue (bottom)
                        useBurgundyStyle: false,
                        title: "Top Ideas",
                        subtitle: "This Week"
                    ) {
                        showTopIdeas = true
                    }
                    
                    LiquidGlassCommunityCard(
                        icon: "lightbulb.fill",
                        iconColor: Color.white, // White lightbulb
                        backgroundGradientTop: Color(red: 0.25, green: 0.35, blue: 0.45), // Deep slate blue
                        backgroundGradientBottom: Color(red: 0.35, green: 0.45, blue: 0.55), // Lighter slate blue
                        useBurgundyStyle: false,
                        title: "Spotlight",
                        subtitle: "Featured"
                    ) {
                        showSpotlight = true
                    }
                }
                .padding(.horizontal)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)).animation(.spring(response: 0.3, dampingFraction: 0.8)),
                    removal: .opacity.combined(with: .scale(scale: 0.95)).animation(.spring(response: 0.3, dampingFraction: 0.8))
                ))
            }
        }
        .sheet(isPresented: $showTopIdeas) {
            TopIdeasView()
        }
        .sheet(isPresented: $showSpotlight) {
            SpotlightView()
        }
    }
}

// MARK: - Liquid Glass Community Card (Black & White with Color Accents)

struct LiquidGlassCommunityCard: View {
    let icon: String
    let iconColor: Color
    var backgroundGradientTop: Color? = nil
    var backgroundGradientBottom: Color? = nil
    var useBurgundyStyle: Bool = false
    let title: String
    let subtitle: String
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            HapticManager.impact(style: .light)
            action()
        }) {
            HStack(spacing: 12) {
                // White icon
                Image(systemName: icon)
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: isPressed)
                
                VStack(alignment: .leading, spacing: 3) {
                    // White text for both banners
                    Text(title)
                        .font(.systemScaled(15, weight: .semibold))
                        .italic()
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(.systemScaled(12, weight: .semibold))
                        .italic()
                        .foregroundStyle(.white.opacity(0.9))
                }
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    // Use gradient colors if provided, otherwise use black glassmorphic background
                    if let gradientTop = backgroundGradientTop, let gradientBottom = backgroundGradientBottom {
                        // Custom gradient background
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [gradientTop, gradientBottom],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: gradientTop.opacity(0.3), radius: 8, x: 0, y: 4)
                    } else {
                        // Black glassmorphic background (default)
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.6))
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(.ultraThinMaterial)
                            )
                    }
                    
                    // Transparent liquid glass border
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.3),
                                    .white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.smooth(duration: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Premium Trending Card (Smaller & Refined)

struct SmartTrendingCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let backgroundColor: Color
    
    @State private var isPressed = false
    @State private var showDetails = false
    
    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) {
                showDetails = true
            }
            
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 16) {
                // Premium Icon with Glass Effect
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    iconColor.opacity(0.2),
                                    iconColor.opacity(0.05),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 30
                            )
                        )
                        .frame(width: 60, height: 60)
                        .blur(radius: 8)
                    
                    // Glass circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.4),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: iconColor.opacity(0.3), radius: 12, y: 6)
                    
                    Image(systemName: icon)
                        .font(.systemScaled(22, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: isPressed)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AMENFont.bold(17))
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.white.opacity(0.85))
                }
                
                Spacer()
                
                // Premium Arrow
                Image(systemName: "arrow.right")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(8)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.15))
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    // Premium gradient background
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    backgroundColor,
                                    backgroundColor.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Glass overlay
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Premium border
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            )
            .shadow(color: backgroundColor.opacity(0.3), radius: 16, y: 8)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 20)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.smooth(duration: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
        .sheet(isPresented: $showDetails) {
            TrendingTopicDetailView(title: title, icon: icon)
        }
    }
}

// MARK: - Top Ideas View

struct TopIdeasView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var trendingService = TrendingService.shared
    @ObservedObject private var filteringService = SmartIdeaFilteringService.shared
    @State private var selectedTimeframe: IdeaTimeframe = .week
    @State private var selectedCategory: TopIdea.IdeaCategory = .all
    @State private var showFilters = false
    
    enum IdeaTimeframe: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        case allTime = "All Time"
        
        var timeInterval: TimeInterval {
            switch self {
            case .today: return 24 * 3600
            case .week: return 7 * 24 * 3600
            case .month: return 30 * 24 * 3600
            case .allTime: return 365 * 24 * 3600
            }
        }
    }
    
    var filteredTopIdeas: [TopIdea] {
        // Use smart filtering algorithm for accurate categorization
        filteringService.filterIdeas(
            trendingService.topIdeas,
            category: selectedCategory,
            timeframe: selectedTimeframe.timeInterval,
            minEngagement: 0
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Top Ideas")
                                    .font(AMENFont.bold(32))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.black, .black.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                
                                Text("The brightest ideas from our community")
                                    .font(AMENFont.regular(14))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            ZStack {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color.yellow.opacity(0.3),
                                                Color.orange.opacity(0.1)
                                            ],
                                            center: .center,
                                            startRadius: 5,
                                            endRadius: 30
                                        )
                                    )
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: "lightbulb.fill")
                                    .font(.systemScaled(40, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.yellow, .orange],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .symbolEffect(.pulse, options: .repeating)
                            }
                        }
                        
                        // Timeframe Selector
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(IdeaTimeframe.allCases, id: \.self) { timeframe in
                                    Button {
                                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                            selectedTimeframe = timeframe
                                        }
                                        Task {
                                            try? await trendingService.fetchTopIdeas(
                                                timeframe: timeframe.timeInterval,
                                                category: selectedCategory
                                            )
                                        }
                                    } label: {
                                        Text(timeframe.rawValue)
                                            .font(AMENFont.semiBold(13))
                                            .foregroundStyle(selectedTimeframe == timeframe ? .white : .primary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(
                                                        selectedTimeframe == timeframe ? 
                                                            LinearGradient(
                                                                colors: [Color.yellow.opacity(0.9), Color.orange.opacity(0.9)],
                                                                startPoint: .leading,
                                                                endPoint: .trailing
                                                            ) :
                                                            LinearGradient(
                                                                colors: [Color.gray.opacity(0.15)],
                                                                startPoint: .top,
                                                                endPoint: .bottom
                                                            )
                                                    )
                                                    .shadow(
                                                        color: selectedTimeframe == timeframe ? Color.yellow.opacity(0.3) : .clear,
                                                        radius: 8,
                                                        y: 4
                                                    )
                                            )
                                    }
                                }
                            }
                        }
                        
                        // Category Filter
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(TopIdea.IdeaCategory.allCases, id: \.self) { category in
                                    Button {
                                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                            selectedCategory = category
                                        }
                                        Task {
                                            try? await trendingService.fetchTopIdeas(
                                                timeframe: selectedTimeframe.timeInterval,
                                                category: category
                                            )
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: category.icon)
                                                .font(.systemScaled(10, weight: .semibold))
                                            
                                            Text(category.rawValue)
                                                .font(AMENFont.semiBold(12))
                                        }
                                        .foregroundStyle(selectedCategory == category ? .white : category.color)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(
                                                    selectedCategory == category ?
                                                        category.color :
                                                        category.color.opacity(0.12)
                                                )
                                                .shadow(
                                                    color: selectedCategory == category ? category.color.opacity(0.3) : .clear,
                                                    radius: 6,
                                                    y: 3
                                                )
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(
                                                    selectedCategory == category ? Color.clear : category.color.opacity(0.3),
                                                    lineWidth: 1
                                                )
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Ideas List
                    if trendingService.isLoading {
                        VStack(spacing: 12) {
                            AMENLoadingIndicator()
                            Text("Finding the brightest ideas...")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if filteredTopIdeas.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "lightbulb.slash")
                                .font(.systemScaled(48))
                                .foregroundStyle(.secondary)
                            Text("No trending ideas yet")
                                .font(AMENFont.bold(18))
                            Text("Be the first to share a brilliant idea!")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(filteredTopIdeas) { idea in
                                TopIdeaCard(idea: idea)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(28))
                            .foregroundStyle(.gray.opacity(0.3))
                    }
                }
            }
            .task {
                // Fetch top ideas when view appears
                try? await trendingService.fetchTopIdeas(
                    timeframe: selectedTimeframe.timeInterval,
                    category: selectedCategory
                )
            }
        }
    }
    
    // MARK: - Community Covenant Check
    // TODO: Re-enable when Community Covenant files are added to Xcode project
    /*
    private func checkCovenantAgreement() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let doc = try await Firestore.firestore()
                .collection("users").document(userId)
                .collection("communityStandards").document("agreement")
                .getDocument()
            
            if !doc.exists {
                await MainActor.run {
                    needsCovenantAgreement = true
                    // Delay showing to avoid conflicting with welcome screen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        showCommunityCovenant = true
                    }
                }
            } else {
                // Check if re-affirmation needed (90 days)
                if let nextReaffirmation = (doc.data()?["nextReaffirmation"] as? Timestamp)?.dateValue() {
                    if Date() > nextReaffirmation {
                        await MainActor.run {
                            needsCovenantAgreement = true
                            showCommunityCovenant = true
                        }
                    }
                }
            }
        } catch {
            dlog("❌ Failed to check covenant agreement: \(error)")
        }
    }
    */
}

// MARK: - Top Idea Model (Now in TrendingService.swift)

// MARK: - Top Idea Card

struct TopIdeaCard: View {
    let idea: TopIdea
    @State private var hasLightbulbed = false
    @State private var localLightbulbCount: Int
    @State private var showComments = false
    @State private var isAnimating = false
    @Namespace private var glassNamespace
    
    init(idea: TopIdea) {
        self.idea = idea
        _localLightbulbCount = State(initialValue: idea.lightbulbCount)
    }
    
    // Rank gradient computed property
    private var rankGradient: LinearGradient {
        switch idea.rank {
        case 1:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.85, green: 0.65, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 2:
            return LinearGradient(
                colors: [Color(red: 0.75, green: 0.75, blue: 0.75), Color(red: 0.5, green: 0.5, blue: 0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 3:
            return LinearGradient(
                colors: [Color(red: 0.8, green: 0.5, blue: 0.2), Color(red: 0.6, green: 0.3, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [Color.blue, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Rank Badge
            HStack {
                ZStack {
                    Circle()
                        .fill(rankGradient)
                        .frame(width: 40, height: 40)
                    
                    Text("#\(idea.rank)")
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(idea.authorName)
                        .font(AMENFont.bold(15))
                        .foregroundStyle(.primary)
                    
                    Text(idea.timeAgo)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Badges
                HStack(spacing: 4) {
                    ForEach(idea.badges, id: \.self) { badge in
                        Text(badge)
                            .font(AMENFont.semiBold(10))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                            )
                    }
                }
            }
            
            // Content
            Text(idea.content)
                .font(AMENFont.regular(15))
                .foregroundStyle(.primary)
                .lineSpacing(4)
            
            // Interactive Reactions
            GlassEffectContainer {
                HStack(spacing: 12) {
                    // Lightbulb Reaction with Animation
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.5))) {
                            hasLightbulbed.toggle()
                            localLightbulbCount += hasLightbulbed ? 1 : -1
                            isAnimating = true
                        }
                        
                        HapticManager.impact(style: hasLightbulbed ? .heavy : .light)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            isAnimating = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            ZStack {
                                // Glow effect when active
                                if hasLightbulbed {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.systemScaled(16, weight: .bold))
                                        .foregroundStyle(.yellow)
                                        .blur(radius: 8)
                                        .scaleEffect(isAnimating ? 1.5 : 1.0)
                                        .opacity(isAnimating ? 0 : 0.6)
                                }
                                
                                Image(systemName: hasLightbulbed ? "lightbulb.fill" : "lightbulb")
                                    .font(.systemScaled(16, weight: .semibold))
                                    .foregroundStyle(hasLightbulbed ? 
                                        LinearGradient(
                                            colors: [.yellow, .orange],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ) :
                                        LinearGradient(
                                            colors: [.black.opacity(0.5), .black.opacity(0.5)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                                    .rotationEffect(.degrees(isAnimating ? 15 : 0))
                            }
                            
                            Text("\(localLightbulbCount)")
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(hasLightbulbed ? .orange : .black.opacity(0.5))
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(hasLightbulbed ? Color.yellow.opacity(0.2) : Color.gray.opacity(0.1))
                                
                                if hasLightbulbed {
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(
                                            LinearGradient(
                                                colors: [.yellow, .orange],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                }
                            }
                        )
                    }
                    
                    // Comment Button
                    ReactionButton(
                        icon: "bubble.left.fill",
                        count: idea.commentCount,
                        isActive: showComments,
                        activeColor: .blue,
                        namespace: glassNamespace
                    ) {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                            showComments.toggle()
                        }
                    }
                    
                    Spacer()
                    
                    // Share Button
                    Button {
                        // Share action
                        HapticManager.impact(style: .light)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.5))
                            .padding(8)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
    }
}

// MARK: - Notification Badge Component

struct NotificationBadge: View {
    let count: Int
    let pulse: Bool
    
    var body: some View {
        ZStack {
            // Pulse circle background (appears when new notification arrives)
            if pulse {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 20, height: 20)
                    .scaleEffect(pulse ? 1.5 : 1.0)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 0.6), value: pulse)
            }
            
            // Main badge
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.red, Color.red.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: max(14, count > 9 ? 18 : 14), height: max(14, 14))
                .shadow(color: .red.opacity(0.5), radius: 4, x: 0, y: 2)
            
            if count <= 99 {
                Text("\(count)")
                    .font(.systemScaled(count > 9 ? 8 : 9, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            } else {
                Text("99+")
                    .font(.systemScaled(7, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
        }
        .scaleEffect(pulse ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: pulse)
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Safe Frame Extension
extension View {
    /// Ensures frame dimensions are never negative or non-finite
    func safeFrame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        self.frame(
            width: width.map { max(0, $0.isFinite ? $0 : 0) },
            height: height.map { max(0, $0.isFinite ? $0 : 0) },
            alignment: alignment
        )
    }
    
    /// Conditionally applies a transformation to a view
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Post Success Toast (Glassmorphic Design)

// MARK: - Posting Bar State

enum PostingBarState: Equatable {
    case hidden
    case posting   // spinner + "Posting…"
    case posted    // checkmark + "Posted · View"
}

// MARK: - ThreadsPostingBar

/// Threads-style bottom bar that slides up from the tab bar.
/// Shows "Posting…" while the network call is in flight, then
/// transitions to "Posted · View" once Firestore confirms.
struct ThreadsPostingBar: View {
    let state: PostingBarState
    let category: String
    let post: Post?
    let onView: () -> Void

    // Category-specific accent
    private var accent: Color {
        switch category {
        case "openTable":   return .orange
        case "testimonies": return .yellow
        case "prayer":      return .blue
        default:            return Color.accentColor
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Left: app icon circle
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 36, height: 36)
                Image("amen-logo")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
            }

            // Middle: label
            Group {
                if state == .posting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.75)
                            .tint(.secondary)
                        Text("Posting…")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.systemScaled(15, weight: .semibold))
                            .foregroundStyle(.green)
                            .symbolEffect(.bounce, value: state == .posted)
                        Text("Posted")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state)

            Spacer()

            // Right: "View" button (only when posted)
            if state == .posted {
                Button(action: onView) {
                    Text("View")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 6)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state)
        .onAppear {
            if state == .posted {
                HapticManager.notification(type: .success)
            }
        }
        .onChange(of: state) { _, newState in
            if newState == .posted {
                HapticManager.notification(type: .success)
            }
        }
    }
}

// Keep PostSuccessToast as a thin alias so any lingering references still compile
@available(*, deprecated, renamed: "ThreadsPostingBar")
struct PostSuccessToast: View {
    let category: String
    @State private var isAnimating = false
    
    // Category display info
    private var categoryInfo: (icon: String, name: String, color: Color) {
        switch category {
        case "openTable":
            return ("lightbulb.fill", "#OPENTABLE", .orange)
        case "testimonies":
            return ("star.fill", "Testimonies", .yellow)
        case "prayer":
            return ("hands.sparkles.fill", "Prayer", .blue)
        default:
            return ("checkmark.circle.fill", "Post", .green)
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Success icon with subtle animation
            ZStack {
                // Outer pulse ring
                Circle()
                    .fill(categoryInfo.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0 : 1)
                
                // Inner circle with glassmorphic effect
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.5),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                
                // Icon
                Image(systemName: categoryInfo.icon)
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(categoryInfo.color)
                    .symbolEffect(.bounce, value: isAnimating)
            }
            
            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text("Posted to \(categoryInfo.name)")
                    .font(AMENFont.bold(14))
                    .foregroundStyle(.primary)
                
                Text("Your post is now live")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.systemScaled(20))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: isAnimating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            ZStack {
                // Glassmorphic background
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                
                // Subtle gradient overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Border with gradient
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .shadow(color: categoryInfo.color.opacity(0.2), radius: 12, y: 4)
        .padding(.horizontal, 20)
        .onAppear {
            // Trigger animations
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
            
            // Haptic feedback
            HapticManager.notification(type: .success)
        }
    }
}

// MARK: - Empty Feed State

/// Shown when the OpenTable feed has no posts.
/// If the user has zero follows, surfaces a "Discover People" CTA to guide them.
struct EmptyFeedView: View {
    @ObservedObject private var followService = FollowService.shared

    // Which variant to show
    private var isNewUser: Bool { followService.following.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 48)

            if isNewUser {
                newUserState
            } else {
                followingButEmptyState
            }

            Spacer().frame(height: 48)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
    }

    // ── New user: hasn't followed anyone yet ──────────────────────────────
    private var newUserState: some View {
        VStack(spacing: 0) {
            // Icon cluster
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.2.fill")
                    .font(.systemScaled(32, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer().frame(height: 20)

            Text("Follow people to see their posts")
                .font(AMENFont.bold(20))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 8)

            Text("When you follow fellow believers, their prayers, testimonies, and thoughts will appear here.")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer().frame(height: 28)

            // Primary CTA — find people
            Button {
                NotificationCenter.default.post(name: .switchToDiscoverTab, object: nil)
            } label: {
                Text("Find People to Follow")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }

    // ── Following people but their feed is empty ──────────────────────────
    private var followingButEmptyState: some View {
        VStack(spacing: 0) {
            // Icon cluster showing "all caught up / nothing new"
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 80, height: 80)
                Image(systemName: "sparkles")
                    .font(.systemScaled(32, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer().frame(height: 20)

            Text("Nothing here yet")
                .font(AMENFont.bold(20))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 8)

            Text("The people you follow haven't posted recently. Be the first to share something — a prayer, a testimony, or what's on your heart.")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer().frame(height: 28)

            // Primary CTA — create a post
            Button {
                NotificationCenter.default.post(name: .openCreatePost, object: nil)
            } label: {
                Text("Share Something")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(ScaleButtonStyle())

            Spacer().frame(height: 12)

            // Secondary — find more people
            Button {
                NotificationCenter.default.post(name: .switchToDiscoverTab, object: nil)
            } label: {
                Text("Find more people to follow")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

extension Notification.Name {
    static let switchToDiscoverTab = Notification.Name("switchToDiscoverTab")
    static let feedDidRefresh = Notification.Name("feedDidRefresh")
}

#Preview("Posting Bar - Posting") {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        VStack {
            Spacer()
            ThreadsPostingBar(state: .posting, category: "openTable", post: nil) {}
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
        }
    }
}

#Preview("Posting Bar - Posted") {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        VStack {
            Spacer()
            ThreadsPostingBar(state: .posted, category: "prayer", post: nil) {}
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
        }
    }
}

#Preview("ContentView") {
    ContentView()
}

// MARK: - Environment Key for Tab Bar Visibility
private struct TabBarVisibleKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(true)
}

extension EnvironmentValues {
    var tabBarVisible: Binding<Bool> {
        get { self[TabBarVisibleKey.self] }
        set { self[TabBarVisibleKey.self] = newValue }
    }
}

// MARK: - Environment Key for Main Tab Selection
private struct MainTabSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<Int> = .constant(0)
}

extension EnvironmentValues {
    var mainTabSelection: Binding<Int> {
        get { self[MainTabSelectionKey.self] }
        set { self[MainTabSelectionKey.self] = newValue }
    }
}

// P0 FIX: Using existing ScrollOffsetPreferenceKey from PeopleDiscoveryView
// (No need to redefine - already exists globally)

// P0 FIX: Removed UIView.findScrollView extension - no longer needed with PreferenceKey approach

// MARK: - Create Quick Action Row
struct CreateQuickActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: LinearGradient
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon with gradient
                ZStack {
                    Circle()
                        .fill(gradient.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.systemScaled(18, weight: .medium))
                        .foregroundStyle(gradient)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.systemScaled(12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.circle.fill")
                    .font(.systemScaled(20, weight: .semibold))
                    .foregroundStyle(gradient)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isPressed ? Color.black.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}


// MARK: - Rotate Transition (compose button + icon unfurl)

extension AnyTransition {
    static var rotate: AnyTransition {
        .modifier(
            active:   RotateModifier(angle: 45),
            identity: RotateModifier(angle: 0)
        )
    }
}

private struct RotateModifier: ViewModifier {
    let angle: Double
    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(angle))
    }
}

// MARK: - Feed Communities Sheet

struct FeedCommunitiesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedMode: LegacyFeedMode
    @StateObject private var drawerState = FeedDrawerState()
    @StateObject private var vm = ArkCommunityViewModel()
    @State private var joiningCommunity: ArkCommunity? = nil
    @State private var showBrowseAll = false
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // Feed Modes Section
                    feedModesSection
                        .padding(.top, 6)
                        .padding(.bottom, 2)

                    Divider()
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .opacity(0.3)

                    // Browse All button
                    Button {
                        showBrowseAll = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.systemScaled(14, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 32, height: 32)
                                .background(Color.accentColor.opacity(0.12), in: Circle())
                            Text("Browse all communities")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)

                    // Loading indicator
                    if vm.isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .padding(.vertical, 20)
                    } else {
                        // Led by You
                        if !vm.myLedCommunities.isEmpty {
                            arkCommunitySection(
                                title: "Led by You",
                                icon: "crown.fill",
                                communities: vm.myLedCommunities,
                                accentColor: .purple
                            )
                            .padding(.bottom, 4)
                        }

                        // Your Communities
                        if !vm.myJoinedCommunities.isEmpty {
                            arkCommunitySection(
                                title: "Your Communities",
                                icon: "person.3.fill",
                                communities: vm.myJoinedCommunities,
                                accentColor: .accentColor
                            )
                            .padding(.bottom, 4)
                        }

                        // Suggested
                        if !vm.suggestedCommunities.isEmpty {
                            arkSuggestedSection
                                .padding(.bottom, 4)
                        }

                        // Empty state
                        if vm.communities.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "person.3")
                                    .font(.systemScaled(36))
                                    .foregroundStyle(.tertiary)
                                Text("No communities yet")
                                    .font(AMENFont.semiBold(15))
                                    .foregroundStyle(.secondary)
                                Button {
                                    showBrowseAll = true
                                } label: {
                                    Text("Browse & Create")
                                        .font(AMENFont.semiBold(13))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                        .background(Color.accentColor, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Communities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                await vm.loadCommunities()
                await vm.loadUserMemberships()
            }
            .navigationDestination(isPresented: $showBrowseAll) {
                BrowseCommunitiesView()
            }
            .sheet(item: $joiningCommunity) { community in
                CommunityCovenantView {
                    Task {
                        await vm.joinCommunity(community)
                        if let cid = community.id {
                            vm.userMembershipIds.insert(cid)
                        }
                    }
                    joiningCommunity = nil
                }
            }
        }
        .presentationDetents([.fraction(0.6)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Feed Modes Section

    private var feedModesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Feed Mode", icon: "slider.horizontal.3")

            VStack(spacing: 0) {
                ForEach(DrawerFeedMode.allCases) { mode in
                    feedModeRow(mode)
                    if mode != DrawerFeedMode.allCases.last {
                        Divider()
                            .padding(.leading, 52)
                            .opacity(0.25)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func feedModeRow(_ mode: DrawerFeedMode) -> some View {
        let isActive = drawerState.activeFeedMode == mode
        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                drawerState.activeFeedMode = mode
            }
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                    .frame(width: 32, height: 32)
                    .background(isActive ? Color.accentColor : Color.clear, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.primary)
                    Text(mode.subtitle)
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.systemScaled(11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ark Community Sections (real data)

    private func arkCommunitySection(
        title: String,
        icon: String,
        communities: [ArkCommunity],
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title, icon: icon)

            VStack(spacing: 0) {
                ForEach(communities) { community in
                    NavigationLink(destination: ArkCommunityDetailView(community: community)) {
                        arkCommunityRow(community, accent: accentColor)
                    }
                    .buttonStyle(.plain)

                    if community.id != communities.last?.id {
                        Divider()
                            .padding(.leading, 56)
                            .opacity(0.25)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func arkCommunityRow(_ community: ArkCommunity, accent: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(community.name.prefix(2).uppercased())
                    .font(.systemScaled(14, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(community.name)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.primary)
                    if community.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.systemScaled(11))
                            .foregroundStyle(.blue)
                    }
                }
                Text("\(community.memberCount) members · \(communityCategory(community))")
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var arkSuggestedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Suggested", icon: "sparkles")

            VStack(spacing: 0) {
                ForEach(vm.suggestedCommunities.prefix(3)) { community in
                    arkSuggestedRow(community)
                    if community.id != vm.suggestedCommunities.prefix(3).last?.id {
                        Divider()
                            .padding(.leading, 56)
                            .opacity(0.25)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func arkSuggestedRow(_ community: ArkCommunity) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(community.name.prefix(2).uppercased())
                    .font(.systemScaled(14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(community.name)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)
                Text("\(community.memberCount) members · \(communityCategory(community))")
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                HapticManager.impact(style: .medium)
                joiningCommunity = community
            } label: {
                Text("Join")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func communityCategory(_ community: ArkCommunity) -> String {
        switch community.category {
        case "small_group": return "Small Group"
        case "ministry":    return "Ministry"
        case "recovery":    return "Recovery"
        case "study":       return "Study"
        case "prayer":      return "Prayer"
        default:            return community.category.capitalized
        }
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.systemScaled(11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(AMENFont.semiBold(12))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }
}
