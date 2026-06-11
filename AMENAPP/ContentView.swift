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
    @StateObject private var contextManager: SpiritualOSContextManager
    @StateObject private var assistantCoordinator: AmenAssistantBarCoordinator
    
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
    @ObservedObject private var featureFlags = AMENFeatureFlags.shared
    private var isShowingLoadingScreen: Bool { appReadyState.isShowingLoadingScreen }
    private var hasRealFirebaseUser: Bool {
        authViewModel.isAuthenticated && Auth.auth().currentUser?.uid != nil
    }

    // ── SabbathMode: Additive wiring (extends existing ShabbatModeService/RestModeGate) ──
    // SabbathModeService drives the Sabbath gate. Does NOT replace SundayChurchFocusManager.
    @ObservedObject private var sabbathService = SabbathModeService.shared
    @State private var sabbathCurrentDest: SabbathNavDestination?
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
    // Audience-First Composer Gate
    @State private var showAudiencePicker = false
    @State private var selectedAudience: AmenPostAudience? = nil
    @State private var selectedAudienceMetadata: AmenAudienceMetadata? = nil
    // Camera OS
    @State private var showCameraOS = false
    @State private var showBereanQuickActions = false
    @State private var showBereanAssistantFromMenu = false
    @State private var showBereanDailyFormation = false
    @State private var showBereanConversionMenu = false
    @State private var showCreatorKit = false
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

    private var isResourcesTabActive: Bool {
        viewModel.selectedTab == 3
    }

    private var shouldShowAssistantBar: Bool {
        showTabBar && !isResourcesTabActive
    }

    private var bottomChromeReservedHeight: CGFloat {
        guard showTabBar else { return 24 }
        return isResourcesTabActive ? 190 : 268
    }
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
    @State private var noteShareRoute: NoteShareRoute?
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
        let uid = Auth.auth().currentUser?.uid ?? ""
        _contextManager = StateObject(wrappedValue: SpiritualOSContextManager(userId: uid))
        _assistantCoordinator = StateObject(wrappedValue: AmenAssistantBarCoordinator(userId: uid))
        _showCreatePost = State(initialValue: false)
        
        // Note: No native UITabBar in use — navigation is handled by AMENTabBar (custom SwiftUI).
        // UITabBar.appearance() setup removed to prevent any phantom system tab bar rendering.
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
            } else if !hasRealFirebaseUser {
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
                        } else if authViewModel.hasRememberedIdentityAfterReinstall {
                            SmartAccountResumeView(
                                onAuthenticated: {
                                    withAnimation(Motion.adaptive(.spring(response: 0.6, dampingFraction: 0.8))) {
                                        showSplash = false
                                    }
                                },
                                onUseAnotherAccount: {
                                    withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.85))) {
                                        showSplash = false
                                    }
                                }
                            )
                            .environmentObject(authViewModel)
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
            } else if authViewModel.needsAgeGate {
                // Audit D-01: universal DOB → tier gate. Reached by any authenticated
                // user without an age profile (notably first-time Google/Apple sign-in),
                // so no auth method can bypass age assurance. Flag-gated upstream.
                AgeGateContainerView()
                    .environmentObject(authViewModel)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .onAppear {
                        dlog("🚦 [LAUNCH] ContentView → AgeGateContainerView appeared")
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
            } else if AmenSimpleModeService.shared.isSimpleModeActive {
                // Simple Mode: full-screen accessibility home — bypasses feed, tab bar, and rails.
                AmenSimpleModeView()
                    .environment(AmenSimpleModeService.shared)
                    .transition(.opacity.animation(.easeOut(duration: 0.2)))
                    .onAppear {
                        dlog("🚦 [LAUNCH] Simple Mode active — showing AmenSimpleModeView")
                        AppReadyStateManager.shared.signalReady()
                    }
            } else {
                // P0 C-3: Account status gate — blocks suspended accounts before main app loads
                AccountStatusGateView {
                    // Main app content
                    mainContent
                }
                .transition(.opacity)
                .onAppear {
                    dlog("🚦 [LAUNCH] mainContent.onAppear fired (hasStartedCoreServices=\(hasStartedCoreServices))")
                    guard hasRealFirebaseUser else {
                        dlog("🚦 [LAUNCH] mainContent blocked — no real Firebase Auth user")
                        hasStartedCoreServices = false
                        AppReadyStateManager.shared.signalReady()
                        return
                    }
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
                            // Initialize MessageSettingsService
                            Task { try? await MessageSettingsService.shared.loadSettings(for: currentUserId) }
                            // Journey engine — warm up so data is ready when ProfileView appears
                            Task { await AmenJourneyEngine.shared.initialize(userId: currentUserId) }
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
        .animation(.easeOut(duration: 0.2), value: AmenSimpleModeService.shared.isSimpleModeActive)
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

                // Context engine ran at scene-active before auth was established;
                // now that auth is confirmed, let it re-attempt location setup.
                AmenContextOrchestrator.shared.resumeAfterAuth()

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
        .onOpenURL { url in
            handleNoteShareURL(url)
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
        .fullScreenCover(item: $noteShareRoute) { route in
            NoteShareViewerView(route: route)
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
    
    private func handleNoteShareURL(_ url: URL) {
        let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "token" || $0.name == "linkToken" })?
            .value

        if url.scheme == "amen", url.host == "note-share" {
            let shareId = url.pathComponents.dropFirst().first ?? ""
            guard !shareId.isEmpty else { return }
            noteShareRoute = NoteShareRoute(shareId: shareId, linkToken: token)
            return
        }

        if url.host?.contains("amenapp.com") == true {
            let components = url.pathComponents
            guard let markerIndex = components.firstIndex(of: "note-share"),
                  components.indices.contains(markerIndex + 1)
            else { return }
            noteShareRoute = NoteShareRoute(shareId: components[markerIndex + 1], linkToken: token)
        }
    }

    @ViewBuilder
    private var selectedTabView: some View {
        // ── SabbathMode gate (additive — takes precedence over Shabbat gate when active) ──
        // state == .active  → show SabbathWindowView (full-screen, gate enforced)
        // state == .steppedOut → normal nav + SabbathBanner at top
        // state == .inactive   → fall through to existing Shabbat gate check
        if sabbathService.currentState == .active {
            ZStack(alignment: .top) {
                SabbathWindowView(service: sabbathService) { surface in
                    // Mark surface used (safety surfaces silently excluded by service)
                    Task { await sabbathService.markSurfaceUsed(surface) }
                    // Navigate to the surface view
                    sabbathCurrentDest = sabbathNavDestination(for: surface)
                }
                .id("sabbathModeGate")
            }
            .fullScreenCover(item: $sabbathCurrentDest) { dest in
                sabbathDestinationView(
                    for: dest,
                    selectedTab: $viewModel.selectedTab,
                    dismiss: { sabbathCurrentDest = nil }
                )
            }
        } else if sabbathService.currentState == .steppedOut {
            // Normal navigation with persistent banner — no gate restriction.
            // SabbathBanner persists at the top until midnight (routing contract).
            VStack(spacing: 0) {
                SabbathBanner(steppedOutAt: {
                    if let ms = sabbathService.currentSession?.steppedOutAt {
                        return Date(timeIntervalSince1970: ms / 1000)
                    }
                    return Date()
                }())
                allTabsZStack
            }
        } else if SundayChurchFocusManager.shared.shouldGateFeature() && !isAllowedDuringChurchFocus(viewModel.selectedTab) {
            // ✅ Existing Shabbat Mode gate (unchanged)
            SundayChurchFocusGateView(selectedTab: $viewModel.selectedTab)
                .id("shabbatModeGate")
                .animation(nil, value: viewModel.selectedTab)
        } else {
            allTabsZStack
        }
    }

    /// All 8 tab views — shared by normal navigation and steppedOut banner path.
    /// Extracted to avoid duplicating the large ZStack in selectedTabView.
    @ViewBuilder
    private var allTabsZStack: some View {
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
                    Group {
                        if #available(iOS 26.0, *) {
                            ONENavigationShell()
                        } else {
                            SpiritualInboxView()
                        }
                    }
                    .id("hub")
                    .task {
                        NotificationAggregationService.shared.updateCurrentScreen(.messages)
                        BadgeCountManager.shared.clearMessages()
                    }
                }

                keepMountedTab(isActive: viewModel.selectedTab == 3) {
                    ResourcesView()
                        .id("resources")
                        .task {
                            NotificationAggregationService.shared.updateCurrentScreen(.none)
                        }
                }

                keepMountedTab(isActive: viewModel.selectedTab == 4) {
                    AmenPulseView()
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
                            guard let uid = Auth.auth().currentUser?.uid else { return }
                            NotificationAggregationService.shared.updateCurrentScreen(.profile(userId: uid))
                        }
                }

                keepMountedTab(isActive: viewModel.selectedTab == 6) {
                    AmenConnectSpacesHubView()
                        .id("spaces")
                        .task {
                            NotificationAggregationService.shared.updateCurrentScreen(.none)
                        }
                }

                keepMountedTab(isActive: viewModel.selectedTab == 7) {
                    // Amen Pulse — bounded daily surface. Gated by Remote Config
                    // (amen_pulse_enabled, default OFF); falls back to the existing
                    // Intelligence Brief until the Pulse pipeline is deployed + verified.
                    Group {
                        if featureFlags.amenPulseEnabled {
                            AmenPulseSurfaceView()
                                .id("amenPulse")
                        } else {
                            WhatNeedsAttentionView()
                                .id("intelligence")
                        }
                    }
                    .task {
                        NotificationAggregationService.shared.updateCurrentScreen(.none)
                    }
                }
            }
            .animation(nil, value: viewModel.selectedTab)
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
        // Tab 7 = Intelligence Brief (spiritual discernment — appropriate during church focus)
        // All other tabs are restricted
        return tab == 3 || tab == 5 || tab == 7
    }
    
    private var mainContentBody: some View {
        ZStack {
            // Main content (takes full screen)
            // Accessibility Intelligence Layer — global Calm Mode (C13) + larger touch
            // targets (C9). Both are no-ops unless enabled in the user's a11y profile.
            selectedTabView
                .ailCalmMode()
                .ailTouchTarget()

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
                    .padding(.bottom, 110) // just above tab bar (pill 62 + compose overflow 28 + gap 20)
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
            // Reserve the exact floating chrome footprint so content never sits under it.
            Color.clear
                .frame(height: bottomChromeReservedHeight)
                .animation(.easeOut(duration: 0.25), value: bottomChromeReservedHeight)
        }
        .overlay(alignment: .bottom) {
            // Always render tab bar, move it offscreen when keyboard appears
            AMENTabBar(
                selectedTab: $viewModel.selectedTab,
                badges: $tabBarBadges,
                onCompose: {
                    tabScrollBridge.expand()
                    // Audience-First: show the audience picker before opening the composer.
                    // The picker's callback sets selectedAudience + selectedPostCategory,
                    // then sets showCreatePost = true so the glass sheet opens.
                    withAnimation(.amenSpringStandard) {
                        showAudiencePicker = true
                    }
                },
                onCameraOS: {
                    showCameraOS = true
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
            VStack(spacing: 10) {
                // Audio mini player bar — shown during speech playback
                if AMENFeatureFlags.shared.audioNarrationEnabled {
                    AudioMiniPlayerBar()
                }

                // Spiritual OS — hidden on Resources so crisis/support flows stay human-first.
                if shouldShowAssistantBar {
                    AmenAssistantBarOverlay(coordinator: assistantCoordinator)
                }
            }
            .padding(.bottom, showTabBar ? 108 : 12)
            .animation(.easeOut(duration: 0.25), value: shouldShowAssistantBar)
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
            if showFTUE {
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
        // CameraOS is default-off until rules/index coverage and runtime privacy review pass.
        .fullScreenCover(isPresented: Binding(
            get: { showCameraOS && featureFlags.cameraOSEnabled },
            set: { showCameraOS = $0 }
        )) {
            AmenCameraOSHubView(
                onMediaCaptured: { _, _ in showCameraOS = false },
                onPrayerCaptured: { _ in showCameraOS = false },
                onDismiss: { showCameraOS = false }
            )
        }
        // Berean Conversion Menu — convert a Berean AI capture into a post, prayer, study, etc.
        .sheet(isPresented: $showBereanConversionMenu) {
            let placeholder = BereanCapture(
                id: UUID().uuidString,
                sourceType: .answer,
                content: "",
                scriptureRefs: [],
                studyOutlinePoints: [],
                capturedAt: Date()
            )
            AmenBereanConversionMenu(capture: placeholder) {
                showBereanConversionMenu = false
            }
        }
        // Creator Kit — AI-powered content drafting for creators.
        .sheet(isPresented: $showCreatorKit) {
            NavigationStack {
                AmenCreatorKitHome()
            }
        }
        // Audience-First picker — shown before the compose editor opens via the compose button.
        // After selection the picker closes itself and fires the callback below.
        // Space audience: the picker handles the sub-Space selection internally and passes
        // AmenAudienceMetadata (spaceId, spaceName, spaceType) back here.
        .sheet(isPresented: $showAudiencePicker) {
            AmenAudienceFirstPickerView(isPresented: $showAudiencePicker) { audience, metadata in
                selectedAudience = audience
                selectedAudienceMetadata = metadata
                selectedPostCategory = audience.suggestedPostCategory ?? .openTable
                withAnimation(.amenSpringStandard) {
                    showCreatePost = true
                }
            }
        }
        // Contextual glass sheet — emerges from the compose button with staged content reveal.
        // CreatePostView receives the audience-informed category. selectedAudience + metadata
        // are stored on ContentView for downstream wiring into the Firestore post document.
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
        .environmentObject(contextManager)  // Spiritual OS — Context Engine (Agent H)
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
            guard hasRealFirebaseUser else {
                dlog("🚦 [TAB] mainContent task skipped — no real Firebase Auth user")
                return
            }

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
        // Berean Daily Formation — full-screen morning briefing (opened via "Daily Devotion" quick action)
        .fullScreenCover(isPresented: $showBereanDailyFormation) {
            BereanDailyFormationView()
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
                                        showBereanDailyFormation = true
                                    }
                                }
                            )

                            Divider()
                                .background(Color(white: 0.2))

                            BereanQuickActionButton(
                                icon: "arrow.triangle.2.circlepath",
                                title: "Convert Capture",
                                delay: 0.15,
                                action: {
                                    HapticManager.impact(style: .light)
                                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.85))) {
                                        showBereanQuickActions = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        showBereanConversionMenu = true
                                    }
                                }
                            )

                            if AMENFeatureFlags.shared.amenCreatorKitEnabled {
                                Divider()
                                    .background(Color(white: 0.2))

                                BereanQuickActionButton(
                                    icon: "wand.and.stars",
                                    title: "Creator Kit",
                                    delay: 0.2,
                                    action: {
                                        HapticManager.impact(style: .light)
                                        withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.85))) {
                                            showBereanQuickActions = false
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                            showCreatorKit = true
                                        }
                                    }
                                )
                            }
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

// MARK: - AccountStatusGateView
// P0 C-3: Blocks suspended/banned accounts from reaching main app content.
// Reads users/{uid}/moderation subcollection — if 3+ active strikes or an active "ban",
// shows an immovable wall with an appeal link. Otherwise passes straight through.

private struct AccountStatusGateView<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var isSuspended = false
    @State private var checked = false

    var body: some View {
        Group {
            if !checked {
                Color.clear
                    .task { await checkStatus() }
            } else if isSuspended {
                AccountSuspendedWallView()
            } else {
                content
            }
        }
    }

    private func checkStatus() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            checked = true
            return
        }
        do {
            let snap = try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("moderation")
                .whereField("status", isEqualTo: "active")
                .getDocuments()

            let docs = snap.documents.map { $0.data() }
            let hasBan = docs.contains { ($0["type"] as? String) == "ban" }
            let strikes = docs.filter { ($0["type"] as? String) == "strike" }.count
            isSuspended = hasBan || strikes >= 3
        } catch {
            // Network failure → don't block the user; fail open
        }
        checked = true
    }
}

private struct AccountSuspendedWallView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "xmark.shield.fill")
                .font(.systemScaled(56, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Text("Account Suspended")
                    .font(.title2.weight(.semibold))
                Text("Your account has been suspended due to repeated Community Guidelines violations. You may submit an appeal through the AMEN support portal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button("Learn More") {
                if let url = URL(string: "https://amenapp.com/support/appeals") {
                    UIApplication.shared.open(url)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: Capsule())

            Spacer()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
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

// Environment keys are defined in ContentViewEnvironmentKeys.swift

// P0 FIX: Using existing ScrollOffsetPreferenceKey from PeopleDiscoveryView
// (No need to redefine - already exists globally)

// P0 FIX: Removed UIView.findScrollView extension - no longer needed with PreferenceKey approach

