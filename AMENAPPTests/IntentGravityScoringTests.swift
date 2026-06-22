import Foundation
import Testing
@testable import AMENAPP

@Suite("Intent Gravity Scoring")
struct IntentGravityScoringTests {
    @Test("Surface score clamps into unit interval")
    func surfaceScoreClamps() {
        let entry = LivingEntry(
            userId: "user_1",
            type: .prayer,
            intent: .prayerCare,
            title: "Pray",
            body: "",
            priorityScore: 2,
            gravityScore: 2,
            spiritualWeight: 2,
            contextSnapshot: .current(sourceSurface: .home)
        )

        let score = LivingEntryContextEngine.evaluate(
            entry: entry,
            context: .current(
                appOpenedAfterInactivity: true,
                eveningHours: true,
                activeTyping: false,
                lowMotion: true
            )
        ).surfaceScore
        #expect(score >= 0)
        #expect(score <= 1)
    }
}
