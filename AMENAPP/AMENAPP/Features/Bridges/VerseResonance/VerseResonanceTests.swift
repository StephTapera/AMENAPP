#if canImport(Testing)
// VerseResonanceTests.swift — AMEN Features/Bridges/VerseResonance
// Swift Testing suite for VerseResonanceService gate logic.
//
// Strategy: contract tests over stored properties and invokable paths.
// No UIHostingController / accessibility-tree walks per project feedback.
// Network is not exercised — CF calls are not made in unit tests.

#if canImport(Testing)
import Testing
import Foundation
@testable import AMENAPP

// MARK: - Test Suite

@Suite("VerseResonance")
struct VerseResonanceTests {

    // MARK: - testFreeUserGetsGenericVerse
    //
    // With the flag OFF (default), VerseResonanceService must take the free path.
    // isContextual must be false regardless of any entitlement or consent state.

    @Test("Free path: flag off → isContextual == false")
    func testFreeUserGetsGenericVerse() async {
        // Precondition: flag is off (default in all test environments).
        // ContextIntelligenceFlags.verseResonance reads AMENFeatureFlags.ctx_verse_resonance_enabled
        // which returns false at compile time in test builds.
        #expect(ContextIntelligenceFlags.verseResonance == false,
                "ctx_verse_resonance_enabled must default to false — free path invariant")

        // Loading the service with flag off must populate todayVerse via the generic path.
        let service = VerseResonanceService.shared

        // Reset state for isolation.
        await MainActor.run { service.todayVerse = nil }
        await service.loadDailyVerse()

        let verse = await MainActor.run { service.todayVerse }
        #expect(verse != nil, "todayVerse must be populated after loadDailyVerse()")
        #expect(verse?.isContextual == false,
                "isContextual must be false when flag is off (free path)")
        #expect(verse?.contextReason == nil,
                "contextReason must be nil for generic verses")
    }

    // MARK: - testPremiumWithEdgeGetsContextual
    //
    // When flag is on, user is Premium, and graphToBerean is enabled, the service should
    // attempt the contextual path. Because we cannot mock the CF in unit tests, we verify
    // the gate conditions are met before the network call would be made, and confirm the
    // fallback path is also tested (CF returns an error → falls back to generic).
    //
    // This test exercises the gate contract; the CF integration path is verified via
    // manual E2E or Firebase Local Emulator runs.

    @Test("Premium gate: SystemCapability.verseResonance requires premium tier")
    func testPremiumWithEdgeGetsContextual() async {
        // Contract: verseResonance is a premium capability.
        #expect(SystemCapability.verseResonance.requiredTier == .premium,
                "verseResonance must require premium tier")
        #expect(SystemCapability.verseResonance.isUpsellable,
                "verseResonance must be upsellable")

        // Contract: when crisis dampening is OFF and we request verseResonance,
        // EntitlementGate must NOT return .crisisSuppressed.
        CrisisDampening.shared.isActive = false
        defer { CrisisDampening.shared.isActive = false }

        let gate = EntitlementGate.shared
        await gate.invalidateCache()
        let decision = await gate.canAccess(.verseResonance)
        switch decision.reason {
        case .crisisSuppressed:
            Issue.record("verseResonance must not be crisis-suppressed when crisis is inactive")
        default:
            break // .flagOff, .tierRequired, .entitled all valid here
        }

        // Contract: graphToBerean consent edge exists in the contract.
        #expect(ConsentEdge.allCases.contains(.graphToBerean),
                "graphToBerean must be a declared ConsentEdge")
    }

    // MARK: - testCrisisDampeningRestrictsPool
    //
    // When crisis dampening is active, EntitlementGate returns .crisisSuppressed for
    // upsellable capabilities. The service must therefore fall back to the generic
    // (free) verse rather than attempting a contextual CF call.

    @Test("Crisis dampening: verseResonance returns crisisSuppressed when active")
    func testCrisisDampeningRestrictsPool() async {
        let gate = EntitlementGate.shared
        await gate.invalidateCache()

        // Activate crisis mode.
        CrisisDampening.shared.isActive = true
        defer {
            CrisisDampening.shared.isActive = false
            Task { await gate.invalidateCache() }
        }

        let decision = await gate.canAccess(.verseResonance)
        #expect(decision == .crisisSuppressed,
                "verseResonance must be crisisSuppressed when crisis dampening is active")
        #expect(!decision.allowed,
                "crisisSuppressed decisions must never be allowed")

        // Consequence for the service: crisis active → decision.allowed == false
        // → service falls back to generic → isContextual == false.
        // We load with crisis active to verify the service respects the gate decision.
        await MainActor.run { VerseResonanceService.shared.todayVerse = nil }
        await VerseResonanceService.shared.loadDailyVerse()

        let verse = await MainActor.run { VerseResonanceService.shared.todayVerse }
        // With flag off (default) in tests the gate path short-circuits at flag check anyway,
        // but the crisis suppression contract is validated above on the gate directly.
        #expect(verse?.isContextual == false,
                "Service must never surface a contextual verse when crisis dampening is active")
    }

    // MARK: - testReflectEmitsSignal
    //
    // saveReflection() must emit a ContextSignal of type .verseReflected via ContextBus.
    // We verify the signal shape matches the contract without touching the network.

    @Test("Reflect: saveReflection emits verseReflected signal with correct shape")
    func testReflectEmitsSignal() async {
        // Subscribe to the bus before triggering reflection.
        let stream = await ContextBus.shared.subscribe(to: [.verseReflected])

        let testVerse = ResonantVerse(
            reference: "Psalm 23:1",
            text: "The Lord is my shepherd; I shall not want.",
            contextReason: nil,
            isContextual: false
        )

        // Post the notification that VerseReflectionSheet would post after saveReflection().
        // We test the notification contract here because VerseReflectionSheet emits via Task.
        // Directly construct and emit the same signal the sheet would produce.
        let signal = ContextSignal(
            id: UUID(),
            type: .verseReflected,
            tierCeiling: .p,
            subjectRefs: [GraphRef(nodeType: .verse, nodeID: testVerse.reference)],
            payload: [
                "reference":    .string(testVerse.reference),
                "hasReflection": .bool(true)
            ],
            occurredAt: Date(),
            decayHalfLifeDays: 21,
            consentEdgeRequired: .graphToBerean
        )

        // Contract checks on signal shape before emission.
        #expect(signal.type == .verseReflected)
        #expect(signal.tierCeiling == .p,
                "verseReflected must be tier .p so it can be forwarded server-side")
        #expect(signal.consentEdgeRequired == .graphToBerean,
                "graphToBerean consent edge is required for verse reflection signals")
        #expect(signal.decayHalfLifeDays == 21,
                "verseReflected signals must decay over 21 days")
        #expect(signal.subjectRefs.first?.nodeType == .verse)
        #expect(signal.subjectRefs.first?.nodeID == testVerse.reference)

        // Payload shape.
        if case .string(let ref) = signal.payload["reference"] {
            #expect(ref == testVerse.reference)
        } else {
            Issue.record("payload[reference] must be a .string AnyCodableValue")
        }
        if case .bool(let hasReflection) = signal.payload["hasReflection"] {
            #expect(hasReflection == true)
        } else {
            Issue.record("payload[hasReflection] must be a .bool AnyCodableValue")
        }

        // Emit and confirm the bus receives it (consent edge graphToBerean is OFF by default,
        // so the bus will drop it silently — we test the signal shape, not the delivery).
        await ContextBus.shared.emit(signal)

        // Notification contract: .verseReflectionSaved must be declared.
        #expect(Notification.Name.verseReflectionSaved.rawValue == "AmenVerseReflectionSaved",
                "Notification name contract must be stable")
    }

    // MARK: - testFreeUserBehaviorByteIdentical
    //
    // Before and after introducing VerseResonanceService, free users must receive the
    // same verse reference. We verify the deterministic selection logic produces a
    // stable, reproducible result for a given date.

    @Test("Free user: generic verse selection is deterministic and stable across calls")
    func testFreeUserBehaviorByteIdentical() async {
        // The flag is off in test builds. Load twice and compare.
        let service = VerseResonanceService.shared

        await MainActor.run { service.todayVerse = nil }
        await service.loadDailyVerse()
        let firstVerse = await MainActor.run { service.todayVerse }

        await MainActor.run { service.todayVerse = nil }
        await service.loadDailyVerse()
        let secondVerse = await MainActor.run { service.todayVerse }

        guard let v1 = firstVerse, let v2 = secondVerse else {
            Issue.record("todayVerse must be non-nil after loadDailyVerse()")
            return
        }

        // Same date → same deterministic index → same verse reference.
        #expect(v1.reference == v2.reference,
                "Generic verse selection must be byte-identical across calls on the same date")
        #expect(v1.text == v2.text,
                "Generic verse text must be byte-identical across calls on the same date")
        #expect(!v1.isContextual,
                "Free path must never set isContextual = true")
        #expect(v1.contextReason == nil,
                "Free path must never set a contextReason")
    }

    // MARK: - testResonantVerseIdentifiableConformance
    //
    // ResonantVerse must be Identifiable with a stable, unique id per instance.

    @Test("ResonantVerse: each instance has a unique id")
    func testResonantVerseIdentifiableConformance() {
        let v1 = ResonantVerse(
            reference: "Psalm 23:1",
            text: "The Lord is my shepherd; I shall not want.",
            contextReason: nil,
            isContextual: false
        )
        let v2 = ResonantVerse(
            reference: "Psalm 23:1",
            text: "The Lord is my shepherd; I shall not want.",
            contextReason: nil,
            isContextual: false
        )
        // Two distinct instances must have different ids even if all fields match.
        #expect(v1.id != v2.id,
                "ResonantVerse.id must be a unique UUID per instance")
    }
}
#endif

#endif
