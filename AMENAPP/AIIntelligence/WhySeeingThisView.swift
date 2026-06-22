// WhySeeingThisView.swift
// AMENAPP
//
// Wave 6 — "Why am I seeing this" for a feed item. Shows the real recommendation
// factors (from FeedExplanation/FeedReasonCode) plus the real server-generated
// human-readable reason. No black box, no invented reasons.
//
// Gated by AMENFeatureFlags.shared.recommendationTransparencyEnabled (default OFF).

import SwiftUI

struct WhySeeingThisView: View {
    let feedExplanation: FeedExplanation

    private var explanation: RecommendationExplanation {
        RecommendationExplanationMapper.explanation(from: feedExplanation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why you're seeing this")
                .font(.headline)

            if !feedExplanation.humanReadable.isEmpty {
                Text(feedExplanation.humanReadable)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !explanation.factors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CONTRIBUTING FACTORS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.5)
                    ForEach(explanation.factors) { factor in
                        HStack(spacing: 8) {
                            Image(systemName: factor.factor.symbol)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Text(factor.factor.displayName)
                                .font(.subheadline)
                        }
                    }
                }
            }

            Text("These are the real signals behind this recommendation — not a guess.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Factor display (additive on the frozen Wave 0 contract)

extension RecommendationFactorKind {
    var displayName: String {
        switch self {
        case .followedCreator:     return "You follow this creator"
        case .communityMembership: return "From a community you're in"
        case .sharedInterest:      return "Matches your interests"
        case .recentActivity:      return "Related to your recent activity"
        }
    }
    var symbol: String {
        switch self {
        case .followedCreator:     return "person.crop.circle.badge.checkmark"
        case .communityMembership: return "person.3"
        case .sharedInterest:      return "heart.text.square"
        case .recentActivity:      return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Attach modifier (feed item context menu / sheet)

extension View {
    /// Presents a "why am I seeing this" sheet when bound flag is on.
    @ViewBuilder
    func whySeeingThis(_ explanation: FeedExplanation?, isPresented: Binding<Bool>) -> some View {
        if AMENFeatureFlags.shared.recommendationTransparencyEnabled, let explanation {
            self.sheet(isPresented: isPresented) {
                WhySeeingThisView(feedExplanation: explanation)
                    .presentationDetents([.medium])
            }
        } else {
            self
        }
    }
}

#if DEBUG
#Preview("Why seeing this") {
    WhySeeingThisView(feedExplanation: FeedExplanation(
        id: "1",
        feedItemId: "post-9",
        reasons: [.followedAuthor, .sharedInterests, .trendingInCommunity],
        humanReadable: "You follow this author and have shown interest in this topic."
    ))
}
#endif
