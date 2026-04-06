//
//  ResourceAffinity.swift
//  AMENAPP
//
//  Tracks which wellness tools a user has found helpful.
//  Stored at users/{userId}/resource_affinity/{resourceType}.
//

import Foundation

struct ResourceAffinity: Identifiable, Codable, Sendable {
    var id: String              // == resourceType key
    var resourceType: String    // "grounding", "breathing", "prayer_support", etc.
    var openCount: Int
    var completionCount: Int
    var lastOpenedAt: Date?
    var lastCompletedAt: Date?
    var helpfulnessScore: Double    // 0.0–1.0, increases on completion
    var cooldownBoostUntil: Date?   // Boost relevance after recent use

    var completionRate: Double {
        guard openCount > 0 else { return 0 }
        return Double(completionCount) / Double(openCount)
    }

    /// Effective ranking score combining helpfulness and recency.
    var rankingScore: Double {
        let recencyBoost: Double
        if let last = lastCompletedAt {
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 999
            recencyBoost = days < 3 ? 0.2 : (days < 7 ? 0.1 : 0.0)
        } else {
            recencyBoost = 0.0
        }
        return min(1.0, helpfulnessScore + recencyBoost)
    }
}
