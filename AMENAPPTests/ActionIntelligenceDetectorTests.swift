import Foundation
import Testing
@testable import AMENAPP

@Suite("Action Intelligence Detector")
struct ActionIntelligenceDetectorTests {
    @Test("Prayer requests become need objects with prayer actions")
    func detectsPrayerNeed() throws {
        let analysis = try #require(ActionIntelligenceEngine.shared.analyzeText(
            "Please pray for my surgery tomorrow morning.",
            id: "msg-prayer-need",
            surface: .message
        ))

        #expect(analysis.intentKind == .prayerNeed)
        #expect(analysis.objectClass == .need)
        #expect(analysis.primaryActions.map(\.verb).contains(.prayNow))
        #expect(analysis.primaryActions.count <= 3)
        #expect(!analysis.shouldSuppressCapsule)
    }

    @Test("Scripture references surface verse study workflows")
    func detectsScriptureReference() throws {
        let analysis = try #require(ActionIntelligenceEngine.shared.analyzeText(
            "Romans 8:28 was on my heart today.",
            id: "msg-scripture",
            surface: .comment
        ))

        let verbs = analysis.allActions.map(\.verb)
        #expect(analysis.intentKind == .scriptureReference)
        #expect(verbs.contains(.saveVerse))
        #expect(verbs.contains(.compareTranslations))
    }

    @Test("Events surface calendar and RSVP workflows")
    func detectsEventMoment() throws {
        let analysis = try #require(ActionIntelligenceEngine.shared.analyzeText(
            "Men's breakfast Saturday at 8am in Tampa.",
            id: "msg-event",
            surface: .groupChat
        ))

        let verbs = analysis.allActions.map(\.verb)
        #expect(analysis.intentKind == .event)
        #expect(analysis.objectClass == .moment)
        #expect(verbs.contains(.addToCalendar))
        #expect(verbs.contains(.rsvp))
    }

    @Test("Collective help language becomes an initiative")
    func detectsInitiativeIdea() throws {
        let analysis = try #require(ActionIntelligenceEngine.shared.analyzeText(
            "We should do something for homeless families this winter.",
            id: "msg-initiative",
            surface: .amenRoom
        ))

        let verbs = analysis.allActions.map(\.verb)
        #expect(analysis.intentKind == .initiativeIdea)
        #expect(analysis.objectClass == .initiative)
        #expect(verbs.contains(.createInitiative))
        #expect(verbs.contains(.inviteLeaders))
    }

    @Test("Crisis-like content suppresses capsules and returns no actions")
    func suppressesCrisisCapsule() throws {
        let analysis = try #require(ActionIntelligenceEngine.shared.analyzeText(
            "I want to kill myself tonight.",
            id: "msg-crisis",
            surface: .directMessage
        ))

        #expect(analysis.shouldSuppressCapsule)
        #expect(analysis.primaryActions.isEmpty)
        #expect(analysis.secondaryActions.isEmpty)
    }
}
