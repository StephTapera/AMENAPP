//
//  HeyFeedAlgorithm.swift
//  AMENAPP
//
//  Multi-signal feed scoring and ranking algorithm for the Hey Feed system.
//  Pure scoring logic — no network calls, no Firestore reads.
//
//  Depends on:
//    • Post / Post.PostCategory      (PostsManager.swift)
//    • HeyFeedPreferences            (HeyHeyFeedModels.swift)
//    • HeyFeedMode / FeedWeights        (HeyHeyFeedModels.swift)
//    • FeedTopic / DebateLevel       (HeyHeyFeedModels.swift)
//    • HeyFeedIntent / HeyFeedParseResult (HeyFeedAIParser.swift)
//

import Foundation

// MARK: - HeyFeedScore

struct HeyFeedScore {
    let postId: String
    let totalScore: Double
    let components: ScoreComponents

    struct ScoreComponents {
        /// 0-100: whether the author is followed.
        let following: Double
        /// 0-100: pinned / blocked topic alignment.
        let topicRelevance: Double
        /// 0-100: log-scaled engagement composite.
        let engagement: Double
        /// 0-100: recency decay.
        let recency: Double
        /// 0-100: pastoral / intent boost.
        let intentBoost: Double
        /// 0-100: user resonance signal.
        let resonanceBoost: Double
        /// 0-100 (or large negative): per-author boost/mute.
        let authorBoost: Double
        /// 0-50: applied as a subtraction; higher = more controversial.
        let controversyPenalty: Double
        /// 0-100: applied as a subtraction; unsafe content penalty.
        let safetyPenalty: Double
    }
}

// MARK: - HeyFeedAlgorithm

@MainActor
final class HeyFeedAlgorithm {

    static let shared = HeyFeedAlgorithm()
    private init() {}

    // MARK: - Public API

    /// Scores a single post against user preferences.
    func score(
        post: Post,
        preferences: HeyFeedPreferences,
        parseResult: HeyFeedParseResult?,
        resonanceScore: Double,
        followedAuthors: Set<String>
    ) -> HeyFeedScore {

        let postId = post.firebaseId ?? post.id.uuidString

        // 1. Following component
        let followingScore: Double = followedAuthors.contains(post.authorId) ? 80.0 : 0.0

        // 2. Topic relevance
        let topicScore = topicRelevance(post: post, preferences: preferences)

        // 3. Engagement (log-scaled, max raw 500 → 100)
        let engagementScore = engagementComponent(post: post)

        // 4. Recency decay
        let recencyScore = recencyComponent(createdAt: post.createdAt)

        // 5. Intent boost
        let intentScore = intentBoost(parseResult: parseResult)

        // 6. Resonance boost (capped at 100)
        let resonanceBoostScore = min(resonanceScore * 100.0, 100.0)

        // 7. Author boost / mute
        let authorScore = authorBoost(authorId: post.authorId, preferences: preferences)

        // 8. Controversy penalty
        let controversyPenaltyScore = controversyPenalty(post: post, preferences: preferences)

        // 9. Safety penalty
        let safetyPenaltyScore = safetyPenalty(post: post, preferences: preferences)

        // --- Weighted total ---
        let components = HeyFeedScore.ScoreComponents(
            following: followingScore,
            topicRelevance: topicScore,
            engagement: engagementScore,
            recency: recencyScore,
            intentBoost: intentScore,
            resonanceBoost: resonanceBoostScore,
            authorBoost: authorScore,
            controversyPenalty: controversyPenaltyScore,
            safetyPenalty: safetyPenaltyScore
        )

        let total = weightedTotal(components: components, preferences: preferences)

        dlog("[HeyFeedAlgorithm] post=\(postId) total=\(String(format: "%.1f", total)) " +
             "following=\(followingScore) topic=\(topicScore) engagement=\(String(format: "%.1f", engagementScore)) " +
             "recency=\(String(format: "%.1f", recencyScore)) intent=\(intentScore) author=\(authorScore)")

        return HeyFeedScore(postId: postId, totalScore: total, components: components)
    }

    /// Filters hidden / muted posts, scores the rest, and returns them sorted descending.
    func rank(
        posts: [Post],
        preferences: HeyFeedPreferences,
        parseResults: [String: HeyFeedParseResult],
        resonanceScores: [String: Double],
        followedAuthors: Set<String>
    ) -> [Post] {

        // Step 1: filter
        let eligible = posts.filter { post in
            let postId = post.firebaseId ?? post.id.uuidString
            guard !preferences.hiddenPosts.contains(postId) else { return false }
            guard !preferences.mutedAuthors.contains(post.authorId) else { return false }
            return true
        }

        // Step 2: score
        let scored: [(post: Post, score: Double)] = eligible.map { post in
            let postId  = post.firebaseId ?? post.id.uuidString
            let parse   = parseResults[postId]
            let res     = resonanceScores[postId] ?? 0.0
            let s       = score(
                post: post,
                preferences: preferences,
                parseResult: parse,
                resonanceScore: res,
                followedAuthors: followedAuthors
            )
            return (post, s.totalScore)
        }

        // Step 3: sort descending
        let sorted = scored
            .sorted { $0.score > $1.score }
            .map { $0.post }

        dlog("[HeyFeedAlgorithm] rank — eligible=\(eligible.count) sorted=\(sorted.count)")
        return sorted
    }

    /// Gate check: should this post appear in the feed at all?
    func shouldShowPost(
        _ post: Post,
        preferences: HeyFeedPreferences,
        safetyRisk: Double
    ) -> Bool {
        let postId = post.firebaseId ?? post.id.uuidString

        if preferences.hiddenPosts.contains(postId)        { return false }
        if preferences.mutedAuthors.contains(post.authorId){ return false }
        if safetyRisk > preferences.sensitivityFilter.riskThreshold { return false }

        return true
    }

    // MARK: - Score Components

    // MARK: Topic Relevance (0-100)

    private func topicRelevance(post: Post, preferences: HeyFeedPreferences) -> Double {
        let words = post.content.lowercased()
        var score = 0.0

        for topic in FeedTopic.allCases {
            let matched = topicKeywords(topic).contains { words.contains($0) }
            guard matched else { continue }

            if preferences.blockedTopics.contains(topic) {
                // Hard block — floor the whole post relevance
                score -= 100.0
                break
            }
            if preferences.pinnedTopics.contains(topic) {
                score += 50.0
            }
        }

        // Also give a small natural lift for prayer / testimony categories
        switch post.category {
        case .prayer:
            if preferences.pinnedTopics.contains(.faith) { score += 20.0 }
        case .testimonies:
            if preferences.pinnedTopics.contains(.faith) { score += 20.0 }
        default:
            break
        }

        return max(score, -100.0)
    }

    /// Lightweight keyword-to-FeedTopic mapping.
    private func topicKeywords(_ topic: FeedTopic) -> [String] {
        switch topic {
        case .faith:
            return ["god", "jesus", "prayer", "scripture", "bible", "church",
                    "faith", "worship", "gospel", "holy spirit", "testimony",
                    "devotion", "sermon", "blessing", "grace", "salvation"]
        case .business:
            return ["business", "entrepreneur", "startup", "market", "revenue",
                    "finance", "investing", "career", "leadership", "strategy"]
        case .tech:
            return ["tech", "software", "ai", "app", "code", "programming",
                    "developer", "machine learning", "digital", "algorithm"]
        case .politics:
            return ["politics", "government", "election", "policy", "law",
                    "congress", "senate", "president", "vote", "legislation"]
        case .relationships:
            return ["relationship", "marriage", "family", "friendship", "dating",
                    "love", "couples", "parenting", "children", "community"]
        case .mentalHealth:
            return ["mental health", "anxiety", "depression", "healing", "therapy",
                    "wellness", "stress", "burnout", "self care", "emotion"]
        case .culture:
            return ["culture", "music", "art", "film", "book", "literature",
                    "creativity", "fashion", "food", "travel", "community"]
        case .local:
            return ["local", "neighborhood", "city", "community event",
                    "nearby", "church nearby", "our town"]
        case .other:
            return []
        }
    }

    // MARK: Engagement (0-100)

    private func engagementComponent(post: Post) -> Double {
        // Composite raw value, weighted by interaction type
        let raw = Double(post.amenCount)
             + Double(post.commentCount) * 2.0
             + Double(post.repostCount)  * 3.0
             + Double(post.lightbulbCount)
        guard raw > 0 else { return 0.0 }
        // log scale: log(1 + raw) / log(1 + 500) * 100
        let maxRaw = 500.0
        let scaled = log(1.0 + min(raw, maxRaw)) / log(1.0 + maxRaw) * 100.0
        return min(scaled, 100.0)
    }

    // MARK: Recency (0-100)

    private func recencyComponent(createdAt: Date) -> Double {
        let ageSeconds = max(Date().timeIntervalSince(createdAt), 0)
        let ageHours   = ageSeconds / 3600.0

        if ageHours < 1.0 {
            return 100.0
        }
        // Halve every 12 hours, floor at 5
        // score = 100 * 0.5^(ageHours / 12)
        let score = 100.0 * pow(0.5, ageHours / 12.0)
        return max(score, 5.0)
    }

    // MARK: Intent Boost (0-100)

    private func intentBoost(parseResult: HeyFeedParseResult?) -> Double {
        guard let result = parseResult else { return 0.0 }
        switch result.intent {
        case .crisis:        return 100.0
        case .prayerRequest: return 70.0
        case .grief:         return 60.0
        case .fellowship:    return Double(HeyFeedIntent.fellowship.priority) / 10.0 * 60.0
        case .question:      return Double(HeyFeedIntent.question.priority)   / 10.0 * 60.0
        case .testimony:     return Double(HeyFeedIntent.testimony.priority)  / 10.0 * 60.0
        case .encouragement: return Double(HeyFeedIntent.encouragement.priority) / 10.0 * 60.0
        case .biblicalStudy: return Double(HeyFeedIntent.biblicalStudy.priority) / 10.0 * 60.0
        case .neutral:       return 0.0
        }
    }

    // MARK: Author Boost (0-100 or -200 for muted)

    private func authorBoost(authorId: String, preferences: HeyFeedPreferences) -> Double {
        if preferences.mutedAuthors.contains(authorId)   { return -200.0 }
        if preferences.boostedAuthors.contains(authorId) { return 60.0 }
        return 0.0
    }

    // MARK: Controversy Penalty (0-50)

    /// Simple heuristic: short posts with high comment counts signal debate.
    private func controversyPenalty(post: Post, preferences: HeyFeedPreferences) -> Double {
        let wordCount = post.content.split(separator: " ").count
        guard wordCount > 0, post.commentCount > 0 else { return 0.0 }

        // A high comments-to-words ratio hints at argumentative content.
        let ratio = Double(post.commentCount) / Double(wordCount)
        // Normalize: ratio > 2.0 is "high debate"
        let debateSignal = min(ratio / 2.0, 1.0)
        let rawPenalty   = debateSignal * preferences.debateLevel.controversyPenalty
        return min(rawPenalty, 50.0)
    }

    // MARK: Safety Penalty (0-100)

    /// Post-level safety risk compared against user's sensitivity threshold.
    private func safetyPenalty(post: Post, preferences: HeyFeedPreferences) -> Double {
        // Safety risk is passed in via shouldShowPost; here we apply a score penalty
        // for borderline content that clears the threshold but is still elevated.
        // We don't have the raw safetyRisk in this code path, so we conservatively
        // return 0 and let shouldShowPost handle hard blocks.
        return 0.0
    }

    // MARK: Weighted Total

    private func weightedTotal(
        components: HeyFeedScore.ScoreComponents,
        preferences: HeyFeedPreferences
    ) -> Double {
        let w = preferences.mode.weights

        // Map FeedWeights dimensions to score components:
        //   following  → followingScore + authorBoost
        //   local      → topicRelevance (local/community signal)
        //   discovery  → resonanceBoost + intentBoost
        //   learning   → engagement
        //   recency    → recency

        let followingTotal  = (components.following + max(components.authorBoost, 0)) / 2.0
        let localTotal      = max(components.topicRelevance, 0)
        let discoveryTotal  = (components.resonanceBoost + components.intentBoost) / 2.0
        let learningTotal   = components.engagement
        let recencyTotal    = components.recency

        let weighted = (w.following  * followingTotal)
                     + (w.local      * localTotal)
                     + (w.discovery  * discoveryTotal)
                     + (w.learning   * learningTotal)
                     + (w.recency    * recencyTotal)

        // Subtract penalties
        let penalised = weighted
            - components.controversyPenalty
            - components.safetyPenalty
            // Hard mute: ensure muted-author posts always score negatively
            + min(components.authorBoost, 0)

        return penalised
    }
}
