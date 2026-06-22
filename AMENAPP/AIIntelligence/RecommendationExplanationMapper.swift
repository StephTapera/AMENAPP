// RecommendationExplanationMapper.swift
// AMENAPP
//
// Wave 6 — Recommendation transparency. Bridges the EXISTING, live FeedExplanation
// / FeedReasonCode (CommunityContractsModels, generated server-side by
// FeedExplanationService) into the RecommendationExplanation contract.
//
// Honesty (§2): factors are the real reason codes that applied. FeedExplanation
// does not carry per-factor weights, so we do NOT fabricate percentages — every
// applied factor is given equal weight 1.0 ("this applied"), and the view shows
// the real server-generated humanReadable text alongside, hiding nothing.
//
// Gated by AMENFeatureFlags.shared.recommendationTransparencyEnabled at render.

import Foundation

enum RecommendationExplanationMapper {

    static func explanation(from feed: FeedExplanation) -> RecommendationExplanation {
        let factors = feed.reasons.compactMap { map($0) }.map {
            RecommendationFactor(factor: $0, weight: 1.0) // applied; source is unranked
        }
        // De-duplicate (several reason codes can map to the same factor kind).
        var seen = Set<RecommendationFactorKind>()
        let unique = factors.filter { seen.insert($0.factor).inserted }
        return RecommendationExplanation(itemId: feed.feedItemId, factors: unique)
    }

    /// Maps a real FeedReasonCode to the contract factor kind. Codes without a
    /// clean factor mapping (prayerContext, liturgicalSeason, …) are intentionally
    /// dropped here but remain visible via FeedExplanation.humanReadable in the UI.
    private static func map(_ code: FeedReasonCode) -> RecommendationFactorKind? {
        switch code {
        case .followedAuthor:       return .followedCreator
        case .sharedInterests:      return .sharedInterest
        case .bookmarkedTopic:      return .sharedInterest
        case .groupActivity:        return .communityMembership
        case .trendingInCommunity:  return .communityMembership
        case .friendEngaged:        return .recentActivity
        case .prayerContext:        return nil
        case .liturgicalSeason:     return nil
        }
    }
}
