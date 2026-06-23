import Testing
@testable import AMENAPP

// GovernanceRedLineTests — Swift-side red lines (Wave 6).
//
// Mirrors the TS red-line suite for the iOS governance surfaces:
//   - AMENFeatureFlagGovernance (invariant 6: default-OFF + sign-off gate)
//   - BereanConstitutionalConfig governance helpers (invariants 3, 4, 8)
//
// NOTE: this is a NEW file — it must be added to the AMENAPPTests target
// membership before it will compile/run (synced-folder caveat). Build is
// HUMAN-PENDING per the build-broker doctrine.

struct GovernanceRedLineTests {

    // ── Invariant 6 — safety-critical flags cannot be enabled without sign-off ──

    @Test func safetyCriticalFlagsCannotBeEnabledWithoutSignOff() {
        for key in AMENFeatureFlagGovernance.safetyCriticalSignOffs.keys {
            #expect(AMENFeatureFlagGovernance.canEnable(key) == false)
        }
    }

    @Test func effectiveEnabledForcesOffEvenWhenRemoteConfigSaysOn() {
        #expect(AMENFeatureFlagGovernance.effectiveEnabled("csam_hash_scan_enabled", remoteConfigValue: true) == false)
    }

    @Test func nonSafetyCriticalFlagHonorsRemoteConfig() {
        #expect(AMENFeatureFlagGovernance.effectiveEnabled("some_standard_flag", remoteConfigValue: true) == true)
        #expect(AMENFeatureFlagGovernance.canEnable("some_standard_flag") == true)
    }

    @Test func csamClassFlagsAreTrackedAsCsamClass() {
        #expect(AMENFeatureFlagGovernance.csamClassFlags.contains("csam_hash_scan_enabled"))
        #expect(AMENFeatureFlagGovernance.csamClassFlags.contains("connect_kids_facial_verification"))
    }

    // ── Invariant 3 — Companion Boundary helper ─────────────────────────────────

    @Test func detectsCompanionBoundaryViolation() {
        let c = BereanConstitutionalConfig.shared
        #expect(c.violatesCompanionBoundary("Just keep talking to me, you don't need anyone else."))
        #expect(c.violatesCompanionBoundary("Please bring this to your pastor and to God.") == false)
    }

    // ── Invariant 4 — red lines present ─────────────────────────────────────────

    @Test func sevenRedLinesAreCodified() {
        #expect(BereanConstitutionalConfig.shared.redLineIDs.count == 7)
    }

    // ── Invariant 8 — founder rulings immutable ─────────────────────────────────

    @Test func founderRulingsAreNotTampered() {
        #expect(BereanConstitutionalConfig.shared.tamperedFounderRulings.isEmpty)
    }
}
