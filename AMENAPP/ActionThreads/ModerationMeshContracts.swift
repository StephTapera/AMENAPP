import Foundation

// Swift mirror of Backend/functions/src/moderationMeshContracts.ts.
// Keep this file contract-only: providers and routing are implemented in later waves.

enum SafetyCapabilityKind: String, Codable, CaseIterable {
    case contentSafety
    case childSafety
    case scamFraud
    case accountIntegrity
    case harassmentBrigading
    case linkSafety
    case creatorProtection
    case communityHealth
    case crisis
    case imageSafety
    case liveVoice
    case liveVideo
    case deepfakeProvenance
}

enum SafetyBackendKind: String, Codable, CaseIterable {
    case managed
    case nvidia
    case appleOnDevice
    case stub
}

enum SafetySignalLevel: String, Codable, CaseIterable, Comparable {
    case none
    case low
    case medium
    case high
    case critical

    private var rank: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .critical: return 4
        }
    }

    static func < (lhs: SafetySignalLevel, rhs: SafetySignalLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

enum AdvisoryAction: String, Codable, CaseIterable {
    case allow
    case nudge
    case holdForHumanReview
    case routeToCrisisWorkflow
    case restrictDistribution
    case knownCSAMProviderHardBlock
}

struct SafetyMeshFlags: Codable, Equatable {
    let moderationMeshEnabled: Bool
    let managedSafetyBackendsEnabled: Bool
    let nvidiaSafetyBackendsEnabled: Bool
    let textSafetyAgentsEnabled: Bool
    let imageSafetyPipelineEnabled: Bool
    let trustGraphInternalScoresEnabled: Bool
    let creatorProtectionAgentEnabled: Bool
    let communityHealthAgentEnabled: Bool
    let crisisAgentEnabled: Bool
    let liveVoiceModerationEnabled: Bool
    let liveVideoModerationEnabled: Bool
    let c2paProvenanceEnabled: Bool
    let csamHashScanEnabled: Bool

    static let disabled = SafetyMeshFlags(
        moderationMeshEnabled: false,
        managedSafetyBackendsEnabled: false,
        nvidiaSafetyBackendsEnabled: false,
        textSafetyAgentsEnabled: false,
        imageSafetyPipelineEnabled: false,
        trustGraphInternalScoresEnabled: false,
        creatorProtectionAgentEnabled: false,
        communityHealthAgentEnabled: false,
        crisisAgentEnabled: false,
        liveVoiceModerationEnabled: false,
        liveVideoModerationEnabled: false,
        c2paProvenanceEnabled: false,
        csamHashScanEnabled: false
    )
}

struct CSAMComplianceGate: Codable, Equatable {
    let espNcmecRegistrationComplete: Bool
    let hashProviderContractSigned: Bool
    let writtenLegalSignoffComplete: Bool
    let nonEngineerReviewComplete: Bool

    static let closed = CSAMComplianceGate(
        espNcmecRegistrationComplete: false,
        hashProviderContractSigned: false,
        writtenLegalSignoffComplete: false,
        nonEngineerReviewComplete: false
    )

    var isCleared: Bool {
        espNcmecRegistrationComplete
            && hashProviderContractSigned
            && writtenLegalSignoffComplete
            && nonEngineerReviewComplete
    }
}

struct SafetyCapabilityPayload: Codable, Equatable {
    enum ContentType: String, Codable, CaseIterable {
        case text
        case image
        case link
        case account
        case behavior
        case provenance
        case audio
        case video
    }

    let contentId: String?
    let contentType: ContentType
    let storageRef: String?
    let url: URL?
    let text: String?
    let metadata: [String: String]
}

struct EvidenceRef: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case policy
        case modelSignal
        case behavioralSignal
        case providerDecision
        case userReport
        case provenance
    }

    let id: String
    let kind: Kind
    let summary: String

    init(id: String = UUID().uuidString, kind: Kind, summary: String) {
        self.id = id
        self.kind = kind
        self.summary = summary
    }
}

struct AdvisoryVerdict: Codable, Identifiable, Equatable {
    let id: String
    let capability: SafetyCapabilityKind
    let backend: SafetyBackendKind
    let signal: String
    let level: SafetySignalLevel
    let confidence: Double
    let recommendedAction: AdvisoryAction
    let evidenceRefs: [EvidenceRef]
    let requiresHumanReview: Bool
    let autonomousActionPermitted: Bool
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        capability: SafetyCapabilityKind,
        backend: SafetyBackendKind,
        signal: String,
        level: SafetySignalLevel,
        confidence: Double,
        recommendedAction: AdvisoryAction,
        evidenceRefs: [EvidenceRef],
        requiresHumanReview: Bool,
        autonomousActionPermitted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.capability = capability
        self.backend = backend
        self.signal = signal
        self.level = level
        self.confidence = min(max(confidence, 0), 1)
        self.recommendedAction = recommendedAction
        self.evidenceRefs = evidenceRefs
        self.requiresHumanReview = requiresHumanReview || level >= .high
        self.autonomousActionPermitted = recommendedAction == .knownCSAMProviderHardBlock && autonomousActionPermitted
        self.createdAt = createdAt
    }
}

struct SafetyCapabilityProviderDescriptor: Codable, Equatable {
    let capability: SafetyCapabilityKind
    let backend: SafetyBackendKind
    let providerVersion: String
    let enabled: Bool
}

protocol SafetyCapabilityProvider {
    var descriptor: SafetyCapabilityProviderDescriptor { get }

    func evaluate(
        context: SocialContext,
        payload: SafetyCapabilityPayload
    ) async throws -> AdvisoryVerdict
}

struct GuardianSignalRecord: Codable, Identifiable, Equatable {
    let id: String
    let socialContextId: String
    let actorUid: String?
    let targetUid: String?
    let surfaceKind: String
    let capability: SafetyCapabilityKind
    let verdict: AdvisoryVerdict
    let createdAt: Date
    let expiresAt: Date?
}

struct HumanReviewQueueItem: Codable, Identifiable, Equatable {
    enum Status: String, Codable, CaseIterable {
        case pending
        case assigned
        case resolved
        case dismissed
    }

    let id: String
    let signalId: String
    let socialContextId: String
    let priority: SafetySignalLevel
    let status: Status
    let capability: SafetyCapabilityKind
    let recommendedAction: AdvisoryAction
    let evidenceRefs: [EvidenceRef]
    let createdAt: Date
    let assignedToUid: String?
}

enum SafetyMeshInvariants {
    static let advisoryOnlyAgents = true
    static let nvidiaIsOptionalPostLaunch = true
    static let liveVoiceVideoContractsOnly = true
    static let deepfakeUsesC2PAProvenanceOnly = true
    static let publicTrustScoresAllowed = false
    static let countryBasedRiskScoringAllowed = false
    static let e2eeDeferredForServerSideScanning = true

    static func isCSAMHashScanAllowed(flags: SafetyMeshFlags, gate: CSAMComplianceGate) -> Bool {
        flags.csamHashScanEnabled && gate.isCleared
    }

    static func isCapabilityEnabled(_ kind: SafetyCapabilityKind, flags: SafetyMeshFlags) -> Bool {
        guard flags.moderationMeshEnabled else { return false }

        switch kind {
        case .contentSafety, .childSafety, .scamFraud, .accountIntegrity, .harassmentBrigading, .linkSafety:
            return flags.textSafetyAgentsEnabled && flags.managedSafetyBackendsEnabled
        case .creatorProtection:
            return flags.creatorProtectionAgentEnabled && flags.managedSafetyBackendsEnabled
        case .communityHealth:
            return flags.communityHealthAgentEnabled
        case .crisis:
            return flags.crisisAgentEnabled && flags.managedSafetyBackendsEnabled
        case .imageSafety:
            return flags.imageSafetyPipelineEnabled && flags.managedSafetyBackendsEnabled
        case .deepfakeProvenance:
            return flags.c2paProvenanceEnabled
        case .liveVoice, .liveVideo:
            return false
        }
    }
}
