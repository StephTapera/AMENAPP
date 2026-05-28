// BereanOnboardingModels.swift
// AMENAPP — Berean Onboarding
// Domain models for the 3-page Berean first-run experience.

import SwiftUI

// MARK: - Page

enum BereanOnboardingPage: Int, CaseIterable, Identifiable {
    case meetBerean = 0
    case howItAdapts = 1
    case groundedAndTrustworthy = 2

    var id: Int { rawValue }
    var isLast: Bool { self == .groundedAndTrustworthy }

    var analyticsName: String {
        switch self {
        case .meetBerean:             return "meet_berean"
        case .howItAdapts:            return "how_it_adapts"
        case .groundedAndTrustworthy: return "grounded_and_trustworthy"
        }
    }
}

// MARK: - Mode Cards (Page 2)

struct BereanMode: Identifiable {
    let id: String
    let systemIcon: String
    let name: String
    let description: String
}

extension BereanMode {
    static let all: [BereanMode] = [
        BereanMode(
            id: "scripture",
            systemIcon: "book.pages",
            name: "Scripture",
            description: "Explore passages with context, commentary, and cross-references."
        ),
        BereanMode(
            id: "prayer",
            systemIcon: "hands.and.sparkles",
            name: "Prayer",
            description: "Spirit-led conversations for prayer and quiet reflection."
        ),
        BereanMode(
            id: "deep_study",
            systemIcon: "magnifyingglass.circle",
            name: "Deep Study",
            description: "Theology, history, and scholarly insight on any passage."
        ),
        BereanMode(
            id: "translation",
            systemIcon: "character.bubble",
            name: "Translation",
            description: "Real-time Scripture translation across 30+ languages."
        ),
        BereanMode(
            id: "catch_up",
            systemIcon: "bolt.horizontal.circle",
            name: "Catch-Up",
            description: "Smart summaries so you never miss a group discussion."
        )
    ]
}

// MARK: - Analytics events (used by BereanOnboardingAnalytics)

struct BereanOnboardingEvent {
    static let started    = "berean_onboarding_started"
    static let pageViewed = "berean_onboarding_page_viewed"
    static let skipped    = "berean_onboarding_skipped"
    static let completed  = "berean_onboarding_completed"
    static let welcomeBackShown = "berean_welcome_back_shown"
}
