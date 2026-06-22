import {
    MediaGateInvariants,
    auditRecordContainsRawData,
    decisionAfterRequiredStageFailure,
    shouldRouteToCSAMProvider,
    SafetyAuditRecord,
} from "./mediaGateContracts";

describe("media gate contracts", () => {
    it("I1 fails closed when a required stage fails", () => {
        expect(decisionAfterRequiredStageFailure()).not.toBe("publish");
        expect(["review", "block"]).toContain(decisionAfterRequiredStageFailure());
    });

    it("I2 stores decisions only in audit records", () => {
        const record: SafetyAuditRecord = {
            auditId: "audit_1",
            postId: "post_1",
            createdAt: new Date().toISOString(),
            providerVersion: "managed-provider-unconfigured",
            modelVersion: "policy-v0",
            findingCategories: ["faceCandidate", "plateCandidate"],
            actionsTaken: ["blurRegion", "stripEXIF", "removeLocation"],
            policyDecision: "review",
            appealStatus: "none",
            retentionExpiresAt: new Date(Date.now() + 86400000).toISOString(),
        };

        expect(auditRecordContainsRawData(record)).toBe(false);
    });

    it("I3 keeps CSAM hash scan provider-gated and off by default", () => {
        expect(MediaGateInvariants.csamProviderGated).toBe(true);
        expect(MediaGateInvariants.csamHashScanDefaultEnabled).toBe(false);
        expect(shouldRouteToCSAMProvider(false)).toBe(false);
    });
});
