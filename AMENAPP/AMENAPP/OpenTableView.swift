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
    @ObservedObject private var featureFlags = AMENFeatureFlags.shared
    @State private var showPersonalizationToast = false
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
    @State private var countingDelayTask: Task<Void, Never>?
    // S3-7: Debounce rapid post-count changes so personalization fires at most once per 500ms.
    @State private var personalizationDebounceTask: Task<Void, Never>?

    // Network error state
    @ObservedObject private var networkMonitor = AMENNetworkMonitor.shared
    @State private var showOfflineBanner = false

    // MARK: - Feed Filter
    @State private var showFeedFilter = false
    @AppStorage("openTable.contentFilter") private var feedContentFilter: String = "all"
    @AppStorage("openTable.feedMode") private var feedMode: String = "personalized"
    @AppStorage("openTable.sortOrder") private var feedSortOrder: String = "newest"

    private var feedSelectionMap: Binding<[String: String]> {
        Binding(
            get: {
                ["main": feedContentFilter, "Feed Mode": feedMode, "Sort": feedSortOrder]
            },
            set: { newMap in
                if let v = newMap["main"]       { feedContentFilter = v }
                if let v = newMap["Feed Mode"]  { feedMode = v }
                if let v = newMap["Sort"]       { feedSortOrder = v }
            }
        )
    }

    private var feedFilterSections: [AmenFilterSection] {
        [
            AmenFilterSection(header: nil, options: [
                AmenFilterOption(id: "all",          label: "All Posts",       icon: "rectangle.stack"),
                AmenFilterOption(id: "testimonies",  label: "Testimonies",     icon: "star"),
                AmenFilterOption(id: "prayer",       label: "Prayer",          icon: "hands.sparkles"),
                AmenFilterOption(id: "following",    label: "Following Only",  icon: "person.2"),
            ]),
            AmenFilterSection(header: "Feed Mode", options: [
                AmenFilterOption(id: "personalized", label: "Personalized",    icon: "wand.and.stars"),
            ]),
            AmenFilterSection(header: "Sort", options: [
                AmenFilterOption(id: "newest",       label: "Newest First",    icon: "arrow.down.circle"),
                AmenFilterOption(id: "chron",        label: "Chronological",   icon: "clock"),
            ]),
        ]
    }

    @Environment(\.tabBarVisible) private var tabBarVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
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

            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            // Header Section (cleaned up - removed grey icon and divider)
                if showHeader {
                    VStack(alignment: .leading, spacing: 4) {
                        
                        HStack {
                            (Text("#")
                                .foregroundStyle(AmenTheme.Colors.amenPurple)
                             + Text("OPENTABLE")
                                .foregroundStyle(Color.primary))
                                .font(AMENFont.bold(24))

                            Spacer()

                            // Refresh indicator
                            if isRefreshing {
                                AMENLoader.inline
                                    .padding(.trailing, 4)
                            }

                            // Feed filter button
                            AmenFilterButton(isShowing: $showFeedFilter)
                        }

                        Text("Gather. Share. Grow.")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // CONTEXTUAL EXPERIENCE BANNER — shown when resolver finds an active experience
                if AMENFeatureFlags.shared.contextualExperiencesEnabled {
                    ExperienceResolverBannerWrapper()
                }

                // Daily Verse Banner — show optimistically while prefs load (both default to true).
                // Only hide after load if the user has explicitly turned it off.
                if !prefsService.isLoaded || (prefsService.preferences.widgetsEnabled && prefsService.preferences.dailyVerseWidgetEnabled) {
                    DailyVerseBanner()
                        .padding(.horizontal)
                        .transition(.opacity.animation(reduceMotion ? .none : .easeIn(duration: 0.2)))
                        .onAppear {
                            dlog("📊 Daily Verse Banner displayed: widgetsEnabled=\(prefsService.preferences.widgetsEnabled), dailyVerseWidgetEnabled=\(prefsService.preferences.dailyVerseWidgetEnabled)")
                        }
                }

                // Feed Composer Row
                FeedComposerRow { showCreatePost = true }
                    .padding(.horizontal)
                    .padding(.top, 4)

                // Feed Section - Dynamic posts from PostsManager (Trending section removed)
                LazyVStack(spacing: 0) {
                    // S3-5: Strip soft-deleted (removed) posts before display.
                    let allPosts = (hasPersonalized && !personalizedPosts.isEmpty ? personalizedPosts : postsManager.openTablePosts)
                        .filter { $0.isEligibleForFeedDisplay }
                    let displayPosts = Array(allPosts.prefix(visiblePostCount))

                    // Skeleton loader during initial data fetch (before first posts arrive)
                    if isInitialLoad && allPosts.isEmpty {
                        PostListSkeletonView(count: 3)
                    } else {
                    // P0 FIX: Use .id (UUID) instead of .firestoreId for stable ForEach identity
                    // firestoreId can change from UUID fallback to real Firebase ID, causing cell rebuilds
                    ForEach(Array(displayPosts.enumerated()), id: \.element.id) { index, post in
                        feedPostItem(post: post, index: index, displayPosts: displayPosts)

                        // "Suggested for you" rail — injected at the index set by the feature
                        // flag (default: after 2nd post, i.e. index == 2). Hidden entirely when
                        // suggestedFollowsEnabled is off in Remote Config.
                        let railIndex = max(0, featureFlags.suggestedRailInsertionIndex - 1)
                        if featureFlags.suggestedFollowsEnabled && index == railIndex {
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
                    withAnimation(reduceMotion ? .none : .easeOut(duration: 0.25)) { isInitialLoad = false }
                }
            }
        }
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.25)) {
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
            countingDelayTask?.cancel()
            countingDelayTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
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
            countingDelayTask?.cancel()
            countingDelayTask = nil
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
                    countingDelayTask?.cancel()
                    countingDelayTask = Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        guard !Task.isCancelled else { return }
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
            
            // PERF FIX: Skip re-personalization on the initial 0→N load event.
            // The .task block already calls personalizeFeeds() after loadInterests().
            // Firing it here too would race the Cloud Run ranking call (3-second timeout)
            // against first paint and cause a concurrent ranked-array replacement that
            // jumps the scroll position. Re-personalize only for subsequent live updates
            // after the initial skeleton has dissolved.
            // S3-7: Debounce so rapid burst writes don't each trigger a Cloud Run call.
            if oldValue != newValue && !isInitialLoad {
                personalizationDebounceTask?.cancel()
                personalizationDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                    guard !Task.isCancelled else { return }
                    personalizeFeeds()
                }
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
        // P2 FIX: When the user follows someone from any screen, re-run feed
        // personalization so the newly followed author's posts get boosted immediately.
        .onReceive(NotificationCenter.default.publisher(for: .followRelationshipChanged)) { _ in
            feedAlgorithm.followingIds = FollowService.shared.following
            if !isInitialLoad { personalizeFeeds() }
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
        .onReceive(NotificationCenter.default.publisher(for: .feedSuggestionsPersonalized)) { _ in
            withAnimation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.75)) {
                showPersonalizationToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.25)) {
                    showPersonalizationToast = false
                }
            }
        }

            // 50% usage banner (top overlay)
            if show50Banner {
                ScrollBudget50Banner()
            }

            // Personalization toast — shown when user follows 3+ people from suggestions
            if showPersonalizationToast {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.amenGold)
                        Text("Your feed is being personalized")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AmenTheme.Colors.amenGold.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(20)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Your feed is being personalized")
            }
        }
        } // end ScrollView
        .refreshable {
            await refreshOpenTable()
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
        // Feed filter dropdown — overlaid top-trailing, above all feed content
        .overlay(alignment: .topTrailing) {
            AmenGlassFilterDropdown(
                sections: feedFilterSections,
                selectionMap: feedSelectionMap,
                isShowing: $showFeedFilter
            )
            // Offset below the header (~96pt accounts for safe area + header height)
            .padding(.top, 96)
            .padding(.trailing, 16)
        }
        .onChange(of: feedContentFilter) { _, newFilter in
            Task { @MainActor in
                await postsManager.fetchFilteredPosts(for: .openTable, filter: newFilter, topicTag: nil)
            }
        }
        .onChange(of: feedMode) { _, _ in
            // Feed mode (personalized/sabbath) is applied by personalizeFeeds() — re-run it.
            if !isInitialLoad { personalizeFeeds() }
        }
        .onChange(of: feedSortOrder) { _, newSort in
            Task { @MainActor in
                await postsManager.fetchFilteredPosts(for: .openTable, filter: newSort, topicTag: nil)
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
        } else {
            Color.clear.frame(height: 0.5)
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

        // S3-4: Capture class instances weakly so the detached task doesn't extend their lifetime.
        personalizationTask = Task.detached(priority: .userInitiated) { [weak feedSession, weak feedAlgorithm] in
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
                await MainActor.run { feedSession?.isSessionComplete = true }
            }

            // 2. Local fallback if Cloud Run unavailable
            // Uses benefit-score model: FinalScore = (ValueScore × TrustScore) − HarmRisk − AddictionRisk
            // Does NOT optimize for engagement, watch time, or session length.
            let ranked: [Post]
            if let r = sessionResult {
                ranked = r.posts
            } else {
                ranked = await feedAlgorithm?.benefitRankPosts(
                    posts,
                    for: interests,
                    followingIds: followingIds
                ) ?? posts
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    insertion: .opacity.combined(with: .scale(scale: 0.95)).animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8)),
                    removal: .opacity.combined(with: .scale(scale: 0.95)).animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8))
                ))
            }
        }
    }
}

// MARK: - Contextual Experience Banner Wrapper

private struct ExperienceResolverBannerWrapper: View {
    @ObservedObject private var resolver = ExperienceResolverService.shared
    @State private var isDismissed = false
    @State private var showExperienceDetail = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !isDismissed,
           let title = resolver.resolved.activeBannerTitle {
            ContextualExperienceFeedBanner(
                resolved: resolver.resolved,
                onTap: { showExperienceDetail = true },
                onDismiss: {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.78)) {
                        isDismissed = true
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .sheet(isPresented: $showExperienceDetail) {
                // Navigate to the active experience if we have an ID
                if let expId = resolver.resolved.activeExperienceId {
                    // ExperienceDetailView is loaded lazily
                    Text("Experience: \(expId)") // placeholder until ExperienceDetailView compiles
                }
            }
            .onAppear {
                isDismissed = false // reset on new experience
            }
            .onChange(of: resolver.resolved.activeExperienceId) { _, _ in
                isDismissed = false
            }
        }
    }
}

