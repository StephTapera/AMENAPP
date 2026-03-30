// DiscoverSearchComponents.swift
// AMEN App — Universal Search UI Components
//
// Provides:
//   • UniversalSearchResultsView   — sectioned list with glassmorphic headers,
//                                    skeleton shimmer while loading, empty state
//   • TrendingTopicsPillsView      — horizontal pill chips from topics collection
//   • SearchRecentListView         — focused-empty state list with clock icon + X
//   • UniversalSearchViewModel     — 8-collection parallel Firestore search + ranking
//
// Dependencies (all pre-existing, not re-declared here):
//   DiscoveryService, SearchRankingService, HapticManager, CachedAsyncImage,
//   DiscoveryPerson, DiscoveryPost, DiscoveryChurch, DiscoveryTopic,
//   UserProfileView, ChurchProfileView, DiscoveryTopicPageView

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - UniversalSearchViewModel

/// Runs the 8-collection parallel Firestore query and applies SearchRankingService.
/// Separate from DiscoveryService so it can be owned at the view level and
/// cancelled cleanly when the view disappears.
@MainActor
final class UniversalSearchViewModel: ObservableObject {

    // MARK: Published

    @Published private(set) var results = UniversalSearchResults(
        people: [], posts: [], churches: [], topics: [],
        prayers: [], testimonies: [], books: [], events: []
    )
    @Published private(set) var isLoading = false
    @Published private(set) var trendingTopics: [DiscoveryTopic] = []
    @Published private(set) var isTrendingLoading = false
    // MARK: - Smart Search additions
    @Published var searchScope: SearchScope = .forYou
    @Published var bereanAnswer = ""
    @Published var bereanAnswerLoading = false
    private var bereanTask: Task<Void, Never>?
    private let questionPrefixes = ["what", "who", "how", "why", "tell me", "explain", "is ", "are ", "does ", "can "]

    // MARK: Private

    private let db = Firestore.firestore()
    private var searchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let recentKey = "amen_recent_searches"
    private let maxRecent = 8

    // MARK: Recent searches (UserDefaults, max 8)

    var recentSearches: [String] {
        UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    func addRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = recentSearches.filter { $0 != trimmed }
        list.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(list.prefix(maxRecent)), forKey: recentKey)
    }

    func removeRecentSearch(_ query: String) {
        var list = recentSearches
        list.removeAll { $0 == query }
        UserDefaults.standard.set(list, forKey: recentKey)
    }

    func clearAllRecentSearches() {
        UserDefaults.standard.removeObject(forKey: recentKey)
        objectWillChange.send()
    }

    // MARK: - Scope-filtered results

    var scopedPeople: [DiscoveryPerson] {
        switch searchScope {
        case .forYou, .people: return results.people
        default: return []
        }
    }

    var scopedPosts: [DiscoveryPost] {
        switch searchScope {
        case .forYou, .posts: return results.posts.filter { $0.imageURL == nil }
        case .photos: return results.posts.filter { $0.imageURL != nil }
        default: return []
        }
    }

    var scopedPhotoPosts: [DiscoveryPost] {
        switch searchScope {
        case .forYou, .photos: return results.posts.filter { $0.imageURL != nil }
        default: return []
        }
    }

    var scopedTopics: [DiscoveryTopic] {
        switch searchScope {
        case .forYou, .tags: return results.topics
        default: return []
        }
    }

    // MARK: - Berean AI for search

    func shouldQueryBerean(for text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        return lower.contains("?") ||
               questionPrefixes.contains(where: { lower.hasPrefix($0) }) ||
               lower.count > 30
    }

    func triggerBereanSearch(for text: String) {
        guard shouldQueryBerean(for: text) else {
            bereanAnswer = ""; bereanAnswerLoading = false; return
        }
        bereanTask?.cancel()
        bereanAnswer = ""
        bereanAnswerLoading = true
        bereanTask = Task {
            let prompt = """
            The user searched for "\(text)" in AMEN, a faith-centered Christian community app. \
            Give a concise 2–3 sentence answer that is helpful, Scripture-grounded where relevant, \
            and warm. Be direct.
            """
            var response = ""
            do {
                let stream = OpenAIService.shared.sendMessage(prompt, maxTokens: 200, temperature: 0.6)
                for try await chunk in stream {
                    guard !Task.isCancelled else { break }
                    response += chunk
                    bereanAnswer = response
                }
            } catch {}
            if !Task.isCancelled { bereanAnswerLoading = false }
        }
    }

    // MARK: Trending Topics

    func loadTrendingTopics() async {
        guard trendingTopics.isEmpty else { return }
        isTrendingLoading = true
        defer { isTrendingLoading = false }
        do {
            let snap = try await db
                .collection("topics")
                .order(by: "postCount", descending: true)
                .limit(to: 10)
                .getDocuments()
            let fetched: [DiscoveryTopic] = snap.documents.compactMap { doc in
                let d = doc.data()
                guard let name = d["name"] as? String else { return nil }
                return DiscoveryTopic(
                    id: doc.documentID,
                    title: name,
                    canonicalSlug: doc.documentID,
                    description: d["description"] as? String ?? "",
                    icon: d["icon"] as? String ?? "tag",
                    iconColor: .purple,
                    backgroundColor: Color.purple.opacity(0.08),
                    postCount: d["postCount"] as? Int ?? 0,
                    trendScore: d["trendScore"] as? Double ?? 0,
                    isTrending: (d["trendScore"] as? Double ?? 0) >= 70,
                    isFollowedByUser: false,
                    relatedScripture: nil,
                    safetyState: .approved
                )
            }
            // Fall back to catalog if collection is empty or doesn't exist yet
            if fetched.isEmpty {
                trendingTopics = Array(DiscoveryTopic.catalog.prefix(10))
            } else {
                trendingTopics = fetched
            }
        } catch {
            // Firestore collection may not exist yet — use static catalog
            trendingTopics = Array(DiscoveryTopic.catalog.prefix(10))
        }
    }

    // MARK: Debounced search (350ms)

    func scheduleSearch(query: String) {
        debounceTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchTask?.cancel()
            results = UniversalSearchResults(
                people: [], posts: [], churches: [], topics: [],
                prayers: [], testimonies: [], books: [], events: []
            )
            isLoading = false
            return
        }
        // Also clear stale Berean answer when query changes
        bereanAnswer = ""
        bereanAnswerLoading = false
        bereanTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await executeSearch(query: query)
            triggerBereanSearch(for: query)
        }
    }

    func executeSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        isLoading = true
        addRecentSearch(trimmed)

        searchTask = Task {
            // 8-collection parallel Firestore search
            enum Partial {
                case people([DiscoveryPerson])
                case posts([DiscoveryPost])
                case churches([DiscoveryChurch])
                case topics([DiscoveryTopic])
                case prayers([SearchSimpleItem])
                case testimonies([SearchSimpleItem])
                case books([SearchSimpleItem])
                case events([SearchSimpleItem])
            }

            var people: [DiscoveryPerson] = []
            var posts: [DiscoveryPost] = []
            var churches: [DiscoveryChurch] = []
            var topics: [DiscoveryTopic] = []
            var prayers: [SearchSimpleItem] = []
            var testimonies: [SearchSimpleItem] = []
            var books: [SearchSimpleItem] = []
            var events: [SearchSimpleItem] = []

            await withTaskGroup(of: Partial.self) { group in
                group.addTask { .people(await self.fetchPeople(query: trimmed)) }
                group.addTask { .posts(await self.fetchPosts(query: trimmed)) }
                group.addTask { .churches(await self.fetchChurches(query: trimmed)) }
                group.addTask { .topics(await self.fetchTopics(query: trimmed)) }
                group.addTask { .prayers(await self.fetchSimple(collection: "prayers", titleField: "title", subtitleField: "content", icon: "hands.sparkles.fill", query: trimmed)) }
                group.addTask { .testimonies(await self.fetchSimple(collection: "testimonies", titleField: "title", subtitleField: "content", icon: "star.fill", query: trimmed)) }
                group.addTask { .books(await self.fetchBooks(query: trimmed)) }
                group.addTask { .events(await self.fetchEvents(query: trimmed)) }
                for await partial in group {
                    switch partial {
                    case .people(let r):      people      = r
                    case .posts(let r):       posts       = r
                    case .churches(let r):    churches    = r
                    case .topics(let r):      topics      = r
                    case .prayers(let r):     prayers     = r
                    case .testimonies(let r): testimonies = r
                    case .books(let r):       books       = r
                    case .events(let r):      events      = r
                    }
                }
            }

            guard !Task.isCancelled else { return }

            // Apply ranking
            results = UniversalSearchResults(
                people:      SearchRankingService.rankPeople(people, query: trimmed),
                posts:       SearchRankingService.rankPosts(posts, query: trimmed),
                churches:    SearchRankingService.rankChurches(churches, query: trimmed),
                topics:      SearchRankingService.rankTopics(topics, query: trimmed),
                prayers:     SearchRankingService.rankSimpleItems(prayers, query: trimmed),
                testimonies: SearchRankingService.rankSimpleItems(testimonies, query: trimmed),
                books:       SearchRankingService.rankSimpleItems(books, query: trimmed),
                events:      SearchRankingService.rankSimpleItems(events, query: trimmed)
            )
            isLoading = false
        }
    }

    // MARK: - Firestore fetchers

    private func fetchPeople(query: String) async -> [DiscoveryPerson] {
        let lowered = query.lowercased()
        let followingSet = FollowService.shared.following
        let currentUID = Auth.auth().currentUser?.uid ?? ""
        do {
            // Prefix match on displayNameLower; fall back to usernameLower if empty
            let snap = try await db.collection("users")
                .whereField("displayNameLower", isGreaterThanOrEqualTo: lowered)
                .whereField("displayNameLower", isLessThanOrEqualTo: lowered + "\u{f8ff}")
                .limit(to: 5)
                .getDocuments()
            return snap.documents.compactMap { doc -> DiscoveryPerson? in
                let d = doc.data()
                guard doc.documentID != currentUID,
                      let displayName = d["displayName"] as? String,
                      let username = d["username"] as? String else { return nil }
                return DiscoveryPerson(
                    id: doc.documentID,
                    displayName: displayName,
                    username: username,
                    bio: d["bio"] as? String ?? "",
                    avatarURL: d["profileImageURL"] as? String,
                    followerCount: d["followersCount"] as? Int ?? 0,
                    isVerified: d["isVerified"] as? Bool ?? false,
                    isFollowing: followingSet.contains(doc.documentID),
                    mutualFollowersCount: 0,
                    followReason: nil,
                    topicAffinities: [],
                    qualityScore: 50
                )
            }
        } catch {
            return []
        }
    }

    private func fetchPosts(query: String) async -> [DiscoveryPost] {
        // Tokenize query to support contains-any search on an array field
        let tokens = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        do {
            let snap = try await db.collection("posts")
                .whereField("contentTokens", arrayContainsAny: Array(tokens.prefix(10)))
                .limit(to: 10)
                .getDocuments()
            return snap.documents.compactMap { doc -> DiscoveryPost? in
                let d = doc.data()
                guard let content = d["content"] as? String else { return nil }
                return DiscoveryPost(
                    id: doc.documentID,
                    authorId: d["authorId"] as? String ?? "",
                    authorName: d["authorName"] as? String ?? "",
                    authorHandle: d["authorHandle"] as? String ?? "",
                    authorAvatarURL: d["authorAvatarURL"] as? String,
                    excerpt: String(content.prefix(180)),
                    fullContent: content,
                    category: d["category"] as? String ?? "opentable",
                    topicTag: d["topicTag"] as? String,
                    createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    amenCount: d["amenCount"] as? Int ?? d["likesCount"] as? Int ?? 0,
                    commentCount: d["commentCount"] as? Int ?? 0,
                    imageURL: (d["mediaURLs"] as? [String])?.first,
                    highlightedExcerpt: nil
                )
            }
        } catch {
            return []
        }
    }

    private func fetchChurches(query: String) async -> [DiscoveryChurch] {
        let lowered = query.lowercased()
        do {
            let snap = try await db.collection("churches")
                .whereField("nameLower", isGreaterThanOrEqualTo: lowered)
                .whereField("nameLower", isLessThanOrEqualTo: lowered + "\u{f8ff}")
                .limit(to: 5)
                .getDocuments()
            return snap.documents.compactMap { doc -> DiscoveryChurch? in
                let d = doc.data()
                guard let name = d["name"] as? String else { return nil }
                return DiscoveryChurch(
                    id: doc.documentID,
                    name: name,
                    denomination: d["denomination"] as? String,
                    city: d["city"] as? String ?? "",
                    state: d["state"] as? String ?? "",
                    nextServiceTime: d["nextServiceTime"] as? String,
                    imageURL: d["imageURL"] as? String,
                    tags: d["tags"] as? [String] ?? [],
                    distanceMiles: nil,
                    isVerified: d["isVerified"] as? Bool ?? false
                )
            }
        } catch {
            return []
        }
    }

    private func fetchTopics(query: String) async -> [DiscoveryTopic] {
        let lowered = query.lowercased()
        // First try local catalog for instant response
        let catalog = DiscoveryTopic.catalog.filter {
            $0.title.lowercased().hasPrefix(lowered) ||
            $0.title.localizedCaseInsensitiveContains(query)
        }
        if !catalog.isEmpty { return Array(catalog.prefix(5)) }

        // Then try Firestore topics collection
        do {
            let snap = try await db.collection("topics")
                .whereField("nameLower", isGreaterThanOrEqualTo: lowered)
                .whereField("nameLower", isLessThanOrEqualTo: lowered + "\u{f8ff}")
                .limit(to: 5)
                .getDocuments()
            return snap.documents.compactMap { doc -> DiscoveryTopic? in
                let d = doc.data()
                guard let name = d["name"] as? String else { return nil }
                return DiscoveryTopic(
                    id: doc.documentID,
                    title: name,
                    canonicalSlug: doc.documentID,
                    description: d["description"] as? String ?? "",
                    icon: d["icon"] as? String ?? "tag",
                    iconColor: .purple,
                    backgroundColor: Color.purple.opacity(0.08),
                    postCount: d["postCount"] as? Int ?? 0,
                    trendScore: d["trendScore"] as? Double ?? 0,
                    isTrending: (d["trendScore"] as? Double ?? 0) >= 70,
                    isFollowedByUser: false,
                    relatedScripture: nil,
                    safetyState: .approved
                )
            }
        } catch {
            return []
        }
    }

    private func fetchSimple(
        collection: String,
        titleField: String,
        subtitleField: String,
        icon: String,
        query: String
    ) async -> [SearchSimpleItem] {
        let lowered = query.lowercased()
        let titleLower = titleField + "Lower"
        do {
            let snap = try await db.collection(collection)
                .whereField(titleLower, isGreaterThanOrEqualTo: lowered)
                .whereField(titleLower, isLessThanOrEqualTo: lowered + "\u{f8ff}")
                .limit(to: 5)
                .getDocuments()
            return snap.documents.compactMap { doc -> SearchSimpleItem? in
                let d = doc.data()
                guard let title = d[titleField] as? String else { return nil }
                let subtitle: String?
                if let raw = d[subtitleField] as? String {
                    subtitle = String(raw.prefix(80))
                } else {
                    subtitle = nil
                }
                return SearchSimpleItem(
                    id: doc.documentID,
                    title: title,
                    subtitle: subtitle,
                    iconName: icon,
                    relevanceScore: 0
                )
            }
        } catch {
            return []
        }
    }

    private func fetchBooks(query: String) async -> [SearchSimpleItem] {
        let lowered = query.lowercased()
        do {
            let snap = try await db.collection("books")
                .whereField("titleLower", isGreaterThanOrEqualTo: lowered)
                .whereField("titleLower", isLessThanOrEqualTo: lowered + "\u{f8ff}")
                .limit(to: 5)
                .getDocuments()
            return snap.documents.compactMap { doc -> SearchSimpleItem? in
                let d = doc.data()
                guard let title = d["title"] as? String else { return nil }
                return SearchSimpleItem(
                    id: doc.documentID,
                    title: title,
                    subtitle: d["author"] as? String,
                    iconName: "book.fill",
                    relevanceScore: 0
                )
            }
        } catch {
            return []
        }
    }

    private func fetchEvents(query: String) async -> [SearchSimpleItem] {
        let lowered = query.lowercased()
        let now = Timestamp(date: Date())
        do {
            let snap = try await db.collection("events")
                .whereField("titleLower", isGreaterThanOrEqualTo: lowered)
                .whereField("titleLower", isLessThanOrEqualTo: lowered + "\u{f8ff}")
                .whereField("date", isGreaterThanOrEqualTo: now)
                .limit(to: 5)
                .getDocuments()
            return snap.documents.compactMap { doc -> SearchSimpleItem? in
                let d = doc.data()
                guard let title = d["title"] as? String else { return nil }
                let location = d["location"] as? String
                let dateStr: String? = {
                    if let ts = d["date"] as? Timestamp {
                        let fmt = DateFormatter()
                        fmt.dateStyle = .medium
                        fmt.timeStyle = .short
                        return fmt.string(from: ts.dateValue())
                    }
                    return nil
                }()
                let subtitle = [location, dateStr].compactMap { $0 }.joined(separator: " · ")
                return SearchSimpleItem(
                    id: doc.documentID,
                    title: title,
                    subtitle: subtitle.isEmpty ? nil : subtitle,
                    iconName: "calendar",
                    relevanceScore: 0
                )
            }
        } catch {
            return []
        }
    }
}

// MARK: - UniversalSearchResultsView

/// Sectioned results list rendered once a query is running or has completed.
/// Shows shimmer skeletons while `isLoading == true`, sectioned rows when done,
/// and a cross+message empty state when all sections are empty.
struct UniversalSearchResultsView: View {

    let query: String
    @ObservedObject var viewModel: UniversalSearchViewModel
    @Binding var searchText: String

    // Navigation targets
    @State private var selectedTopic: DiscoveryTopic? = nil
    @State private var navigateToTopic = false

    // Navigation state for full screen Berean
    @State private var showBereanAI = false
    @State private var bereanSeedQuery = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // PART 4: Berean AI answer card — shown for question-style queries
                if viewModel.bereanAnswerLoading || !viewModel.bereanAnswer.isEmpty {
                    BereanSearchAnswerCard(
                        query: query,
                        answer: viewModel.bereanAnswer,
                        isLoading: viewModel.bereanAnswerLoading,
                        onAskMore: {
                            bereanSeedQuery = query
                            showBereanAI = true
                        }
                    )
                    .padding(.bottom, 8)
                    .padding(.top, 8)
                }

                // PART 3: Top profile card — shown when people results exist
                if let topPerson = viewModel.scopedPeople.first,
                   viewModel.searchScope == .forYou || viewModel.searchScope == .people {
                    SearchTopProfileCard(
                        person: topPerson,
                        previewPosts: viewModel.results.posts,
                        onFollow: {
                            Task {
                                if topPerson.isFollowing {
                                    await DiscoveryService.shared.unfollowUser(userId: topPerson.id)
                                } else {
                                    await DiscoveryService.shared.followUser(userId: topPerson.id)
                                }
                            }
                        },
                        onTapProfile: { /* navigation handled by USSPersonRow below */ }
                    )
                    .padding(.bottom, 8)
                }

                if viewModel.isLoading {
                    shimmerSections
                } else if viewModel.results.isEmpty {
                    emptyState
                } else {
                    resultSections
                }
                Spacer().frame(height: 100)
            }
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .fullScreenCover(isPresented: $showBereanAI) {
            BereanAIAssistantView(seedMessage: bereanSeedQuery)
        }
        .navigationDestination(isPresented: $navigateToTopic) {
            if let topic = selectedTopic {
                DiscoveryTopicPageView(topic: topic)
            }
        }
    }

    // MARK: - Shimmer Skeleton

    private var shimmerSections: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(["People", "Posts", "Churches"], id: \.self) { label in
                glassHeader(label)
                ForEach(0..<3, id: \.self) { _ in
                    SearchSkeletonRow()
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 60)
            Image(systemName: "xmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text("Nothing found for '\(query)'")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Result Sections

    @ViewBuilder
    private var resultSections: some View {
        let r = viewModel.results

        // People
        if !r.people.isEmpty {
            glassHeader("People")
            ForEach(r.people) { person in
                USSPersonRow(person: person) {
                    Task {
                        if person.isFollowing {
                            await DiscoveryService.shared.unfollowUser(userId: person.id)
                        } else {
                            await DiscoveryService.shared.followUser(userId: person.id)
                        }
                    }
                }
                rowDivider(indent: 60)
            }
        }

        // Posts
        if !r.posts.isEmpty {
            glassHeader("Posts")
            ForEach(r.posts) { post in
                USSPostRow(post: post)
                rowDivider(indent: 16)
            }
        }

        // Churches
        if !r.churches.isEmpty {
            glassHeader("Churches")
            ForEach(r.churches) { church in
                NavigationLink(destination: ChurchProfileView(churchId: church.id)) {
                    USSChurchRow(church: church)
                }
                .buttonStyle(.plain)
                rowDivider(indent: 16)
            }
        }

        // Topics
        if !r.topics.isEmpty {
            glassHeader("Topics")
            ForEach(r.topics) { topic in
                Button {
                    selectedTopic = topic
                    navigateToTopic = true
                } label: {
                    USSTopicRow(topic: topic)
                }
                .buttonStyle(.plain)
                rowDivider(indent: 16)
            }
        }

        // Prayers
        if !r.prayers.isEmpty {
            glassHeader("Prayers")
            ForEach(r.prayers) { item in
                USSSimpleRow(item: item)
                rowDivider(indent: 16)
            }
        }

        // Testimonies
        if !r.testimonies.isEmpty {
            glassHeader("Testimonies")
            ForEach(r.testimonies) { item in
                USSSimpleRow(item: item)
                rowDivider(indent: 16)
            }
        }

        // Books
        if !r.books.isEmpty {
            glassHeader("Books")
            ForEach(r.books) { item in
                USSSimpleRow(item: item)
                rowDivider(indent: 16)
            }
        }

        // Events
        if !r.events.isEmpty {
            glassHeader("Events")
            ForEach(r.events) { item in
                USSSimpleRow(item: item)
                rowDivider(indent: 16)
            }
        }
    }

    // MARK: - Glassmorphic section header

    private func glassHeader(_ title: String) -> some View {
        Text(title)
            .font(.custom("OpenSans-SemiBold", size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial.opacity(0.5))
    }

    private func rowDivider(indent: CGFloat) -> some View {
        Divider().padding(.leading, indent)
    }
}

// MARK: - Row Components

struct USSPersonRow: View {
    let person: DiscoveryPerson
    let onFollowTap: () -> Void

    @State private var inFlight = false
    @State private var showProfile = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Button { showProfile = true } label: {
                HStack(spacing: 12) {
                    avatarView(url: person.avatarURL, size: 36, initial: person.displayName)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(person.displayName)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.primary)
                            if person.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.blue)
                            }
                        }
                        Text("@\(person.username)")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Color.clear.frame(width: person.id == Auth.auth().currentUser?.uid ? 0 : 88)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .navigationDestination(isPresented: $showProfile) {
                UserProfileView(userId: person.id)
            }

            if Auth.auth().currentUser?.uid != person.id {
                Button {
                    guard !inFlight else { return }
                    inFlight = true
                    onFollowTap()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { inFlight = false }
                } label: {
                    Text(person.isFollowing ? "Following" : "Follow")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(person.isFollowing ? Color.secondary : Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                person.isFollowing
                                    ? AnyShapeStyle(Color.primary.opacity(0.08))
                                    : AnyShapeStyle(LinearGradient(
                                        colors: [Color.purple, Color.purple.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
                .padding(.trailing, 16)
            }
        }
    }
}

struct USSPostRow: View {
    let post: DiscoveryPost

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatarView(url: post.authorAvatarURL, size: 28, initial: post.authorName)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(post.authorName)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.primary)
                    if let tag = post.topicTag {
                        Text(tag)
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(categoryColor(post.category))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(categoryColor(post.category).opacity(0.12)))
                    }
                }
                Text(post.excerpt)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Label("\(post.amenCount)", systemImage: "hands.sparkles")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func categoryColor(_ c: String) -> Color {
        switch c.lowercased() {
        case "prayer": return .purple
        case "testimonies": return .orange
        case "opentable": return .blue
        default: return .secondary
        }
    }
}

struct USSChurchRow: View {
    let church: DiscoveryChurch

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let url = church.imageURL, !url.isEmpty, let u = URL(string: url) {
                    CachedAsyncImage(url: u) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.1))
                            .overlay(Image(systemName: "building.columns.fill").foregroundStyle(.blue))
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: "building.columns.fill").foregroundStyle(.blue))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(church.name)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.primary)
                    if church.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                    }
                }
                Text("\(church.city), \(church.state)")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct USSTopicRow: View {
    let topic: DiscoveryTopic

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.25), Color.purple.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Text("#")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.purple)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                if topic.postCount > 0 {
                    Text("\(topic.postCount) posts")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

struct USSSimpleRow: View {
    let item: SearchSimpleItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconName)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let sub = item.subtitle {
                    Text(sub)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - Skeleton shimmer row

struct SearchSkeletonRow: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(shimmerGradient)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(width: 120, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(width: 80, height: 10)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
            ) {
                phase = 1
            }
        }
    }

    private var shimmerGradient: some ShapeStyle {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.05), location: 0),
                .init(color: Color.white.opacity(phase == 0 ? 0.05 : 0.12), location: 0.5),
                .init(color: Color.white.opacity(0.05), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - TrendingTopicsPillsView

/// Horizontal scrolling pill chips driven by `topics` Firestore collection.
/// Section header: "Trending in AMEN".
/// Tap → pre-fills search bar and fires search.
struct TrendingTopicsPillsView: View {

    @ObservedObject var viewModel: UniversalSearchViewModel
    let onTopicTap: (DiscoveryTopic) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trending in AMEN")
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

            if viewModel.isTrendingLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { _ in
                            trendingSkeletonPill
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.trendingTopics) { topic in
                            Button {
                                HapticManager.impact(style: .light)
                                onTopicTap(topic)
                            } label: {
                                Text(topic.title)
                                    .font(.custom("OpenSans-Medium", size: 13))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(Color.clear)
                                            .overlay(
                                                Capsule()
                                                    .stroke(
                                                        LinearGradient(
                                                            colors: [Color.purple, Color.purple.opacity(0.5)],
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        ),
                                                        lineWidth: 1
                                                    )
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
        .task {
            await viewModel.loadTrendingTopics()
        }
    }

    private var trendingSkeletonPill: some View {
        Capsule()
            .fill(Color.white.opacity(0.06))
            .frame(width: 80, height: 34)
    }
}

// MARK: - SearchRecentListView

/// Shown below search bar when focused and query is empty.
/// Displays up to 8 recent searches from UserDefaults.
struct SearchRecentListView: View {

    @ObservedObject var viewModel: UniversalSearchViewModel
    let onSelect: (String) -> Void

    @State private var recentSnapshot: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if recentSnapshot.isEmpty {
                Text("No recent searches")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
            } else {
                ForEach(recentSnapshot, id: \.self) { term in
                    HStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        Button {
                            onSelect(term)
                        } label: {
                            Text(term)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Button {
                            viewModel.removeRecentSearch(term)
                            recentSnapshot = viewModel.recentSearches
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())

                    Divider().padding(.leading, 48)
                }

                Button {
                    viewModel.clearAllRecentSearches()
                    recentSnapshot = []
                } label: {
                    Text("Clear all")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { recentSnapshot = viewModel.recentSearches }
    }
}

// MARK: - Shared avatar helper (file-private, avoids conflict with other files)

/// Creates a 36pt or configurable-size circular avatar with initials fallback.
private func avatarView(url: String?, size: CGFloat, initial: String) -> some View {
    ZStack {
        Circle()
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(width: size, height: size)
        if let urlStr = url, !urlStr.isEmpty, let u = URL(string: urlStr) {
            CachedAsyncImage(url: u) { img in
                img.resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } placeholder: {
                Text(String(initial.prefix(1)).uppercased())
                    .font(.custom("OpenSans-Bold", size: size * 0.44))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(String(initial.prefix(1)).uppercased())
                .font(.custom("OpenSans-Bold", size: size * 0.44))
                .foregroundStyle(.secondary)
        }
    }
    .frame(width: size, height: size)
}
