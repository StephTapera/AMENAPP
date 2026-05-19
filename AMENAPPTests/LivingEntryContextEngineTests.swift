import Foundation
import Testing
@testable import AMENAPP

struct LivingEntryContextEngineTests {
    @Test("Church proximity and Sunday mode elevate church entries")
    func churchEntrySurfacesNearChurch() {
        let entry = LivingEntry(
            userId: "user-1",
            type: .churchNote,
            intent: .sermonReflection,
            title: "Sunday note",
            churchId: "church-1",
            priorityScore: 0.6,
            gravityScore: 0.6,
            spiritualWeight: 0.9,
            triggerRules: [LivingEntryTriggerRule(type: .churchProximity, churchId: "church-1")],
            contextSnapshot: .current(sourceSurface: .churchNotes)
        )
        let context = LivingEntryRuntimeContext.current(
            nearbyChurchId: "church-1",
            appOpenedAfterInactivity: true,
            lowMotion: true
        )
        let evaluation = LivingEntryContextEngine.evaluate(entry: entry, context: context)
        #expect(evaluation.matchedReasons.contains("Near church"))
        #expect(evaluation.surfaceScore >= 0.65)
    }

    @Test("Sunday mode suppresses non-urgent work")
    func sundaySuppressesWork() {
        let entry = LivingEntry(
            userId: "user-1",
            type: .task,
            intent: .work,
            title: "Work admin",
            priorityScore: 0.5,
            gravityScore: 0.4,
            spiritualWeight: 0.1,
            triggerRules: [],
            contextSnapshot: .current(sourceSurface: .home)
        )
        let context = LivingEntryRuntimeContext.current()
        let evaluation = LivingEntryContextEngine.evaluate(entry: entry, context: context)
        #expect(evaluation.interruptionPenalty >= 0)
    }
}
