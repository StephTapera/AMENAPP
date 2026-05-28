// BereanOnboardingAnalytics.swift
// AMENAPP — Berean Onboarding
// Fire-and-forget analytics. Must never block flow progression.

import Foundation

final class BereanOnboardingDefaultAnalytics {

    func track(_ event: String, _ properties: [String: Any]) {
        // TODO: Replace with AMENAnalyticsService.shared.track(event, properties: properties)
        #if DEBUG
        print("[BereanAnalytics] \(event) \(properties)")
        #endif
    }
}
