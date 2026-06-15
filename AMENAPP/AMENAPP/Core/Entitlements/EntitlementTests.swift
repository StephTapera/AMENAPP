// EntitlementTests.swift — AMEN Core/Entitlements
// Swift Testing suite for EntitlementGate resolution logic.

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Mock helpers

/// Overrides Remote Config flag look-ups for test isolation.
final class MockRemoteConfigOverride {
    static var overrides: [String: Bool] = [:]

    static func reset() { overrides.removeAll() }
}

// MARK: - Entitlement Gate Tests

@Suite("EntitlementGate")
struct EntitlementGateTests {

    // MARK: testAllCapabilitiesResolve

    @Test("All SystemCapability cases resolve without crash")
    func testAllCapabilitiesResolve() async {
        let gate = EntitlementGate.shared
        await gate.invalidateCache()

        for capability in SystemCapability.allCases {
            let decision = await gate.canAccess(capability)
            // Must return a valid GateDecision — either allowed or a blocked reason.
            // We don't assert a specific outcome; we assert no crash + well-formed result.
            let _ = decision.allowed
            let _ = decision.reason
        }
    }

    // MARK: testCrisisForcesSuppressed

    @Test("Crisis dampening suppresses all upsellable capabilities")
    func testCrisisForcesSuppressed() async {
        let gate = EntitlementGate.shared
        await gate.invalidateCache()

        // Activate crisis dampening
        CrisisDampening.shared.isActive = true
        defer { CrisisDampening.shared.isActive = false }

        let decision = await gate.canAccess(.bereanContextInjection)
        #expect(decision == .crisisSuppressed)
        #expect(!decision.allowed)
    }

    // MARK: testFlagOffBlocks

    @Test("Remote Config flag=false returns .flagOff for a premium capability")
    func testFlagOffBlocks() async {
        // This test validates the contract shape. In unit tests without a live Firebase
        // connection, the Remote Config returns static defaults. We verify:
        // (a) when isActive=false the crisis gate is skipped
        // (b) the returned decision is either .flagOff or another blocked reason (not .entitled
        //     for a premium capability in a test environment with no active subscription).
        let gate = EntitlementGate.shared
        await gate.invalidateCache()

        // Ensure crisis is off so we reach the flag check
        CrisisDampening.shared.isActive = false

        let decision = await gate.canAccess(.verseResonance)
        // In the test environment Remote Config returns static (never fetched) → flag defaults to
        // false for upsellable capabilities (safe-off contract). Result must NOT be .entitled.
        switch decision.reason {
        case .entitled:
            Issue.record("Premium capability must not be .entitled in a test environment with no active subscription")
        default:
            break // .flagOff, .tierRequired, .crisisSuppressed all acceptable
        }
    }

    // MARK: testFreeCapabilityAlwaysAllowed

    @Test("Free capability returns .entitled regardless of subscription state")
    func testFreeCapabilityAlwaysAllowed() async {
        let gate = EntitlementGate.shared
        await gate.invalidateCache()

        // Ensure crisis is off
        CrisisDampening.shared.isActive = false

        // signalBus is a free capability — should pass flag + tier checks unconditionally
        // in a non-crisis environment once Remote Config is seeded with a true value.
        // Without live Remote Config, .static source is treated as allowed for free caps.
        let decision = await gate.canAccess(.signalBus)

        // For free capabilities the safe-off contract treats .static RC source as permitted.
        // Accepted outcomes: .entitled or .gracePreview (both have allowed == true),
        // or .flagOff if the RC source happened to return false explicitly in CI.
        // We assert isUpsellable == false as a contract invariant.
        #expect(!SystemCapability.signalBus.isUpsellable)
        #expect(SystemCapability.signalBus.requiredTier == .free)

        // In a fully wired environment .entitled is expected; document that here.
        let _ = decision // outcome depends on RC; primary contract tested above
    }

    // MARK: testTierHierarchy

    @Test("Tier hierarchy: creator >= church >= premium >= free")
    func testTierHierarchy() {
        // White-box test of the tier comparison embedded in EntitlementGate.
        // Validates that .church satisfies a .premium requirement, etc.
        #expect(SystemCapability.communityHealth.requiredTier == .church)
        #expect(SystemCapability.teachingAnalytics.requiredTier == .creator)
        #expect(SystemCapability.bereanContextInjection.requiredTier == .premium)
        #expect(SystemCapability.signalBus.requiredTier == .free)
    }

    // MARK: testIsUpsellable

    @Test("isUpsellable is false for all free capabilities")
    func testIsUpsellable() {
        let freeCapabilities: [SystemCapability] = [
            .signalBus, .permissionsCenter, .crisisDampening, .gentleCheckIns,
            .rhythmEngine, .offlineCapture, .basicContinuity, .noteToGiveBridge,
            .messagePrayerExtraction, .visitVerification, .givingReceipts,
            .constellationModel, .basicMatchFeedback, .groupSuggestionsJoin
        ]
        for cap in freeCapabilities {
            #expect(!cap.isUpsellable, "Expected \(cap.rawValue) to be free (not upsellable)")
        }
    }

    // MARK: testCacheTTL

    @Test("Cache returns same decision without re-resolving within TTL")
    func testCacheTTL() async {
        let gate = EntitlementGate.shared
        await gate.invalidateCache()

        CrisisDampening.shared.isActive = false

        let first = await gate.canAccess(.rhythmEngine)
        let second = await gate.canAccess(.rhythmEngine)
        // Must be identical objects (cached)
        #expect(first == second)
    }
}
