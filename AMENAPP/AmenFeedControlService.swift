// AmenFeedControlService.swift
// AMENAPP
// Manages FeedControlState and exposes it to the feed ranking pipeline.

import Foundation
import Combine

@MainActor
final class AmenFeedControlService: ObservableObject {
    static let shared = AmenFeedControlService()

    @Published private(set) var state: FeedControlState = FeedControlState()
    private let core = AmenSocialSafetyService.shared

    func load() async {
        guard AMENFeatureFlags.shared.feedModeControlsEnabled else { return }
        state = (try? await core.fetchFeedControlState()) ?? FeedControlState()
    }

    func applyMode(_ mode: HeyFeedMode) async throws {
        var updated = state
        updated = FeedControlState(
            activeMode: mode,
            blockedCategories: state.blockedCategories,
            sessionDurationLimitMinutes: state.sessionDurationLimitMinutes,
            quietHoursStart: state.quietHoursStart,
            quietHoursEnd: state.quietHoursEnd
        )
        try await core.updateFeedControls(updated)
        state = updated
    }

    func toggleBlockedCategory(_ category: SafetyRiskCategory) async throws {
        var categories = state.blockedCategories
        if categories.contains(category) {
            categories.remove(category)
        } else {
            categories.insert(category)
        }
        let updated = FeedControlState(
            activeMode: state.activeMode,
            blockedCategories: categories,
            sessionDurationLimitMinutes: state.sessionDurationLimitMinutes,
            quietHoursStart: state.quietHoursStart,
            quietHoursEnd: state.quietHoursEnd
        )
        try await core.updateFeedControls(updated)
        state = updated
    }

    /// Returns true if a post with the given categories should be suppressed.
    func shouldSuppress(categories: [SafetyRiskCategory]) -> Bool {
        guard AMENFeatureFlags.shared.feedBoundaryEnabled else { return false }
        return !state.blockedCategories.isDisjoint(with: categories)
    }
}
