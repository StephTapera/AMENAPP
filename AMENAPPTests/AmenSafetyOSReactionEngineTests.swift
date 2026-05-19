import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@Suite("Amen Safety OS Reaction Engine")
@MainActor
struct AmenSafetyOSReactionEngineTests {
    private let engine = AmenLocalTriggerEngine.shared

    @Test("Scripture and prayer can coexist")
    func scriptureAndPrayerCanCoexist() {
        let results = engine.analyze(text: "Psalm 139 helped me. Please pray for me.", surface: .comment)
        #expect(results.contains { $0.type == .scriptureReference })
        #expect(results.contains { $0.type == .prayerRequest })
    }

    @Test("Shame tone receives highest priority and opens discernment")
    func shameTonePriority() {
        let results = engine.analyze(text: "You should be ashamed of yourself. Psalm 139 says God knows us.", surface: .comment)
        #expect(results.first?.type == .shameTone)
        #expect(results.first?.shouldShowDiscernmentSheet == true)
        #expect(results.first?.recommendedActions.first == .editWithGrace)
    }

    @Test("Conflict tone opens discernment without blocking post anyway")
    func conflictToneAllowsPostAnyway() {
        let results = engine.analyze(text: "You always do this. I hate how this conversation goes.", surface: .reply)
        let conflict = results.first { $0.type == .conflictTone }
        #expect(conflict?.shouldShowDiscernmentSheet == true)
        #expect(conflict?.recommendedActions.contains(.postAnyway) == true)
    }

    @Test("Recommended reactions stay spiritual and non-metric")
    func recommendedReactions() {
        let triggers = engine.analyze(text: "Please pray for me this week.", surface: .post)
        let reactions = engine.recommendedReactions(for: triggers)
        #expect(reactions.first == .praying)
        #expect(reactions.contains(.heart))
    }
}
#endif
