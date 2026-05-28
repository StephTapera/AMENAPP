import SwiftUI
import FirebaseAuth
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
                                AMENLoader.inline
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
                            FeedPostDivider()
                        }
                    }

                    // Loading indicator for pagination
                    if isLoadingMore || firebasePostService.isLoadingMore {
                        HStack {
                            Spacer()
                            AMENLoader.inline
                                .padding(.vertical, 20)
                            Spacer()
                        }
                        .accessibilityLabel("Loading more posts")
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

