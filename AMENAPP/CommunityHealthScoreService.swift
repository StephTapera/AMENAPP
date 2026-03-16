//
//  CommunityHealthScoreService.swift
//  AMENAPP
//
//  Feature 27: Community Health Score — scores users and posts based on
//  report history, engagement quality, account age, and verification.
//  Low-health content is shadow-reduced in the algorithmic feed.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

struct CommunityHealthScore {
    let score: Int // 0-100
    let tier: HealthTier
    let factors: [String]

    enum HealthTier: String {
        case excellent = "Trusted"    // 80-100
        case good      = "Good"       // 60-79
        case caution   = "New"        // 40-59
        case watch     = "Watch"      // 20-39
        case restricted = "Restricted" // 0-19
    }
}

class CommunityHealthScoreService {
    static let shared = CommunityHealthScoreService()
    private let db = Firestore.firestore()
    private var scoreCache: [String: (score: CommunityHealthScore, cachedAt: Date)] = [:]

    private init() {}

    /// Compute health score for a user.
    func scoreUser(userId: String) async -> CommunityHealthScore {
        // Check cache (1 hour TTL)
        if let cached = scoreCache[userId],
           Date().timeIntervalSince(cached.cachedAt) < 3600 {
            return cached.score
        }

        var score = 50 // Start at neutral
        var factors: [String] = []

        do {
            let userDoc = try await db.collection("users").document(userId).getDocument()
            let data = userDoc.data() ?? [:]

            // Account age bonus (max 20 points)
            if let createdAt = data["createdAt"] as? Timestamp {
                let daysSinceCreation = Calendar.current.dateComponents([.day], from: createdAt.dateValue(), to: Date()).day ?? 0
                let ageBonus = min(20, daysSinceCreation / 7) // 1 point per week, max 20
                score += ageBonus
                if ageBonus >= 10 { factors.append("Established account") }
            }

            // Post count bonus (max 15 points)
            let postCount = data["postsCount"] as? Int ?? 0
            score += min(15, postCount)
            if postCount >= 5 { factors.append("\(postCount) posts") }

            // Follower trust (max 10 points)
            let followers = data["followersCount"] as? Int ?? 0
            score += min(10, followers / 2)

            // Verification bonus
            if data["isVerified"] as? Bool == true {
                score += 15
                factors.append("Verified")
            }

            // Report penalty
            let reportsSnap = try? await db.collection("reports")
                .whereField("reportedUserId", isEqualTo: userId)
                .limit(to: 10)
                .getDocuments()
            let reportCount = reportsSnap?.documents.count ?? 0
            score -= reportCount * 10
            if reportCount > 0 { factors.append("\(reportCount) reports") }

        } catch {
            // Default to neutral on error
        }

        score = max(0, min(100, score))
        let tier: CommunityHealthScore.HealthTier
        switch score {
        case 80...: tier = .excellent
        case 60..<80: tier = .good
        case 40..<60: tier = .caution
        case 20..<40: tier = .watch
        default: tier = .restricted
        }

        let result = CommunityHealthScore(score: score, tier: tier, factors: factors)
        scoreCache[userId] = (score: result, cachedAt: Date())
        return result
    }

    /// Should this user's content be shadow-reduced in the feed?
    func shouldReduceVisibility(userId: String) async -> Bool {
        let health = await scoreUser(userId: userId)
        return health.score < 30
    }
}
