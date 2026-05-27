import Foundation
import FirebaseFirestore

enum BadgeType: String, Codable {
    case giving, wellness, crisis, community
    var color: String {
        switch self { case .giving: return "gold"; case .wellness: return "teal"; case .crisis: return "blue"; case .community: return "purple" }
    }
    var displayName: String { rawValue.capitalized }
}

enum BadgeTier: Int, Codable {
    case bronze = 1, silver = 2, gold = 3
    var displayName: String {
        switch self { case .bronze: return "Bronze"; case .silver: return "Silver"; case .gold: return "Gold" }
    }
}

struct ImpactBadge: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var description: String
    var earnedAt: Timestamp?
    var type: BadgeType
    var tier: BadgeTier

    var icon: String {
        switch name {
        case "givingChampion": return "dollarsign.circle.fill"
        case "crisisSupporter": return "heart.circle.fill"
        case "wellnessAdvocate": return "leaf.circle.fill"
        default: return "medal.fill"
        }
    }

    var badgeColor: Color {
        switch type {
        case .giving: return Color(red: 0.83, green: 0.69, blue: 0.22)
        case .wellness: return Color(red: 0.10, green: 0.60, blue: 0.56)
        case .crisis: return Color(red: 0.40, green: 0.70, blue: 0.95)
        case .community: return Color(red: 0.60, green: 0.50, blue: 0.90)
        }
    }
}

import SwiftUI
extension ImpactBadge {
    var badgeColorValue: Color {
        switch type {
        case .giving: return Color(red: 0.83, green: 0.69, blue: 0.22)
        case .wellness: return Color(red: 0.10, green: 0.60, blue: 0.56)
        case .crisis: return Color(red: 0.40, green: 0.70, blue: 0.95)
        case .community: return Color(red: 0.60, green: 0.50, blue: 0.90)
        }
    }
}

struct ImpactMetrics: Codable {
    var totalGiven: Int
    var givingCount: Int
    var wellnessEngagementHours: Double
    var crisisCheckinsCount: Int
    var supportGroupMemberships: Int
    var badgesEarned: [String]
    var impactScore: Int
    var lastAggregationAt: Timestamp?

    static func calculateScore(givingCount: Int, wellnessHours: Double, crisisCheckins: Int) -> Int {
        (givingCount * 10) + Int(wellnessHours * 2) + (crisisCheckins * 5)
    }

    static var empty: ImpactMetrics {
        ImpactMetrics(totalGiven: 0, givingCount: 0, wellnessEngagementHours: 0, crisisCheckinsCount: 0, supportGroupMemberships: 0, badgesEarned: [], impactScore: 0, lastAggregationAt: nil)
    }
}

struct WeeklyInsight: Identifiable, Codable {
    @DocumentID var id: String?
    var period: String
    var generatedAt: Timestamp?
    var summaryTotalGiven: Int
    var summaryOrganizationsSupported: Int
    var summaryWellnessHoursLogged: Double
    var summaryCrisisCheckinsCount: Int
    var summaryStreaksActive: Int
    var summaryImpactScore: Int
    var highlights: [InsightHighlight]
    var recommendations: [InsightRecommendation]
    var givingTrend: String
    var wellnessTrend: String

    struct InsightHighlight: Codable, Identifiable {
        var id = UUID().uuidString
        var title: String
        var metric: String
        var comparison: String
        var emoji: String
    }

    struct InsightRecommendation: Codable, Identifiable {
        var id = UUID().uuidString
        var title: String
        var description: String
        var actionLink: String
    }
}
