import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {
    SafetyAuditRecord,
    SafetyFinding,
    RedactionAction,
    PolicyDecision,
    failClosedPolicyDecision,
    decisionAfterRequiredStageFailure,
    shouldRouteToCSAMProvider,
    auditRecordContainsRawData,
} from "./mediaGateContracts";

const REGION = "us-east1";
interface MediaGateFlags {
    berean_camera_enabled: boolean;
    media_gate_enabled: boolean;
    media_gate_ondevice_precheck: boolean;
    media_gate_server_scan: boolean;
    csam_hash_scan_enabled: boolean;
}

const MEDIA_GATE_FLAGS: MediaGateFlags = Object.freeze({
    berean_camera_enabled: false,
    media_gate_enabled: false,
    media_gate_ondevice_precheck: false,
    media_gate_server_scan: false,
    csam_hash_scan_enabled: false,
});

interface MediaGateRequest {
    postId?: string;
    uploadPath?: string;
    clientFindings?: SafetyFinding[];
    requestedActions?: RedactionAction[];
    knownMinorAuthor?: boolean;
}

interface ManagedProviderResult {
    providerVersion: string;
    decision: PolicyDecision;
    findings: SafetyFinding[];
}

export const evaluateMediaGatePolicy = onCall({ enforceAppCheck: true, region: REGION, timeoutSeconds: 30 }, async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Auth required");
    }
    if (request.app == undefined) {
        throw new HttpsError("failed-precondition", "App Check required");
    }

    const flags = await loadMediaGateFlags();
    if (!flags.media_gate_enabled) {
        return { ok: true, decision: "review" satisfies PolicyDecision, flagsEnabled: false };
    }

    const data = request.data as MediaGateRequest;
    const postId = data?.postId;
    const uploadPath = String(data?.uploadPath ?? "");
    if (!uploadPath) {
        return writeFailClosedAudit({
            uid: request.auth.uid,
            postId,
            reason: "missing-upload-path",
            clientFindings: data?.clientFindings ?? [],
        });
    }

    await quarantineUpload(uploadPath, request.auth.uid, postId);

    if (shouldRouteToCSAMProvider(flags.csam_hash_scan_enabled)) {
        // CSAM hash scanning is provider-gated and disabled by default. Do not enable
        // without ESP/NCMEC registration, a signed hash-provider contract, written
        // legal sign-off, and non-engineer review. Never handle raw CSAM here.
        await callGatedCSAMProviderInterfaceOnly(uploadPath);
    }

    const providerResult = flags.media_gate_server_scan
        ? await callManagedContentSafetyProvider(uploadPath)
        : {
            providerVersion: "managed-provider-disabled",
            decision: failClosedPolicyDecision,
            findings: [],
        } satisfies ManagedProviderResult;

    const serverVerifiedActions = await applyServerSideRedactions(
        uploadPath,
        data?.requestedActions ?? []
    );

    const decision = mergePolicyDecision(providerResult.decision, data?.knownMinorAuthor === true);
    const audit = buildAuditRecord({
        postId,
        providerVersion: providerResult.providerVersion,
        findingCategories: [
            ...(data?.clientFindings ?? []),
            ...providerResult.findings,
        ].map((finding) => finding.category),
        actionsTaken: serverVerifiedActions,
        decision,
    });

    if (auditRecordContainsRawData(audit)) {
        return writeFailClosedAudit({
            uid: request.auth.uid,
            postId,
            reason: "raw-data-audit-rejected",
            clientFindings: data?.clientFindings ?? [],
        });
    }

    await admin.firestore()
        .collection("safetyAuditRecords")
        .doc(audit.auditId)
        .set(audit);

    return { ok: true, decision, auditId: audit.auditId };
});

async function loadMediaGateFlags(): Promise<typeof MEDIA_GATE_FLAGS> {
    const snapshot = await admin.firestore().collection("system").doc("featureFlags").get();
    const remote = snapshot.data() ?? {};
    return {
        berean_camera_enabled: remote.berean_camera_enabled === true,
        media_gate_enabled: remote.media_gate_enabled === true,
        media_gate_ondevice_precheck: remote.media_gate_ondevice_precheck === true,
        media_gate_server_scan: remote.media_gate_server_scan === true,
        csam_hash_scan_enabled: false,
    };
}

async function quarantineUpload(uploadPath: string, uid: string, postId?: string): Promise<void> {
    await admin.firestore().collection("mediaGateQuarantine").doc(uploadPath.replace(/\//g, "__")).set({
        uploadPath,
        uid,
        postId: postId ?? null,
        status: "quarantined",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}

async function callManagedContentSafetyProvider(uploadPath: string): Promise<ManagedProviderResult> {
    const endpoint = process.env.MEDIA_GATE_PROVIDER_ENDPOINT;
    if (!endpoint) {
        return {
            providerVersion: "managed-provider-unconfigured",
            decision: decisionAfterRequiredStageFailure(),
            findings: [],
        };
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5_000);
    try {
        const response = await fetch(endpoint, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ uploadPath }),
            signal: controller.signal,
        });
        if (!response.ok) {
            return {
                providerVersion: "managed-provider-error",
                decision: decisionAfterRequiredStageFailure(),
                findings: [],
            };
        }
        const body = await response.json() as Partial<ManagedProviderResult>;
        return {
            providerVersion: String(body.providerVersion ?? "managed-provider-unknown"),
            decision: normalizeDecision(body.decision),
            findings: Array.isArray(body.findings) ? body.findings : [],
        };
    } catch {
        return {
            providerVersion: "managed-provider-timeout-or-error",
            decision: decisionAfterRequiredStageFailure(),
            findings: [],
        };
    } finally {
        clearTimeout(timeout);
    }
}

async function callGatedCSAMProviderInterfaceOnly(_uploadPath: string): Promise<void> {
    // Interface only: intentionally no provider implementation and no raw-media handling.
    throw new HttpsError("failed-precondition", "CSAM provider compliance gate is not cleared");
}

async function applyServerSideRedactions(_uploadPath: string, actions: RedactionAction[]): Promise<string[]> {
    // Server must re-verify and apply redactions. Wave 0 stores decisions only while the
    // managed media-transform provider and keys remain human-configured.
    const actionNames = new Set(actions.map((action) => action.type));
    actionNames.add("stripEXIF");
    actionNames.add("removeLocation");
    return Array.from(actionNames).sort();
}

function mergePolicyDecision(providerDecision: PolicyDecision, knownMinorAuthor: boolean): PolicyDecision {
    if (knownMinorAuthor && providerDecision === "publish") {
        return "limit";
    }
    return providerDecision === "publish" ? "publish" : providerDecision;
}

function normalizeDecision(decision: unknown): PolicyDecision {
    switch (decision) {
    case "publish":
    case "blur":
    case "limit":
    case "block":
    case "review":
        return decision;
    default:
        return failClosedPolicyDecision;
    }
}

function buildAuditRecord(input: {
    postId?: string;
    providerVersion: string;
    findingCategories: SafetyAuditRecord["findingCategories"];
    actionsTaken: string[];
    decision: PolicyDecision;
}): SafetyAuditRecord {
    const createdAt = new Date();
    const retention = new Date(createdAt.getTime() + 30 * 24 * 60 * 60 * 1000);
    return {
        auditId: admin.firestore().collection("safetyAuditRecords").doc().id,
        postId: input.postId,
        createdAt: createdAt.toISOString(),
        providerVersion: input.providerVersion,
        modelVersion: "media-gate-policy-v0",
        findingCategories: Array.from(new Set(input.findingCategories)),
        actionsTaken: input.actionsTaken,
        policyDecision: input.decision,
        appealStatus: "none",
        retentionExpiresAt: retention.toISOString(),
    };
}

async function writeFailClosedAudit(input: {
    uid: string;
    postId?: string;
    reason: string;
    clientFindings: SafetyFinding[];
}) {
    const audit = buildAuditRecord({
        postId: input.postId,
        providerVersion: "fail-closed",
        findingCategories: input.clientFindings.map((finding) => finding.category),
        actionsTaken: ["quarantine", input.reason],
        decision: decisionAfterRequiredStageFailure(),
    });
    await admin.firestore().collection("safetyAuditRecords").doc(audit.auditId).set({
        ...audit,
        uid: input.uid,
    });
    return { ok: false, decision: audit.policyDecision, auditId: audit.auditId };
}
