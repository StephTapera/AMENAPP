//
//  PersonalizationService.swift
//  AMENAPP
//
//  Intelligent personalization engine that uses user interests
//  to recommend relevant people and posts
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class PersonalizationService: ObservableObject {
    static let shared = PersonalizationService()
    
    @Published var isPersonalizing = false
    @Published var userProfile: UserModel?
    
    private let db = Firestore.firestore()
    
    private init() {
        // Load user profile on init
        Task {
            await loadUserProfile()
        }
    }
    
    // MARK: - User Profile Management
    
    func loadUserProfile() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ PersonalizationService: No authenticated user")
            return
        }
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            userProfile = try? document.data(as: UserModel.self)
            print("✅ PersonalizationService: Loaded user profile with \(userProfile?.interests?.count ?? 0) interests")
        } catch {
            print("❌ PersonalizationService: Failed to load profile - \(error)")
        }
    }
    
    // MARK: - Post Personalization Algorithm
    
    /// Personalize posts based on user interests, goals, and behavior
    func personalizePostsFeed(_ posts: [Post], category: Post.PostCategory) -> [Post] {
        guard let profile = userProfile else {
            print("⚠️ No user profile for personalization")
            return posts
        }
        
        guard let interests = profile.interests, !interests.isEmpty else {
            print("⚠️ User has no interests set")
            return posts
        }
        
        let goals = profile.goals ?? []
        
        print("🎯 Personalizing \(posts.count) posts with \(interests.count) interests and \(goals.count) goals")
        
        // Score and sort posts
        let scoredPosts = posts.map { post -> (post: Post, score: PostRelevanceScore) in
            let score = calculatePostRelevance(
                post: post,
                interests: interests,
                goals: goals,
                category: category
            )
            return (post: post, score: score)
        }
        
        // Sort by total score
        let sortedPosts = scoredPosts
            .sorted { $0.score.total > $1.score.total }
            .map { $0.post }
        
        // Log top 3 posts for debugging
        if scoredPosts.count >= 3 {
            print("📊 Top 3 personalized posts:")
            for i in 0..<min(3, scoredPosts.count) {
                let scored = scoredPosts.sorted { $0.score.total > $1.score.total }[i]
                print("   \(i+1). Score: \(Int(scored.score.total)) - \(scored.post.content.prefix(50))...")
            }
        }
        
        return sortedPosts
    }
    
    // MARK: - People Recommendation Algorithm
    
    /// Find people who match user's interests for friend suggestions
    func findRelevantPeople(limit: Int = 20) async -> [UserModel] {
        guard let currentProfile = userProfile else {
            print("⚠️ No user profile for people recommendations")
            return []
        }
        
        guard let userInterests = currentProfile.interests, !userInterests.isEmpty else {
            print("⚠️ User has no interests for people matching")
            return []
        }
        
        do {
            print("🔍 Finding people with matching interests...")
            
            // Fetch potential matches from Firestore
            // Query users who have ANY of the same interests
            var allMatches: [UserModel] = []
            
            // Query by interests (Firestore supports array-contains-any for up to 10 items)
            let interestsToQuery = Array(userInterests.prefix(10))
            
            let snapshot = try await db.collection("users")
                .whereField("interests", arrayContainsAny: interestsToQuery)
                .limit(to: 50) // Get more than needed for scoring
                .getDocuments()
            
            let users = snapshot.documents.compactMap { doc -> UserModel? in
                try? doc.data(as: UserModel.self)
            }
            
            // Filter out current user
            let otherUsers = users.filter { $0.id != currentProfile.id }
            
            print("📥 Found \(otherUsers.count) users with matching interests")
            
            // Score each user
            let scoredUsers = otherUsers.map { user -> (user: UserModel, score: UserRelevanceScore) in
                let score = calculateUserRelevance(
                    user: user,
                    currentUserInterests: userInterests,
                    currentUserGoals: currentProfile.goals ?? []
                )
                return (user: user, score: score)
            }
            
            // Sort by score and take top results
            let topUsers = scoredUsers
                .sorted { $0.score.total > $1.score.total }
                .prefix(limit)
                .map { $0.user }
            
            print("✅ Recommended \(topUsers.count) users based on interests")
            
            // Log top 3 for debugging
            if scoredUsers.count >= 3 {
                print("📊 Top 3 recommended users:")
                for i in 0..<min(3, scoredUsers.count) {
                    let scored = scoredUsers.sorted { $0.score.total > $1.score.total }[i]
                    print("   \(i+1). Score: \(Int(scored.score.total)) - @\(scored.user.username) (\(scored.score.sharedInterests) shared interests)")
                }
            }
            
            return Array(topUsers)
            
        } catch {
            print("❌ Failed to find relevant people: \(error)")
            return []
        }
    }
    
    // MARK: - Post Relevance Scoring
    
    private func calculatePostRelevance(
        post: Post,
        interests: [String],
        goals: [String],
        category: Post.PostCategory
    ) -> PostRelevanceScore {
        var score = PostRelevanceScore()
        
        // 1. INTEREST-BASED SCORING (50 points)
        
        // Topic tag exact match (highest priority)
        if let topicTag = post.topicTag {
            let topicLower = topicTag.lowercased()
            
            // Exact match
            for interest in interests {
                if topicLower == interest.lowercased() {
                    score.interestMatch += 50.0
                    score.matchedInterests.append(interest)
                    break
                }
            }
            
            // Partial match if no exact match
            if score.interestMatch == 0 {
                for interest in interests {
                    let interestWords = interest.lowercased().split(separator: " ")
                    let topicWords = topicLower.split(separator: " ")
                    
                    if interestWords.contains(where: { topicWords.contains($0) }) {
                        score.interestMatch += 25.0
                        score.matchedInterests.append(interest)
                    }
                }
            }
        }
        
        // Content keyword matching
        let contentLower = post.content.lowercased()
        for interest in interests {
            let keywords = extractKeywords(from: interest)
            for keyword in keywords {
                if contentLower.contains(keyword.lowercased()) {
                    score.interestMatch += 5.0
                    if !score.matchedInterests.contains(interest) {
                        score.matchedInterests.append(interest)
                    }
                }
            }
        }
        
        // Cap interest match at 50
        score.interestMatch = min(score.interestMatch, 50.0)
        
        // 2. GOAL ALIGNMENT (25 points)
        for goal in goals {
            let keywords = extractKeywords(from: goal)
            for keyword in keywords where keyword.count > 3 {
                if contentLower.contains(keyword.lowercased()) {
                    score.goalAlignment += 5.0
                    score.matchedGoals.append(goal)
                }
            }
        }
        score.goalAlignment = min(score.goalAlignment, 25.0)
        
        // 3. ENGAGEMENT QUALITY (15 points)
        switch category {
        case .openTable:
            score.engagement = min(Double(post.lightbulbCount) / 10.0, 10.0)
        case .testimonies, .prayer:
            score.engagement = min(Double(post.amenCount) / 20.0, 10.0)
        case .tip, .funFact:
            score.engagement = min(Double(post.amenCount) / 15.0, 10.0)
        }
        
        // Comment bonus
        score.engagement += min(Double(post.commentCount) / 10.0, 5.0)
        
        // 4. RECENCY (10 points)
        let hoursAgo = Date().timeIntervalSince(post.createdAt) / 3600.0
        if hoursAgo < 1 {
            score.recency = 10.0
        } else if hoursAgo < 3 {
            score.recency = 8.0
        } else if hoursAgo < 12 {
            score.recency = 6.0
        } else if hoursAgo < 24 {
            score.recency = 4.0
        } else if hoursAgo < 72 {
            score.recency = 2.0
        } else {
            score.recency = 1.0
        }
        
        return score
    }
    
    // MARK: - User Relevance Scoring
    
    private func calculateUserRelevance(
        user: UserModel,
        currentUserInterests: [String],
        currentUserGoals: [String]
    ) -> UserRelevanceScore {
        var score = UserRelevanceScore()
        
        let otherUserInterests = user.interests ?? []
        let otherUserGoals = user.goals ?? []
        
        // 1. SHARED INTERESTS (60 points - highest priority)
        for currentInterest in currentUserInterests {
            for otherInterest in otherUserInterests {
                // Exact match
                if currentInterest.lowercased() == otherInterest.lowercased() {
                    score.sharedInterests += 1
                    score.interestScore += 10.0
                    continue
                }
                
                // Partial match (shared keywords)
                let currentWords = Set(currentInterest.lowercased().split(separator: " "))
                let otherWords = Set(otherInterest.lowercased().split(separator: " "))
                let intersection = currentWords.intersection(otherWords)
                
                if !intersection.isEmpty {
                    score.sharedInterests += 1
                    score.interestScore += 5.0
                }
            }
        }
        score.interestScore = min(score.interestScore, 60.0)
        
        // 2. SHARED GOALS (30 points)
        for currentGoal in currentUserGoals {
            for otherGoal in otherUserGoals {
                // Exact match
                if currentGoal.lowercased() == otherGoal.lowercased() {
                    score.sharedGoals += 1
                    score.goalScore += 10.0
                    continue
                }
                
                // Partial match
                let currentWords = Set(currentGoal.lowercased().split(separator: " "))
                let otherWords = Set(otherGoal.lowercased().split(separator: " "))
                let intersection = currentWords.intersection(otherWords)
                
                if !intersection.isEmpty {
                    score.sharedGoals += 1
                    score.goalScore += 5.0
                }
            }
        }
        score.goalScore = min(score.goalScore, 30.0)
        
        // 3. ACTIVITY LEVEL (10 points)
        // Users with posts are more engaged
        if user.postsCount > 0 {
            score.activityScore = min(Double(user.postsCount) / 5.0, 5.0)
        }
        
        // Users with followers are more connected
        if user.followersCount > 0 {
            score.activityScore += min(Double(user.followersCount) / 20.0, 5.0)
        }
        
        return score
    }
    
    // MARK: - Helper Methods
    
    /// Extract searchable keywords from a phrase
    private func extractKeywords(from text: String) -> [String] {
        return text
            .components(separatedBy: CharacterSet(charactersIn: " ,&-/()"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 2 }
    }
}

// MARK: - Scoring Models

struct PostRelevanceScore {
    var interestMatch: Double = 0.0      // Max 50 points
    var goalAlignment: Double = 0.0      // Max 25 points
    var engagement: Double = 0.0         // Max 15 points
    var recency: Double = 0.0            // Max 10 points
    
    var matchedInterests: [String] = []
    var matchedGoals: [String] = []
    
    var total: Double {
        interestMatch + goalAlignment + engagement + recency
    }
}

struct UserRelevanceScore {
    var sharedInterests: Int = 0
    var sharedGoals: Int = 0
    
    var interestScore: Double = 0.0  // Max 60 points
    var goalScore: Double = 0.0      // Max 30 points
    var activityScore: Double = 0.0  // Max 10 points
    
    var total: Double {
        interestScore + goalScore + activityScore
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let userInterestsUpdated = Notification.Name("userInterestsUpdated")
}
