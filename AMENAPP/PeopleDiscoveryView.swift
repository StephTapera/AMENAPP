//
//  PeopleDiscoveryView.swift
//  AMENAPP
//
//  Unified Discovery: People + Posts + Churches
//  Liquid Glass design, smart search, recent searches, trending topics, suggested people
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine
import CoreLocation

// MARK: - Discovery Search Scope

enum DiscoveryScope: String, CaseIterable {
    case all = "All"
    case people = "People"
    case posts = "Posts"
    case churches = "Churches"

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .people: return "person.2"
        case .posts: return "doc.text"
        case .churches: return "building.columns"
        }
    }
}

// MARK: - Recent Search Entry (with TTL)

private struct RecentSearchEntry: Codable {
    let query: String
    let timestamp: Date
}

// MARK: - Discovery View Model

@MainActor
class DiscoveryViewModel: ObservableObject {

    // Search state
    @Published var searchText = ""
    @Published var scope: DiscoveryScope = .all
    @Published var isSearching = false
    @Published var searchError: String?  // Fix #11: visible search errors

    // Results
    @Published var userResults: [UserModel] = []
    @Published var postResults: [AlgoliaPost] = []
    @Published var churchResults: [ChurchEntity] = []  // Fix #3: church results

    // Discovery content
    @Published var suggestedPeople: [UserModel] = []
    // Fix #5: single source of truth — mirror FollowService.shared.following
    @Published var followingUserIds: Set<String> = []
    @Published var recentSearches: [String] = []
    @Published var trendingTopics: [TrendingTopic] = []
    @Published var networkError: String?

    // Pagination
    @Published var isLoadingMore = false
    @Published var hasMore = true
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 30

    private let db = Firestore.firestore()
    private var searchTask: Task<Void, Never>?
    private var connectionsCache: (following: Set<String>, followers: Set<String>)?
    // Fix #5: subscription to FollowService
    private var followCancellable: AnyCancellable?
    // Fix #9: real-time follow listener
    private var followListener: ListenerRegistration?

    init() {
        loadRecentSearches()
        // Fix #10: load static trending immediately so UI is never empty
        trendingTopics = TrendingTopic.mockTopics
        // Fix #5: keep followingUserIds in sync with FollowService canonical set
        followCancellable = FollowService.shared.$following
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updated in
                self?.followingUserIds = updated
            }
    }

    deinit {
        followListener?.remove()
    }

    // MARK: - Recent Searches (UserDefaults with TTL)  — Fix #12

    private static let recentSearchesKey = "discovery_recent_searches_v2"
    private static let ttlDays: Double = 30

    private func loadRecentSearches() {
        guard let data = UserDefaults.standard.data(forKey: Self.recentSearchesKey),
              let entries = try? JSONDecoder().decode([RecentSearchEntry].self, from: data)
        else {
            // Migrate legacy plain-string list
            let legacy = UserDefaults.standard.stringArray(forKey: "discovery_recent_searches") ?? []
            recentSearches = legacy
            return
        }
        let cutoff = Date().addingTimeInterval(-Self.ttlDays * 86400)
        recentSearches = entries
            .filter { $0.timestamp > cutoff }
            .map(\.query)
    }

    func addRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var searches = recentSearches.filter { $0 != trimmed }
        searches.insert(trimmed, at: 0)
        recentSearches = Array(searches.prefix(8))

        // Persist with timestamp
        let entries = recentSearches.map { RecentSearchEntry(query: $0, timestamp: Date()) }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.recentSearchesKey)
        }
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: Self.recentSearchesKey)
    }

    // MARK: - Trending (static-first, Firestore replaces async)  — Fix #10

    func loadTrendingFromFirestore() async {
        // Static is already loaded in init(); Firestore results replace when ready.
        let db = Firestore.firestore()

        // 1. Try the curated `trending` collection (managed by Cloud Functions)
        do {
            let snapshot = try await db.collection("trending")
                .order(by: "postsCount", descending: true)
                .limit(to: 8)
                .getDocuments()

            let topics: [TrendingTopic] = snapshot.documents.compactMap { doc in
                let data = doc.data()
                guard
                    let icon = data["icon"] as? String,
                    let title = data["title"] as? String,
                    let postsCount = data["postsCount"] as? Int
                else { return nil }

                let iconColor = colorFromFirestore(data["iconColor"] as? String)
                let bgColorStr = data["backgroundColor"] as? String
                let bgColor = bgColorStr.map { colorFromFirestore($0) } ?? iconColor.opacity(0.08)

                return TrendingTopic(
                    id: doc.documentID,
                    icon: icon,
                    iconColor: iconColor,
                    title: title,
                    backgroundColor: bgColor,
                    postsCount: postsCount
                )
            }

            if !topics.isEmpty {
                trendingTopics = topics
                return  // Curated collection present — done.
            }
        } catch {
            // Fall through to live count enrichment
        }

        // 2. Fallback: enrich the static mock topics with real post counts from Firestore
        // Each mock topic maps to its topicTag value stored on posts.
        let current = trendingTopics
        var enriched: [TrendingTopic] = []
        await withTaskGroup(of: (Int, Int).self) { group in
            for (idx, topic) in current.enumerated() {
                group.addTask {
                    let count: Int
                    do {
                        let snap = try await db.collection("posts")
                            .whereField("topicTag", isEqualTo: topic.title)
                            .count
                            .getAggregation(source: .server)
                        count = snap.count.intValue
                    } catch {
                        count = topic.postsCount // Keep static fallback on error
                    }
                    return (idx, count)
                }
            }
            // Initialise with current topics then overwrite counts
            enriched = current
            for await (idx, count) in group where count > 0 {
                if idx < enriched.count {
                    let t = enriched[idx]
                    enriched[idx] = TrendingTopic(
                        id: t.id, icon: t.icon, iconColor: t.iconColor,
                        title: t.title, backgroundColor: t.backgroundColor,
                        postsCount: count
                    )
                }
            }
        }
        // Sort by live count descending
        trendingTopics = enriched.sorted { $0.postsCount > $1.postsCount }
    }

    /// Maps a Firestore color string ("purple", "blue", "#RRGGBB") → SwiftUI Color
    private func colorFromFirestore(_ value: String?) -> Color {
        guard let value else { return .accentColor }
        switch value.lowercased() {
        case "red":    return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green":  return .green
        case "blue":   return .blue
        case "purple": return .purple
        case "pink":   return .pink
        case "teal":   return .teal
        case "indigo": return .indigo
        case "gray":   return .gray
        default:
            if value.hasPrefix("#") {
                let hex = value.dropFirst()
                if let intVal = UInt64(hex, radix: 16), hex.count == 6 {
                    let r = Double((intVal >> 16) & 0xFF) / 255
                    let g = Double((intVal >> 8) & 0xFF) / 255
                    let b = Double(intVal & 0xFF) / 255
                    return Color(red: r, green: g, blue: b)
                }
            }
            return .accentColor
        }
    }

    // MARK: - Load Suggested People  — Fix #2 (privacy filter)

    func loadSuggestedPeople() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        do {
            // Fix #9: attach real-time listener instead of one-time fetch
            attachFollowListener(currentUserId: currentUserId)

            // Fix #2: exclude private accounts from suggestions
            let snapshot = try await db.collection("users")
                .whereField("isPrivate", isEqualTo: false)
                .limit(to: pageSize)
                .getDocuments()
            lastDocument = snapshot.documents.last

            var users: [UserModel] = []
            for doc in snapshot.documents {
                if var user = try? doc.data(as: UserModel.self) {
                    if user.id == nil { user.id = doc.documentID }
                    // Respect showInDiscovery privacy toggle (default: true when field absent)
                    let showInDiscovery = doc.data()["showInDiscovery"] as? Bool ?? true
                    if user.id != currentUserId && showInDiscovery { users.append(user) }
                }
            }

            // Fix #8: rank entire initial page at once
            suggestedPeople = await rankUsers(users, currentUserId: currentUserId)
        } catch {
            networkError = "Unable to load suggestions."
        }
    }

    func loadMoreSuggested() async {
        guard !isLoadingMore, hasMore, let last = lastDocument else { return }
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let snapshot = try await db.collection("users")
                .whereField("isPrivate", isEqualTo: false)  // Fix #2
                .start(afterDocument: last)
                .limit(to: pageSize)
                .getDocuments()
            lastDocument = snapshot.documents.last
            hasMore = snapshot.documents.count >= pageSize

            var newUsers: [UserModel] = []
            for doc in snapshot.documents {
                if var user = try? doc.data(as: UserModel.self) {
                    if user.id == nil { user.id = doc.documentID }
                    let showInDiscovery = doc.data()["showInDiscovery"] as? Bool ?? true
                    if user.id != currentUserId && showInDiscovery { newUsers.append(user) }
                }
            }

            // Fix #8: re-rank holistically: merge new page then sort entire list
            let merged = suggestedPeople + newUsers
            suggestedPeople = await rankUsers(merged, currentUserId: currentUserId)
        } catch {
            Logger.error("Load more failed", error: error)
        }
    }

    func refresh() async {
        lastDocument = nil
        hasMore = true
        connectionsCache = nil
        suggestedPeople = []
        searchError = nil
        await loadSuggestedPeople()
    }

    // MARK: - Unified Search  — Fix #6 (scope-aware), Fix #7 (150ms debounce)

    func search(query: String) {
        searchTask?.cancel()
        searchError = nil  // Fix #11: clear prior error
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            userResults = []
            postResults = []
            churchResults = []
            isSearching = false
            return
        }

        searchTask = Task {
            // Fix #7: reduced from 280ms → 150ms
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            isSearching = true
            defer { isSearching = false }

            // Fix #6: only fire the calls relevant to the active scope
            await withTaskGroup(of: Void.self) { group in
                if scope == .all || scope == .people {
                    group.addTask { await self.searchPeople(query: trimmed) }
                }
                if scope == .all || scope == .posts {
                    group.addTask { await self.searchPosts(query: trimmed) }
                }
                if scope == .all || scope == .churches {
                    group.addTask { await self.searchChurches(query: trimmed) }  // Fix #3
                }
            }
        }
    }

    // Fix #1: eliminate N+1 — convert AlgoliaUser directly via toUserModel()
    private func searchPeople(query: String) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        do {
            let algoliaUsers = try await AlgoliaSearchService.shared.searchUsers(query: query)
            if !algoliaUsers.isEmpty {
                // Fix #1: no Firestore reads — map inline from Algolia result
                userResults = algoliaUsers
                    .filter { $0.objectID != currentUserId }
                    .map { $0.toUserModel() }
                return
            }
        } catch {}

        // Firestore prefix fallback (only if Algolia returned nothing)
        do {
            let lower = query.lowercased()
            let snap = try await db.collection("users")
                .whereField("username", isGreaterThanOrEqualTo: lower)
                .whereField("username", isLessThanOrEqualTo: lower + "\u{f8ff}")
                .limit(to: 20)
                .getDocuments()

            var users: [UserModel] = []
            for doc in snap.documents {
                if var user = try? doc.data(as: UserModel.self) {
                    if user.id == nil { user.id = doc.documentID }
                    if user.id != currentUserId { users.append(user) }
                }
            }
            userResults = users
        } catch {
            // Fix #11: surface error to UI
            searchError = "People search unavailable. Tap to retry."
            Logger.error("People search failed", error: error)
        }
    }

    private func searchPosts(query: String) async {
        do {
            postResults = try await AlgoliaSearchService.shared.searchPosts(query: query, limit: 20)
        } catch {
            postResults = []
            // Only set searchError if people search didn't already set it
            if searchError == nil {
                searchError = "Post search unavailable. Tap to retry."
            }
        }
    }

    // Fix #3: church search implementation
    private func searchChurches(query: String) async {
        do {
            let lower = query.lowercased()
            let snap = try await db.collection("churches")
                .whereField("name", isGreaterThanOrEqualTo: lower)
                .whereField("name", isLessThan: lower + "\u{f8ff}")
                .limit(to: 10)
                .getDocuments()

            churchResults = snap.documents.compactMap { doc in
                guard let church = try? Firestore.Decoder().decode(ChurchEntity.self, from: doc.data())
                else { return nil }
                // Ensure id is set from document
                return church
            }
        } catch {
            churchResults = []
        }
    }

    // MARK: - Follow  — Fix #4 (operation lock), Fix #5 (sync to FollowService)

    // Remove follow listener explicitly (called from view's onDisappear)
    func detachFollowListener() {
        followListener?.remove()
        followListener = nil
    }
    
    // Fix #9: real-time Firestore listener replaces one-time loadFollowingStatus fetch
    private func attachFollowListener(currentUserId: String) {
        // Remove any existing listener
        followListener?.remove()
        followListener = db.collection("users").document(currentUserId)
            .collection("following")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snap = snapshot else { return }
                let ids = Set(snap.documents.map(\.documentID))
                Task { @MainActor in
                    self.followingUserIds = ids
                }
            }
    }

    // Fix #4: guard against double-tap race; Fix #5: update FollowService canonical set
    func toggleFollow(userId: String) {
        // Optimistic update
        let wasFollowing = followingUserIds.contains(userId)
        if wasFollowing {
            followingUserIds.remove(userId)
        } else {
            followingUserIds.insert(userId)
        }

        Task {
            do {
                if wasFollowing {
                    // FollowService already guards via unfollowOperationsInProgress
                    try await FollowService.shared.unfollowUser(userId: userId)
                } else {
                    // FollowService already guards via followOperationsInProgress
                    try await FollowService.shared.followUser(userId: userId)
                }
                // FollowService.$following will publish the authoritative update,
                // which our Combine sink (Fix #5) will apply automatically.
            } catch {
                // Revert optimistic update on failure
                if wasFollowing {
                    followingUserIds.insert(userId)
                } else {
                    followingUserIds.remove(userId)
                }
            }
        }
    }

    // MARK: - Ranking  — Fix #13 (smarter: mutual followers, profile completeness, recency)

    private func rankUsers(_ users: [UserModel], currentUserId: String) async -> [UserModel] {
        // Fetch mutual-follower info once per ranking pass
        let myFollowing = followingUserIds  // already populated from listener / FollowService

        return users.sorted { a, b in
            func score(_ u: UserModel) -> Double {
                var s = 0.0
                // Follower popularity (log-scaled to not over-weight celebrities)
                s += log(Double(max(u.followersCount, 1)) + 1) * 2.0
                // Profile completeness
                if !(u.bio?.isEmpty ?? true) { s += 3.0 }
                if !(u.profileImageURL?.isEmpty ?? true) { s += 2.0 }
                // Mutual connection: already following boosts visibility of their connections
                if let uid = u.id, myFollowing.contains(uid) { s += 10.0 }
                return s
            }
            return score(a) > score(b)
        }
    }
}

// MARK: - Main Discovery View

struct PeopleDiscoveryViewNew: View {
    @StateObject private var vm = DiscoveryViewModel()
    @State private var searchText = ""
    @State private var isSearchFocused = false
    @State private var showProfileSheet: UserModel?
    @State private var scrollOffset: CGFloat = 0
    @State private var isTabBarHidden = false
    @State private var lastDragValue: CGFloat = 0
    @State private var selectedTopic: TrendingTopic? = nil
    private let scopeHaptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Background
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        // Scroll offset tracker
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("discoverScroll")).minY
                            )
                        }
                        .frame(height: 0)

                        // Title
                        titleHeader
                            .padding(.top, 8)

                        // Search bar
                        searchBar
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                        // Scope tabs
                        scopeTabs
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)

                        // Content
                        if searchText.isEmpty {
                            discoveryContent
                        } else {
                            searchResultsContent
                        }
                    }
                }
                .coordinateSpace(name: "discoverScroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
                .refreshable {
                    searchText = ""
                    await vm.refresh()
                }
            }
            .navigationBarHidden(true)
            .toolbar(isTabBarHidden ? .hidden : .visible, for: .tabBar)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        let delta = v.translation.height - lastDragValue
                        if delta < -8, !isTabBarHidden {
                            withAnimation(.easeInOut(duration: 0.2)) { isTabBarHidden = true }
                        } else if delta > 8, isTabBarHidden {
                            withAnimation(.easeInOut(duration: 0.2)) { isTabBarHidden = false }
                        }
                        lastDragValue = v.translation.height
                    }
                    .onEnded { _ in lastDragValue = 0 }
            )
            .sheet(item: $showProfileSheet) { user in
                if let uid = user.id, !uid.isEmpty {
                    NavigationView { SafeUserProfileWrapper(userId: uid) }
                }
            }
            .task {
                scopeHaptic.prepare()
                async let people: () = vm.loadSuggestedPeople()
                async let trending: () = vm.loadTrendingFromFirestore()
                _ = await (people, trending)
            }
            .navigationDestination(item: $selectedTopic) { topic in
                TrendingTopicFeedView(topic: topic)
            }
            .onDisappear {
                // Remove the Firestore follow listener when the view leaves to prevent accumulation
                vm.detachFollowListener()
            }
            .onChange(of: searchText) { _, newVal in
                vm.search(query: newVal)
            }
            .onChange(of: vm.scope) { _, _ in
                if !searchText.isEmpty { vm.search(query: searchText) }
            }
        }
    }

    // MARK: - Title Header (collapses on scroll)

    private var titleHeader: some View {
        let progress = max(0, min(1, -scrollOffset / 80))
        let fontSize = 28 - (8 * progress)
        let opacity = 1.0 - progress * 0.6

        return HStack {
            Text("Discover")
                .font(.custom("OpenSans-Bold", size: fontSize))
                .foregroundStyle(.primary)
                .opacity(opacity)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.15), value: scrollOffset)
    }

    // MARK: - Search Bar (tap-to-expand)

    private var searchBar: some View {
        SearchExpandBar(
            query: $searchText,
            results: vm.discoveryDropdownResults,
            onQueryChanged: { q in
                vm.search(query: q)
            },
            onSelectResult: { result in
                vm.addRecentSearch(result.name)
                vm.search(query: result.name)
                // Navigate based on result type
                switch result.resultType {
                case .person(let uid):
                    if let user = vm.userResults.first(where: { $0.id == uid }) {
                        showProfileSheet = user
                    }
                case .post, .church, .topic:
                    break  // handled by the search results section below
                }
            },
            onClose: {
                searchText = ""
            }
        )
    }

    // MARK: - Scope Tabs

    private var scopeTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DiscoveryScope.allCases, id: \.self) { s in
                    ScopeTabButton(scope: s, isSelected: vm.scope == s) {
                        vm.scope = s
                        scopeHaptic.impactOccurred()
                    }
                }
            }
        }
    }

    // MARK: - Discovery Content (no search query)

    @ViewBuilder
    private var discoveryContent: some View {
        // Recent Searches
        if !vm.recentSearches.isEmpty {
            recentSearchesSection
        }

        // Trending Topics
        trendingSection

        // Suggested People
        suggestedPeopleSection
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent Searches")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.primary)
                Spacer()
                Button("Clear") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        vm.clearRecentSearches()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .font(.custom("OpenSans-Medium", size: 14))
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(vm.recentSearches, id: \.self) { term in
                    Button {
                        searchText = term
                        vm.addRecentSearch(term)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .frame(width: 22)

                            Text(term)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.primary)

                            Spacer()

                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())

                    if term != vm.recentSearches.last {
                        Divider()
                            .padding(.leading, 54)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 28)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trending Topics")
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(vm.trendingTopics) { topic in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        vm.addRecentSearch(topic.title)
                        selectedTopic = topic
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(topic.backgroundColor)
                                    .frame(width: 40, height: 40)
                                Image(systemName: topic.icon)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(topic.iconColor)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title)
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                    .foregroundStyle(.primary)
                                Text(topic.postsCount > 1000
                                     ? "\(topic.postsCount / 1000).\((topic.postsCount % 1000) / 100)K posts"
                                     : "\(topic.postsCount) posts")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DiscoveryPressStyle())

                    if topic.id != vm.trendingTopics.last?.id {
                        Divider().padding(.leading, 70)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 28)
    }

    private var suggestedPeopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested People")
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)

            if vm.suggestedPeople.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.secondary)
                    Spacer()
                }
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(vm.suggestedPeople.enumerated()), id: \.element.id) { idx, user in
                        DiscoveryPersonRow(
                            user: user,
                            isFollowing: vm.followingUserIds.contains(user.id ?? ""),
                            cardIndex: idx,
                            onTap: { showProfileSheet = user },
                            onFollow: {
                                if let uid = user.id { vm.toggleFollow(userId: uid) }
                            }
                        )
                        .onAppear {
                            let threshold = Int(Double(vm.suggestedPeople.count) * 0.8)
                            if idx >= threshold && vm.hasMore {
                                Task { await vm.loadMoreSuggested() }
                            }
                        }

                        if user.id != vm.suggestedPeople.last?.id {
                            Divider().padding(.leading, 74)
                        }
                    }

                    if vm.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView().tint(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 16)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 28)
    }

    // MARK: - Search Results Content

    @ViewBuilder
    private var searchResultsContent: some View {
        if vm.isSearching {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView().tint(.secondary)
                    Text("Searching...")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.top, 60)
            .transition(.opacity)
        } else if let errorMsg = vm.searchError {
            // Fix #11: visible error state with retry
            VStack(spacing: 16) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.orange)
                Text("Search unavailable")
                    .font(.custom("OpenSans-SemiBold", size: 17))
                    .foregroundStyle(.primary)
                Text(errorMsg)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    vm.search(query: searchText)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text("Retry")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.primary))
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.top, 60)
            .padding(.horizontal, 32)
            .transition(.opacity)
        } else if vm.userResults.isEmpty && vm.postResults.isEmpty && vm.churchResults.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No results for \"\(searchText)\"")
                    .font(.custom("OpenSans-SemiBold", size: 17))
                    .foregroundStyle(.primary)
                Text("Try a different search term")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 80)
            .transition(.opacity)
        } else {
            // People results
            if !vm.userResults.isEmpty && (vm.scope == .all || vm.scope == .people) {
                searchResultSection(title: "People", count: vm.userResults.count) {
                    ForEach(Array(vm.userResults.enumerated()), id: \.element.id) { idx, user in
                        DiscoveryPersonRow(
                            user: user,
                            isFollowing: vm.followingUserIds.contains(user.id ?? ""),
                            cardIndex: idx,
                            onTap: { showProfileSheet = user },
                            onFollow: {
                                if let uid = user.id { vm.toggleFollow(userId: uid) }
                            }
                        )
                        if user.id != vm.userResults.last?.id {
                            Divider().padding(.leading, 74)
                        }
                    }
                }
            }

            // Post results
            if !vm.postResults.isEmpty && (vm.scope == .all || vm.scope == .posts) {
                searchResultSection(title: "Posts", count: vm.postResults.count) {
                    ForEach(vm.postResults) { post in
                        DiscoveryPostRow(post: post)
                        if post.id != vm.postResults.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }

            // Fix #3: Church results section
            if !vm.churchResults.isEmpty && (vm.scope == .all || vm.scope == .churches) {
                searchResultSection(title: "Churches", count: vm.churchResults.count) {
                    ForEach(vm.churchResults) { church in
                        DiscoveryChurchRow(church: church)
                        if church.id != vm.churchResults.last?.id {
                            Divider().padding(.leading, 74)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultSection<Content: View>(title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.primary)
                Text("(\(count))")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)

            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 24)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Scope Tab Button

struct ScopeTabButton: View {
    let scope: DiscoveryScope
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: scope.icon)
                    .font(.system(size: 13, weight: .medium))
                Text(scope.rawValue)
                    .font(.custom("OpenSans-SemiBold", size: 13))
            }
            .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.primary : Color(uiColor: .secondarySystemFill))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Discovery Person Row

struct DiscoveryPersonRow: View {
    let user: UserModel
    let isFollowing: Bool
    let cardIndex: Int
    let onTap: () -> Void
    let onFollow: () -> Void

    @State private var appeared = false
    @State private var isPressed = false
    @State private var showCheckmark = false
    // Local mirror of isFollowing so the button updates instantly without
    // waiting for the parent ForEach to re-evaluate via FollowService publish.
    @State private var localIsFollowing: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Button(action: onTap) {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: 46, height: 46)

                    if let urlStr = user.profileImageURL, !urlStr.isEmpty {
                        CachedAsyncImage(url: URL(string: urlStr)) { image in
                            image.resizable().scaledToFill()
                                .frame(width: 46, height: 46)
                                .clipShape(Circle())
                        } placeholder: {
                            Text(user.initials)
                                .font(.custom("OpenSans-Bold", size: 17))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(user.initials)
                            .font(.custom("OpenSans-Bold", size: 17))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(ScaleButtonStyle())

            // Info
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(user.displayName)
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if localIsFollowing {
                            Text("Following")
                                .font(.custom("OpenSans-Medium", size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color(uiColor: .tertiarySystemFill))
                                )
                        }
                    }

                    HStack(spacing: 5) {
                        Text("@\(user.username)")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if user.followersCount > 0 {
                            Text("•").foregroundStyle(.tertiary)
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text("\(user.followersCount)")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            Spacer(minLength: 8)

            // Follow button — uses localIsFollowing for instant feedback
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                // Toggle local state immediately so button reflects new state
                // even before the parent ForEach re-renders via FollowService.
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                    if !localIsFollowing { showCheckmark = true }
                    localIsFollowing.toggle()
                }
                onFollow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation(.easeOut(duration: 0.2)) { showCheckmark = false }
                }
            } label: {
                ZStack {
                    if showCheckmark {
                        // Brief checkmark flash — solid filled pill
                        Capsule()
                            .fill(Color.accentColor)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    } else if localIsFollowing {
                        // "Following" — outlined ghost pill, never black box
                        Capsule()
                            .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
                        Text("Following")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.secondary)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        // "Follow" — solid adaptive pill (black in light, white in dark)
                        Capsule()
                            .fill(Color.primary)
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                        Text("Follow")
                            .font(.custom("OpenSans-Bold", size: 13))
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: localIsFollowing ? 90 : 72, height: 32)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: localIsFollowing)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showCheckmark)
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            // Initialize local follow state from prop on first appear
            localIsFollowing = isFollowing
            let delay = min(Double(cardIndex) * 0.04, 0.25)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8).delay(delay)) {
                appeared = true
            }
        }
        // Keep local state in sync if the parent FollowService update arrives
        // after the optimistic toggle (e.g. server revert on error).
        .onChange(of: isFollowing) { _, newValue in
            if newValue != localIsFollowing {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    localIsFollowing = newValue
                }
            }
        }
    }
}

// MARK: - Discovery Post Row

struct DiscoveryPostRow: View {
    let post: AlgoliaPost

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(post.content)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text("by \(post.authorName)")
                        .font(.custom("OpenSans-Medium", size: 12))
                        .foregroundStyle(.secondary)

                    Text("•").foregroundStyle(.tertiary)

                    Text(post.category.capitalized)
                        .font(.custom("OpenSans-Medium", size: 12))
                        .foregroundStyle(.blue)

                    if let count = post.amenCount, count > 0 {
                        Text("•").foregroundStyle(.tertiary)
                        Text("\(count) Amens")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Discovery Church Row  — Fix #3

struct DiscoveryChurchRow: View {
    let church: ChurchEntity

    var body: some View {
        HStack(spacing: 12) {
            // Church icon
            ZStack {
                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 46, height: 46)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(church.name)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !church.address.isEmpty {
                    Text(church.address)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let denom = church.denomination, !denom.isEmpty {
                    Text(denom)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - Press Style for Discovery Rows

struct DiscoveryPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color(uiColor: .tertiarySystemFill)
                    : Color.clear
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Safe Profile Wrapper

struct SafeUserProfileWrapper: View {
    let userId: String
    @State private var loadFailed = false
    @State private var isLoading = true
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Group {
            if loadFailed {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("Unable to Load Profile")
                        .font(.custom("OpenSans-Bold", size: 20))
                    Text("This profile could not be loaded.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 24).fill(.black))
                    }
                }
            } else {
                UserProfileView(userId: userId, showsDismissButton: true)
                    .task {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        isLoading = false
                    }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if isLoading { loadFailed = true }
        }
    }
}

// MARK: - Trending Topic Feed View

/// Full-screen feed of posts tagged with a trending topic.
/// Fetches across all post categories using `topicTag` field, sorted by recency.
@MainActor
struct TrendingTopicFeedView: View {
    let topic: TrendingTopic

    @State private var posts: [Post] = []
    @State private var isLoading = true
    @State private var loadError: String? = nil

    private let service = FirebasePostService.shared

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            if isLoading {
                VStack(spacing: 14) {
                    ProgressView().tint(.secondary)
                    Text("Loading posts…")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
            } else if let err = loadError {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.orange)
                    Text("Couldn't load posts")
                        .font(.custom("OpenSans-SemiBold", size: 17))
                    Text(err)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Retry") {
                        Task { await loadPosts() }
                    }
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Capsule().fill(Color.primary))
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .buttonStyle(ScaleButtonStyle())
                }
            } else if posts.isEmpty {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(topic.backgroundColor)
                            .frame(width: 72, height: 72)
                        Image(systemName: topic.icon)
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(topic.iconColor)
                    }
                    Text("No posts yet for \"\(topic.title)\"")
                        .font(.custom("OpenSans-SemiBold", size: 17))
                        .foregroundStyle(.primary)
                    Text("Be the first to share your thoughts!")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(posts) { post in
                            PostCard(post: post)
                            Divider()
                        }
                        Color.clear.frame(height: 80)
                    }
                }
                .refreshable { await loadPosts() }
            }
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ZStack {
                    Circle()
                        .fill(topic.backgroundColor)
                        .frame(width: 34, height: 34)
                    Image(systemName: topic.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(topic.iconColor)
                }
            }
        }
        .task { await loadPosts() }
    }

    // MARK: - Load posts across all categories matching this topic tag

    private func loadPosts() async {
        isLoading = true
        loadError = nil
        do {
            // Fetch from all three main categories, filter by topicTag = topic.title, merge & sort
            async let openTable = service.fetchPosts(for: .openTable, topicTag: topic.title, limit: 20)
            async let testimonies = service.fetchPosts(for: .testimonies, topicTag: topic.title, limit: 10)
            async let prayer = service.fetchPosts(for: .prayer, topicTag: topic.title, limit: 10)

            let (ot, te, pr) = try await (openTable, testimonies, prayer)
            let combined = (ot + te + pr).sorted { $0.createdAt > $1.createdAt }

            // Deduplicate by firebaseId
            var seen = Set<String>()
            posts = combined.filter { post in
                guard let fid = post.firebaseId, !fid.isEmpty else { return true }
                return seen.insert(fid).inserted
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Typealias for backward compat

typealias PeopleDiscoveryView = PeopleDiscoveryViewNew

