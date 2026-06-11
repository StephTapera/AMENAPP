// ContextContractIntegrityTests.swift
// AMEN Universal Migration & Context System — CONTRACT TRIPWIRE
//
// Purpose: make the "frozen contract got truncated" failure class impossible to miss.
// A duplicate mission once overwrote ContextStoreModels.swift down to 2 lines, silently
// breaking the whole module; it was only caught by a file-change reminder. This test
// catches it in EVERY suite pass, in minutes:
//
//  1. COMPILE-TIME tripwire — this file references every canonical type and key case.
//     If any of EncryptionTier / ContextFacet / StructuredFacetValue / ContextTierTable /
//     ContextSnapshot is deleted or renamed, the TEST TARGET FAILS TO COMPILE. Loud.
//
//  2. RUNTIME tripwire — locates the repo via #filePath and asserts the source/contract
//     files still declare the canonical type set and that CONTRACTS.md exceeds its known
//     minimum length. (XCTSkip when the files aren't reachable, e.g. a sandboxed CI run,
//     so this never false-fails — but on a local run a truncation fails hard.)

import XCTest
@testable import AMENAPP

final class ContextContractIntegrityTests: XCTestCase {

    // MARK: 1. Compile-time tripwire (presence of the canonical type set)

    func testCanonicalTypesExistAtCompileTime() {
        // EncryptionTier — 3 tiers.
        XCTAssertEqual(EncryptionTier.s.rawValue, "S")
        XCTAssertEqual(EncryptionTier.c.rawValue, "C")
        XCTAssertEqual(EncryptionTier.p.rawValue, "P")

        // ContextTierTable — the law. Sensitive categories map to P; confidential to C.
        XCTAssertEqual(ContextTierTable.tier(for: .interests), .c)
        XCTAssertEqual(ContextTierTable.tier(for: .relationships), .p)
        XCTAssertEqual(ContextTierTable.tier(for: .family), .p)
        XCTAssertEqual(ContextTierTable.tier(for: .health), .p)
        XCTAssertEqual(ContextTierTable.tier(for: .faith_journey), .c)
        XCTAssertEqual(ContextTierTable.tier(for: .faith_journey,
                                             key: "faith.journey.areas_needing_support"), .p)
        XCTAssertFalse(ContextTierTable.isServerReadable(.p))
        XCTAssertTrue(ContextTierTable.isServerReadable(.c))

        // StructuredFacetValue — the tagged union, all five variants.
        let values: [StructuredFacetValue] = [
            .text("x"),
            .list(["a"]),
            .faithJourney(FaithJourneyValue(currentChurchId: nil, currentChurchName: nil,
                currentStudy: nil, favoriteBooks: [], spiritualGoals: [], prayerHabits: [],
                areasOfGrowth: [], areasNeedingSupport: [])),
            .communicationStyle(CommunicationStyleValue(preferredTone: nil,
                conversationStyles: [], frustratingBehaviors: [], meaningfulContentTypes: [])),
            .relationshipCategory(RelationshipCategoryValue(category: .friends, note: nil))
        ]
        XCTAssertEqual(values.count, 5)

        // ContextFacet — the only writable surface; tier-validity invariant.
        let facet = ContextFacet(
            id: UUID(), userId: "u", category: .interests, key: "interests.manual",
            label: "Interests", value: .list(["theology"]), visibility: .privateVisibility,
            tier: ContextTierTable.tier(for: .interests, key: "interests.manual"),
            provenance: Provenance(source: .manual, sourceLabel: nil, extractedAt: nil,
                confidence: nil, userApproved: true, userEdited: false,
                sanitizationPassId: "manual-test"),
            createdAt: Date(), updatedAt: Date(), schemaVersion: 1)
        XCTAssertTrue(facet.hasValidTier)

        // ContextSnapshot — append-only time series.
        let snap = ContextSnapshot(id: UUID(), userId: "u", takenAt: Date(),
                                   trigger: .manual, facetStates: [facet], schemaVersion: 1)
        XCTAssertEqual(snap.facetStates.count, 1)
    }

    // MARK: 2. Runtime tripwire (source/contract files not truncated)

    /// Minimum byte length below which CONTRACTS.md is presumed truncated/condensed.
    private let contractsMinBytes = 2500

    private var repoRoot: URL? {
        // #filePath → <repo>/AMENAPPTests/ContextContractIntegrityTests.swift
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: root.path) ? root : nil
    }

    func testContextStoreModelsDeclaresCanonicalTypes() throws {
        guard let root = repoRoot else { throw XCTSkip("repo root unreachable (sandboxed run)") }
        let modelsURL = root
            .appendingPathComponent("AMENAPP")
            .appendingPathComponent("ContextStore")
            .appendingPathComponent("ContextStoreModels.swift")
        guard let src = try? String(contentsOf: modelsURL, encoding: .utf8) else {
            throw XCTSkip("ContextStoreModels.swift unreachable")
        }
        for decl in ["enum EncryptionTier", "struct ContextFacet", "enum StructuredFacetValue",
                     "enum ContextTierTable", "struct ContextSnapshot"] {
            XCTAssertTrue(src.contains(decl),
                "CONTRACT TRIPWIRE: ContextStoreModels.swift is missing `\(decl)` — frozen model may have been truncated/overwritten. Restore from CONTRACTS.md.")
        }
    }

    func testContractsDocNotTruncated() throws {
        guard let root = repoRoot else { throw XCTSkip("repo root unreachable (sandboxed run)") }
        let contractsURL = root.appendingPathComponent("CONTRACTS.md")
        guard let text = try? String(contentsOf: contractsURL, encoding: .utf8) else {
            throw XCTSkip("CONTRACTS.md unreachable")
        }
        XCTAssertGreaterThan(text.utf8.count, contractsMinBytes,
            "CONTRACT TRIPWIRE: CONTRACTS.md (\(text.utf8.count) bytes) is below the \(contractsMinBytes)-byte floor — it may have been condensed/overwritten. Restore the full frozen contract.")
        XCTAssertTrue(text.contains("Server-read invariant"),
            "CONTRACT TRIPWIRE: CONTRACTS.md lost the Admin-SDK server-read invariant section.")
    }
}
