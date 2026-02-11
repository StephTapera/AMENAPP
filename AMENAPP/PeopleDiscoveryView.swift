//
//  PeopleDiscoveryView.swift
//  AMENAPP
//
//  Created by Steph on 1/28/26.
//
//  Optimized view for discovering and connecting with other users
//  Features: Smart suggestions, fast image loading, glassmorphic design
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - People Discovery View

struct PeopleDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PeopleDiscoveryViewModel()
    @StateObject private var postSearchViewModel = PostSearchViewModel()
    @State private var searchText = ""
    @State private var selectedFilter: DiscoveryFilter = .suggested
    @State private var searchTask: Task<Void, Never>?
    @State private var suggestions: [AlgoliaUserSuggestion] = []
    @State private var showSuggestions = false
    @State private var selectedTab: DiscoveryTab = .people
    @State private var hasLoadedUsers = false

    enum DiscoveryTab: String, CaseIterable {
        case people = "People"
        case posts = "Posts"

        var icon: String {
            switch self {
            case .people: return "person.2.fill"
            case .posts: return "square.grid.2x2.fill"
            }
        }
    }

    enum DiscoveryFilter: String, CaseIterable {
        case suggested = "For You"
        case recent = "Recent"

        var icon: String {
            switch self {
            case .suggested: return "sparkles"
            case .recent: return "clock.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.96, blue: 0.98),
                        Color(red: 0.98, green: 0.98, blue: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Custom Header
                    customHeaderView

                    // Smart Tab Switcher
                    tabSwitcherView

                    // Content based on selected tab
                    if selectedTab == .people {
                        peopleContentView
                    } else {
                        postsContentView
                    }
                }
            }
            .overlay(alignment: .top) {
                if let error = viewModel.error {
                    ErrorBanner(message: error) {
                        viewModel.error = nil
                    }
                    .padding(.top, 60)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.error)
            .navigationBarHidden(true)
            .task {
                if !hasLoadedUsers {
                    await viewModel.loadUsers(filter: selectedFilter)
                    hasLoadedUsers = true
                }
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    // MARK: - Custom Header

    private var customHeaderView: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.6))
                    .contentShape(Circle())
            }
            .padding(.leading, 20)

            Spacer()

            Text("Discover")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.black)

            Spacer()

            Color.clear
                .frame(width: 44)
                .padding(.trailing, 20)
        }
        .frame(height: 56)
        .background(
            ZStack {
                Color.white.opacity(0.7)

                BlurView(style: .systemUltraThinMaterialLight)
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 0.5)
        }
    }

    // MARK: - Tab Switcher

    private var tabSwitcherView: some View {
        HStack(spacing: 0) {
            ForEach(DiscoveryTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedTab = tab
                        searchTask?.cancel()
                        searchText = ""
                        suggestions = []
                        showSuggestions = false
                    }
                } label: {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 15, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.custom("OpenSans-Bold", size: 15))
                        }
                        .foregroundStyle(selectedTab == tab ? .black : .black.opacity(0.4))
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)

                        // Animated liquid glass indicator
                        if selectedTab == tab {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.8),
                                            Color.black.opacity(0.6)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(height: 3)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Capsule()
                                .fill(Color.clear)
                                .frame(height: 3)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(
            ZStack {
                Color.white.opacity(0.5)
                BlurView(style: .systemUltraThinMaterialLight)
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 0.5)
        }
    }

    // MARK: - People Content

    private var peopleContentView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Search Bar
                searchBarView
                    .padding(.top, 20)

                // Filter Chips
                filterChipsView

                // Content
                if viewModel.isLoading && viewModel.users.isEmpty {
                    loadingView
                } else if viewModel.users.isEmpty {
                    emptyStateView
                } else {
                    usersListView
                }
            }
            .padding(.bottom, 30)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Posts Content

    private var postsContentView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Search bar for posts
                postSearchBarView
                    .padding(.top, 20)

                // Posts grid or empty state
                if postSearchViewModel.isLoading && postSearchViewModel.posts.isEmpty {
                    postLoadingView
                } else if postSearchViewModel.posts.isEmpty && !searchText.isEmpty {
                    postEmptyStateView
                } else if !postSearchViewModel.posts.isEmpty {
                    postsGridContent
                } else {
                    postWelcomeView
                }
            }
        }
        .refreshable {
            if !searchText.isEmpty {
                await postSearchViewModel.searchPosts(query: searchText)
            }
        }
    }

    private var postSearchBarView: some View {
        HStack(spacing: 12) {
            Group {
                if postSearchViewModel.isLoading && !searchText.isEmpty {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .foregroundStyle(.black.opacity(0.6))
            .frame(width: 20)

            TextField("Search posts, hashtags...", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 15))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchText) {
                    searchTask?.cancel()
                    searchTask = Task {
                        do {
                            try await Task.sleep(nanoseconds: 400_000_000)
                            guard !Task.isCancelled else { return }
                            await postSearchViewModel.searchPosts(query: searchText)
                        } catch {}
                    }
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchTask?.cancel()
                    searchText = ""
                    postSearchViewModel.clearResults()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.black.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.6))

                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.8), Color.white.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
    }

    private var postsGridContent: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3)
        ], spacing: 3) {
            ForEach(postSearchViewModel.posts) { post in
                PostThumbnailView(post: post)
            }
        }
        .padding(.top, 16)
    }

    private var postLoadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.black.opacity(0.6))
            Text("Searching posts...")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private var postEmptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 100, height: 100)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    }

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.black.opacity(0.4))
            }

            Text("No posts found")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.black)

            Text("Try different keywords or hashtags")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private var postWelcomeView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.8), Color.white.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 8)

                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.black.opacity(0.5))
            }

            VStack(spacing: 8) {
                Text("Search Posts")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.black)

                Text("Find posts by caption, hashtags, or location")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.black.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Popular hashtags
            VStack(alignment: .leading, spacing: 12) {
                Text("Try searching:")
                    .font(.custom("OpenSans-Bold", size: 12))
                    .foregroundStyle(.black.opacity(0.4))

                HStack(spacing: 8) {
                    ForEach(["#prayer", "#faith", "#blessed"], id: \.self) { tag in
                        Button {
                            searchText = tag
                        } label: {
                            Text(tag)
                                .font(.custom("OpenSans-Bold", size: 13))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.black.opacity(0.7), Color.black.opacity(0.5)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                                )
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Search Bar

    private var searchBarView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Group {
                    if viewModel.isLoading && !searchText.isEmpty {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                .foregroundStyle(.black.opacity(0.6))
                .frame(width: 20)

                TextField("Search people...", text: $searchText)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: searchText) {
                        searchTask?.cancel()
                        showSuggestions = !searchText.isEmpty

                        searchTask = Task {
                            do {
                                try await Task.sleep(nanoseconds: 400_000_000)
                                guard !Task.isCancelled else { return }

                                if !searchText.isEmpty {
                                    await loadSuggestions(query: searchText)
                                }

                                await viewModel.searchUsers(query: searchText)
                            } catch {}
                        }
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchTask?.cancel()
                        searchText = ""
                        suggestions = []
                        showSuggestions = false
                        Task {
                            await viewModel.loadUsers(filter: selectedFilter)
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.black.opacity(0.3))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.6))

                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.8), Color.white.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
            )

            // Autocomplete suggestions
            if showSuggestions && !suggestions.isEmpty {
                SearchSuggestionsView(
                    suggestions: suggestions,
                    onSelect: { (suggestion: AlgoliaUserSuggestion) in
                        searchTask?.cancel()
                        searchText = suggestion.username
                        showSuggestions = false
                        suggestions = []
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showSuggestions)
    }

    private func loadSuggestions(query: String) async {
        do {
            suggestions = try await AlgoliaSearchService.shared.getUserSuggestions(query: query, limit: 5)
        } catch {
            suggestions = []
        }
    }

    // MARK: - Filter Chips

    private var filterChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DiscoveryFilter.allCases, id: \.self) { filter in
                    PeopleFilterChip(
                        filter: filter,
                        isSelected: selectedFilter == filter
                    ) {
                        searchTask?.cancel()
                        searchText = ""

                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedFilter = filter
                        }
                        Task {
                            await viewModel.loadUsers(filter: filter)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Users List

    private var usersListView: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.users) { user in
                if let userId = user.id, !userId.isEmpty {
                    NavigationLink {
                        UserProfileView(userId: userId)
                            .navigationBarBackButtonHidden(false)
                            .toolbar(.visible, for: .navigationBar)
                    } label: {
                        CompactUserCard(user: user)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    CompactUserCard(user: user)
                        .opacity(0.6)
                }
            }

            // Load more trigger
            if viewModel.hasMore && !viewModel.isLoadingMore {
                Color.clear
                    .frame(height: 20)
                    .onAppear {
                        Task {
                            await viewModel.loadMore()
                        }
                    }
            }

            if viewModel.isLoadingMore {
                ProgressView()
                    .padding()
                    .tint(.black.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.black.opacity(0.6))

            Text("Discovering people...")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        Group {
            if !searchText.isEmpty {
                searchEmptyState
            } else {
                discoveryEmptyState
            }
        }
    }

    private var searchEmptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 100, height: 100)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    }

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.black.opacity(0.4))
            }

            Text("No results for \"\(searchText)\"")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Text("Try searching for a different username or name")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.black.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: {
                searchTask?.cancel()
                searchText = ""
                Task {
                    await viewModel.loadUsers(filter: selectedFilter)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Clear Search")
                        .font(.custom("OpenSans-Bold", size: 14))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.black.opacity(0.8), Color.black.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
                )
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var discoveryEmptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 100, height: 100)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    }

                Image(systemName: "person.2.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.black.opacity(0.4))
            }

            Text("No users to discover")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.black)

            Text("Check back later for new people to connect with")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.black.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

// MARK: - Discovery Filter Chip

struct PeopleFilterChip: View {
    let filter: PeopleDiscoveryView.DiscoveryFilter
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(filter.rawValue)
                    .font(.custom("OpenSans-Bold", size: 13))
            }
            .foregroundStyle(isSelected ? .white : .black.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.8), Color.black.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            }
                    } else {
                        Capsule()
                            .fill(Color.white.opacity(0.6))
                            .overlay {
                                Capsule()
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                            }
                    }
                }
            )
            .shadow(color: .black.opacity(isSelected ? 0.15 : 0.05), radius: isSelected ? 10 : 6, x: 0, y: isSelected ? 4 : 2)
            .scaleEffect(isSelected ? 1.0 : 0.98)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Compact User Card (Smaller Design)

struct CompactUserCard: View {
    let user: UserModel
    @State private var isFollowing = false
    @State private var optimisticFollowState: Bool?
    @StateObject private var followService = FollowService.shared

    var body: some View {
        HStack(spacing: 12) {
            // Avatar - smaller and faster loading
            FastProfileImage(
                url: user.profileImageURL,
                initials: user.initials,
                size: 48
            )

            // User Info - compact
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.black)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("@\(user.username)")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.black.opacity(0.5))
                        .lineLimit(1)

                    if user.postsCount > 0 {
                        Text("•")
                            .foregroundStyle(.black.opacity(0.3))
                        Text("\(user.postsCount) posts")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.black.opacity(0.4))
                    }
                }
            }

            Spacer(minLength: 8)

            // Compact Follow Button
            MiniFollowButton(isFollowing: .constant(optimisticFollowState ?? isFollowing)) {
                await toggleFollow()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.5))

                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.7), Color.white.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.8), Color.white.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
        .task {
            await loadFollowStatus()
        }
    }

    private func loadFollowStatus() async {
        guard let userId = user.id else { return }
        isFollowing = await followService.isFollowing(userId: userId)
    }

    private func toggleFollow() async {
        guard let userId = user.id else { return }
        guard optimisticFollowState == nil else { return }

        let previousState = isFollowing
        optimisticFollowState = !previousState

        do {
            if previousState {
                try await followService.unfollowUser(userId: userId)
            } else {
                try await followService.followUser(userId: userId)
            }

            await MainActor.run {
                isFollowing = !previousState
                optimisticFollowState = nil
            }
        } catch {
            await MainActor.run {
                optimisticFollowState = nil
                let errorHaptic = UINotificationFeedbackGenerator()
                errorHaptic.notificationOccurred(.error)
            }
        }
    }
}

// MARK: - Fast Profile Image

struct FastProfileImage: View {
    let url: String?
    let initials: String
    let size: CGFloat

    @State private var cachedImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let cachedImage = cachedImage {
                Image(uiImage: cachedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.black.opacity(0.7), Color.black.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size, height: size)

                    Text(initials)
                        .font(.custom("OpenSans-Bold", size: size * 0.4))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
                .onAppear {
                    loadImage()
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func loadImage() {
        guard let urlString = url,
              !urlString.isEmpty,
              let imageURL = URL(string: urlString),
              !isLoading else {
            return
        }

        isLoading = true

        Task {
            // Check cache first
            if let cached = await ProfileImageCache.shared.get(forKey: urlString) {
                await MainActor.run {
                    cachedImage = cached
                    isLoading = false
                }
                return
            }

            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)

                if let downloadedImage = UIImage(data: data) {
                    let resizedImage = await resizeImage(downloadedImage, targetSize: CGSize(width: size * 2, height: size * 2))
                    await ProfileImageCache.shared.set(resizedImage, forKey: urlString)

                    await MainActor.run {
                        cachedImage = resizedImage
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }

    private func resizeImage(_ image: UIImage, targetSize: CGSize) async -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

// MARK: - Mini Follow Button

struct MiniFollowButton: View {
    @Binding var isFollowing: Bool
    let action: () async -> Void
    @State private var isPressed = false

    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            HStack(spacing: 4) {
                if !isFollowing {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(isFollowing ? "Following" : "Follow")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            .foregroundStyle(isFollowing ? Color.black.opacity(0.6) : Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Group {
                    if isFollowing {
                        Capsule()
                            .fill(Color.white.opacity(0.5))
                            .overlay {
                                Capsule()
                                    .stroke(Color.black.opacity(0.15), lineWidth: 1)
                            }
                    } else {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.8), Color.black.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            }
                    }
                }
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .shadow(color: .black.opacity(isFollowing ? 0.05 : 0.15), radius: isFollowing ? 4 : 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - View Model

@MainActor
final class PeopleDiscoveryViewModel: ObservableObject {
    @Published private(set) var users: [UserModel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var error: String?

    private let db = Firestore.firestore()
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 20
    private var currentSearchQuery: String?
    private var currentFilter: PeopleDiscoveryView.DiscoveryFilter = .suggested

    func loadUsers(filter: PeopleDiscoveryView.DiscoveryFilter) async {
        guard !isLoading else { return }

        isLoading = true
        lastDocument = nil
        error = nil
        currentFilter = filter
        currentSearchQuery = nil

        do {
            users = try await fetchUsers(filter: filter, limit: pageSize)
            hasMore = users.count >= pageSize
            prefetchProfileImages(for: users)
        } catch {
            handleError(error, context: "loading users")
        }

        isLoading = false
    }

    func loadMore() async {
        guard !isLoadingMore && hasMore && !isLoading else { return }

        isLoadingMore = true

        do {
            let newUsers: [UserModel]

            if let searchQuery = currentSearchQuery {
                newUsers = []
            } else {
                newUsers = try await fetchUsers(filter: currentFilter, limit: pageSize, afterDocument: lastDocument)
            }

            users.append(contentsOf: newUsers)
            hasMore = newUsers.count >= pageSize
            prefetchProfileImages(for: newUsers)
        } catch {
            handleError(error, context: "loading more users")
        }

        isLoadingMore = false
    }

    func refresh() async {
        error = nil

        if let searchQuery = currentSearchQuery {
            await searchUsers(query: searchQuery)
        } else {
            await loadUsers(filter: currentFilter)
        }
    }

    func searchUsers(query: String) async {
        guard !isLoading else { return }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            currentSearchQuery = nil
            error = nil
            await loadUsers(filter: currentFilter)
            return
        }

        isLoading = true
        error = nil
        currentSearchQuery = trimmedQuery
        lastDocument = nil

        do {
            let algoliaUsers = try await AlgoliaSearchService.shared.searchUsers(
                query: trimmedQuery,
                limit: pageSize
            )

            users = algoliaUsers.map { $0.toUserModel() }
            hasMore = false
        } catch {
            do {
                users = try await performFirestoreSearch(query: trimmedQuery)
                hasMore = false
            } catch {
                handleError(error, context: "searching users")
            }
        }

        isLoading = false
    }

    private func performFirestoreSearch(query: String) async throws -> [UserModel] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw PeopleDiscoveryError.notAuthenticated
        }

        let lowercaseQuery = query.lowercased()
        var results: [UserModel] = []

        let usernameSnapshot = try await db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: lowercaseQuery)
            .whereField("username", isLessThanOrEqualTo: lowercaseQuery + "\u{f8ff}")
            .limit(to: pageSize)
            .getDocuments()

        for doc in usernameSnapshot.documents {
            do {
                var user = try doc.data(as: UserModel.self)
                user.id = doc.documentID
                results.append(user)
            } catch {}
        }

        if results.count < 5 {
            let nameSnapshot = try await db.collection("users")
                .whereField("displayName", isGreaterThanOrEqualTo: query)
                .whereField("displayName", isLessThanOrEqualTo: query + "\u{f8ff}")
                .limit(to: pageSize)
                .getDocuments()

            var nameResults: [UserModel] = []
            for doc in nameSnapshot.documents {
                do {
                    var user = try doc.data(as: UserModel.self)
                    user.id = doc.documentID
                    nameResults.append(user)
                } catch {}
            }

            for user in nameResults {
                if !results.contains(where: { $0.id == user.id }) {
                    results.append(user)
                }
            }
        }

        return results.filter { $0.id != currentUserId }
    }

    private func fetchUsers(filter: PeopleDiscoveryView.DiscoveryFilter, limit: Int, afterDocument: DocumentSnapshot? = nil) async throws -> [UserModel] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw PeopleDiscoveryError.notAuthenticated
        }

        var query = db.collection("users")
            .limit(to: limit)

        switch filter {
        case .suggested:
            // Smart suggestion algorithm:
            // 1. Get users you're NOT following
            // 2. Score by: (followers * 2) + (posts * 1) + (engagement rate * 3)
            // 3. Filter out inactive users (no posts in 90 days - if we track that)
            // 4. Personalize based on interests (future enhancement)

            let followingSnapshot = try await db.collection("users")
                .document(currentUserId)
                .collection("following")
                .getDocuments()

            let followingIds = Set(followingSnapshot.documents.map { $0.documentID })

            // Query for active users sorted by engagement
            query = query
                .order(by: "followersCount", descending: true)
                .order(by: "postsCount", descending: true)

            if let afterDocument = afterDocument {
                query = query.start(afterDocument: afterDocument)
            }

            let snapshot = try await query.getDocuments()
            lastDocument = snapshot.documents.last

            var fetchedUsers: [UserModel] = []
            for doc in snapshot.documents {
                do {
                    var user = try doc.data(as: UserModel.self)
                    user.id = doc.documentID
                    fetchedUsers.append(user)
                } catch {}
            }

            let filtered = fetchedUsers.filter { user in
                guard let userId = user.id else { return false }
                return userId != currentUserId && !followingIds.contains(userId)
            }
            return filtered

        case .recent:
            query = query.order(by: "createdAt", descending: true)

            if let afterDocument = afterDocument {
                query = query.start(afterDocument: afterDocument)
            }

            let snapshot = try await query.getDocuments()
            lastDocument = snapshot.documents.last

            var fetchedUsers: [UserModel] = []
            for doc in snapshot.documents {
                do {
                    var user = try doc.data(as: UserModel.self)
                    user.id = doc.documentID
                    fetchedUsers.append(user)
                } catch {}
            }

            let filtered = fetchedUsers.filter { $0.id != nil && $0.id != currentUserId }
            return filtered
        }
    }

    private func handleError(_ error: Error, context: String) {
        if let discoveryError = error as? PeopleDiscoveryError {
            self.error = discoveryError.userMessage
        } else {
            self.error = "Something went wrong. Please try again."
        }
    }
}

// MARK: - Error Types

private enum PeopleDiscoveryError: LocalizedError {
    case notAuthenticated
    case searchFailed
    case loadFailed

    var userMessage: String {
        switch self {
        case .notAuthenticated:
            return "Please sign in to continue."
        case .searchFailed:
            return "Search failed. Please try again."
        case .loadFailed:
            return "Failed to load users. Please try again."
        }
    }

    var errorDescription: String? {
        userMessage
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.white)
                .lineLimit(2)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.9))
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
        )
    }
}

// MARK: - Blur View Helper

struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

// MARK: - Profile Image Cache

actor ProfileImageCache {
    static let shared = ProfileImageCache()

    private var cache: [String: UIImage] = [:]
    private let maxCacheSize = 100
    private var accessOrder: [String] = []

    private init() {}

    func get(forKey key: String) -> UIImage? {
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
            accessOrder.append(key)
        }
        return cache[key]
    }

    func set(_ image: UIImage, forKey key: String) {
        if cache.count >= maxCacheSize, let oldestKey = accessOrder.first {
            cache.removeValue(forKey: oldestKey)
            accessOrder.removeFirst()
        }

        cache[key] = image
        accessOrder.append(key)
    }

    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }
}

// MARK: - Image Prefetcher

func prefetchProfileImages(for users: [UserModel]) {
    Task.detached(priority: .utility) {
        for user in users {
            guard let urlString = user.profileImageURL,
                  !urlString.isEmpty,
                  let url = URL(string: urlString) else {
                continue
            }

            if await ProfileImageCache.shared.get(forKey: urlString) != nil {
                continue
            }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    let targetSize = CGSize(width: 96, height: 96)
                    let renderer = UIGraphicsImageRenderer(size: targetSize)
                    let resizedImage = renderer.image { _ in
                        image.draw(in: CGRect(origin: .zero, size: targetSize))
                    }

                    await ProfileImageCache.shared.set(resizedImage, forKey: urlString)
                }
            } catch {}
        }
    }
}

// MARK: - Preview

#Preview {
    PeopleDiscoveryView()
}
