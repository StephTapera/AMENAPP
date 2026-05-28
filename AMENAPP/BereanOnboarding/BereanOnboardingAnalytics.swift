// BereanOnboardingAnalytics.swift
// AMENAPP — Berean Onboarding
// Fire-and-forget analytics. Must never block flow progression.

import Foundation

@MainActor
final class BereanOnboardingDefaultAnalytics {

    func track(_ event: String, _ properties: [String: Any] = [:]) {
        let amenEvent: AMENAnalyticsEvent
        switch event {
        case BereanOnboardingEvent.started:
            amenEvent = .bereanOnboardingStarted
        case BereanOnboardingEvent.pageViewed:
            amenEvent = .bereanOnboardingPageViewed(page: properties["page"] as? String ?? "")
        case BereanOnboardingEvent.skipped:
            let raw = properties["from_page"]
            let fromPage = (raw as? String) ?? raw.map { "\($0)" } ?? ""
            amenEvent = .bereanOnboardingSkipped(fromPage: fromPage)
        case BereanOnboardingEvent.completed:
            amenEvent = .bereanOnboardingCompleted
        case BereanOnboardingEvent.welcomeBackShown:
            amenEvent = .bereanWelcomeBackShown
        default:
            return
        }
        AMENAnalyticsService.shared.track(amenEvent)
    }
}
