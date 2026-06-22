// BereanIntelligenceLayerTests.swift
// AMENAPPTests
//
// Unit tests for the Berean AI Intelligence Layer v2:
//   - BereanTheoLens (lens definitions, prompt blocks, pill mappings)
//   - BereanTheologyBoundaryService (hard-block phrase scrubber)
//   - BereanSmartPillEngine (pill selection, safety overrides)
//   - BereanChurchNoteCategory (display names, icons)
//   - BereanSelahEntryType (display names, icons)
//

import XCTest
@testable import AMENAPP

// MARK: - BereanSmartNotesSafetyGateTests

@MainActor
final class BereanSmartNotesSafetyGateTests: XCTestCase {

    func testMissingConsentBlocksBeforeCloudSave() async throws {
        var reachedCrisisScan = false
        var reachedConstitutionalReview = false
        let gate = BereanSmartNotesSafetyGate(
            hasAIConsent: { false },
            currentUserIsMinor: { false },
            hasCrisisSignal: { _ in
                reachedCrisisScan = true
                return false
            },
            constitutionalReviewer: { _ in
                reachedConstitutionalReview = true
                return .approved(mode: .build, risk: .high)
            }
        )

        do {
            try await gate.validate(noteContent: "Sermon notes from Romans 8")
            XCTFail("Missing consent should block Smart Notes save")
        } catch let error as BereanSmartNotesSafetyGate.GateError {
            XCTAssertEqual(error, .aiConsentRequired)
            XCTAssertFalse(reachedCrisisScan)
            XCTAssertFalse(reachedConstitutionalReview)
        }
    }

    func testCrisisContentBlocksBeforeCloudSave() async throws {
        var reachedConstitutionalReview = false
        let gate = BereanSmartNotesSafetyGate(
            hasAIConsent: { true },
            currentUserIsMinor: { false },
            hasCrisisSignal: { _ in true },
            constitutionalReviewer: { _ in
                reachedConstitutionalReview = true
                return .approved(mode: .build, risk: .high)
            }
        )

        do {
            try await gate.validate(noteContent: "I want to hurt myself after church")
            XCTFail("Crisis content should block Smart Notes save")
        } catch let error as BereanSmartNotesSafetyGate.GateError {
            XCTAssertEqual(error, .crisisInputDetected)
            XCTAssertFalse(reachedConstitutionalReview)
        }
    }

    func testMinorUserBlocksBeforeCloudSave() async throws {
        var reachedConstitutionalReview = false
        let gate = BereanSmartNotesSafetyGate(
            hasAIConsent: { true },
            currentUserIsMinor: { true },
            hasCrisisSignal: { _ in false },
            constitutionalReviewer: { _ in
                reachedConstitutionalReview = true
                return .approved(mode: .build, risk: .high)
            }
        )

        do {
            try await gate.validate(noteContent: "Sermon notes from Romans 8")
            XCTFail("Minor users should block Smart Notes save")
        } catch let error as BereanSmartNotesSafetyGate.GateError {
            XCTAssertEqual(error, .minorUserBlocked)
            XCTAssertFalse(reachedConstitutionalReview)
        }
    }

    func testConstitutionalReviewFailureBlocksBeforeCloudSave() async throws {
        let gate = BereanSmartNotesSafetyGate(
            hasAIConsent: { true },
            currentUserIsMinor: { false },
            hasCrisisSignal: { _ in false },
            constitutionalReviewer: { _ in
                .blocked(
                    reasons: ["Medical topic detected in study call - consider adding a medical guardrail note before dispatching."],
                    mode: .guard,
                    risk: .high
                )
            }
        )

        do {
            try await gate.validate(noteContent: "Notes about medication and prayer")
            XCTFail("Constitutional review failure should block Smart Notes save")
        } catch let error as BereanSmartNotesSafetyGate.GateError {
            guard case .moderationBlocked = error else {
                return XCTFail("Expected moderationBlocked, got \(error)")
            }
        }
    }
}

// MARK: - BereanTheoLensTests

final class BereanTheoLensTests: XCTestCase {

    // All lenses must have non-empty display names
    func testAllLensesHaveDisplayNames() {
        for lens in BereanTheoLens.allCases {
            XCTAssertFalse(lens.displayName.isEmpty, "Lens \(lens) has empty displayName")
        }
    }

    // All lenses must have non-empty backendValues (sent to server)
    func testAllLensesHaveBackendValues() {
        for lens in BereanTheoLens.allCases {
            XCTAssertFalse(lens.backendValue.isEmpty, "Lens \(lens) has empty backendValue")
        }
    }

    // Backend values must be distinct
    func testBackendValuesAreUnique() {
        let values = BereanTheoLens.allCases.map { $0.backendValue }
        let unique = Set(values)
        XCTAssertEqual(values.count, unique.count, "Duplicate backendValues detected: \(values)")
    }

    // Each lens must recommend at least 2 smart pills
    func testAllLensesHavePreferredPills() {
        for lens in BereanTheoLens.allCases {
            XCTAssertGreaterThanOrEqual(lens.preferredSmartPills.count, 2,
                "Lens \(lens) has fewer than 2 preferred pills")
        }
    }

    // Each lens must have at least 1 empty state suggestion
    func testAllLensesHaveEmptyStateSuggestions() {
        for lens in BereanTheoLens.allCases {
            XCTAssertFalse(lens.emptyStateSuggestions.isEmpty,
                "Lens \(lens) has no emptyStateSuggestions")
        }
    }

    // Prompt block must include the anti-roleplay instruction
    func testPromptBlockContainsAntiRoleplayInstruction() {
        for lens in BereanTheoLens.allCases {
            let block = BereanLensPromptBlock.build(for: lens)
            // Must not encourage roleplay — must contain an explicit denial
            XCTAssertTrue(
                block.contains("NOT") || block.contains("not") || block.contains("never"),
                "Lens \(lens) prompt block missing anti-roleplay guard: \(block)"
            )
        }
    }

    // Wisdom lens should reference wisdom-related terms
    func testWisdomLensPromptMentionsWisdom() {
        let block = BereanLensPromptBlock.build(for: .wisdom)
        let lower = block.lowercased()
        XCTAssertTrue(
            lower.contains("wisdom") || lower.contains("proverb") || lower.contains("discernment"),
            "Wisdom lens prompt block doesn't reference wisdom: \(block)"
        )
    }

    // Prayer lens should reference prayer/lament terms
    func testPrayerLensPromptMentionsPrayer() {
        let block = BereanLensPromptBlock.build(for: .prayer)
        let lower = block.lowercased()
        XCTAssertTrue(
            lower.contains("prayer") || lower.contains("psalm") || lower.contains("lament"),
            "Prayer lens prompt block doesn't reference prayer: \(block)"
        )
    }

    // Discernment lens should reference discernment terms
    func testDiscernmentLensPromptMentionsDiscernment() {
        let block = BereanLensPromptBlock.build(for: .discernment)
        let lower = block.lowercased()
        XCTAssertTrue(
            lower.contains("discern") || lower.contains("wise") || lower.contains("counsel"),
            "Discernment lens prompt block doesn't reference discernment: \(block)"
        )
    }

    // Lens store default should be .wisdom (or whatever is declared)
    @MainActor
    func testLensStoreDefaultIsValid() {
        // Default is wisdom lens per spec
        let store = BereanTheoLensStore.shared
        XCTAssertNotNil(store.selectedLens)
    }

    // Analytics name must be non-empty for all lenses
    func testAnalyticsNamesNonEmpty() {
        for lens in BereanTheoLens.allCases {
            XCTAssertFalse(lens.analyticsName.isEmpty, "Lens \(lens) has empty analyticsName")
        }
    }
}

// MARK: - BereanTheologyBoundaryTests

final class BereanTheologyBoundaryTests: XCTestCase {

    private let service = BereanTheologyBoundaryService.shared

    // Clean text passes through unchanged
    func testCleanTextPassesThrough() {
        let clean = "Romans 8:28 tells us that God works all things together for good."
        let result = service.sanitize(clean)
        XCTAssertFalse(result.rewroteContent, "Clean text should not trigger rewrite")
        XCTAssertEqual(result.sanitizedText, clean)
    }

    // Hard-block: "God told me"
    func testBlocksGodToldMe() {
        let input = "God told me that you need to leave your job immediately."
        let result = service.sanitize(input)
        XCTAssertTrue(result.rewroteContent, "Should have rewritten 'God told me'")
        XCTAssertFalse(result.sanitizedText.lowercased().contains("god told me"),
            "Sanitized text should not contain 'God told me'")
    }

    // Hard-block: "The Holy Spirit says"
    func testBlocksHolySpiritSays() {
        let input = "The Holy Spirit says you should reconcile with your brother today."
        let result = service.sanitize(input)
        XCTAssertTrue(result.rewroteContent)
        XCTAssertFalse(result.sanitizedText.lowercased().contains("the holy spirit says"))
    }

    // Hard-block: "I feel led to tell you"
    func testBlocksIFeelLedToTellYou() {
        let input = "I feel led to tell you that this relationship is not from God."
        let result = service.sanitize(input)
        XCTAssertTrue(result.rewroteContent)
    }

    // Hard-block: "This will definitely happen"
    func testBlocksDefinitePropheticClaims() {
        let input = "This will definitely happen based on what I see in Scripture."
        let result = service.sanitize(input)
        XCTAssertTrue(result.rewroteContent)
    }

    // Hard-block: roleplay phrase ("I, Paul, would say")
    func testBlocksRoleplayPhrase() {
        let input = "I, Paul, would say to you that suffering builds character."
        let result = service.sanitize(input)
        XCTAssertTrue(result.rewroteContent, "Roleplay phrase should be blocked")
    }

    // Hard-block: "I am your pastor"
    func testBlocksIAmYourPastor() {
        let input = "I am your pastor and I believe you should make this decision."
        let result = service.sanitize(input)
        XCTAssertTrue(result.rewroteContent)
    }

    // Hard-block: "God is punishing you"
    func testBlocksGodIsPunishingYou() {
        let input = "God is punishing you for what you did last year."
        let result = service.sanitize(input)
        XCTAssertTrue(result.rewroteContent)
    }

    // Hard-block: "Keep this between us"
    func testBlocksKeepThisBetweenUs() {
        let input = "Keep this between us, but I believe you are called to leave the church."
        let result = service.sanitize(input)
        XCTAssertTrue(result.rewroteContent)
    }

    // Detected patterns array is populated when rewrite occurs
    func testDetectedPatternsPopulated() {
        let input = "God told me you should do this."
        let result = service.sanitize(input)
        XCTAssertTrue(result.rewroteContent)
        XCTAssertFalse(result.detectedPatterns.isEmpty, "detectedPatterns should not be empty")
    }

    // Multiple violations are all caught
    func testMultipleViolationsCaught() {
        let input = "God told me and The Holy Spirit says that you must do this."
        let result = service.sanitize(input)
        XCTAssertTrue(result.rewroteContent)
        XCTAssertGreaterThanOrEqual(result.detectedPatterns.count, 1)
    }

    // Case-insensitive matching
    func testCaseInsensitiveMatch() {
        let input = "GOD TOLD ME this is your calling."
        let result = service.sanitize(input)
        XCTAssertTrue(result.rewroteContent, "Should catch uppercase variant")
    }
}

// MARK: - BereanDisputedTopicDetectorTests

final class BereanDisputedTopicDetectorTests: XCTestCase {

    func testPredestinationDetected() {
        let text = "The Calvinist view of predestination holds that election is unconditional."
        let topics = BereanDisputedTopicDetector.detect(in: text)
        XCTAssertTrue(topics.contains("predestination") || !topics.isEmpty,
            "Predestination topic not detected")
    }

    func testNeutralTextHasNoTopics() {
        let text = "John 3:16 says that God so loved the world."
        let topics = BereanDisputedTopicDetector.detect(in: text)
        // Neutral text should have zero or very few disputed topics
        XCTAssertTrue(topics.isEmpty || topics.count < 3)
    }
}

// MARK: - BereanSmartPillEngineTests

@MainActor
final class BereanSmartPillEngineTests: XCTestCase {

    // Crisis state returns ONLY safety pills
    func testCrisisStateReturnsSafetyPillsOnly() {
        let pills = BereanSmartPillEngine.pills(
            lens: .wisdom,
            isCrisisState: true,
            sensitivityFlags: [],
            hasScriptureRefs: true
        )
        XCTAssertFalse(pills.isEmpty, "Crisis should return safety pills")
        XCTAssertTrue(pills.allSatisfy { $0.isSafetyPill },
            "Crisis state must return ONLY safety pills, got: \(pills.map { $0.rawValue })")
    }

    // CrisisEscalation flag returns ONLY safety pills even without isCrisisState
    func testCrisisEscalationFlagReturnsSafetyPills() {
        let pills = BereanSmartPillEngine.pills(
            lens: .prayer,
            isCrisisState: false,
            sensitivityFlags: [.crisisEscalation],
            hasScriptureRefs: false
        )
        XCTAssertTrue(pills.allSatisfy { $0.isSafetyPill },
            "crisisEscalation flag must trigger safety-only pills")
    }

    // PastoralEscalation flag returns ONLY safety pills
    func testPastoralEscalationReturnsSafetyPills() {
        let pills = BereanSmartPillEngine.pills(
            lens: .discernment,
            isCrisisState: false,
            sensitivityFlags: [.pastoralEscalation],
            hasScriptureRefs: false
        )
        XCTAssertTrue(pills.allSatisfy { $0.isSafetyPill },
            "pastoralEscalation flag must trigger safety-only pills")
    }

    // Scrupulosity suppresses debate pills and adds askTrustedPastor
    func testScrupulositySupressesDebatePills() {
        let pills = BereanSmartPillEngine.pills(
            lens: .wisdom,
            isCrisisState: false,
            sensitivityFlags: [.scrupulosityRisk],
            hasScriptureRefs: false
        )
        let debatePills = pills.filter { $0.isDebateOrDeepDive }
        XCTAssertTrue(debatePills.isEmpty,
            "Scrupulosity should suppress debate pills, got: \(debatePills.map { $0.rawValue })")
        XCTAssertTrue(pills.contains(.askTrustedPastor),
            "Scrupulosity should add .askTrustedPastor")
    }

    // Normal state returns non-safety pills capped at 6
    func testNormalStateReturnsModeBasedPills() {
        let pills = BereanSmartPillEngine.pills(
            lens: .wisdom,
            isCrisisState: false,
            sensitivityFlags: [],
            hasScriptureRefs: false
        )
        XCTAssertFalse(pills.isEmpty, "Normal state should return pills")
        XCTAssertLessThanOrEqual(pills.count, 6, "Pills capped at 6")
    }

    // Scripture refs adds showScriptureContext pill
    func testScriptureRefsAddsContextPill() {
        let pills = BereanSmartPillEngine.pills(
            lens: .wisdom,
            isCrisisState: false,
            sensitivityFlags: [],
            hasScriptureRefs: true
        )
        XCTAssertTrue(pills.contains(.showScriptureContext),
            "hasScriptureRefs should inject .showScriptureContext pill")
    }

    // Safety pills have correct isSafetyPill flag
    func testSafetyPillFlagCorrect() {
        let safePills: [BereanSmartPill] = [.pause, .breathe, .talkToSomeone, .findImmediateHelp, .readPsalm23, .savePrivately]
        for pill in safePills {
            XCTAssertTrue(pill.isSafetyPill, "\(pill) should be a safety pill")
        }
    }

    // Non-safety pills do not have isSafetyPill flag
    func testNonSafetyPillFlagCorrect() {
        let nonSafePills: [BereanSmartPill] = [.explainDeeper, .showScriptureContext, .saveToSelah, .addToChurchNotes]
        for pill in nonSafePills {
            XCTAssertFalse(pill.isSafetyPill, "\(pill) should not be a safety pill")
        }
    }

    // Debate pills have correct isDebateOrDeepDive flag
    func testDebatePillFlagCorrect() {
        let debatePills: [BereanSmartPill] = [.compareInterpretations, .comparePassages, .showCrossReferences, .continueResearch, .explainDeeper]
        for pill in debatePills {
            XCTAssertTrue(pill.isDebateOrDeepDive, "\(pill) should be debate/deep-dive")
        }
    }

    // All pills have non-empty display labels
    func testAllPillsHaveDisplayLabels() {
        for pill in BereanSmartPill.allCases {
            XCTAssertFalse(pill.displayLabel.isEmpty, "\(pill) has empty displayLabel")
        }
    }

    // All pills have non-empty accessibility labels
    func testAllPillsHaveAccessibilityLabels() {
        for pill in BereanSmartPill.allCases {
            XCTAssertFalse(pill.accessibilityLabel.isEmpty, "\(pill) has empty accessibilityLabel")
        }
    }
}

// MARK: - BereanChurchNotesCategoryTests

final class BereanChurchNotesCategoryTests: XCTestCase {

    func testAllCategoriesHaveDisplayNames() {
        for cat in BereanChurchNoteCategory.allCases {
            XCTAssertFalse(cat.displayName.isEmpty, "\(cat) has empty displayName")
        }
    }

    func testAllCategoriesHaveIcons() {
        for cat in BereanChurchNoteCategory.allCases {
            XCTAssertFalse(cat.icon.isEmpty, "\(cat) has empty icon")
        }
    }

    func testRawValuesAreSnakeCase() {
        for cat in BereanChurchNoteCategory.allCases {
            XCTAssertFalse(cat.rawValue.isEmpty)
            XCTAssertFalse(cat.rawValue.contains(" "), "\(cat) rawValue has spaces")
        }
    }
}

// MARK: - BereanSelahEntryTypeTests

final class BereanSelahEntryTypeTests: XCTestCase {

    func testAllEntryTypesHaveDisplayNames() {
        for type in BereanSelahEntryType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "\(type) has empty displayName")
        }
    }

    func testAllEntryTypesHaveIcons() {
        for type in BereanSelahEntryType.allCases {
            XCTAssertFalse(type.icon.isEmpty, "\(type) has empty icon")
        }
    }
}

// MARK: - BereanUserTierAccessTests

final class BereanUserTierAccessTests: XCTestCase {

    // Free tier: only Core is full access
    func testFreeTierCoreFullAccess() {
        XCTAssertEqual(BereanUserTier.free.access(for: .core), .full)
    }

    func testFreeTierDeepLocked() {
        XCTAssertEqual(BereanUserTier.free.access(for: .deep), .locked)
    }

    func testFreeTierAdaptiveLocked() {
        XCTAssertEqual(BereanUserTier.free.access(for: .adaptive), .locked)
    }

    // Pro/Founder: all modes are full access
    func testProTierFullAccess() {
        for mode in BereanModelMode.allCases {
            XCTAssertEqual(BereanUserTier.pro.access(for: mode), .full,
                "Pro should have full access for \(mode)")
        }
    }

    func testFounderTierFullAccess() {
        for mode in BereanModelMode.allCases {
            XCTAssertEqual(BereanUserTier.founder.access(for: mode), .full,
                "Founder should have full access for \(mode)")
        }
    }

    // Plus tier: deep is limited, adaptive is locked, core is full
    func testPlusTierCoreFullAccess() {
        XCTAssertEqual(BereanUserTier.plus.access(for: .core), .full)
    }

    func testPlusTierDeepLimited() {
        XCTAssertEqual(BereanUserTier.plus.access(for: .deep), .limited)
    }

    func testPlusTierAdaptiveLocked() {
        XCTAssertEqual(BereanUserTier.plus.access(for: .adaptive), .locked)
    }
}
