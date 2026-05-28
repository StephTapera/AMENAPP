//
//  GivingProfile.swift
//  AMENAPP
//
//  Private giving relevance state.
//  Stored at users/{userId}/giving_profile/current.
//

import Foundation

struct GivingRelevanceProfile: Codable, Sendable {
    var topCauseAffinities: [String: Double]   // GivingCauseCategory.rawValue → score
    var recentGivingIntentScore: Double         // 0.0–1.0
    var givingSuppressedDueToNeedState: Bool
    var preferredGivingMode: String             // "private", "public"
    var lastUpdatedAt: Date?

    var rankedCauses: [GivingCauseCategory] {
        GivingCauseCategory.allCases
            .sorted { (topCauseAffinities[$0.rawValue] ?? 0) > (topCauseAffinities[$1.rawValue] ?? 0) }
    }

    static var empty: GivingRelevanceProfile {
        GivingRelevanceProfile(
            topCauseAffinities: [:],
            recentGivingIntentScore: 0.0,
            givingSuppressedDueToNeedState: false,
            preferredGivingMode: "private",
            lastUpdatedAt: nil
        )
    }
}
