// CreatorStudioViewModel.swift
// AMENAPP — Creator Studio / Wave 5
//
// ViewModel for the anti-vanity Creator Studio stewardship dashboard.
// Fail-closed: nothing loads unless creatorStudioDashboardEnabled.
// CONSTITUTION LOCK: no growth chart, no streak, no raw number headlines.

import Foundation
import SwiftUI

@MainActor
final class CreatorStudioViewModel: ObservableObject {

    @Published var insights: [StudioInsight] = []
    @Published var isLoading = false
    /// Visitor count — ONLY surfaced as a narrative sentence, never as a headline metric.
    @Published var profileViews: Int = 0

    func load(creatorId: String) async {
        guard AMENFeatureFlags.shared.creatorStudioDashboardEnabled else { return }

        isLoading = true
        defer { isLoading = false }

        // TODO: replace with real Firestore load from /creators/{creatorId}/studioInsights
        // The collection should contain StudioInsight documents keyed by insight kind.
        // Until the callable is deployed, populate with stewardship-framed example values.

        let now = Date().timeIntervalSince1970

        insights = [
            StudioInsight(
                id: "stub_search_discovery",
                creatorId: creatorId,
                kind: .searchDiscovery,
                narrativeText: "More people are finding you through prayer searches.",
                supportingMetricLabel: nil,
                supportingMetricValue: nil,
                supportingMetricContext: nil,
                periodLabel: "This month",
                generatedAt: now
            ),
            StudioInsight(
                id: "stub_formation_trend",
                creatorId: creatorId,
                kind: .formationTrend,
                narrativeText: "Your short studies are completed more often than long videos.",
                supportingMetricLabel: nil,
                supportingMetricValue: nil,
                supportingMetricContext: nil,
                periodLabel: "This month",
                generatedAt: now
            ),
            StudioInsight(
                id: "stub_stewardship_summary",
                creatorId: creatorId,
                kind: .stewardshipSummary,
                narrativeText: "You are guiding people through your current series on Romans.",
                supportingMetricLabel: nil,
                supportingMetricValue: nil,
                supportingMetricContext: nil,
                periodLabel: "Ongoing",
                generatedAt: now
            )
        ]

        // TODO: load real profileViews count from Firestore aggregate (no identity list)
        // profileViews is shown ONLY as "N people visited your page" in narrative context.
        profileViews = 0
    }
}
