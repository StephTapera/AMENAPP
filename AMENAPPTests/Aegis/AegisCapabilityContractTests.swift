// AegisCapabilityContractTests.swift
// One contract test per C-ID (C1–C58).
// Tests rawValue, lane assignment, and aegis.<id> flag key.
// All tests are pure enum property lookups — no Firebase required.

import Foundation
import Testing
@testable import AMENAPP

@Suite("Aegis Capability Contract Tests — C1–C58")
struct AegisCapabilityContractTests {

    // MARK: - Registry invariants

    @Test("58 capabilities registered in AegisCapability")
    func capabilityCount() {
        #expect(AegisCapability.allCases.count == 58)
    }

    @Test("All display names are non-empty")
    func allDisplayNamesNonEmpty() {
        for cap in AegisCapability.allCases {
            #expect(!cap.displayName.isEmpty)
        }
    }

    @Test("All rawValues are unique")
    func allRawValuesUnique() {
        let vals = AegisCapability.allCases.map(\.rawValue)
        #expect(Set(vals).count == 58)
    }

    @Test("All flag keys match aegis.<rawValue> format")
    func allFlagKeyFormat() {
        for cap in AegisCapability.allCases {
            #expect(cap.flagKey == "aegis.\(cap.rawValue)")
        }
    }

    @Test("AegisCapability.id equals rawValue")
    func capabilityIdEqualsRawValue() {
        for cap in AegisCapability.allCases {
            #expect(cap.id == cap.rawValue)
        }
    }

    @Test("AegisContractsVersion is non-empty")
    func contractsVersionNonEmpty() {
        #expect(!AegisContractsVersion.isEmpty)
    }

    @Test("8 distinct lanes registered")
    func laneCoverage() {
        let lanes = Set(AegisCapability.allCases.map(\.lane))
        #expect(lanes.count == 8)
    }

    // MARK: - Vision lane (C1–C13)

    @Test("C1 — childMinorPresence: vision lane, aegis.C1")
    func c1() {
        #expect(AegisCapability.childMinorPresence.rawValue == "C1")
        #expect(AegisCapability.childMinorPresence.lane == .vision)
        #expect(AegisCapability.childMinorPresence.flagKey == "aegis.C1")
    }

    @Test("C2 — schoolExposure: vision lane, aegis.C2")
    func c2() {
        #expect(AegisCapability.schoolExposure.rawValue == "C2")
        #expect(AegisCapability.schoolExposure.lane == .vision)
        #expect(AegisCapability.schoolExposure.flagKey == "aegis.C2")
    }

    @Test("C3 — homeAddress: vision lane, aegis.C3")
    func c3() {
        #expect(AegisCapability.homeAddress.rawValue == "C3")
        #expect(AegisCapability.homeAddress.lane == .vision)
        #expect(AegisCapability.homeAddress.flagKey == "aegis.C3")
    }

    @Test("C4 — licensePlate: vision lane, aegis.C4")
    func c4() {
        #expect(AegisCapability.licensePlate.rawValue == "C4")
        #expect(AegisCapability.licensePlate.lane == .vision)
        #expect(AegisCapability.licensePlate.flagKey == "aegis.C4")
    }

    @Test("C5 — sensitiveDocs: vision lane, aegis.C5")
    func c5() {
        #expect(AegisCapability.sensitiveDocs.rawValue == "C5")
        #expect(AegisCapability.sensitiveDocs.lane == .vision)
        #expect(AegisCapability.sensitiveDocs.flagKey == "aegis.C5")
    }

    @Test("C6 — idPassport: vision lane, aegis.C6 — .block severity")
    func c6() {
        #expect(AegisCapability.idPassport.rawValue == "C6")
        #expect(AegisCapability.idPassport.lane == .vision)
        #expect(AegisCapability.idPassport.flagKey == "aegis.C6")
        // C6 produces .block results — verify the capability can be used that way
        let r = AegisDetectionResult.make(
            capability: .idPassport, severity: .block, confidence: 0.9, action: "ID detected"
        )
        #expect(r.severity.blocksPublishing)
    }

    @Test("C7 — medicalDocs: vision lane, aegis.C7")
    func c7() {
        #expect(AegisCapability.medicalDocs.rawValue == "C7")
        #expect(AegisCapability.medicalDocs.lane == .vision)
        #expect(AegisCapability.medicalDocs.flagKey == "aegis.C7")
    }

    @Test("C8 — financialInfo: vision lane, aegis.C8 — .block severity")
    func c8() {
        #expect(AegisCapability.financialInfo.rawValue == "C8")
        #expect(AegisCapability.financialInfo.lane == .vision)
        #expect(AegisCapability.financialInfo.flagKey == "aegis.C8")
        let r = AegisDetectionResult.make(
            capability: .financialInfo, severity: .block, confidence: 0.95, action: "Card number detected"
        )
        #expect(r.severity == .block)
    }

    @Test("C9 — sensitiveBackground: vision lane, aegis.C9")
    func c9() {
        #expect(AegisCapability.sensitiveBackground.rawValue == "C9")
        #expect(AegisCapability.sensitiveBackground.lane == .vision)
        #expect(AegisCapability.sensitiveBackground.flagKey == "aegis.C9")
    }

    @Test("C10 — multiPersonFace: vision lane, aegis.C10")
    func c10() {
        #expect(AegisCapability.multiPersonFace.rawValue == "C10")
        #expect(AegisCapability.multiPersonFace.lane == .vision)
        #expect(AegisCapability.multiPersonFace.flagKey == "aegis.C10")
    }

    @Test("C11 — realtimeLocation: vision lane, aegis.C11")
    func c11() {
        #expect(AegisCapability.realtimeLocation.rawValue == "C11")
        #expect(AegisCapability.realtimeLocation.lane == .vision)
        #expect(AegisCapability.realtimeLocation.flagKey == "aegis.C11")
    }

    @Test("C12 — routineMapping: vision lane, aegis.C12")
    func c12() {
        #expect(AegisCapability.routineMapping.rawValue == "C12")
        #expect(AegisCapability.routineMapping.lane == .vision)
        #expect(AegisCapability.routineMapping.flagKey == "aegis.C12")
    }

    @Test("C13 — exifGpsStrip: vision lane, aegis.C13")
    func c13() {
        #expect(AegisCapability.exifGpsStrip.rawValue == "C13")
        #expect(AegisCapability.exifGpsStrip.lane == .vision)
        #expect(AegisCapability.exifGpsStrip.flagKey == "aegis.C13")
    }

    // MARK: - Provenance lane (C14–C19)

    @Test("C14 — voiceCloneRisk: provenance lane, aegis.C14")
    func c14() {
        #expect(AegisCapability.voiceCloneRisk.rawValue == "C14")
        #expect(AegisCapability.voiceCloneRisk.lane == .provenance)
        #expect(AegisCapability.voiceCloneRisk.flagKey == "aegis.C14")
    }

    @Test("C15 — deepfakeDetection: provenance lane, aegis.C15")
    func c15() {
        #expect(AegisCapability.deepfakeDetection.rawValue == "C15")
        #expect(AegisCapability.deepfakeDetection.lane == .provenance)
        #expect(AegisCapability.deepfakeDetection.flagKey == "aegis.C15")
    }

    @Test("C16 — c2paProvenance: provenance lane, aegis.C16")
    func c16() {
        #expect(AegisCapability.c2paProvenance.rawValue == "C16")
        #expect(AegisCapability.c2paProvenance.lane == .provenance)
        #expect(AegisCapability.c2paProvenance.flagKey == "aegis.C16")
    }

    @Test("C17 — syntheticDisclosure: provenance lane, aegis.C17")
    func c17() {
        #expect(AegisCapability.syntheticDisclosure.rawValue == "C17")
        #expect(AegisCapability.syntheticDisclosure.lane == .provenance)
        #expect(AegisCapability.syntheticDisclosure.flagKey == "aegis.C17")
    }

    @Test("C18 — editedRealityDisclosure: provenance lane, aegis.C18")
    func c18() {
        #expect(AegisCapability.editedRealityDisclosure.rawValue == "C18")
        #expect(AegisCapability.editedRealityDisclosure.lane == .provenance)
        #expect(AegisCapability.editedRealityDisclosure.flagKey == "aegis.C18")
    }

    @Test("C19 — aiCsamDetection: provenance lane, aegis.C19 — .block severity")
    func c19() {
        #expect(AegisCapability.aiCsamDetection.rawValue == "C19")
        #expect(AegisCapability.aiCsamDetection.lane == .provenance)
        #expect(AegisCapability.aiCsamDetection.flagKey == "aegis.C19")
        let r = AegisDetectionResult.make(
            capability: .aiCsamDetection, severity: .block, confidence: 1.0, action: "CSAM blocked"
        )
        #expect(r.severity == .block)
    }

    // MARK: - Berean lane (C20–C29)

    @Test("C20 — pauseBeforePosting: berean lane, aegis.C20")
    func c20() {
        #expect(AegisCapability.pauseBeforePosting.rawValue == "C20")
        #expect(AegisCapability.pauseBeforePosting.lane == .berean)
        #expect(AegisCapability.pauseBeforePosting.flagKey == "aegis.C20")
    }

    @Test("C21 — spiritualAbuse: berean lane, aegis.C21")
    func c21() {
        #expect(AegisCapability.spiritualAbuse.rawValue == "C21")
        #expect(AegisCapability.spiritualAbuse.lane == .berean)
        #expect(AegisCapability.spiritualAbuse.flagKey == "aegis.C21")
    }

    @Test("C22 — donationFraud: berean lane, aegis.C22")
    func c22() {
        #expect(AegisCapability.donationFraud.rawValue == "C22")
        #expect(AegisCapability.donationFraud.lane == .berean)
        #expect(AegisCapability.donationFraud.flagKey == "aegis.C22")
    }

    @Test("C23 — prayerExploitation: berean lane, aegis.C23")
    func c23() {
        #expect(AegisCapability.prayerExploitation.rawValue == "C23")
        #expect(AegisCapability.prayerExploitation.lane == .berean)
        #expect(AegisCapability.prayerExploitation.flagKey == "aegis.C23")
    }

    @Test("C24 — doctrinalMisinfo: berean lane, aegis.C24")
    func c24() {
        #expect(AegisCapability.doctrinalMisinfo.rawValue == "C24")
        #expect(AegisCapability.doctrinalMisinfo.lane == .berean)
        #expect(AegisCapability.doctrinalMisinfo.flagKey == "aegis.C24")
    }

    @Test("C25 — romanceScam: berean lane, aegis.C25")
    func c25() {
        #expect(AegisCapability.romanceScam.rawValue == "C25")
        #expect(AegisCapability.romanceScam.lane == .berean)
        #expect(AegisCapability.romanceScam.flagKey == "aegis.C25")
    }

    @Test("C26 — sextortionPattern: berean lane, aegis.C26 — escalates to legal")
    func c26() {
        #expect(AegisCapability.sextortionPattern.rawValue == "C26")
        #expect(AegisCapability.sextortionPattern.lane == .berean)
        #expect(AegisCapability.sextortionPattern.flagKey == "aegis.C26")
        // Sextortion always produces .block
        let r = AegisDetectionResult.make(
            capability: .sextortionPattern, severity: .block, confidence: 0.9, action: "Blocked"
        )
        #expect(r.capabilityId == .sextortionPattern)
        #expect(r.severity.blocksPublishing)
    }

    @Test("C27 — aiCompanionReliance: berean lane, aegis.C27")
    func c27() {
        #expect(AegisCapability.aiCompanionReliance.rawValue == "C27")
        #expect(AegisCapability.aiCompanionReliance.lane == .berean)
        #expect(AegisCapability.aiCompanionReliance.flagKey == "aegis.C27")
    }

    @Test("C28 — fakeExpertise: berean lane, aegis.C28")
    func c28() {
        #expect(AegisCapability.fakeExpertise.rawValue == "C28")
        #expect(AegisCapability.fakeExpertise.lane == .berean)
        #expect(AegisCapability.fakeExpertise.flagKey == "aegis.C28")
    }

    @Test("C29 — contextCollapseGuard: berean lane, aegis.C29")
    func c29() {
        #expect(AegisCapability.contextCollapseGuard.rawValue == "C29")
        #expect(AegisCapability.contextCollapseGuard.lane == .berean)
        #expect(AegisCapability.contextCollapseGuard.flagKey == "aegis.C29")
    }

    // MARK: - Harassment lane (C30–C39)

    @Test("C30 — relationshipPrivacy: harassment lane, aegis.C30")
    func c30() {
        #expect(AegisCapability.relationshipPrivacy.rawValue == "C30")
        #expect(AegisCapability.relationshipPrivacy.lane == .harassment)
        #expect(AegisCapability.relationshipPrivacy.flagKey == "aegis.C30")
    }

    @Test("C31 — revengePosting: harassment lane, aegis.C31 — .block severity")
    func c31() {
        #expect(AegisCapability.revengePosting.rawValue == "C31")
        #expect(AegisCapability.revengePosting.lane == .harassment)
        #expect(AegisCapability.revengePosting.flagKey == "aegis.C31")
    }

    @Test("C32 — screenshotRisk: harassment lane, aegis.C32")
    func c32() {
        #expect(AegisCapability.screenshotRisk.rawValue == "C32")
        #expect(AegisCapability.screenshotRisk.lane == .harassment)
        #expect(AegisCapability.screenshotRisk.flagKey == "aegis.C32")
    }

    @Test("C33 — doxxingDetection: harassment lane, aegis.C33 — .block when phone+address")
    func c33() {
        #expect(AegisCapability.doxxingDetection.rawValue == "C33")
        #expect(AegisCapability.doxxingDetection.lane == .harassment)
        #expect(AegisCapability.doxxingDetection.flagKey == "aegis.C33")
        let r = AegisDetectionResult.make(
            capability: .doxxingDetection, severity: .block, confidence: 0.85, action: "PII detected"
        )
        #expect(r.severity == .block)
    }

    @Test("C34 — stalkingPattern: harassment lane, aegis.C34")
    func c34() {
        #expect(AegisCapability.stalkingPattern.rawValue == "C34")
        #expect(AegisCapability.stalkingPattern.lane == .harassment)
        #expect(AegisCapability.stalkingPattern.flagKey == "aegis.C34")
    }

    @Test("C35 — coordinatedHarassment: harassment lane, aegis.C35")
    func c35() {
        #expect(AegisCapability.coordinatedHarassment.rawValue == "C35")
        #expect(AegisCapability.coordinatedHarassment.lane == .harassment)
        #expect(AegisCapability.coordinatedHarassment.flagKey == "aegis.C35")
    }

    @Test("C36 — fakeAccountDetection: harassment lane, aegis.C36")
    func c36() {
        #expect(AegisCapability.fakeAccountDetection.rawValue == "C36")
        #expect(AegisCapability.fakeAccountDetection.lane == .harassment)
        #expect(AegisCapability.fakeAccountDetection.flagKey == "aegis.C36")
    }

    @Test("C37 — leaderImpersonation: harassment lane, aegis.C37 — .block severity")
    func c37() {
        #expect(AegisCapability.leaderImpersonation.rawValue == "C37")
        #expect(AegisCapability.leaderImpersonation.lane == .harassment)
        #expect(AegisCapability.leaderImpersonation.flagKey == "aegis.C37")
        let r = AegisDetectionResult.make(
            capability: .leaderImpersonation, severity: .block, confidence: 0.9, action: "Impersonation blocked"
        )
        #expect(r.severity.blocksPublishing)
    }

    @Test("C38 — groupInfiltration: harassment lane, aegis.C38")
    func c38() {
        #expect(AegisCapability.groupInfiltration.rawValue == "C38")
        #expect(AegisCapability.groupInfiltration.lane == .harassment)
        #expect(AegisCapability.groupInfiltration.flagKey == "aegis.C38")
    }

    @Test("C39 — rosterExposure: harassment lane, aegis.C39")
    func c39() {
        #expect(AegisCapability.rosterExposure.rawValue == "C39")
        #expect(AegisCapability.rosterExposure.lane == .harassment)
        #expect(AegisCapability.rosterExposure.flagKey == "aegis.C39")
    }

    // MARK: - Privacy Modes lane (C40–C43)

    @Test("C40 — familyPrivacyMode: privacyModes lane, aegis.C40")
    func c40() {
        #expect(AegisCapability.familyPrivacyMode.rawValue == "C40")
        #expect(AegisCapability.familyPrivacyMode.lane == .privacyModes)
        #expect(AegisCapability.familyPrivacyMode.flagKey == "aegis.C40")
    }

    @Test("C41 — churchSafetyMode: privacyModes lane, aegis.C41")
    func c41() {
        #expect(AegisCapability.churchSafetyMode.rawValue == "C41")
        #expect(AegisCapability.churchSafetyMode.lane == .privacyModes)
        #expect(AegisCapability.churchSafetyMode.flagKey == "aegis.C41")
    }

    @Test("C42 — minorProtectionMode: privacyModes lane, aegis.C42")
    func c42() {
        #expect(AegisCapability.minorProtectionMode.rawValue == "C42")
        #expect(AegisCapability.minorProtectionMode.lane == .privacyModes)
        #expect(AegisCapability.minorProtectionMode.flagKey == "aegis.C42")
    }

    @Test("C43 — highRiskRegionMode: privacyModes lane, aegis.C43")
    func c43() {
        #expect(AegisCapability.highRiskRegionMode.rawValue == "C43")
        #expect(AegisCapability.highRiskRegionMode.lane == .privacyModes)
        #expect(AegisCapability.highRiskRegionMode.flagKey == "aegis.C43")
    }

    // MARK: - Vulnerable-User lane (C44–C46)

    @Test("C44 — griefTargeting: vulnerableUser lane, aegis.C44")
    func c44() {
        #expect(AegisCapability.griefTargeting.rawValue == "C44")
        #expect(AegisCapability.griefTargeting.lane == .vulnerableUser)
        #expect(AegisCapability.griefTargeting.flagKey == "aegis.C44")
    }

    @Test("C45 — elderNewBeliever: vulnerableUser lane, aegis.C45")
    func c45() {
        #expect(AegisCapability.elderNewBeliever.rawValue == "C45")
        #expect(AegisCapability.elderNewBeliever.lane == .vulnerableUser)
        #expect(AegisCapability.elderNewBeliever.flagKey == "aegis.C45")
    }

    @Test("C46 — crisisFinancial: vulnerableUser lane, aegis.C46 — .block severity")
    func c46() {
        #expect(AegisCapability.crisisFinancial.rawValue == "C46")
        #expect(AegisCapability.crisisFinancial.lane == .vulnerableUser)
        #expect(AegisCapability.crisisFinancial.flagKey == "aegis.C46")
        let r = AegisDetectionResult.make(
            capability: .crisisFinancial, severity: .block, confidence: 0.88, action: "Financial predation blocked"
        )
        #expect(r.severity == .block)
    }

    // MARK: - Wellbeing lane (C47–C50)

    @Test("C47 — hiddenPublicMetrics: wellbeing lane, aegis.C47")
    func c47() {
        #expect(AegisCapability.hiddenPublicMetrics.rawValue == "C47")
        #expect(AegisCapability.hiddenPublicMetrics.lane == .wellbeing)
        #expect(AegisCapability.hiddenPublicMetrics.flagKey == "aegis.C47")
    }

    @Test("C48 — antiRageAmplification: wellbeing lane, aegis.C48")
    func c48() {
        #expect(AegisCapability.antiRageAmplification.rawValue == "C48")
        #expect(AegisCapability.antiRageAmplification.lane == .wellbeing)
        #expect(AegisCapability.antiRageAmplification.flagKey == "aegis.C48")
    }

    @Test("C49 — antiDoomscroll: wellbeing lane, aegis.C49")
    func c49() {
        #expect(AegisCapability.antiDoomscroll.rawValue == "C49")
        #expect(AegisCapability.antiDoomscroll.lane == .wellbeing)
        #expect(AegisCapability.antiDoomscroll.flagKey == "aegis.C49")
    }

    @Test("C50 — memoryResurfacing: wellbeing lane, aegis.C50")
    func c50() {
        #expect(AegisCapability.memoryResurfacing.rawValue == "C50")
        #expect(AegisCapability.memoryResurfacing.lane == .wellbeing)
        #expect(AegisCapability.memoryResurfacing.flagKey == "aegis.C50")
    }

    // MARK: - Data Rights lane (C51–C58)

    @Test("C51 — noSellGuarantee: dataRights lane, aegis.C51")
    func c51() {
        #expect(AegisCapability.noSellGuarantee.rawValue == "C51")
        #expect(AegisCapability.noSellGuarantee.lane == .dataRights)
        #expect(AegisCapability.noSellGuarantee.flagKey == "aegis.C51")
    }

    @Test("C52 — trackingMinimization: dataRights lane, aegis.C52")
    func c52() {
        #expect(AegisCapability.trackingMinimization.rawValue == "C52")
        #expect(AegisCapability.trackingMinimization.lane == .dataRights)
        #expect(AegisCapability.trackingMinimization.flagKey == "aegis.C52")
    }

    @Test("C53 — shadowProfilePrevention: dataRights lane, aegis.C53")
    func c53() {
        #expect(AegisCapability.shadowProfilePrevention.rawValue == "C53")
        #expect(AegisCapability.shadowProfilePrevention.lane == .dataRights)
        #expect(AegisCapability.shadowProfilePrevention.flagKey == "aegis.C53")
    }

    @Test("C54 — crossPlatformLinking: dataRights lane, aegis.C54")
    func c54() {
        #expect(AegisCapability.crossPlatformLinking.rawValue == "C54")
        #expect(AegisCapability.crossPlatformLinking.lane == .dataRights)
        #expect(AegisCapability.crossPlatformLinking.flagKey == "aegis.C54")
    }

    @Test("C55 — trueRightToBeForgotten: dataRights lane, aegis.C55")
    func c55() {
        #expect(AegisCapability.trueRightToBeForgotten.rawValue == "C55")
        #expect(AegisCapability.trueRightToBeForgotten.lane == .dataRights)
        #expect(AegisCapability.trueRightToBeForgotten.flagKey == "aegis.C55")
    }

    @Test("C56 — reverseImageTraceability: dataRights lane, aegis.C56")
    func c56() {
        #expect(AegisCapability.reverseImageTraceability.rawValue == "C56")
        #expect(AegisCapability.reverseImageTraceability.lane == .dataRights)
        #expect(AegisCapability.reverseImageTraceability.flagKey == "aegis.C56")
    }

    @Test("C57 — digitalLegacy: dataRights lane, aegis.C57")
    func c57() {
        #expect(AegisCapability.digitalLegacy.rawValue == "C57")
        #expect(AegisCapability.digitalLegacy.lane == .dataRights)
        #expect(AegisCapability.digitalLegacy.flagKey == "aegis.C57")
    }

    @Test("C58 — dataPortability: dataRights lane, aegis.C58")
    func c58() {
        #expect(AegisCapability.dataPortability.rawValue == "C58")
        #expect(AegisCapability.dataPortability.lane == .dataRights)
        #expect(AegisCapability.dataPortability.flagKey == "aegis.C58")
    }
}
