// AegisFeatureFlags.swift
// All aegis.<C-ID> flags default OFF — server-controlled, remotely killable.
// Safety-critical base flags (GUARDIAN/preflight) remain in AmenSafetyFeatureFlags (default ON).
// These flags gate NEW Aegis surfaces and capabilities introduced in Aegis v1.

import Foundation
import FirebaseRemoteConfig

@MainActor
final class AegisFeatureFlags: ObservableObject {

    static let shared = AegisFeatureFlags()
    private let remoteConfig = RemoteConfig.remoteConfig()

    // ── Vision Detection (C1–C13) ─────────────────────────────────────────

    @Published var c1ChildMinorPresence      = false
    @Published var c2SchoolExposure          = false
    @Published var c3HomeAddress             = false
    @Published var c4LicensePlate            = false
    @Published var c5SensitiveDocs           = false
    @Published var c6IdPassport              = false
    @Published var c7MedicalDocs             = false
    @Published var c8FinancialInfo           = false
    @Published var c9SensitiveBackground     = false
    @Published var c10MultiPersonFace        = false
    @Published var c11RealtimeLocation       = false
    @Published var c12RoutineMapping         = false
    @Published var c13ExifGpsStrip           = false

    // ── AI & Provenance (C14–C19) ─────────────────────────────────────────

    @Published var c14VoiceCloneRisk         = false
    @Published var c15DeepfakeDetection      = false
    @Published var c16C2paProvenance         = false
    @Published var c17SyntheticDisclosure    = false
    @Published var c18EditedRealityDisclosure = false
    @Published var c19AiCsamDetection        = false

    // ── Berean Safety (C20–C29) ───────────────────────────────────────────

    @Published var c20PauseBeforePosting     = false
    @Published var c21SpiritualAbuse         = false
    @Published var c22DonationFraud          = false
    @Published var c23PrayerExploitation     = false
    @Published var c24DoctrinalMisinfo       = false
    @Published var c25RomanceScam            = false
    @Published var c26SextortionPattern      = false
    @Published var c27AiCompanionReliance    = false
    @Published var c28FakeExpertise          = false
    @Published var c29ContextCollapseGuard   = false

    // ── Relationship & Harassment (C30–C39) ──────────────────────────────

    @Published var c30RelationshipPrivacy    = false
    @Published var c31RevengePosting         = false
    @Published var c32ScreenshotRisk         = false
    @Published var c33DoxxingDetection       = false
    @Published var c34StalkingPattern        = false
    @Published var c35CoordinatedHarassment  = false
    @Published var c36FakeAccountDetection   = false
    @Published var c37LeaderImpersonation    = false
    @Published var c38GroupInfiltration      = false
    @Published var c39RosterExposure         = false

    // ── Privacy Modes (C40–C43) ───────────────────────────────────────────

    @Published var c40FamilyPrivacyMode      = false
    @Published var c41ChurchSafetyMode       = false
    @Published var c42MinorProtectionMode    = false
    @Published var c43HighRiskRegionMode     = false

    // ── Vulnerable-User Protection (C44–C46) ─────────────────────────────

    @Published var c44GriefTargeting         = false
    @Published var c45ElderNewBeliever       = false
    @Published var c46CrisisFinancial        = false

    // ── Wellbeing (C47–C50) ───────────────────────────────────────────────

    @Published var c47HiddenPublicMetrics    = false
    @Published var c48AntiRageAmplification  = false
    @Published var c49AntiDoomscroll         = false
    @Published var c50MemoryResurfacing      = false

    // ── Data Rights & Tracking (C51–C58) ─────────────────────────────────

    @Published var c51NoSellGuarantee        = false
    @Published var c52TrackingMinimization   = false
    @Published var c53ShadowProfilePrevention = false
    @Published var c54CrossPlatformLinking   = false
    @Published var c55TrueRightToBeForgotten = false
    @Published var c56ReverseImageTraceability = false
    @Published var c57DigitalLegacy          = false
    @Published var c58DataPortability        = false

    // ─────────────────────────────────────────────────────────────────────

    private init() { fetchRemoteConfig() }

    // Lookup by AegisCapability
    func isEnabled(_ capability: AegisCapability) -> Bool {
        switch capability {
        case .childMinorPresence:      return c1ChildMinorPresence
        case .schoolExposure:          return c2SchoolExposure
        case .homeAddress:             return c3HomeAddress
        case .licensePlate:            return c4LicensePlate
        case .sensitiveDocs:           return c5SensitiveDocs
        case .idPassport:              return c6IdPassport
        case .medicalDocs:             return c7MedicalDocs
        case .financialInfo:           return c8FinancialInfo
        case .sensitiveBackground:     return c9SensitiveBackground
        case .multiPersonFace:         return c10MultiPersonFace
        case .realtimeLocation:        return c11RealtimeLocation
        case .routineMapping:          return c12RoutineMapping
        case .exifGpsStrip:            return c13ExifGpsStrip
        case .voiceCloneRisk:          return c14VoiceCloneRisk
        case .deepfakeDetection:       return c15DeepfakeDetection
        case .c2paProvenance:          return c16C2paProvenance
        case .syntheticDisclosure:     return c17SyntheticDisclosure
        case .editedRealityDisclosure: return c18EditedRealityDisclosure
        case .aiCsamDetection:         return c19AiCsamDetection
        case .pauseBeforePosting:      return c20PauseBeforePosting
        case .spiritualAbuse:          return c21SpiritualAbuse
        case .donationFraud:           return c22DonationFraud
        case .prayerExploitation:      return c23PrayerExploitation
        case .doctrinalMisinfo:        return c24DoctrinalMisinfo
        case .romanceScam:             return c25RomanceScam
        case .sextortionPattern:       return c26SextortionPattern
        case .aiCompanionReliance:     return c27AiCompanionReliance
        case .fakeExpertise:           return c28FakeExpertise
        case .contextCollapseGuard:    return c29ContextCollapseGuard
        case .relationshipPrivacy:     return c30RelationshipPrivacy
        case .revengePosting:          return c31RevengePosting
        case .screenshotRisk:          return c32ScreenshotRisk
        case .doxxingDetection:        return c33DoxxingDetection
        case .stalkingPattern:         return c34StalkingPattern
        case .coordinatedHarassment:   return c35CoordinatedHarassment
        case .fakeAccountDetection:    return c36FakeAccountDetection
        case .leaderImpersonation:     return c37LeaderImpersonation
        case .groupInfiltration:       return c38GroupInfiltration
        case .rosterExposure:          return c39RosterExposure
        case .familyPrivacyMode:       return c40FamilyPrivacyMode
        case .churchSafetyMode:        return c41ChurchSafetyMode
        case .minorProtectionMode:     return c42MinorProtectionMode
        case .highRiskRegionMode:      return c43HighRiskRegionMode
        case .griefTargeting:          return c44GriefTargeting
        case .elderNewBeliever:        return c45ElderNewBeliever
        case .crisisFinancial:         return c46CrisisFinancial
        case .hiddenPublicMetrics:     return c47HiddenPublicMetrics
        case .antiRageAmplification:   return c48AntiRageAmplification
        case .antiDoomscroll:          return c49AntiDoomscroll
        case .memoryResurfacing:       return c50MemoryResurfacing
        case .noSellGuarantee:         return c51NoSellGuarantee
        case .trackingMinimization:    return c52TrackingMinimization
        case .shadowProfilePrevention: return c53ShadowProfilePrevention
        case .crossPlatformLinking:    return c54CrossPlatformLinking
        case .trueRightToBeForgotten:  return c55TrueRightToBeForgotten
        case .reverseImageTraceability: return c56ReverseImageTraceability
        case .digitalLegacy:           return c57DigitalLegacy
        case .dataPortability:         return c58DataPortability
        }
    }

    func fetchRemoteConfig() {
        let defaults = Dictionary(
            uniqueKeysWithValues: AegisCapability.allCases.map { ($0.flagKey, false as NSObject) }
        )
        remoteConfig.setDefaults(defaults)
        remoteConfig.fetchAndActivate { [weak self] _, error in
            guard let self, error == nil else { return }
            Task { @MainActor in self.applyRemoteConfig() }
        }
    }

    private func applyRemoteConfig() {
        c1ChildMinorPresence       = remoteConfig.configValue(forKey: AegisCapability.childMinorPresence.flagKey).boolValue
        c2SchoolExposure           = remoteConfig.configValue(forKey: AegisCapability.schoolExposure.flagKey).boolValue
        c3HomeAddress              = remoteConfig.configValue(forKey: AegisCapability.homeAddress.flagKey).boolValue
        c4LicensePlate             = remoteConfig.configValue(forKey: AegisCapability.licensePlate.flagKey).boolValue
        c5SensitiveDocs            = remoteConfig.configValue(forKey: AegisCapability.sensitiveDocs.flagKey).boolValue
        c6IdPassport               = remoteConfig.configValue(forKey: AegisCapability.idPassport.flagKey).boolValue
        c7MedicalDocs              = remoteConfig.configValue(forKey: AegisCapability.medicalDocs.flagKey).boolValue
        c8FinancialInfo            = remoteConfig.configValue(forKey: AegisCapability.financialInfo.flagKey).boolValue
        c9SensitiveBackground      = remoteConfig.configValue(forKey: AegisCapability.sensitiveBackground.flagKey).boolValue
        c10MultiPersonFace         = remoteConfig.configValue(forKey: AegisCapability.multiPersonFace.flagKey).boolValue
        c11RealtimeLocation        = remoteConfig.configValue(forKey: AegisCapability.realtimeLocation.flagKey).boolValue
        c12RoutineMapping          = remoteConfig.configValue(forKey: AegisCapability.routineMapping.flagKey).boolValue
        c13ExifGpsStrip            = remoteConfig.configValue(forKey: AegisCapability.exifGpsStrip.flagKey).boolValue
        c14VoiceCloneRisk          = remoteConfig.configValue(forKey: AegisCapability.voiceCloneRisk.flagKey).boolValue
        c15DeepfakeDetection       = remoteConfig.configValue(forKey: AegisCapability.deepfakeDetection.flagKey).boolValue
        c16C2paProvenance          = remoteConfig.configValue(forKey: AegisCapability.c2paProvenance.flagKey).boolValue
        c17SyntheticDisclosure     = remoteConfig.configValue(forKey: AegisCapability.syntheticDisclosure.flagKey).boolValue
        c18EditedRealityDisclosure = remoteConfig.configValue(forKey: AegisCapability.editedRealityDisclosure.flagKey).boolValue
        c19AiCsamDetection         = remoteConfig.configValue(forKey: AegisCapability.aiCsamDetection.flagKey).boolValue
        c20PauseBeforePosting      = remoteConfig.configValue(forKey: AegisCapability.pauseBeforePosting.flagKey).boolValue
        c21SpiritualAbuse          = remoteConfig.configValue(forKey: AegisCapability.spiritualAbuse.flagKey).boolValue
        c22DonationFraud           = remoteConfig.configValue(forKey: AegisCapability.donationFraud.flagKey).boolValue
        c23PrayerExploitation      = remoteConfig.configValue(forKey: AegisCapability.prayerExploitation.flagKey).boolValue
        c24DoctrinalMisinfo        = remoteConfig.configValue(forKey: AegisCapability.doctrinalMisinfo.flagKey).boolValue
        c25RomanceScam             = remoteConfig.configValue(forKey: AegisCapability.romanceScam.flagKey).boolValue
        c26SextortionPattern       = remoteConfig.configValue(forKey: AegisCapability.sextortionPattern.flagKey).boolValue
        c27AiCompanionReliance     = remoteConfig.configValue(forKey: AegisCapability.aiCompanionReliance.flagKey).boolValue
        c28FakeExpertise           = remoteConfig.configValue(forKey: AegisCapability.fakeExpertise.flagKey).boolValue
        c29ContextCollapseGuard    = remoteConfig.configValue(forKey: AegisCapability.contextCollapseGuard.flagKey).boolValue
        c30RelationshipPrivacy     = remoteConfig.configValue(forKey: AegisCapability.relationshipPrivacy.flagKey).boolValue
        c31RevengePosting          = remoteConfig.configValue(forKey: AegisCapability.revengePosting.flagKey).boolValue
        c32ScreenshotRisk          = remoteConfig.configValue(forKey: AegisCapability.screenshotRisk.flagKey).boolValue
        c33DoxxingDetection        = remoteConfig.configValue(forKey: AegisCapability.doxxingDetection.flagKey).boolValue
        c34StalkingPattern         = remoteConfig.configValue(forKey: AegisCapability.stalkingPattern.flagKey).boolValue
        c35CoordinatedHarassment   = remoteConfig.configValue(forKey: AegisCapability.coordinatedHarassment.flagKey).boolValue
        c36FakeAccountDetection    = remoteConfig.configValue(forKey: AegisCapability.fakeAccountDetection.flagKey).boolValue
        c37LeaderImpersonation     = remoteConfig.configValue(forKey: AegisCapability.leaderImpersonation.flagKey).boolValue
        c38GroupInfiltration       = remoteConfig.configValue(forKey: AegisCapability.groupInfiltration.flagKey).boolValue
        c39RosterExposure          = remoteConfig.configValue(forKey: AegisCapability.rosterExposure.flagKey).boolValue
        c40FamilyPrivacyMode       = remoteConfig.configValue(forKey: AegisCapability.familyPrivacyMode.flagKey).boolValue
        c41ChurchSafetyMode        = remoteConfig.configValue(forKey: AegisCapability.churchSafetyMode.flagKey).boolValue
        c42MinorProtectionMode     = remoteConfig.configValue(forKey: AegisCapability.minorProtectionMode.flagKey).boolValue
        c43HighRiskRegionMode      = remoteConfig.configValue(forKey: AegisCapability.highRiskRegionMode.flagKey).boolValue
        c44GriefTargeting          = remoteConfig.configValue(forKey: AegisCapability.griefTargeting.flagKey).boolValue
        c45ElderNewBeliever        = remoteConfig.configValue(forKey: AegisCapability.elderNewBeliever.flagKey).boolValue
        c46CrisisFinancial         = remoteConfig.configValue(forKey: AegisCapability.crisisFinancial.flagKey).boolValue
        c47HiddenPublicMetrics     = remoteConfig.configValue(forKey: AegisCapability.hiddenPublicMetrics.flagKey).boolValue
        c48AntiRageAmplification   = remoteConfig.configValue(forKey: AegisCapability.antiRageAmplification.flagKey).boolValue
        c49AntiDoomscroll          = remoteConfig.configValue(forKey: AegisCapability.antiDoomscroll.flagKey).boolValue
        c50MemoryResurfacing       = remoteConfig.configValue(forKey: AegisCapability.memoryResurfacing.flagKey).boolValue
        c51NoSellGuarantee         = remoteConfig.configValue(forKey: AegisCapability.noSellGuarantee.flagKey).boolValue
        c52TrackingMinimization    = remoteConfig.configValue(forKey: AegisCapability.trackingMinimization.flagKey).boolValue
        c53ShadowProfilePrevention = remoteConfig.configValue(forKey: AegisCapability.shadowProfilePrevention.flagKey).boolValue
        c54CrossPlatformLinking    = remoteConfig.configValue(forKey: AegisCapability.crossPlatformLinking.flagKey).boolValue
        c55TrueRightToBeForgotten  = remoteConfig.configValue(forKey: AegisCapability.trueRightToBeForgotten.flagKey).boolValue
        c56ReverseImageTraceability = remoteConfig.configValue(forKey: AegisCapability.reverseImageTraceability.flagKey).boolValue
        c57DigitalLegacy           = remoteConfig.configValue(forKey: AegisCapability.digitalLegacy.flagKey).boolValue
        c58DataPortability         = remoteConfig.configValue(forKey: AegisCapability.dataPortability.flagKey).boolValue
    }
}
