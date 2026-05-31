// AegisContracts.swift — CONTRACTS v1 FROZEN 2026-05-31
// Do not modify without bumping AegisContractsVersion and broadcasting to all agents.

import Foundation

let AegisContractsVersion = "2026-05-31-v1"

// MARK: - Capability Registry (C1–C58)

enum AegisCapability: String, CaseIterable, Codable, Identifiable {
    // Vision Detection (on-device first)
    case childMinorPresence      = "C1"
    case schoolExposure          = "C2"
    case homeAddress             = "C3"
    case licensePlate            = "C4"
    case sensitiveDocs           = "C5"
    case idPassport              = "C6"
    case medicalDocs             = "C7"
    case financialInfo           = "C8"
    case sensitiveBackground     = "C9"
    case multiPersonFace         = "C10"
    case realtimeLocation        = "C11"
    case routineMapping          = "C12"
    case exifGpsStrip            = "C13"
    // AI & Provenance
    case voiceCloneRisk          = "C14"
    case deepfakeDetection       = "C15"
    case c2paProvenance          = "C16"
    case syntheticDisclosure     = "C17"
    case editedRealityDisclosure = "C18"
    case aiCsamDetection         = "C19"
    // Berean-Powered Safety
    case pauseBeforePosting      = "C20"
    case spiritualAbuse          = "C21"
    case donationFraud           = "C22"
    case prayerExploitation      = "C23"
    case doctrinalMisinfo        = "C24"
    case romanceScam             = "C25"
    case sextortionPattern       = "C26"
    case aiCompanionReliance     = "C27"
    case fakeExpertise           = "C28"
    case contextCollapseGuard    = "C29"
    // Relationship & Harassment
    case relationshipPrivacy     = "C30"
    case revengePosting          = "C31"
    case screenshotRisk          = "C32"
    case doxxingDetection        = "C33"
    case stalkingPattern         = "C34"
    case coordinatedHarassment   = "C35"
    case fakeAccountDetection    = "C36"
    case leaderImpersonation     = "C37"
    case groupInfiltration       = "C38"
    case rosterExposure          = "C39"
    // Privacy Modes
    case familyPrivacyMode       = "C40"
    case churchSafetyMode        = "C41"
    case minorProtectionMode     = "C42"
    case highRiskRegionMode      = "C43"
    // Vulnerable-User Protection
    case griefTargeting          = "C44"
    case elderNewBeliever        = "C45"
    case crisisFinancial         = "C46"
    // Wellbeing
    case hiddenPublicMetrics     = "C47"
    case antiRageAmplification   = "C48"
    case antiDoomscroll          = "C49"
    case memoryResurfacing       = "C50"
    // Data Rights & Tracking
    case noSellGuarantee         = "C51"
    case trackingMinimization    = "C52"
    case shadowProfilePrevention = "C53"
    case crossPlatformLinking    = "C54"
    case trueRightToBeForgotten  = "C55"
    case reverseImageTraceability = "C56"
    case digitalLegacy           = "C57"
    case dataPortability         = "C58"

    var id: String { rawValue }

    // Human-readable name for UI
    var displayName: String {
        switch self {
        case .childMinorPresence:      return "Child/Minor Presence"
        case .schoolExposure:          return "School Exposure"
        case .homeAddress:             return "Home Address"
        case .licensePlate:            return "License Plate"
        case .sensitiveDocs:           return "Sensitive Document"
        case .idPassport:              return "ID / Passport"
        case .medicalDocs:             return "Medical Documents"
        case .financialInfo:           return "Financial Information"
        case .sensitiveBackground:     return "Sensitive Background"
        case .multiPersonFace:         return "Multi-Person Face"
        case .realtimeLocation:        return "Real-time Location"
        case .routineMapping:          return "Daily Routine Mapping"
        case .exifGpsStrip:            return "EXIF / GPS Strip"
        case .voiceCloneRisk:          return "Voice Clone Risk"
        case .deepfakeDetection:       return "Deepfake Detection"
        case .c2paProvenance:          return "C2PA Content Credentials"
        case .syntheticDisclosure:     return "Synthetic Account Disclosure"
        case .editedRealityDisclosure: return "Edited Reality Disclosure"
        case .aiCsamDetection:         return "AI-Generated CSAM Detection"
        case .pauseBeforePosting:      return "Pause Before Posting"
        case .spiritualAbuse:          return "Spiritual Abuse / Coercive Control"
        case .donationFraud:           return "Donation / Ministry Fraud"
        case .prayerExploitation:      return "Prayer-Request Exploitation"
        case .doctrinalMisinfo:        return "Doctrinal Misinformation"
        case .romanceScam:             return "Romance / Pig-Butchering Scam"
        case .sextortionPattern:       return "Sextortion Pattern"
        case .aiCompanionReliance:     return "AI Companion Over-Reliance"
        case .fakeExpertise:           return "Fake Expertise Claim"
        case .contextCollapseGuard:    return "Context-Collapse Guard"
        case .relationshipPrivacy:     return "Relationship Privacy"
        case .revengePosting:          return "Revenge Posting"
        case .screenshotRisk:          return "Screenshot Risk"
        case .doxxingDetection:        return "Doxxing Detection"
        case .stalkingPattern:         return "Stalking-Pattern Protection"
        case .coordinatedHarassment:   return "Coordinated Harassment"
        case .fakeAccountDetection:    return "Fake Account / Impersonation"
        case .leaderImpersonation:     return "Leader Impersonation"
        case .groupInfiltration:       return "Group Infiltration"
        case .rosterExposure:          return "Member Roster Exposure"
        case .familyPrivacyMode:       return "Family Privacy Mode"
        case .churchSafetyMode:        return "Church Safety Mode"
        case .minorProtectionMode:     return "Minor Protection Mode"
        case .highRiskRegionMode:      return "High-Risk Region Mode"
        case .griefTargeting:          return "Grief / Bereavement Targeting"
        case .elderNewBeliever:        return "Elder & New-Believer Protection"
        case .crisisFinancial:         return "Crisis-State Financial Predation"
        case .hiddenPublicMetrics:     return "Hidden Public Metrics"
        case .antiRageAmplification:   return "Anti-Rage Amplification"
        case .antiDoomscroll:          return "Anti-Doomscroll"
        case .memoryResurfacing:       return "Memory Resurfacing Controls"
        case .noSellGuarantee:         return "No-Sell Guarantee"
        case .trackingMinimization:    return "Tracking Minimization"
        case .shadowProfilePrevention: return "Shadow Profile Prevention"
        case .crossPlatformLinking:    return "Cross-Platform Identity Linking"
        case .trueRightToBeForgotten:  return "Right to Be Forgotten"
        case .reverseImageTraceability: return "Reverse-Image Traceability"
        case .digitalLegacy:           return "Digital Legacy"
        case .dataPortability:         return "Data Portability"
        }
    }

    // Lane assignment for routing
    var lane: AegisLane {
        switch self {
        case .childMinorPresence, .schoolExposure, .homeAddress, .licensePlate,
             .sensitiveDocs, .idPassport, .medicalDocs, .financialInfo,
             .sensitiveBackground, .multiPersonFace, .realtimeLocation,
             .routineMapping, .exifGpsStrip:
            return .vision
        case .voiceCloneRisk, .deepfakeDetection, .c2paProvenance,
             .syntheticDisclosure, .editedRealityDisclosure, .aiCsamDetection:
            return .provenance
        case .pauseBeforePosting, .spiritualAbuse, .donationFraud,
             .prayerExploitation, .doctrinalMisinfo, .romanceScam,
             .sextortionPattern, .aiCompanionReliance, .fakeExpertise,
             .contextCollapseGuard:
            return .berean
        case .relationshipPrivacy, .revengePosting, .screenshotRisk,
             .doxxingDetection, .stalkingPattern, .coordinatedHarassment,
             .fakeAccountDetection, .leaderImpersonation, .groupInfiltration,
             .rosterExposure:
            return .harassment
        case .familyPrivacyMode, .churchSafetyMode, .minorProtectionMode,
             .highRiskRegionMode:
            return .privacyModes
        case .griefTargeting, .elderNewBeliever, .crisisFinancial:
            return .vulnerableUser
        case .hiddenPublicMetrics, .antiRageAmplification, .antiDoomscroll,
             .memoryResurfacing:
            return .wellbeing
        case .noSellGuarantee, .trackingMinimization, .shadowProfilePrevention,
             .crossPlatformLinking, .trueRightToBeForgotten,
             .reverseImageTraceability, .digitalLegacy, .dataPortability:
            return .dataRights
        }
    }

    // Feature flag key: "aegis.<rawValue>"
    var flagKey: String { "aegis.\(rawValue)" }
}

enum AegisLane: String, CaseIterable {
    case vision, provenance, berean, harassment
    case privacyModes, vulnerableUser, wellbeing, dataRights
}

// MARK: - Severity

enum AegisSeverity: String, Codable, CaseIterable, Comparable {
    case info    = "info"
    case caution = "caution"
    case warn    = "warn"
    case block   = "block"

    private var order: Int {
        switch self {
        case .info: return 0; case .caution: return 1
        case .warn: return 2; case .block: return 3
        }
    }

    static func < (lhs: AegisSeverity, rhs: AegisSeverity) -> Bool {
        lhs.order < rhs.order
    }

    var isActionable: Bool { self >= .caution }
    var blocksPublishing: Bool { self == .block }

    // Bridge to SafetyDecisionOutcome for existing preflight pipeline
    var outcomeMapping: SafetyDecisionOutcome {
        switch self {
        case .info:    return .allow
        case .caution: return .allowWithLabel
        case .warn:    return .limitDistribution
        case .block:   return .block
        }
    }
}

// MARK: - Care Resource

struct AegisCareResource: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let actionLabel: String?
    let actionUrl: String?
    let resourceType: AegisCareResourceType

    enum AegisCareResourceType: String, Codable {
        case pastoralGuidance = "pastoral"
        case crisisLine       = "crisis"
        case legalInfo        = "legal"
        case externalLink     = "link"
        case inAppAction      = "action"
    }
}

// MARK: - Evidence

struct AegisEvidence: Codable {
    let type: AegisEvidenceType
    let description: String
    let confidence: Double
    let spanStart: Int?
    let spanEnd: Int?

    enum AegisEvidenceType: String, Codable {
        case boundingBox  = "bounding_box"
        case textSpan     = "text_span"
        case metadata     = "metadata"
        case pattern      = "pattern"
        case voiceprint   = "voiceprint"
        case hash         = "hash"
    }
}

// MARK: - Detection Result (frozen contract)

struct AegisDetectionResult: Codable, Identifiable {
    let resultId: String
    let capabilityId: AegisCapability
    let severity: AegisSeverity
    let confidence: Double          // calibrated 0.0–1.0
    let evidence: [AegisEvidence]
    let regions: [[String: Double]] // bounding boxes {x,y,w,h} normalized
    let suggestedAction: String
    let careResources: [AegisCareResource]
    let timestamp: Date
    let policyVersion: String

    var id: String { resultId }

    static func make(
        capability: AegisCapability,
        severity: AegisSeverity,
        confidence: Double,
        action: String,
        evidence: [AegisEvidence] = [],
        regions: [[String: Double]] = [],
        care: [AegisCareResource] = []
    ) -> AegisDetectionResult {
        AegisDetectionResult(
            resultId: UUID().uuidString,
            capabilityId: capability,
            severity: severity,
            confidence: confidence,
            evidence: evidence,
            regions: regions,
            suggestedAction: action,
            careResources: care,
            timestamp: Date(),
            policyVersion: AegisContractsVersion
        )
    }
}

// MARK: - Safety Decision (orchestrator output)

struct AegisSafetyDecision: Codable {
    let decisionId: String
    let allowPost: Bool
    let requiredAcknowledgements: [AegisCapability]
    let audienceRestriction: AegisAudienceRestriction?
    let redactions: [AegisDetectionResult]          // results that must be addressed
    let routeToCare: Bool
    let careResources: [AegisCareResource]
    let detectionResults: [AegisDetectionResult]
    let timestamp: Date
    let policyVersion: String

    enum AegisAudienceRestriction: String, Codable {
        case adultsOnly   = "adults_only"
        case noMinors     = "no_minors"
        case churchOnly   = "church_only"
        case privateOnly  = "private_only"
    }

    // Highest severity among all results
    var maxSeverity: AegisSeverity {
        detectionResults.map(\.severity).max() ?? .info
    }

    // Bridge to existing preflight pipeline
    var asPreflightOutcome: SafetyDecisionOutcome {
        guard allowPost else {
            return redactions.isEmpty ? .block : .quarantine
        }
        return routeToCare ? .allowWithLabel : .allow
    }

    static func allow(results: [AegisDetectionResult] = []) -> AegisSafetyDecision {
        AegisSafetyDecision(
            decisionId: UUID().uuidString,
            allowPost: true,
            requiredAcknowledgements: [],
            audienceRestriction: nil,
            redactions: [],
            routeToCare: false,
            careResources: [],
            detectionResults: results,
            timestamp: Date(),
            policyVersion: AegisContractsVersion
        )
    }

    static func block(results: [AegisDetectionResult], care: [AegisCareResource] = []) -> AegisSafetyDecision {
        AegisSafetyDecision(
            decisionId: UUID().uuidString,
            allowPost: false,
            requiredAcknowledgements: [],
            audienceRestriction: nil,
            redactions: results,
            routeToCare: !care.isEmpty,
            careResources: care,
            detectionResults: results,
            timestamp: Date(),
            policyVersion: AegisContractsVersion
        )
    }
}

// MARK: - Callable Proxy Request / Response Types

// aegisAnalyzeMedia
struct AegisAnalyzeMediaRequest: Codable {
    let mediaUrl: String
    let mediaType: String           // "image" | "video" | "audio"
    let userId: String
    let surface: String             // ContentSurface rawValue
    let capabilities: [String]     // AegisCapability rawValues to check
}

struct AegisAnalyzeMediaResponse: Codable {
    let results: [AegisDetectionResult]
    let decision: AegisSafetyDecision
    let provenanceStatus: String?   // MediaAuthenticityStatus rawValue
    let c2paSignature: String?
}

// aegisReviewText
struct AegisReviewTextRequest: Codable {
    let text: String
    let surface: String
    let userId: String
    let capabilities: [String]
    let context: [String: String]
}

struct AegisReviewTextResponse: Codable {
    let results: [AegisDetectionResult]
    let decision: AegisSafetyDecision
    let pauseReason: String?
    let pastoralReflection: String? // Berean-powered, pastoral tone
}

// aegisAccountTrust
struct AegisAccountTrustRequest: Codable {
    let targetUserId: String
    let requestingUserId: String
    let capabilities: [String]
}

struct AegisAccountTrustResponse: Codable {
    let results: [AegisDetectionResult]
    let trustLevel: String              // IdentityTrustLevel rawValue
    let syntheticDisclosure: String     // AIGeneratedStatus rawValue
    let cryptoVerified: Bool
    let verificationSignature: String?
}

// aegisPrivacyAction
struct AegisPrivacyActionRequest: Codable {
    let userId: String
    let action: AegisPrivacyActionType
    let modeId: String?                 // AegisCapability rawValue for C40–C43
    let targetPaths: [String]          // Firestore/Storage paths for deletion

    enum AegisPrivacyActionType: String, Codable {
        case exportData       = "export"
        case trueDelete       = "delete"
        case applyMode        = "apply_mode"
        case deferLocation    = "defer_location"
        case memorialAccount  = "memorial"
        case transferLegacy   = "transfer_legacy"
    }
}

struct AegisPrivacyActionResponse: Codable {
    let success: Bool
    let exportUrl: String?
    let deletionManifest: AegisDeletionManifest?
    let error: String?
}

// aegisEscalate
struct AegisEscalateRequest: Codable {
    let reporterId: String
    let reportedUserId: String
    let capability: String          // AegisCapability rawValue
    let evidenceUrls: [String]
    let evidenceText: [String]
    let contentId: String?
    let urgency: AegisEscalateUrgency

    enum AegisEscalateUrgency: String, Codable {
        case low, medium, high, critical
    }
}

struct AegisEscalateResponse: Codable {
    let ticketId: String
    let route: String               // GuardianRoute rawValue
    let careResources: [AegisCareResource]
    let estimatedResponseTime: String?
}

// MARK: - Deletion Manifest (C55 — True Right to Be Forgotten)

struct AegisDeletionManifest: Codable {
    let manifestId: String
    let userId: String
    let requestedAt: Date
    let firestorePaths: [String]
    let storagePaths: [String]
    let pineconeNamespaces: [String]    // embeddings namespaces
    let derivedDataPaths: [String]      // search indexes, caches
    let confirmedAt: Date?
    let isComplete: Bool

    // Canonical deletion fan-out paths for any user
    static func canonicalPaths(for userId: String) -> AegisDeletionManifest {
        AegisDeletionManifest(
            manifestId: UUID().uuidString,
            userId: userId,
            requestedAt: Date(),
            firestorePaths: [
                "users/\(userId)",
                "posts/\(userId)",
                "comments/\(userId)",
                "messages/\(userId)",
                "notifications/\(userId)",
                "userFollows/\(userId)",
                "churchNotes/\(userId)",
                "prayerRequests/\(userId)",
                "safetyProfiles/\(userId)",
                "aegisProfiles/\(userId)",
                "bereanSessions/\(userId)",
                "privacyModes/\(userId)",
                "wellbeingState/\(userId)",
                "dataExports/\(userId)",
                "reportHistory/\(userId)",
                "moderationLog/\(userId)",
            ],
            storagePaths: [
                "users/\(userId)/",
                "posts/\(userId)/",
                "profileImages/\(userId)/",
                "churchNotes/\(userId)/",
            ],
            pineconeNamespaces: [
                "user-\(userId)-posts",
                "user-\(userId)-berean",
                "user-\(userId)-church-notes",
                "user-\(userId)-preferences",
            ],
            derivedDataPaths: [
                "algolia:users:\(userId)",
                "algolia:posts:author:\(userId)",
                "cache:feed:\(userId)",
                "cache:recommendations:\(userId)",
            ],
            confirmedAt: nil,
            isComplete: false
        )
    }
}

// MARK: - Privacy Mode Configuration

struct AegisPrivacyModeConfig: Codable, Identifiable {
    let capability: AegisCapability // C40–C43
    var isActive: Bool
    let rules: [AegisPrivacyRule]

    var id: String { capability.rawValue }

    var title: String { capability.displayName }
}

struct AegisPrivacyRule: Codable {
    let ruleId: String
    let description: String
    let enforcement: AegisRuleEnforcement

    enum AegisRuleEnforcement: String, Codable {
        case softPrompt     // advisory only
        case requireConsent // must acknowledge
        case autoApply      // applied silently
        case block          // prevents action
    }
}

// MARK: - Wellbeing State

struct AegisWellbeingState: Codable {
    let userId: String
    var hiddenMetrics: Bool
    var antiRageEnabled: Bool
    var doomscrollGuardEnabled: Bool
    var lateNightFrictionEnabled: Bool  // 1-4am friction
    var memoryControlsEnabled: Bool
    var mutedDates: [String]            // "MM-DD" format
    var mutedUserIds: [String]          // for memory resurfacing
    var sessionStartedAt: Date?
    var scrollDepthToday: Int           // feed items scrolled
}

// MARK: - Coverage Record (for the §7 coverage report)

struct AegisCoverageRecord: Codable {
    let capabilityId: AegisCapability
    let hasContract: Bool
    let backendFunction: String?
    let firestorePath: String?
    let swiftUIView: String?
    let featureFlag: String
    let testName: String?
    var status: AegisCoverageStatus

    enum AegisCoverageStatus: String, Codable {
        case done    = "DONE"
        case partial = "PARTIAL"
        case todo    = "TODO"
    }
}
