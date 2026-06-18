// AMENDiscoveryView.swift
// AMEN App — Discovery & Search System
//
// The main Discovery/Search tab — replaces PeopleDiscoveryView.
// Consistent with AMEN's Liquid Glass / premium iOS design language.
//
// State machine:
//   .landing  → discovery modules (topics, trends, follow suggestions, recent searches)
//   .typing   → live typeahead suggestions
//   .results  → full tabbed search results
//   .topicPage → dedicated topic page

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Discover Mode

enum DiscoverMode: String, CaseIterable {
    case forYou      = "For You"
    case topics      = "Topics"
    case nearYou     = "Near You"
    case media       = "Media"
    case communities = "Communities"

    var icon: String {
        switch self {
        case .forYou:      return "sparkles"
        case .topics:      return "square.grid.2x2"
        case .nearYou:     return "location.fill"
        case .media:       return "play.circle"
        case .communities: return "person.3.fill"
        }
    }
}

struct AMENDiscoveryView: View {

    @StateObject private var service = DiscoveryService.shared
    @ObservedObject private var followService = FollowService.shared
    @StateObject private var trendingService = TrendingService.shared
    // PERF FIX: Use the shared singleton so the Firestore listener persists across
    // tab navigations instead of being recreated and re-fetching on every switch.
    @ObservedObject private var disasterVM = DisasterResourcesViewModel.shared
    @StateObject private var feedService = DiscoveryLandingFeedService()

    // Universal search view-model — owns 8-collection Firestore search + ranking
    @StateObject private var searchVM = UniversalSearchViewModel()

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var scrollOffset: CGFloat = 0
    @State private var showClearAllConfirm = false
    @State private var showBereanAI = false
    @AppStorage("hasSeenAISearchHint") private var hasSeenAISearchHint = false
    @State private var showAISearchHint = false
    @State private var isSearchDimmed = false

    // Search bar visibility — separate from focus so the TextField enters the
    // hierarchy before @FocusState is applied (avoids focus-on-transition failure)
    @State private var searchBarVisible = false

    // Discover mode selector
    @Namespace private var tabNamespace
    @State private var selectedMode: DiscoverMode = .forYou
    @State private var showMediaViewer = false
    @State private var heroIndex = 0

    // Navigation
    @State private var selectedTopic: DiscoveryTopic? = nil
    @State private var navigateToTopicPage = false
    @State private var showStudiesDiscovery = false

    // Rail navigation — discovery rails sheet destinations
    @State private var railSelectedSpaceId: String? = nil
    @State private var railSelectedMentorId: String? = nil
    @State private var railSelectedChurchId: String? = nil
    @State private var showBereanPulse = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Background
                Color(.systemBackground).ignoresSafeArea()

                // Dim overlay when search focused
                if isSearchDimmed {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isSearchFocused = false
                        }
                        .zIndex(5)
                        .transition(.opacity.animation(.spring(response: 0.38, dampingFraction: 0.72)))
                }

                VStack(spacing: 0) {
                    // Header: pill UI on landing, real search bar while searching/on subpages
                    if case .landing = service.searchState, !searchBarVisible, !isSearchFocused, searchText.isEmpty {
                        // Premium header: eyebrow + search pill + Ask Berean + topic pills
                        VStack(spacing: 0) {
                            HStack {
                                Text("AMEN DISCOVER")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .tracking(1.4)
                                Spacer()
                                Button {
                                    HapticManager.impact(style: .light)
                                    showBereanPulse = true
                                } label: {
                                    Image(systemName: "waveform.path.ecg")
                                        .font(.systemScaled(18, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .accessibilityLabel("Berean Pulse")
                                .accessibilityHint("Open spiritual intelligence dashboard")
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                            AmenDiscoverPillsRow(
                                searchPlaceholder: searchPlaceholder,
                                onSearchTap: {
                                    HapticManager.impact(style: .light)
                                    // Step 1: show the real search bar (TextField enters hierarchy)
                                    searchBarVisible = true
                                    // Step 2: apply focus on the next run-loop tick once TextField exists
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        isSearchFocused = true
                                    }
                                },
                                onAskBereanTap: {
                                    HapticManager.impact(style: .light)
                                    showBereanAI = true
                                },
                                topics: DiscoverMode.allCases.map { mode in
                                    AmenDiscoverPillItem(
                                        title: mode.rawValue,
                                        systemImage: mode.icon,
                                        isActive: selectedMode == mode,
                                        action: {
                                            HapticManager.impact(style: .light)
                                            withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.72))) {
                                                selectedMode = mode
                                            }
                                            if mode == .media { showMediaViewer = true }
                                        }
                                    )
                                }
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .background(.ultraThinMaterial)
                        .zIndex(10)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    } else {
                        // Real search bar — active while typing or on results/topic subpages
                        searchBarSection
                            .background(.ultraThinMaterial)
                            .zIndex(10)
                            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    }

                    // Scope filter tab bar — shown when search is active
                    if isSearchFocused || !searchText.isEmpty {
                        EnhancedSearchScopeTabBar(selected: $searchVM.searchScope)
                            .background(.ultraThinMaterial)
                            .zIndex(9)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Content area driven by state machine
                    contentArea
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $navigateToTopicPage) {
                if let topic = selectedTopic {
                    DiscoveryTopicPageView(topic: topic)
                }
            }
            .sheet(isPresented: $showStudiesDiscovery) {
                NavigationStack {
                    AmenStudiesDiscoveryView()
                }
            }
            // Rail navigation sheets
            .sheet(item: Binding(
                get: { railSelectedSpaceId.map { IdentifiableString(value: $0) } },
                set: { railSelectedSpaceId = $0?.value }
            )) { wrapper in
                NavigationStack {
                    AmenSpaceDetailView(
                        space: AmenConnectSpacesSpace(
                            id: wrapper.value,
                            name: "",
                            type: .smallGroup,
                            memberIds: [],
                            careSensitivity: false,
                            createdBy: "",
                            createdAt: Date(),
                            updatedAt: Date()
                        ),
                        events: [],
                        tiers: [],
                        hostProfile: nil
                    )
                }
            }
            .sheet(item: Binding(
                get: { railSelectedMentorId.map { IdentifiableString(value: $0) } },
                set: { railSelectedMentorId = $0?.value }
            )) { wrapper in
                NavigationStack {
                    AmenMentorChannelView(mentorId: wrapper.value)
                }
            }
            .sheet(item: Binding(
                get: { railSelectedChurchId.map { IdentifiableString(value: $0) } },
                set: { railSelectedChurchId = $0?.value }
            )) { wrapper in
                AmenChurchHubView(churchId: wrapper.value) {
                    railSelectedChurchId = nil
                }
            }
            .fullScreenCover(isPresented: $showBereanAI) {
                BereanChatView()
            }
            .fullScreenCover(isPresented: $showMediaViewer, onDismiss: {
                withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.72))) {
                    selectedMode = .forYou
                }
            }) {
                DiscoverMediaViewer(
                    videos: feedService.youtubeVideos,
                    onDismiss: { showMediaViewer = false },
                    onAskBerean: { showMediaViewer = false; showBereanAI = true }
                )
            }
            .onChange(of: isSearchFocused) { _, focused in
                withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.72))) {
                    isSearchDimmed = focused
                }
            }
            .sheet(isPresented: $showBereanPulse) {
                BereanPulseView()
            }
        }
    }

    // MARK: - Discover Mode Selector

    private var discoverModeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DiscoverMode.allCases, id: \.self) { mode in
                    Button {
                        HapticManager.impact(style: .light)
                        withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.72))) {
                            selectedMode = mode
                        }
                        if mode == .media {
                            showMediaViewer = true
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode.icon)
                                .font(.systemScaled(11, weight: .medium))
                            Text(mode.rawValue)
                                .font(AMENFont.semiBold(13))
                        }
                        .foregroundStyle(selectedMode == mode ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if selectedMode == mode {
                                Capsule()
                                    .fill(Color.black)
                                    .matchedGeometryEffect(id: "activeDiscoverMode", in: tabNamespace)
                            } else {
                                Capsule()
                                    .fill(Color.primary.opacity(0.07))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Search Bar

    private var isShowingSubpage: Bool {
        switch service.searchState {
        case .results, .topicPage: return true
        default: return false
        }
    }

    private var searchBarSection: some View {
        HStack(spacing: 10) {
            // Back button — visible when on results or topic page
            if isShowingSubpage {
                Button {
                    HapticManager.impact(style: .light)
                    searchText = ""
                    isSearchFocused = false
                    searchBarVisible = false
                    service.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Unified Liquid Glass search capsule
            AmenSmartCapsule(
                text: $searchText,
                placeholder: searchPlaceholder,
                style: .discover,
                isFocused: $isSearchFocused,
                onSubmit: {
                    Task { await service.submitSearch(searchText) }
                    searchVM.scheduleSearch(query: searchText)
                },
                onClear: {
                    searchText = ""
                    service.clearSearch()
                    searchVM.scheduleSearch(query: "")
                    isSearchFocused = false
                }
            )
            // Lower layout priority so the Ask Berean button is never clipped at the trailing edge
            .layoutPriority(0)
            .onChange(of: searchText) { _, newValue in
                service.setQuery(newValue)
                searchVM.scheduleSearch(query: newValue)
            }
            .onChange(of: isSearchFocused) { _, focused in
                if focused {
                    HapticManager.impact(style: .light)
                }
            }

            // Berean AI button — labeled capsule so users know what it does
            if !isSearchFocused && searchText.isEmpty {
                Button {
                    HapticManager.impact(style: .light)
                    showBereanAI = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.systemScaled(13, weight: .semibold))
                        Text("Ask AI")
                            .font(AMENFont.semiBold(12))
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .overlay(alignment: .bottom) {
                    if showAISearchHint {
                        Text("Ask Berean anything")
                            .font(AMENFont.regular(11))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.purple.opacity(0.85)))
                            .offset(y: 36)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .onAppear {
                    guard !hasSeenAISearchHint else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))) {
                            showAISearchHint = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showAISearchHint = false
                                hasSeenAISearchHint = true
                            }
                        }
                    }
                }
            }

            if isSearchFocused || !searchText.isEmpty {
                Button("Cancel") {
                    searchText = ""
                    service.clearSearch()
                    searchVM.scheduleSearch(query: "")
                    isSearchFocused = false
                    searchBarVisible = false
                }
                .font(AMENFont.regular(15))
                .foregroundStyle(.primary)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSearchFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isShowingSubpage)
        .onChange(of: searchVM.searchScope) { _, _ in
            guard !searchText.isEmpty else { return }
            searchVM.scheduleSearch(query: searchText)
        }
    }

    private var searchPlaceholder: String {
        "Verses, people, news, videos, studies..."
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch service.searchState {
        case .landing:
            // When focused + empty → show recent searches overlay on top of landing
            if isSearchFocused && searchText.isEmpty {
                searchFocusedEmptyView
            } else {
                switch selectedMode {
                case .forYou:
                    landingView
                case .topics:
                    DiscoverTopicsGrid { tile in
                        // Map tile slug to a DiscoveryTopic for navigation
                        if let topic = DiscoveryTopic.catalog.first(where: { $0.canonicalSlug == tile.slug }) {
                            selectedTopic = topic
                            service.selectTopic(topic)
                        } else {
                            searchText = tile.title
                            Task { await service.submitSearch(tile.title) }
                        }
                    }
                case .nearYou:
                    DiscoverNearYouView()
                case .media:
                    Color.clear
                        .onAppear { showMediaViewer = true }
                case .communities:
                    DiscoverCommunitiesView(discussions: feedService.discussions)
                }
            }
        case .typing:
            // Show recent searches if query is empty, typeahead otherwise
            if searchText.isEmpty && isSearchFocused {
                searchFocusedEmptyView
            } else {
                typeaheadView
            }
        case .results(let query):
            // Show new UniversalSearchResultsView alongside existing tabbed view
            UniversalSearchResultsView(
                query: query,
                viewModel: searchVM,
                searchText: $searchText
            )
        case .topicPage(let topic):
            DiscoveryTopicPageView(topic: topic)
        }
    }

    /// Shown when search bar is focused and query is empty — recent searches list.
    private var searchFocusedEmptyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SearchRecentListView(viewModel: searchVM) { term in
                    searchText = term
                    isSearchFocused = false
                    service.setQuery(term)
                    searchVM.scheduleSearch(query: term)
                    Task { await service.submitSearch(term) }
                }
                Spacer().frame(height: 100)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Landing View

    private var landingView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                // ── Discovery rails (Netflix/Apple TV horizontal rails) ──
                AmenDiscoveryRailsView(
                    userId: Auth.auth().currentUser?.uid ?? ""
                ) { item in
                    switch item.type {
                    case .space:
                        railSelectedSpaceId = item.metadata["spaceId"] ?? item.id
                    case .mentor:
                        railSelectedMentorId = item.metadata["mentorId"] ?? item.id
                    case .church:
                        railSelectedChurchId = item.metadata["churchId"] ?? item.id
                    case .event, .study, .discussion, .person, .churchNote:
                        break
                    }
                } onSeeAll: { _ in
                }

                // ── Active disaster alert (pinned at top when present) ──
                if let topDisaster = disasterVM.disasters.first {
                    DisasterAlertCard(disaster: topDisaster)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // ── Hero carousel (Reels-inspired featured cards) ──
                DiscoverHeroStack(
                    feedService: feedService,
                    currentIndex: $heroIndex,
                    onAskBerean: { showBereanAI = true }
                )
                .padding(.top, 4)

                // ── Explore by type pills ──
                exploreByTypeSection

                // 1. Topic chips + Trending topics row
                topicChipsSection

                TrendingTopicsPillsView(viewModel: searchVM) { topic in
                    searchText = topic.title
                    service.setQuery(topic.title)
                    searchVM.scheduleSearch(query: topic.title)
                    Task { await service.submitSearch(topic.title) }
                }

                // 2. Verse of the Day — hero card
                VStack(alignment: .leading, spacing: 12) {
                    DiscoverSectionHeader(title: "Verse of the Day", icon: "book.closed.fill")
                        .padding(.horizontal, 16)

                    if feedService.isLoadingVerse {
                        DiscoveryTrendSkeletonCard()
                            .frame(height: 280)
                            .padding(.horizontal, 16)
                    } else if let verse = feedService.dailyVerse {
                        VerseHeroCard(verse: verse)
                            .padding(.horizontal, 16)
                            .discoveryCardEntry(index: 0)
                    }
                }

                // 3. People suggested — horizontal avatar row
                if !service.followSuggestions.isEmpty || service.isFollowSuggestionsLoading {
                    VStack(alignment: .leading, spacing: 12) {
                        DiscoverSectionHeader(title: "People to Follow", icon: "person.2.fill")
                            .padding(.horizontal, 16)
                        followSuggestionsSection
                    }
                }

                // 4. Bible Studies
                if !feedService.bibleStudies.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            DiscoverSectionHeader(title: "Bible Studies", icon: "graduationcap.fill")
                            Spacer()
                            Button {
                                showStudiesDiscovery = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Explore All")
                                        .font(.systemScaled(13, weight: .semibold))
                                    Image(systemName: "chevron.right")
                                        .font(.systemScaled(11, weight: .semibold))
                                }
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        VStack(spacing: 12) {
                            ForEach(Array(feedService.bibleStudies.enumerated()), id: \.element.id) { idx, study in
                                DiscoverBibleStudyCard(study: study)
                                    .padding(.horizontal, 16)
                                    .discoveryCardEntry(index: idx + 2)
                            }
                        }
                    }
                }

                // 5. Discussions
                if !feedService.discussions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        DiscoverSectionHeader(title: "Discussions", icon: "bubble.left.and.bubble.right.fill")
                            .padding(.horizontal, 16)
                        DiscoverDiscussionCard(discussions: Array(feedService.discussions.prefix(4)))
                            .padding(.horizontal, 16)
                            .discoveryCardEntry(index: 5)
                    }
                }

                // 6. What people are discussing (Trends)
                trendsSection

                // 7. Trending in AMEN
                topIdeasSection

                // 8. Videos — YouTube cards
                VStack(alignment: .leading, spacing: 12) {
                    DiscoverSectionHeader(title: "Videos", icon: "play.circle.fill")
                        .padding(.horizontal, 16)
                    if feedService.isLoadingVideos {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(0..<3, id: \.self) { _ in
                                    DiscoveryTrendSkeletonCard()
                                        .frame(width: 220, height: 200)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    } else if !feedService.youtubeVideos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(feedService.youtubeVideos.enumerated()), id: \.element.id) { idx, video in
                                    DiscoveryLandingVideoCard(video: video)
                                        .discoveryCardEntry(index: idx + 6)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                    }
                }

                // 9. News — compact horizontal scroll
                if !feedService.newsItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        DiscoverSectionHeader(title: "Faith News", icon: "newspaper.fill")
                            .padding(.horizontal, 16)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(feedService.newsItems.enumerated()), id: \.element.id) { idx, item in
                                    DiscoveryLandingNewsCard(item: item)
                                        .discoveryCardEntry(index: idx + 10)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                    }
                }

                // 10. Berean AI banner
                bereanAIBannerSection

                // 11. Popular topics grid
                popularTopicsSection

                // 12. AMEN Intelligence footer banner
                amenIntelligenceFooter

                Spacer().frame(height: 100)
            }
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            disasterVM.loadDisasters()
            await feedService.loadAll()
            if trendingService.topIdeas.isEmpty || !trendingService.isLoading {
                try? await trendingService.fetchTopIdeas()
            }
        }
        .onAppear {
            disasterVM.loadDisasters()
            Task { await feedService.loadAll() }
        }
    }

    // MARK: - Topic Chips

    private var topicChipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(service.topicChips) { topic in
                        TopicChipButton(topic: topic) {
                            selectedTopic = topic
                            service.selectTopic(topic)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Recent Searches

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)
                Spacer()
                Button("Clear all") {
                    showClearAllConfirm = true
                }
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(service.recentSearches) { item in
                        RecentSearchChip(item: item) {
                            searchText = item.query
                            Task { await service.submitSearch(item.query) }
                        } onRemove: {
                            withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                                service.removeRecentSearch(id: item.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .confirmationDialog("Clear recent searches?", isPresented: $showClearAllConfirm, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) {
                withAnimation { service.clearAllRecentSearches() }
            }
        }
    }

    // MARK: - Trends Section

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What people are discussing")
                    .font(AMENFont.semiBold(17))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                Text("Summaries reviewed for safety and accuracy")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            if service.isTrendsLoading {
                // Skeleton cards
                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        DiscoveryTrendSkeletonCard()
                    }
                }
                .padding(.horizontal, 16)
            } else if service.trends.isEmpty {
                // Fallback: show topic-based pseudo-trends from the catalog
                VStack(spacing: 10) {
                    ForEach(Array(DiscoveryTopic.catalog.prefix(4))) { topic in
                        TopicTrendRow(topic: topic) {
                            selectedTopic = topic
                            service.selectTopic(topic)
                        }
                    }
                }
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(service.trends) { trend in
                        DiscoveryTrendCard(trend: trend) {
                            // Tap opens a search for the trend title
                            searchText = trend.title
                            Task { await service.submitSearch(trend.title) }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Top Ideas Section

    private var topIdeasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("From the Community")
                        .font(AMENFont.semiBold(17))
                        .foregroundStyle(.primary)
                    Text("Recent posts in AMEN")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            if trendingService.isLoading {
                // Loading indicator
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 16)
            } else if trendingService.topIdeas.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(32))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No posts yet")
                        .font(AMENFont.medium(14))
                        .foregroundStyle(.secondary)
                    Text("Check back soon for posts from the community")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 16)
            } else {
                // Show top 5 ideas in horizontal scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(trendingService.topIdeas.prefix(5))) { idea in
                            TopIdeaCard(idea: idea)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .onAppear {
            if trendingService.topIdeas.isEmpty && !trendingService.isLoading {
                Task {
                    try? await trendingService.fetchTopIdeas()
                }
            }
        }
    }

    // MARK: - Follow Suggestions

    private var followSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if service.isFollowSuggestionsLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in
                            FollowSuggestionSkeletonCard()
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(service.followSuggestions) { suggestion in
                            DiscoveryFollowCard(suggestion: suggestion) {
                                Task {
                                    if suggestion.isFollowing {
                                        await service.unfollowUser(userId: suggestion.id)
                                    } else {
                                        await service.followUser(userId: suggestion.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Berean AI Banner

    private var bereanAIBannerSection: some View {
        Button {
            HapticManager.impact(style: .light)
            showBereanAI = true
        } label: {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.8), Color.indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.systemScaled(18, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ask Berean AI")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)
                    Text("Scripture-grounded answers to any faith question")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.purple.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.purple.opacity(0.15), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Premium Hero Cards Row (NEW)

    private var amenHeroCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Featured")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    AmenHeroDiscoveryCard(
                        title: "Palm Sunday reflections",
                        tagLabel: "Seasonal",
                        tagIcon: "leaf.fill",
                        accentColor: Color(red: 0.36, green: 0.55, blue: 0.36)
                    )
                    AmenHeroDiscoveryCard(
                        title: "Worship moments near you",
                        tagLabel: "Local",
                        tagIcon: "location.fill",
                        accentColor: Color(red: 0.25, green: 0.45, blue: 0.65)
                    )
                    AmenHeroDiscoveryCard(
                        title: "Verses for anxiety",
                        tagLabel: "Care",
                        tagIcon: "heart.fill",
                        accentColor: Color(red: 0.55, green: 0.35, blue: 0.65)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Explore by Type Pills (NEW)

    private var exploreByTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Explore by type")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(exploreTypes, id: \.label) { item in
                        Button {
                            HapticManager.impact(style: .light)
                            searchText = item.searchTerm
                            Task { await service.submitSearch(item.searchTerm) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: item.icon)
                                    .font(.systemScaled(13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(item.label)
                                    .font(.systemScaled(14, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            // Solid readable surface (not glass): chips carry text, and the
                            // rails design rule is "no glass on content cards". Semantic fills
                            // adapt to light/dark, Reduce Transparency, and Increase Contrast.
                            .background(
                                Capsule()
                                    .fill(Color(.secondarySystemBackground))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                                    )
                            )
                            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    private var exploreTypes: [(label: String, icon: String, searchTerm: String)] {
        [
            (label: "Text posts",     icon: "text.alignleft",          searchTerm: "posts"),
            (label: "Photos",         icon: "photo",                   searchTerm: "photos"),
            (label: "Videos",         icon: "play.circle",             searchTerm: "videos"),
            (label: "Comments",       icon: "bubble.left",             searchTerm: "comments"),
            (label: "Hashtags",       icon: "number",                  searchTerm: "hashtags"),
            (label: "Bible verses",   icon: "book.closed",             searchTerm: "bible verses"),
            (label: "Communities",    icon: "person.3",                searchTerm: "communities"),
        ]
    }

    // MARK: - AMEN Intelligence Footer (NEW)

    private var amenIntelligenceFooter: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(.tertiarySystemBackground))
                        .overlay(Circle().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
                        .frame(width: 48, height: 48)
                    Image(systemName: "sparkles")
                        .font(.systemScaled(20, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Ranked for meaning, not noise")
                        .font(.systemScaled(17, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Scripture trails, prayer circles, and faith-forward discovery")
                        .font(.systemScaled(13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }

            Button {
                HapticManager.impact(style: .medium)
                showBereanAI = true
            } label: {
                Text("Explore")
                    .font(.systemScaled(15, weight: .semibold))
                    // Inverting label/background gives a high-contrast CTA in both
                    // light (dark fill, light text) and dark (light fill, dark text).
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.label))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        // Solid readable surface (not glass): this card holds heading + body text.
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
        .padding(.horizontal, 16)
    }

    // MARK: - Popular Topics Section (upgraded grid card wrappers)

    private var popularTopicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular topics")
                .font(AMENFont.semiBold(17))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(Array(service.popularTopics.enumerated()), id: \.element.id) { idx, topic in
                    AmenPremiumTopicGridCard(
                        topic: topic,
                        isTall: idx % 4 == 0 || idx % 4 == 3
                    ) {
                        selectedTopic = topic
                        service.selectTopic(topic)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Typeahead Suggestions View

    private var typeaheadView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if service.isSuggestionsLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else {
                    ForEach(service.typeaheadSuggestions) { suggestion in
                        TypeaheadRow(suggestion: suggestion) {
                            searchText = suggestion.text
                            isSearchFocused = false
                            Task { await service.submitSearch(suggestion.text) }
                        }
                    }
                }

                // If no suggestions but user is typing, still allow search
                if service.typeaheadSuggestions.isEmpty && !service.isSuggestionsLoading && !searchText.isEmpty {
                    Button {
                        isSearchFocused = false
                        Task { await service.submitSearch(searchText) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.systemScaled(15))
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text("Search for \"\(searchText)\"")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                }

                Divider().padding(.horizontal, 16).padding(.top, 8)

                // Berean AI shortcut — ask a faith question instead of searching
                Button {
                    isSearchFocused = false
                    HapticManager.impact(style: .light)
                    showBereanAI = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Ask Berean AI")
                                .font(AMENFont.semiBold(15))
                                .foregroundStyle(.primary)
                            if !searchText.isEmpty {
                                Text("Ask Berean: \"\(searchText)\"")
                                    .font(AMENFont.regular(12))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Scripture-grounded answers")
                                    .font(AMENFont.regular(12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.systemScaled(11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)

                Spacer().frame(height: 100)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Discover Extensions

/// Thin `Identifiable` wrapper used by `.sheet(item:)` to present a String-keyed destination.
private struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }
}

private struct DiscoverTopicTile: Identifiable {
    let id: String
    let title: String
    let slug: String
    let icon: String
    let color: Color
}

private struct DiscoverTopicsGrid: View {
    let onSelect: (DiscoverTopicTile) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private var tiles: [DiscoverTopicTile] {
        DiscoveryTopic.catalog.map { topic in
            DiscoverTopicTile(
                id: topic.id,
                title: topic.title,
                slug: topic.canonicalSlug,
                icon: topic.icon,
                color: topic.iconColor
            )
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(DiscoveryTopic.catalog) { topic in
                    DiscoveryTopicGridCard(topic: topic) {
                        let tile = DiscoverTopicTile(
                            id: topic.id,
                            title: topic.title,
                            slug: topic.canonicalSlug,
                            icon: topic.icon,
                            color: topic.iconColor
                        )
                        onSelect(tile)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
    }
}

private struct DiscoverNearYouView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DiscoverSectionHeader(title: "Near You", icon: "location.fill")
                Text("Enable location to see churches, events, and communities nearby.")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Image(systemName: "location.circle")
                        .font(.systemScaled(20, weight: .semibold))
                        .foregroundStyle(.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location Access")
                            .font(AMENFont.semiBold(15))
                        Text("Get local results tailored to your area.")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                        )
                )
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 60)
        }
    }
}

private struct DiscoverCommunitiesView: View {
    let discussions: [DiscussionItem]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DiscoverSectionHeader(title: "Communities", icon: "person.3.fill")
                if discussions.isEmpty {
                    Text("No communities available yet. Check back soon.")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                } else {
                    DiscoverDiscussionCard(discussions: Array(discussions.prefix(6)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 60)
        }
    }
}

private struct DiscoverMediaViewer: View {
    let videos: [YoutubeVideoItem]
    let onDismiss: () -> Void
    let onAskBerean: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DiscoverSectionHeader(title: "Media", icon: "play.circle.fill")
                    if videos.isEmpty {
                        Text("No videos available right now.")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { _, video in
                            DiscoveryLandingVideoCard(video: video)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 60)
            }
            .navigationTitle("Discover Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { onDismiss() }
                        .font(AMENFont.semiBold(15))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onAskBerean()
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.systemScaled(14, weight: .semibold))
                    }
                }
            }
        }
    }
}

private struct DiscoverHeroStack: View {
    @ObservedObject var feedService: DiscoveryLandingFeedService
    @Binding var currentIndex: Int
    let onAskBerean: () -> Void

    var body: some View {
        TabView(selection: $currentIndex) {
            heroAskBereanCard
                .tag(0)

            if let news = feedService.newsItems.first {
                DiscoveryLandingNewsCard(item: news)
                    .frame(maxWidth: .infinity)
                    .tag(1)
            }

            if let video = feedService.youtubeVideos.first {
                DiscoveryLandingVideoCard(video: video)
                    .frame(maxWidth: .infinity)
                    .tag(2)
            }
        }
        .frame(height: 240)
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .padding(.horizontal, 16)
    }

    private var heroAskBereanCard: some View {
        Button(action: onAskBerean) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.black.opacity(0.9), Color.black.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ask Berean AI")
                        .font(AMENFont.semiBold(20))
                        .foregroundStyle(.white)
                    Text("Scripture-grounded answers and practical wisdom.")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.systemScaled(14, weight: .semibold))
                        Text("Start a conversation")
                            .font(AMENFont.semiBold(14))
                    }
                    .foregroundStyle(.white)
                }
                .padding(18)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Header

private struct DiscoverSectionHeader: View {
    let title: String
    let icon: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.8))
            Text(title)
                .font(AMENFont.semiBold(17))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Discovery Card Entry Modifier (stagger-fade animation)

struct DiscoveryCardEntryModifier: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .onAppear {
                withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.72)).delay(Double(index) * 0.06)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func discoveryCardEntry(index: Int) -> some View {
        modifier(DiscoveryCardEntryModifier(index: index))
    }
}

// MARK: - Topic Chip Button

struct TopicChipButton: View {
    let topic: DiscoveryTopic
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: topic.icon)
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(topic.iconColor)
                Text(topic.title)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(topic.iconColor.opacity(0.2), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Search Chip

struct RecentSearchChip: View {
    let item: RecentSearchItem
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onTap) {
                HStack(spacing: 5) {
                    Image(systemName: item.type == .person ? "person.circle" : "clock")
                        .font(.systemScaled(11))
                        .foregroundStyle(.secondary)
                    Text(item.query)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.systemScaled(9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.07))
        )
    }
}

// MARK: - Typeahead Row

struct TypeaheadRow: View {
    let suggestion: TypeaheadSuggestion
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon or avatar — CachedAsyncImage for reliable display
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: 32, height: 32)
                    if let urlStr = suggestion.avatarURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                        } placeholder: {
                            Image(systemName: suggestion.icon)
                                .font(.systemScaled(13))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: suggestion.icon)
                            .font(.systemScaled(13))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.text)
                        .font(AMENFont.regular(15))
                        .foregroundStyle(.primary)
                    if let subtitle = suggestion.subtitle {
                        Text(subtitle)
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if suggestion.type == .recentSearch {
                    Image(systemName: "arrow.up.left")
                        .font(.systemScaled(11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Divider().padding(.leading, 60)
    }
}

// MARK: - Trend Card

struct DiscoveryTrendCard: View {
    let trend: DiscoveryTrend
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        // No engagement-count badge shown per product invariant
                    }

                    Text(trend.title)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(trend.summary)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.systemScaled(11))
                            .foregroundStyle(.tertiary)
                        Text("\(trend.discussionCount) discussions")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()

                if let thumb = trend.thumbnailURL {
                    CachedAsyncImage(url: URL(string: thumb)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1))
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// Fallback trend row when no live trends are available
struct TopicTrendRow: View {
    let topic: DiscoveryTopic
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: topic.icon)
                    .font(.systemScaled(18))
                    .foregroundStyle(topic.iconColor)
                    .frame(width: 40, height: 40)
                    .background(topic.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.title)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.primary)
                    Text(topic.description)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Follow Suggestion Card (Horizontal Scroll)

struct DiscoveryFollowCard: View {
    let suggestion: FollowSuggestion
    let onFollowTap: () -> Void

    @State private var isFollowInFlight = false

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            // Avatar — CachedAsyncImage for reliable display
            ZStack {
                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 56, height: 56)
                if let urlStr = suggestion.person.avatarURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    } placeholder: {
                        Text(String(suggestion.person.displayName.prefix(1)).uppercased())
                            .font(AMENFont.bold(20))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(String(suggestion.person.displayName.prefix(1)).uppercased())
                        .font(AMENFont.bold(20))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)

            VStack(spacing: 2) {
                Text(suggestion.person.displayName)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("@\(suggestion.person.username)")
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let reason = suggestion.reason as String?, !reason.isEmpty {
                Text(reason)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 130)
            }

            // Follow button
            Button {
                guard !isFollowInFlight else { return }
                isFollowInFlight = true
                onFollowTap()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isFollowInFlight = false
                }
            } label: {
                Text(suggestion.isFollowing ? "Following" : "Follow")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(suggestion.isFollowing ? .secondary : .primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(suggestion.isFollowing
                                  ? Color.primary.opacity(0.06)
                                  : Color.primary.opacity(0.10))
                            .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                    )
            }
            .buttonStyle(.plain)
            .disabled(isFollowInFlight)
        }
        .frame(width: 140)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Topic Grid Card

struct DiscoveryTopicGridCard: View {
    let topic: DiscoveryTopic
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: topic.icon)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(topic.iconColor)
                    .frame(width: 36, height: 36)
                    .background(topic.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title)
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if topic.postCount > 0 {
                        Text("\(topic.postCount) posts")
                            .font(AMENFont.regular(11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Skeleton Views

struct DiscoveryTrendSkeletonCard: View {
    @State private var opacity: Double = 0.4
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.primary.opacity(0.06))
            .frame(height: 80)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    opacity = 0.9
                }
            }
    }
}

struct FollowSuggestionSkeletonCard: View {
    @State private var opacity: Double = 0.4
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.primary.opacity(0.06))
            .frame(width: 140, height: 180)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    opacity = 0.9
                }
            }
    }
}

// MARK: - Verse Hero Card

struct VerseHeroCard: View {
    let verse: DiscoveryLandingDailyVerseData
    @State private var isSaved = false
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 0) {
            // Image area — gradient overlay
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.11, green: 0.16, blue: 0.11), Color(red: 0.18, green: 0.29, blue: 0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 160)
                    .overlay(
                        Canvas { ctx, size in
                            let spacing: CGFloat = 16
                            for row in stride(from: 0, to: size.height, by: spacing) {
                                for col in stride(from: 0, to: size.width, by: spacing) {
                                    ctx.fill(Path(ellipseIn: CGRect(x: col, y: row, width: 1.5, height: 1.5)), with: .color(.white.opacity(0.15)))
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                    )

                // Type badge top-left
                Text("VERSE")
                    .font(AMENFont.semiBold(10))
                    .foregroundStyle(.white)
                    .tracking(1.2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
                    .padding(14)

                // Testament pill top-right
                VStack {
                    HStack {
                        Spacer()
                        Text(verse.testament + " · " + (verse.reference.components(separatedBy: " ").first ?? ""))
                            .font(AMENFont.semiBold(10))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.55))
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            )
                    }
                    Spacer()
                }
                .padding(14)

                // Bottom overlay — reference
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verse.reference.uppercased())
                                .font(AMENFont.semiBold(10))
                                .foregroundStyle(.white.opacity(0.7))
                                .tracking(1)
                        }
                        Spacer()
                    }
                    .padding(14)
                }
            }
            .frame(height: 160)

            // Verse text + metadata
            VStack(alignment: .leading, spacing: 12) {
                Text(verse.text)
                    .font(AMENFont.regular(15))
                    .italic()
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        isSaved.toggle()
                        HapticManager.impact(style: .light)
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.systemScaled(16))
                            .foregroundStyle(isSaved ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSaved ? "Remove bookmark" : "Bookmark article")

                    Button {
                        HapticManager.impact(style: .light)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.systemScaled(16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share article")
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.88).background(.ultraThinMaterial))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 6)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in isPressed = pressing }, perform: {})
    }
}

// MARK: - Video Card

struct DiscoveryLandingVideoCard: View {
    let video: YoutubeVideoItem
    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Thumbnail
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbStr = video.thumbnailURL, let url = URL(string: thumbStr) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            LinearGradient(colors: [Color.indigo.opacity(0.4), Color.purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                    } else {
                        LinearGradient(colors: [Color.indigo.opacity(0.4), Color.purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.systemScaled(16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .offset(x: 2)
                        )
                )

                // Duration pill
                if !video.duration.isEmpty {
                    Text(video.duration)
                        .font(AMENFont.semiBold(10))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                        .padding(8)
                }

                // Type badge
                VStack {
                    HStack {
                        Text("VIDEO")
                            .font(AMENFont.semiBold(9))
                            .foregroundStyle(.white)
                            .tracking(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.5))
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            )
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }

            // Title + channel
            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(video.channelName)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                    if !video.viewCount.isEmpty {
                        Text("· \(video.viewCount)")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(Color.white.opacity(0.88).background(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 6)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in isPressed = pressing }, perform: {})
        .frame(width: 220)
    }
}

// MARK: - News Card

struct DiscoveryLandingNewsCard: View {
    let item: NewsItem
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 12) {
            // Source icon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 40, height: 40)
                Image(systemName: "newspaper")
                    .font(.systemScaled(16))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.sourceName)
                        .font(AMENFont.semiBold(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(item.publishedAt.timeAgoString())
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                }
                Text(item.headline)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(item.category)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.55)))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.88).background(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
        .frame(width: 280, height: 100)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in isPressed = pressing }, perform: {})
    }
}

// MARK: - Bible Study Card

struct DiscoverBibleStudyCard: View {
    let study: BibleStudyItem
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 14) {
            // Cover
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: study.coverGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 90, height: 90)
                    .overlay(
                        Canvas { ctx, size in
                            let spacing: CGFloat = 12
                            for row in stride(from: 0, to: size.height, by: spacing) {
                                for col in stride(from: 0, to: size.width, by: spacing) {
                                    ctx.fill(Path(ellipseIn: CGRect(x: col, y: row, width: 1.5, height: 1.5)), with: .color(.white.opacity(0.15)))
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    )
                Text(study.emoji)
                    .font(.systemScaled(28))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("BIBLE STUDY")
                    .font(AMENFont.semiBold(9))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Text(study.title)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label("\(study.lessonCount) lessons", systemImage: "book")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                    Label(study.duration, systemImage: "clock")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.systemScaled(10))
                        .foregroundStyle(.orange)
                    Text(String(format: "%.1f", study.rating))
                        .font(AMENFont.semiBold(11))
                        .foregroundStyle(.primary)
                    Text("· \(study.enrolledCount) enrolled")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.white.opacity(0.88).background(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 6)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in isPressed = pressing }, perform: {})
    }
}

// MARK: - Discussion Group Card

struct DiscoverDiscussionCard: View {
    let discussions: [DiscussionItem]
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(discussions.enumerated()), id: \.element.id) { idx, item in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 38, height: 38)
                        Image(systemName: item.iconName)
                            .font(.systemScaled(16, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(.primary)
                        Text(item.subtitle)
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        Text("\(item.participantCount)")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if idx < discussions.count - 1 {
                    Divider()
                        .background(Color.black.opacity(0.05))
                        .padding(.leading, 64)
                }
            }
        }
        .background(Color.white.opacity(0.88).background(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 6)
    }
}

// MARK: - New Data Models

struct DiscoveryLandingDailyVerseData: Identifiable {
    let id = UUID()
    let reference: String
    let text: String
    let bookName: String
    let testament: String
    let discussionCount: Int
    let saveCount: Int
}

struct YoutubeVideoItem: Identifiable {
    let id: String
    let title: String
    let channelName: String
    let thumbnailURL: String?
    let viewCount: String
    let duration: String
}

struct NewsItem: Identifiable {
    let id = UUID()
    let headline: String
    let sourceName: String
    let publishedAt: Date
    let imageURL: String?
    let category: String
}

struct UnsplashPhoto: Identifiable {
    let id: String
    let thumbURL: String
    let regularURL: String
    let photographerName: String
}

struct BibleStudyItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let lessonCount: Int
    let duration: String
    let rating: Double
    let enrolledCount: Int
    let emoji: String
    let coverGradient: [Color]
}

struct DiscussionItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let participantCount: Int
}

// MARK: - DiscoveryLandingFeedService

@MainActor
class DiscoveryLandingFeedService: ObservableObject {
    static let shared = DiscoveryLandingFeedService()

    @Published var dailyVerse: DiscoveryLandingDailyVerseData?
    @Published var youtubeVideos: [YoutubeVideoItem] = []
    @Published var newsItems: [NewsItem] = []
    @Published var unsplashPhotos: [UnsplashPhoto] = []
    @Published var bibleStudies: [BibleStudyItem] = []
    @Published var discussions: [DiscussionItem] = []

    @Published var isLoadingVerse = false
    @Published var isLoadingVideos = false
    @Published var isLoadingNews = false

    init() {
        Task { await loadAll() }
    }

    func loadAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadDailyVerse() }
            group.addTask { await self.loadYouTubeVideos() }
            group.addTask { await self.loadNews() }
            group.addTask { await self.loadBibleStudies() }
            group.addTask { await self.loadDiscussions() }
            group.addTask { await self.loadUnsplashPhotos() }
        }
    }

    private func loadDailyVerse() async {
        isLoadingVerse = true
        defer { isLoadingVerse = false }

        // INFRA-4: Direct client-side calls to scripture.api.bible are forbidden —
        // the client must never hold API.Bible credentials.
        // TODO(INFRA-4): route through a getDailyVerse CF callable when provisioned.
        // Until then, serve from the curated local fallback below.

        let verseCount = 10
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let todayIndex = (dayOfYear - 1) % verseCount

        // Fallback: local top 10 verses
        let fallback: [(ref: String, text: String, testament: String)] = [
            ("Psalm 23:1", "The LORD is my shepherd; I shall not want.", "Old Testament"),
            ("John 3:16", "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.", "New Testament"),
            ("Romans 8:28", "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.", "New Testament"),
            ("Philippians 4:13", "I can do all this through him who gives me strength.", "New Testament"),
            ("Isaiah 40:31", "But those who hope in the LORD will renew their strength. They will soar on wings like eagles.", "Old Testament"),
            ("Jeremiah 29:11", "For I know the plans I have for you, declares the LORD, plans to prosper you and not to harm you, plans to give you hope and a future.", "Old Testament"),
            ("Psalm 46:1", "God is our refuge and strength, an ever-present help in trouble.", "Old Testament"),
            ("Proverbs 3:5", "Trust in the LORD with all your heart and lean not on your own understanding.", "Old Testament"),
            ("Matthew 28:20", "And surely I am with you always, to the very end of the age.", "New Testament"),
            ("Romans 5:8", "But God demonstrates his own love for us in this: While we were still sinners, Christ died for us.", "New Testament"),
        ]
        let fb = fallback[todayIndex]
        dailyVerse = DiscoveryLandingDailyVerseData(
            reference: fb.ref,
            text: fb.text,
            bookName: "",
            testament: fb.testament,
            discussionCount: Int.random(in: 12...89),
            saveCount: Int.random(in: 8...45)
        )
    }

    private func loadYouTubeVideos() async {
        isLoadingVideos = true
        defer { isLoadingVideos = false }

        let apiKey = "" // API key configured via Firebase Remote Config
        let queries = ["faith sermon", "worship music", "bible study devotional", "christian prayer"]
        let query = queries[Int.random(in: 0..<queries.count)].addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "faith"
        let urlStr = "https://www.googleapis.com/youtube/v3/search?part=snippet&q=\(query)&type=video&relevanceLanguage=en&maxResults=6&key=\(apiKey)"

        guard let url = URL(string: urlStr) else {
            youtubeVideos = mockYouTubeVideos
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            youtubeVideos = mockYouTubeVideos
            return
        }

        let parsed = items.compactMap { item -> YoutubeVideoItem? in
            guard let id = (item["id"] as? [String: Any])?["videoId"] as? String,
                  let snippet = item["snippet"] as? [String: Any],
                  let title = snippet["title"] as? String,
                  let channel = snippet["channelTitle"] as? String else { return nil }
            let thumb = ((snippet["thumbnails"] as? [String: Any])?["medium"] as? [String: Any])?["url"] as? String
            return YoutubeVideoItem(id: id, title: title, channelName: channel, thumbnailURL: thumb, viewCount: "", duration: "")
        }
        youtubeVideos = parsed.isEmpty ? mockYouTubeVideos : parsed
    }

    private var mockYouTubeVideos: [YoutubeVideoItem] {
        [
            YoutubeVideoItem(id: "mock1", title: "Sunday Sermon: Walking by Faith", channelName: "Grace Church", thumbnailURL: nil, viewCount: "12K views", duration: "38:22"),
            YoutubeVideoItem(id: "mock2", title: "Praise & Worship Live", channelName: "Elevation Worship", thumbnailURL: nil, viewCount: "45K views", duration: "1:12:04"),
            YoutubeVideoItem(id: "mock3", title: "Morning Devotional — Psalm 23", channelName: "Daily Bread", thumbnailURL: nil, viewCount: "8.2K views", duration: "12:15"),
        ]
    }

    private func loadNews() async {
        isLoadingNews = true
        defer { isLoadingNews = false }

        let apiKey = "" // API key configured via Firebase Remote Config
        let urlStr = "https://newsapi.org/v2/everything?q=faith+OR+church+OR+spiritual&language=en&pageSize=5&sortBy=publishedAt&apiKey=\(apiKey)"

        guard let url = URL(string: urlStr) else {
            newsItems = mockNewsItems
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let articles = json["articles"] as? [[String: Any]] else {
            newsItems = mockNewsItems
            return
        }

        let formatter = ISO8601DateFormatter()
        let parsed = articles.compactMap { a -> NewsItem? in
            guard let title = a["title"] as? String else { return nil }
            let src = (a["source"] as? [String: Any])?["name"] as? String ?? ""
            let dateStr = a["publishedAt"] as? String ?? ""
            let date = formatter.date(from: dateStr) ?? Date()
            let img = a["urlToImage"] as? String
            return NewsItem(headline: title, sourceName: src, publishedAt: date, imageURL: img, category: "Faith")
        }
        newsItems = parsed.isEmpty ? mockNewsItems : parsed
    }

    private var mockNewsItems: [NewsItem] {
        [
            NewsItem(headline: "New Study Shows Prayer's Impact on Mental Health", sourceName: "Christianity Today", publishedAt: Date().addingTimeInterval(-3600), imageURL: nil, category: "Faith"),
            NewsItem(headline: "Community Churches Partner for City-Wide Outreach", sourceName: "Church Times", publishedAt: Date().addingTimeInterval(-7200), imageURL: nil, category: "Community"),
            NewsItem(headline: "Biblical Archaeology: New Discoveries in Jerusalem", sourceName: "The Gospel Coalition", publishedAt: Date().addingTimeInterval(-10800), imageURL: nil, category: "Culture"),
        ]
    }

    private func loadBibleStudies() async {
        lazy var db = Firestore.firestore()
        do {
            let snap = try await db.collection("studies").limit(to: 6).getDocuments()
            let fetched = snap.documents.compactMap { doc -> BibleStudyItem? in
                let d = doc.data()
                guard let title = d["title"] as? String else { return nil }
                return BibleStudyItem(
                    id: doc.documentID,
                    title: title,
                    subtitle: d["subtitle"] as? String ?? "",
                    lessonCount: d["lessonCount"] as? Int ?? 8,
                    duration: d["duration"] as? String ?? "6 weeks",
                    rating: d["rating"] as? Double ?? 4.5,
                    enrolledCount: d["enrolledCount"] as? Int ?? 0,
                    emoji: d["emoji"] as? String ?? "📖",
                    coverGradient: [Color.indigo.opacity(0.7), Color.purple.opacity(0.5)]
                )
            }
            bibleStudies = fetched.isEmpty ? mockBibleStudies : fetched
        } catch {
            bibleStudies = mockBibleStudies
        }
    }

    private var mockBibleStudies: [BibleStudyItem] {
        [
            BibleStudyItem(id: "1", title: "The Sermon on the Mount", subtitle: "A deep study of Matthew 5–7", lessonCount: 12, duration: "6 weeks", rating: 4.8, enrolledCount: 1240, emoji: "⛰️", coverGradient: [Color(red: 0.11, green: 0.16, blue: 0.11), Color(red: 0.18, green: 0.29, blue: 0.16)]),
            BibleStudyItem(id: "2", title: "Psalms of Praise", subtitle: "Worship through the Psalms", lessonCount: 8, duration: "4 weeks", rating: 4.6, enrolledCount: 890, emoji: "🎵", coverGradient: [Color(red: 0.1, green: 0.1, blue: 0.25), Color(red: 0.3, green: 0.1, blue: 0.4)]),
            BibleStudyItem(id: "3", title: "Romans: The Gospel Unveiled", subtitle: "Paul's letter to the Romans", lessonCount: 16, duration: "8 weeks", rating: 4.9, enrolledCount: 2100, emoji: "✉️", coverGradient: [Color(red: 0.2, green: 0.1, blue: 0.05), Color(red: 0.4, green: 0.2, blue: 0.0)]),
        ]
    }

    private func loadDiscussions() async {
        lazy var db = Firestore.firestore()
        do {
            let snap = try await db.collection("discussions").order(by: "participantCount", descending: true).limit(to: 5).getDocuments()
            let fetched = snap.documents.compactMap { doc -> DiscussionItem? in
                let d = doc.data()
                guard let title = d["title"] as? String else { return nil }
                return DiscussionItem(
                    id: doc.documentID,
                    title: title,
                    subtitle: d["subtitle"] as? String ?? "",
                    iconName: d["iconName"] as? String ?? "bubble.left.and.bubble.right",
                    participantCount: d["participantCount"] as? Int ?? 0
                )
            }
            discussions = fetched.isEmpty ? mockDiscussions : fetched
        } catch {
            discussions = mockDiscussions
        }
    }

    private var mockDiscussions: [DiscussionItem] {
        [
            DiscussionItem(id: "1", title: "Faith & Mental Health", subtitle: "How do you cope with anxiety through faith?", iconName: "heart.text.square", participantCount: 234),
            DiscussionItem(id: "2", title: "Marriage & Family", subtitle: "Raising children in a faith-centered home", iconName: "house.fill", participantCount: 187),
            DiscussionItem(id: "3", title: "Modern Discipleship", subtitle: "What does following Jesus look like today?", iconName: "figure.walk", participantCount: 312),
            DiscussionItem(id: "4", title: "Worship Styles", subtitle: "Traditional vs contemporary — what's right?", iconName: "music.note", participantCount: 156),
        ]
    }

    private func loadUnsplashPhotos() async {
        let apiKey = "" // API key configured via Firebase Remote Config
        let queries = ["faith", "worship", "nature", "prayer", "church", "cross"]
        let q = queries[Int.random(in: 0..<queries.count)]
        let urlStr = "https://api.unsplash.com/search/photos?query=\(q)&per_page=9&client_id=\(apiKey)"

        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            // Fallback: empty (DiscoverMediaGridSection handles its own fallback)
            return
        }
        unsplashPhotos = results.compactMap { r -> UnsplashPhoto? in
            guard let id = r["id"] as? String,
                  let urls = r["urls"] as? [String: Any],
                  let thumb = urls["thumb"] as? String,
                  let regular = urls["regular"] as? String,
                  let user = r["user"] as? [String: Any],
                  let name = user["name"] as? String else { return nil }
            return UnsplashPhoto(id: id, thumbURL: thumb, regularURL: regular, photographerName: name)
        }
    }
}

// MARK: - Premium Hero Discovery Card (NEW)

struct AmenHeroDiscoveryCard: View {
    let title: String
    let tagLabel: String
    let tagIcon: String
    let accentColor: Color
    @State private var isPressed = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background: light tinted base + gradient overlay
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(white: 0.92))
                .frame(width: 280, height: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.black.opacity(0.05), .black.opacity(0.45)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    // Subtle dot-grid texture
                    Canvas { ctx, size in
                        let spacing: CGFloat = 18
                        for row in stride(from: 0, to: size.height, by: spacing) {
                            for col in stride(from: 0, to: size.width, by: spacing) {
                                ctx.fill(Path(ellipseIn: CGRect(x: col, y: row, width: 1.5, height: 1.5)),
                                         with: .color(.white.opacity(0.12)))
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                )

            // Glass bottom tray
            VStack(alignment: .leading, spacing: 6) {
                // Tag badge pill
                HStack(spacing: 5) {
                    Image(systemName: tagIcon)
                        .font(.systemScaled(10, weight: .semibold))
                        .foregroundColor(.white)
                    Text(tagLabel.uppercased())
                        .font(.systemScaled(10, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(0.8)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(accentColor.opacity(0.85))
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                )

                Text(title)
                    .font(.systemScaled(18, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.black.opacity(0.25))
                    )
            )
            .clipShape(
                RoundedCornerShape(radius: 28, corners: [.bottomLeft, .bottomRight])
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in isPressed = pressing }, perform: {})
    }
}

// Rounded corner helper for bottom-only rounding on the tray
private struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Premium Topic Grid Card (upgraded, alternating tall/normal)

struct AmenPremiumTopicGridCard: View {
    let topic: DiscoveryTopic
    let isTall: Bool
    let action: () -> Void
    @State private var isBookmarked = false
    @State private var isLiked = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                // Glass card background
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )

                VStack(spacing: 0) {
                    // Icon area — large centered SF symbol
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(topic.backgroundColor.opacity(0.5))

                        Image(systemName: topic.icon)
                            .font(.systemScaled(isTall ? 42 : 32, weight: .medium))
                            .foregroundColor(Color(white: 0.55))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: isTall ? 130 : 100)

                    // Glass info tray at bottom
                    VStack(alignment: .leading, spacing: 3) {
                        Text(topic.title)
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundColor(.black)
                            .lineLimit(1)
                        if topic.postCount > 0 {
                            Text("\(topic.postCount) posts")
                                .font(.systemScaled(11, weight: .regular))
                                .foregroundColor(Color(white: 0.45))
                        } else if let scripture = topic.relatedScripture {
                            Text(scripture)
                                .font(.systemScaled(10, weight: .regular))
                                .foregroundColor(Color(white: 0.45))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(Rectangle().fill(Color.white.opacity(0.5)))
                    )
                    .clipShape(
                        RoundedCornerShape(radius: 20, corners: [.bottomLeft, .bottomRight])
                    )
                }

                // No engagement badge shown per product invariant

                // Bookmark + heart buttons top-right
                VStack(alignment: .trailing, spacing: 6) {
                    Button {
                        isBookmarked.toggle()
                        HapticManager.impact(style: .light)
                    } label: {
                        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundColor(.black)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Circle().fill(Color.white.opacity(0.7)))
                                    .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark")

                    Button {
                        isLiked.toggle()
                        HapticManager.impact(style: .light)
                    } label: {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundColor(isLiked ? .red : .black)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Circle().fill(Color.white.opacity(0.7)))
                                    .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isLiked ? "Unlike" : "Like")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(10)
            }
            .frame(height: isTall ? 210 : 175)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in isPressed = pressing }, perform: {})
    }
}

// MARK: - Date Extension

private extension Date {
    func timeAgoString() -> String {
        let seconds = Int(-timeIntervalSinceNow)
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

// MARK: - Dark-mode verification harness (DEBUG only)
//
// Renders the REAL de-literaled editorial sections (no duplicated styling) across
// appearances so the dark-mode fix can be visually confirmed. These sections do not
// trigger the landing view's Firebase onAppear loads.

#if DEBUG
private extension AMENDiscoveryView {
    @ViewBuilder
    var debugEditorialSections: some View {
        ScrollView {
            VStack(spacing: 24) {
                amenHeroCardsSection
                exploreByTypeSection
                amenIntelligenceFooter
            }
            .padding(.vertical, 24)
        }
        .background(Color(.systemBackground))
    }
}

#Preview("Editorial — Light") {
    AMENDiscoveryView().debugEditorialSections
        .preferredColorScheme(.light)
}

#Preview("Editorial — Dark") {
    AMENDiscoveryView().debugEditorialSections
        .preferredColorScheme(.dark)
}

// Reduce Transparency note: these sections were converted from translucent material
// (`.ultraThinMaterial` + a white overlay) to fully OPAQUE semantic fills
// (`Color(.secondarySystemBackground)` / `.tertiarySystemBackground`). With no
// translucency left, Reduce Transparency has nothing to fall back from. There is also
// no writable `accessibilityReduceTransparency` environment key to force in a preview;
// confirm via Xcode canvas → Variants if desired.
#endif
