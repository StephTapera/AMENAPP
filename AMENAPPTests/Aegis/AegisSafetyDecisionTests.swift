// AegisSafetyDecisionTests.swift
// Tests AegisSafetyDecision factories, severity ordering,
// AegisDetectionResult factory, deletion manifest, and wellbeing state.
// All tests are pure model/struct operations — no Firebase required.

import Foundation
import Testing
@testable import AMENAPP

@Suite("Aegis Safety Decision & Model Tests")
struct AegisSafetyDecisionTests {

    // MARK: - AegisSeverity ordering

    @Test("Severity: info < caution < warn < block (total order)")
    func severityOrdering() {
        #expect(AegisSeverity.info    < .caution)
        #expect(AegisSeverity.caution < .warn)
        #expect(AegisSeverity.warn    < .block)
        #expect(AegisSeverity.info    < .block)
    }

    @Test("Severity max across all cases is .block")
    func severityMaxIsBlock() {
        let maxSev = AegisSeverity.allCases.max()
        #expect(maxSev == .block)
    }

    @Test("Severity min across all cases is .info")
    func severityMinIsInfo() {
        let minSev = AegisSeverity.allCases.min()
        #expect(minSev == .info)
    }

    @Test("Only .block blocksPublishing")
    func onlyBlockBlocksPublishing() {
        #expect(!AegisSeverity.info.blocksPublishing)
        #expect(!AegisSeverity.caution.blocksPublishing)
        #expect(!AegisSeverity.warn.blocksPublishing)
        #expect(AegisSeverity.block.blocksPublishing)
    }

    @Test("isActionable: caution/warn/block are actionable; info is not")
    func isActionable() {
        #expect(!AegisSeverity.info.isActionable)
        #expect(AegisSeverity.caution.isActionable)
        #expect(AegisSeverity.warn.isActionable)
        #expect(AegisSeverity.block.isActionable)
    }

    @Test("outcomeMapping: info→allow, caution→allowWithLabel, warn→limitDistribution, block→block")
    func outcomeMappingAllSeverities() {
        #expect(AegisSeverity.info.outcomeMapping    == .allow)
        #expect(AegisSeverity.caution.outcomeMapping == .allowWithLabel)
        #expect(AegisSeverity.warn.outcomeMapping    == .limitDistribution)
        #expect(AegisSeverity.block.outcomeMapping   == .block)
    }

    // MARK: - AegisDetectionResult.make factory

    @Test("DetectionResult.make populates all required fields")
    func detectionResultMakeFields() {
        let result = AegisDetectionResult.make(
            capability: .donationFraud,
            severity: .warn,
            confidence: 0.9,
            action: "Potential fraud detected."
        )
        #expect(result.capabilityId == .donationFraud)
        #expect(result.severity == .warn)
        #expect(result.confidence == 0.9)
        #expect(result.suggestedAction == "Potential fraud detected.")
        #expect(!result.resultId.isEmpty)
        #expect(result.policyVersion == AegisContractsVersion)
        #expect(result.evidence.isEmpty)
        #expect(result.regions.isEmpty)
        #expect(result.careResources.isEmpty)
    }

    @Test("DetectionResult.make with care resources attaches them")
    func detectionResultMakeWithCare() {
        let care = AegisCareResource(
            id: "care-test",
            title: "Test Resource",
            body: "You are not alone.",
            actionLabel: "Call",
            actionUrl: "tel:+18005551234",
            resourceType: .crisisLine
        )
        let result = AegisDetectionResult.make(
            capability: .spiritualAbuse,
            severity: .block,
            confidence: 0.95,
            action: "Blocked",
            care: [care]
        )
        #expect(result.careResources.count == 1)
        #expect(result.careResources[0].id == "care-test")
    }

    @Test("DetectionResult.make with evidence attaches it")
    func detectionResultMakeWithEvidence() {
        let evidence = AegisEvidence(
            type: .textSpan,
            description: "Credit card number matched",
            confidence: 0.99,
            spanStart: 10,
            spanEnd: 25
        )
        let result = AegisDetectionResult.make(
            capability: .financialInfo,
            severity: .block,
            confidence: 0.99,
            action: "Card blocked",
            evidence: [evidence]
        )
        #expect(result.evidence.count == 1)
        #expect(result.evidence[0].type == .textSpan)
    }

    @Test("DetectionResult.make produces unique IDs on each call")
    func detectionResultUniqueIds() {
        let r1 = AegisDetectionResult.make(capability: .romanceScam, severity: .warn, confidence: 0.7, action: "a")
        let r2 = AegisDetectionResult.make(capability: .romanceScam, severity: .warn, confidence: 0.7, action: "a")
        #expect(r1.resultId != r2.resultId)
    }

    // MARK: - AegisSafetyDecision.allow factory

    @Test("allow() produces safe default decision")
    func allowDecisionDefaults() {
        let d = AegisSafetyDecision.allow()
        #expect(d.allowPost == true)
        #expect(d.requiredAcknowledgements.isEmpty)
        #expect(d.audienceRestriction == nil)
        #expect(d.redactions.isEmpty)
        #expect(d.routeToCare == false)
        #expect(d.careResources.isEmpty)
        #expect(!d.decisionId.isEmpty)
        #expect(d.policyVersion == AegisContractsVersion)
    }

    @Test("allow() asPreflightOutcome is .allow")
    func allowDecisionPreflightOutcome() {
        #expect(AegisSafetyDecision.allow().asPreflightOutcome == .allow)
    }

    @Test("allow() maxSeverity is .info when no results")
    func allowDecisionMaxSeverityNoResults() {
        #expect(AegisSafetyDecision.allow().maxSeverity == .info)
    }

    @Test("allow(results:) passes results through to detectionResults")
    func allowDecisionWithResults() {
        let r = AegisDetectionResult.make(capability: .pauseBeforePosting, severity: .caution, confidence: 0.5, action: "Pause")
        let d = AegisSafetyDecision.allow(results: [r])
        #expect(d.detectionResults.count == 1)
        #expect(d.detectionResults[0].capabilityId == .pauseBeforePosting)
    }

    // MARK: - AegisSafetyDecision.block factory

    @Test("block() sets allowPost false and copies redactions from results")
    func blockDecisionRedactions() {
        let result = AegisDetectionResult.make(
            capability: .idPassport, severity: .block, confidence: 0.98, action: "Blocked"
        )
        let d = AegisSafetyDecision.block(results: [result])
        #expect(d.allowPost == false)
        #expect(d.redactions.count == 1)
        #expect(d.redactions[0].capabilityId == .idPassport)
        #expect(d.routeToCare == false)
    }

    @Test("block() asPreflightOutcome is .quarantine when redactions are present")
    func blockDecisionPreflightOutcomeQuarantine() {
        let result = AegisDetectionResult.make(
            capability: .financialInfo, severity: .block, confidence: 0.9, action: "Blocked"
        )
        let d = AegisSafetyDecision.block(results: [result])
        #expect(d.asPreflightOutcome == .quarantine)
    }

    @Test("block() with care resources sets routeToCare = true")
    func blockDecisionWithCareRoutesToCare() {
        let care = AegisCareResource(
            id: "ccri-care",
            title: "CCRI",
            body: "Help available.",
            actionLabel: nil,
            actionUrl: nil,
            resourceType: .crisisLine
        )
        let result = AegisDetectionResult.make(
            capability: .sextortionPattern, severity: .block, confidence: 0.92, action: "Blocked"
        )
        let d = AegisSafetyDecision.block(results: [result], care: [care])
        #expect(d.routeToCare == true)
        #expect(d.careResources.count == 1)
    }

    // MARK: - maxSeverity computed property

    @Test("maxSeverity picks .warn from mixed caution/warn/info results")
    func maxSeverityPicksHighest() {
        let r1 = AegisDetectionResult.make(capability: .pauseBeforePosting,  severity: .caution, confidence: 0.5, action: "")
        let r2 = AegisDetectionResult.make(capability: .doctrinalMisinfo,    severity: .warn,    confidence: 0.7, action: "")
        let r3 = AegisDetectionResult.make(capability: .contextCollapseGuard, severity: .info,   confidence: 0.3, action: "")
        let d = AegisSafetyDecision.allow(results: [r1, r2, r3])
        #expect(d.maxSeverity == .warn)
    }

    @Test("maxSeverity returns .block when any result is .block")
    func maxSeverityBlockWins() {
        let r1 = AegisDetectionResult.make(capability: .spiritualAbuse, severity: .caution, confidence: 0.5, action: "")
        let r2 = AegisDetectionResult.make(capability: .doxxingDetection, severity: .block, confidence: 0.9, action: "")
        let d = AegisSafetyDecision.allow(results: [r1, r2])
        #expect(d.maxSeverity == .block)
    }

    // MARK: - asPreflightOutcome

    @Test("asPreflightOutcome: allowPost + routeToCare → .allowWithLabel")
    func asPreflightOutcomeAllowWithLabel() {
        let d = AegisSafetyDecision(
            decisionId: UUID().uuidString,
            allowPost: true,
            requiredAcknowledgements: [],
            audienceRestriction: nil,
            redactions: [],
            routeToCare: true,
            careResources: [],
            detectionResults: [],
            timestamp: Date(),
            policyVersion: AegisContractsVersion
        )
        #expect(d.asPreflightOutcome == .allowWithLabel)
    }

    @Test("asPreflightOutcome: allowPost=false + empty redactions → .block")
    func asPreflightOutcomeBlockNoRedactions() {
        let d = AegisSafetyDecision(
            decisionId: UUID().uuidString,
            allowPost: false,
            requiredAcknowledgements: [],
            audienceRestriction: nil,
            redactions: [],
            routeToCare: false,
            careResources: [],
            detectionResults: [],
            timestamp: Date(),
            policyVersion: AegisContractsVersion
        )
        #expect(d.asPreflightOutcome == .block)
    }

    // MARK: - AegisCareResource

    @Test("AegisCareResource stores all fields")
    func careResourceFields() {
        let care = AegisCareResource(
            id: "care.test.1",
            title: "Test Title",
            body: "Test body.",
            actionLabel: "Act Now",
            actionUrl: "https://example.com",
            resourceType: .externalLink
        )
        #expect(care.id == "care.test.1")
        #expect(care.title == "Test Title")
        #expect(care.body == "Test body.")
        #expect(care.actionLabel == "Act Now")
        #expect(care.actionUrl == "https://example.com")
        #expect(care.resourceType == .externalLink)
    }

    @Test("AegisCareResource allows nil actionUrl and actionLabel")
    func careResourceNilActionFields() {
        let care = AegisCareResource(
            id: "care.pastoral",
            title: "Pastoral Note",
            body: "Speak to a pastor.",
            actionLabel: nil,
            actionUrl: nil,
            resourceType: .pastoralGuidance
        )
        #expect(care.actionUrl == nil)
        #expect(care.actionLabel == nil)
        #expect(care.resourceType == .pastoralGuidance)
    }

    // MARK: - AegisEvidence

    @Test("AegisEvidence span fields store correctly")
    func evidenceSpanFields() {
        let e = AegisEvidence(
            type: .textSpan,
            description: "Matched pattern",
            confidence: 0.88,
            spanStart: 5,
            spanEnd: 15
        )
        #expect(e.type == .textSpan)
        #expect(e.spanStart == 5)
        #expect(e.spanEnd == 15)
    }

    @Test("AegisEvidence boundingBox with nil spans")
    func evidenceBoundingBoxNilSpans() {
        let e = AegisEvidence(
            type: .boundingBox,
            description: "Face region",
            confidence: 0.95,
            spanStart: nil,
            spanEnd: nil
        )
        #expect(e.type == .boundingBox)
        #expect(e.spanStart == nil)
        #expect(e.spanEnd == nil)
    }

    // MARK: - C55 AegisDeletionManifest (data rights fan-out)

    @Test("C55 — canonicalPaths has exactly 16 Firestore paths")
    func deletionManifestFirestoreCount() {
        let m = AegisDeletionManifest.canonicalPaths(for: "uid-test")
        #expect(m.firestorePaths.count == 16)
    }

    @Test("C55 — canonicalPaths has exactly 4 Storage paths")
    func deletionManifestStorageCount() {
        let m = AegisDeletionManifest.canonicalPaths(for: "uid-test")
        #expect(m.storagePaths.count == 4)
    }

    @Test("C55 — canonicalPaths has exactly 4 Pinecone namespaces")
    func deletionManifestPineconeCount() {
        let m = AegisDeletionManifest.canonicalPaths(for: "uid-test")
        #expect(m.pineconeNamespaces.count == 4)
    }

    @Test("C55 — canonicalPaths has exactly 4 derived data paths")
    func deletionManifestDerivedCount() {
        let m = AegisDeletionManifest.canonicalPaths(for: "uid-test")
        #expect(m.derivedDataPaths.count == 4)
    }

    @Test("C55 — canonicalPaths interpolates userId into all collection roots")
    func deletionManifestUserIdInterpolated() {
        let uid = "user-abc-123"
        let m = AegisDeletionManifest.canonicalPaths(for: uid)
        #expect(m.userId == uid)
        #expect(m.firestorePaths.contains("users/\(uid)"))
        #expect(m.storagePaths.contains("users/\(uid)/"))
        #expect(m.pineconeNamespaces.contains("user-\(uid)-posts"))
        #expect(m.derivedDataPaths.contains("algolia:users:\(uid)"))
    }

    @Test("C55 — aegisProfiles and wellbeingState paths are in the manifest")
    func deletionManifestIncludesAegisAndWellbeing() {
        let uid = "uid-xyz"
        let m = AegisDeletionManifest.canonicalPaths(for: uid)
        #expect(m.firestorePaths.contains("aegisProfiles/\(uid)"))
        #expect(m.firestorePaths.contains("wellbeingState/\(uid)"))
    }

    @Test("C55 — manifest starts incomplete with nil confirmedAt")
    func deletionManifestStartsIncomplete() {
        let m = AegisDeletionManifest.canonicalPaths(for: "uid")
        #expect(m.isComplete == false)
        #expect(m.confirmedAt == nil)
        #expect(!m.manifestId.isEmpty)
    }

    // MARK: - C47–C50 AegisWellbeingState

    @Test("C47–C50 — AegisWellbeingState initializes with correct zero-state defaults")
    func wellbeingStateZeroDefaults() {
        let state = AegisWellbeingState(
            userId: "uid",
            hiddenMetrics: false,
            antiRageEnabled: false,
            doomscrollGuardEnabled: false,
            lateNightFrictionEnabled: false,
            memoryControlsEnabled: false,
            mutedDates: [],
            mutedUserIds: [],
            sessionStartedAt: nil,
            scrollDepthToday: 0
        )
        #expect(state.userId == "uid")
        #expect(!state.hiddenMetrics)
        #expect(!state.antiRageEnabled)
        #expect(!state.doomscrollGuardEnabled)
        #expect(!state.lateNightFrictionEnabled)
        #expect(!state.memoryControlsEnabled)
        #expect(state.mutedDates.isEmpty)
        #expect(state.mutedUserIds.isEmpty)
        #expect(state.sessionStartedAt == nil)
        #expect(state.scrollDepthToday == 0)
    }

    @Test("C47 — hiddenMetrics can be toggled on")
    func wellbeingC47HiddenMetricsToggle() {
        var state = AegisWellbeingState(
            userId: "uid", hiddenMetrics: false, antiRageEnabled: false,
            doomscrollGuardEnabled: false, lateNightFrictionEnabled: false,
            memoryControlsEnabled: false, mutedDates: [], mutedUserIds: [],
            sessionStartedAt: nil, scrollDepthToday: 0
        )
        state.hiddenMetrics = true
        #expect(state.hiddenMetrics == true)
    }

    @Test("C48 — antiRageEnabled can be toggled on")
    func wellbeingC48AntiRageToggle() {
        var state = AegisWellbeingState(
            userId: "uid", hiddenMetrics: false, antiRageEnabled: false,
            doomscrollGuardEnabled: false, lateNightFrictionEnabled: false,
            memoryControlsEnabled: false, mutedDates: [], mutedUserIds: [],
            sessionStartedAt: nil, scrollDepthToday: 0
        )
        state.antiRageEnabled = true
        #expect(state.antiRageEnabled == true)
    }

    @Test("C49 — scrollDepthToday increments")
    func wellbeingC49ScrollDepth() {
        var state = AegisWellbeingState(
            userId: "uid", hiddenMetrics: false, antiRageEnabled: false,
            doomscrollGuardEnabled: true, lateNightFrictionEnabled: false,
            memoryControlsEnabled: false, mutedDates: [], mutedUserIds: [],
            sessionStartedAt: Date(), scrollDepthToday: 0
        )
        state.scrollDepthToday = 250
        #expect(state.scrollDepthToday == 250)
    }

    @Test("C50 — mutedDates stores dates in MM-DD format")
    func wellbeingC50MutedDates() {
        var state = AegisWellbeingState(
            userId: "uid", hiddenMetrics: false, antiRageEnabled: false,
            doomscrollGuardEnabled: false, lateNightFrictionEnabled: false,
            memoryControlsEnabled: true, mutedDates: [], mutedUserIds: [],
            sessionStartedAt: nil, scrollDepthToday: 0
        )
        state.mutedDates = ["05-31", "12-25"]
        #expect(state.mutedDates.count == 2)
        #expect(state.mutedDates.contains("12-25"))
    }
}
