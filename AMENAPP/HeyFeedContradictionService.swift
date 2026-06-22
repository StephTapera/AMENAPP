//
//  HeyFeedContradictionService.swift
//  AMENAPP
//
//  Detects contradictions between explicit feed preferences and actual behavior.
//  Example: user requests "more theology deep dives" but skips every long-form post.
//  Reduces boost weight when contradiction confidence is high.
//

import Foundation
import SwiftUI

@MainActor
final class HeyFeedContradictionService: ObservableObject {

    static let shared = HeyFeedContradictionService()
    private init() {}

    // MARK: - Thresholds

    private let minEventsForDetection = 5     // Need at least 5 events to detect
    private let contradictionThreshold = 0.65 // 65% skip rate = contradiction

    // MARK: - State (in-memory, session only — not persisted)

    /// Per preference-target: [engages, skips]
    private var engagementStats: [String: (engages: Int, skips: Int)] = [:]

    // MARK: - Record Events

    /// Record that the user engaged with content matching a preference target.
    func recordEngage(targetId: String) {
        var stats = engagementStats[targetId] ?? (0, 0)
        stats.engages += 1
        engagementStats[targetId] = stats
    }

    /// Record that the user skipped/hid content matching a preference target.
    func recordSkip(targetId: String) {
        var stats = engagementStats[targetId] ?? (0, 0)
        stats.skips += 1
        engagementStats[targetId] = stats
    }

    // MARK: - Query

    /// Contradiction score for a given target (0.0 = no contradiction, 1.0 = strong contradiction).
    func contradictionScore(for targetId: String) -> Double {
        guard let stats = engagementStats[targetId] else { return 0 }
        let total = stats.engages + stats.skips
        guard total >= minEventsForDetection else { return 0 }
        let skipRate = Double(stats.skips) / Double(total)
        return skipRate >= contradictionThreshold ? skipRate : 0
    }

    /// Effective ranking delta modifier (reduces boost when contradiction detected).
    /// Returns a multiplier: 1.0 = no contradiction, down to 0.2 for strong contradiction.
    func boostMultiplier(for targetId: String) -> Double {
        let score = contradictionScore(for: targetId)
        guard score > 0 else { return 1.0 }
        return max(0.2, 1.0 - score * 0.8)
    }

    /// Returns a suggestion prompt if contradiction is strong enough.
    func suggestionPrompt(for targetId: String) -> String? {
        let score = contradictionScore(for: targetId)
        guard score >= contradictionThreshold else { return nil }
        let label = targetId.replacingOccurrences(of: "_", with: " ").capitalized
        return "You asked for more \(label) — want a different style of it instead?"
    }

    /// All active contradiction suggestions.
    var allSuggestions: [String] {
        engagementStats.compactMap { key, _ in
            suggestionPrompt(for: key)
        }
    }

    /// Reset stats (call on session end or after user updates preference).
    func reset(for targetId: String? = nil) {
        if let id = targetId {
            engagementStats.removeValue(forKey: id)
        } else {
            engagementStats = [:]
        }
    }
}
