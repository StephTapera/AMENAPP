import {
    AdvisoryVerdict,
    SafetyMeshInvariants,
    closedCSAMComplianceGate,
    defaultSafetyMeshFlags,
    isCSAMHashScanAllowed,
    isCapabilityEnabled,
    normalizeAdvisoryVerdict,
    requiresHumanReview,
} from "./moderationMeshContracts";

describe("moderation mesh contracts", () => {
    it("keeps every rollout and provider flag off by default", () => {
        expect(Object.values(defaultSafetyMeshFlags).every((value) => value === false)).toBe(true);
        expect(isCapabilityEnabled("contentSafety", defaultSafetyMeshFlags)).toBe(false);
        expect(isCapabilityEnabled("imageSafety", defaultSafetyMeshFlags)).toBe(false);
        expect(isCapabilityEnabled("liveVoice", defaultSafetyMeshFlags)).toBe(false);
        expect(isCapabilityEnabled("liveVideo", defaultSafetyMeshFlags)).toBe(false);
    });

    it("requires all four CSAM compliance gates before hash scanning can route", () => {
        expect(isCSAMHashScanAllowed(defaultSafetyMeshFlags, closedCSAMComplianceGate)).toBe(false);
        expect(isCSAMHashScanAllowed({ ...defaultSafetyMeshFlags, csam_hash_scan_enabled: true }, {
            espNcmecRegistrationComplete: true,
            hashProviderContractSigned: true,
            writtenLegalSignoffComplete: true,
            nonEngineerReviewComplete: false,
        })).toBe(false);
        expect(isCSAMHashScanAllowed({ ...defaultSafetyMeshFlags, csam_hash_scan_enabled: true }, {
            espNcmecRegistrationComplete: true,
            hashProviderContractSigned: true,
            writtenLegalSignoffComplete: true,
            nonEngineerReviewComplete: true,
        })).toBe(true);
    });

    it("keeps advisory agents non-punitive except managed known-CSAM hard-block", () => {
        const advisory: AdvisoryVerdict = {
            verdictId: "verdict_1",
            capability: "contentSafety",
            backend: "managed",
            signal: "harassment",
            level: "critical",
            confidence: 1.4,
            recommendedAction: "holdForHumanReview",
            evidenceRefs: [],
            requiresHumanReview: false,
            autonomousActionPermitted: true,
            createdAt: new Date().toISOString(),
        };

        const normalized = normalizeAdvisoryVerdict(advisory);
        expect(normalized.confidence).toBe(1);
        expect(normalized.requiresHumanReview).toBe(true);
        expect(normalized.autonomousActionPermitted).toBe(false);
        expect(requiresHumanReview(advisory)).toBe(true);
    });

    it("codifies post-launch infrastructure and public-score constraints", () => {
        expect(SafetyMeshInvariants.nvidiaIsOptionalPostLaunch).toBe(true);
        expect(SafetyMeshInvariants.liveVoiceVideoContractsOnly).toBe(true);
        expect(SafetyMeshInvariants.deepfakeUsesC2PAProvenanceOnly).toBe(true);
        expect(SafetyMeshInvariants.publicTrustScoresAllowed).toBe(false);
        expect(SafetyMeshInvariants.countryBasedRiskScoringAllowed).toBe(false);
    });
});
