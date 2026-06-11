// ContextStoreSecurityTests.swift
// AMEN Universal Migration & Context System — Wave 1 happy-path contract tests.
//
// The Firestore emulator harness (`FirebaseFirestoreEmulator`) is NOT a module in
// this project, so these are contract/unit tests over the ContextStoreService guards
// and the canonical factory/tier rules — the preferred form per the Wave 1 brief.
// Adversarial rules tests live in the rules-tester's emulator suite, not here.
//
// What is covered (happy path + the guards that keep the owner path honest):
//   - makeFacet derives the canonical tier, defaults to private, schemaVersion 1.
//   - The tier table is law (Tier C categories, Tier P relationships/family/health,
//     and the faith "areas needing support" Tier-P override).
//   - hasValidTier holds for factory-built facets.
//   - The master gate fails loudly when contextSystemEnabled is OFF (its default),
//     proving nothing is user-visible / persistable without the flag.
//   - Snapshot capture produces an immutable copy of the supplied facet states.
//   - ContextStoreError carries clear messages.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

// MARK: - Helpers

@MainActor
private enum ContextStoreFixtures {
    static let uid = "owner-uid-123"

    /// A verified provenance receipt (non-empty passId == Aegis C59 verified).
    static func approvedProvenance(
        approved: Bool = true,
        passId: String = "sanitize-pass-001"
    ) -> Provenance {
        Provenance(
            source: .manual,
            sourceLabel: nil,
            extractedAt: nil,
            confidence: nil,
            userApproved: approved,
            userEdited: false,
            sanitizationPassId: passId
        )
    }

    static func interestFacet() -> ContextFacet {
        ContextStoreService.shared.makeFacet(
            userId: uid,
            category: .interests,
            key: "interest.ai",
            label: "AI",
            value: .text("Artificial intelligence"),
            provenance: approvedProvenance()
        )
    }
}

// MARK: - Factory + tier law

@Suite("ContextStore — factory & tier law")
@MainActor
struct ContextStoreFactoryTests {

    @Test("makeFacet derives the canonical tier (interests → C)")
    func factoryDerivesTierC() {
        let facet = ContextStoreFixtures.interestFacet()
        #expect(facet.tier == .c)
        #expect(facet.hasValidTier)
    }

    @Test("makeFacet defaults visibility to private and schemaVersion to 1")
    func factoryDefaults() {
        let facet = ContextStoreFixtures.interestFacet()
        #expect(facet.visibility == .privateVisibility)
        #expect(facet.schemaVersion == 1)
        #expect(facet.schemaVersion == ContextStoreService.currentSchemaVersion)
    }

    @Test("Relationship facets are forced to Tier P")
    func relationshipsAreTierP() {
        let facet = ContextStoreService.shared.makeFacet(
            userId: ContextStoreFixtures.uid,
            category: .relationships,
            key: "relationship.mentors",
            label: "Mentors",
            value: .relationshipCategory(.init(category: .mentors, note: nil)),
            provenance: ContextStoreFixtures.approvedProvenance()
        )
        #expect(facet.tier == .p)
        #expect(facet.hasValidTier)
    }

    @Test("Faith 'areas needing support' override forces Tier P even within faith_journey")
    func faithSupportOverrideIsTierP() {
        let facet = ContextStoreService.shared.makeFacet(
            userId: ContextStoreFixtures.uid,
            category: .faith_journey,
            key: "faith.areas_needing_support",
            label: "Areas needing support",
            value: .list(["encouragement"]),
            provenance: ContextStoreFixtures.approvedProvenance()
        )
        #expect(facet.tier == .p)
        #expect(facet.hasValidTier)
    }

    @Test("General faith_journey facets remain Tier C")
    func faithGeneralIsTierC() {
        let facet = ContextStoreService.shared.makeFacet(
            userId: ContextStoreFixtures.uid,
            category: .faith_journey,
            key: "faith.current_study",
            label: "Current study",
            value: .text("Romans"),
            provenance: ContextStoreFixtures.approvedProvenance()
        )
        #expect(facet.tier == .c)
        #expect(facet.hasValidTier)
    }
}

// MARK: - Master gate

@Suite("ContextStore — master gate")
@MainActor
struct ContextStoreMasterGateTests {

    // contextSystemEnabled defaults to false; with the flag OFF every entry point
    // must fail loudly with .contextSystemDisabled before any Firestore/Auth work.

    @Test("saveFacet is gated behind contextSystemEnabled")
    func saveIsGated() async {
        guard !AMENFeatureFlags.shared.contextSystemEnabled else { return }
        await #expect(throws: ContextStoreError.contextSystemDisabled) {
            try await ContextStoreService.shared.saveFacet(ContextStoreFixtures.interestFacet())
        }
    }

    @Test("loadFacets is gated behind contextSystemEnabled")
    func loadIsGated() async {
        guard !AMENFeatureFlags.shared.contextSystemEnabled else { return }
        await #expect(throws: ContextStoreError.contextSystemDisabled) {
            _ = try await ContextStoreService.shared.loadFacets()
        }
    }

    @Test("takeSnapshot is gated behind contextSystemEnabled")
    func snapshotIsGated() async {
        guard !AMENFeatureFlags.shared.contextSystemEnabled else { return }
        await #expect(throws: ContextStoreError.contextSystemDisabled) {
            _ = try await ContextStoreService.shared.takeSnapshot(trigger: .manual)
        }
    }

    @Test("deleteFacet is gated behind contextSystemEnabled")
    func deleteIsGated() async {
        guard !AMENFeatureFlags.shared.contextSystemEnabled else { return }
        await #expect(throws: ContextStoreError.contextSystemDisabled) {
            try await ContextStoreService.shared.deleteFacet(id: UUID())
        }
    }
}

// MARK: - Snapshot model

@Suite("ContextStore — snapshot capture")
@MainActor
struct ContextStoreSnapshotTests {

    @Test("A snapshot is an immutable copy of the supplied facet states")
    func snapshotCapturesStates() {
        let facet = ContextStoreFixtures.interestFacet()
        let snapshot = ContextSnapshot(
            id: UUID(),
            userId: ContextStoreFixtures.uid,
            takenAt: Date(),
            trigger: .manual,
            facetStates: [facet],
            schemaVersion: ContextStoreService.currentSchemaVersion
        )
        #expect(snapshot.facetStates.count == 1)
        #expect(snapshot.facetStates.first == facet)
        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.userId == ContextStoreFixtures.uid)
    }

    @Test("Snapshot round-trips through Codable (owner-only persistence shape)")
    func snapshotCodableRoundTrip() throws {
        let facet = ContextStoreFixtures.interestFacet()
        let original = ContextSnapshot(
            id: UUID(),
            userId: ContextStoreFixtures.uid,
            takenAt: Date(timeIntervalSince1970: 1_000_000),
            trigger: .major_edit,
            facetStates: [facet],
            schemaVersion: 1
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ContextSnapshot.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - Errors

@Suite("ContextStore — error contract")
struct ContextStoreErrorTests {

    @Test("Every error exposes a non-empty description")
    func errorsHaveDescriptions() {
        let cases: [ContextStoreError] = [
            .contextSystemDisabled,
            .notSignedIn,
            .invalidTier(expected: .c, actual: .p),
            .notApproved,
            .sanitizationFailed,
            .ownerMismatch,
            .invalidSchemaVersion(2)
        ]
        for c in cases {
            #expect(!(c.errorDescription ?? "").isEmpty)
        }
    }
}

#endif
