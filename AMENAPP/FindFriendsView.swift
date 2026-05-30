//
//  FindFriendsView.swift
//  AMENAPP
//

import SwiftUI
import FirebaseAuth

// MARK: - ViewModel

@MainActor
final class FindFriendsViewModel: ObservableObject {

    // MARK: State

    @Published var searchText: String = ""
    @Published var selectedInterest: FriendInterest = .all

    /// What is being shown: suggestions (empty query) or search results (non-empty query)
    @Published private(set) var displayMode: DisplayMode = .suggestions

    @Published private(set) var suggestions: [RecommendedUsersAIService.UserRecommendation] = []
    @Published private(set) var searchResults: [AlgoliaUserSuggestion] = []
    @Published private(set) var followStates: [String: Bool] = [:]   // userId → isFollowing
    @Published private(set) var pendingFollowIds: Set<String> = []

    @Published private(set) var isLoadingSuggestions = false
    @Published private(set) var isLoadingSearch = false
    @Published private(set) var searchError: String?

    enum DisplayMode { case suggestions, searchResults }

    private var searchTask: Task<Void, Never>?

    // MARK: Computed

    var filteredSuggestions: [RecommendedUsersAIService.UserRecommendation] {
        guard selectedInterest != .all else { return suggestions }
        return suggestions.filter { rec in
            rec.sharedInterests.contains {
                $0.localizedCaseInsensitiveContains(selectedInterest.rawValue)
            }
        }
    }

    var isLoadingAny: Bool { isLoadingSuggestions || isLoadingSearch }

    // MARK: Load suggestions

    func loadSuggestions() async {
        guard suggestions.isEmpty else { return }
        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }
        await RecommendedUsersAIService.shared.fetchRecommendations()
        suggestions = RecommendedUsersAIService.shared.recommendations
        await prefetchFollowStates(for: suggestions.map(\.id))
    }

    // MARK: Search

    func onSearchTextChanged(_ query: String) {
        searchTask?.cancel()
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            searchResults = []
            searchError = nil
            displayMode = .suggestions
            return
        }
        displayMode = .searchResults
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)   // 280 ms debounce
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }

    private func performSearch(query: String) async {
        isLoadingSearch = true
        searchError = nil
        defer { isLoadingSearch = false }
        do {
            let results = try await AlgoliaSearchService.shared.getUserSuggestions(query: query, limit: 20)
            guard !Task.isCancelled else { return }
            searchResults = results
            await prefetchFollowStates(for: results.map(\.id))
        } catch {
            guard !Task.isCancelled else { return }
            searchError = "Couldn't load results. Try again."
        }
    }

    // MARK: Follow

    func toggleFollow(userId: String) async {
        let currentlyFollowing = followStates[userId] ?? false
        // Optimistic update
        followStates[userId] = !currentlyFollowing
        pendingFollowIds.insert(userId)
        do {
            if currentlyFollowing {
                try await FollowService.shared.unfollowUser(userId: userId)
            } else {
                try await FollowService.shared.followUser(userId: userId)
                await FollowBurstCoordinator.shared.recordFollow(
                    targetUserId: userId,
                    targetIsPrivate: false,
                    internalProfileCluster: nil
                )
            }
        } catch {
            // Roll back
            followStates[userId] = currentlyFollowing
        }
        pendingFollowIds.remove(userId)
    }

    func isFollowing(_ userId: String) -> Bool { followStates[userId] ?? false }
    func isPending(_ userId: String) -> Bool    { pendingFollowIds.contains(userId) }

    // MARK: Private helpers

    private func prefetchFollowStates(for userIds: [String]) async {
        await withTaskGroup(of: (String, Bool).self) { group in
            for id in userIds where followStates[id] == nil {
                group.addTask {
                    let state = await FollowService.shared.isFollowing(userId: id)
                    return (id, state)
                }
            }
            for await (id, state) in group {
                followStates[id] = state
            }
        }
    }
}

// MARK: - FriendInterest

enum FriendInterest: String, CaseIterable {
    case all        = "All"
    case bibleStudy = "Bible Study"
    case prayer     = "Prayer"
    case sports     = "Sports"
    case music      = "Music"
    case ministry   = "Ministry"
    case youngAdults = "Young Adults"
}

// MARK: - FindFriendsView

struct FindFriendsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm = FindFriendsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                interestFilterRow
                Divider()
                contentBody
            }
            .navigationTitle("Find community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .task { await vm.loadSuggestions() }
        .onChange(of: vm.searchText) { _, new in vm.onSearchTextChanged(new) }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search community", text: $vm.searchText)
                .font(.custom("OpenSans-Regular", size: 16))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !vm.searchText.isEmpty {
                Button { vm.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemFill))
        )
        .padding(.horizontal)
        .padding(.top, 12)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: vm.searchText.isEmpty)
    }

    // MARK: Interest filter (visible in suggestions mode only)

    @ViewBuilder
    private var interestFilterRow: some View {
        if vm.displayMode == .suggestions {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FriendInterest.allCases, id: \.self) { interest in
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                vm.selectedInterest = interest
                            }
                        } label: {
                            Text(interest.rawValue)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(vm.selectedInterest == interest ? .white : .primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(vm.selectedInterest == interest
                                              ? Color.black
                                              : Color(.systemFill))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
            .transition(.opacity)
        }
    }

    // MARK: Content body

    @ViewBuilder
    private var contentBody: some View {
        if vm.isLoadingAny && vm.displayMode == .suggestions && vm.filteredSuggestions.isEmpty {
            loadingView
        } else if vm.displayMode == .suggestions {
            suggestionsBody
        } else {
            searchResultsBody
        }
    }

    // MARK: Suggestions body

    private var suggestionsBody: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    if vm.filteredSuggestions.isEmpty {
                        emptyState(
                            icon: "person.2.slash",
                            title: "No suggestions yet",
                            subtitle: "Follow a few people and we'll suggest others you might know."
                        )
                    } else {
                        ForEach(Array(vm.filteredSuggestions.enumerated()), id: \.element.id) { index, rec in
                            CommunityPersonRow(
                                id: rec.id,
                                name: rec.name,
                                username: rec.username,
                                profileImageURL: rec.profileImageURL,
                                subtitle: rec.matchReason,
                                pills: rec.sharedInterests,
                                isFollowing: vm.isFollowing(rec.id),
                                isPending: vm.isPending(rec.id),
                                onFollow: { Task { await vm.toggleFollow(userId: rec.id) } }
                            )
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            if index < vm.filteredSuggestions.count - 1 {
                                Divider().padding(.horizontal)
                            }
                        }
                    }
                } header: {
                    sectionHeader(title: "Suggested for you", icon: "sparkles", iconColor: .blue)
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: Search results body

    @ViewBuilder
    private var searchResultsBody: some View {
        if vm.isLoadingSearch {
            loadingView
        } else if let error = vm.searchError {
            emptyState(icon: "wifi.slash", title: "Something went wrong", subtitle: error)
        } else if vm.searchResults.isEmpty {
            emptyState(
                icon: "magnifyingglass",
                title: "No results for \"\(vm.searchText)\"",
                subtitle: "Try a different name or username."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(vm.searchResults.enumerated()), id: \.element.id) { index, user in
                        CommunityPersonRow(
                            id: user.id,
                            name: user.displayName,
                            username: "@\(user.username)",
                            profileImageURL: user.profileImageURL,
                            subtitle: "\(user.followersCount) followers",
                            pills: [],
                            isFollowing: vm.isFollowing(user.id),
                            isPending: vm.isPending(user.id),
                            onFollow: { Task { await vm.toggleFollow(userId: user.id) } }
                        )
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        if index < vm.searchResults.count - 1 {
                            Divider().padding(.horizontal)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in
                CommunityPersonRowSkeleton()
                    .padding(.horizontal)
            }
            Spacer()
        }
        .padding(.top, 12)
    }

    // MARK: Empty state

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.custom("OpenSans-Bold", size: 17))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: Section header

    private func sectionHeader(title: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.custom("OpenSans-Bold", size: 18))
            Image(systemName: icon)
                .foregroundStyle(iconColor)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}

// MARK: - CommunityPersonRow

struct CommunityPersonRow: View {
    let id: String
    let name: String
    let username: String
    let profileImageURL: String?
    let subtitle: String
    let pills: [String]
    let isFollowing: Bool
    let isPending: Bool
    let onFollow: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            avatar
            info
            Spacer(minLength: 8)
            followButton
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: Avatar

    private var avatar: some View {
        Group {
            if let urlString = profileImageURL, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsPlaceholder
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())
            } else {
                initialsPlaceholder
            }
        }
    }

    private var initialsPlaceholder: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: avatarGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 52, height: 52)
            Text(initials)
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    private var avatarGradient: [Color] {
        let palettes: [[Color]] = [
            [.blue, .purple], [.pink, .orange], [.green, .cyan],
            [.purple, .pink], [.orange, .yellow], [.teal, .blue]
        ]
        let index = abs(id.hashValue) % palettes.count
        return palettes[index]
    }

    // MARK: Info

    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.custom("OpenSans-SemiBold", size: 15))
                .lineLimit(1)
            Text(subtitle)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !pills.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(pills.prefix(3), id: \.self) { pill in
                            Text(pill)
                                .font(.custom("OpenSans-SemiBold", size: 11))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.blue.opacity(0.1)))
                        }
                    }
                }
            }
        }
    }

    // MARK: Follow button

    private var followButton: some View {
        Button(action: onFollow) {
            Group {
                if isPending {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.75)
                        .frame(width: 20, height: 20)
                } else {
                    HStack(spacing: 4) {
                        if isFollowing {
                            Image(systemName: "checkmark")
                                .font(.systemScaled(12, weight: .semibold))
                        }
                        Text(isFollowing ? "Following" : "Follow")
                            .font(.custom("OpenSans-Bold", size: 13))
                    }
                }
            }
            .foregroundStyle(isFollowing ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isFollowing ? Color(.systemFill) : Color.black)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPending)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: isFollowing)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: isPending)
    }
}

// MARK: - Skeleton row (loading placeholder)

struct CommunityPersonRowSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(.systemFill))
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemFill))
                    .frame(width: 130, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemFill))
                    .frame(width: 90, height: 10)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemFill))
                .frame(width: 72, height: 32)
        }
        .opacity(shimmer ? 0.4 : 1.0)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    FindFriendsView()
}
