//
//  ChurchFitScoreService.swift
//  AMENAPP
//
//  Computes an AI church fit score (0-100%) based on user's theology
//  preferences, engagement history, location, and community patterns.
//

import Foundation
import CoreLocation

// MARK: - Models

struct FitScore {
    let score: Int          // 0-100
    let topReason: String   // "Reformed theology · 1.2 mi"
    let badge: FitBadge?

    enum FitBadge: String {
        case excellent = "Great fit"    // 80-100
        case good      = "Good fit"     // 60-79
        case fair      = "Worth exploring" // 40-59
    }

    static func badgeFor(score: Int) -> FitBadge? {
        switch score {
        case 80...: return .excellent
        case 60..<80: return .good
        case 40..<60: return .fair
        default: return nil
        }
    }
}

struct UserPreferenceVector {
    var denomination: String?         // "Reformed", "Baptist", etc.
    var denominationIsFlexible: Bool  // true if user selects "Open to any"
    var preferredStyle: ServiceStyle
    var location: CLLocationCoordinate2D?
    var engagedTopics: [String]       // from HomeFeedAlgorithm interests

    enum ServiceStyle: String {
        case traditional, contemporary, hybrid, noPreference
    }
}

struct ChurchProfileVector {
    var denomination: String?
    var serviceStyle: UserPreferenceVector.ServiceStyle
    var distanceMiles: Float
    var amenUserCount: Int    // AMEN users who attend / have notes
}

// MARK: - Service

class ChurchFitScoreService {
    static let shared = ChurchFitScoreService()
    private init() {}

    // Cached user preferences for the session
    private var userPrefs: UserPreferenceVector?

    /// Build user preference vector from available data.
    func loadUserPreferences() -> UserPreferenceVector {
        if let cached = userPrefs { return cached }

        let interests = HomeFeedAlgorithm.shared.userInterests
        let topics = Array(interests.engagedTopics.keys)

        // Infer denomination from engaged topics
        let denomination: String?
        let denominationKeywords: [String: [String]] = [
            "Reformed": ["reformed", "calvinist", "sovereignty", "doctrines of grace"],
            "Charismatic": ["charismatic", "pentecostal", "spirit-filled", "tongues", "prophetic"],
            "Baptist": ["baptist", "immersion", "believers baptism"],
            "Catholic": ["catholic", "mass", "eucharist", "rosary", "pope"],
            "Non-denominational": ["nondenominational", "non-denominational", "community church"],
        ]

        denomination = denominationKeywords.first { _, keywords in
            keywords.contains { keyword in
                topics.contains { $0.lowercased().contains(keyword) }
            }
        }?.key

        let prefs = UserPreferenceVector(
            denomination: denomination,
            denominationIsFlexible: denomination == nil,
            preferredStyle: .noPreference,
            location: nil, // Set by caller with CLLocationManager
            engagedTopics: topics
        )

        userPrefs = prefs
        return prefs
    }

    /// Compute fit score for a church.
    func computeFitScore(
        user: UserPreferenceVector,
        church: ChurchProfileVector
    ) -> FitScore {
        var score: Float = 0

        // Denomination match: 40% weight
        if let userDenom = user.denomination, let churchDenom = church.denomination,
           userDenom.lowercased() == churchDenom.lowercased() {
            score += 40
        } else if user.denominationIsFlexible {
            score += 20
        }

        // Distance score: 30% weight (inverse — closer is better)
        let distanceScore = max(0, 30 - (church.distanceMiles * 3))
        score += distanceScore

        // Community activity: 20% weight
        let activityScore = min(20, Float(church.amenUserCount) * 2)
        score += activityScore

        // Service style match: 10% weight
        if user.preferredStyle == church.serviceStyle {
            score += 10
        } else if user.preferredStyle == .noPreference {
            score += 5
        }

        let finalScore = Int(min(100, max(0, score)))
        let topReason = computeTopReason(user: user, church: church, distanceScore: distanceScore)
        let badge = FitScore.badgeFor(score: finalScore)

        return FitScore(score: finalScore, topReason: topReason, badge: badge)
    }

    /// Batch compute fit scores for an array of churches.
    func computeScores(
        for churches: [(id: String, denomination: String?, distanceMiles: Float, amenUsers: Int)]
    ) -> [String: FitScore] {
        let user = loadUserPreferences()
        var results: [String: FitScore] = [:]

        for church in churches {
            let vector = ChurchProfileVector(
                denomination: church.denomination,
                serviceStyle: .noPreference,
                distanceMiles: church.distanceMiles,
                amenUserCount: church.amenUsers
            )
            results[church.id] = computeFitScore(user: user, church: vector)
        }

        return results
    }

    // MARK: - Helpers

    private func computeTopReason(
        user: UserPreferenceVector,
        church: ChurchProfileVector,
        distanceScore: Float
    ) -> String {
        var parts: [String] = []

        if let denom = church.denomination {
            parts.append(denom)
        }

        if church.distanceMiles < 5 {
            parts.append(String(format: "%.1f mi", church.distanceMiles))
        }

        if church.amenUserCount > 0 {
            parts.append("\(church.amenUserCount) AMEN members")
        }

        return parts.prefix(2).joined(separator: " · ")
    }

    /// Reset cached preferences (call on sign-out or preference change).
    func resetPreferences() {
        userPrefs = nil
    }
}
