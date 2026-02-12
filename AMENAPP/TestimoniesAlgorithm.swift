//
//  TestimoniesAlgorithm.swift
//  AMENAPP
//
//  Created by AI Assistant on 2/11/26.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Testimonies Feed Personalization Algorithm

/// Intelligent feed ranking algorithm for testimonies
/// Emphasizes inspirational content, community relevance, and diversity
@MainActor
class TestimoniesAlgorithm: ObservableObject {
    static let shared = TestimoniesAlgorithm()

    @Published var personalizedTestimonies: [Post] = []
    @Published var userPreferences = TestimonyPreferences()

    // MARK: - Testimony Preferences Model

    struct TestimonyPreferences: Codable {
        var engagedCategories: [String: Double] = [:]  // Category → Interest (0-100)
        var engagedAuthors: [String: Int] = [:]        // AuthorID → Engagement count
        var interactionHistory: [String: Int] = [:]    // PostID → Interactions
        var favoriteTestimonyTypes: [String: Double] = [:] // Type → Preference
        var lastUpdate: Date = Date()

        var isStale: Bool {
            Date().timeIntervalSince(lastUpdate) > 86400 // 24 hours
        }
    }

    // MARK: - Post Scoring

    /// Score a testimony for personalized relevance (0-100)
    func scoreTestimony(_ post: Post, for preferences: TestimonyPreferences) -> Double {
        var score: Double = 0.0

        // 1. Inspirational Impact (30%) - Content quality and engagement
        score += calculateInspirationalScore(post) * 0.30

        // 2. Recency Boost (20%) - Recent testimonies
        score += calculateRecencyScore(post) * 0.20

        // 3. Category Relevance (20%) - User's interests
        score += calculateCategoryScore(post, preferences: preferences) * 0.20

        // 4. Author Affinity (15%) - Users they engage with
        score += calculateAuthorScore(post, preferences: preferences) * 0.15

        // 5. Diversity Factor (15%) - Prevent echo chamber
        score += calculateDiversityScore(post, preferences: preferences) * 0.15

        return min(100, max(0, score))
    }

    // MARK: - Inspirational Impact

    private func calculateInspirationalScore(_ post: Post) -> Double {
        // Weight reactions more heavily for testimonies
        let amenWeight = Double(post.amenCount) * 2.5  // "Amen" reactions are highly meaningful
        let commentWeight = Double(post.commentCount) * 3.0  // Comments show deep engagement
        let lightbulbWeight = Double(post.lightbulbCount) * 1.5  // Insights

        let totalImpact = amenWeight + commentWeight + lightbulbWeight

        // Logarithmic scaling for fair distribution
        if totalImpact < 5 {
            return 30 // New testimony
        } else if totalImpact < 15 {
            return 50 // Moderate impact
        } else if totalImpact < 40 {
            return 70 // Good impact
        } else if totalImpact < 80 {
            return 85 // High impact
        } else {
            return min(100, 85 + log(totalImpact - 80) * 3)
        }
    }

    // MARK: - Recency Scoring

    private func calculateRecencyScore(_ post: Post) -> Double {
        let now = Date()
        let hoursSincePost = now.timeIntervalSince(post.createdAt) / 3600

        // Testimonies stay relevant longer than news
        if hoursSincePost < 6 {
            return 100 // Very recent
        } else if hoursSincePost < 24 {
            return 85 // Recent
        } else if hoursSincePost < 72 {
            return 65 // This week
        } else if hoursSincePost < 168 { // 7 days
            return 45 // This week
        } else {
            return max(20, 45 - (hoursSincePost - 168) / 24 * 3) // Gradual decay
        }
    }

    // MARK: - Category Relevance

    private func calculateCategoryScore(_ post: Post, preferences: TestimonyPreferences) -> Double {
        var categoryScore: Double = 50 // Baseline neutral

        // Check category preference
        if let topicTag = post.topicTag,
           let preference = preferences.engagedCategories[topicTag] {
            categoryScore = preference
        }

        // Check content keywords
        let contentWords = Set(post.content.lowercased().split(separator: " ").map(String.init))
        let matchedCategories = preferences.engagedCategories.filter { category, score in
            contentWords.contains(category.lowercased())
        }

        if !matchedCategories.isEmpty {
            let avgMatch = matchedCategories.values.reduce(0, +) / Double(matchedCategories.count)
            categoryScore = max(categoryScore, avgMatch)
        }

        return categoryScore
    }

    // MARK: - Author Affinity

    private func calculateAuthorScore(_ post: Post, preferences: TestimonyPreferences) -> Double {
        guard let engagementCount = preferences.engagedAuthors[post.authorId] else {
            return 30 // New author
        }

        // More engagement = higher score
        let rawScore = min(100, 30 + (log(Double(engagementCount) + 1) * 25))
        return rawScore
    }

    // MARK: - Diversity Scoring

    private func calculateDiversityScore(_ post: Post, preferences: TestimonyPreferences) -> Double {
        // Reward testimonies from categories user hasn't engaged with
        let categoryEngagement = preferences.engagedCategories[post.topicTag ?? ""] ?? 0

        if categoryEngagement < 20 {
            return 80 // High diversity bonus
        } else if categoryEngagement < 50 {
            return 55 // Moderate diversity
        } else {
            return 25 // Low diversity
        }
    }

    // MARK: - Feed Ranking

    /// Rank testimonies using personalized algorithm
    func rankTestimonies(_ posts: [Post], for preferences: TestimonyPreferences) -> [Post] {
        let scoredPosts = posts.map { post in
            (post: post, score: scoreTestimony(post, for: preferences))
        }

        return scoredPosts
            .sorted { $0.score > $1.score }
            .map { $0.post }
    }

    // MARK: - Interaction Learning

    /// Update preferences based on interaction
    func recordInteraction(with post: Post, type: InteractionType) {
        // Update category preferences
        if let category = post.topicTag {
            let currentScore = userPreferences.engagedCategories[category] ?? 50
            let boost = type.scoreBoost
            userPreferences.engagedCategories[category] = min(100, currentScore + boost)
        }

        // Update author affinity
        userPreferences.engagedAuthors[post.authorId, default: 0] += type.weight

        // Record interaction
        userPreferences.interactionHistory[post.id.uuidString, default: 0] += 1

        // Update timestamp
        userPreferences.lastUpdate = Date()

        // Persist
        savePreferences()

        #if DEBUG
        print("📊 Testimony preference updated: Category=\(post.topicTag ?? "none") +\(type.scoreBoost)")
        #endif
    }

    enum InteractionType {
        case view
        case amen
        case comment
        case share
        case longRead

        var scoreBoost: Double {
            switch self {
            case .view: return 1
            case .amen: return 8  // Amen is highly meaningful for testimonies
            case .comment: return 12
            case .share: return 15
            case .longRead: return 10
            }
        }

        var weight: Int {
            switch self {
            case .view: return 1
            case .amen: return 3
            case .comment: return 4
            case .share: return 5
            case .longRead: return 2
            }
        }
    }

    // MARK: - Persistence

    private func savePreferences() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(userPreferences)
            UserDefaults.standard.set(data, forKey: "testimonyPreferences_v1")
        } catch {
            print("❌ Failed to save testimony preferences: \(error)")
        }
    }

    func loadPreferences() {
        guard let data = UserDefaults.standard.data(forKey: "testimonyPreferences_v1") else {
            print("ℹ️ No saved testimony preferences found")
            return
        }

        do {
            let decoder = JSONDecoder()
            userPreferences = try decoder.decode(TestimonyPreferences.self, from: data)
            print("✅ Loaded testimony preferences: \(userPreferences.engagedCategories.count) categories")
        } catch {
            print("❌ Failed to load testimony preferences: \(error)")
        }
    }

    // MARK: - Smart Refresh

    func shouldRefreshFeed() -> Bool {
        return userPreferences.isStale ||
               userPreferences.interactionHistory.values.reduce(0, +) % 10 == 0
    }
}

// MARK: - Post Extension

extension Post {
    func hasUserInteractedWithTestimony(preferences: TestimoniesAlgorithm.TestimonyPreferences) -> Bool {
        return preferences.interactionHistory[id.uuidString] != nil
    }
}
