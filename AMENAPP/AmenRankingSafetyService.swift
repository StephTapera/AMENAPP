//
//  AmenRankingSafetyService.swift
//  AMENAPP
//
//  Client interface for safety-first ranking.
//  Fetches ranking decisions from backend.
//  Applies suppression/boost signals to feed ordering.
//  Public vanity metrics hidden by default per feature flag.
//

import Foundation
import SwiftUI
import FirebaseFunctions

// MARK: - TSRankingDecision

struct TSRankingDecision {
    let contentId: String
    let finalScore: Double
    let trendEligible: Bool
    let boostEligible: Bool
    let suppressedReason: String?
    let policyVersion: String
}

@MainActor
final class AmenRankingSafetyService: ObservableObject {

    static let shared = AmenRankingSafetyService()

    private let functions = Functions.functions()
    private let flags = AmenSafetyFeatureFlags.shared

    // Cached ranking decisions by contentId
    private var rankingCache: [String: TSRankingDecision] = [:]

    private init() {}

    // MARK: - Fetch ranking decision

    func rankingDecision(for contentId: String) async -> TSRankingDecision? {
        if let cached = rankingCache[contentId] { return cached }

        do {
            let result = try await functions.httpsCallable("computeRankingScore").call([
                "contentId": contentId,
            ])
            guard let data = result.data as? [String: Any] else { return nil }
            let decision = parseRankingDecision(data, contentId: contentId)
            rankingCache[contentId] = decision
            return decision
        } catch {
            return nil
        }
    }

    // MARK: - Feed sorting

    /// Sort feed items using safety-first ranking scores.
    /// Falls back to chronological if ranking unavailable.
    func sortFeedItems<T: FeedRankable>(_ items: [T]) -> [T] {
        guard flags.rankingSafetyEnabled else { return items }
        return items.sorted { a, b in
            (rankingCache[a.contentId]?.finalScore ?? 0.5) >
            (rankingCache[b.contentId]?.finalScore ?? 0.5)
        }
    }

    // MARK: - Vanity metric visibility

    var shouldShowVanityMetrics: Bool {
        !flags.hideVanityMetricsEnabled
    }

    var shouldShowLikeCount: Bool { shouldShowVanityMetrics }
    var shouldShowViewCount: Bool { shouldShowVanityMetrics }

    // MARK: - Trend eligibility

    func isTrendEligible(_ contentId: String) -> Bool {
        guard flags.trendGateEnabled else { return true }
        return rankingCache[contentId]?.trendEligible ?? false
    }

    // MARK: - Suppression

    func suppressionReason(for contentId: String) -> String? {
        rankingCache[contentId]?.suppressedReason
    }

    // MARK: - Parse

    private func parseRankingDecision(_ data: [String: Any], contentId: String) -> TSRankingDecision {
        TSRankingDecision(
            contentId: contentId,
            finalScore: data["finalScore"] as? Double ?? 0.5,
            trendEligible: data["trendEligible"] as? Bool ?? false,
            boostEligible: data["boostEligible"] as? Bool ?? false,
            suppressedReason: data["suppressedReason"] as? String,
            policyVersion: data["policyVersion"] as? String ?? AmenTrustSafetyOSVersion
        )
    }

    func invalidateCache(for contentId: String) {
        rankingCache.removeValue(forKey: contentId)
    }
}

// MARK: - Protocol for rankable feed items

protocol FeedRankable {
    var contentId: String { get }
}
