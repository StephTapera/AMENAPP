//
//  TrendingService.swift
//  AMENAPP
//
//  Service for Top Ideas (trending posts) and Spotlight (featured users)
//

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Top Idea Model

struct TopIdea: Identifiable {
    let id: String // Firebase post ID
    let rank: Int
    let authorId: String
    let authorName: String
    let authorUsername: String?
    let authorProfileImageURL: String?
    let timeAgo: String
    let content: String
    let lightbulbCount: Int
    let commentCount: Int
    let amenCount: Int
    let category: IdeaCategory
    let badges: [String]
    let trendingScore: Double
    let createdAt: Date
    
    enum IdeaCategory: String, CaseIterable {
        case all = "All Ideas"
        case ai = "AI & Tech"
        case ministry = "Ministry"
        case business = "Business"
        case creative = "Creative"
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .ai: return "brain.head.profile"
            case .ministry: return "hands.sparkles"
            case .business: return "briefcase"
            case .creative: return "paintbrush"
            }
        }
        
        var color: Color {
            switch self {
            case .all: return .gray
            case .ai: return .blue
            case .ministry: return .purple
            case .business: return .green
            case .creative: return .orange
            }
        }
        
        // Map to topic tags
        static func fromTopicTag(_ tag: String) -> IdeaCategory {
            let lowercased = tag.lowercased()
            if lowercased.contains("ai") || lowercased.contains("tech") || lowercased.contains("technology") {
                return .ai
            } else if lowercased.contains("ministry") || lowercased.contains("church") || lowercased.contains("worship") {
                return .ministry
            } else if lowercased.contains("business") || lowercased.contains("entrepreneur") || lowercased.contains("startup") {
                return .business
            } else if lowercased.contains("creative") || lowercased.contains("art") || lowercased.contains("design") {
                return .creative
            }
            return .all
        }
    }
}

// MARK: - Spotlight User Model

struct SpotlightUser: Identifiable {
    let id: String // Firebase user ID
    let name: String
    let username: String
    let bio: String
    let profileImageURL: String?
    let category: SpotlightCategory
    let stats: UserStats
    let isVerified: Bool
    let joinedDate: Date
    
    struct UserStats {
        let posts: Int
        let followers: String
        let engagement: String
    }
    
    enum SpotlightCategory: String, CaseIterable {
        case all = "All"
        case creators = "Creators"
        case innovators = "Innovators"
        case leaders = "Leaders"
        case newcomers = "Newcomers"
        
        var icon: String {
            switch self {
            case .all: return "star.fill"
            case .creators: return "paintbrush.fill"
            case .innovators: return "lightbulb.fill"
            case .leaders: return "crown.fill"
            case .newcomers: return "sparkles"
            }
        }
        
        var color: Color {
            switch self {
            case .all: return .yellow
            case .creators: return .purple
            case .innovators: return .orange
            case .leaders: return .blue
            case .newcomers: return .green
            }
        }
    }
}

// MARK: - Trending Service

@MainActor
class TrendingService: ObservableObject {
    static let shared = TrendingService()
    
    @Published var topIdeas: [TopIdea] = []
    @Published var spotlightUsers: [SpotlightUser] = []
    @Published var isLoading = false
    
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // MARK: - Top Ideas Algorithm
    
    /// Calculate trending score for a post
    /// Factors: engagement velocity, recency, quality (comments > reactions)
    private func calculateTrendingScore(
        amenCount: Int,
        lightbulbCount: Int,
        commentCount: Int,
        createdAt: Date
    ) -> Double {
        let now = Date()
        let hoursSincePost = now.timeIntervalSince(createdAt) / 3600
        
        // Prevent division by zero, use minimum 1 hour
        let timeWindow = max(1.0, hoursSincePost)
        
        // Weighted engagement: comments worth more than reactions
        let engagementScore = Double(commentCount * 3 + lightbulbCount * 2 + amenCount)
        
        // Velocity: engagement per hour
        let velocity = engagementScore / timeWindow
        
        // Recency boost: newer posts get bonus
        let recencyBoost: Double
        if hoursSincePost < 6 {
            recencyBoost = 2.0 // Very recent
        } else if hoursSincePost < 24 {
            recencyBoost = 1.5 // Recent
        } else if hoursSincePost < 72 {
            recencyBoost = 1.0 // Somewhat recent
        } else {
            recencyBoost = 0.5 // Older
        }
        
        // Final trending score
        return velocity * recencyBoost
    }
    
    /// Fetch top trending ideas from Firebase
    func fetchTopIdeas(
        timeframe: TimeInterval = 7 * 24 * 3600, // Default: 7 days
        limit: Int = 20,
        category: TopIdea.IdeaCategory = .all
    ) async throws {
        isLoading = true
        defer { isLoading = false }
        
        print("📊 Fetching top ideas for timeframe: \(timeframe / 86400) days")
        
        let cutoffDate = Date().addingTimeInterval(-timeframe)
        
        // Query posts from OpenTable with minimum engagement
        var query = db.collection("posts")
            .whereField("category", isEqualTo: "openTable")
            .whereField("createdAt", isGreaterThan: cutoffDate)
            .whereField("lightbulbCount", isGreaterThan: 2) // Minimum 3 lightbulbs to be considered
        
        let snapshot = try await query.getDocuments()
        
        print("📥 Fetched \(snapshot.documents.count) potential top ideas")
        
        // Convert to TopIdea with scoring
        var ideas: [TopIdea] = []
        
        for document in snapshot.documents {
            let data = document.data()
            
            guard let authorId = data["authorId"] as? String,
                  let authorName = data["authorName"] as? String,
                  let content = data["content"] as? String,
                  let createdAtTimestamp = data["createdAt"] as? Timestamp else {
                continue
            }
            
            let createdAt = createdAtTimestamp.dateValue()
            let amenCount = data["amenCount"] as? Int ?? 0
            let lightbulbCount = data["lightbulbCount"] as? Int ?? 0
            let commentCount = data["commentCount"] as? Int ?? 0
            let topicTag = data["topicTag"] as? String
            
            // Calculate trending score
            let trendingScore = calculateTrendingScore(
                amenCount: amenCount,
                lightbulbCount: lightbulbCount,
                commentCount: commentCount,
                createdAt: createdAt
            )
            
            // Determine category from topic tag
            let ideaCategory = topicTag != nil ? TopIdea.IdeaCategory.fromTopicTag(topicTag!) : .all
            
            // Filter by category if not "all"
            if category != .all && ideaCategory != category {
                continue
            }
            
            // Determine badges
            var badges: [String] = []
            if lightbulbCount > 50 { badges.append("💡 Brilliant") }
            if commentCount > 20 { badges.append("💬 Hot Discussion") }
            if amenCount > 30 { badges.append("🙏 Inspiring") }
            let hoursSincePost = Date().timeIntervalSince(createdAt) / 3600
            if hoursSincePost < 6 { badges.append("🔥 Trending Now") }
            
            let idea = TopIdea(
                id: document.documentID,
                rank: 0, // Will be assigned after sorting
                authorId: authorId,
                authorName: authorName,
                authorUsername: data["authorUsername"] as? String,
                authorProfileImageURL: data["authorProfileImageURL"] as? String,
                timeAgo: formatTimeAgo(from: createdAt),
                content: content,
                lightbulbCount: lightbulbCount,
                commentCount: commentCount,
                amenCount: amenCount,
                category: ideaCategory,
                badges: badges,
                trendingScore: trendingScore,
                createdAt: createdAt
            )
            
            ideas.append(idea)
        }
        
        // Sort by trending score and assign ranks
        ideas.sort { $0.trendingScore > $1.trendingScore }
        
        // Take top N and assign ranks
        topIdeas = Array(ideas.prefix(limit)).enumerated().map { index, idea in
            TopIdea(
                id: idea.id,
                rank: index + 1,
                authorId: idea.authorId,
                authorName: idea.authorName,
                authorUsername: idea.authorUsername,
                authorProfileImageURL: idea.authorProfileImageURL,
                timeAgo: idea.timeAgo,
                content: idea.content,
                lightbulbCount: idea.lightbulbCount,
                commentCount: idea.commentCount,
                amenCount: idea.amenCount,
                category: idea.category,
                badges: idea.badges,
                trendingScore: idea.trendingScore,
                createdAt: idea.createdAt
            )
        }
        
        print("✅ Top ideas calculated: \(topIdeas.count) ideas")
    }
    
    // MARK: - Spotlight Users
    
    /// Fetch featured spotlight users
    func fetchSpotlightUsers(category: SpotlightUser.SpotlightCategory = .all) async throws {
        isLoading = true
        defer { isLoading = false }
        
        print("⭐ Fetching spotlight users")
        
        // Query users sorted by various metrics
        // For now, we'll fetch users with posts and calculate their stats
        let postsSnapshot = try await db.collection("posts")
            .whereField("category", isEqualTo: "openTable")
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()
        
        // Aggregate user stats
        var userStats: [String: (posts: Int, totalEngagement: Int, lastPost: Date)] = [:]
        
        for document in postsSnapshot.documents {
            let data = document.data()
            guard let authorId = data["authorId"] as? String,
                  let createdAtTimestamp = data["createdAt"] as? Timestamp else {
                continue
            }
            
            let amenCount = data["amenCount"] as? Int ?? 0
            let lightbulbCount = data["lightbulbCount"] as? Int ?? 0
            let commentCount = data["commentCount"] as? Int ?? 0
            let engagement = amenCount + lightbulbCount + commentCount
            let createdAt = createdAtTimestamp.dateValue()
            
            if var stats = userStats[authorId] {
                stats.posts += 1
                stats.totalEngagement += engagement
                stats.lastPost = max(stats.lastPost, createdAt)
                userStats[authorId] = stats
            } else {
                userStats[authorId] = (posts: 1, totalEngagement: engagement, lastPost: createdAt)
            }
        }
        
        // Sort users by engagement and activity
        let sortedUsers = userStats.sorted { $0.value.totalEngagement > $1.value.totalEngagement }
        
        // Fetch user details for top users
        var users: [SpotlightUser] = []
        
        for (userId, stats) in sortedUsers.prefix(20) {
            // Fetch user profile
            guard let userDoc = try? await db.collection("users").document(userId).getDocument(),
                  userDoc.exists,
                  let userData = userDoc.data(),
                  let name = userData["displayName"] as? String else {
                continue
            }
            
            let username = userData["username"] as? String ?? "@\(name.lowercased().replacingOccurrences(of: " ", with: ""))"
            let bio = userData["bio"] as? String ?? "Active community member sharing ideas and inspiration."
            let profileImageURL = userData["profileImageURL"] as? String
            let joinedTimestamp = userData["createdAt"] as? Timestamp
            let joinedDate = joinedTimestamp?.dateValue() ?? Date()
            
            // Calculate engagement rate
            let avgEngagementPerPost = Double(stats.totalEngagement) / Double(stats.posts)
            let engagementPercent = min(99, Int(avgEngagementPerPost * 10))
            
            // Determine category based on activity
            let userCategory = determineSpotlightCategory(
                posts: stats.posts,
                joinedDate: joinedDate,
                engagementRate: avgEngagementPerPost
            )
            
            // Filter by category if specified
            if category != .all && userCategory != category {
                continue
            }
            
            // Format follower count (placeholder - would need followers collection)
            let followerCount = "\(stats.totalEngagement / 10)+"
            
            let user = SpotlightUser(
                id: userId,
                name: name,
                username: username,
                bio: bio,
                profileImageURL: profileImageURL,
                category: userCategory,
                stats: SpotlightUser.UserStats(
                    posts: stats.posts,
                    followers: followerCount,
                    engagement: "\(engagementPercent)%"
                ),
                isVerified: stats.totalEngagement > 50, // Auto-verify highly engaged users
                joinedDate: joinedDate
            )
            
            users.append(user)
        }
        
        spotlightUsers = users
        print("✅ Fetched \(users.count) spotlight users")
    }
    
    /// Determine spotlight category based on user activity
    private func determineSpotlightCategory(
        posts: Int,
        joinedDate: Date,
        engagementRate: Double
    ) -> SpotlightUser.SpotlightCategory {
        let daysSinceJoined = Date().timeIntervalSince(joinedDate) / 86400
        
        // Newcomers: joined within 30 days
        if daysSinceJoined < 30 {
            return .newcomers
        }
        
        // Leaders: high engagement rate
        if engagementRate > 15 {
            return .leaders
        }
        
        // Creators: many posts
        if posts > 20 {
            return .creators
        }
        
        // Innovators: balanced activity
        if engagementRate > 8 && posts > 10 {
            return .innovators
        }
        
        return .all
    }
    
    // MARK: - Helper Functions
    
    private func formatTimeAgo(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)
        
        if minutes < 1 {
            return "Just now"
        } else if minutes < 60 {
            return "\(minutes)m"
        } else if hours < 24 {
            return "\(hours)h"
        } else if days < 7 {
            return "\(days)d"
        } else {
            let weeks = days / 7
            return "\(weeks)w"
        }
    }
}
