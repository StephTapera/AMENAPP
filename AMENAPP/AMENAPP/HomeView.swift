import SwiftUI
import FirebaseAuth

// MARK: - Scroll offset tracker (iOS 18 availability shim)

private struct ScrollOffsetTracker: ViewModifier {
    let action: (CGFloat, CGFloat) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { old, new in
                action(old, new)
            }
        } else {
            content
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
    @StateObject private var digestViewModel = AmenDailyDigestViewModel()
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

    // MARK: - Context Mode (AmenContextOrchestrator)
    @State private var currentContextMode: AmenContextMode = .standard
    @ObservedObject private var bereanMenuManager = BereanContextMenuManager.shared

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
                    .accessibilityLabel("Open feed mode menu")
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
                                    .accessibilityHidden(true)
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
                // Context mode reactive updates
                .onReceive(NotificationCenter.default.publisher(for: .amenContextModeChanged)) { notification in
                    if let mode = notification.object as? AmenContextMode {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            currentContextMode = mode
                        }
                    }
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
                .overlay(alignment: .bottom) {
                    if let payload = bereanMenuManager.activePayload {
                        BereanFloatingActionTray(
                            payload: payload,
                            actions: bereanMenuManager.actions(for: payload),
                            onAction: { action in
                                bereanMenuManager.activate(payload: payload, action: action)
                            }
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.amenSpringStandard, value: bereanMenuManager.activePayload != nil)
                .overlay(alignment: .bottomTrailing) {
                    if AMENFeatureFlags.shared.communityOSUniversalComposerEnabled {
                        AmenComposerLaunchButton(
                            source: ComposerSource.standalone,
                            label: "Create",
                            systemImage: "plus.circle.fill"
                        )
                        .padding(.trailing, 16)
                        .padding(.bottom, 90)  // above tab bar
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

                    // Spiritual OS — Daily Digest (Agent A, gated by AppStorage flag)
                    AmenDailyDigestView(
                        viewModel: digestViewModel,
                        userId: Auth.auth().currentUser?.uid ?? ""
                    )

                    // Spiritual OS — Context Mode Banners
                    contextModeBanner

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
            // Native scroll offset tracking — does not replace SwiftUI's internal UIScrollViewDelegate
            // ✅ PERFORMANCE FIX: Throttle scroll updates to reduce lag
            .modifier(ScrollOffsetTracker { _, newOffset in
                handleScroll(offset: -newOffset)
            })
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

    // MARK: - Context Mode Banner

    @ViewBuilder
    private var contextModeBanner: some View {
        switch currentContextMode {
        case .driving:
            DrivingModeBanner()
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
        case .church:
            SundayModeCalloutBanner()
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
        case .event:
            if let space = AmenContextOrchestrator.shared.eventCheckInSpace {
                EventCheckInBanner(spaceName: space.name, spaceId: space.spaceId)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        case .travel:
            TravelModeBanner()
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
        case .standard:
            EmptyView()
        }
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
