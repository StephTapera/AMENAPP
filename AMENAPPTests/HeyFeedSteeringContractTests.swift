import Testing
import Foundation
@testable import AMENAPP

@Suite("HeyFeed v2 Steering — contract parity & invariants")
struct HeyFeedSteeringContractTests {

    // MARK: - Clamp parity with TS STEER_CLAMP

    @Test("Clamp constant mirrors STEER_CLAMP = 0.35")
    func clampConstant() {
        #expect(SteeringBounds.clamp == 0.35)
    }

    @Test("clampSteering bounds aggregate delta to ±0.35")
    func clampBounds() {
        #expect(SteeringBounds.clampSteering(0.9) == 0.35)
        #expect(SteeringBounds.clampSteering(-0.9) == -0.35)
        #expect(SteeringBounds.clampSteering(0.1) == 0.1)
        #expect(SteeringBounds.clampSteering(0) == 0)
    }

    // MARK: - SafetyFloor wins over any boost

    @Test("A floor block wins over any positive steering — preference cannot override safety")
    func floorWinsOverBoost() {
        // A post implicated in a hardBlock floor (csam) with any risk above ceiling is blocked,
        // regardless of the viewer's chosen filter or any steering preference.
        var safety = PostSafetyMetadata()
        safety.riskScore = 0.95
        safety.riskReasons = [.harassment]

        let verdict = SafetyFloorEngine.gate(
            postId: "p1",
            safety: safety,
            viewerFilter: .off,     // user chose the laxest filter
            viewerIsMinor: false
        )
        #expect(verdict.allowed == false)
        #expect(verdict.appliedFloor == .harassment)
    }

    @Test("User threshold may only go stricter, never laxer than the floor ceiling")
    func effectiveThresholdNarrowsOnly() {
        #expect(SteeringBounds.effectiveRiskThreshold(userThreshold: 0.9, ceilingRisk: 0.3) == 0.3)
        #expect(SteeringBounds.effectiveRiskThreshold(userThreshold: 0.1, ceilingRisk: 0.3) == 0.1)
    }

    @Test("Minor viewer is forced to strict regardless of chosen filter")
    func minorForcedStrict() {
        var safety = PostSafetyMetadata()
        safety.riskScore = 0.5   // clears .off (0.9) and .balanced (0.6), but not .strict (0.3)
        safety.riskReasons = []

        let verdict = SafetyFloorEngine.gate(
            postId: "p2",
            safety: safety,
            viewerFilter: .off,    // would normally allow 0.5
            viewerIsMinor: true    // forced to strict (0.3) => blocked
        )
        #expect(verdict.allowed == false)
        #expect(verdict.isMinorShielded == true)
    }

    @Test("Fail-closed: unevaluable post never surfaces")
    func failClosed() {
        let verdict = SafetyFloorEngine.gate(
            postId: "p3",
            safety: nil,
            viewerFilter: .balanced,
            viewerIsMinor: false
        )
        #expect(verdict.allowed == false)
        #expect(verdict.reasons.contains("unevaluable"))
    }

    @Test("A clean post under threshold is allowed")
    func cleanPostAllowed() {
        var safety = PostSafetyMetadata()
        safety.riskScore = 0.1
        safety.riskReasons = []

        let verdict = SafetyFloorEngine.gate(
            postId: "p4",
            safety: safety,
            viewerFilter: .balanced,
            viewerIsMinor: false
        )
        #expect(verdict.allowed == true)
    }

    // MARK: - Forbidden steering targets

    @Test("Every SafetyFloor category is a forbidden steering target")
    func forbiddenTargets() {
        for category in SafetyFloorCategory.allCases {
            let target = SteeringTarget(id: category.rawValue, type: .topic, label: category.rawValue)
            #expect(SteeringBounds.isFloorTargetForbidden(target) == true)
        }
    }

    @Test("An ordinary topic is not forbidden")
    func benignTargetAllowed() {
        let target = SteeringTarget(id: "testimonies", type: .topic, label: "Testimonies")
        #expect(SteeringBounds.isFloorTargetForbidden(target) == false)
    }

    // MARK: - Composer additive + clamped; base score unchanged

    @Test("Composer leaves baseScore untouched and clamps the aggregate delta")
    func composerClampsAndPreservesBase() {
        let target = SteeringTarget(id: "testimonies", type: .topic, label: "Testimonies")
        // Two strong boosts that would exceed the clamp in aggregate.
        let entries = [
            makeEntry(verb: .moreOf, target: target, strength: 1.0),
            makeEntry(verb: .prioritize, target: target, strength: 1.0),
        ]
        let result = SteeringComposer.compose(postId: "p5", baseScore: 100, matchedEntries: entries)

        #expect(result.baseScore == 100)               // scorer output unchanged
        #expect(result.steeringDelta == 0.35)            // aggregate clamped
        #expect(result.signals.contains { $0.kind == .userSteering })
        #expect(result.finalScore > result.baseScore)    // boost moved it up
    }

    @Test("Composer refuses to boost a forbidden floor target")
    func composerRefusesForbiddenBoost() {
        let target = SteeringTarget(id: "violence", type: .tone, label: "violence")
        let entries = [makeEntry(verb: .moreOf, target: target, strength: 1.0)]
        let result = SteeringComposer.compose(postId: "p6", baseScore: 100, matchedEntries: entries)

        #expect(result.steeringDelta == 0)               // no boost applied
        #expect(result.finalScore == 100)                // base unchanged
    }

    @Test("Inactive / paused entries contribute nothing")
    func inactiveEntriesIgnored() {
        let target = SteeringTarget(id: "testimonies", type: .topic, label: "Testimonies")
        var entry = makeEntry(verb: .moreOf, target: target, strength: 1.0)
        entry.active = false
        let result = SteeringComposer.compose(postId: "p7", baseScore: 100, matchedEntries: [entry])
        #expect(result.steeringDelta == 0)
    }

    // MARK: - Verb bridge to v1

    @Test("SteeringVerb.nlAction bridges to v1 HeyFeedNLAction")
    func verbBridge() {
        #expect(SteeringVerb.moreOf.nlAction == .increase)
        #expect(SteeringVerb.lessOf.nlAction == .decrease)
        #expect(SteeringVerb.mute.nlAction == .mute)
        #expect(SteeringVerb.explore.nlAction == .explore)
        #expect(SteeringVerb.reset.nlAction == .balance)
        #expect(SteeringVerb.prioritize.nlAction == .increase)
    }

    // MARK: - Helpers

    private func makeEntry(
        verb: SteeringVerb,
        target: SteeringTarget,
        strength: Double
    ) -> PreferenceVocabularyEntry {
        PreferenceVocabularyEntry(
            id: UUID().uuidString,
            verb: verb,
            target: target,
            strength: strength,
            duration: .session,
            source: .explicitControl,
            active: true,
            paused: false,
            createdAt: Date(),
            expiresAt: nil
        )
    }
}
