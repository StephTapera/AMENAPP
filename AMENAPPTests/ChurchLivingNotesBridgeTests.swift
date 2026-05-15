import Foundation
import Testing
@testable import AMENAPP

struct ChurchLivingNotesBridgeTests {
    @Test("Church living notes groups entries into the expected buckets")
    func groupsEntries() {
        let baseContext = LivingEntryContextSnapshot.current(sourceSurface: .churchNotes)
        let entries = [
            LivingEntry(userId: "u", type: .churchNote, intent: .sermonReflection, title: "Note", triggerRules: [], contextSnapshot: baseContext),
            LivingEntry(userId: "u", type: .prayer, intent: .prayerCare, title: "Prayer", triggerRules: [], contextSnapshot: baseContext),
            LivingEntry(userId: "u", type: .followUp, intent: .spiritualGrowth, title: "Action", triggerRules: [], contextSnapshot: baseContext),
            LivingEntry(userId: "u", type: .reflection, intent: .sermonReflection, state: .needsReflection, title: "Reflect", triggerRules: [], contextSnapshot: baseContext)
        ]
        let grouped = ChurchLivingNotesView.group(entries: entries)
        #expect(grouped.duringService.count == 1)
        #expect(grouped.afterService.count == 2)
        #expect(grouped.reflections.count == 1)
    }
}
