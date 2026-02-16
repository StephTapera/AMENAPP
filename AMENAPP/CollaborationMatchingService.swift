//
//  CollaborationMatchingService.swift
//  AMENAPP
//
//  Created by Claude on 2/15/26.
//
//  Smart AI-powered collaboration matching - finds potential co-founders and collaborators
//  Suggests people to users in a subtle, non-intrusive way
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

/// Intelligent service that matches users based on idea compatibility,
/// skills, interests, and engagement patterns
@MainActor
class CollaborationMatchingService: ObservableObject {
    static let shared = CollaborationMatchingService()
    
    @Published var suggestedCollaborators: [UserMatch] = []
    @Published var isLoading = false
    
    private let db = Firestore.firestore()
    private let filteringService = SmartIdeaFilteringService.shared
    
    // MARK: - User Match Model
    
    struct UserMatch: Identifiable {
        let id: String
        let userId: String
        let userName: String
        let profileImageURL: String?
        let bio: String?
        let matchScore: Double // 0-100
        let matchReasons: [MatchReason]
        let sharedInterests: [TopIdea.IdeaCategory]
        let complementarySkills: [String]
        let recentIdeas: [String] // Preview of their ideas
        
        enum MatchReason: String {
            case similarIdeas = "Posts similar ideas"
            case complementarySkills = "Has complementary skills"
            case sameCategory = "Active in same categories"
            case mutualConnections = "Mutual connections"
            case engagementPattern = "Engages with similar content"
            case geographicProximity = "Same location"
            case careerStage = "Similar career stage"
            
            var icon: String {
                switch self {
                case .similarIdeas: return "lightbulb.2.fill"
                case .complementarySkills: return "puzzle.piece.fill"
                case .sameCategory: return "tag.fill"
                case .mutualConnections: return "person.2.fill"
                case .engagementPattern: return "chart.line.uptrend.xyaxis"
                case .geographicProximity: return "location.fill"
                case .careerStage: return "briefcase.fill"
                }
            }
        }
    }
    
    // MARK: - Smart Matching Algorithm
    
    /// Find potential collaborators for current user
    /// Uses multi-factor scoring algorithm
    func findPotentialCollaborators(limit: Int = 10) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 1. Get current user's data
            let currentUserData = try await fetchUserData(userId: currentUserId)
            
            // 2. Get all users (except current user)
            let allUsers = try await fetchAllUsers(excluding: currentUserId)
            
            // 3. Calculate match scores for each user
            var matches: [UserMatch] = []
            
            for userData in allUsers {
                let matchScore = await calculateMatchScore(
                    currentUser: currentUserData,
                    potentialMatch: userData
                )
                
                if matchScore.score >= 30.0 { // Minimum threshold
                    let match = UserMatch(
                        id: userData.userId,
                        userId: userData.userId,
                        userName: userData.userName,
                        profileImageURL: userData.profileImageURL,
                        bio: userData.bio,
                        matchScore: matchScore.score,
                        matchReasons: matchScore.reasons,
                        sharedInterests: matchScore.sharedInterests,
                        complementarySkills: matchScore.complementarySkills,
                        recentIdeas: userData.recentIdeas
                    )
                    matches.append(match)
                }
            }
            
            // 4. Sort by match score and take top N
            suggestedCollaborators = matches
                .sorted { $0.matchScore > $1.matchScore }
                .prefix(limit)
                .map { $0 }
            
            print("✅ Found \(suggestedCollaborators.count) potential collaborators")
            
        } catch {
            print("❌ Failed to find collaborators: \(error)")
        }
    }
    
    // MARK: - Match Score Calculation (AI-Style Algorithm)
    
    private func calculateMatchScore(
        currentUser: UserData,
        potentialMatch: UserData
    ) async -> (score: Double, reasons: [UserMatch.MatchReason], sharedInterests: [TopIdea.IdeaCategory], complementarySkills: [String]) {
        
        var score: Double = 0
        var reasons: [UserMatch.MatchReason] = []
        var sharedInterests: Set<TopIdea.IdeaCategory> = []
        var complementarySkills: [String] = []
        
        // FACTOR 1: Idea Category Overlap (30 points max)
        let categoryOverlap = calculateCategoryOverlap(
            currentUser.categories,
            potentialMatch.categories
        )
        if categoryOverlap > 0 {
            score += min(30.0, categoryOverlap * 10.0)
            reasons.append(.sameCategory)
            sharedInterests = currentUser.categories.intersection(potentialMatch.categories)
        }
        
        // FACTOR 2: Similar Engagement Patterns (20 points max)
        let engagementSimilarity = calculateEngagementSimilarity(
            currentUser.engagementPattern,
            potentialMatch.engagementPattern
        )
        if engagementSimilarity > 0.5 {
            score += engagementSimilarity * 20.0
            reasons.append(.engagementPattern)
        }
        
        // FACTOR 3: Complementary Skills (25 points max)
        let skillMatch = findComplementarySkills(
            currentUser.skills,
            potentialMatch.skills
        )
        if !skillMatch.isEmpty {
            score += Double(skillMatch.count) * 5.0
            reasons.append(.complementarySkills)
            complementarySkills = skillMatch
        }
        
        // FACTOR 4: Similar Idea Themes (15 points max)
        let ideaSimilarity = calculateIdeaSimilarity(
            currentUser.recentIdeas,
            potentialMatch.recentIdeas
        )
        if ideaSimilarity > 0.3 {
            score += ideaSimilarity * 15.0
            reasons.append(.similarIdeas)
        }
        
        // FACTOR 5: Mutual Connections (10 points max)
        let mutualCount = calculateMutualConnections(
            currentUser.following,
            potentialMatch.following
        )
        if mutualCount > 0 {
            score += min(10.0, Double(mutualCount) * 2.0)
            reasons.append(.mutualConnections)
        }
        
        return (
            score: min(100.0, score),
            reasons: reasons,
            sharedInterests: Array(sharedInterests),
            complementarySkills: complementarySkills
        )
    }
    
    // MARK: - Similarity Calculations
    
    /// Calculate category overlap (0-1 scale)
    private func calculateCategoryOverlap(
        _ categories1: Set<TopIdea.IdeaCategory>,
        _ categories2: Set<TopIdea.IdeaCategory>
    ) -> Double {
        let intersection = categories1.intersection(categories2)
        let union = categories1.union(categories2)
        
        guard !union.isEmpty else { return 0 }
        return Double(intersection.count) / Double(union.count)
    }
    
    /// Calculate engagement pattern similarity (0-1 scale)
    private func calculateEngagementSimilarity(
        _ pattern1: EngagementPattern,
        _ pattern2: EngagementPattern
    ) -> Double {
        // Compare time of day, frequency, and content types
        let timeOfDayMatch = abs(pattern1.averageHourOfDay - pattern2.averageHourOfDay) < 3.0
        let frequencyRatio = min(pattern1.postsPerWeek, pattern2.postsPerWeek) / max(pattern1.postsPerWeek, pattern2.postsPerWeek)
        
        return (timeOfDayMatch ? 0.5 : 0) + (frequencyRatio * 0.5)
    }
    
    /// Find complementary skills between users
    private func findComplementarySkills(
        _ skills1: [String],
        _ skills2: [String]
    ) -> [String] {
        // Look for complementary pairs (e.g., designer + developer)
        let complementaryPairs: [[String]] = [
            ["design", "development"],
            ["frontend", "backend"],
            ["marketing", "technical"],
            ["business", "engineering"],
            ["creative", "analytical"],
            ["writer", "editor"],
            ["video", "audio"]
        ]
        
        var complementary: [String] = []
        
        for pair in complementaryPairs {
            let user1HasFirst = skills1.contains(where: { pair[0].contains($0.lowercased()) })
            let user2HasSecond = skills2.contains(where: { pair[1].contains($0.lowercased()) })
            
            if user1HasFirst && user2HasSecond {
                complementary.append(pair[1])
            }
            
            let user1HasSecond = skills1.contains(where: { pair[1].contains($0.lowercased()) })
            let user2HasFirst = skills2.contains(where: { pair[0].contains($0.lowercased()) })
            
            if user1HasSecond && user2HasFirst {
                complementary.append(pair[0])
            }
        }
        
        return Array(Set(complementary))
    }
    
    /// Calculate idea content similarity using keyword analysis
    private func calculateIdeaSimilarity(
        _ ideas1: [String],
        _ ideas2: [String]
    ) -> Double {
        guard !ideas1.isEmpty && !ideas2.isEmpty else { return 0 }
        
        // Extract keywords from ideas
        let keywords1 = Set(ideas1.flatMap { extractKeywords(from: $0) })
        let keywords2 = Set(ideas2.flatMap { extractKeywords(from: $0) })
        
        let intersection = keywords1.intersection(keywords2)
        let union = keywords1.union(keywords2)
        
        guard !union.isEmpty else { return 0 }
        return Double(intersection.count) / Double(union.count)
    }
    
    /// Extract meaningful keywords from text
    private func extractKeywords(from text: String) -> [String] {
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 3 } // Only words longer than 3 chars
        
        // Remove common stop words
        let stopWords = Set(["that", "this", "with", "from", "have", "been", "will", "would", "could", "should"])
        return words.filter { !stopWords.contains($0) }
    }
    
    /// Calculate mutual connections
    private func calculateMutualConnections(
        _ following1: [String],
        _ following2: [String]
    ) -> Int {
        Set(following1).intersection(Set(following2)).count
    }
    
    // MARK: - Data Fetching
    
    private func fetchUserData(userId: String) async throws -> UserData {
        let doc = try await db.collection("users").document(userId).getDocument()
        
        guard let data = doc.data() else {
            throw NSError(domain: "CollaborationMatching", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        // Fetch user's recent posts
        let postsSnapshot = try await db.collection("posts")
            .whereField("userId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .limit(to: 10)
            .getDocuments()
        
        let recentIdeas = postsSnapshot.documents.compactMap { $0.data()["content"] as? String }
        
        // Determine categories from ideas
        var categories: Set<TopIdea.IdeaCategory> = []
        for idea in recentIdeas {
            let category = filteringService.detectCategory(for: idea)
            if category != .all {
                categories.insert(category)
            }
        }
        
        return UserData(
            userId: userId,
            userName: data["username"] as? String ?? "Unknown",
            profileImageURL: data["profileImageURL"] as? String,
            bio: data["bio"] as? String,
            categories: categories,
            skills: data["skills"] as? [String] ?? [],
            recentIdeas: recentIdeas,
            following: data["following"] as? [String] ?? [],
            engagementPattern: EngagementPattern(
                averageHourOfDay: 14.0, // Default placeholder
                postsPerWeek: Double(postsSnapshot.documents.count)
            )
        )
    }
    
    private func fetchAllUsers(excluding: String) async throws -> [UserData] {
        let snapshot = try await db.collection("users")
            .limit(to: 100) // Limit for performance
            .getDocuments()
        
        var users: [UserData] = []
        
        for doc in snapshot.documents where doc.documentID != excluding {
            if let userData = try? await fetchUserData(userId: doc.documentID) {
                users.append(userData)
            }
        }
        
        return users
    }
    
    // MARK: - Subtle Suggestion UI Helpers
    
    /// Get a casual, non-pushy suggestion message
    func getSubtleSuggestionMessage(for match: UserMatch) -> String {
        guard let reason = match.matchReasons.first else {
            return "You might connect well with \(match.userName)"
        }
        
        switch reason {
        case .similarIdeas:
            return "\(match.userName) shares similar ideas in \(match.sharedInterests.first?.rawValue ?? "your field")"
        case .complementarySkills:
            return "\(match.userName) has skills that complement yours"
        case .sameCategory:
            return "\(match.userName) is also passionate about \(match.sharedInterests.first?.rawValue ?? "these topics")"
        case .engagementPattern:
            return "\(match.userName) posts at similar times as you"
        default:
            return "You and \(match.userName) might make a great team"
        }
    }
}

// MARK: - Supporting Data Models

struct UserData {
    let userId: String
    let userName: String
    let profileImageURL: String?
    let bio: String?
    let categories: Set<TopIdea.IdeaCategory>
    let skills: [String]
    let recentIdeas: [String]
    let following: [String]
    let engagementPattern: EngagementPattern
}

struct EngagementPattern {
    let averageHourOfDay: Double
    let postsPerWeek: Double
}
