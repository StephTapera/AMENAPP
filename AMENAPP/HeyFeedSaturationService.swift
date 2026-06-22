//
//  HeyFeedSaturationService.swift
//  AMENAPP
//
//  Detects when the user is being oversaturated with any single topic,
//  even if they previously requested more of it.
//  Provides saturation penalty to HomeFeedAlgorithm.
//

import Foundation
import SwiftUI

@MainActor
final class HeyFeedSaturationService: ObservableObject {

    static let shared = HeyFeedSaturationService()
    private init() {}

    // MARK: - Config

    private let windowSize        = 25    // Rolling window of last N posts seen
    private let saturationThreshold = 8  // > 8 of same topic in 25 = saturated
    private let strongThreshold   = 12   // > 12 = strong saturation

    // MARK: - State

    /// Ring buffer of recently seen post topic clusters.
    private var recentTopics: [[String]] = []  // Array of [topicId] per post
    private var topicCounts: [String: Int] = [:]

    // MARK: - Record

    /// Record that a post with these topics was shown to the user.
    func recordImpression(topics: [String]) {
        recentTopics.append(topics)
        for t in topics { topicCounts[t, default: 0] += 1 }

        // Trim to window
        while recentTopics.count > windowSize {
            let oldest = recentTopics.removeFirst()
            for t in oldest {
                if let count = topicCounts[t] {
                    let newCount = count - 1
                    if newCount <= 0 { topicCounts.removeValue(forKey: t) }
                    else { topicCounts[t] = newCount }
                }
            }
        }
    }

    // MARK: - Query

    /// Saturation penalty for a given topic (0.0 = none, up to -0.25).
    func saturationPenalty(for topic: String) -> Double {
        let count = topicCounts[topic] ?? 0
        if count <= saturationThreshold { return 0 }
        if count >= strongThreshold { return -0.25 }
        // Linear scale between threshold and strong
        let t = Double(count - saturationThreshold) / Double(strongThreshold - saturationThreshold)
        return -0.25 * t
    }

    /// True if the user is seeing too much of this topic.
    func isSaturated(for topic: String) -> Bool {
        (topicCounts[topic] ?? 0) > saturationThreshold
    }

    /// Returns topics that are currently saturated (for rebalance suggestions).
    var saturatedTopics: [String] {
        topicCounts.filter { $0.value > saturationThreshold }.map(\.key)
    }

    /// Returns a rebalance suggestion label if saturation detected.
    var rebalanceSuggestion: String? {
        let sat = saturatedTopics
        guard !sat.isEmpty else { return nil }
        let topicLabel = sat.first?.replacingOccurrences(of: "_", with: " ").capitalized ?? "this topic"
        return "Still want more \(topicLabel), or rebalance a bit?"
    }

    /// Reset all saturation tracking (e.g., on feed full refresh).
    func reset() {
        recentTopics = []
        topicCounts = [:]
    }
}
