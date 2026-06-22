// ChurchRecommendationReasonService.swift
// AMENAPP
//
// Transforms numeric scoring data from ChurchMatcherService into
// human-readable ChurchRecommendationReason objects for the UI.
// Pure score decomposition — no AI calls.

import Foundation
import CoreLocation

@MainActor
final class ChurchRecommendationReasonService {

    static let shared = ChurchRecommendationReasonService()

    private init() {}

    // MARK: - Generate from ChurchMatch

    /// Decomposes a ChurchMatch into an array of recommendation reasons,
    /// sorted by score contribution.
    func generateReasons(from match: ChurchMatch) -> [ChurchRecommendationReason] {
        var reasons: [ChurchRecommendationReason] = []

        // Distance / proximity
        if match.geoScore > 0 {
            let short: String
            let long: String
            if match.geoScore >= 0.8 {
                short = "Very close to you"
                long = "This church is nearby, making it easy to attend regularly and become part of the community."
            } else if match.geoScore >= 0.5 {
                short = "Within a reasonable drive"
                long = "This church is a manageable distance from you, close enough for regular attendance."
            } else {
                short = "A bit farther away"
                long = "This church is farther from you, but may be worth the drive for a great fit."
            }
            reasons.append(ChurchRecommendationReason(
                shortReason: short,
                longReason: long,
                category: .distance,
                score: match.geoScore
            ))
        }

        // Theology / denomination
        if match.theologyScore > 0 {
            let short: String
            let long: String
            if match.theologyScore >= 0.7 {
                short = "Strong theological alignment"
                long = "This church's theological emphasis closely matches your stated preferences and beliefs."
            } else if match.theologyScore >= 0.5 {
                short = "Good theological fit"
                long = "This church's approach to scripture and doctrine is compatible with your preferences."
            } else {
                short = "Different theological perspective"
                long = "This church may offer a fresh perspective that broadens your understanding."
            }
            // Add denomination-specific reason if available
            if let denomination = match.church.denomination, !denomination.isEmpty {
                reasons.append(ChurchRecommendationReason(
                    shortReason: "\(denomination) church",
                    longReason: "This is a \(denomination) church. \(long)",
                    category: .denomination,
                    score: match.theologyScore * 0.5
                ))
            }
            reasons.append(ChurchRecommendationReason(
                shortReason: short,
                longReason: long,
                category: .theology,
                score: match.theologyScore
            ))
        }

        // Spiritual season
        if match.seasonScore > 0 {
            reasons.append(ChurchRecommendationReason(
                shortReason: "Fits your current season",
                longReason: "This church specializes in supporting people in a similar spiritual season to yours.",
                category: .season,
                score: match.seasonScore
            ))
        }

        // Teaching style
        if match.teachingScore > 0 {
            let short: String
            let long: String
            if match.teachingScore >= 0.8 {
                short = "Teaching style matches your learning"
                long = "The pastor's teaching approach aligns well with how you learn and grow spiritually."
            } else if match.teachingScore >= 0.6 {
                short = "Compatible teaching style"
                long = "The teaching style at this church is a good fit for your learning preferences."
            } else {
                short = "Different teaching approach"
                long = "The teaching style may differ from your preference, but can offer a fresh perspective."
            }
            reasons.append(ChurchRecommendationReason(
                shortReason: short,
                longReason: long,
                category: .teaching,
                score: match.teachingScore
            ))
        }

        // Sort by score contribution (highest first)
        return reasons.sorted { $0.score > $1.score }
    }

    // MARK: - Generate and Store

    /// Generates reasons for a match and stores them on the church interaction.
    func generateAndStore(match: ChurchMatch) {
        guard AMENFeatureFlags.shared.churchExplainableRecommendationsEnabled else { return }

        let reasons = generateReasons(from: match)
        ChurchInteractionService.shared.setRecommendationReasons(
            churchId: match.id,
            reasons: reasons
        )
    }

    /// Batch-generates reasons for all matches and stores them.
    func generateAndStoreAll(matches: [ChurchMatch]) {
        guard AMENFeatureFlags.shared.churchExplainableRecommendationsEnabled else { return }

        for match in matches {
            generateAndStore(match: match)
        }
    }
}
