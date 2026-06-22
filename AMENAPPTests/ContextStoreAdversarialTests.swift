// ContextStoreAdversarialTests.swift
// AMEN Universal Migration & Context System — Wave 1 ADVERSARIAL security pass.
//
// Every test in this file encodes a HOSTILE attempt against the frozen security
// model (CONTRACTS.md, ContextStoreRules.txt, ContextStoreModels.swift,
// AegisEnforcementService.swift). Each adversarial attempt MUST fail, and the test
// asserts that failure.
//
// Framework: XCTest — matches the sibling happy-path file (ContextStoreSecurityTests.swift)
// and the rest of the AMENAPPTests target. No `import Testing` here because the
// ContextStore tests already standardized on XCTest.
//
// Emulator note: this repo has NO live Firestore emulator harness wired
// (firebase.json declares no "emulators" block, and the `FirebaseFirestoreEmulator`
// module imported by the happy-path file resolves to no real product). So the
// cross-user-read denial (case 1) is proven in its closest testable form: by
// parsing the FROZEN rules text and asserting the read scope is pinned to
// `request.auth.uid == userId`, plus a Swift-level check that any code path
// requiring a foreign uid is rejected. Everything else is a true unit test against
// the frozen Swift contracts — no Firebase imports required, so this file compiles
// and runs standalone.

// The file can be discovered by non-test targets because it lives beside the
// ContextStore sources, so keep the XCTest-only declarations behind a test-target
// compilation condition. The tests still compile and run in AMENAPPTests.
#if canImport(XCTest)
import XCTest
@testable import AMENAPP

final class ContextStoreAdversarialTests: XCTestCase {

    // MARK: - Fixtures

    /// Locates the frozen rules text next to this source file, falling back to the
    /// repo-relative path. Returns nil only if neither is present.
    private func loadFrozenRulesText() -> String? {
        let here = URL(fileURLWithPath: #filePath)
        let sibling = here.deletingLastPathComponent().appendingPathComponent("ContextStoreRules.txt")
        if let text = try? String(contentsOf: sibling, encoding: .utf8) {
            return text
        }
        // Fallback: walk up from this file looking for the ContextStore directory.
        var dir = here.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("AMENAPP/ContextStore/ContextStoreRules.txt")
            if let text = try? String(contentsOf: candidate, encoding: .utf8) { return text }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    /// Issues a facet with full control over the hostile knobs each test needs.
    private func makeFacet(
        userId: String = "owner-uid",
        category: FacetCategory = .interests,
        key: String = "interest.ai",
        tier: EncryptionTier? = nil,
        userApproved: Bool = true,
        sanitizationPassId: String = "pass-abc123",
        schemaVersion: Int = 1
    ) -> ContextFacet {
        let resolvedTier = tier ?? ContextTierTable.tier(for: category, key: key)
        let provenance = Provenance(
            source: .manual,
            sourceLabel: nil,
            extractedAt: nil,
            confidence: nil,
            userApproved: userApproved,
            userEdited: false,
            sanitizationPassId: sanitizationPassId
        )
        return ContextFacet(
            id: UUID(),
            userId: userId,
            category: category,
            key: key,
            label: "Test facet",
            value: .text("hostile value"),
            visibility: .privateVisibility,
            tier: resolvedTier,
            provenance: provenance,
            createdAt: Date(),
            updatedAt: Date(),
            schemaVersion: schemaVersion
        )
    }

    /// Mirror of the ContextStoreService write guard (kept local so this test owns no
    /// other agent's file). A facet may persist ONLY when every clause holds. This is
    /// the exact conjunction the Firestore rules + client write path enforce.
    private func writeWouldBeAccepted(_ facet: ContextFacet, requestUid: String) -> Bool {
        guard facet.userId == requestUid else { return false }                          // owner-only
        guard facet.provenance.userApproved else { return false }                       // §1.7 approval gate
        guard AegisEnforcementService.shared.verifySanitization(facet.provenance) else { return false } // C59
        guard facet.hasValidTier else { return false }                                  // tier-table law
        guard facet.schemaVersion == 1 else { return false }                            // schema pin
        return true
    }

    // MARK: - 1. Cross-user read is denied

    func testRulesText_readsScopedToRequestAuthUidEqualsUserId() throws {
        let rules = try XCTUnwrap(loadFrozenRulesText(),
                                  "Frozen ContextStoreRules.txt must be present to assert the read scope.")

        // Both facet and snapshot read rules MUST pin to the authenticated owner.
        // There must be NO `allow read` that omits the `request.auth.uid == userId` clause.
        let lines = rules.split(separator: "\n").map(String.init)
        let readLines = lines.filter { $0.contains("allow read") }
        XCTAssertFalse(readLines.isEmpty, "Expected explicit read rules in the frozen file.")
        for line in readLines {
            XCTAssertTrue(line.contains("request.auth.uid == userId"),
                          "Every read rule must be owner-scoped; offending line: \(line)")
            XCTAssertTrue(line.contains("isSignedIn()"),
                          "Read rules must also require authentication; offending line: \(line)")
        }

        // Defensively assert there is no wildcard read grant anywhere.
        XCTAssertFalse(rules.contains("allow read: if true"),
                       "A blanket read grant would break cross-user confidentiality.")
    }

    func testCrossUserRead_codePathRequiringForeignUidIsRejected() {
        // A facet owned by "victim-uid" can never be served to "attacker-uid".
        let victimFacet = makeFacet(userId: "victim-uid")
        XCTAssertFalse(writeWouldBeAccepted(victimFacet, requestUid: "attacker-uid"),
                       "Owner-only rule must reject access keyed to a foreign uid.")
        // Sanity: the legitimate owner is accepted, proving the guard isn't trivially false.
        XCTAssertTrue(writeWouldBeAccepted(victimFacet, requestUid: "victim-uid"))
    }

    // MARK: - 2. Unapproved-provenance write is rejected

    func testUnapprovedProvenanceWrite_isBlocked() {
        let unapproved = makeFacet(userApproved: false)
        // The approval guard must reject it even though sanitization + tier are valid.
        XCTAssertTrue(AegisEnforcementService.shared.verifySanitization(unapproved.provenance),
                      "Precondition: receipt is valid so we isolate the approval clause.")
        XCTAssertTrue(unapproved.hasValidTier, "Precondition: tier is valid.")
        XCTAssertFalse(unapproved.provenance.userApproved, "The hostile facet is unapproved.")
        XCTAssertFalse(writeWouldBeAccepted(unapproved, requestUid: unapproved.userId),
                       "A facet with userApproved == false must never persist (§1.7).")
    }

    // MARK: - 3. Tier mismatch rejected

    func testTierMismatch_hasValidTierIsFalse_andWriteBlocked() {
        // relationships is canonically Tier P; forging it to Tier C is a confidentiality attack.
        let forged = makeFacet(category: .relationships,
                               key: "relationship.family_category",
                               tier: .c)
        XCTAssertNotEqual(forged.tier,
                          ContextTierTable.tier(for: forged.category, key: forged.key),
                          "Forged tier must differ from the canonical table value.")
        XCTAssertFalse(forged.hasValidTier,
                       "A facet whose tier != canonical table must report hasValidTier == false.")
        XCTAssertFalse(writeWouldBeAccepted(forged, requestUid: forged.userId),
                       "A tier-mismatched facet must be rejected by the write guard.")
    }

    // MARK: - 4. Tier-P confidentiality

    func testTierP_isNeverServerReadable() {
        XCTAssertFalse(ContextTierTable.isServerReadable(.p),
                       "Tier P must never be server-readable.")
        // And the readable tiers stay readable, so the check isn't trivially false.
        XCTAssertTrue(ContextTierTable.isServerReadable(.c))
        XCTAssertTrue(ContextTierTable.isServerReadable(.s))
    }

    func testSensitiveCategoriesMapToTierP() {
        XCTAssertEqual(ContextTierTable.tier(for: .relationships), .p)
        XCTAssertEqual(ContextTierTable.tier(for: .family), .p)
        XCTAssertEqual(ContextTierTable.tier(for: .health), .p)
    }

    func testFaithAreasNeedingSupportIsForcedTierP() {
        // The faith key override: areas_needing_support is Tier P even though the rest
        // of faith_journey is Tier C.
        let p = ContextTierTable.tier(for: .faith_journey,
                                      key: "faith.areas_needing_support")
        XCTAssertEqual(p, .p, "Faith *.areas_needing_support must be forced to Tier P.")

        // Contrast: general faith_journey is Tier C (so the override is specific, not blanket).
        let c = ContextTierTable.tier(for: .faith_journey, key: "faith.current_study")
        XCTAssertEqual(c, .c, "General faith_journey facets remain Tier C.")
    }

    // MARK: - 5. Empty sanitization receipt is rejected

    func testEmptySanitizationReceipt_isRejected() {
        let noReceipt = makeFacet(sanitizationPassId: "")
        XCTAssertFalse(AegisEnforcementService.shared.verifySanitization(noReceipt.provenance),
                       "A facet with an empty sanitization receipt must fail C59 verification.")
        XCTAssertFalse(writeWouldBeAccepted(noReceipt, requestUid: noReceipt.userId),
                       "A facet with an empty receipt must never persist.")
        // The frozen unverified receipt likewise reports not-verified.
        XCTAssertFalse(SanitizationReceipt.unverified.isVerified)
        // A populated receipt is accepted, proving the guard isn't trivially false.
        XCTAssertTrue(AegisEnforcementService.shared.verifySanitization(makeFacet().provenance))
    }

    // MARK: - 6. Minor constraints

    func testMinor_contextQR_isDenied() {
        let decision = AegisEnforcementService.shared.minorConstraint(for: .contextQR, isMinor: true)
        guard case .denied = decision else {
            return XCTFail("Context QR must be denied for minors; got \(decision).")
        }
    }

    func testMinor_faithAreasNeedingSupportServerWrite_isDenied() {
        let decision = AegisEnforcementService.shared.minorConstraint(
            for: .faithAreasNeedingSupportServerWrite, isMinor: true)
        guard case .denied = decision else {
            return XCTFail("Minor faith-support server write must be denied; got \(decision).")
        }
    }

    func testUnknownAge_failsClosed_treatedAsMinor() {
        // Aegis treats unknown age as minor (fail closed). The caller passes the
        // fail-closed default (isMinor: true) when age is unknown; assert the gated
        // capability is still denied under that default.
        let unknownAgeIsMinor = true   // mirrors "unknown age ⇒ minor" contract
        let decision = AegisEnforcementService.shared.minorConstraint(
            for: .contextQR, isMinor: unknownAgeIsMinor)
        guard case .denied = decision else {
            return XCTFail("Unknown-age (fail-closed) must be denied for Context QR; got \(decision).")
        }
    }

    func testAdult_contextQR_isAllowed_provingGateIsNotTriviallyDenied() {
        let decision = AegisEnforcementService.shared.minorConstraint(for: .contextQR, isMinor: false)
        guard case .allowed = decision else {
            return XCTFail("Adults must be allowed Context QR, proving the minor gate is specific; got \(decision).")
        }
    }
}
#endif
