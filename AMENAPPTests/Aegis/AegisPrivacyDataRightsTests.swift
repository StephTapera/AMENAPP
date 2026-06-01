// AegisPrivacyDataRightsTests.swift
// Tests C40–C43 privacy mode rules, C51 no-sell statement, C55 deletion manifest,
// callable request types, and escalation urgency levels.
// All tests are pure static/struct operations — no Firebase required.

import Foundation
import Testing
@testable import AMENAPP

@Suite("Aegis Privacy Mode & Data Rights Tests (C40–C58)")
struct AegisPrivacyDataRightsTests {

    // MARK: - C40 — Family Privacy Mode

    @Test("C40 — familyPrivacyMode has exactly 4 rules")
    @MainActor
    func c40RuleCount() {
        #expect(AegisPrivacyModeService.rulesFor(.familyPrivacyMode).count == 4)
    }

    @Test("C40 — all rule IDs are prefixed C40")
    @MainActor
    func c40RuleIdPrefix() {
        for rule in AegisPrivacyModeService.rulesFor(.familyPrivacyMode) {
            #expect(rule.ruleId.hasPrefix("C40"))
        }
    }

    @Test("C40 — all rule descriptions are non-empty")
    @MainActor
    func c40RuleDescriptions() {
        for rule in AegisPrivacyModeService.rulesFor(.familyPrivacyMode) {
            #expect(!rule.description.isEmpty)
        }
    }

    @Test("C40 — enforcement types include autoApply, requireConsent, and block")
    @MainActor
    func c40EnforcementCoverage() {
        let enforcements = Set(AegisPrivacyModeService.rulesFor(.familyPrivacyMode).map(\.enforcement))
        #expect(enforcements.contains(.autoApply))
        #expect(enforcements.contains(.requireConsent))
        #expect(enforcements.contains(.block))
    }

    // MARK: - C41 — Church Safety Mode

    @Test("C41 — churchSafetyMode has exactly 3 rules")
    @MainActor
    func c41RuleCount() {
        #expect(AegisPrivacyModeService.rulesFor(.churchSafetyMode).count == 3)
    }

    @Test("C41 — all rule IDs are prefixed C41")
    @MainActor
    func c41RuleIdPrefix() {
        for rule in AegisPrivacyModeService.rulesFor(.churchSafetyMode) {
            #expect(rule.ruleId.hasPrefix("C41"))
        }
    }

    @Test("C41 — includes a softPrompt rule for donation fraud advisory")
    @MainActor
    func c41HasSoftPrompt() {
        let enforcements = AegisPrivacyModeService.rulesFor(.churchSafetyMode).map(\.enforcement)
        #expect(enforcements.contains(.softPrompt))
    }

    @Test("C41 — includes a requireConsent rule for pastoral actions")
    @MainActor
    func c41HasRequireConsent() {
        let enforcements = AegisPrivacyModeService.rulesFor(.churchSafetyMode).map(\.enforcement)
        #expect(enforcements.contains(.requireConsent))
    }

    // MARK: - C42 — Minor Protection Mode

    @Test("C42 — minorProtectionMode has exactly 3 rules")
    @MainActor
    func c42RuleCount() {
        #expect(AegisPrivacyModeService.rulesFor(.minorProtectionMode).count == 3)
    }

    @Test("C42 — all rule IDs are prefixed C42")
    @MainActor
    func c42RuleIdPrefix() {
        for rule in AegisPrivacyModeService.rulesFor(.minorProtectionMode) {
            #expect(rule.ruleId.hasPrefix("C42"))
        }
    }

    @Test("C42 — at least 2 rules use .block enforcement")
    @MainActor
    func c42HasBlockEnforcements() {
        let blockCount = AegisPrivacyModeService.rulesFor(.minorProtectionMode)
            .filter { $0.enforcement == .block }.count
        #expect(blockCount >= 2)
    }

    @Test("C42 — has an autoApply rule for age-appropriate content filtering")
    @MainActor
    func c42HasAutoApply() {
        let enforcements = AegisPrivacyModeService.rulesFor(.minorProtectionMode).map(\.enforcement)
        #expect(enforcements.contains(.autoApply))
    }

    // MARK: - C43 — High-Risk Region Mode

    @Test("C43 — highRiskRegionMode has exactly 4 rules")
    @MainActor
    func c43RuleCount() {
        #expect(AegisPrivacyModeService.rulesFor(.highRiskRegionMode).count == 4)
    }

    @Test("C43 — all rule IDs are prefixed C43")
    @MainActor
    func c43RuleIdPrefix() {
        for rule in AegisPrivacyModeService.rulesFor(.highRiskRegionMode) {
            #expect(rule.ruleId.hasPrefix("C43"))
        }
    }

    @Test("C43 — all rules are .autoApply (no soft prompts in high-risk context)")
    @MainActor
    func c43AllAutoApply() {
        for rule in AegisPrivacyModeService.rulesFor(.highRiskRegionMode) {
            #expect(rule.enforcement == .autoApply)
        }
    }

    // MARK: - rulesFor edge cases

    @Test("rulesFor a non-privacy-mode capability returns empty")
    @MainActor
    func rulesForNonModeCapabilityReturnsEmpty() {
        #expect(AegisPrivacyModeService.rulesFor(.spiritualAbuse).isEmpty)
        #expect(AegisPrivacyModeService.rulesFor(.doxxingDetection).isEmpty)
        #expect(AegisPrivacyModeService.rulesFor(.hiddenPublicMetrics).isEmpty)
    }

    // MARK: - AegisPrivacyModeConfig

    @Test("C40 — AegisPrivacyModeConfig id equals capability rawValue (C40)")
    @MainActor
    func privacyModeConfigC40Id() {
        let config = AegisPrivacyModeConfig(
            capability: .familyPrivacyMode,
            isActive: false,
            rules: AegisPrivacyModeService.rulesFor(.familyPrivacyMode)
        )
        #expect(config.id == "C40")
        #expect(config.title == AegisCapability.familyPrivacyMode.displayName)
        #expect(!config.isActive)
    }

    @Test("C42 — AegisPrivacyModeConfig isActive can be toggled")
    @MainActor
    func privacyModeConfigToggleActive() {
        var config = AegisPrivacyModeConfig(
            capability: .minorProtectionMode,
            isActive: false,
            rules: AegisPrivacyModeService.rulesFor(.minorProtectionMode)
        )
        config.isActive = true
        #expect(config.isActive == true)
        #expect(config.id == "C42")
    }

    // MARK: - AegisPrivacyRule enforcement enum

    @Test("AegisRuleEnforcement rawValues are all non-empty")
    func enforcementRawValues() {
        let values: [AegisPrivacyRule.AegisRuleEnforcement] = [
            .softPrompt, .requireConsent, .autoApply, .block
        ]
        for v in values {
            #expect(!v.rawValue.isEmpty)
        }
    }

    @Test("AegisRuleEnforcement encodes and decodes correctly")
    func enforcementEncoding() throws {
        let values: [AegisPrivacyRule.AegisRuleEnforcement] = [
            .softPrompt, .requireConsent, .autoApply, .block
        ]
        for v in values {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(AegisPrivacyRule.AegisRuleEnforcement.self, from: data)
            #expect(decoded == v)
        }
    }

    // MARK: - C51 — No-Sell Guarantee (static statement, no network)

    @Test("C51 — noSellGuarantee is in dataRights lane")
    func c51Lane() {
        #expect(AegisCapability.noSellGuarantee.lane == .dataRights)
    }

    // MARK: - AegisPrivacyActionRequest types (C55–C58)

    @Test("AegisPrivacyActionType all rawValues are non-empty")
    func privacyActionTypeRawValues() {
        let types: [AegisPrivacyActionRequest.AegisPrivacyActionType] = [
            .exportData, .trueDelete, .applyMode, .deferLocation, .memorialAccount, .transferLegacy
        ]
        for t in types {
            #expect(!t.rawValue.isEmpty)
        }
    }

    @Test("AegisPrivacyActionType.trueDelete rawValue is 'delete'")
    func privacyActionTypeTrueDeleteRawValue() {
        #expect(AegisPrivacyActionRequest.AegisPrivacyActionType.trueDelete.rawValue == "delete")
    }

    @Test("AegisPrivacyActionType.exportData rawValue is 'export'")
    func privacyActionTypeExportRawValue() {
        #expect(AegisPrivacyActionRequest.AegisPrivacyActionType.exportData.rawValue == "export")
    }

    @Test("AegisPrivacyActionType.applyMode rawValue is 'apply_mode'")
    func privacyActionTypeApplyModeRawValue() {
        #expect(AegisPrivacyActionRequest.AegisPrivacyActionType.applyMode.rawValue == "apply_mode")
    }

    @Test("AegisPrivacyActionType.memorialAccount rawValue is 'memorial'")
    func privacyActionTypeMemorialRawValue() {
        #expect(AegisPrivacyActionRequest.AegisPrivacyActionType.memorialAccount.rawValue == "memorial")
    }

    @Test("AegisPrivacyActionType.transferLegacy rawValue is 'transfer_legacy'")
    func privacyActionTypeTransferLegacyRawValue() {
        #expect(AegisPrivacyActionRequest.AegisPrivacyActionType.transferLegacy.rawValue == "transfer_legacy")
    }

    @Test("AegisPrivacyActionType encodes and decodes all cases correctly")
    func privacyActionTypeEncoding() throws {
        let types: [AegisPrivacyActionRequest.AegisPrivacyActionType] = [
            .exportData, .trueDelete, .applyMode, .deferLocation, .memorialAccount, .transferLegacy
        ]
        for t in types {
            let data = try JSONEncoder().encode(t)
            let decoded = try JSONDecoder().decode(AegisPrivacyActionRequest.AegisPrivacyActionType.self, from: data)
            #expect(decoded == t)
        }
    }

    // MARK: - Callable request struct initializers

    @Test("AegisAnalyzeMediaRequest initializes with correct fields")
    func analyzeMediaRequestInit() {
        let req = AegisAnalyzeMediaRequest(
            mediaUrl: "https://example.com/img.jpg",
            mediaType: "image",
            userId: "uid-1",
            surface: "post",
            capabilities: ["C1", "C2", "C13"]
        )
        #expect(req.mediaUrl == "https://example.com/img.jpg")
        #expect(req.mediaType == "image")
        #expect(req.userId == "uid-1")
        #expect(req.surface == "post")
        #expect(req.capabilities.count == 3)
    }

    @Test("AegisReviewTextRequest initializes with context dictionary")
    func reviewTextRequestInit() {
        let req = AegisReviewTextRequest(
            text: "Can you send your address?",
            surface: "message",
            userId: "uid-2",
            capabilities: ["C21", "C33"],
            context: ["priorMessages": "3"]
        )
        #expect(req.text == "Can you send your address?")
        #expect(req.capabilities.contains("C33"))
        #expect(req.context["priorMessages"] == "3")
    }

    @Test("AegisAccountTrustRequest initializes with both user IDs")
    func accountTrustRequestInit() {
        let req = AegisAccountTrustRequest(
            targetUserId: "target-uid",
            requestingUserId: "requester-uid",
            capabilities: ["C36", "C37"]
        )
        #expect(req.targetUserId == "target-uid")
        #expect(req.requestingUserId == "requester-uid")
        #expect(req.capabilities.count == 2)
    }

    // MARK: - AegisEscalateRequest urgency

    @Test("AegisEscalateUrgency all cases encode/decode correctly")
    func escalateUrgencyEncoding() throws {
        let urgencies: [AegisEscalateRequest.AegisEscalateUrgency] = [.low, .medium, .high, .critical]
        for u in urgencies {
            let data = try JSONEncoder().encode(u)
            let decoded = try JSONDecoder().decode(AegisEscalateRequest.AegisEscalateUrgency.self, from: data)
            #expect(decoded == u)
        }
    }

    @Test("AegisEscalateUrgency.critical rawValue is 'critical'")
    func escalateUrgencyCriticalRawValue() {
        #expect(AegisEscalateRequest.AegisEscalateUrgency.critical.rawValue == "critical")
    }

    // MARK: - AegisLane coverage

    @Test("AegisLane has 8 distinct cases matching 8 capability groups")
    func aegisLaneCases() {
        #expect(AegisLane.allCases.count == 8)
    }

    @Test("AegisLane rawValues are all non-empty")
    func aegisLaneRawValues() {
        for lane in AegisLane.allCases {
            #expect(!lane.rawValue.isEmpty)
        }
    }

    @Test("Vision lane contains exactly 13 capabilities (C1–C13)")
    func visionLane13Capabilities() {
        let visionCaps = AegisCapability.allCases.filter { $0.lane == .vision }
        #expect(visionCaps.count == 13)
    }

    @Test("Provenance lane contains exactly 6 capabilities (C14–C19)")
    func provenanceLane6Capabilities() {
        let caps = AegisCapability.allCases.filter { $0.lane == .provenance }
        #expect(caps.count == 6)
    }

    @Test("Berean lane contains exactly 10 capabilities (C20–C29)")
    func bereanLane10Capabilities() {
        let caps = AegisCapability.allCases.filter { $0.lane == .berean }
        #expect(caps.count == 10)
    }

    @Test("Harassment lane contains exactly 10 capabilities (C30–C39)")
    func harassmentLane10Capabilities() {
        let caps = AegisCapability.allCases.filter { $0.lane == .harassment }
        #expect(caps.count == 10)
    }

    @Test("PrivacyModes lane contains exactly 4 capabilities (C40–C43)")
    func privacyModesLane4Capabilities() {
        let caps = AegisCapability.allCases.filter { $0.lane == .privacyModes }
        #expect(caps.count == 4)
    }

    @Test("VulnerableUser lane contains exactly 3 capabilities (C44–C46)")
    func vulnerableUserLane3Capabilities() {
        let caps = AegisCapability.allCases.filter { $0.lane == .vulnerableUser }
        #expect(caps.count == 3)
    }

    @Test("Wellbeing lane contains exactly 4 capabilities (C47–C50)")
    func wellbeingLane4Capabilities() {
        let caps = AegisCapability.allCases.filter { $0.lane == .wellbeing }
        #expect(caps.count == 4)
    }

    @Test("DataRights lane contains exactly 8 capabilities (C51–C58)")
    func dataRightsLane8Capabilities() {
        let caps = AegisCapability.allCases.filter { $0.lane == .dataRights }
        #expect(caps.count == 8)
    }

    @Test("All lane capability counts sum to 58")
    func allLaneCapabilitiesSumTo58() {
        let total = AegisLane.allCases.map { lane in
            AegisCapability.allCases.filter { $0.lane == lane }.count
        }.reduce(0, +)
        #expect(total == 58)
    }
}
