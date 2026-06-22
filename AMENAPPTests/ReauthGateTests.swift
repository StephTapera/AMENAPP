// ReauthGateTests.swift
// AMEN — THRESHOLD W3 Tests
//
// Tests cover DefaultReauthPolicy.requirement(switchingTo:) only.
// LocalAuthentication flows (ReauthGate.evaluate) are not tested here because
// LAContext cannot be mocked without a dependency-injection seam (planned for W5).

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Test Suite

@Suite("ReauthGate — DefaultReauthPolicy")
struct ReauthGateTests {

    // MARK: - Helpers

    private let policy = DefaultReauthPolicy()

    /// Builds a minimal `ProfileDescriptor` with the given capability set.
    /// All non-capability fields are stable stubs so tests are readable.
    private func makeProfile(capabilities: Set<ProfileCapability>) -> ProfileDescriptor {
        ProfileDescriptor(
            id: UUID().uuidString,
            identityId: "identity-test",
            type: .personal,
            handle: "test_handle",
            displayName: "Test Profile",
            avatarRef: nil,
            trustTier: .established,
            capabilities: capabilities,
            e2eeKeyRef: nil
        )
    }

    // MARK: - Tests

    /// Spec §6: post + dm only → no step-up required.
    @Test("post and dm only → .none")
    func testPostDMRequiresNoAuth() {
        let profile = makeProfile(capabilities: [.post, .dm])
        let req = policy.requirement(switchingTo: profile)
        #expect(req == .none)
    }

    /// Spec §6: post alone → no step-up required.
    @Test("post only → .none")
    func testPostOnlyRequiresNoAuth() {
        let profile = makeProfile(capabilities: [.post])
        let req = policy.requirement(switchingTo: profile)
        #expect(req == .none)
    }

    /// Spec §6: empty capability set → no step-up required.
    @Test("empty capabilities → .none")
    func testEmptyCapabilitiesRequiresNoAuth() {
        let profile = makeProfile(capabilities: [])
        let req = policy.requirement(switchingTo: profile)
        #expect(req == .none)
    }

    /// Spec §6: moderate → biometricOrPasscode.
    @Test("moderate → .biometricOrPasscode")
    func testModerateRequiresBiometric() {
        let profile = makeProfile(capabilities: [.moderate])
        let req = policy.requirement(switchingTo: profile)
        #expect(req == .biometricOrPasscode)
    }

    /// Spec §6: orgAdmin → biometricOrPasscode.
    @Test("orgAdmin → .biometricOrPasscode")
    func testOrgAdminRequiresBiometric() {
        let profile = makeProfile(capabilities: [.orgAdmin])
        let req = policy.requirement(switchingTo: profile)
        #expect(req == .biometricOrPasscode)
    }

    /// Spec §6: guardianTools → biometricOrPasscodeAndRecentAuth(maxAge: 300).
    @Test("guardianTools → .biometricOrPasscodeAndRecentAuth(maxAge: 300)")
    func testGuardianToolsMaxAge300() {
        let profile = makeProfile(capabilities: [.guardianTools])
        let req = policy.requirement(switchingTo: profile)
        #expect(req == .biometricOrPasscodeAndRecentAuth(maxAge: 300))
    }

    /// Spec §6: keyManagement → biometricOrPasscodeAndRecentAuth(maxAge: 120).
    @Test("keyManagement → .biometricOrPasscodeAndRecentAuth(maxAge: 120)")
    func testKeyManagementMaxAge120() {
        let profile = makeProfile(capabilities: [.keyManagement])
        let req = policy.requirement(switchingTo: profile)
        #expect(req == .biometricOrPasscodeAndRecentAuth(maxAge: 120))
    }

    /// Most-restrictive-wins rule: keyManagement (120 s) beats guardianTools (300 s).
    @Test("guardianTools + keyManagement → .biometricOrPasscodeAndRecentAuth(maxAge: 120)")
    func testMostRestrictiveWins() {
        let profile = makeProfile(capabilities: [.guardianTools, .keyManagement])
        let req = policy.requirement(switchingTo: profile)
        // keyManagement has the shorter maxAge, so it must win.
        #expect(req == .biometricOrPasscodeAndRecentAuth(maxAge: 120))
    }

    /// Elevated capability dominates non-elevated: post + dm + moderate → biometricOrPasscode.
    @Test("post + dm + moderate → .biometricOrPasscode (elevated wins)")
    func testMixedElevatedAndNonElevated() {
        let profile = makeProfile(capabilities: [.post, .dm, .moderate])
        let req = policy.requirement(switchingTo: profile)
        #expect(req == .biometricOrPasscode)
    }

    /// All elevated caps together: keyManagement should still be the decisive tier.
    @Test("all elevated caps → .biometricOrPasscodeAndRecentAuth(maxAge: 120)")
    func testAllElevatedCapsKeyManagementWins() {
        let profile = makeProfile(capabilities: [.moderate, .orgAdmin, .guardianTools, .keyManagement])
        let req = policy.requirement(switchingTo: profile)
        #expect(req == .biometricOrPasscodeAndRecentAuth(maxAge: 120))
    }

    /// guardianTools + orgAdmin: guardianTools (300 s) beats biometricOrPasscode.
    @Test("guardianTools + orgAdmin → .biometricOrPasscodeAndRecentAuth(maxAge: 300)")
    func testGuardianToolsBeatsOrgAdmin() {
        let profile = makeProfile(capabilities: [.guardianTools, .orgAdmin])
        let req = policy.requirement(switchingTo: profile)
        #expect(req == .biometricOrPasscodeAndRecentAuth(maxAge: 300))
    }

    /// orgAdmin + moderate together: both map to biometricOrPasscode — result is same tier.
    @Test("orgAdmin + moderate → .biometricOrPasscode")
    func testOrgAdminAndModerate() {
        let profile = makeProfile(capabilities: [.orgAdmin, .moderate])
        let req = policy.requirement(switchingTo: profile)
        #expect(req == .biometricOrPasscode)
    }
}
