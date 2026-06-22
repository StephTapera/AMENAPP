// MediaGatePipeline: ordered, fail-closed media publishing stages from capture through final disposition.
export const mediaGatePipeline = [
    "Capture",
    "OnDevicePrecheck",
    "Quarantine",
    "ServerScan",
    "PolicyDecision",
    "Publish",
    "Blur",
    "Limit",
    "Block",
    "Review",
] as const;

export type MediaGatePipelineStage = typeof mediaGatePipeline[number];

// PolicyDecision: server-authoritative result; any uncertainty defaults to review/block, never publish.
export type PolicyDecision = "publish" | "blur" | "limit" | "block" | "review";
export const failClosedPolicyDecision: PolicyDecision = "review";

export type SafetyFindingCategory =
    | "faceCandidate"
    | "textCandidate"
    | "plateCandidate"
    | "exifLocation"
    | "audioPII";

export interface SafetyRegion {
    x: number;
    y: number;
    width: number;
    height: number;
}

export interface SafetyTimeSpan {
    startSeconds: number;
    endSeconds: number;
}

// RedactionAction: transformations suggested on-device and re-applied server-side.
export type RedactionAction =
    | { type: "blurRegion"; region: SafetyRegion }
    | { type: "muteSpan"; timeSpan: SafetyTimeSpan }
    | { type: "stripEXIF" }
    | { type: "removeLocation" }
    | { type: "aiLabel"; label: string }
    | { type: "restrictAudience"; audience: string };

// SafetyFinding: typed candidate signal only; never embeds raw media or raw private text.
export interface SafetyFinding {
    category: SafetyFindingCategory;
    confidence: number;
    region?: SafetyRegion;
    timeSpan?: SafetyTimeSpan;
    suggestedAction: RedactionAction;
}

// SafetyAuditRecord: retention-bounded decisions only; raw media/private text is never stored here.
export interface SafetyAuditRecord {
    auditId: string;
    postId?: string;
    createdAt: string;
    providerVersion: string;
    modelVersion: string;
    findingCategories: SafetyFindingCategory[];
    actionsTaken: string[];
    policyDecision: PolicyDecision;
    appealStatus: "none" | "open" | "resolved";
    reviewerDecision?: string;
    retentionExpiresAt: string;
    openAppealMediaReference?: string;
}

// MediaGateInvariants: executable policy constants for fail-closed, disabled CSAM, and stricter known-minor defaults.
export const MediaGateInvariants = Object.freeze({
    failClosed: true,
    csamProviderGated: true,
    csamHashScanDefaultEnabled: false,
    knownMinorPublicLocationAllowed: false,
    knownMinorDefaultActions: [
        { type: "removeLocation" },
        { type: "stripEXIF" },
        { type: "restrictAudience", audience: "followers" },
    ] satisfies RedactionAction[],
});

export function decisionAfterRequiredStageFailure(): PolicyDecision {
    return failClosedPolicyDecision;
}

export function shouldRouteToCSAMProvider(csamHashScanEnabled: boolean): boolean {
    return MediaGateInvariants.csamProviderGated && csamHashScanEnabled;
}

export function auditRecordContainsRawData(record: SafetyAuditRecord): boolean {
    const text = [
        ...record.actionsTaken,
        record.reviewerDecision ?? "",
        record.openAppealMediaReference ?? "",
    ].join(" ").toLowerCase();
    return text.includes("data:image")
        || text.includes("base64")
        || text.includes("rawtext")
        || text.includes("transcript:")
        || text.includes("exif:");
}
