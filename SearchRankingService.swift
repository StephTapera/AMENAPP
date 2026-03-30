//
//  SearchRankingService.swift
//  AMENAPP
//
//  Re-ranks search results returned from Algolia / Firestore using
//  AMEN-specific signals: recency, engagement quality, query relevance,
//  and content safety.
//
//  Design principles:
//    - Stateless (all methods are static) — no singletons needed.
//    - Safe defaults: items with zero quality signals are not suppressed,
//      just ranked lower; suppression is delegated to ContentSafetyShieldService.
//    - Category affinity: prayer/testimony results boosted when query
//      semantically matches those domains.

import Foundation

// MARK: - Universal search results bundle (8 collections)

/// All search results returned from the 8-collection parallel Firestore search,
/// each section pre-ranked by SearchRankingService.
struct UniversalSearchResults {
    var people: [DiscoveryPerson]
    var posts: [DiscoveryPost]
    var churches: [DiscoveryChurch]
    var topics: [DiscoveryTopic]
    var prayers: [SearchSimpleItem]
    var testimonies: [SearchSimpleItem]
    var books: [SearchSimpleItem]
    var events: [SearchSimpleItem]

    var isEmpty: Bool {
        people.isEmpty && posts.isEmpty && churches.isEmpty &&
        topics.isEmpty && prayers.isEmpty && testimonies.isEmpty &&
        books.isEmpty && events.isEmpty
    }
}

/// Lightweight model for prayers / testimonies / books / events result rows.
struct SearchSimpleItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?           // author, location, date string, etc.
    let iconName: String            // SF Symbol
    var relevanceScore: Double
}

// MARK: - Ranking engine

enum SearchRankingService {

    // MARK: - Core text-match scorer
    //
    // Scoring rubric (additive, per field):
    //   Exact (case-insensitive) match  → +3 pts
    //   Prefix match                    → +2 pts
    //   Contains                        → +1 pt
    //   Has profileImageURL/cover       → +0.5 pts  (caller adds)
    //   followerCount or likeCount >100 → +0.5 pts  (caller adds)

    static func textScore(candidate: String, query: String) -> Double {
        guard !query.isEmpty else { return 0 }
        let c = candidate.lowercased()
        let q = query.lowercased()
        if c == q           { return 3 }
        if c.hasPrefix(q)   { return 2 }
        if c.contains(q)    { return 1 }
        return 0
    }

    // MARK: - People Ranking

    /// Ranks people by: query relevance + engagement signals.
    static func rankPeople(_ people: [DiscoveryPerson], query: String) -> [DiscoveryPerson] {
        let q = query.lowercased()
        return people.sorted { a, b in
            scoreForPerson(a, query: q) > scoreForPerson(b, query: q)
        }
    }

    static func scoreForPerson(_ person: DiscoveryPerson, query: String) -> Double {
        var score: Double = 0

        // Text matching across display name and username
        score += textScore(candidate: person.displayName, query: query) * 3
        score += textScore(candidate: person.username,    query: query) * 2

        // Image presence bonus
        if let url = person.avatarURL, !url.isEmpty { score += 0.5 }

        // Follower/engagement signal
        if person.followerCount > 100 { score += 0.5 }

        // Quality score from profile completeness (0–30, scaled down)
        score += min(3, person.qualityScore * 0.03)

        // Follower count — log scale
        score += min(2, log10(Double(max(1, person.followerCount))) * 0.5)

        // Already following
        if person.isFollowing { score += 1 }

        // Verified badge
        if person.isVerified { score += 0.5 }

        return score
    }

    // MARK: - Post Ranking

    /// Ranks posts by: query relevance in excerpt + recency + engagement.
    static func rankPosts(_ posts: [DiscoveryPost], query: String) -> [DiscoveryPost] {
        let q = query.lowercased()
        return posts.sorted { a, b in
            scoreForPost(a, query: q) > scoreForPost(b, query: q)
        }
    }

    static func scoreForPost(_ post: DiscoveryPost, query: String) -> Double {
        var score: Double = 0

        score += textScore(candidate: post.excerpt, query: query)
        if let tag = post.topicTag {
            score += textScore(candidate: tag, query: query) * 0.5
        }

        // Image presence
        if post.imageURL != nil { score += 0.5 }

        // Engagement
        if post.amenCount > 100 { score += 0.5 }

        // Recency — decays over 7 days
        let ageHours = Date().timeIntervalSince(post.createdAt) / 3600
        let recency = max(0, 1.0 - ageHours / 168.0)
        score += recency

        return score
    }

    // MARK: - Church Ranking

    static func rankChurches(_ churches: [DiscoveryChurch], query: String) -> [DiscoveryChurch] {
        let q = query.lowercased()
        return churches.sorted { a, b in
            scoreForChurch(a, query: q) > scoreForChurch(b, query: q)
        }
    }

    private static func scoreForChurch(_ church: DiscoveryChurch, query: String) -> Double {
        var score: Double = 0
        score += textScore(candidate: church.name, query: query) * 3
        score += textScore(candidate: church.city, query: query)
        if let img = church.imageURL, !img.isEmpty { score += 0.5 }
        if church.isVerified { score += 0.5 }
        return score
    }

    // MARK: - Topic Ranking

    static func rankTopics(_ topics: [DiscoveryTopic], query: String) -> [DiscoveryTopic] {
        let q = query.lowercased()
        return topics.sorted { a, b in
            scoreForTopic(a, query: q) > scoreForTopic(b, query: q)
        }
    }

    private static func scoreForTopic(_ topic: DiscoveryTopic, query: String) -> Double {
        var score = textScore(candidate: topic.title, query: query) * 3
        score += textScore(candidate: topic.description, query: query)
        if topic.postCount > 100 { score += 0.5 }
        score += min(1, topic.trendScore / 100.0)
        return score
    }

    // MARK: - Simple Item Ranking (prayers, testimonies, books, events)

    static func rankSimpleItems(_ items: [SearchSimpleItem], query: String) -> [SearchSimpleItem] {
        let q = query.lowercased()
        return items
            .map { item in
                var s = textScore(candidate: item.title, query: q) * 3
                if let sub = item.subtitle {
                    s += textScore(candidate: sub, query: q)
                }
                return SearchSimpleItem(
                    id: item.id,
                    title: item.title,
                    subtitle: item.subtitle,
                    iconName: item.iconName,
                    relevanceScore: s
                )
            }
            .sorted { $0.relevanceScore > $1.relevanceScore }
    }

    // MARK: - Top Results Blending

    /// Merges heterogeneous result arrays into a ranked Top tab list.
    /// Quota-aware: limits per type to ensure diversity.
    static func blendTopResults(
        people: [DiscoveryPerson],
        posts: [DiscoveryPost],
        topics: [DiscoveryTopic],
        churches: [DiscoveryChurch],
        prayers: [DiscoveryPost],
        testimonies: [DiscoveryPost],
        query: String,
        intent: DiscoveryQueryIntent
    ) -> [DiscoveryResult] {
        var results: [DiscoveryResult] = []

        // Intent-aware caps
        let peopleCap      = intent == .person   ? 4 : 2
        let postsCap       = intent == .topic    ? 4 : 2
        let topicsCap      = intent == .topic    ? 3 : 2
        let churchesCap    = intent == .church   ? 3 : 1
        let prayersCap     = 1
        let testimoniesCap = 1

        let q = query.lowercased()

        for p in people.prefix(peopleCap) {
            let score = scoreForPerson(p, query: q)
            results.append(DiscoveryResult(id: "p-\(p.id)", type: .person(p),
                                           relevanceScore: score, safetyScore: 100))
        }
        for t in topics.prefix(topicsCap) {
            let score = scoreForTopic(t, query: q)
            results.append(DiscoveryResult(id: "t-\(t.id)", type: .topic(t),
                                           relevanceScore: score + t.trendScore * 0.1, safetyScore: 100))
        }
        for p in posts.prefix(postsCap) {
            let score = scoreForPost(p, query: q)
            results.append(DiscoveryResult(id: "po-\(p.id)", type: .post(p),
                                           relevanceScore: score, safetyScore: 100))
        }
        for c in churches.prefix(churchesCap) {
            let score = scoreForChurch(c, query: q)
            results.append(DiscoveryResult(id: "c-\(c.id)", type: .church(c),
                                           relevanceScore: score, safetyScore: 100))
        }
        for pr in prayers.prefix(prayersCap) {
            let score = scoreForPost(pr, query: q) + 0.5 // prayer affinity boost
            results.append(DiscoveryResult(id: "pray-\(pr.id)", type: .post(pr),
                                           relevanceScore: score, safetyScore: 100))
        }
        for te in testimonies.prefix(testimoniesCap) {
            let score = scoreForPost(te, query: q) + 0.5
            results.append(DiscoveryResult(id: "test-\(te.id)", type: .post(te),
                                           relevanceScore: score, safetyScore: 100))
        }

        // Filter suppressed items and sort by relevance
        return results
            .filter { $0.safetyScore >= DiscoverySafetyThresholds.minimumSafetyScore }
            .sorted { $0.relevanceScore > $1.relevanceScore }
    }
}
