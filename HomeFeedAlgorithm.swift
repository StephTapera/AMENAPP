//
//  HomeFeedAlgorithm.swift
//  AMENAPP
//
//  Created by AI Assistant on 2/2/26.
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Home Feed Personalization Algorithm

/// Intelligent feed ranking algorithm that personalizes content for each user
/// Based on engagement patterns, interests, and community relevance
@MainActor
class HomeFeedAlgorithm: ObservableObject {
    static let shared = HomeFeedAlgorithm()
    
    @Published var personalizedPosts: [Post] = []
    @Published var userInterests = UserInterests()

    // Cached set of user IDs that the current viewer follows.
    // Populated by ViewModelsHomeViewModel / PostsManager after loading following list.
    // Used by scorePost to enforce followers-only visibility in the feed.
    var followingIds: Set<String> = []
    
    // MARK: - User Interests Model
    
    struct UserInterests: Codable {
        var engagedTopics: [String: Double] = [:]  // Topic → Interest score (0-100)
        var engagedAuthors: [String: Int] = [:]     // AuthorID → Engagement count
        var interactionHistory: [String: Int] = [:] // PostID → Interactions
        var preferredCategories: [String: Double] = [:] // Category → Preference score
        var onboardingGoals: [String] = []  // Goals selected during onboarding
        var lastUpdate: Date = Date()
        
        // Time decay factor
        var isStale: Bool {
            Date().timeIntervalSince(lastUpdate) > 86400 // 24 hours
        }
    }
    
    // MARK: - Scoring Context (pre-captures MainActor values for background use)

    /// Snapshot of all @MainActor-isolated values needed by scorePost.
    /// Captured on the main thread in personalizePostsDebounced, then passed
    /// to the background Task.detached so scorePost can run fully nonisolated.
    struct ScoringContext {
        let prefsLoaded: Bool
        let mutedAuthors: Set<String>
        let hiddenPosts: Set<String>
        let boostedPosts: Set<String>
        let boostedAuthors: Set<String>
        let controversyPenaltyFactor: Double
        let topicWeights: [FeedTopic: Double]
        let modeWeightsRecency: Double
        let modeWeightsFollowing: Double
        let currentUserId: String?

        @MainActor
        static func capture() -> ScoringContext {
            let svc = HeyFeedPreferencesService.shared
            let prefs = svc.preferences
            let weights = prefs.mode.weights
            // Build a local copy of topic weights so background thread never touches @MainActor state
            var topicWeights: [FeedTopic: Double] = [:]
            for topic in FeedTopic.allCases {
                topicWeights[topic] = svc.getTopicWeight(topic)
            }
            return ScoringContext(
                prefsLoaded: svc.lastRefreshTime != nil,
                mutedAuthors: prefs.mutedAuthors,
                hiddenPosts: prefs.hiddenPosts,
                boostedPosts: prefs.boostedPosts,
                boostedAuthors: prefs.boostedAuthors,
                controversyPenaltyFactor: prefs.debateLevel.controversyPenalty / 50.0,
                topicWeights: topicWeights,
                modeWeightsRecency: weights.recency,
                modeWeightsFollowing: weights.following,
                currentUserId: Auth.auth().currentUser?.uid
            )
        }
    }

    // MARK: - Post Scoring

    /// Score a post for personalized relevance (0-100).
    /// Pass a pre-captured `ScoringContext` when calling from a background thread.
    /// When `context` is nil the function reads HeyFeedPreferencesService directly
    /// (safe only on the MainActor — use only for synchronous main-thread callsites).
    nonisolated func scorePost(_ post: Post,
                               for interests: UserInterests,
                               followingIds: Set<String> = [],
                               context: ScoringContext? = nil) -> Double {
        // Resolve preferences — use pre-captured context if provided (background-safe),
        // otherwise read the service directly (main-thread only path).
        let prefsLoaded: Bool
        let mutedAuthors: Set<String>
        let hiddenPosts: Set<String>
        let boostedPosts: Set<String>
        let boostedAuthors: Set<String>
        let controversyPenaltyFactor: Double
        let modeWeightsRecency: Double
        let modeWeightsFollowing: Double
        let currentUserId: String?

        if let ctx = context {
            prefsLoaded              = ctx.prefsLoaded
            mutedAuthors             = ctx.mutedAuthors
            hiddenPosts              = ctx.hiddenPosts
            boostedPosts             = ctx.boostedPosts
            boostedAuthors           = ctx.boostedAuthors
            controversyPenaltyFactor = ctx.controversyPenaltyFactor
            modeWeightsRecency       = ctx.modeWeightsRecency
            modeWeightsFollowing     = ctx.modeWeightsFollowing
            currentUserId            = ctx.currentUserId
        } else {
            // ⚠️ This path is only reached from main-actor-isolated call sites (legacy/sync).
            // Use assumeIsolated so the compiler allows access to @MainActor properties.
            let captured = MainActor.assumeIsolated {
                let svc   = HeyFeedPreferencesService.shared
                let prefs = svc.preferences
                let w     = prefs.mode.weights
                return (
                    prefsLoaded: svc.lastRefreshTime != nil,
                    mutedAuthors: prefs.mutedAuthors,
                    hiddenPosts: prefs.hiddenPosts,
                    boostedPosts: prefs.boostedPosts,
                    boostedAuthors: prefs.boostedAuthors,
                    controversyPenaltyFactor: prefs.debateLevel.controversyPenalty / 50.0,
                    modeWeightsRecency: w.recency,
                    modeWeightsFollowing: w.following,
                    currentUserId: Auth.auth().currentUser?.uid as String?
                )
            }
            prefsLoaded              = captured.prefsLoaded
            mutedAuthors             = captured.mutedAuthors
            hiddenPosts              = captured.hiddenPosts
            boostedPosts             = captured.boostedPosts
            boostedAuthors           = captured.boostedAuthors
            controversyPenaltyFactor = captured.controversyPenaltyFactor
            modeWeightsRecency       = captured.modeWeightsRecency
            modeWeightsFollowing     = captured.modeWeightsFollowing
            currentUserId            = captured.currentUserId
        }

        // Gate: muted authors / hidden posts (only after prefs loaded from Firestore)
        if prefsLoaded && mutedAuthors.contains(post.authorId) { return 0.0 }
        if prefsLoaded && hiddenPosts.contains(post.firebaseId ?? post.id.uuidString) { return 0.0 }

        // Privacy gate: followers-only posts must not appear for non-followers.
        if post.visibility == .followers && !followingIds.contains(post.authorId) {
            if let uid = currentUserId, post.authorId != uid { return 0.0 }
        }

        var score: Double = 0.0

        // 1. Recency Score — weighted by mode
        score += calculateRecencyScore(post) * modeWeightsRecency * 100

        // 2. Following Relationship — weighted by mode
        score += calculateFollowingScore(post, followingIds: followingIds) * modeWeightsFollowing * 100

        // 3. Topic Relevance (18%)
        score += calculateTopicScore(post, interests: interests) * 0.18

        // 4. Goal Alignment (12%)
        score += calculateGoalScore(post, interests: interests) * 0.12

        // 5. Author Affinity (9%)
        score += calculateAuthorScore(post, interests: interests) * 0.09

        // 6. Engagement Quality (12%)
        score += calculateEngagementScore(post) * 0.12

        // 7. Diversity Bonus (8%)
        score += calculateDiversityScore(post, interests: interests) * 0.08

        // 8. Category Boost — Tips and Fun Facts
        score += calculateCategoryBoost(post, interests: interests)

        // 9. Anti-Ragebait Penalty
        score -= calculateControversyPenalty(post) * controversyPenaltyFactor

        // 10. Repetition Penalty
        score -= calculateRepetitionPenalty(post, interests: interests)

        // 11. Topic Weight (0x block, 1x neutral, 2x pinned)
        let postTopic = mapCategoryToTopic(post.category)
        let topicMultiplier = context?.topicWeights[postTopic] ?? 1.0
        score *= topicMultiplier

        // 12. Boosted Posts / Authors
        let postId = post.firebaseId ?? post.id.uuidString
        if boostedPosts.contains(postId)          { score += 20 }
        if boostedAuthors.contains(post.authorId) { score += 15 }

        // 13. Living Wall spiritual momentum (prayer/testimony posts only)
        if post.category == .prayer || post.category == .testimonies {
            let livingWallScore = LivingWallRanker.shared.score(post)
            // Normalize to 0-10 contribution to avoid overpowering other signals
            score += min(10, livingWallScore * 0.05)
        }

        return min(100, max(0, score))
    }
    
    // MARK: - Following Relationship Score
    
    /// Boost posts from people user follows (relationship strength)
    nonisolated private func calculateFollowingScore(_ post: Post, followingIds: Set<String>) -> Double {
        if followingIds.contains(post.authorId) {
            return 90  // High priority for followed accounts
        } else {
            return 30  // Neutral for discovery
        }
    }
    
    // MARK: - Category Boost
    
    /// Give special boost to Tip and Fun Fact posts to help them surface
    nonisolated private func calculateCategoryBoost(_ post: Post, interests: UserInterests) -> Double {
        switch post.category {
        case .tip:
            // Tips are valuable - give them a boost to help discovery
            return 8.0
        case .funFact:
            // Fun Facts are engaging - give them a boost to surface well
            return 8.0
        default:
            return 0.0
        }
    }
    
    // MARK: - Recency Scoring
    
    nonisolated private func calculateRecencyScore(_ post: Post) -> Double {
        let now = Date()
        let hoursSincePost = now.timeIntervalSince(post.createdAt) / 3600
        
        // Exponential decay: 100 for new posts, decreases over time
        if hoursSincePost < 1 {
            return 100 // Brand new (< 1 hour)
        } else if hoursSincePost < 6 {
            return 90 // Very recent (< 6 hours)
        } else if hoursSincePost < 24 {
            return 70 // Recent (< 1 day)
        } else if hoursSincePost < 72 {
            return 40 // Somewhat old (< 3 days)
        } else {
            return max(10, 40 - (hoursSincePost - 72) / 24 * 5) // Gradual decay
        }
    }
    
    // MARK: - Topic Relevance Scoring
    
    nonisolated private func calculateTopicScore(_ post: Post, interests: UserInterests) -> Double {
        var topicScore: Double = 50 // Baseline neutral score
        
        // Check if post topic matches user interests
        if let topicTag = post.topicTag,
           let interestLevel = interests.engagedTopics[topicTag] {
            topicScore = interestLevel
        }
        
        // Check if post content contains keywords from user's interests
        let contentWords = Set(post.content.lowercased().split(separator: " ").map(String.init))
        let matchedTopics = interests.engagedTopics.filter { topic, score in
            contentWords.contains(topic.lowercased())
        }
        
        if !matchedTopics.isEmpty {
            let avgMatch = matchedTopics.values.reduce(0, +) / Double(matchedTopics.count)
            topicScore = max(topicScore, avgMatch)
        }
        
        return topicScore
    }
    
    // MARK: - Goal Alignment Scoring
    
    /// Score posts based on alignment with user's spiritual goals
    nonisolated private func calculateGoalScore(_ post: Post, interests: UserInterests) -> Double {
        guard !interests.onboardingGoals.isEmpty else {
            return 50 // Neutral if no goals set
        }
        
        var goalScore: Double = 30 // Baseline
        
        // Map goals to relevant keywords and categories
        let goalKeywords: [String: [String]] = [
            "Grow in Faith": ["faith", "spiritual", "growth", "journey", "testimony", "berean"],
            "Daily Bible Reading": ["scripture", "bible", "verse", "psalm", "gospel", "word"],
            "Consistent Prayer": ["prayer", "pray", "praying", "intercession", "worship"],
            "Build Community": ["community", "fellowship", "church", "gathering", "together"],
            "Share the Gospel": ["gospel", "evangelism", "witness", "testimony", "share"],
            "Serve Others": ["serve", "service", "volunteer", "help", "ministry", "mission"]
        ]
        
        let contentLower = post.content.lowercased()
        
        // Check if post content aligns with any of the user's goals
        for goal in interests.onboardingGoals {
            if let keywords = goalKeywords[goal] {
                let matchCount = keywords.filter { contentLower.contains($0) }.count
                if matchCount > 0 {
                    // Boost score based on keyword matches (up to 100)
                    goalScore += Double(matchCount) * 15
                }
            }
        }
        
        // Category-based goal alignment
        switch post.category {
        case .prayer:
            if interests.onboardingGoals.contains("Consistent Prayer") {
                goalScore += 20
            }
        case .testimonies:
            if interests.onboardingGoals.contains("Share the Gospel") || 
               interests.onboardingGoals.contains("Grow in Faith") {
                goalScore += 20
            }
        case .openTable:
            if interests.onboardingGoals.contains("Build Community") {
                goalScore += 15
            }
        default:
            break
        }
        
        return min(100, goalScore)
    }
    
    // MARK: - Author Affinity Scoring
    
    nonisolated private func calculateAuthorScore(_ post: Post, interests: UserInterests) -> Double {
        guard let engagementCount = interests.engagedAuthors[post.authorId] else {
            return 30 // New author - neutral score
        }
        
        // More engagements with author = higher score
        // Cap at 100, scale logarithmically to prevent extreme scores
        let rawScore = min(100, 30 + (log(Double(engagementCount) + 1) * 20))
        return rawScore
    }
    
    // MARK: - Engagement Quality Scoring
    
    nonisolated private func calculateEngagementScore(_ post: Post) -> Double {
        // Weighted engagement: comments > reactions
        // Note: viewCount is not available on Post model yet
        let commentWeight = Double(post.commentCount) * 3.0
        let reactionWeight = Double(post.amenCount) * 1.5
        
        let totalEngagement = commentWeight + reactionWeight
        
        // Logarithmic scaling to prevent viral posts from dominating
        if totalEngagement < 5 {
            return 30 // Low engagement
        } else if totalEngagement < 20 {
            return 50 // Moderate engagement
        } else if totalEngagement < 50 {
            return 70 // Good engagement
        } else if totalEngagement < 100 {
            return 85 // High engagement
        } else {
            return min(100, 85 + log(totalEngagement - 100) * 3)
        }
    }
    
    // MARK: - Diversity Scoring
    
    nonisolated private func calculateDiversityScore(_ post: Post, interests: UserInterests) -> Double {
        // Reward posts from categories user hasn't engaged with much
        let categoryEngagement = interests.preferredCategories[post.category.rawValue] ?? 0
        
        // Inverse scoring: less engaged categories get diversity bonus
        if categoryEngagement < 20 {
            return 70 // High diversity bonus
        } else if categoryEngagement < 50 {
            return 50 // Moderate diversity
        } else {
            return 20 // Low diversity (already engaged)
        }
    }
    
    // MARK: - Anti-Ragebait Mechanics
    
    /// ✅ Detect and penalize controversial/ragebait content
    /// Looks for engagement spikes combined with negative signals
    nonisolated private func calculateControversyPenalty(_ post: Post) -> Double {
        var penalty: Double = 0.0
        
        // Signal 1: Abnormally high comment-to-reaction ratio (debate/argument)
        // Healthy posts have ~1:3 comment-to-reaction ratio
        // Controversial posts have ~1:1 or higher (lots of debate)
        if post.amenCount > 0 {
            let commentToReactionRatio = Double(post.commentCount) / Double(post.amenCount)
            
            if commentToReactionRatio > 1.5 {
                // Very high ratio = likely controversial
                penalty += 30
            } else if commentToReactionRatio > 1.0 {
                // Moderate ratio = possibly controversial
                penalty += 15
            }
        }
        
        // Signal 2: Rapid engagement spike in short time (viral ragebait)
        // Posts with 50+ comments in first hour are suspicious
        let hoursSincePost = Date().timeIntervalSince(post.createdAt) / 3600
        if hoursSincePost < 1 && post.commentCount > 50 {
            penalty += 30
            #if DEBUG
            dlog("⚠️ [CONTROVERSY] Rapid engagement spike detected")
            #endif
        }
        
        // Signal 3: Check if post has been reported (future integration with moderation)
        // This would require adding a reportCount field to Post model
        // For now, we'll leave this as a placeholder
        
        return penalty
    }
    
    /// ✅ Prevent same author from dominating feed (repetition penalty)
    /// Tracks how many times user has seen this author today
    nonisolated private func calculateRepetitionPenalty(_ post: Post, interests: UserInterests) -> Double {
        // Check how many times user has engaged with this author
        let authorEngagementCount = interests.engagedAuthors[post.authorId] ?? 0
        
        // If user has seen this author 4+ times recently, apply penalty
        // This prevents feed from being dominated by one prolific poster
        if authorEngagementCount > 6 {
            return 25 // Strong penalty (seen 7+ times)
        } else if authorEngagementCount > 4 {
            return 15 // Moderate penalty (seen 5-6 times)
        } else if authorEngagementCount > 3 {
            return 5  // Light penalty (seen 4 times)
        }
        
        return 0 // No penalty for fresh authors
    }
    
    // MARK: - Feed Ranking
    
    /// Rank posts using personalized algorithm with ethical safeguards.
    /// `nonisolated` so this can be called safely from `Task.detached` without
    /// inheriting the `@MainActor` isolation of the enclosing class.
    nonisolated func rankPosts(_ posts: [Post],
                              for interests: UserInterests,
                              followingIds: Set<String> = [],
                              scoringContext: ScoringContext? = nil) -> [Post] {
        // 1. Filter spam and low-quality content FIRST
        let filteredPosts = applyEthicalFilters(posts)

        // Respect personalizedRecommendations privacy toggle
        let isPersonalized = UserDefaults.standard.object(forKey: "personalizedRecommendations") as? Bool ?? true
        guard isPersonalized else {
            // Chronological order when personalization is off
            return filteredPosts.sorted { $0.createdAt > $1.createdAt }
        }

        // 2. Score remaining posts — pass pre-captured context for background safety
        let scoredPosts = filteredPosts.map { post in
            (post: post, score: scorePost(post, for: interests, followingIds: followingIds, context: scoringContext))
        }

        // 3. Sort by score
        let sorted = scoredPosts.sorted { $0.score > $1.score }

        // 4. Apply author diversity (prevent same author dominating feed)
        let diversified = applyAuthorDiversity(sorted)

        return diversified.map { $0.post }
    }
    
    // MARK: - Ethical Safeguards
    
    /// Filter out spam, duplicates, and low-quality content
    nonisolated private func applyEthicalFilters(_ posts: [Post]) -> [Post] {
        var seen = Set<String>()
        var authorPostCount: [String: Int] = [:]
        
        return posts.filter { post in
            // Filter 1: No duplicate/near-duplicate content
            let contentHash = post.content.lowercased().prefix(50)
            guard !seen.contains(String(contentHash)) else {
                dlog("🚫 [SPAM FILTER] Duplicate content blocked")
                return false
            }
            seen.insert(String(contentHash))
            
            // Filter 2: Limit posts per author (no flooding)
            let count = authorPostCount[post.authorId, default: 0]
            guard count < 10 else {
                dlog("🚫 [SPAM FILTER] Author \(post.authorId) flooding blocked")
                return false
            }
            authorPostCount[post.authorId] = count + 1
            
            // Filter 3: Engagement bait detection (all caps, excessive emoji)
            let hasEngagementBait = detectEngagementBait(post)
            if hasEngagementBait {
                dlog("🚫 [ENGAGEMENT BAIT] Post filtered")
                return false
            }
            
            return true
        }
    }
    
    /// Detect engagement bait patterns
    nonisolated private func detectEngagementBait(_ post: Post) -> Bool {
        let content = post.content
        
        // Check for ALL CAPS (> 70% uppercase)
        let uppercaseCount = content.filter { $0.isUppercase }.count
        if Double(uppercaseCount) / Double(content.count) > 0.7 {
            return true
        }
        
        // Check for excessive emoji (> 30% of characters)
        let emojiCount = content.unicodeScalars.filter { $0.properties.isEmoji }.count
        if Double(emojiCount) / Double(content.count) > 0.3 {
            return true
        }
        
        return false
    }
    
    /// Apply author diversity - prevent same author appearing consecutively
    nonisolated private func applyAuthorDiversity(_ scoredPosts: [(post: Post, score: Double)]) -> [(post: Post, score: Double)] {
        var result: [(post: Post, score: Double)] = []
        var lastAuthorId: String? = nil
        var skippedPosts: [(post: Post, score: Double)] = []
        
        for item in scoredPosts {
            if item.post.authorId == lastAuthorId {
                // Same author as previous - skip for now
                skippedPosts.append(item)
            } else {
                // Different author - add to result
                result.append(item)
                lastAuthorId = item.post.authorId
            }
        }
        
        // Add skipped posts at the end (prevents total exclusion)
        result.append(contentsOf: skippedPosts)
        
        return result
    }
    
    // MARK: - Interest Learning
    
    /// Update user interests based on interaction
    func recordInteraction(with post: Post, type: InteractionType) {
        // Update topic interests
        if let topic = post.topicTag {
            let currentScore = userInterests.engagedTopics[topic] ?? 50
            let boost = type.scoreBoost
            userInterests.engagedTopics[topic] = min(100, currentScore + boost)
        }
        
        // Update author affinity
        userInterests.engagedAuthors[post.authorId, default: 0] += type.weight
        
        // Update category preference
        let category = post.category.rawValue
        let currentPref = userInterests.preferredCategories[category] ?? 50
        userInterests.preferredCategories[category] = min(100, currentPref + type.scoreBoost / 2)
        
        // Record interaction - use stable Firestore ID if available, fall back to local UUID
        let postKey = post.firebaseId ?? post.id.uuidString
        userInterests.interactionHistory[postKey, default: 0] += 1
        
        // Update timestamp
        userInterests.lastUpdate = Date()
        
        // Persist
        saveInterests()

    }
    
    enum InteractionType {
        case view
        case reaction
        case comment
        case share
        case longRead // Spent >10s reading
        
        var scoreBoost: Double {
            switch self {
            case .view: return 1
            case .reaction: return 5
            case .comment: return 10
            case .share: return 15
            case .longRead: return 8
            }
        }
        
        var weight: Int {
            switch self {
            case .view: return 1
            case .reaction: return 2
            case .comment: return 3
            case .share: return 4
            case .longRead: return 2
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveInterests() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(userInterests)
            UserDefaults.standard.set(data, forKey: "userInterests_v1")
        } catch {
            dlog("❌ Failed to save user interests: \(error)")
        }
    }
    
    private static let interestsDecoder = JSONDecoder()
    private var interestsLoaded = false

    func loadInterests() {
        // Skip redundant loads on tab switches
        guard !interestsLoaded else { return }

        guard let data = UserDefaults.standard.data(forKey: "userInterests_v1") else {
            interestsLoaded = true
            Task { await loadGoalsFromFirestore() }
            return
        }

        do {
            userInterests = try Self.interestsDecoder.decode(UserInterests.self, from: data)
            interestsLoaded = true

            // Load goals from Firestore (once)
            Task { await loadGoalsFromFirestore() }
        } catch {
            dlog("❌ Failed to load interests: \(error)")
        }
    }
    
    /// Load user's onboarding goals from Firestore
    func loadGoalsFromFirestore() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let db = Firestore.firestore()
            let doc = try await db.collection("users").document(userId).getDocument()
            
            if let goals = doc.data()?["goals"] as? [String], !goals.isEmpty {
                await MainActor.run {
                    userInterests.onboardingGoals = goals
                    dlog("✅ Loaded \(goals.count) goals from Firestore: \(goals.joined(separator: ", "))")
                    
                    // Save updated interests
                    saveInterests()
                }
            }
        } catch {
            dlog("❌ Failed to load goals from Firestore: \(error)")
        }
    }
    
    // MARK: - Debounced Personalization (P1-3 Performance Fix)
    
    private var personalizationTask: Task<Void, Never>?
    private var lastPersonalizationTime: Date?
    private let debounceInterval: TimeInterval = 0.3  // 300ms debounce
    
    /// Debounced personalization - prevents excessive re-ranking during rapid updates.
    /// Ranking is performed on a background thread to keep the main thread free.
    func personalizePostsDebounced(_ posts: [Post]) {
        // Cancel any pending personalization task
        personalizationTask?.cancel()

        // Always sync followingIds from the live FollowService before ranking
        followingIds = FollowService.shared.following

        // Capture all values needed by the background task while still on the main thread.
        // ScoringContext snapshots @MainActor-isolated HeyFeedPreferencesService state so
        // rankPosts / scorePost can run fully nonisolated in Task.detached.
        let snapshotInterests = userInterests
        let snapshotFollowingIds = followingIds
        let snapshotContext = ScoringContext.capture()

        // Check if we need to debounce (if called within debounce interval)
        if let lastTime = lastPersonalizationTime,
           Date().timeIntervalSince(lastTime) < debounceInterval {
            // Create debounced task — sleep on background, then rank off main
            personalizationTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }

                // Perform CPU-heavy ranking entirely off the main thread
                let ranked = await Task.detached(priority: .userInitiated) { [weak self] () -> [Post] in
                    guard let self else { return posts }
                    return self.rankPosts(posts,
                                         for: snapshotInterests,
                                         followingIds: snapshotFollowingIds,
                                         scoringContext: snapshotContext)
                }.value

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.followingIds = FollowService.shared.following
                    self.lastPersonalizationTime = Date()
                    self.personalizedPosts = ranked
                    #if DEBUG
                    dlog("🎯 [DEBOUNCED] Personalized \(ranked.count) posts")
                    #endif
                }
            }
        } else {
            // First call or outside debounce window — still rank off main thread
            lastPersonalizationTime = Date()
            personalizationTask = Task {
                let ranked = await Task.detached(priority: .userInitiated) { [weak self] () -> [Post] in
                    guard let self else { return posts }
                    return self.rankPosts(posts,
                                         for: snapshotInterests,
                                         followingIds: snapshotFollowingIds,
                                         scoringContext: snapshotContext)
                }.value

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.personalizedPosts = ranked
                    #if DEBUG
                    dlog("🎯 [IMMEDIATE] Personalized \(ranked.count) posts")
                    #endif
                }
            }
        }
    }
    
    // MARK: - Benefit-Optimized Scoring (FinalScore = ValueScore × TrustScore − HarmRisk − AddictionRisk)
    
    /// Compute the benefit-optimized final score for a post.
    /// Objective function: maximize benefit, not engagement.
    /// Does NOT train on watch time, rewatch, rage comments, or session length.
    nonisolated func benefitScore(_ post: Post, for interests: UserInterests) -> BenefitScoreResult {
        let value    = computeValueScore(post, interests: interests)
        let trust    = computeTrustScore(post, interests: interests)
        let harm     = computeHarmRisk(post)
        let addiction = computeAddictionRisk(post)
        
        // Hard constraints applied before combining
        let harmClamped     = min(harm, 1.0)
        let addictionClamped = min(addiction, 1.0)
        
        let combined = (value * trust) - harmClamped - addictionClamped
        let final = max(0.0, min(1.0, combined))
        
        return BenefitScoreResult(
            finalScore: final,
            valueScore: value,
            trustScore: trust,
            harmRisk: harmClamped,
            addictionRisk: addictionClamped
        )
    }
    
    struct BenefitScoreResult {
        let finalScore: Double     // 0.0–1.0 combined
        let valueScore: Double     // "does this help someone?"
        let trustScore: Double     // author reputation + community signals
        let harmRisk: Double       // toxicity/harassment/etc — subtract from score
        let addictionRisk: Double  // scroll-trap patterns — subtract from score
        
        /// Hard limits applied before ranking: if either threshold exceeded, post is demoted/held
        nonisolated var shouldDownrank: Bool  { harmRisk > 0.6 }
        nonisolated var shouldCapImpressions: Bool { addictionRisk > 0.5 }
    }
    
    // MARK: ValueScore — "Does this help someone?"
    
    /// Rates a post on its potential to encourage, teach, or move someone to action.
    /// Higher weight for: scripture, practical step, testimony, encouragement.
    /// Not influenced by: view time, rewatch, comment count, session length.
    nonisolated private func computeValueScore(_ post: Post, interests: UserInterests) -> Double {
        var score = 0.3 // Baseline: neutral post has some value
        
        let content = post.content.lowercased()
        
        // Encouragement signals
        let encouragementTerms = ["you are", "god loves", "you can", "hope", "strength", "grace",
                                   "peace", "blessed", "grateful", "thankful", "encouragement",
                                   "you've got this", "believe", "trust in god", "keep going"]
        let encouragementHits = encouragementTerms.filter { content.contains($0) }.count
        score += min(0.25, Double(encouragementHits) * 0.06)
        
        // Scripture/learning signals
        let scriptureTerms = ["verse", "scripture", "proverbs", "john", "psalm", "matthew",
                               "romans", "genesis", "corinthians", "gospel", "word of god",
                               "bible", "study", "devotional", "sermon", "lesson"]
        let scriptureHits = scriptureTerms.filter { content.contains($0) }.count
        score += min(0.25, Double(scriptureHits) * 0.06)
        
        // Practical step signals ("do this", "try this", actionable)
        let practicalTerms = ["step", "action", "try", "practice", "daily", "habit", "commit",
                               "challenge", "how to", "tip:", "start by", "this week"]
        let practicalHits = practicalTerms.filter { content.contains($0) }.count
        score += min(0.15, Double(practicalHits) * 0.05)
        
        // Category bonus
        switch post.category {
        case .prayer:     score += 0.10 // Prayer requests carry inherent value
        case .testimonies: score += 0.12 // Personal testimony is high value
        case .tip:        score += 0.08
        default: break
        }
        
        // Meaningful action signal: high lightbulb count = others found this valuable
        // This feeds ValueScore, not just TrustScore — content deemed worth saving is high-value content
        if post.lightbulbCount >= 5 {
            score += 0.12
        } else if post.lightbulbCount >= 2 {
            score += 0.06
        } else if post.lightbulbCount >= 1 {
            score += 0.03
        }
        
        // Goal alignment bonus (user-specific)
        let goalBonus = calculateGoalScore(post, interests: interests) / 100.0 * 0.10
        score += goalBonus
        
        return min(1.0, score)
    }
    
    // MARK: TrustScore — Author reputation + community signals + consistency
    
    /// Not raw engagement count — weighted by quality signals.
    /// Meaningful actions (saves/lightbulbs, reposts) outweigh fast-tap reactions.
    /// Penalizes accounts with high report rates or volatile engagement patterns.
    nonisolated private func computeTrustScore(_ post: Post, interests: UserInterests) -> Double {
        var score = 0.5 // Baseline: unknown author starts neutral
        
        // Author affinity from user's personal history
        let affinityRaw = calculateAuthorScore(post, interests: interests) / 100.0
        score += affinityRaw * 0.25
        
        // Meaningful-action signal: lightbulb = "this helped me", repost = worth sharing
        // These are deliberate, higher-friction actions — weighted 2× over fast-tap amen.
        let meaningfulActions = post.lightbulbCount + post.repostCount
        let fastTapActions = post.amenCount
        
        if meaningfulActions > 0 {
            // Lightbulb/repost signal: each meaningful action is worth ~0.04, capped at 0.20
            score += min(0.20, Double(meaningfulActions) * 0.04)
        }
        
        // Fast-tap reactions contribute less, and only when meaningful actions are also present
        // Pure amen-only posts get a small bump — prevents totally ignoring them
        if fastTapActions > 0 && meaningfulActions == 0 {
            score += min(0.05, Double(fastTapActions) * 0.005) // Modest signal, uncorroborated
        }
        
        // Quality ratio: saves relative to comments — saves = "worth keeping", comments can be debate
        if post.commentCount > 0 && post.lightbulbCount > 0 {
            let saveCommentRatio = Double(post.lightbulbCount) / Double(post.commentCount)
            if saveCommentRatio >= 1.0 {
                score += 0.12 // More saves than comments = strong content quality
            } else if saveCommentRatio >= 0.5 {
                score += 0.06
            }
        } else if post.commentCount > 0 {
            // Only comments, no saves — could be debate-driven, slight penalty
            let amenCommentRatio = Double(post.amenCount) / Double(post.commentCount)
            if amenCommentRatio < 0.5 {
                score -= 0.08 // High debate, low positive reaction
            }
        }
        
        // Consistency: if user has engaged with this author multiple times, trust is earned
        let authorEngagement = interests.engagedAuthors[post.authorId] ?? 0
        if authorEngagement >= 5 {
            score += 0.15
        } else if authorEngagement >= 2 {
            score += 0.08
        }
        
        return min(1.0, max(0.1, score)) // Floor at 0.1 — never zero-trust an unknown author
    }
    
    // MARK: HarmRisk — Toxicity, harassment, sexual, self-harm, extremism, manipulation
    
    /// Returns 0.0 (safe) – 1.0 (high harm). Computed independently.
    /// If > 0.6: post is downranked and queued for review.
    nonisolated private func computeHarmRisk(_ post: Post) -> Double {
        var risk = 0.0
        let content = post.content.lowercased()
        
        // Toxicity/hostility language
        let hostileTerms = ["you're wrong", "shut up", "idiot", "stupid", "moron",
                             "hate you", "you all are", "fake christian", "hypocrite",
                             "go to hell", "dumb", "ignorant people"]
        let hostileHits = hostileTerms.filter { content.contains($0) }.count
        risk += min(0.5, Double(hostileHits) * 0.15)
        
        // Self-harm language (must be caught early — not filtered, but flagged for care)
        let selfHarmTerms = ["want to die", "kill myself", "end it all", "no point living",
                              "suicide", "self harm", "cutting myself", "don't want to be here"]
        if selfHarmTerms.contains(where: { content.contains($0) }) {
            // Not a downrank — route to CrisisSupport instead (handled by ContentModerationService)
            // Here we only flag for feed ranking purposes
            risk += 0.3
        }
        
        // Manipulation/false urgency patterns
        let manipulationTerms = ["share or else", "god will punish", "you must share",
                                  "chain letter", "ignore this and", "proof that god",
                                  "scientific proof", "they don't want you to know"]
        let manipulationHits = manipulationTerms.filter { content.contains($0) }.count
        risk += min(0.4, Double(manipulationHits) * 0.20)
        
        // Existing controversy penalty feeds into harm risk
        let controversyContrib = calculateControversyPenalty(post) / 100.0 * 0.3
        risk += controversyContrib
        
        return min(1.0, risk)
    }
    
    // MARK: AddictionRisk — Scroll-trap patterns (cliffhanger, rage bait, thirst trap, engagement bait)
    
    /// Returns 0.0 (healthy) – 1.0 (high addiction risk). Computed independently.
    /// If > 0.5: impressions capped, removed from autoplay/infinite scroll contexts.
    nonisolated private func computeAddictionRisk(_ post: Post) -> Double {
        var risk = 0.0
        let content = post.content.lowercased()
        
        // Cliffhanger patterns ("wait till you see", "you won't believe", "part 2 coming")
        let cliffhangerTerms = ["wait till you see", "you won't believe", "stay tuned",
                                 "part 2", "to be continued", "i'll tell you later",
                                 "thread below", "comment below for", "link in bio"]
        let cliffHits = cliffhangerTerms.filter { content.contains($0) }.count
        risk += min(0.35, Double(cliffHits) * 0.12)
        
        // Rage bait ("controversial opinion:", "am I wrong?", "unpopular opinion")
        let rageBaitTerms = ["controversial opinion", "unpopular opinion", "am i wrong",
                              "fight me", "nobody talks about", "wake up", "they lied",
                              "the truth about", "everyone is wrong about"]
        let rageBaitHits = rageBaitTerms.filter { content.contains($0) }.count
        risk += min(0.35, Double(rageBaitHits) * 0.12)
        
        // Explicit engagement bait ("comment amen if", "like if you agree", "tag someone who")
        let engagementBaitTerms = ["comment amen if", "like if you agree", "tag someone",
                                    "repost if", "share if you", "drop an amen", "say amen",
                                    "type amen", "who agrees", "1 like = 1 prayer"]
        let engageBaitHits = engagementBaitTerms.filter { content.contains($0) }.count
        risk += min(0.40, Double(engageBaitHits) * 0.13)
        
        // ALL CAPS overuse (existing engagement bait check)
        if detectEngagementBait(post) { risk += 0.20 }
        
        return min(1.0, risk)
    }
    
    // MARK: - Topic Cluster Classification
    
    /// Lightweight topic cluster for diversity re-ranking.
    /// Posts are bucketed into one of these clusters to enforce distribution constraints.
    enum TopicCluster: String {
        case scripture      // Bible verses, study, devotional
        case prayer         // Prayer requests, intercession
        case testimony      // Personal faith stories
        case community      // Fellowship, church, relationships
        case practicalFaith // Tips, how-to, actionable faith steps
        case reflection     // Gratitude, journaling, introspection
        case discussion     // Open table general discussion, opinions
        case other
        
        /// "Grounding" clusters must appear at least once per session
        nonisolated var isGrounding: Bool {
            switch self {
            case .scripture, .prayer, .testimony, .practicalFaith: return true
            default: return false
            }
        }
    }
    
    /// Classify a post into a topic cluster using lightweight keyword heuristics.
    /// No ML inference at ranking time — runs synchronously per-post.
    nonisolated func topicCluster(for post: Post) -> TopicCluster {
        let content = post.content.lowercased()
        
        switch post.category {
        case .prayer:     return .prayer
        case .testimonies: return .testimony
        default: break
        }
        
        // Scripture cluster
        let scriptureKw = ["verse", "scripture", "proverbs", "psalm", "matthew", "john ", "romans",
                            "genesis", "corinthians", "acts ", "gospel", "bible", "study", "devotional"]
        if scriptureKw.contains(where: { content.contains($0) }) { return .scripture }
        
        // Practical faith cluster
        let practicalKw = ["how to", "step ", "tips", "habit", "daily practice", "try this",
                            "challenge yourself", "this week", "practical", "action"]
        if practicalKw.contains(where: { content.contains($0) }) { return .practicalFaith }
        
        // Reflection cluster
        let reflectionKw = ["grateful", "thankful", "reflecting", "journal", "pondering",
                             "sitting with", "peace", "stillness", "rest"]
        if reflectionKw.contains(where: { content.contains($0) }) { return .reflection }
        
        // Prayer cluster (even in openTable)
        let prayerKw = ["pray", "prayer", "intercede", "worship", "lord", "god, please", "father god"]
        if prayerKw.contains(where: { content.contains($0) }) { return .prayer }
        
        // Community cluster
        let communityKw = ["church", "fellowship", "community", "together", "gathering", "family of god"]
        if communityKw.contains(where: { content.contains($0) }) { return .community }
        
        // Testimony cluster
        let testimonyKw = ["testimony", "god did", "he saved me", "my story", "what god has done",
                            "transformed", "delivered", "miracle"]
        if testimonyKw.contains(where: { content.contains($0) }) { return .testimony }
        
        return .discussion
    }
    
    // MARK: - MMR-Style Diversity Re-Ranker
    
    /// Anti-rabbit-hole distribution: re-ranks a scored list using Maximal Marginal Relevance.
    /// Constraints enforced:
    ///   - Max 2 consecutive posts in the same topic cluster
    ///   - Max 40% of the final list from any single cluster
    ///   - At least 1 "grounding" post (scripture/prayer/testimony/practical) per 10-post window
    ///
    /// Pipeline: Candidate generation → Safety filter → Benefit score → MMR diversity → Final list
    nonisolated private func applyMMRDiversity(_ scored: [(post: Post, score: Double)]) -> [(post: Post, score: Double)] {
        guard scored.count > 3 else { return scored }
        
        let total = scored.count
        let maxClusterFraction = 0.40  // No single cluster > 40% of feed
        let maxClusterCap = max(2, Int(Double(total) * maxClusterFraction))
        let groundingWindowSize = 10   // At least 1 grounding post per N cards
        
        // Track cluster state
        var clusterCounts: [TopicCluster: Int] = [:]
        var result: [(post: Post, score: Double)] = []
        var deferred: [(post: Post, score: Double)] = []
        
        // Group posts by cluster for grounding injection
        var groundingPool: [(post: Post, score: Double)] = []
        var nonGrounding: [(post: Post, score: Double)] = []
        for item in scored {
            let cluster = topicCluster(for: item.post)
            if cluster.isGrounding {
                groundingPool.append(item)
            } else {
                nonGrounding.append(item)
            }
        }
        
        // Rebuild candidate list: interleave grounding posts naturally
        // Ratio: ~1 grounding per 4 posts to prevent echo chambers
        var candidates: [(post: Post, score: Double)] = []
        var gi = 0  // grounding index
        var ni = 0  // non-grounding index
        while gi < groundingPool.count || ni < nonGrounding.count {
            // Every 4th position (0-indexed): insert a grounding post if available
            let pos = candidates.count
            if pos % 4 == 3 && gi < groundingPool.count {
                candidates.append(groundingPool[gi]); gi += 1
            } else if ni < nonGrounding.count {
                candidates.append(nonGrounding[ni]); ni += 1
            } else if gi < groundingPool.count {
                candidates.append(groundingPool[gi]); gi += 1
            }
        }
        
        // MMR pass: enforce consecutive and session-cap constraints
        var consecutive = 0
        var lastCluster: TopicCluster? = nil
        var groundingInWindow = 0
        var windowStart = 0
        
        for item in candidates {
            let cluster = topicCluster(for: item.post)
            let clusterCount = clusterCounts[cluster, default: 0]
            
            // CONSTRAINT 1: Cluster session cap (no cluster > 40%)
            guard clusterCount < maxClusterCap else {
                deferred.append(item)
                continue
            }
            
            // CONSTRAINT 2: Max 2 consecutive in same cluster
            if cluster == lastCluster {
                consecutive += 1
                if consecutive >= 2 {
                    deferred.append(item)
                    continue
                }
            } else {
                consecutive = 0
            }
            
            // Accept this post
            result.append(item)
            clusterCounts[cluster, default: 0] += 1
            lastCluster = cluster
            if cluster.isGrounding { groundingInWindow += 1 }
            
            // CONSTRAINT 3: Grounding window — if we've placed 10 posts with no grounding,
            // immediately inject the best available grounding post next
            if result.count - windowStart >= groundingWindowSize {
                if groundingInWindow == 0 {
                    // Find the highest-scoring grounding post still in deferred or groundingPool
                    if let bestGrounding = deferred.enumerated()
                        .filter({ topicCluster(for: $0.element.post).isGrounding })
                        .max(by: { $0.element.score < $1.element.score }) {
                        result.append(bestGrounding.element)
                        deferred.remove(at: bestGrounding.offset)
                        clusterCounts[topicCluster(for: bestGrounding.element.post), default: 0] += 1
                    }
                }
                groundingInWindow = 0
                windowStart = result.count
            }
        }
        
        // Append deferred posts that couldn't be placed earlier (ensures nothing is lost)
        result.append(contentsOf: deferred)
        return result
    }
    
    // MARK: - Benefit-Ranked Feed
    
    /// Rank posts using the benefit-score model.
    /// Pipeline: Candidate generation → Safety filter → Benefit score → MMR diversity → Final list.
    /// Objective: benefit, not engagement. No watch-time or session-length signal.
    /// `nonisolated` so this can be called from `Task.detached` without main-thread blocking.
    nonisolated func benefitRankPosts(_ posts: [Post], for interests: UserInterests, followingIds: Set<String> = []) -> [Post] {
        // 1. Candidate generation + safety filtering
        let filtered = applyEthicalFilters(posts)
        
        // 2. Benefit scoring — independent models combined with hard constraints
        var scored: [(post: Post, result: BenefitScoreResult)] = filtered.map { post in
            (post: post, result: benefitScore(post, for: interests))
        }
        
        // 3. Hard constraint sort (harm/addiction risk posts move to end)
        scored.sort {
            if $0.result.shouldDownrank != $1.result.shouldDownrank { return !$0.result.shouldDownrank }
            if $0.result.shouldCapImpressions != $1.result.shouldCapImpressions { return !$0.result.shouldCapImpressions }
            return $0.result.finalScore > $1.result.finalScore
        }
        
        // 4. Blend with recency + follow bonus before diversity pass
        let withRecency = scored.map { item -> (post: Post, score: Double) in
            let hoursSince = Date().timeIntervalSince(item.post.createdAt) / 3600
            let recencyBonus = hoursSince < 2 ? 0.08 : (hoursSince < 6 ? 0.04 : 0.0)
            let followBonus = followingIds.contains(item.post.authorId) ? 0.06 : 0.0
            return (item.post, item.result.finalScore + recencyBonus + followBonus)
        }.sorted { $0.score > $1.score }
        
        // 5. MMR-style diversity re-ranking (anti-rabbit-hole constraints)
        let diversified = applyMMRDiversity(withRecency)
        
        // 6. Author diversity (no same author back-to-back)
        let authorDiversified = applyAuthorDiversity(diversified)
        
        return authorDiversified.map { $0.post }
    }
    
    // MARK: - Smart Refresh
    
    /// Determine if feed should refresh based on user behavior
    func shouldRefreshFeed() -> Bool {
        // Refresh if interests are stale
        if userInterests.isStale {
            return true
        }
        
        // Refresh if significant new interactions (every 10 interactions)
        if userInterests.interactionHistory.values.reduce(0, +) % 10 == 0 {
            return true
        }
        
        return false
    }
    
    // MARK: - Topic Discovery
    
    // MARK: - HeyFeed Integration Helpers
    
    /// Map Post category to HeyFeed topic
    nonisolated private func mapCategoryToTopic(_ category: Post.PostCategory) -> FeedTopic {
        switch category {
        case .prayer:
            return .faith
        case .testimonies:
            return .faith
        case .tip:
            return .faith  // Tips on AMEN are faith/ministry-focused by platform design
        case .funFact:
            return .faith  // Fun facts here are Bible/theology facts
        case .openTable:
            // OpenTable is general community discussion — if topicTag is available use that;
            // default to .faith since this is a faith platform.
            return .faith
        }
    }
    
    /// Suggest new topics based on engagement patterns
    func discoverNewTopics(from allTopics: [String]) -> [String] {
        let engagedTopics = Set(userInterests.engagedTopics.keys)
        let unexplored = allTopics.filter { !engagedTopics.contains($0) }
        
        // Return 3-5 random unexplored topics for discovery
        return Array(unexplored.shuffled().prefix(Int.random(in: 3...5)))
    }
}

// MARK: - Feed Session Manager (Finite Sessions)

/// Manages finite feed sessions: N cards per session, then a deliberate stop.
/// Feed delivery is chunked — continuing scrolling requires an explicit tap.
/// Server and client both enforce the cap to prevent bypass.
@MainActor
class FeedSessionManager: ObservableObject {
    static let shared = FeedSessionManager()
    
    // MARK: - Session Config
    
    /// Cards shown per session before the Stop Screen is presented.
    /// User-configurable; default 25. Range: 10–50.
    static let defaultSessionCap = 25
    
    @Published var sessionCap: Int = defaultSessionCap
    @Published var cardsSeenThisSession: Int = 0
    @Published var sessionId: String = UUID().uuidString
    @Published var isSessionComplete: Bool = false
    @Published var sessionExtensionsUsed: Int = 0
    
    /// Remaining cards before Stop Screen (server would echo this in `session_cap_remaining`)
    var sessionCapRemaining: Int {
        max(0, sessionCap - cardsSeenThisSession)
    }
    
    var sessionProgress: Double {
        guard sessionCap > 0 else { return 0 }
        return min(1.0, Double(cardsSeenThisSession) / Double(sessionCap))
    }
    
    // MARK: - Session Control
    
    func recordCardSeen() {
        cardsSeenThisSession += 1
        if cardsSeenThisSession >= sessionCap {
            isSessionComplete = true
        }
    }
    
    /// User deliberately chose to continue — start a new batch with a fresh session.
    /// Each extension is tracked (max 2 per sitting to discourage compulsive use).
    func extendSession() {
        guard sessionExtensionsUsed < 2 else { return } // hard cap: 2 extensions per sitting
        sessionExtensionsUsed += 1
        cardsSeenThisSession = 0
        sessionId = UUID().uuidString
        isSessionComplete = false
    }
    
    func startNewSession() {
        cardsSeenThisSession = 0
        sessionId = UUID().uuidString
        isSessionComplete = false
        sessionExtensionsUsed = 0
    }
    
    /// Called when user closes the Stop Screen without extending (they're done).
    func endSession() {
        startNewSession()
    }
    
    private init() {}
}

// MARK: - Post Extension for Tracking

extension Post {
    /// Check if user has interacted with this post
    func hasUserInteracted(interests: HomeFeedAlgorithm.UserInterests) -> Bool {
        let key = firebaseId ?? id.uuidString
        return interests.interactionHistory[key] != nil
    }
    
    /// Get interaction count for this post
    func userInteractionCount(interests: HomeFeedAlgorithm.UserInterests) -> Int {
        let key = firebaseId ?? id.uuidString
        return interests.interactionHistory[key] ?? 0
    }
}
