// BereanDailyFormationView.swift
// Root view: shows onboarding on first launch, feed thereafter.
// Real Firestore data loaded via BereanFormationDataService (consent-gated).
// Reading plan verse text requires YouVersion license — mock ONLY in DEBUG.

import SwiftUI
import FirebaseAuth

struct BereanDailyFormationView: View {

    @StateObject private var dataService = BereanFormationDataService.shared
    @AppStorage("bereanFormationOnboardingDone") private var onboardingDone = false

    private var currentUserName: String {
        Auth.auth().currentUser?.displayName ?? "Friend"
    }

    private var cards: [BereanFormationCard] {
        BereanFormationService.assembleCards(
            readingPlan: readingPlan,
            prayerList: dataService.prayerList,
            sanctuaries: dataService.sanctuaries,
            highlights: dataService.highlights,
            memoryVerses: dataService.memoryVerses,
            seasonal: BereanSeasonalRhythm.current(),
            translationPref: UserDefaults.standard.string(forKey: "bibleTranslationPref") ?? "ESV",
            selectedTopics: dataService.prefs.selectedTopics
        )
    }

    private var readingPlan: BereanReadingPlan {
        // Verse text from YouVersion requires a content license — mock in DEBUG only.
        // In release the verse card is omitted (selectedTopics controls this via the flag below).
#if DEBUG
        return BereanMockData.readingPlan
#else
        // Return a zero-progress plan; getVerse() will return an empty string that is
        // filtered by assembleCards when todayPassageRef is blank.
        return BereanReadingPlan(
            name: "", currentDay: 0, totalDays: 1,
            todayPassageRef: "", todayPassageRange: ""
        )
#endif
    }

    var body: some View {
        Group {
            if !onboardingDone {
                BereanFormationOnboardingView { prefs in
                    dataService.savePrefs(prefs)
                    onboardingDone = true
                    Task { await dataService.loadData() }
                }
            } else {
                BereanDailyFormationFeedView(
                    userName: currentUserName,
                    cards: cards,
                    prayerList: dataService.prayerList
                )
                .task { await dataService.loadData() }
            }
        }
    }
}

#Preview { BereanDailyFormationView() }
