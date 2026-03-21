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

enum SearchRankingService {

    // MARK: - People Ranking

    /// Ranks people by: follower count (log-scaled) + isFollowing boost + query name match.
    static func rankPeople(_ people: [DiscoveryPerson], query: String) -> [DiscoveryPerson] {
        let q = query.lowercased()
        return people.sorted { a, b in
            scoreForPerson(a, query: q) > scoreForPerson(b, query: q)
        }
    }

    private static func scoreForPerson(_ person: DiscoveryPerson, query: String) -> Double {
        var score: Double = 0

        // Name / username match boost (0–40)
        if person.displayName.lowercased().hasPrefix(query)   { score += 40 }
        else if person.username.lowercased().hasPrefix(query)  { score += 35 }
        else if person.displayName.lowercased().contains(query) { score += 20 }
        else if person.username.lowercased().contains(query)    { score += 15 }

        // Quality score from profile completeness signals (0–30)
        score += min(30, person.qualityScore * 0.3)

        // Follower count — log scale so mega-accounts don't dominate (0–20)
        score += min(20, log10(Double(max(1, person.followerCount))) * 5)

        // Already following — surface people the current user knows (10)
        if person.isFollowing { score += 10 }

        // Verified badge (5)
        if person.isVerified { score += 5 }

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

    private static func scoreForPost(_ post: DiscoveryPost, query: String) -> Double {
        var score: Double = 0

        let excerpt = post.excerpt.lowercased()

        // Query match in excerpt (0–35)
        if excerpt.hasPrefix(query)     { score += 35 }
        else if excerpt.contains(query) { score += 20 }

        // Recency — decays over 7 days (0–30)
        let ageHours = Date().timeIntervalSince(post.createdAt) / 3600
        let recency = max(0, 30 - ageHours / 5.6)   // ~30 at 0h, 0 at 168h (7d)
        score += recency

        // Engagement quality: log-scaled amen + comment counts (0–20)
        let engagement = log1p(Double(post.amenCount)) * 4 + log1p(Double(post.commentCount)) * 3
        score += min(20, engagement)

        // Has image (slight boost for richer content) (5)
        if post.imageURL != nil { score += 5 }

        return score
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

        for p in people.prefix(peopleCap) {
            let score = scoreForPerson(p, query: query.lowercased())
            results.append(DiscoveryResult(id: "p-\(p.id)", type: .person(p),
                                           relevanceScore: score, safetyScore: 100))
        }
        for t in topics.prefix(topicsCap) {
            results.append(DiscoveryResult(id: "t-\(t.id)", type: .topic(t),
                                           relevanceScore: t.trendScore + 40, safetyScore: 100))
        }
        for p in posts.prefix(postsCap) {
            let score = scoreForPost(p, query: query.lowercased())
            results.append(DiscoveryResult(id: "po-\(p.id)", type: .post(p),
                                           relevanceScore: score, safetyScore: 100))
        }
        for c in churches.prefix(churchesCap) {
            results.append(DiscoveryResult(id: "c-\(c.id)", type: .church(c),
                                           relevanceScore: 75, safetyScore: 100))
        }
        for pr in prayers.prefix(prayersCap) {
            let score = scoreForPost(pr, query: query.lowercased()) + 5 // prayer affinity boost
            results.append(DiscoveryResult(id: "pray-\(pr.id)", type: .post(pr),
                                           relevanceScore: score, safetyScore: 100))
        }
        for te in testimonies.prefix(testimoniesCap) {
            let score = scoreForPost(te, query: query.lowercased()) + 5
            results.append(DiscoveryResult(id: "test-\(te.id)", type: .post(te),
                                           relevanceScore: score, safetyScore: 100))
        }

        // Filter suppressed items and sort by relevance
        return results
            .filter { $0.safetyScore >= DiscoverySafetyThresholds.minimumSafetyScore }
            .sorted { $0.relevanceScore > $1.relevanceScore }
    }
}
