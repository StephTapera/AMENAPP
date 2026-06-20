export type SafetyCapabilityKind =
    | "contentSafety"
    | "childSafety"
    | "scamFraud"
    | "accountIntegrity"
    | "harassmentBrigading"
    | "linkSafety"
    | "creatorProtection"
    | "communityHealth"
    | "crisis"
    | "imageSafety"
    | "liveVoice"
    | "liveVideo"
    | "deepfakeProvenance";

export type SafetyBackendKind = "managed" | "nvidia" | "appleOnDevice" | "stub";

export type SafetySignalLevel = "none" | "low" | "medium" | "high" | "critical";

export type AdvisoryAction =
    | "allow"
    | "nudge"
    | "holdForHumanReview"
    | "routeToCrisisWorkflow"
    | "restrictDistribution"
    | "knownCSAMProviderHardBlock";

export interface SafetyMeshFlags {
    moderation_mesh_enabled: boolean;
    managed_safety_backends_enabled: boolean;
    nvidia_safety_backends_enabled: boolean;
    text_safety_agents_enabled: boolean;
    image_safety_pipeline_enabled: boolean;
    trust_graph_internal_scores_enabled: boolean;
    creator_protection_agent_enabled: boolean;
    community_health_agent_enabled: boolean;
    crisis_agent_enabled: boolean;
    live_voice_moderation_enabled: boolean;
    live_video_moderation_enabled: boolean;
    c2pa_provenance_enabled: boolean;
    csam_hash_scan_enabled: boolean;
}

export const defaultSafetyMeshFlags: SafetyMeshFlags = Object.freeze({
    moderation_mesh_enabled: false,
    managed_safety_backends_enabled: false,
    nvidia_safety_backends_enabled: false,
    text_safety_agents_enabled: false,
    image_safety_pipeline_enabled: false,
    trust_graph_internal_scores_enabled: false,
    creator_protection_agent_enabled: false,
    community_health_agent_enabled: false,
    crisis_agent_enabled: false,
    live_voice_moderation_enabled: false,
    live_video_moderation_enabled: false,
    c2pa_provenance_enabled: false,
    csam_hash_scan_enabled: false,
});

export interface CSAMComplianceGate {
    espNcmecRegistrationComplete: boolean;
    hashProviderContractSigned: boolean;
    writtenLegalSignoffComplete: boolean;
    nonEngineerReviewComplete: boolean;
}

export const closedCSAMComplianceGate: CSAMComplianceGate = Object.freeze({
    espNcmecRegistrationComplete: false,
    hashProviderContractSigned: false,
    writtenLegalSignoffComplete: false,
    nonEngineerReviewComplete: false,
});

export interface SafetyCapabilityPayload {
    contentId?: string;
    contentType: "text" | "image" | "link" | "account" | "behavior" | "provenance" | "audio" | "video";
    storageRef?: string;
    url?: string;
    text?: string;
    metadata?: Record<string, unknown>;
}

export interface EvidenceRef {
    refId: string;
    kind: "policy" | "modelSignal" | "behavioralSignal" | "providerDecision" | "userReport" | "provenance";
    summary: string;
}

export interface AdvisoryVerdict {
    verdictId: string;
    capability: SafetyCapabilityKind;
    backend: SafetyBackendKind;
    signal: string;
    level: SafetySignalLevel;
    confidence: number;
    recommendedAction: AdvisoryAction;
    evidenceRefs: EvidenceRef[];
    requiresHumanReview: boolean;
    autonomousActionPermitted: boolean;
    createdAt: string;
}

export interface SafetyCapabilityProvider {
    capability: SafetyCapabilityKind;
    backend: SafetyBackendKind;
    providerVersion: string;
    enabled: boolean;
}

export interface GuardianSignalRecord {
    signalId: string;
    socialContextId: string;
    actorUid?: string;
    targetUid?: string;
    surfaceKind: string;
    capability: SafetyCapabilityKind;
    verdict: AdvisoryVerdict;
    createdAt: string;
    expiresAt?: string;
}

export interface HumanReviewQueueItem {
    itemId: string;
    signalId: string;
    socialContextId: string;
    priority: SafetySignalLevel;
    status: "pending" | "assigned" | "resolved" | "dismissed";
    capability: SafetyCapabilityKind;
    recommendedAction: AdvisoryAction;
    evidenceRefs: EvidenceRef[];
    createdAt: string;
    assignedToUid?: string;
}

export const SafetyMeshInvariants = Object.freeze({
    advisoryOnlyAgents: true,
    nvidiaIsOptionalPostLaunch: true,
    liveVoiceVideoContractsOnly: true,
    deepfakeUsesC2PAProvenanceOnly: true,
    publicTrustScoresAllowed: false,
    countryBasedRiskScoringAllowed: false,
    e2eeDeferredForServerSideScanning: true,
});

export function isCSAMHashScanAllowed(flags: SafetyMeshFlags, gate: CSAMComplianceGate): boolean {
    return flags.csam_hash_scan_enabled === true
        && gate.espNcmecRegistrationComplete === true
        && gate.hashProviderContractSigned === true
        && gate.writtenLegalSignoffComplete === true
        && gate.nonEngineerReviewComplete === true;
}

export function isCapabilityEnabled(kind: SafetyCapabilityKind, flags: SafetyMeshFlags): boolean {
    if (!flags.moderation_mesh_enabled) {
        return false;
    }
    switch (kind) {
    case "contentSafety":
    case "childSafety":
    case "scamFraud":
    case "accountIntegrity":
    case "harassmentBrigading":
    case "linkSafety":
        return flags.text_safety_agents_enabled && flags.managed_safety_backends_enabled;
    case "creatorProtection":
        return flags.creator_protection_agent_enabled && flags.managed_safety_backends_enabled;
    case "communityHealth":
        return flags.community_health_agent_enabled;
    case "crisis":
        return flags.crisis_agent_enabled && flags.managed_safety_backends_enabled;
    case "imageSafety":
        return flags.image_safety_pipeline_enabled && flags.managed_safety_backends_enabled;
    case "deepfakeProvenance":
        return flags.c2pa_provenance_enabled;
    case "liveVoice":
        return false;
    case "liveVideo":
        return false;
    }
}

export function normalizeAdvisoryVerdict(verdict: AdvisoryVerdict): AdvisoryVerdict {
    const autonomousActionPermitted = verdict.recommendedAction === "knownCSAMProviderHardBlock";
    return {
        ...verdict,
        confidence: Math.max(0, Math.min(1, verdict.confidence)),
        requiresHumanReview: verdict.requiresHumanReview || verdict.level === "high" || verdict.level === "critical",
        autonomousActionPermitted,
    };
}

export function requiresHumanReview(verdict: AdvisoryVerdict): boolean {
    return normalizeAdvisoryVerdict(verdict).requiresHumanReview;
}
