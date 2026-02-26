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
    
    // MARK: - Post Scoring
    
    /// Score a post for personalized relevance (0-100)
    func scorePost(_ post: Post, for interests: UserInterests, followingIds: Set<String> = []) -> Double {
        var score: Double = 0.0
        
        // 1. Recency Score (18%) - Newer is better
        score += calculateRecencyScore(post) * 0.18
        
        // 2. Following Relationship (23%) - Prioritize people you follow
        score += calculateFollowingScore(post, followingIds: followingIds) * 0.23
        
        // 3. Topic Relevance (18%) - User's interests
        score += calculateTopicScore(post, interests: interests) * 0.18
        
        // 4. Goal Alignment (12%) - User's spiritual goals
        score += calculateGoalScore(post, interests: interests) * 0.12
        
        // 5. Author Affinity (9%) - Users they engage with
        score += calculateAuthorScore(post, interests: interests) * 0.09
        
        // 6. Engagement Quality (12%) - Community validation
        score += calculateEngagementScore(post) * 0.12
        
        // 7. Diversity Bonus (8%) - Prevent echo chamber
        score += calculateDiversityScore(post, interests: interests) * 0.08
        
        // 8. Category Boost - Special boost for Tips and Fun Facts
        score += calculateCategoryBoost(post, interests: interests)
        
        return min(100, max(0, score))
    }
    
    // MARK: - Following Relationship Score
    
    /// Boost posts from people user follows (relationship strength)
    private func calculateFollowingScore(_ post: Post, followingIds: Set<String>) -> Double {
        if followingIds.contains(post.authorId) {
            return 90  // High priority for followed accounts
        } else {
            return 30  // Neutral for discovery
        }
    }
    
    // MARK: - Category Boost
    
    /// Give special boost to Tip and Fun Fact posts to help them surface
    private func calculateCategoryBoost(_ post: Post, interests: UserInterests) -> Double {
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
    
    private func calculateRecencyScore(_ post: Post) -> Double {
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
    
    private func calculateTopicScore(_ post: Post, interests: UserInterests) -> Double {
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
    private func calculateGoalScore(_ post: Post, interests: UserInterests) -> Double {
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
    
    private func calculateAuthorScore(_ post: Post, interests: UserInterests) -> Double {
        guard let engagementCount = interests.engagedAuthors[post.authorId] else {
            return 30 // New author - neutral score
        }
        
        // More engagements with author = higher score
        // Cap at 100, scale logarithmically to prevent extreme scores
        let rawScore = min(100, 30 + (log(Double(engagementCount) + 1) * 20))
        return rawScore
    }
    
    // MARK: - Engagement Quality Scoring
    
    private func calculateEngagementScore(_ post: Post) -> Double {
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
    
    private func calculateDiversityScore(_ post: Post, interests: UserInterests) -> Double {
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
    
    // MARK: - Feed Ranking
    
    /// Rank posts using personalized algorithm with ethical safeguards
    func rankPosts(_ posts: [Post], for interests: UserInterests, followingIds: Set<String> = []) -> [Post] {
        // 1. Filter spam and low-quality content FIRST
        let filteredPosts = applyEthicalFilters(posts)
        
        // 2. Score remaining posts (with following relationship)
        let scoredPosts = filteredPosts.map { post in
            (post: post, score: scorePost(post, for: interests, followingIds: followingIds))
        }
        
        // 3. Sort by score
        let sorted = scoredPosts.sorted { $0.score > $1.score }
        
        // 4. Apply author diversity (prevent same author dominating feed)
        let diversified = applyAuthorDiversity(sorted)
        
        return diversified.map { $0.post }
    }
    
    // MARK: - Ethical Safeguards
    
    /// Filter out spam, duplicates, and low-quality content
    private func applyEthicalFilters(_ posts: [Post]) -> [Post] {
        var seen = Set<String>()
        var authorPostCount: [String: Int] = [:]
        
        return posts.filter { post in
            // Filter 1: No duplicate/near-duplicate content
            let contentHash = post.content.lowercased().prefix(50)
            guard !seen.contains(String(contentHash)) else {
                print("🚫 [SPAM FILTER] Duplicate content blocked")
                return false
            }
            seen.insert(String(contentHash))
            
            // Filter 2: Limit posts per author (no flooding)
            let count = authorPostCount[post.authorId, default: 0]
            guard count < 10 else {
                print("🚫 [SPAM FILTER] Author \(post.authorId) flooding blocked")
                return false
            }
            authorPostCount[post.authorId] = count + 1
            
            // Filter 3: Engagement bait detection (all caps, excessive emoji)
            let hasEngagementBait = detectEngagementBait(post)
            if hasEngagementBait {
                print("🚫 [ENGAGEMENT BAIT] Post filtered")
                return false
            }
            
            return true
        }
    }
    
    /// Detect engagement bait patterns
    private func detectEngagementBait(_ post: Post) -> Bool {
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
    private func applyAuthorDiversity(_ scoredPosts: [(post: Post, score: Double)]) -> [(post: Post, score: Double)] {
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
        
        // Record interaction - convert UUID to String
        userInterests.interactionHistory[post.id.uuidString, default: 0] += 1
        
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
            print("❌ Failed to save user interests: \(error)")
        }
    }
    
    func loadInterests() {
        guard let data = UserDefaults.standard.data(forKey: "userInterests_v1") else {
            print("ℹ️ No saved interests found")
            // Still try to load goals from Firestore
            Task { await loadGoalsFromFirestore() }
            return
        }
        
        do {
            let decoder = JSONDecoder()
            userInterests = try decoder.decode(UserInterests.self, from: data)
            print("✅ Loaded user interests: \(userInterests.engagedTopics.count) topics, \(userInterests.engagedAuthors.count) authors")
            
            // Also load goals from Firestore to ensure they're up to date
            Task { await loadGoalsFromFirestore() }
        } catch {
            print("❌ Failed to load interests: \(error)")
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
                    print("✅ Loaded \(goals.count) goals from Firestore: \(goals.joined(separator: ", "))")
                    
                    // Save updated interests
                    saveInterests()
                }
            }
        } catch {
            print("❌ Failed to load goals from Firestore: \(error)")
        }
    }
    
    // MARK: - Debounced Personalization (P1-3 Performance Fix)
    
    private var personalizationTask: Task<Void, Never>?
    private var lastPersonalizationTime: Date?
    private let debounceInterval: TimeInterval = 0.3  // 300ms debounce
    
    /// Debounced personalization - prevents excessive re-ranking during rapid updates
    func personalizePostsDebounced(_ posts: [Post]) {
        // Cancel any pending personalization task
        personalizationTask?.cancel()
        
        // Check if we need to debounce (if called within debounce interval)
        if let lastTime = lastPersonalizationTime,
           Date().timeIntervalSince(lastTime) < debounceInterval {
            // Create debounced task
            personalizationTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
                
                // Only proceed if not cancelled
                guard !Task.isCancelled else { return }
                
                self.lastPersonalizationTime = Date()
                self.personalizedPosts = self.rankPosts(posts, for: self.userInterests)
                
                #if DEBUG
                print("🎯 [DEBOUNCED] Personalized \(posts.count) posts")
                #endif
            }
        } else {
            // First call or outside debounce window - execute immediately
            lastPersonalizationTime = Date()
            personalizedPosts = rankPosts(posts, for: userInterests)
            
            #if DEBUG
            print("🎯 [IMMEDIATE] Personalized \(posts.count) posts")
            #endif
        }
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
    
    /// Suggest new topics based on engagement patterns
    func discoverNewTopics(from allTopics: [String]) -> [String] {
        let engagedTopics = Set(userInterests.engagedTopics.keys)
        let unexplored = allTopics.filter { !engagedTopics.contains($0) }
        
        // Return 3-5 random unexplored topics for discovery
        return Array(unexplored.shuffled().prefix(Int.random(in: 3...5)))
    }
}

// MARK: - Post Extension for Tracking

extension Post {
    /// Check if user has interacted with this post
    func hasUserInteracted(interests: HomeFeedAlgorithm.UserInterests) -> Bool {
        return interests.interactionHistory[id.uuidString] != nil
    }
    
    /// Get interaction count for this post
    func userInteractionCount(interests: HomeFeedAlgorithm.UserInterests) -> Int {
        return interests.interactionHistory[id.uuidString] ?? 0
    }
}
