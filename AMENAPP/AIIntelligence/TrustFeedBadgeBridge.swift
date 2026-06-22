// TrustFeedBadgeBridge.swift
// AMENAPP
//
// Wave 4/6 wiring — bridges the canonical Post.trueSource bundle to the Trust
// provenance + recommendation-transparency surfaces, and hosts the feed-side
// "why am I seeing this" sheet that prefers the real server FeedExplanation.
//
// Honest by construction:
//  - Provenance origin is read from the backend-written aiGenerated / aiAssisted
//    flags on TrueSourceMetadata; it never claims "human" for AI-touched content.
//  - Why-seeing uses the REAL server FeedExplanation (FeedExplanationService),
//    never reasons synthesised from continuous ranking scores.
//
// Gated by provenanceLabelsEnabled / recommendationTransparencyEnabled at the site.

import SwiftUI

// MARK: - Post → TrustProvenanceLabel

extension Post {
    /// Derives the user-facing provenance label from the canonical True Source
    /// record. Returns nil when the post carries no True Source bundle (legacy
    /// content) so the badge is simply omitted rather than guessed.
    var trustProvenanceLabel: TrustProvenanceLabel? {
        guard let source = trueSource?.source else { return nil }

        let origin: ProvenanceOrigin
        if source.aiGenerated || source.provenanceStatus == .aiGenerated {
            origin = .aiGenerated
        } else if source.aiAssisted {
            origin = .aiAssisted
        } else {
            origin = .human
        }

        let contentId: String = {
            if let firebaseId, !firebaseId.isEmpty { return firebaseId }
            return firestoreId
        }()
        return ProvenanceLabelMapper.make(contentId: contentId, origin: origin)
    }
}

// MARK: - Feed "why am I seeing this" (Trust surface, real explanation only)

/// Presents the Trust `WhySeeingThisView` backed by the real server
/// FeedExplanation when `recommendationTransparencyEnabled` is on and an
/// explanation exists. Otherwise falls through to the supplied native fallback,
/// so the user always sees an honest answer (never an empty Trust shell).
struct TrustWhySeeingThisSheet<Fallback: View>: View {
    let feedItemId: String?
    @ViewBuilder var fallback: () -> Fallback

    @State private var explanation: FeedExplanation?
    @State private var didLoad = false

    var body: some View {
        if !AMENFeatureFlags.shared.recommendationTransparencyEnabled {
            fallback()
        } else if let explanation {
            WhySeeingThisView(feedExplanation: explanation)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        } else if didLoad {
            // Flag on but no real explanation available → honest native fallback.
            fallback()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 140)
                .task { await load() }
        }
    }

    private func load() async {
        guard let feedItemId, !feedItemId.isEmpty else { didLoad = true; return }
        explanation = await FeedExplanationService.shared.explanation(for: feedItemId)
        didLoad = true
    }
}
