// DiscoveryService.swift
// AMEN App — Discovery & Search System
//
// Central orchestration service for:
//   - Universal search across all entity types
//   - Typeahead / live suggestions
//   - Trending topics (safety-gated, AI-summarized)
//   - Follow suggestions (graph + quality + safety signals)
//   - Topic personalization
//   - Recent search persistence
//   - Query intent classification
//   - Safety ranking and suppression
//
// Architecture:
//   Algolia → primary search (instant, typo-tolerant)
//   Firestore → fallback + trending + topics + churches + notes
//   HomeFeedAlgorithm signals → reuse for ranking
//   ContentSafetyShieldService → safety scoring (existing, not duplicated)

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class DiscoveryService: ObservableObject {

    static let shared = DiscoveryService()

    // MARK: - Published State

    @Published private(set) var searchState: DiscoverySearchState = .landing
    @Published private(set) var typeaheadSuggestions: [TypeaheadSuggestion] = []
    @Published private(set) var trendingTopics: [DiscoveryTopic] = DiscoveryTopic.catalog  // static-first
    @Published private(set) var popularTopics: [DiscoveryTopic] = []
    @Published private(set) var topicChips: [DiscoveryTopic] = []                          // horizontal chips
    @Published private(set) var trends: [DiscoveryTrend] = []
    @Published private(set) var followSuggestions: [FollowSuggestion] = []
    @Published private(set) var recentSearches: [RecentSearchItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isSuggestionsLoading = false
    @Published private(set) var isTrendsLoading = false
    @Published private(set) var isFollowSuggestionsLoading = false

    // MARK: - Search Results (per tab)

    @Published private(set) var topResults: [DiscoveryResult] = []
    @Published private(set) var peopleResults: [DiscoveryPerson] = []
    @Published private(set) var postResults: [DiscoveryPost] = []
    @Published private(set) var topicResults: [DiscoveryTopic] = []
    @Published private(set) var churchResults: [DiscoveryChurch] = []
    @Published private(set) var noteResults: [DiscoveryNote] = []

    @Published private(set) var hasMorePeople = false
    @Published private(set) var hasMorePosts = false

    // MARK: - Dependencies

    private let db = Firestore.firestore()
    private let algolia = AlgoliaSearchService.shared

    // MARK: - Internal State

    private var searchTask: Task<Void, Never>?
    private var suggestionsTask: Task<Void, Never>?
    private var currentQuery = ""

    private let recentSearchesKey = "amen.discovery.recentSearches"
    private let maxRecentSearches = 12

    // MARK: - Init

    private init() {
        loadRecentSearches()
        Task { await loadLandingPageData() }
    }

    // MARK: - Public: Search State Machine

    func setQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            searchState = .landing
            typeaheadSuggestions = []
            clearResults()
            return
        }

        currentQuery = trimmed
        searchState = .typing(trimmed)

        // Cancel previous suggestions task
        suggestionsTask?.cancel()
        suggestionsTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
            guard !Task.isCancelled else { return }
            await loadTypeaheadSuggestions(query: trimmed)
        }
    }

    func submitSearch(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        suggestionsTask?.cancel()
        searchTask?.cancel()

        currentQuery = trimmed
        searchState = .results(trimmed)
        isSearching = true
        typeaheadSuggestions = []

        // Add to recent searches
        addRecentSearch(RecentSearchItem(
            id: UUID().uuidString,
            query: trimmed,
            type: .query,
            timestamp: Date()
        ))

        searchTask = Task {
            await performSearch(query: trimmed)
            isSearching = false
        }
    }

    func selectTopic(_ topic: DiscoveryTopic) {
        searchState = .topicPage(topic)
    }

    func goBack() {
        searchTask?.cancel()
        suggestionsTask?.cancel()
        searchState = .landing
        currentQuery = ""
        typeaheadSuggestions = []
        clearResults()
    }

    func clearSearch() {
        searchTask?.cancel()
        suggestionsTask?.cancel()
        searchState = .landing
        currentQuery = ""
        typeaheadSuggestions = []
        clearResults()
    }

    // MARK: - Public: Follow Actions

    func followUser(userId: String) async {
        // Delegate to existing FollowService
        do {
            try await FollowService.shared.followUser(userId: userId)
            // Optimistic update in follow suggestions
            if let idx = followSuggestions.firstIndex(where: { $0.id == userId }) {
                followSuggestions[idx].isFollowing = true
            }
            // Update people results too
            if let idx = peopleResults.firstIndex(where: { $0.id == userId }) {
                peopleResults[idx].isFollowing = true
            }
        } catch {
            print("[DiscoveryService] Follow failed: \(error)")
        }
    }

    func unfollowUser(userId: String) async {
        do {
            try await FollowService.shared.unfollowUser(userId: userId)
            if let idx = followSuggestions.firstIndex(where: { $0.id == userId }) {
                followSuggestions[idx].isFollowing = false
            }
            if let idx = peopleResults.firstIndex(where: { $0.id == userId }) {
                peopleResults[idx].isFollowing = false
            }
        } catch {
            print("[DiscoveryService] Unfollow failed: \(error)")
        }
    }

    // MARK: - Public: Recent Searches

    func addRecentSearch(_ item: RecentSearchItem) {
        var searches = recentSearches.filter { $0.query != item.query }
        searches.insert(item, at: 0)
        recentSearches = Array(searches.prefix(maxRecentSearches))
        saveRecentSearches()
    }

    func removeRecentSearch(id: String) {
        recentSearches.removeAll(where: { $0.id == id })
        saveRecentSearches()
    }

    func clearAllRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
    }

    // MARK: - Landing Page Data Load

    func loadLandingPageData() async {
        // withTaskGroup instead of async let to avoid swift_task_dealloc crash
        // when the parent .task modifier cancels on view disappear.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadTrendingTopics() }
            group.addTask { await self.loadFollowSuggestions() }
        }
        buildTopicChips()
    }

    private func buildTopicChips() {
        // Chips are a curated ordered slice of the catalog
        // Priority: user's interests first, then popular, then default order
        topicChips = Array(DiscoveryTopic.catalog.prefix(14))
        popularTopics = Array(DiscoveryTopic.catalog.prefix(8))
    }

    // MARK: - Trending Topics

    private func loadTrendingTopics() async {
        isTrendsLoading = true
        defer { isTrendsLoading = false }

        do {
            // Fetch from Firestore `trending` collection (populated by Cloud Functions)
            let snapshot = try await db
                .collection("trending")
                .whereField("safetyStatus", isEqualTo: "approved")
                .order(by: "trendScore", descending: true)
                .limit(to: 6)
                .getDocuments()

            let fetched: [DiscoveryTrend] = snapshot.documents.compactMap { doc in
                let d = doc.data()
                guard let title = d["title"] as? String,
                      let summary = d["summary"] as? String else { return nil }
                return DiscoveryTrend(
                    id: doc.documentID,
                    title: title,
                    summary: summary,
                    discussionCount: d["discussionCount"] as? Int ?? 0,
                    uniqueAuthors: d["uniqueAuthors"] as? Int ?? 0,
                    trendScore: d["trendScore"] as? Double ?? 0,
                    safetyStatus: DiscoveryTrend.TrendSafetyStatus(
                        rawValue: d["safetyStatus"] as? String ?? "approved"
                    ) ?? .approved,
                    thumbnailURL: d["thumbnailURL"] as? String,
                    createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    topTopics: d["topTopics"] as? [String] ?? []
                )
            }

            if !fetched.isEmpty {
                trends = fetched
            }

            // Enrich topic catalog with live post counts
            await enrichTopicPostCounts()

        } catch {
            // Non-fatal: static catalog already shown
            print("[DiscoveryService] Trending fetch failed: \(error)")
        }
    }

    private func enrichTopicPostCounts() async {
        // Fetch post counts for each topic tag in parallel batches
        var enriched = DiscoveryTopic.catalog
        do {
            let snapshot = try await db.collection("topicStats").getDocuments()
            for doc in snapshot.documents {
                let count = doc.data()["postCount"] as? Int ?? 0
                if let idx = enriched.firstIndex(where: { $0.id == doc.documentID }) {
                    enriched[idx] = DiscoveryTopic(
                        id: enriched[idx].id,
                        title: enriched[idx].title,
                        canonicalSlug: enriched[idx].canonicalSlug,
                        description: enriched[idx].description,
                        icon: enriched[idx].icon,
                        iconColor: enriched[idx].iconColor,
                        backgroundColor: enriched[idx].backgroundColor,
                        postCount: count,
                        trendScore: doc.data()["trendScore"] as? Double ?? 0,
                        isTrending: (doc.data()["trendScore"] as? Double ?? 0) >= 70,
                        isFollowedByUser: enriched[idx].isFollowedByUser,
                        relatedScripture: enriched[idx].relatedScripture,
                        safetyState: enriched[idx].safetyState
                    )
                }
            }
            trendingTopics = enriched
        } catch {
            // Keep static catalog
        }
    }

    // MARK: - Follow Suggestions

    private func loadFollowSuggestions() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isFollowSuggestionsLoading = true
        defer { isFollowSuggestionsLoading = false }

        do {
            // Fetch users with good quality scores who the current user isn't following
            let snapshot = try await db
                .collection("users")
                .whereField("showInDiscovery", isEqualTo: true)
                .whereField("qualityScore", isGreaterThanOrEqualTo: 60)
                .order(by: "qualityScore", descending: true)
                .limit(to: 30)
                .getDocuments()

            let followingSet = FollowService.shared.following

            let candidates: [FollowSuggestion] = snapshot.documents.compactMap { doc in
                let d = doc.data()
                let userId = doc.documentID
                guard userId != uid,
                      !followingSet.contains(userId),
                      let displayName = d["displayName"] as? String,
                      let username = d["username"] as? String else { return nil }

                let person = DiscoveryPerson(
                    id: userId,
                    displayName: displayName,
                    username: username,
                    bio: d["bio"] as? String ?? "",
                    avatarURL: d["profileImageURL"] as? String,
                    followerCount: d["followersCount"] as? Int ?? 0,
                    isVerified: d["isVerified"] as? Bool ?? false,
                    isFollowing: false,
                    mutualFollowersCount: 0,
                    followReason: generateFollowReason(from: d),
                    topicAffinities: d["topicAffinities"] as? [String] ?? [],
                    qualityScore: d["qualityScore"] as? Double ?? 50
                )

                return FollowSuggestion(
                    id: userId,
                    person: person,
                    reason: generateFollowReason(from: d) ?? "Active in AMEN community",
                    isFollowing: false
                )
            }

            // Rank by relevance: quality score + topic overlap
            followSuggestions = Array(rankFollowSuggestions(candidates).prefix(8))

        } catch {
            print("[DiscoveryService] Follow suggestions failed: \(error)")
        }
    }

    private func generateFollowReason(from data: [String: Any]) -> String? {
        let topics = data["topicAffinities"] as? [String] ?? []
        if let first = topics.first {
            let topicDisplay = DiscoveryTopic.catalog.first(where: { $0.id == first })?.title ?? first
            return "Posts about \(topicDisplay)"
        }
        if let role = data["ministryRole"] as? String, !role.isEmpty {
            return role
        }
        return nil
    }

    private func rankFollowSuggestions(_ candidates: [FollowSuggestion]) -> [FollowSuggestion] {
        // Simple relevance ranking for suggestions
        // Full personalization can be added later with user interests
        return candidates.sorted { a, b in
            let aScore = a.person.qualityScore + Double(a.person.followerCount) * 0.001
            let bScore = b.person.qualityScore + Double(b.person.followerCount) * 0.001
            return aScore > bScore
        }
    }

    // MARK: - Typeahead Suggestions

    private func loadTypeaheadSuggestions(query: String) async {
        isSuggestionsLoading = true
        defer { isSuggestionsLoading = false }

        var suggestions: [TypeaheadSuggestion] = []

        // Recent searches matching query
        let matchingRecents = recentSearches
            .filter { $0.query.localizedCaseInsensitiveContains(query) }
            .prefix(3)
            .map { item in
                TypeaheadSuggestion(
                    id: "recent-\(item.id)",
                    text: item.query,
                    type: .recentSearch,
                    subtitle: nil,
                    avatarURL: item.avatarURL
                )
            }
        suggestions.append(contentsOf: matchingRecents)

        // Topic matches from catalog
        let topicMatches = DiscoveryTopic.catalog
            .filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.canonicalSlug.contains(query.lowercased().replacingOccurrences(of: " ", with: "-"))
            }
            .prefix(3)
            .map { topic in
                TypeaheadSuggestion(
                    id: "topic-\(topic.id)",
                    text: topic.title,
                    type: .topic,
                    subtitle: "\(topic.postCount) posts"
                )
            }
        suggestions.append(contentsOf: topicMatches)

        // Scripture intent detection
        if looksLikeScripture(query) {
            let normalizedRef = normalizeScriptureReference(query)
            suggestions.append(TypeaheadSuggestion(
                id: "scripture-\(query)",
                text: normalizedRef,
                type: .scripture,
                subtitle: "Search scripture reference"
            ))
        }

        // People from Algolia (fast) — skip if task was cancelled between keystrokes
        guard !Task.isCancelled else { return }
        if let algoliaResults = try? await algolia.getUserSuggestions(query: query, limit: 3) {
            let peopleSuggestions = algoliaResults.map { u in
                TypeaheadSuggestion(
                    id: "person-\(u.id)",
                    text: u.displayName,
                    type: .person,
                    subtitle: "@\(u.username)",
                    avatarURL: u.profileImageURL
                )
            }
            suggestions.append(contentsOf: peopleSuggestions)
        }

        // Query completion (contextual suggestion)
        let expansion = expandQuery(query)
        if let expanded = expansion, expanded != query {
            suggestions.insert(TypeaheadSuggestion(
                id: "expand-\(query)",
                text: expanded,
                type: .queryCompletion
            ), at: 0)
        }

        typeaheadSuggestions = Array(suggestions.prefix(8))
    }

    // MARK: - Full Search

    private func performSearch(query: String) async {
        clearResults()

        // Classify query intent for better result ordering
        let intent = classifyDiscoveryQueryIntent(query)

        // Run all search streams concurrently using withTaskGroup to avoid
        // swift_task_dealloc crash when parent task is cancelled mid-flight.
        enum SearchResult {
            case people([DiscoveryPerson])
            case posts([DiscoveryPost])
            case topics([DiscoveryTopic])
            case churches([DiscoveryChurch])
            case notes([DiscoveryNote])
        }
        var people: [DiscoveryPerson] = []
        var posts: [DiscoveryPost] = []
        var topics: [DiscoveryTopic] = []
        var churches: [DiscoveryChurch] = []
        var notes: [DiscoveryNote] = []
        await withTaskGroup(of: SearchResult.self) { group in
            group.addTask { .people(await self.searchPeople(query: query)) }
            group.addTask { .posts(await self.searchPosts(query: query)) }
            group.addTask { .topics(await self.searchTopics(query: query)) }
            group.addTask { .churches(await self.searchChurches(query: query)) }
            group.addTask { .notes(await self.searchNotes(query: query)) }
            for await result in group {
                switch result {
                case .people(let r):   people = r
                case .posts(let r):    posts = r
                case .topics(let r):   topics = r
                case .churches(let r): churches = r
                case .notes(let r):    notes = r
                }
            }
        }
        peopleResults = people
        postResults = posts
        topicResults = topics
        churchResults = churches
        noteResults = notes

        // Build Top tab blended results with safety scoring + intent bias
        topResults = buildTopResultsBlend(
            intent: intent,
            people: people,
            posts: posts,
            topics: topics,
            churches: churches,
            notes: notes
        )
    }

    private func searchPeople(query: String) async -> [DiscoveryPerson] {
        // Algolia first, Firestore fallback
        if let algoliaUsers = try? await algolia.searchUsers(query: query, limit: 20) {
            let currentUser = Auth.auth().currentUser?.uid ?? ""
            let followingSet = FollowService.shared.following
            let mapped = algoliaUsers
                .filter { $0.objectID != currentUser }
                .map { u -> DiscoveryPerson in
                    DiscoveryPerson(
                        id: u.objectID,
                        displayName: u.displayName,
                        username: u.username,
                        bio: u.bio ?? "",
                        avatarURL: u.profileImageURL,
                        followerCount: u.followersCount ?? 0,
                        isVerified: u.isVerified,
                        isFollowing: followingSet.contains(u.objectID),
                        mutualFollowersCount: 0,
                        followReason: nil,
                        topicAffinities: [],
                        qualityScore: Double(u.followersCount ?? 0) * 0.01 + 50
                    )
                }
            if !mapped.isEmpty { return mapped }
        }

        // Firestore prefix fallback
        return await searchPeopleFirestore(query: query)
    }

    private func searchPeopleFirestore(query: String) async -> [DiscoveryPerson] {
        let lowered = query.lowercased()
        do {
            let snapshot = try await db.collection("users")
                .whereField("usernameLower", isGreaterThanOrEqualTo: lowered)
                .whereField("usernameLower", isLessThan: lowered + "\u{f8ff}")
                .limit(to: 15)
                .getDocuments()

            let followingSet = FollowService.shared.following
            let currentUser = Auth.auth().currentUser?.uid ?? ""

            return snapshot.documents.compactMap { doc in
                let d = doc.data()
                guard doc.documentID != currentUser,
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

    private func searchPosts(query: String) async -> [DiscoveryPost] {
        if let algoliaResults = try? await algolia.searchPosts(query: query, category: nil, limit: 20) {
            return algoliaResults.map { p in
                DiscoveryPost(
                    id: p.objectID,
                    authorId: p.authorId ?? "",
                    authorName: p.authorName,
                    authorHandle: "",
                    authorAvatarURL: nil,           // AlgoliaPost doesn't include avatar
                    excerpt: String(p.content.prefix(180)),
                    fullContent: p.content,
                    category: p.category,
                    topicTag: nil,                  // AlgoliaPost doesn't index topicTag
                    createdAt: Date(timeIntervalSince1970: p.createdAt ?? 0),
                    amenCount: p.likesCount,
                    commentCount: p.commentCount ?? 0,
                    imageURL: p.mediaURLs.first,    // mediaURLs is non-optional [String]
                    highlightedExcerpt: nil
                )
            }
        }
        return []
    }

    private func searchTopics(query: String) async -> [DiscoveryTopic] {
        DiscoveryTopic.catalog.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    private func searchChurches(query: String) async -> [DiscoveryChurch] {
        let lowered = query.lowercased()
        do {
            let snapshot = try await db.collection("churches")
                .whereField("nameLower", isGreaterThanOrEqualTo: lowered)
                .whereField("nameLower", isLessThan: lowered + "\u{f8ff}")
                .limit(to: 10)
                .getDocuments()

            return snapshot.documents.compactMap { doc in
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

    private func searchNotes(query: String) async -> [DiscoveryNote] {
        let lowered = query.lowercased()
        do {
            // Note: combining isPublic filter with titleLower range requires a composite
            // index. We query by titleLower only (no composite index needed) and filter
            // isPublic client-side on the small result set.
            let snapshot = try await db.collection("churchNotes")
                .whereField("titleLower", isGreaterThanOrEqualTo: lowered)
                .whereField("titleLower", isLessThan: lowered + "\u{f8ff}")
                .limit(to: 16)
                .getDocuments()

            return snapshot.documents.compactMap { doc in
                let d = doc.data()
                guard let title = d["title"] as? String,
                      d["isPublic"] as? Bool == true else { return nil }
                return DiscoveryNote(
                    id: doc.documentID,
                    title: title,
                    speakerName: d["speakerName"] as? String,
                    churchName: d["churchName"] as? String,
                    scriptureReference: d["scriptureReference"] as? String,
                    summary: d["summary"] as? String ?? "",
                    createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    tags: d["tags"] as? [String] ?? []
                )
            }
            .prefix(8)
            .map { $0 }
        } catch {
            return []
        }
    }

    // MARK: - Top Results Blending

    private func buildTopResultsBlend(
        intent: DiscoveryQueryIntent,
        people: [DiscoveryPerson],
        posts: [DiscoveryPost],
        topics: [DiscoveryTopic],
        churches: [DiscoveryChurch],
        notes: [DiscoveryNote]
    ) -> [DiscoveryResult] {
        var results: [DiscoveryResult] = []

        // Apply quotas based on intent — diversify top results
        let peopleCap   = intent == .person   ? 4 : 2
        let postsCap    = intent == .topic    ? 4 : 3
        let topicsCap   = intent == .topic    ? 3 : 2
        let churchesCap = intent == .church   ? 3 : 1
        let notesCap    = intent == .resource ? 2 : 1

        people.prefix(peopleCap).forEach { p in
            let score = min(100, p.qualityScore + (p.isFollowing ? 10 : 0))
            results.append(DiscoveryResult(id: "p-\(p.id)", type: .person(p),
                                           relevanceScore: score, safetyScore: 100))
        }

        topics.prefix(topicsCap).forEach { t in
            results.append(DiscoveryResult(id: "t-\(t.id)", type: .topic(t),
                                           relevanceScore: t.trendScore + 40, safetyScore: 100))
        }

        posts.prefix(postsCap).forEach { p in
            let freshness = max(0, 100 - Date().timeIntervalSince(p.createdAt) / 3600)
            let score = min(100, Double(p.amenCount) * 0.5 + freshness * 0.5)
            results.append(DiscoveryResult(id: "po-\(p.id)", type: .post(p),
                                           relevanceScore: score, safetyScore: 100))
        }

        churches.prefix(churchesCap).forEach { c in
            results.append(DiscoveryResult(id: "c-\(c.id)", type: .church(c),
                                           relevanceScore: 75, safetyScore: 100))
        }

        notes.prefix(notesCap).forEach { n in
            results.append(DiscoveryResult(id: "n-\(n.id)", type: .note(n),
                                           relevanceScore: 65, safetyScore: 100))
        }

        return results.sorted { $0.relevanceScore > $1.relevanceScore }
    }

    // MARK: - Query Intent Classification

    func classifyDiscoveryQueryIntent(_ query: String) -> DiscoveryQueryIntent {
        let lowered = query.lowercased()

        // Church intent
        if lowered.contains("church") || lowered.contains("ministry") ||
           lowered.contains("congregation") || lowered.contains("near me") {
            return .church
        }

        // Scripture intent
        if looksLikeScripture(query) { return .scripture }

        // Person intent (at-sign or known name patterns)
        if lowered.hasPrefix("@") { return .person }

        // Topic matches
        if DiscoveryTopic.catalog.contains(where: { $0.title.localizedCaseInsensitiveContains(query) }) {
            return .topic
        }

        // Resource intent
        if lowered.contains("sermon") || lowered.contains("book") ||
           lowered.contains("study guide") || lowered.contains("devotional") {
            return .resource
        }

        return .ambiguous
    }

    // MARK: - Scripture Reference Detection

    private func looksLikeScripture(_ query: String) -> Bool {
        let pattern = #"(?i)(?:genesis|exodus|leviticus|numbers|deuteronomy|joshua|judges|ruth|samuel|kings|chronicles|ezra|nehemiah|esther|job|psalm|psalms|proverbs|ecclesiastes|song|isaiah|jeremiah|lamentations|ezekiel|daniel|hosea|joel|amos|obadiah|jonah|micah|nahum|habakkuk|zephaniah|haggai|zechariah|malachi|matthew|mark|luke|john|acts|romans|corinthians|galatians|ephesians|philippians|colossians|thessalonians|timothy|titus|philemon|hebrews|james|peter|jude|revelation)\s*\d"#
        return query.range(of: pattern, options: .regularExpression) != nil
    }

    private func normalizeScriptureReference(_ query: String) -> String {
        // Simple normalization: capitalize and trim
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Query Expansion

    private func expandQuery(_ query: String) -> String? {
        let expansions: [String: String] = [
            "prayer": "Prayer & Intercession",
            "bible": "Bible Study",
            "church": "Church Community",
            "faith work": "Faith & Work",
            "marriage": "Christian Marriage",
            "salvation": "Salvation & Grace",
            "disciple": "Discipleship",
            "worship": "Worship & Praise",
        ]
        let lowered = query.lowercased()
        return expansions.first(where: { lowered.contains($0.key) })?.value
    }

    // MARK: - Helpers

    private func clearResults() {
        topResults = []
        peopleResults = []
        postResults = []
        topicResults = []
        churchResults = []
        noteResults = []
    }

    private func saveRecentSearches() {
        if let data = try? JSONEncoder().encode(recentSearches) {
            UserDefaults.standard.set(data, forKey: recentSearchesKey)
        }
    }

    private func loadRecentSearches() {
        guard let data = UserDefaults.standard.data(forKey: recentSearchesKey),
              let decoded = try? JSONDecoder().decode([RecentSearchItem].self, from: data)
        else { return }
        // Prune items older than 30 days
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        recentSearches = decoded.filter { $0.timestamp > cutoff }
    }
}


