// SwiftDataMigrationSafetyTests.swift
// AMENAPPTests
//
// Documents the raw value strings that SwiftData uses as property-level defaults
// when migrating existing records to a new schema version.
//
// CRITICAL: If any raw value here changes, existing store records silently get wrong
// phase state after migration. These tests are the canary — they MUST pass before
// any deploy that touches LocalPostDraft or LocalSelahSession model fields.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

// MARK: - SwiftDataMigrationSafetyTests

@Suite("SwiftData migration safety")
struct SwiftDataMigrationSafetyTests {

    // MARK: LocalPostDraft — upload phase

    @Test("LocalPostDraftUploadPhase.idle raw value is 'idle'")
    func uploadPhaseIdleRawValue() {
        #expect(LocalPostDraftUploadPhase.idle.rawValue == "idle")
    }

    @Test("LocalPostDraft property-level default for uploadPhaseRawValue is 'idle'")
    func localPostDraftUploadPhaseDefault() {
        let draft = LocalPostDraft(userId: "migration-test")
        #expect(draft.uploadPhaseRawValue == "idle",
                "Property-level default must match 'idle' so migrated records start in a safe phase")
    }

    // MARK: LocalPostDraft — moderation phase

    @Test("LocalPostDraftModerationPhase.pending raw value is 'pending'")
    func moderationPhasePendingRawValue() {
        #expect(LocalPostDraftModerationPhase.pending.rawValue == "pending")
    }

    @Test("LocalPostDraft property-level default for moderationPhaseRawValue is 'pending'")
    func localPostDraftModerationPhaseDefault() {
        let draft = LocalPostDraft(userId: "migration-test")
        #expect(draft.moderationPhaseRawValue == "pending",
                "Property-level default must match 'pending' so migrated records are not falsely blocked")
    }

    // MARK: LocalSelahSession — phase

    @Test("LocalSelahSessionPhase.idle raw value is 'idle'")
    func selahPhaseIdleRawValue() {
        #expect(LocalSelahSessionPhase.idle.rawValue == "idle")
    }

    @Test("LocalSelahSession initialises phaseRawValue to 'idle'")
    func localSelahSessionPhaseDefault() {
        let session = LocalSelahSession(userId: "migration-test")
        #expect(session.phaseRawValue == "idle",
                "New sessions must start idle; migration relies on this string value")
    }

    // MARK: Round-trip invariants — enum ↔ rawValue

    @Test("All LocalPostDraftUploadPhase cases round-trip through rawValue")
    func uploadPhaseRoundTrip() {
        let cases: [LocalPostDraftUploadPhase] = [.idle, .uploading, .completed, .failed]
        for phase in cases {
            let recovered = LocalPostDraftUploadPhase(rawValue: phase.rawValue)
            #expect(recovered == phase, "Round-trip failed for phase: \(phase.rawValue)")
        }
    }

    @Test("All LocalPostDraftModerationPhase cases round-trip through rawValue")
    func moderationPhaseRoundTrip() {
        let cases: [LocalPostDraftModerationPhase] = [.pending, .passed, .blocked, .editRequired]
        for phase in cases {
            let recovered = LocalPostDraftModerationPhase(rawValue: phase.rawValue)
            #expect(recovered == phase, "Round-trip failed for moderation phase: \(phase.rawValue)")
        }
    }

    @Test("All LocalSelahSessionPhase cases round-trip through rawValue")
    func selahPhaseRoundTrip() {
        let cases: [LocalSelahSessionPhase] = [.idle, .preparing, .active, .paused, .completed, .failed]
        for phase in cases {
            let recovered = LocalSelahSessionPhase(rawValue: phase.rawValue)
            #expect(recovered == phase, "Round-trip failed for selah phase: \(phase.rawValue)")
        }
    }
}

#endif
