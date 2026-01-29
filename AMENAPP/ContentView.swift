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

struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel
    @StateObject private var authViewModel: AuthenticationViewModel
    @StateObject private var messagingCoordinator: AMENAPP.MessagingCoordinator
    @State private var showCreatePost: Bool
    
    init() {
        // Initialize property wrappers - default to HomeView (tab 0) to show OpenTable
        _viewModel = StateObject(wrappedValue: ContentViewModel())
        _authViewModel = StateObject(wrappedValue: AuthenticationViewModel())
        _messagingCoordinator = StateObject(wrappedValue: AMENAPP.MessagingCoordinator.shared)
        _showCreatePost = State(initialValue: false)
        
        // Make tab bar smaller and more compact
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor.systemBackground
        
        // Reduce tab bar height by adjusting insets
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.secondaryLabel
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor.label
        
        // Remove titles to make it more compact
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 0)]
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 0)]
        
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
                    .fullScreenCover(isPresented: $authViewModel.showWelcomeValues) {
                        WelcomeValuesView()
                            .onDisappear {
                                authViewModel.dismissWelcomeValues()
                            }
                    }
                    .fullScreenCover(isPresented: $authViewModel.showAppTutorial) {
                        AppTutorialView()
                            .onDisappear {
                                authViewModel.dismissAppTutorial()
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
                    }
            }
        }
        .onChange(of: authViewModel.isAuthenticated) { oldValue, newValue in
            print("🔔 ContentView: isAuthenticated changed from \(oldValue) to \(newValue)")
        }
        .onChange(of: authViewModel.needsOnboarding) { oldValue, newValue in
            print("🔔 ContentView: needsOnboarding changed from \(oldValue) to \(newValue)")
        }
        .onChange(of: messagingCoordinator.shouldOpenMessagesTab) { oldValue, newValue in
            if newValue {
                print("💬 Opening Messages tab from notification")
                viewModel.selectedTab = 1  // Switch to Messages tab
            }
        }
    }
    
    @ViewBuilder
    private var selectedTabView: some View {
        // ✅ Tab Pre-loading for Performance
        // All views are kept in memory but only the selected one is visible
        // This provides instant tab switching with no loading delay
        ZStack {
            HomeView()
                .id("home")
                .opacity(viewModel.selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(viewModel.selectedTab == 0)
            
            MessagesView()
                .id("messages")
                .environmentObject(messagingCoordinator)
                .opacity(viewModel.selectedTab == 1 ? 1 : 0)
                .allowsHitTesting(viewModel.selectedTab == 1)
            
            ResourcesView()
                .id("resources")
                .opacity(viewModel.selectedTab == 3 ? 1 : 0)
                .allowsHitTesting(viewModel.selectedTab == 3)
            
            ProfileView()
                .environmentObject(authViewModel)
                .id("profile")
                .opacity(viewModel.selectedTab == 4 ? 1 : 0)
                .allowsHitTesting(viewModel.selectedTab == 4)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedTab)
    }
    
    private var mainContent: some View {
        ZStack {
            // Main content
            selectedTabView
            
            // Custom compact tab bar
            VStack {
                Spacer()
                
                CompactTabBar(selectedTab: $viewModel.selectedTab, showCreatePost: $showCreatePost)
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showCreatePost) {
            CreatePostView()
        }
        .onAppear {
            // Ensure we start on Home tab (OpenTable view)
            viewModel.selectedTab = 0
            viewModel.checkAuthenticationStatus()
            
            // Setup push notifications
            Task {
                await setupPushNotifications()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Handle app becoming active
            authViewModel.checkAuthenticationStatus()
        }
    }
    
    // MARK: - Push Notification Setup
    
    private func setupPushNotifications() async {
        let pushManager = PushNotificationManager.shared
        
        // Check if already granted
        let alreadyGranted = await pushManager.checkNotificationPermissions()
        
        if alreadyGranted {
            // Setup FCM token
            await MainActor.run {
                pushManager.setupFCMToken()
            }
            print("✅ Push notifications already enabled")
        } else {
            // Request permission after a short delay (don't overwhelm user on launch)
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            let granted = await pushManager.requestNotificationPermissions()
            
            if granted {
                await MainActor.run {
                    pushManager.setupFCMToken()
                }
                print("✅ Push notifications enabled")
            } else {
                print("⚠️ Push notifications denied")
            }
        }
        
        // Start listening to notifications
        await MainActor.run {
            NotificationService.shared.startListening()
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
}

// MARK: - Compact Tab Bar (Minimal Frosted Glass Design with Center Create Button)
struct CompactTabBar: View {
    @Binding var selectedTab: Int
    @Binding var showCreatePost: Bool
    @StateObject private var messagingService = FirebaseMessagingService.shared
    @State private var previousUnreadCount: Int = 0
    @State private var badgePulse: Bool = false
    
    let leftTabs: [(icon: String, tag: Int)] = [
        ("house.fill", 0),
        ("message.fill", 1)
    ]
    
    let rightTabs: [(icon: String, tag: Int)] = [
        ("books.vertical.fill", 3),
        ("person.fill", 4)
    ]
    
    // Computed property for total unread count
    private var totalUnreadCount: Int {
        messagingService.conversations.reduce(0) { $0 + $1.unreadCount }
    }
    
    var body: some View {
        ZStack {
            // Main Tab Bar Container - Minimal Frosted Glass
            HStack(spacing: 0) {
                // Left tabs
                ForEach(leftTabs, id: \.tag) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = tab.tag
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(selectedTab == tab.tag ? .primary : .secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .scaleEffect(selectedTab == tab.tag ? 1.05 : 1.0)
                            
                            // 🔴 Unread dot for Messages tab
                            if tab.tag == 1 && totalUnreadCount > 0 {
                                UnreadDot(pulse: badgePulse)
                                    .offset(x: 10, y: 2)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Spacer for center button
                Spacer()
                    .frame(width: 64)
                
                // Right tabs
                ForEach(rightTabs, id: \.tag) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = tab.tag
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(selectedTab == tab.tag ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .scaleEffect(selectedTab == tab.tag ? 1.05 : 1.0)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .frame(height: 44)
            .background(
                ZStack {
                    // Frosted glass effect
                    Capsule()
                        .fill(.ultraThinMaterial)
                    
                    // Subtle inner shadow for depth
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Clean border
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
                }
            )
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            .padding(.horizontal, 40)
            
            // Center Create Button - Minimal Frosted Circle
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    showCreatePost = true
                }
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            } label: {
                ZStack {
                    // Frosted glass circle
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 48, height: 48)
                    
                    // Subtle gradient overlay
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    // Clean border
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.5),
                                    Color.white.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                        .frame(width: 48, height: 48)
                    
                    // Plus icon
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
        }
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
        .onAppear {
            previousUnreadCount = totalUnreadCount
        }
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
            
            // Main dot
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 1.5)
                )
                .shadow(color: .red.opacity(0.5), radius: 3, y: 1)
                .scaleEffect(pulse ? 1.2 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pulse)
        }
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var notificationService = NotificationService.shared
    @State private var isCategoriesExpanded = false
    @State private var showNotifications = false
    @State private var showSearch = false
    @State private var showBereanAssistant = false
    @State private var showAdminCleanup = false
    @State private var showMigrationPanel = false  // NEW: Migration panel
    @State private var tapCount = 0
    @State private var notificationBadgePulse = false
    
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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Expandable Category Pills - perfectly centered and aligned
                    if isCategoriesExpanded {
                        HStack {
                            Spacer()
                            HStack(spacing: 12) {
                                ForEach(viewModel.categories, id: \.self) { category in
                                    CategoryPill(
                                        title: category,
                                        isSelected: viewModel.selectedCategory == category
                                    ) {
                                        viewModel.selectCategory(category)
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            isCategoriesExpanded = false
                                        }
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                    }
                    
                    // Dynamic Content Based on Selected Category
                    Group {
                        switch viewModel.selectedCategory {
                        case "#OPENTABLE":
                            OpenTableView()
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        case "Testimonies":
                            TestimoniesView()
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        case "Prayer":
                            PrayerView()
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        default:
                            OpenTableView()
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: viewModel.selectedCategory)
                }
                .padding(.vertical)
            }
            .navigationTitle("AMEN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Berean AI Assistant Button
                    BereanAssistantButton {
                        showBereanAssistant = true
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Button {
                        // Normal tap - expand categories
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isCategoriesExpanded.toggle()
                        }
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
                    HStack(spacing: 12) {
                        Button {
                            showSearch = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        
                        Button {
                            showNotifications = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.primary)
                                
                                // Notification badge - only shows if there are unread notifications
                                if notificationService.unreadCount > 0 {
                                    NotificationBadge(
                                        count: notificationService.unreadCount,
                                        pulse: notificationBadgePulse
                                    )
                                    .offset(x: 6, y: -6)
                                }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsView()
            }
            .fullScreenCover(isPresented: $showSearch) {
                SearchView()
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
}

// MARK: - Berean Assistant Button

struct BereanAssistantButton: View {
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            action()
        }) {
            ZStack {
                // Minimal circle background
                Circle()
                    .fill(Color.black.opacity(0.05))
                    .frame(width: 36, height: 36)
                
                // Bible study icon - minimal and clean
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.black)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(isPressed ? 0.90 : 1.0)
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
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, adaptivePadding)
                .padding(.vertical, 12)
                .lineLimit(1)
                .background(
                    ZStack {
                        // Liquid glass effect
                        Capsule()
                            .fill(.ultraThinMaterial)
                        
                        // Subtle white gradient overlay
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Black border - more prominent when selected
                        Capsule()
                            .strokeBorder(
                                Color.black.opacity(isSelected ? 0.4 : 0.15),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
                )
                .shadow(
                    color: .black.opacity(isSelected ? 0.15 : 0.08),
                    radius: isSelected ? 12 : 8,
                    y: isSelected ? 4 : 2
                )
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
    
    private var adaptiveFontSize: CGFloat {
        // Adjust font size based on horizontal size class
        switch horizontalSizeClass {
        case .compact:
            return 13  // iPhone portrait
        default:
            return 14  // iPad or iPhone landscape
        }
    }
    
    private var adaptivePadding: CGFloat {
        // Adjust horizontal padding
        switch horizontalSizeClass {
        case .compact:
            return 16
        default:
            return 20
        }
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

// MARK: - Smart Community Card (Enhanced with better colors and animations)

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
            VStack(alignment: .leading, spacing: 8) {
                // Icon with smart glow
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 34, height: 34)
                        .blur(radius: 5)
                    
                    Circle()
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle()
                                .stroke(iconColor.opacity(0.3), lineWidth: 1.5)
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .symbolEffect(.bounce, value: isPressed)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(.black)
                    
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 10))
                        .foregroundStyle(.black.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 90)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(accentColor.opacity(0.25), lineWidth: 1.5)
                    )
                    .shadow(color: accentColor.opacity(0.15), radius: 8, y: 3)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
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

struct TestimonyCategory: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let backgroundColor: Color
    
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
            .background(
                Capsule()
                    .fill(isFollowing ? Color.clear : Color.black)
                    .overlay(
                        Capsule()
                            .stroke(isFollowing ? Color.secondary.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .glassEffect(.regular.interactive())
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

// MARK: - Category Views

struct OpenTableView: View {
    @StateObject private var postsManager = PostsManager.shared
    @State private var showTopIdeas = false
    @State private var showSpotlight = false
    @State private var isRefreshing = false
    
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
                
                // Community Section - Enhanced with smart colors
                VStack(alignment: .leading, spacing: 12) {
                    Text("Community")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .padding(.horizontal)
                    
                    HStack(spacing: 12) {
                        SmartCommunityCard(
                            icon: "star.fill",
                            iconColor: Color(red: 1.0, green: 0.84, blue: 0.0), // Gold
                            title: "Top Ideas",
                            subtitle: "This Week",
                            backgroundColor: Color(red: 1.0, green: 0.98, blue: 0.92),
                            accentColor: Color(red: 1.0, green: 0.84, blue: 0.0)
                        ) {
                            showTopIdeas = true
                        }
                        
                        SmartCommunityCard(
                            icon: "sparkles",
                            iconColor: Color(red: 0.6, green: 0.5, blue: 1.0), // Soft purple
                            title: "Spotlight",
                            subtitle: "Featured",
                            backgroundColor: Color(red: 0.95, green: 0.94, blue: 1.0),
                            accentColor: Color(red: 0.6, green: 0.5, blue: 1.0)
                        ) {
                            showSpotlight = true
                        }
                    }
                    .padding(.horizontal)
                }
                .sheet(isPresented: $showTopIdeas) {
                    TopIdeasView()
                }
                .sheet(isPresented: $showSpotlight) {
                    SpotlightView()
                }
                
                // Trending Section - Collapsible
                CollapsibleTrendingSection()
                
                // Feed Section - Dynamic posts from PostsManager
                VStack(spacing: 16) {
                    ForEach(postsManager.openTablePosts, id: \.id) { post in
                        PostCard(
                            post: post,
                            isUserPost: isCurrentUserPost(post) // Check if post belongs to current user
                        )
                    }
                    
                    // Show empty state if no posts
                    if postsManager.openTablePosts.isEmpty {
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
    @State private var isExpanded = true
    @State private var currentIndex = 0
    let timer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with expand/collapse button
            Button {
                withAnimation(.smooth(duration: 0.3)) {
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
            
            // Premium Trending Cards - Smaller & More Refined
            if isExpanded {
                TabView(selection: $currentIndex) {
                    SmartTrendingCard(
                        icon: "brain.head.profile",
                        iconColor: Color(red: 0.4, green: 0.7, blue: 1.0),
                        title: "AI & Faith",
                        subtitle: "267 discussions",
                        backgroundColor: Color(red: 0.4, green: 0.7, blue: 1.0)
                    )
                    .tag(0)
                    
                    SmartTrendingCard(
                        icon: "shield.checkered",
                        iconColor: Color(red: 0.4, green: 0.85, blue: 0.7),
                        title: "Tech Ethics",
                        subtitle: "189 discussions",
                        backgroundColor: Color(red: 0.4, green: 0.85, blue: 0.7)
                    )
                    .tag(1)
                    
                    SmartTrendingCard(
                        icon: "lightbulb.fill",
                        iconColor: Color(red: 1.0, green: 0.7, blue: 0.4),
                        title: "Startups",
                        subtitle: "342 discussions",
                        backgroundColor: Color(red: 1.0, green: 0.7, blue: 0.4)
                    )
                    .tag(2)
                    
                    SmartTrendingCard(
                        icon: "book.fill",
                        iconColor: Color(red: 0.6, green: 0.5, blue: 1.0),
                        title: "Scripture",
                        subtitle: "524 discussions",
                        backgroundColor: Color(red: 0.6, green: 0.5, blue: 1.0)
                    )
                    .tag(3)
                    
                    SmartTrendingCard(
                        icon: "flame.fill",
                        iconColor: Color(red: 1.0, green: 0.6, blue: 0.7),
                        title: "Hot Takes",
                        subtitle: "412 discussions",
                        backgroundColor: Color(red: 1.0, green: 0.6, blue: 0.7)
                    )
                    .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(height: 100)
                .onReceive(timer) { _ in
                    withAnimation(.easeInOut(duration: 0.5)) {
                        currentIndex = (currentIndex + 1) % 5
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            }
        }
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
    @State private var selectedTimeframe: IdeaTimeframe = .week
    @State private var selectedCategory: IdeaCategory = .all
    @State private var showFilters = false
    
    enum IdeaTimeframe: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        case allTime = "All Time"
    }
    
    enum IdeaCategory: String, CaseIterable {
        case all = "All Ideas"
        case ai = "AI & Tech"
        case ministry = "Ministry"
        case business = "Business"
        case creative = "Creative"
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .ai: return "brain.head.profile"
            case .ministry: return "hands.sparkles"
            case .business: return "briefcase"
            case .creative: return "paintbrush"
            }
        }
        
        var color: Color {
            switch self {
            case .all: return .gray
            case .ai: return .blue
            case .ministry: return .purple
            case .business: return .green
            case .creative: return .orange
            }
        }
    }
    
    var topIdeas: [TopIdea] {
        [
            // Sample ideas will be replaced with real data from Firebase
        ].filter { idea in
            selectedCategory == .all || idea.category == selectedCategory
        }
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
                                ForEach(IdeaCategory.allCases, id: \.self) { category in
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedCategory = category
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
                    VStack(spacing: 16) {
                        ForEach(topIdeas) { idea in
                            TopIdeaCard(idea: idea)
                        }
                    }
                    .padding(.horizontal)
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
        }
    }
}

// MARK: - Top Idea Model

struct TopIdea: Identifiable {
    let id = UUID()
    let rank: Int
    let authorName: String
    let timeAgo: String
    let content: String
    let lightbulbCount: Int
    let commentCount: Int
    let category: TopIdeasView.IdeaCategory
    let badges: [String]
}

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
            GlassEffectContainer(spacing: 12) {
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
                    .glassEffectID("lightbulb", in: glassNamespace)
                    
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
                    .glassEffectID("comment", in: glassNamespace)
                    
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
                .frame(width: count > 9 ? 18 : 14, height: 14)
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

#Preview {
    ContentView()
}
