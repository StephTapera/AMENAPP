//
//  PrayerAlgorithm.swift
//  AMENAPP
//
//  Created by AI Assistant on 2/11/26.
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth

// MARK: - Prayer Feed Personalization Algorithm

/// Intelligent feed ranking algorithm for prayer requests
/// Emphasizes urgency, community relevance, and prayer coverage gaps
@MainActor
class PrayerAlgorithm: ObservableObject {
    static let shared = PrayerAlgorithm()

    @Published var personalizedPrayers: [Post] = []
    @Published var userPrayerHistory = PrayerHistory()

    // MARK: - Prayer History Model

    struct PrayerHistory: Codable {
        var prayedForAuthors: [String: Int] = [:]      // AuthorID → Prayer count
        var prayerTopics: [String: Double] = [:]       // Topic → Interest (0-100)
        var prayerInteractions: [String: Int] = [:]    // PostID → Prayer count
        var recentPrayers: [String] = []               // Recent prayer IDs (last 50)
        var lastUpdate: Date = Date()

        var isStale: Bool {
            Date().timeIntervalSince(lastUpdate) > 86400 // 24 hours
        }
    }

    // MARK: - Post Scoring

    /// Score a prayer request for personalized relevance (0-100)
    func scorePrayer(_ post: Post, for history: PrayerHistory) -> Double {
        var score: Double = 0.0

        // 1. Urgency (35%) - Time-sensitive prayers need attention
        score += calculateUrgencyScore(post) * 0.35

        // 2. Prayer Gap (25%) - Prayers with few responses
        score += calculatePrayerGapScore(post) * 0.25

        // 3. Community Relevance (20%) - Connection to user
        score += calculateCommunityScore(post, history: history) * 0.20

        // 4. Topic Relevance (10%) - Prayer topics user cares about
        score += calculateTopicScore(post, history: history) * 0.10

        // 5. Recency (10%) - Recent prayers
        score += calculateRecencyScore(post) * 0.10

        return min(100, max(0, score))
    }

    // MARK: - Urgency Scoring

    private func calculateUrgencyScore(_ post: Post) -> Double {
        let now = Date()
        let hoursSincePost = now.timeIntervalSince(post.createdAt) / 3600

        // Check for urgency keywords in content
        let urgentKeywords = ["urgent", "emergency", "critical", "help", "hospital", "surgery", "crisis"]
        let hasUrgentKeyword = urgentKeywords.contains { keyword in
            post.content.lowercased().contains(keyword)
        }

        // Emergency prayers get immediate priority
        if hasUrgentKeyword {
            return 100
        }

        // Recent prayers (< 24 hours) are urgent
        if hoursSincePost < 24 {
            return 85
        }

        // Prayers 1-3 days old still need attention
        if hoursSincePost < 72 {
            return 65
        }

        // Prayers 3-7 days old - moderate urgency
        if hoursSincePost < 168 {
            return 45
        }

        // Older prayers resurface periodically (prevent abandonment)
        if hoursSincePost < 336 { // 14 days
            return 30
        }

        return 20
    }

    // MARK: - Prayer Gap Scoring

    private func calculatePrayerGapScore(_ post: Post) -> Double {
        // "Amen" count represents prayers
        let prayerCount = post.amenCount

        // Prayers with no responses need urgent attention
        if prayerCount == 0 {
            return 100 // No one has prayed yet!
        }

        // Few prayers - needs more coverage
        if prayerCount < 3 {
            return 85
        }

        // Some prayers but could use more
        if prayerCount < 10 {
            return 60
        }

        // Well-covered prayers
        if prayerCount < 20 {
            return 40
        }

        // Highly prayed-for (reduce frequency)
        return 20
    }

    // MARK: - Community Relevance Scoring

    private func calculateCommunityScore(_ post: Post, history: PrayerHistory) -> Double {
        var communityScore: Double = 30 // Baseline

        // 1. Author Affinity - Have we prayed for this person before?
        if let prayerCount = history.prayedForAuthors[post.authorId] {
            // Boost prayers from people we've helped before
            communityScore += min(40, Double(prayerCount) * 8)
        }

        // 2. New Requester Bonus - First-time prayer requests get attention
        if history.prayedForAuthors[post.authorId] == nil {
            communityScore += 20 // Welcome new members
        }

        // 3. Mutual Connection (if following system exists)
        // TODO: Check if user follows this author
        // if UserService.shared.isFollowing(post.authorId) {
        //     communityScore += 15
        // }

        return min(100, communityScore)
    }

    // MARK: - Topic Relevance Scoring

    private func calculateTopicScore(_ post: Post, history: PrayerHistory) -> Double {
        guard let topic = post.topicTag else { return 50 }

        // Check if user has prayed for this topic before
        if let topicInterest = history.prayerTopics[topic] {
            return topicInterest
        }

        // Default neutral score for new topics
        return 50
    }

    // MARK: - Recency Scoring

    private func calculateRecencyScore(_ post: Post) -> Double {
        let now = Date()
        let hoursSincePost = now.timeIntervalSince(post.createdAt) / 3600

        if hoursSincePost < 6 {
            return 100 // Very recent
        } else if hoursSincePost < 24 {
            return 80
        } else if hoursSincePost < 72 {
            return 60
        } else if hoursSincePost < 168 {
            return 40
        } else {
            return 20
        }
    }

    // MARK: - Feed Ranking

    /// Rank prayers using personalized algorithm
    func rankPrayers(_ posts: [Post], for history: PrayerHistory) -> [Post] {
        let scoredPosts = posts.map { post in
            (post: post, score: scorePrayer(post, for: history))
        }

        return scoredPosts
            .sorted { $0.score > $1.score }
            .map { $0.post }
    }

    // MARK: - Interaction Learning

    /// Update history when user prays for someone
    func recordPrayer(for post: Post) {
        // Update author prayer count
        userPrayerHistory.prayedForAuthors[post.authorId, default: 0] += 1

        // Update topic interest
        if let topic = post.topicTag {
            let currentScore = userPrayerHistory.prayerTopics[topic] ?? 50
            userPrayerHistory.prayerTopics[topic] = min(100, currentScore + 10)
        }

        // Record prayer interaction
        userPrayerHistory.prayerInteractions[post.id.uuidString, default: 0] += 1

        // Add to recent prayers (keep last 50)
        userPrayerHistory.recentPrayers.append(post.id.uuidString)
        if userPrayerHistory.recentPrayers.count > 50 {
            userPrayerHistory.recentPrayers.removeFirst()
        }

        // Update timestamp
        userPrayerHistory.lastUpdate = Date()

        // Persist
        saveHistory()

        #if DEBUG
        print("🙏 Prayer recorded: Author=\(post.authorId), Topic=\(post.topicTag ?? "none")")
        #endif
    }

    /// Record view interaction
    func recordView(for post: Post) {
        // Light tracking for views (doesn't boost as much as prayer)
        if let topic = post.topicTag {
            let currentScore = userPrayerHistory.prayerTopics[topic] ?? 50
            userPrayerHistory.prayerTopics[topic] = min(100, currentScore + 1)
        }

        userPrayerHistory.lastUpdate = Date()
        saveHistory()
    }

    /// Record comment interaction
    func recordComment(for post: Post) {
        // Comments on prayers show engagement
        userPrayerHistory.prayedForAuthors[post.authorId, default: 0] += 1

        if let topic = post.topicTag {
            let currentScore = userPrayerHistory.prayerTopics[topic] ?? 50
            userPrayerHistory.prayerTopics[topic] = min(100, currentScore + 5)
        }

        userPrayerHistory.lastUpdate = Date()
        saveHistory()
    }

    // MARK: - Persistence

    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(userPrayerHistory)
            UserDefaults.standard.set(data, forKey: "prayerHistory_v1")
        } catch {
            print("❌ Failed to save prayer history: \(error)")
        }
    }

    func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "prayerHistory_v1") else {
            print("ℹ️ No saved prayer history found")
            return
        }

        do {
            let decoder = JSONDecoder()
            userPrayerHistory = try decoder.decode(PrayerHistory.self, from: data)
            print("✅ Loaded prayer history: \(userPrayerHistory.prayedForAuthors.count) people prayed for")
        } catch {
            print("❌ Failed to load prayer history: \(error)")
        }
    }

    // MARK: - Smart Refresh

    func shouldRefreshFeed() -> Bool {
        return userPrayerHistory.isStale ||
               userPrayerHistory.prayerInteractions.values.reduce(0, +) % 5 == 0
    }

    // MARK: - Helper Methods

    /// Check if user has prayed for this request
    func hasPrayedFor(_ post: Post) -> Bool {
        return userPrayerHistory.prayerInteractions[post.id.uuidString] != nil
    }

    /// Get prayer count for author
    func getPrayerCountForAuthor(_ authorId: String) -> Int {
        return userPrayerHistory.prayedForAuthors[authorId] ?? 0
    }
}

// MARK: - Post Extension

extension Post {
    func hasPrayerFromUser(history: PrayerAlgorithm.PrayerHistory) -> Bool {
        return history.prayerInteractions[id.uuidString] != nil
    }

    var isUrgentPrayer: Bool {
        let urgentKeywords = ["urgent", "emergency", "critical", "help", "hospital", "surgery", "crisis"]
        return urgentKeywords.contains { keyword in
            content.lowercased().contains(keyword)
        }
    }
}
