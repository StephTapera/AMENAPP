import Foundation

// Wave 1 Lane E: contract-only escalation wiring.
// No scanning, restriction writes, CyberTipline submission, queue writes, or deploy behavior live here.

enum TrustCenterEscalationSignal: String, Codable, CaseIterable, Sendable {
    case csam = "csam"
    case grooming = "grooming"
    case sexualSolicitationMinor = "sexual_solicitation_minor"
    case childExploitation = "child_exploitation"
    case safetyProviderUnavailable = "safety_provider_unavailable"
}

enum TrustCenterEscalationDetectionSource: String, Codable, CaseIterable, Sendable {
    case iosContentSafety = "ios_content_safety"
    case childSafetyService = "child_safety_service"
    case mediaSafetyGateway = "media_safety_gateway"
    case messageSafetyGateway = "message_safety_gateway"
    case cloudFunction = "cloud_function"
    case unknown = "unknown"
}

enum TrustCenterEscalationRestrictionAction: String, Codable, CaseIterable, Sendable {
    case blockSubmission = "block_submission"
    case softHideContent = "soft_hide_content"
    case holdForHumanReview = "hold_for_human_review"
    case freezeAccountPendingReview = "freeze_account_pending_review"
    case noClientRestriction = "no_client_restriction"
}

enum TrustCenterCyberTiplineStatus: String, Codable, CaseIterable, Sendable {
    case notApplicable = "not_applicable"
    case pendingHumanAuthorization = "pending_human_authorization"
    case pendingBackendVerification = "pending_backend_verification"
    case blockedMissingVerifiedPipeline = "blocked_missing_verified_pipeline"
}

enum TrustCenterEscalationReviewQueuePath: String, Codable, CaseIterable, Sendable {
    case moderationQueue = "/moderationQueue"
    case criticalReviewQueue = "/criticalReviewQueue"
    case unresolvedAmbiguous = "unresolved_ambiguous"
}

enum TrustCenterEscalationReviewStatus: String, Codable, CaseIterable, Sendable {
    case pending = "pending"
    case pendingReview = "pending_review"
    case pendingNCMEC = "pending_ncmec"
    case escalated = "escalated"
    case appealed = "appealed"
    case resolved = "resolved"
    case queuePathUnresolved = "queue_path_unresolved"
}

enum TrustCenterEscalationLaunchBlocker: String, Codable, CaseIterable, Sendable {
    case featureFlagDisabled = "ff.safety.escalationV2_disabled"
    case cyberTiplineImplementationUnverified = "cybertipline_implementation_unverified"
    case photoDNAOrHashProviderMissing = "photodna_or_hash_provider_missing"
    case humanLegalGateMissing = "human_legal_gate_missing"
    case queuePathAmbiguous = "queue_path_ambiguous"
    case backendTriggerUnverified = "backend_trigger_unverified"
    case scanningNotInjectedInAllUploadPaths = "scanning_not_injected_in_all_upload_paths"
    case appealMetadataRequired = "appeal_metadata_required"
}

struct TrustCenterEscalationContentRef: Codable, Equatable, Sendable {
    let path: String
    let contentType: String
    let authorId: String

    init(path: String, contentType: String, authorId: String) {
        self.path = path
        self.contentType = contentType
        self.authorId = authorId
    }
}

struct TrustCenterEscalationDetectionPayload: Codable, Equatable, Sendable {
    let content: TrustCenterEscalationContentRef
    let signals: [TrustCenterEscalationSignal]
    let detectionSource: TrustCenterEscalationDetectionSource
    let decisionId: String?
    let detectedAt: Date

    init(
        content: TrustCenterEscalationContentRef,
        signals: [TrustCenterEscalationSignal],
        detectionSource: TrustCenterEscalationDetectionSource,
        decisionId: String? = nil,
        detectedAt: Date = Date()
    ) {
        self.content = content
        self.signals = signals
        self.detectionSource = detectionSource
        self.decisionId = decisionId
        self.detectedAt = detectedAt
    }
}

struct TrustCenterEscalationRestrictionPayload: Codable, Equatable, Sendable {
    let actions: [TrustCenterEscalationRestrictionAction]
    let reasonCode: String
    let restrictedAt: Date
    let requiresManualReview: Bool

    init(
        actions: [TrustCenterEscalationRestrictionAction],
        reasonCode: String,
        restrictedAt: Date = Date(),
        requiresManualReview: Bool = true
    ) {
        self.actions = actions
        self.reasonCode = reasonCode
        self.restrictedAt = restrictedAt
        self.requiresManualReview = requiresManualReview
    }
}

struct TrustCenterEscalationAppealMetadata: Codable, Equatable, Sendable {
    let isAppealable: Bool
    let appealQueuePath: String?
    let appealDeadline: Date?
    let nonAppealableReason: String?

    static let nonAppealableChildSafetyEscalation = TrustCenterEscalationAppealMetadata(
        isAppealable: false,
        appealQueuePath: nil,
        appealDeadline: nil,
        nonAppealableReason: "CSAM and immediate child-safety escalations require human safety review before any author appeal path."
    )

    init(
        isAppealable: Bool,
        appealQueuePath: String?,
        appealDeadline: Date?,
        nonAppealableReason: String?
    ) {
        self.isAppealable = isAppealable
        self.appealQueuePath = appealQueuePath
        self.appealDeadline = appealDeadline
        self.nonAppealableReason = nonAppealableReason
    }
}

struct TrustCenterEscalationReviewQueuePayload: Codable, Equatable, Sendable {
    let path: TrustCenterEscalationReviewQueuePath
    let status: TrustCenterEscalationReviewStatus
    let escalateImmediately: Bool
    let isCanonicalPathVerified: Bool
    let knownExistingPaths: [TrustCenterEscalationReviewQueuePath]

    static let unresolvedCSAMQueue = TrustCenterEscalationReviewQueuePayload(
        path: .unresolvedAmbiguous,
        status: .queuePathUnresolved,
        escalateImmediately: true,
        isCanonicalPathVerified: false,
        knownExistingPaths: [.moderationQueue, .criticalReviewQueue]
    )

    init(
        path: TrustCenterEscalationReviewQueuePath,
        status: TrustCenterEscalationReviewStatus,
        escalateImmediately: Bool,
        isCanonicalPathVerified: Bool,
        knownExistingPaths: [TrustCenterEscalationReviewQueuePath]
    ) {
        self.path = path
        self.status = status
        self.escalateImmediately = escalateImmediately
        self.isCanonicalPathVerified = isCanonicalPathVerified
        self.knownExistingPaths = knownExistingPaths
    }
}

struct TrustCenterEscalationPlan: Codable, Equatable, Sendable {
    let isEnabled: Bool
    let detection: TrustCenterEscalationDetectionPayload
    let restriction: TrustCenterEscalationRestrictionPayload
    let cyberTiplineStatus: TrustCenterCyberTiplineStatus
    let reviewQueue: TrustCenterEscalationReviewQueuePayload
    let appeal: TrustCenterEscalationAppealMetadata
    let launchBlockers: [TrustCenterEscalationLaunchBlocker]
}

protocol TrustCenterEscalationContractAdapting: Sendable {
    func escalationPlan(
        for detection: TrustCenterEscalationDetectionPayload,
        featureGate: TrustCenterFeatureGate
    ) -> TrustCenterEscalationPlan
}

struct TrustCenterEscalationContractAdapter: TrustCenterEscalationContractAdapting {
    func escalationPlan(
        for detection: TrustCenterEscalationDetectionPayload,
        featureGate: TrustCenterFeatureGate = .disabled
    ) -> TrustCenterEscalationPlan {
        let containsCSAM = detection.signals.contains(.csam) || detection.signals.contains(.childExploitation)
        let restriction = restrictionPayload(for: detection, containsCSAM: containsCSAM)
        let isEnabled = featureGate.isEnabled(.escalationV2)
        var blockers = Self.launchBlockers

        if !isEnabled {
            blockers.insert(.featureFlagDisabled, at: 0)
        }

        return TrustCenterEscalationPlan(
            isEnabled: isEnabled,
            detection: detection,
            restriction: restriction,
            cyberTiplineStatus: containsCSAM ? .blockedMissingVerifiedPipeline : .notApplicable,
            reviewQueue: containsCSAM ? .unresolvedCSAMQueue : nonCSAMQueuePayload(),
            appeal: containsCSAM ? .nonAppealableChildSafetyEscalation : ordinaryAppealMetadata(),
            launchBlockers: blockers
        )
    }

    static let launchBlockers: [TrustCenterEscalationLaunchBlocker] = [
        .cyberTiplineImplementationUnverified,
        .photoDNAOrHashProviderMissing,
        .humanLegalGateMissing,
        .queuePathAmbiguous,
        .backendTriggerUnverified,
        .scanningNotInjectedInAllUploadPaths,
        .appealMetadataRequired
    ]

    private func restrictionPayload(
        for detection: TrustCenterEscalationDetectionPayload,
        containsCSAM: Bool
    ) -> TrustCenterEscalationRestrictionPayload {
        if containsCSAM {
            return TrustCenterEscalationRestrictionPayload(
                actions: [.blockSubmission, .softHideContent, .holdForHumanReview],
                reasonCode: TrustCenterEscalationSignal.csam.rawValue
            )
        }

        if detection.signals.contains(.grooming) || detection.signals.contains(.sexualSolicitationMinor) {
            return TrustCenterEscalationRestrictionPayload(
                actions: [.softHideContent, .holdForHumanReview],
                reasonCode: detection.signals.first?.rawValue ?? TrustCenterEscalationSignal.childExploitation.rawValue
            )
        }

        return TrustCenterEscalationRestrictionPayload(
            actions: [.holdForHumanReview],
            reasonCode: detection.signals.first?.rawValue ?? TrustCenterEscalationSignal.safetyProviderUnavailable.rawValue
        )
    }

    private func nonCSAMQueuePayload() -> TrustCenterEscalationReviewQueuePayload {
        TrustCenterEscalationReviewQueuePayload(
            path: .moderationQueue,
            status: .pending,
            escalateImmediately: false,
            isCanonicalPathVerified: true,
            knownExistingPaths: [.moderationQueue]
        )
    }

    private func ordinaryAppealMetadata() -> TrustCenterEscalationAppealMetadata {
        TrustCenterEscalationAppealMetadata(
            isAppealable: true,
            appealQueuePath: "/moderationAppeals",
            appealDeadline: nil,
            nonAppealableReason: nil
        )
    }
}
