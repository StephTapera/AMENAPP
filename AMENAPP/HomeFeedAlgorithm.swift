//
//  HomeFeedAlgorithm.swift
//  AMENAPP
//
//  Created by AI Assistant on 2/2/26.
//

import Foundation
import SwiftUI

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
        var lastUpdate: Date = Date()
        
        // Time decay factor
        var isStale: Bool {
            Date().timeIntervalSince(lastUpdate) > 86400 // 24 hours
        }
    }
    
    // MARK: - Post Scoring
    
    /// Score a post for personalized relevance (0-100)
    func scorePost(_ post: Post, for interests: UserInterests) -> Double {
        var score: Double = 0.0
        
        // 1. Recency Score (25%) - Newer is better
        score += calculateRecencyScore(post) * 0.25
        
        // 2. Topic Relevance (30%) - User's interests
        score += calculateTopicScore(post, interests: interests) * 0.30
        
        // 3. Author Affinity (15%) - Users they engage with
        score += calculateAuthorScore(post, interests: interests) * 0.15
        
        // 4. Engagement Quality (20%) - Community validation
        score += calculateEngagementScore(post) * 0.20
        
        // 5. Diversity Bonus (10%) - Prevent echo chamber
        score += calculateDiversityScore(post, interests: interests) * 0.10
        
        return min(100, max(0, score))
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
        // Weighted engagement: comments > reactions > views
        let commentWeight = Double(post.commentCount) * 3.0
        let reactionWeight = Double(post.amenCount) * 1.5
        let viewWeight = Double(post.viewCount) * 0.5
        
        let totalEngagement = commentWeight + reactionWeight + viewWeight
        
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
    
    /// Rank posts using personalized algorithm
    func rankPosts(_ posts: [Post], for interests: UserInterests) -> [Post] {
        let scoredPosts = posts.map { post in
            (post: post, score: scorePost(post, for: interests))
        }
        
        return scoredPosts
            .sorted { $0.score > $1.score }
            .map { $0.post }
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
        
        // Record interaction
        userInterests.interactionHistory[post.id, default: 0] += 1
        
        // Update timestamp
        userInterests.lastUpdate = Date()
        
        // Persist
        saveInterests()
        
        print("📊 Interest updated: Topic=\(post.topicTag ?? "none") +\(type.scoreBoost), Author +\(type.weight)")
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
            return
        }
        
        do {
            let decoder = JSONDecoder()
            userInterests = try decoder.decode(UserInterests.self, from: data)
            print("✅ Loaded user interests: \(userInterests.engagedTopics.count) topics, \(userInterests.engagedAuthors.count) authors")
        } catch {
            print("❌ Failed to load interests: \(error)")
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
        return interests.interactionHistory[id] != nil
    }
    
    /// Get interaction count for this post
    func userInteractionCount(interests: HomeFeedAlgorithm.UserInterests) -> Int {
        return interests.interactionHistory[id] ?? 0
    }
}
