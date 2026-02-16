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
    @StateObject private var appUsageTracker = AppUsageTracker.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @ObservedObject private var messagingService = FirebaseMessagingService.shared
    @State private var showCreatePost: Bool
    @State private var showPostSuccessToast = false
    @State private var postSuccessCategory: String = ""
    @State private var savedSearchObserver: NSObjectProtocol?
    @State private var postSuccessObserver: NSObjectProtocol?
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
            if !authViewModel.isAuthenticated {
                // Show sign-in view - pass the authViewModel so it's shared!
                SignInView()
                    .environmentObject(authViewModel)
                    .onAppear {
                        print("🔍 ContentView: Showing SignInView")
                        print("   - isAuthenticated: \(authViewModel.isAuthenticated)")
                        print("   - needsOnboarding: \(authViewModel.needsOnboarding)")
                    }
            } else if authViewModel.needsUsernameSelection {
                // Show username selection for social sign-in users (before onboarding)
                UsernameSelectionView()
                    .environmentObject(authViewModel)
                    .onAppear {
                        print("🔍 ContentView: Showing UsernameSelectionView")
                        print("   - isAuthenticated: \(authViewModel.isAuthenticated)")
                        print("   - needsUsernameSelection: \(authViewModel.needsUsernameSelection)")
                    }
                    .onDisappear {
                        // Mark username selection as complete when dismissed
                        authViewModel.completeUsernameSelection()
                    }
            } else if authViewModel.needsOnboarding {
                // Show onboarding for new users
                OnboardingView()
                    .environmentObject(authViewModel)
                    .onAppear {
                        print("🔍 ContentView: Showing OnboardingView")
                        print("   - isAuthenticated: \(authViewModel.isAuthenticated)")
                        print("   - needsOnboarding: \(authViewModel.needsOnboarding)")
                    }
            } else {
                // Main app content
                mainContent
                    .fullScreenCover(isPresented: $authViewModel.showWelcomeToAMEN) {
                        WelcomeToAMENView()
                            .onDisappear {
                                authViewModel.dismissWelcomeToAMEN()
                            }
                    }
                    .onAppear {
                        print("🔍 ContentView: Showing Main App")
                        print("   - isAuthenticated: \(authViewModel.isAuthenticated)")
                        print("   - needsOnboarding: \(authViewModel.needsOnboarding)")
                    }
                    .task {
                        // Run user search migration on first launch (production-ready, silent)
                        await runUserSearchMigrationIfNeeded()
                        
                        // Run post profile image migration on first launch
                        await runPostProfileImageMigrationIfNeeded()
                    }
            }
        }
        .onChange(of: authViewModel.isAuthenticated) { oldValue, newValue in
            print("🔔 ContentView: isAuthenticated changed from \(oldValue) to \(newValue)")
        }
        .onChange(of: authViewModel.needsOnboarding) { oldValue, newValue in
            print("🔔 ContentView: needsOnboarding changed from \(oldValue) to \(newValue)")
        }
        .onChange(of: authViewModel.needsUsernameSelection) { oldValue, newValue in
            print("🔔 ContentView: needsUsernameSelection changed from \(oldValue) to \(newValue)")
        }
        .onChange(of: messagingCoordinator.shouldOpenMessagesTab) { oldValue, newValue in
            if newValue {
                print("💬 Opening Messages tab from notification")
                viewModel.selectedTab = 1  // Switch to Messages tab
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }
    
    @ViewBuilder
    private var selectedTabView: some View {
        // ✅ Tab Pre-loading for Performance
        // All views are kept in memory but only the selected one is visible
        // This provides instant tab switching with no loading delay
        ZStack {
            if viewModel.selectedTab == 0 {
                HomeView()
                    .id("home")
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
            
            if viewModel.selectedTab == 1 {
                MessagesView()
                    .id("messages")
                    .environmentObject(messagingCoordinator)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
            
            if viewModel.selectedTab == 3 {
                ResourcesView()
                    .id("resources")
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
            
            if viewModel.selectedTab == 4 {
                ProfileView()
                    .environmentObject(authViewModel)
                    .id("profile")
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
    }
    
    private var mainContent: some View {
        ZStack {
            // Main content (takes full screen)
            selectedTabView
                .ignoresSafeArea(.all, edges: .bottom)
            
            // Daily limit reached dialog
            if appUsageTracker.showLimitReachedDialog {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                
                DailyLimitReachedDialog()
                    .environmentObject(appUsageTracker)
                    .transition(.scale(scale: 0.95).combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.8)))
                    .zIndex(999)
            }
            
            // Post success toast notification (appears at bottom)
            VStack {
                Spacer()
                
                if showPostSuccessToast {
                    PostSuccessToast(category: postSuccessCategory)
                        .padding(.bottom, 100) // Above tab bar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(998)
                }
            }
        }
        .moderationToast() // ✅ Add moderation toast overlay
        .overlay(alignment: .bottom) {
            // Custom compact tab bar (fixed at bottom)
            CompactTabBar(selectedTab: $viewModel.selectedTab, showCreatePost: $showCreatePost)
                .ignoresSafeArea(.keyboard) // Don't move when keyboard appears
        }
        .sheet(isPresented: $showCreatePost) {
            CreatePostView()
        }
        .environmentObject(appUsageTracker)
        .environmentObject(notificationManager)
        .task {
            // Ensure we start on Home tab (OpenTable view)
            viewModel.selectedTab = 0
            
            // Start tracking app usage
            appUsageTracker.startSession()
            
            // Cache current user's profile data (including profile image URL)
            await UserProfileImageCache.shared.cacheCurrentUserProfile()
            
            // Setup push notifications
            await setupPushNotifications()
            
            // ✅ Start listening to messages for real-time badge updates
            messagingService.startListeningToConversations()
            await messagingService.fetchAndCacheCurrentUserName()
            
            // Setup saved search notification observer
            setupSavedSearchObserver()
            
            // Setup post success notification observer
            setupPostSuccessObserver()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCreatePost)) { _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showCreatePost = true
            }
        }
        .onDisappear {
            // Stop tracking when view disappears
            appUsageTracker.endSession()

            if let savedSearchObserver {
                NotificationCenter.default.removeObserver(savedSearchObserver)
                self.savedSearchObserver = nil
            }

            if let postSuccessObserver {
                NotificationCenter.default.removeObserver(postSuccessObserver)
                self.postSuccessObserver = nil
            }
        }
    }
    
    // MARK: - Push Notification Setup
    
    private func setupPushNotifications() async {
        let pushManager = PushNotificationManager.shared
        
        // Check if already granted
        let alreadyGranted = await pushManager.checkNotificationPermissions()
        
        if alreadyGranted {
            // Setup FCM token (with error handling)
            await MainActor.run {
                pushManager.setupFCMToken()
                print("✅ Push notifications already enabled")
            }
            
            // Setup smart break reminder notification categories
            await SmartBreakReminderService.shared.setupNotificationCategories()
        } else {
            // Request permission after a short delay (don't overwhelm user on launch)
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            let granted = await pushManager.requestNotificationPermissions()
            
            if granted {
                await MainActor.run {
                    pushManager.setupFCMToken()
                    print("✅ Push notifications enabled")
                }
                
                // Setup smart break reminder notification categories
                await SmartBreakReminderService.shared.setupNotificationCategories()
            } else {
                print("⚠️ Push notifications denied")
            }
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
            guard let userInfo = notification.userInfo,
                  let searchId = userInfo["savedSearchId"] as? String,
                  let query = userInfo["query"] as? String else { return }
            
            Task { @MainActor in
                print("📍 Opening saved search: \(query) (ID: \(searchId))")

                // Navigate to search tab
                viewModel.selectedTab = 1

                // Haptic feedback
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            }
        }
    }
    
    // MARK: - Post Success Notification Observer
    
    private func setupPostSuccessObserver() {
        guard postSuccessObserver == nil else { return }

        postSuccessObserver = NotificationCenter.default.addObserver(
            forName: .newPostCreated,
            object: nil,
            queue: .main
        ) { [self] notification in
            guard let userInfo = notification.userInfo,
                  let category = userInfo["category"] as? String else { return }
            
            Task { @MainActor in
                print("🎉 Post created successfully in category: \(category)")

                // Show success toast
                postSuccessCategory = category
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showPostSuccessToast = true
                }

                // Auto-dismiss after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showPostSuccessToast = false
                    }
                }
            }
        }
    }
    
    // MARK: - User Search Migration (Production - Runs Silently)
    
    /// Automatically runs user search migration on first app launch (production-ready, silent)
    private func runUserSearchMigrationIfNeeded() async {
        // Check if migration has already run
        guard !UserDefaults.standard.bool(forKey: "hasRunUserSearchMigration_v1") else {
            print("✅ User search migration already completed")
            return
        }
        
        print("🔧 Running user search migration in background...")
        
        do {
            // Check if migration is needed
            let status = try await UserSearchMigration.shared.checkStatus()
            
            if status.needsMigration > 0 {
                print("📊 Found \(status.needsMigration) users needing migration")
                
                // Run migration silently in background
                try await UserSearchMigration.shared.fixAllUsers()
                
                // Mark as completed
                UserDefaults.standard.set(true, forKey: "hasRunUserSearchMigration_v1")
                
                print("✅ User search migration completed successfully!")
                print("   Total: \(status.totalUsers)")
                print("   Migrated: \(status.needsMigration)")
            } else {
                print("✅ All users already have search fields")
                
                // Mark as completed even if no migration needed
                UserDefaults.standard.set(true, forKey: "hasRunUserSearchMigration_v1")
            }
        } catch {
            // Log error but don't show to user - search fallback will handle it
            print("⚠️ User search migration failed: \(error.localizedDescription)")
            print("   Search will use fallback mechanism")
        }
    }
    
    // MARK: - Post Profile Image Migration (Production - Runs Silently)
    
    /// Automatically runs post profile image migration on first app launch
    private func runPostProfileImageMigrationIfNeeded() async {
        // Check if migration has already run
        guard !UserDefaults.standard.bool(forKey: "hasRunPostProfileImageMigration_v1") else {
            print("✅ Post profile image migration already completed")
            return
        }
        
        print("🔧 Running post profile image migration in background...")
        
        do {
            // Check if migration is needed
            let status = try await PostProfileImageMigration.shared.checkStatus()
            
            if status.needsMigration > 0 {
                print("📊 Found \(status.needsMigration) posts needing profile images")
                
                // Run migration silently in background
                try await PostProfileImageMigration.shared.migrateAllPosts()
                
                // Mark as completed
                UserDefaults.standard.set(true, forKey: "hasRunPostProfileImageMigration_v1")
                
                print("✅ Post profile image migration completed successfully!")
                print("   Total: \(status.totalPosts)")
                print("   Migrated: \(status.needsMigration)")
            } else {
                print("✅ All posts already have profile images")
                
                // Mark as completed even if no migration needed
                UserDefaults.standard.set(true, forKey: "hasRunPostProfileImageMigration_v1")
            }
        } catch {
            // Log error but don't show to user
            print("⚠️ Post profile image migration failed: \(error.localizedDescription)")
            print("   Posts without profile images will show initials instead")
        }
    }
    
    // MARK: - Scene Phase Handler
    
    /// Handle app lifecycle changes for usage tracking
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            print("🟢 App became active")
            appUsageTracker.startSession()
            
        case .inactive:
            print("🟡 App became inactive")
            // Don't end session yet, might be temporary
            
        case .background:
            print("🔴 App went to background")
            appUsageTracker.endSession()
            
        @unknown default:
            break
        }
    }
}

// MARK: - Compact Tab Bar (Smaller with Glassmorphic Design)
struct CompactTabBar: View {
    @Binding var selectedTab: Int
    @Binding var showCreatePost: Bool
    @ObservedObject private var messagingService = FirebaseMessagingService.shared
    @ObservedObject private var postsManager = PostsManager.shared
    @ObservedObject private var userService = UserService.shared
    @State private var previousUnreadCount: Int = 0
    @State private var badgePulse: Bool = false
    @State private var newPostsBadgePulse: Bool = false
    @State private var lastSeenPostTime: Date = Date()
    @Namespace private var tabNamespace

    // ✅ REAL-TIME PROFILE PHOTO UPDATE
    @State private var profilePhotoUpdateTrigger = UUID() // Force AsyncImage to reload
    
    // All tabs in order: Home, Messages, Create (center), Resources, Profile
    let allTabs: [(icon: String, tag: Int)] = [
        ("house.fill", 0),
        ("message.fill", 1),
        ("books.vertical.fill", 3),
        ("person.fill", 4)
    ]
    
    // Computed property for total unread count
    private var totalUnreadCount: Int {
        messagingService.conversations.reduce(0) { $0 + $1.unreadCount }
    }
    
    // Computed property for new posts indicator
    private var hasNewPosts: Bool {
        guard let latestPost = postsManager.allPosts.first else { return false }
        return latestPost.createdAt > lastSeenPostTime
    }
    
    var body: some View {
        HStack(spacing: 8) {  // Reduced from 12 to 8
            ForEach(Array(allTabs.enumerated()), id: \.element.tag) { index, tab in
                // Tab Button
                tabButton(for: tab, isSelected: selectedTab == tab.tag)
                
                // Add Create button after Messages (index 1)
                if index == 1 {
                    createButton
                }
            }
        }
        .fixedSize()
        .padding(.horizontal, 10)  // Reduced from 12 to 10
        .padding(.vertical, 6)     // Reduced from 10 to 6
        .background(glassmorphicBackground)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)  // Reduced from 20 to 16
        .padding(.bottom, 6)       // Reduced from 8 to 6
        .onChange(of: totalUnreadCount) { oldValue, newValue in
            // Trigger pulse animation when unread count increases
            if newValue > oldValue {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                    badgePulse = true
                }
                
                // Haptic feedback for new message
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                // Reset pulse after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation {
                        badgePulse = false
                    }
                }
            }
            previousUnreadCount = newValue
        }
        .onChange(of: postsManager.allPosts.count) { oldValue, newValue in
            // Trigger pulse animation when new posts are added
            if newValue > oldValue && selectedTab != 0 {
                // Only show if user is not on Home tab
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                    newPostsBadgePulse = true
                }
                
                // Haptic feedback for new post
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                // Reset pulse after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation {
                        newPostsBadgePulse = false
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    profilePhotoUpdateTrigger = UUID()
                }

                // Success haptic
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()

                print("🔄 Tab bar: Profile photo updated in real-time to: \(imageURL)")
            }
        }
    }
    
    // MARK: - Enhanced Glassmorphic Background (Ultra Transparent Liquid Glass)

    private var glassmorphicBackground: some View {
        ZStack {
            // Base ultra-thin frosted glass
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(0.7)  // More transparent base

            // Liquid glass gradient overlay (very subtle)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Delicate shimmer highlight at top
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.25),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .padding(0.5)
                .blur(radius: 0.5)

            // Refined border with gradient (thinner and more transparent)
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )

            // Subtle inner glow for depth
            Capsule()
                .stroke(
                    Color.white.opacity(0.08),
                    lineWidth: 1
                )
                .blur(radius: 1)
                .padding(1)
        }
    }
    
    // MARK: - Tab Button (Smaller Icon-Only Pill Style)
    
    @ViewBuilder
    private func tabButton(for tab: (icon: String, tag: Int), isSelected: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selectedTab = tab.tag
            }
            
            // Auto-refresh Home feed when tapping Home button
            if tab.tag == 0 {
                Task {
                    await postsManager.refreshPosts()
                }
                // Mark posts as seen
                lastSeenPostTime = Date()
            }
            
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
        } label: {
            ZStack {
                // Selected state background with glassmorphic effect
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.2),
                                    Color.black.opacity(0.12)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.1),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        )
                        .matchedGeometryEffect(id: "TAB_BACKGROUND", in: tabNamespace)
                }
                
                // Icon with badge OR profile photo for Profile tab
                ZStack(alignment: .topTrailing) {
                    // Profile tab (tag 4) shows user's profile photo if available
                    if tab.tag == 4 {
                        profileTabContent(isSelected: isSelected)
                    } else {
                        // Regular icon for other tabs
                        Image(systemName: tab.icon)
                            .font(.system(size: 19, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .symbolEffect(.bounce, value: isSelected)
                    }
                    
                    // Smart badge for Messages tab (shows count then transitions to dot)
                    if tab.tag == 1 && totalUnreadCount > 0 {
                        SmartMessageBadge(unreadCount: totalUnreadCount, pulse: badgePulse)
                            .offset(x: 8, y: -6)
                    }
                    
                    // Simple dot indicator for Home tab (closer to button)
                    if tab.tag == 0 && hasNewPosts {
                        UnreadDot(pulse: newPostsBadgePulse)
                            .offset(x: 8, y: -6)
                    }
                }
                .frame(width: 46, height: 36)
            }
            .frame(width: 46, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
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
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        isSelected ? Color.primary : Color.secondary.opacity(0.5),
                                        lineWidth: isSelected ? 2 : 1.5
                                    )
                            )
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            .symbolEffect(.bounce, value: isSelected)
                    case .failure(_):
                        // Fallback to icon if image fails to load
                        Image(systemName: "person.fill")
                            .font(.system(size: 19, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .symbolEffect(.bounce, value: isSelected)
                    case .empty:
                        // Show loading placeholder
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 28, height: 28)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.6)
                            )
                    @unknown default:
                        Image(systemName: "person.fill")
                            .font(.system(size: 19, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                }
                .id(profilePhotoUpdateTrigger) // ✅ Force reload when UUID changes
            } else {
                // No profile photo - show default icon
                Image(systemName: "person.fill")
                    .font(.system(size: 19, weight: isSelected ? .semibold : .medium))
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
    
    private var createButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                showCreatePost = true
            }
            let haptic = UIImpactFeedbackGenerator(style: .heavy)
            haptic.impactOccurred()
        } label: {
            ZStack {
                // Subtle outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.primary.opacity(0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 18
                        )
                    )
                    .frame(width: 38, height: 38)  // Reduced from 44 to 38
                
                // Main circular button with glassmorphic touch
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(0.92),
                                Color.primary.opacity(0.78)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle()
                            .stroke(
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
                    )
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.15),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .padding(1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                
                Image(systemName: "pencil")
                    .font(.system(size: 16, weight: .bold))  // Reduced from 18 to 16
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Unread Badge Component

struct UnreadDot: View {
    let pulse: Bool
    
    var body: some View {
        ZStack {
            // Pulse circle background
            if pulse {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 2.0 : 1.0)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 0.6), value: pulse)
            }
            
            // Main dot (no white outline)
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .shadow(color: .red.opacity(0.5), radius: 3, y: 1)
                .scaleEffect(pulse ? 1.2 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pulse)
        }
    }
}

// MARK: - Smart Message Badge (Shows count then transitions to dot)

struct SmartMessageBadge: View {
    let unreadCount: Int
    let pulse: Bool
    @State private var showCount: Bool = true
    
    var body: some View {
        ZStack {
            // Pulse circle background
            if pulse {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: showCount ? 20 : 12, height: showCount ? 20 : 12)
                    .scaleEffect(pulse ? 2.0 : 1.0)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 0.6), value: pulse)
            }
            
            if showCount && unreadCount > 0 {
                // Show count badge
                ZStack {
                    Capsule()
                        .fill(Color.red)
                        .frame(width: max(16, CGFloat(unreadCount > 9 ? 20 : 16)), height: 16)
                    
                    Text("\(min(unreadCount, 9))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .red.opacity(0.5), radius: 3, y: 1)
                .scaleEffect(pulse ? 1.2 : 1.0)
                .transition(.scale.combined(with: .opacity))
            } else {
                // Show simple dot
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: .red.opacity(0.5), radius: 3, y: 1)
                    .scaleEffect(pulse ? 1.2 : 1.0)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            // Show count for 2 seconds, then transition to dot
            if unreadCount > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        showCount = false
                    }
                }
            }
        }
        .onChange(of: unreadCount) { oldValue, newValue in
            // Show count again when unread count increases
            if newValue > oldValue && newValue > 0 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    showCount = true
                }
                
                // Transition back to dot after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        showCount = false
                    }
                }
            }
        }
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var notificationService = NotificationService.shared
    @ObservedObject private var postsManager = PostsManager.shared  // ✅ FIXED: Use @ObservedObject for singletons
    @State private var isCategoriesExpanded = false
    @State private var showNotifications = false
    @State private var showSearch = false
    @State private var showBereanAssistant = false
    @State private var showAdminCleanup = false
    @State private var showMigrationPanel = false  // NEW: Migration panel
    @State private var tapCount = 0
    @State private var notificationBadgePulse = false
    
    // MARK: - Scroll Detection for Dynamic UI
    @State private var scrollOffset: CGFloat = 0
    @State private var lastScrollOffset: CGFloat = 0
    @State private var isScrollingUp = false
    @State private var showToolbar = true
    
    // Helper function for adaptive spacing
    private func adaptiveSpacing(for width: CGFloat) -> CGFloat {
        switch width {
        case ..<350: return 4  // Tight spacing on small screens
        case 350..<400: return 6  // Medium spacing
        default: return 8  // Standard spacing
        }
    }
    
    var body: some View {
        NavigationStack {
            mainScrollContent
                .navigationTitle("AMEN")
                .navigationBarTitleDisplayMode(.inline)
                // GESTURE 1: Hide toolbar on scroll down
                .toolbar(showToolbar ? .visible : .hidden, for: .navigationBar)
                .animation(.easeInOut(duration: 0.3), value: showToolbar)
                .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Berean AI Assistant Button
                    BereanAssistantButton {
                        showBereanAssistant = true
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Button {
                        // Tap AMEN title - toggle categories expand/collapse
                        withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
                            isCategoriesExpanded.toggle()
                            showToolbar = true // Also show toolbar
                        }
                        
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        HStack(spacing: 4) {
                            Text("AMEN")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.up")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .rotationEffect(.degrees(isCategoriesExpanded ? 180 : 0))
                        }
                    }
                    // Secret admin access: tap 5 times quickly
                    .onTapGesture(count: 5) {
                        showAdminCleanup = true
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        // People Discovery button
                        Button {
                            showSearch = true
                        } label: {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                        }

                        // Notifications button with liquid glass glow
                        Button {
                            showNotifications = true
                        } label: {
                            ZStack {
                                // Liquid glass glow effect when unread notifications exist
                                if notificationService.unreadCount > 0 {
                                    Circle()
                                        .fill(
                                            RadialGradient(
                                                colors: [
                                                    Color.blue.opacity(0.3),
                                                    Color.blue.opacity(0.15),
                                                    Color.clear
                                                ],
                                                center: .center,
                                                startRadius: 0,
                                                endRadius: 20
                                            )
                                        )
                                        .frame(width: 40, height: 40)
                                        .blur(radius: 4)
                                        .scaleEffect(notificationBadgePulse ? 1.15 : 1.0)
                                        .opacity(notificationBadgePulse ? 0.8 : 0.5)
                                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: notificationBadgePulse)
                                }
                                
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsView()
            }
            .fullScreenCover(isPresented: $showSearch) {
                PeopleDiscoveryView()
            }
            .fullScreenCover(isPresented: $showBereanAssistant) {
                BereanAIAssistantView()
            }
            .sheet(isPresented: $showAdminCleanup) {
                AdminCleanupView()
            }
            .sheet(isPresented: $showMigrationPanel) {
                UserSearchMigrationView()
            }
            .onChange(of: notificationService.unreadCount) { oldValue, newValue in
                // Trigger pulse animation when notification count increases
                if newValue > oldValue {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                        notificationBadgePulse = true
                    }
                    
                    // Haptic feedback for new notification
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    // Reset pulse after animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation {
                            notificationBadgePulse = false
                        }
                    }
                }
            }
            .onAppear {
                // Start listening to notifications
                notificationService.startListening()
            }
        }
    }
    
    // MARK: - Computed Properties to help type checker
    
    private var mainScrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geometry.frame(in: .named("scroll")).minY
                    )
                }
                .frame(height: 0)
                
                VStack(alignment: .leading, spacing: 0) {
                    // GESTURE 3: Invisible top anchor for scroll-to-top
                    Color.clear
                        .frame(height: 1)
                        .id("top")
                    
                    // Expandable Category Pills - perfectly centered and aligned
                    if isCategoriesExpanded {
                        categoryPillsView
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                    }
                    
                    // Subtle collaboration suggestions (only in OpenTable)
                    if viewModel.selectedCategory == "#OPENTABLE" {
                        SubtleCollaborationSuggestionsView()
                            .padding(.top, 8)
                    }
                    
                    // Dynamic Content Based on Selected Category
                    selectedCategoryView
                }
                .padding(.bottom)
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                handleScrollOffset(value)
            }
            // GESTURE 3: Tap status bar area to scroll to top
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    proxy.scrollTo("top", anchor: .top)
                    showToolbar = true
                }
                
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            }
            .refreshable {
                await refreshCurrentCategory()
            }
        }
    }
    
    // MARK: - Scroll Offset Handler (GESTURE 1 & 2)
    
    private func handleScrollOffset(_ offset: CGFloat) {
        let delta = offset - lastScrollOffset
        lastScrollOffset = offset
        
        // GESTURE 1: Hide toolbar on scroll down
        // Scrolling up (delta > 0) or at top (offset >= -5)
        if delta > 5 || offset >= -5 {
            if !showToolbar {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showToolbar = true
                }
            }
        }
        // Scrolling down (delta < -10)
        else if delta < -10 && offset < -100 {
            if showToolbar {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showToolbar = false
                }
            }
        }
        
        // GESTURE 2: Auto-collapse category pills when scrolling down
        if delta < -30 && offset < -50 {
            if isCategoriesExpanded {
                withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
                    isCategoriesExpanded = false
                }
            }
        }
    }
    
    // MARK: - Refresh Handler
    
    /// Refresh the currently selected category
    private func refreshCurrentCategory() async {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Post notification to refresh the current category
        NotificationCenter.default.post(
            name: Notification.Name("refreshCategory"),
            object: nil,
            userInfo: ["category": viewModel.selectedCategory]
        )
        
        // Wait a moment for the refresh to complete
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        await MainActor.run {
            let successHaptic = UINotificationFeedbackGenerator()
            successHaptic.notificationOccurred(.success)
        }
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
                        withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
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
        Group {
            switch viewModel.selectedCategory {
            case "#OPENTABLE":
                OpenTableView()
                    .id("openTable-\(viewModel.selectedCategory)") // Unique ID to force view update
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            case "Testimonies":
                TestimoniesView()
                    .id("testimonies-\(viewModel.selectedCategory)")
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            case "Prayer":
                PrayerView()
                    .id("prayer-\(viewModel.selectedCategory)")
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            default:
                OpenTableView()
                    .id("openTable-\(viewModel.selectedCategory)")
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
    }
}

// MARK: - Berean Assistant Button

struct BereanAssistantButton: View {
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var isAnimating = false
    
    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            action()
        }) {
            ZStack {
                // Outer glow ring - subtle pulse
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.black.opacity(0.08),
                                Color.black.opacity(0.02),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 22
                        )
                    )
                    .frame(width: 44, height: 44)
                    .scaleEffect(isAnimating ? 1.08 : 1.0)
                    .opacity(isAnimating ? 0.6 : 1.0)
                
                // Main button background with liquid glass effect
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle()
                            .stroke(
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
                    )
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                
                // AMEN "A" Logo - Stylized
                Text("A")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.black,
                                Color.black.opacity(0.85)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .rotationEffect(.degrees(isAnimating ? 2 : 0))
            }
            .scaleEffect(isPressed ? 0.92 : 1.0)
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
        .onAppear {
            // Subtle continuous pulse animation
            withAnimation(
                .easeInOut(duration: 2.5)
                .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
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
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            action()
        }) {
            Text(title)
                .font(.custom("OpenSans-SemiBold", size: adaptiveFontSize))
                .fontWeight(isSelected ? .bold : .semibold)
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
                    .font(.system(size: 20))
                    .foregroundStyle(.black)
                
                Spacer()
                
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(.black)
                
                Text(subtitle)
                    .font(.custom("OpenSans-Regular", size: 11))
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
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            action()
        }) {
            HStack(spacing: 10) {
                // Compact icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .symbolEffect(.bounce, value: isPressed)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 10))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
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
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.black)
                    .frame(height: 40)
                
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 12))
                    .foregroundStyle(.black)
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
                                .font(.system(size: 40))
                                .foregroundStyle(.black)
                        }
                        
                        Text(title)
                            .font(.custom("OpenSans-Bold", size: 28))
                            .foregroundStyle(.black)
                        
                        Text(topicContent.description)
                            .font(.custom("OpenSans-Regular", size: 15))
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
                                    .font(.custom("OpenSans-Bold", size: 22))
                                    .foregroundStyle(.black)
                                
                                Text(stat.0)
                                    .font(.custom("OpenSans-Regular", size: 12))
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
                                    .font(.custom("OpenSans-Bold", size: 16))
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
                                        .font(.custom("OpenSans-Bold", size: 14))
                                }
                                .foregroundStyle(.black)
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
                                        .font(.custom("OpenSans-Bold", size: 14))
                                }
                                .foregroundStyle(.black)
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
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(.black)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(topicContent.relatedTopics, id: \.self) { topic in
                                    Text(topic)
                                        .font(.custom("OpenSans-SemiBold", size: 13))
                                        .foregroundStyle(.black)
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
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(.black)
                            .padding(.horizontal)
                        
                        VStack(spacing: 10) {
                            ForEach(topicContent.resources, id: \.0) { resource in
                                Button {
                                    // Open resource
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(resource.0)
                                                .font(.custom("OpenSans-Bold", size: 14))
                                                .foregroundStyle(.black)
                                            
                                            Text(resource.1)
                                                .font(.custom("OpenSans-Regular", size: 12))
                                                .foregroundStyle(.black.opacity(0.6))
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
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
                    
                    Spacer(minLength: 40)
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
                            .font(.system(size: 28))
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isActive ? .black : .black.opacity(0.5))
                
                if let count = count {
                    Text("\(count)")
                        .font(.custom("OpenSans-SemiBold", size: 11))
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
                .font(.system(size: 14, weight: .medium))
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
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                            dismiss()
                        } label: {
                            Text(emoji)
                                .font(.system(size: 32))
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
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(comment.avatarColor)
                )
            
            VStack(alignment: .leading, spacing: 6) {
                // Author and time
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.primary)
                    
                    Text("•")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                    
                    Text(comment.timeAgo)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                // Comment content
                Text(comment.content)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Comment actions
                HStack(spacing: 16) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            hasAmened.toggle()
                            localAmenCount += hasAmened ? 1 : -1
                            
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "hands.sparkles.fill")
                                .font(.system(size: 11))
                            if localAmenCount > 0 {
                                Text("\(localAmenCount)")
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                            }
                        }
                        .foregroundStyle(hasAmened ? Color(red: 1.0, green: 0.84, blue: 0.0) : .secondary)
                    }
                    
                    Button {
                        // Reply action
                    } label: {
                        Text("Reply")
                            .font(.custom("OpenSans-SemiBold", size: 12))
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.05))
                        )
                }
                
                Spacer()
                
                Text("Comments")
                    .font(.custom("OpenSans-Bold", size: 18))
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
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                self.replyingTo = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
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
                                .font(.custom("OpenSans-SemiBold", size: 11))
                                .foregroundStyle(.white)
                        )
                    
                    // Glass-style text field
                    HStack(spacing: 8) {
                        TextField("Add a comment...", text: $commentText, axis: .vertical)
                            .font(.custom("OpenSans-Regular", size: 15))
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
                                    .font(.system(size: 18))
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
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        isBold.toggle()
                    }
                } label: {
                    Text("B")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(isBold ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(isBold ? Color.black : Color.gray.opacity(0.1))
                        )
                }
                
                // Italic
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
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
                        .font(.system(size: 14))
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
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isBold.toggle()
                }
            } label: {
                Text("B")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(isBold ? .white : .primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isBold ? Color.black : Color.gray.opacity(0.1))
                    )
            }
            
            // Italic
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
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
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
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
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
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
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showReplies.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showReplies ? "chevron.down" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                            Text("\(comment.replies.count) \(comment.replies.count == 1 ? "reply" : "replies")")
                                .font(.custom("OpenSans-SemiBold", size: 13))
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
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                        
                        Text(comment.timeAgo)
                            .font(.custom("OpenSans-Regular", size: 13))
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
                        AsyncImage(url: URL(string: gifURL)) { image in
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
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                hasAmened.toggle()
                                localAmenCount += hasAmened ? 1 : -1
                                
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "hands.sparkles.fill")
                                    .font(.system(size: 13))
                                if localAmenCount > 0 {
                                    Text("\(localAmenCount)")
                                        .font(.custom("OpenSans-SemiBold", size: 13))
                                }
                            }
                            .foregroundStyle(hasAmened ? Color(red: 1.0, green: 0.84, blue: 0.0) : .secondary)
                        }
                        
                        Button {
                            onReply(comment)
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.system(size: 12))
                                Text("Reply")
                                    .font(.custom("OpenSans-SemiBold", size: 13))
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
                                .font(.system(size: 14))
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
                        .font(.custom("OpenSans-Regular", size: 16))
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
                                
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            } label: {
                                AsyncImage(url: URL(string: gifURL)) { image in
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isFollowing.toggle()
                
                let haptic = UIImpactFeedbackGenerator(style: isFollowing ? .medium : .light)
                haptic.impactOccurred()
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
                    .font(.system(size: 10, weight: .bold))
            }
            Text(isFollowing ? "Following" : "Follow")
                .font(.custom("OpenSans-Bold", size: 12))
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

struct OpenTableView: View {
    @ObservedObject private var postsManager = PostsManager.shared
    @StateObject private var feedAlgorithm = HomeFeedAlgorithm.shared
    @State private var showTopIdeas = false
    @State private var showSpotlight = false
    @State private var isRefreshing = false
    @State private var personalizedPosts: [Post] = []
    @State private var hasPersonalized = false // Track if personalization has run
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Section
                VStack(alignment: .leading, spacing: 4) {
                    Text("Where AI meets faith, ideas meet innovation")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text("#OPENTABLE")
                            .font(.custom("OpenSans-Bold", size: 24))
                            .foregroundStyle(.black)
                        
                        Spacer()
                        
                        // Refresh indicator
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }

                        Button {
                            // Discussion action
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.body)
                                .foregroundStyle(.gray)
                        }
                    }
                    
                    Text("AI • Bible & Tech • Business • Ideas")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                // Community Section - Collapsible with Liquid Glass Design
                CollapsibleCommunitySection(
                    showTopIdeas: $showTopIdeas,
                    showSpotlight: $showSpotlight
                )
                
                // Trending Section - Collapsible
                CollapsibleTrendingSection()
                
                // Feed Section - Dynamic posts from PostsManager
                LazyVStack(spacing: 16) {
                    let displayPosts = hasPersonalized && !personalizedPosts.isEmpty ? personalizedPosts : postsManager.openTablePosts

                    ForEach(displayPosts, id: \.firestoreId) { post in
                        PostCard(
                            post: post,
                            isUserPost: isCurrentUserPost(post) // Check if post belongs to current user
                        )
                        .onAppear {
                            // Track view interaction
                            feedAlgorithm.recordInteraction(with: post, type: .view)
                        }
                    }
                    
                    // Show empty state if no posts
                    if postsManager.openTablePosts.isEmpty && !isRefreshing {
                        VStack(spacing: 16) {
                            Image(systemName: "tray")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            
                            Text("No posts yet")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.primary)
                            
                            Text("Be the first to share an idea!")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    }
                }
                .padding(.horizontal)
            }
        }
        .refreshable {
            await refreshOpenTable()
        }
        .task {
            // ✅ Start real-time listener for openTable posts
            FirebasePostService.shared.startListening(category: .openTable)
            
            // Load user interests once
            if !hasPersonalized {
                feedAlgorithm.loadInterests()
                personalizeFeeds()
                hasPersonalized = true
            }
        }
        .onChange(of: postsManager.openTablePosts) { oldValue, newValue in
            // Only re-personalize if there are new posts
            if oldValue.count != newValue.count {
                personalizeFeeds()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.newPostCreated)) { notification in
            // Optimized real-time refresh when new post is created
            if let userInfo = notification.userInfo,
               let category = userInfo["category"] as? String,
               category == Post.PostCategory.openTable.rawValue {
                
                let isOptimistic = userInfo["isOptimistic"] as? Bool ?? false
                
                // Immediate UI feedback for optimistic updates
                if isOptimistic {
                    print("⚡ Optimistic post detected in OpenTable feed")
                    // Posts are already updated via PostsManager
                } else {
                    print("✅ Confirmed post in OpenTable feed")
                    // Haptic feedback only for confirmed posts
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            }
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
    
    // MARK: - Personalization
    
    /// Apply smart algorithm to personalize feed
    private func personalizeFeeds() {
        guard !postsManager.openTablePosts.isEmpty else {
            personalizedPosts = []
            return
        }
        
        // Rank posts using algorithm (optimized to run off main thread)
        Task.detached(priority: .userInitiated) {
            let ranked = await feedAlgorithm.rankPosts(
                postsManager.openTablePosts,
                for: feedAlgorithm.userInterests
            )
            
            await MainActor.run {
                personalizedPosts = ranked
                print("✨ Feed personalized: \(personalizedPosts.count) posts ranked")
            }
        }
    }
    
    // MARK: - Refresh Function
    
    /// Refresh OpenTable posts with pull-to-refresh
    private func refreshOpenTable() async {
        isRefreshing = true
        print("🔄 Refreshing OpenTable posts...")
        
        await postsManager.fetchFilteredPosts(
            for: .openTable,
            filter: "all",
            topicTag: nil
        )
        
        // Haptic feedback on completion
        await MainActor.run {
            isRefreshing = false
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            print("✅ OpenTable posts refreshed!")
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            } label: {
                HStack {
                    Text("Trending")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
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

struct CollapsibleCommunitySection: View {
    @AppStorage("communitySectionExpanded") private var isExpanded = true
    @Binding var showTopIdeas: Bool
    @Binding var showSpotlight: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with expand/collapse button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            } label: {
                HStack {
                    Text("Community")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
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
                        icon: "star.fill",
                        iconColor: Color.white, // White star
                        backgroundGradientTop: Color(red: 0.15, green: 0.18, blue: 0.22), // Deep slate blue-gray
                        backgroundGradientBottom: Color(red: 0.20, green: 0.24, blue: 0.28), // Lighter slate
                        useBurgundyStyle: true,
                        title: "Top Ideas",
                        subtitle: "This Week"
                    ) {
                        showTopIdeas = true
                    }
                    
                    LiquidGlassCommunityCard(
                        icon: "lightbulb.fill",
                        iconColor: Color.white, // White lightbulb
                        backgroundGradientTop: Color(red: 0.75, green: 0.08, blue: 0.12), // Rich red-burgundy
                        backgroundGradientBottom: Color(red: 0.85, green: 0.10, blue: 0.14), // Brighter burgundy
                        useBurgundyStyle: true,
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
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            action()
        }) {
            HStack(spacing: 10) {
                // Icon with color accent
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(useBurgundyStyle ? 0.4 : 0.3))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .symbolEffect(.bounce, value: isPressed)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 10))
                        .foregroundStyle(.white.opacity(useBurgundyStyle ? 0.9 : 0.8))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(useBurgundyStyle ? 0.7 : 0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    // Rich burgundy background with full opacity
                    if useBurgundyStyle {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.thinMaterial)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                backgroundGradientTop ?? Color.black,
                                                backgroundGradientBottom ?? Color.black
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    } else {
                        // Dark frosted glass background (default)
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                (backgroundGradientTop ?? Color.black).opacity(0.7),
                                                (backgroundGradientBottom ?? Color.black).opacity(0.5)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    }
                    
                    // Enhanced color accent overlay for burgundy style
                    if useBurgundyStyle {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        iconColor.opacity(0.12),
                                        iconColor.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        iconColor.opacity(0.2),
                                        iconColor.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    // Glass highlight (top reflection)
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(useBurgundyStyle ? 0.12 : 0.1),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    
                    // Border only for default style (no border for burgundy)
                    if !useBurgundyStyle {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.4),
                                        Color.white.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
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
            
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
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
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: isPressed)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                }
                
                Spacer()
                
                // Premium Arrow
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
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
    @StateObject private var trendingService = TrendingService.shared
    @StateObject private var filteringService = SmartIdeaFilteringService.shared
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
                                    .font(.custom("OpenSans-Bold", size: 32))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.black, .black.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                
                                Text("The brightest ideas from our community")
                                    .font(.custom("OpenSans-Regular", size: 14))
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
                                    .font(.system(size: 40, weight: .semibold))
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
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                                            .font(.custom("OpenSans-SemiBold", size: 13))
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
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                                                .font(.system(size: 10, weight: .semibold))
                                            
                                            Text(category.rawValue)
                                                .font(.custom("OpenSans-SemiBold", size: 12))
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
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Finding the brightest ideas...")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if filteredTopIdeas.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "lightbulb.slash")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("No trending ideas yet")
                                .font(.custom("OpenSans-Bold", size: 18))
                            Text("Be the first to share a brilliant idea!")
                                .font(.custom("OpenSans-Regular", size: 14))
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
                            .font(.system(size: 28))
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
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(idea.authorName)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                    
                    Text(idea.timeAgo)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Badges
                HStack(spacing: 4) {
                    ForEach(idea.badges, id: \.self) { badge in
                        Text(badge)
                            .font(.custom("OpenSans-SemiBold", size: 10))
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
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.primary)
                .lineSpacing(4)
            
            // Interactive Reactions
            GlassEffectContainer {
                HStack(spacing: 12) {
                    // Lightbulb Reaction with Animation
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                            hasLightbulbed.toggle()
                            localLightbulbCount += hasLightbulbed ? 1 : -1
                            isAnimating = true
                        }
                        
                        let haptic = UIImpactFeedbackGenerator(style: hasLightbulbed ? .heavy : .light)
                        haptic.impactOccurred()
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            isAnimating = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            ZStack {
                                // Glow effect when active
                                if hasLightbulbed {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.yellow)
                                        .blur(radius: 8)
                                        .scaleEffect(isAnimating ? 1.5 : 1.0)
                                        .opacity(isAnimating ? 0 : 0.6)
                                }
                                
                                Image(systemName: hasLightbulbed ? "lightbulb.fill" : "lightbulb")
                                    .font(.system(size: 16, weight: .semibold))
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
                                .font(.custom("OpenSans-SemiBold", size: 13))
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showComments.toggle()
                        }
                    }
                    
                    Spacer()
                    
                    // Share Button
                    Button {
                        // Share action
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
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
                    .font(.system(size: count > 9 ? 8 : 9, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            } else {
                Text("99+")
                    .font(.system(size: 7, weight: .bold))
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
}

// MARK: - Post Success Toast (Glassmorphic Design)

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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(categoryInfo.color)
                    .symbolEffect(.bounce, value: isAnimating)
            }
            
            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text("Posted to \(categoryInfo.name)")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
                
                Text("Your post is now live")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
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
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        }
    }
}

#Preview("Post Success Toast - OpenTable") {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            PostSuccessToast(category: "openTable")
                .padding(.bottom, 100)
        }
    }
}

#Preview("Post Success Toast - Prayer") {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            PostSuccessToast(category: "prayer")
                .padding(.bottom, 100)
        }
    }
}

#Preview("Post Success Toast - Testimonies") {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            PostSuccessToast(category: "testimonies")
                .padding(.bottom, 100)
        }
    }
}

#Preview("ContentView") {
    ContentView()
}

