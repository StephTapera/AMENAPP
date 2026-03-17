//
//  SpotlightViewModel.swift
//  AMENAPP
//
//  ViewModel for Spotlight with smart ranking algorithm
//  Prioritizes quality, relevance, safety over virality
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class SpotlightViewModel: ObservableObject {
    @Published var spotlightPosts: [Post] = []
    @Published var isLoading: Bool = false
    @Published var hasMoreContent: Bool = true
    
    private let rankingEngine = SpotlightRankingEngine()
    private let db = Firestore.firestore()
    private var currentUserId: String?
    private var cancellables = Set<AnyCancellable>()
    
    // Track shown content for diversity
    private var shownAuthorIds = Set<String>()
    private var shownTopics = Set<String>()
    
    // Explanation map
    private var postExplanations: [String: String] = [:]
    
    init() {
        self.currentUserId = Auth.auth().currentUser?.uid
    }
    
    // MARK: - Public Methods
    
    func loadSpotlight() async {
        guard let userId = currentUserId else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Fetch candidate posts from multiple sources
            let candidates = try await fetchCandidatePosts(userId: userId)
            
            // Score and rank posts
            let scored = await scoreAndRankPosts(candidates: candidates, userId: userId)
            
            // Filter by eligibility and take top N
            let eligible = scored.filter { $0.score.eligibility == .eligible }
            
            // Enforce diversity and take top 30
            let diverse = enforceDiversity(posts: eligible)
            spotlightPosts = Array(diverse.prefix(30)).map { $0.post }
            
            // Store explanations
            for item in diverse.prefix(30) {
                postExplanations[item.post.id.uuidString] = item.score.explanation
            }
            
            hasMoreContent = eligible.count > 30
            
            dlog("✨ Spotlight loaded: \(spotlightPosts.count) posts")
            
        } catch {
            dlog("❌ Spotlight load failed: \(error.localizedDescription)")
        }
    }
    
    func refreshSpotlight() async {
        // Reset tracking
        shownAuthorIds.removeAll()
        shownTopics.removeAll()
        postExplanations.removeAll()
        
        await loadSpotlight()
    }
    
    func applyFilter(_ filter: SpotlightFilter) async {
        // Filter existing posts or reload with filter
        await loadSpotlight()
    }
    
    func filterByCategory(_ filter: SpotlightFilter) async {
        guard let userId = currentUserId else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Fetch candidate posts from multiple sources
            let candidates = try await fetchCandidatePosts(userId: userId)
            
            // Filter by category first
            let filtered: [Post]
            switch filter {
            case .all:
                filtered = candidates
            case .prayer:
                filtered = candidates.filter { $0.category == .prayer }
            case .testimonies:
                filtered = candidates.filter { $0.category == .testimonies }
            case .discussions:
                filtered = candidates.filter { $0.category == .openTable }
            case .local:
                // Local posts could be church-related or location-based
                // For now, include all categories but prioritize local connections
                filtered = candidates
            }
            
            // Score and rank filtered posts
            let scored = await scoreAndRankPosts(candidates: filtered, userId: userId)
            
            // Filter by eligibility
            let eligible = scored.filter { $0.score.eligibility == .eligible }
            
            // Enforce diversity and take top 30
            let diverse = enforceDiversity(posts: eligible)
            spotlightPosts = Array(diverse.prefix(30)).map { $0.post }
            
            // Store explanations
            for item in diverse.prefix(30) {
                postExplanations[item.post.id.uuidString] = item.score.explanation
            }
            
            hasMoreContent = eligible.count > 30
            
            dlog("✨ Spotlight filtered (\(filter.title)): \(spotlightPosts.count) posts")
            
        } catch {
            dlog("❌ Spotlight filter failed: \(error.localizedDescription)")
        }
    }
    
    func getExplanation(for post: Post) -> String? {
        return postExplanations[post.id.uuidString]
    }
    
    // MARK: - Private Methods
    
    private func fetchCandidatePosts(userId: String) async throws -> [Post] {
        // Fetch from multiple sources in parallel
        async let followingPosts = fetchFollowingPosts(userId: userId)
        async let communityPosts = fetchCommunityPosts(userId: userId)
        async let discoveryPosts = fetchDiscoveryPosts()
        
        let (following, community, discovery) = try await (
            followingPosts,
            communityPosts,
            discoveryPosts
        )
        
        // Combine and deduplicate
        let allPosts = following + community + discovery
        let uniquePosts = Array(Dictionary(grouping: allPosts, by: { $0.id }).values.compactMap { $0.first })
        
        return uniquePosts
    }
    
    private func fetchFollowingPosts(userId: String) async throws -> [Post] {
        // Get user's following list
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let followingIds = userDoc.data()?["followingIds"] as? [String], !followingIds.isEmpty else {
            return []
        }
        
        // Fetch recent posts from following (last 7 days)
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 86400)
        
        // Split into chunks of 10 (Firestore 'in' query limit)
        let chunks = stride(from: 0, to: followingIds.count, by: 10).map {
            Array(followingIds[$0..<min($0 + 10, followingIds.count)])
        }
        
        var allPosts: [Post] = []
        
        for chunk in chunks {
            let snapshot = try await db.collection("posts")
                .whereField("authorId", in: chunk)
                .whereField("createdAt", isGreaterThan: Timestamp(date: sevenDaysAgo))
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()
            
            let posts = snapshot.documents.compactMap { doc -> Post? in
                guard var firestorePost = try? doc.data(as: FirestorePost.self) else { return nil }
                firestorePost.id = doc.documentID
                return firestorePost.toPost()
            }
            
            allPosts.append(contentsOf: posts)
        }
        
        return allPosts
    }
    
    private func fetchCommunityPosts(userId: String) async throws -> [Post] {
        // Fetch posts from user's church/local community
        let userDoc = try await db.collection("users").document(userId).getDocument()
        
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 86400)
        
        var posts: [Post] = []
        
        // Church posts
        if let churchId = userDoc.data()?["churchId"] as? String {
            let snapshot = try await db.collection("posts")
                .whereField("churchId", isEqualTo: churchId)
                .whereField("createdAt", isGreaterThan: Timestamp(date: sevenDaysAgo))
                .order(by: "createdAt", descending: true)
                .limit(to: 15)
                .getDocuments()
            
            let churchPosts = snapshot.documents.compactMap { doc -> Post? in
                guard var firestorePost = try? doc.data(as: FirestorePost.self) else { return nil }
                firestorePost.id = doc.documentID
                return firestorePost.toPost()
            }
            
            posts.append(contentsOf: churchPosts)
        }
        
        return posts
    }
    
    private func fetchDiscoveryPosts() async throws -> [Post] {
        // Fetch high-quality posts from outside user's network
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 86400)
        
        let snapshot = try await db.collection("posts")
            .whereField("createdAt", isGreaterThan: Timestamp(date: sevenDaysAgo))
            .order(by: "createdAt", descending: true)
            .limit(to: 30)
            .getDocuments()
        
        let posts = snapshot.documents.compactMap { doc -> Post? in
            guard var firestorePost = try? doc.data(as: FirestorePost.self) else { return nil }
            firestorePost.id = doc.documentID
            return firestorePost.toPost()
        }
        
        return posts
    }
    
    private func scoreAndRankPosts(
        candidates: [Post],
        userId: String
    ) async -> [(post: Post, score: SpotlightScore)] {
        
        let scored = candidates.compactMap { post -> (post: Post, score: SpotlightScore)? in
            let score = rankingEngine.calculateSpotlightScore(
                post: post,
                currentUserId: userId
            )
            
            // Only include if score is above threshold
            guard score.totalScore > 0.3 else { return nil }
            
            return (post: post, score: score)
        }
        
        // Sort by total score descending
        return scored.sorted { $0.score.totalScore > $1.score.totalScore }
    }
    
    private func enforceDiversity(
        posts: [(post: Post, score: SpotlightScore)]
    ) -> [(post: Post, score: SpotlightScore)] {
        var result: [(post: Post, score: SpotlightScore)] = []
        var recentAuthors = Set<String>()
        
        for item in posts {
            // No more than 1 post per author in every 10 posts
            if result.count % 10 == 0 {
                recentAuthors.removeAll()
            }
            
            // Skip if author seen recently
            if recentAuthors.contains(item.post.authorId) {
                continue
            }
            
            result.append(item)
            recentAuthors.insert(item.post.authorId)
            
            if result.count >= 50 {
                break
            }
        }
        
        return result
    }
}

// MARK: - Spotlight Ranking Engine

struct SpotlightRankingEngine {
    
    func calculateSpotlightScore(
        post: Post,
        currentUserId: String
    ) -> SpotlightScore {
        
        let quality = calculateQualityScore(post: post)
        let relevance = calculateRelevanceScore(post: post, userId: currentUserId)
        let safety = calculateSafetyScore(post: post)
        let freshness = calculateFreshnessScore(post: post)
        let engagement = calculateEngagementScore(post: post)
        
        // Weighted scoring (quality and safety prioritized)
        let totalScore = (
            0.30 * quality +
            0.25 * relevance +
            0.20 * safety +
            0.15 * freshness +
            0.10 * engagement
        )
        
        let eligibility = determineEligibility(post: post, safety: safety, quality: quality)
        let explanation = generateExplanation(
            quality: quality,
            relevance: relevance,
            engagement: engagement,
            post: post
        )
        
        return SpotlightScore(
            totalScore: totalScore,
            quality: quality,
            relevance: relevance,
            safety: safety,
            freshness: freshness,
            engagement: engagement,
            eligibility: eligibility,
            explanation: explanation
        )
    }
    
    // MARK: - Quality Score (0.0 to 1.0)
    
    private func calculateQualityScore(post: Post) -> Double {
        // Content length quality
        let lengthScore: Double = {
            let length = post.content.count
            if length < 30 { return 0.2 }
            if length < 100 { return 0.5 }
            if length < 300 { return 0.8 }
            if length < 500 { return 1.0 }
            return 0.9 // Very long posts slightly penalized
        }()
        
        // Has media
        let mediaScore: Double = (post.imageURLs?.isEmpty == false) ? 0.2 : 0.0
        
        // Content specificity (has details)
        let specificityScore = calculateSpecificityScore(content: post.content)
        
        return min(1.0, 0.5 * lengthScore + 0.3 * specificityScore + 0.2 * mediaScore)
    }
    
    private func calculateSpecificityScore(content: String) -> Double {
        var signals = 0
        
        // Check for specific indicators
        if content.range(of: "\\d{4}", options: .regularExpression) != nil { signals += 1 } // Years
        if content.range(of: "[A-Z][a-z]+ [A-Z][a-z]+", options: .regularExpression) != nil { signals += 1 } // Names
        if content.contains("church") || content.contains("pastor") || content.contains("Bible") { signals += 1 }
        if content.range(of: "\\d+\\s+(year|month|day|week)", options: [.regularExpression, .caseInsensitive]) != nil { signals += 1 }
        
        return Double(signals) / 4.0
    }
    
    // MARK: - Relevance Score (0.0 to 1.0)
    
    private func calculateRelevanceScore(post: Post, userId: String) -> Double {
        // Simplified relevance (would use more data in production)
        
        // Is from someone user follows?
        // (Would check followingIds in production)
        let followScore: Double = 0.5 // Neutral
        
        // Recent post = more relevant
        let ageHours = Date().timeIntervalSince(post.createdAt) / 3600
        let recencyScore = ageHours < 24 ? 1.0 : (ageHours < 72 ? 0.7 : 0.5)
        
        return 0.6 * followScore + 0.4 * recencyScore
    }
    
    // MARK: - Safety Score (0.0 to 1.0)
    
    private func calculateSafetyScore(post: Post) -> Double {
        // Basic safety checks (in production, use ContentModerationService)
        
        var safetyScore = 1.0
        
        // No reports = safer
        // (Would check actual report count in production)
        
        // Content length check (very short = potentially spam)
        if post.content.count < 20 {
            safetyScore *= 0.7
        }
        
        // Has proper punctuation/capitalization (basic quality signal)
        let hasCapital = post.content.first?.isUppercase ?? false
        if !hasCapital {
            safetyScore *= 0.9
        }
        
        return safetyScore
    }
    
    // MARK: - Freshness Score (0.0 to 1.0)
    
    private func calculateFreshnessScore(post: Post) -> Double {
        let ageHours = Date().timeIntervalSince(post.createdAt) / 3600
        
        // Exponential decay with 24-hour half-life
        let freshness = exp(-ageHours / 24.0)
        
        return max(0.0, min(1.0, freshness))
    }
    
    // MARK: - Engagement Score (0.0 to 1.0)
    
    private func calculateEngagementScore(post: Post) -> Double {
        // Weighted engagement
        let lightbulbScore = Double(post.lightbulbCount) * 1.0
        let commentScore = Double(post.commentCount) * 2.0 // Comments > reactions
        let repostScore = Double(post.repostCount) * 3.0 // Reposts highest value
        
        let totalEngagement = lightbulbScore + commentScore + repostScore
        
        // Time decay
        let ageHours = max(1.0, Date().timeIntervalSince(post.createdAt) / 3600)
        let engagementRate = totalEngagement / ageHours
        
        // Normalize (target: 5 engagements/hour = 1.0)
        return min(1.0, engagementRate / 5.0)
    }
    
    // MARK: - Eligibility Check
    
    private func determineEligibility(
        post: Post,
        safety: Double,
        quality: Double
    ) -> SpotlightEligibility {
        
        // Must meet safety threshold
        guard safety > 0.6 else {
            return .ineligible
        }
        
        // Must meet minimum quality
        guard quality > 0.4 else {
            return .ineligible
        }
        
        // Must have minimum content
        guard post.content.count >= 20 else {
            return .ineligible
        }
        
        return .eligible
    }
    
    // MARK: - Explanation Generation
    
    private func generateExplanation(
        quality: Double,
        relevance: Double,
        engagement: Double,
        post: Post
    ) -> String {
        
        if quality > 0.7 && engagement < 0.3 {
            return "High-quality post with low visibility"
        } else if engagement > 0.7 {
            return "Popular in your community"
        } else if relevance > 0.7 {
            return "Relevant to your interests"
        } else if post.createdAt.timeIntervalSinceNow > -7200 { // < 2 hours
            return "Recently posted"
        } else if post.category == .prayer {
            return "Prayer request needing support"
        } else if post.category == .testimonies {
            return "Testimony from your community"
        } else {
            return "Recommended for you"
        }
    }
}

// MARK: - Supporting Types

struct SpotlightScore {
    let totalScore: Double
    let quality: Double
    let relevance: Double
    let safety: Double
    let freshness: Double
    let engagement: Double
    let eligibility: SpotlightEligibility
    let explanation: String
}

enum SpotlightEligibility {
    case eligible
    case ineligible
    case pendingReview
}
