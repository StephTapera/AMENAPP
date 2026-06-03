// BereanDailyFormationView.swift
// AMENAPP — Berean Daily Formation Companion
//
// Root view: shows onboarding on first launch, feed thereafter.
// @AppStorage key: "bereanFormationOnboardingDone"

import SwiftUI

struct BereanDailyFormationView: View {
    @AppStorage("bereanFormationOnboardingDone") private var onboardingDone = false
    @State private var prefs: BereanFormationPrefs? = nil
    @State private var cards: [BereanFormationCard] = []

    private let prayerList = BereanMockData.prayerList

    var body: some View {
        Group {
            if onboardingDone, let prefs {
                BereanDailyFormationFeedView(
                    userName: BereanMockUser.name,
                    cards: cards,
                    prayerList: prayerList
                )
                .onAppear { if cards.isEmpty { rebuildCards(prefs: prefs) } }
            } else {
                BereanFormationOnboardingView { result in
                    prefs = result
                    rebuildCards(prefs: result)
                    withAnimation { onboardingDone = true }
                }
            }
        }
    }

    private func rebuildCards(prefs: BereanFormationPrefs) {
        cards = BereanFormationService.assembleCards(
            readingPlan: BereanMockData.readingPlan,
            prayerList: prayerList,
            sanctuaries: BereanMockData.sanctuaries,
            highlights: BereanMockData.highlights,
            memoryVerses: BereanMockData.memoryVerses,
            seasonal: BereanMockData.seasonal,
            translationPref: BereanMockUser.translationPref,
            selectedTopics: prefs.selectedTopics
        )
    }
}

#Preview { BereanDailyFormationView() }
