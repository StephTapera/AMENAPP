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
import FirebaseAuth

struct AMENDiscoveryView: View {

    @StateObject private var service = DiscoveryService.shared
    @ObservedObject private var followService = FollowService.shared

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var scrollOffset: CGFloat = 0
    @State private var showClearAllConfirm = false
    @State private var showBereanAI = false
    @AppStorage("hasSeenAISearchHint") private var hasSeenAISearchHint = false
    @State private var showAISearchHint = false

    // Navigation
    @State private var selectedTopic: DiscoveryTopic? = nil
    @State private var navigateToTopicPage = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Background
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Sticky search bar with Berean AI access
                    searchBarSection
                        .background(.ultraThinMaterial)
                        .zIndex(10)

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
            .fullScreenCover(isPresented: $showBereanAI) {
                BereanAIAssistantView()
            }
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
                    service.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField(searchPlaceholder, text: $searchText)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await service.submitSearch(searchText) }
                    }
                    .onChange(of: searchText) { _, newValue in
                        service.setQuery(newValue)
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        service.clearSearch()
                        isSearchFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.06))
            )

            // Berean AI button — labeled capsule so users know what it does
            if !isSearchFocused && searchText.isEmpty {
                Button {
                    HapticManager.impact(style: .medium)
                    showBereanAI = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Ask AI")
                            .font(.custom("OpenSans-SemiBold", size: 12))
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
                            .font(.custom("OpenSans-Regular", size: 11))
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
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
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
                    isSearchFocused = false
                }
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.primary)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSearchFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isShowingSubpage)
    }

    private var searchPlaceholder: String {
        "Search or ask Berean AI…"
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch service.searchState {
        case .landing:
            landingView
        case .typing:
            typeaheadView
        case .results(let query):
            DiscoverySearchResultsView(query: query)
        case .topicPage(let topic):
            DiscoveryTopicPageView(topic: topic)
        }
    }

    // MARK: - Landing View

    private var landingView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                // Topic chips
                topicChipsSection

                // Recent searches
                if !service.recentSearches.isEmpty {
                    recentSearchesSection
                }

                // What people are discussing (Trends)
                trendsSection

                // Berean AI — Ask scripture-grounded questions about anything you find
                bereanAIBannerSection

                // Premium "Suggested for you" — people, bible studies, communities, topics
                AMENSuggestionsSection(
                    peopleSuggestions: service.followSuggestions,
                    isLoadingPeople: service.isFollowSuggestionsLoading,
                    onFollowPerson: { userId in
                        Task { await service.followUser(userId: userId) }
                    },
                    onUnfollowPerson: { userId in
                        Task { await service.unfollowUser(userId: userId) }
                    },
                    onStudyTap: { _ in
                        // TODO: navigate to bible study flow
                    },
                    onCommunityTap: { topic in
                        selectedTopic = topic
                        service.selectTopic(topic)
                    }
                )

                // Popular topics grid
                popularTopicsSection

                // Spacer for tab bar
                Spacer().frame(height: 100)
            }
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
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
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.primary)
                Spacer()
                Button("Clear all") {
                    showClearAllConfirm = true
                }
                .font(.custom("OpenSans-Regular", size: 13))
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
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
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
                    .font(.custom("OpenSans-SemiBold", size: 17))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                Text("Summaries reviewed for safety and accuracy")
                    .font(.custom("OpenSans-Regular", size: 12))
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

    // MARK: - Follow Suggestions

    private var followSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested for you")
                .font(.custom("OpenSans-SemiBold", size: 17))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

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

    // MARK: - Popular Topics Grid

    // MARK: - Berean AI Banner

    private var bereanAIBannerSection: some View {
        Button {
            HapticManager.impact(style: .medium)
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ask Berean AI")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.primary)
                    Text("Scripture-grounded answers to any faith question")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
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

    private var popularTopicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular topics")
                .font(.custom("OpenSans-SemiBold", size: 17))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(service.popularTopics) { topic in
                    DiscoveryTopicGridCard(topic: topic) {
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
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text("Search for \"\(searchText)\"")
                                .font(.custom("OpenSans-Regular", size: 15))
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
                    HapticManager.impact(style: .medium)
                    showBereanAI = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Ask Berean AI")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            if !searchText.isEmpty {
                                Text("Ask Berean: \"\(searchText)\"")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Scripture-grounded answers")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11))
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

// MARK: - Topic Chip Button

struct TopicChipButton: View {
    let topic: DiscoveryTopic
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: topic.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(topic.iconColor)
                Text(topic.title)
                    .font(.custom("OpenSans-SemiBold", size: 13))
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
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(item.query)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
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
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: suggestion.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.text)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.primary)
                    if let subtitle = suggestion.subtitle {
                        Text(subtitle)
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if suggestion.type == .recentSearch {
                    Image(systemName: "arrow.up.left")
                        .font(.system(size: 11))
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
                        if trend.trendScore >= 70 {
                            Text("Trending")
                                .font(.custom("OpenSans-SemiBold", size: 10))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.1)))
                        }
                    }

                    Text(trend.title)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(trend.summary)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text("\(trend.discussionCount) discussions")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()

                if let thumb = trend.thumbnailURL {
                    AsyncImage(url: URL(string: thumb)) { img in
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
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 0.5))
            )
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
                    .font(.system(size: 18))
                    .foregroundStyle(topic.iconColor)
                    .frame(width: 40, height: 40)
                    .background(topic.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.title)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.primary)
                    Text(topic.description)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
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
                            .font(.custom("OpenSans-Bold", size: 20))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(String(suggestion.person.displayName.prefix(1)).uppercased())
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)

            VStack(spacing: 2) {
                Text(suggestion.person.displayName)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("@\(suggestion.person.username)")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let reason = suggestion.reason as String?, !reason.isEmpty {
                Text(reason)
                    .font(.custom("OpenSans-Regular", size: 11))
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
                    .font(.custom("OpenSans-SemiBold", size: 13))
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
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.5))
        )
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
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(topic.iconColor)
                    .frame(width: 36, height: 36)
                    .background(topic.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if topic.postCount > 0 {
                        Text("\(topic.postCount) posts")
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 0.5))
            )
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
