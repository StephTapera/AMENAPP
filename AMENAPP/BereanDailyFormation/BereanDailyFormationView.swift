// BereanDailyFormationView.swift
// AMENAPP — Berean Daily Formation Companion
//
// Root view: shows onboarding on first launch, feed thereafter.
// @AppStorage key: "bereanFormationOnboardingDone"

import SwiftUI

struct BereanDailyFormationView: View {

    private static let allTopics: Set<String> = ["verse", "plan", "prayer", "sanctuary", "study", "memory", "seasonal"]
    // AUDIT GAP: allConsents hardcodes all integrations as enabled, bypassing the
    // consent collected in BereanFormationOnboardingView. The onboarding result
    // (BereanFormationPrefs) must be persisted (e.g. UserDefaults / Firestore) and
    // read here so that prayerList / sanctuary data is only included when the user
    // actually granted consent for those integrations. Until that wiring exists,
    // cards are assembled as if all consents are true regardless of user choice.
    private static let allConsents: [String: Bool] = ["youversion": true, "sanctuary": true, "prayerlist": true, "notifications": true]

    // AUDIT GAP: prayerList is sourced from BereanMockData in production. A real
    // Firestore fetch (users/{uid}/prayerItems) gated on consents["prayerlist"] == true
    // must replace this before shipping. Shipping mock prayer data risks confusing
    // users and exposes the mock placeholder text in a released build.
    private let prayerList = BereanMockData.prayerList

    // AUDIT GAP: assembleCards() is called unconditionally with BereanMockData.
    // In production this data must come from Firestore / YouVersion API, and each
    // data source must be gated on the corresponding consent flag. The mock path
    // must be compiled out with #if DEBUG or a Remote Config feature flag.
    private var cards: [BereanFormationCard] {
        BereanFormationService.assembleCards(
            readingPlan: BereanMockData.readingPlan,
            prayerList: prayerList,
            sanctuaries: BereanMockData.sanctuaries,
            highlights: BereanMockData.highlights,
            memoryVerses: BereanMockData.memoryVerses,
            seasonal: BereanMockData.seasonal,
            translationPref: BereanMockUser.translationPref,
            selectedTopics: Self.allTopics
        )
    }

    var body: some View {
        BereanDailyFormationFeedView(
            userName: BereanMockUser.name,
            cards: cards,
            prayerList: prayerList
        )
    }
}

#Preview { BereanDailyFormationView() }
