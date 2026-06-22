/**
 * insiderThreatAudit.ts — Insider-threat access-control spine.
 *
 * WHY THIS EXISTS (Trust & Safety Remediation item 21 — "cheap now, brutal to
 * retrofit; build it before a single moderator can see private data"):
 *   Before any second admin, moderator, or contractor can read private data
 *   (DMs, prayer requests, minors' data, Tier-1 evidence), the platform must:
 *     1. record WHO accessed WHAT and WHEN in an immutable audit log, and
 *     2. enforce the two-person rule on sensitive cases (dualApprovalRequired)
 *        and break-glass-with-justification for private content
 *        (breakGlassRequiredForPrivateContent).
 *
 *   submitReport.ts ALREADY writes `dualApprovalRequired` and
 *   `breakGlassRequiredForPrivateContent` onto Tier-1 moderationCases,
 *   evidenceVault, and ncmecReadiness records — but until now nothing ever READ
 *   or ENFORCED them. This module closes that gap: it is the single server-side
 *   gate that sensitive-data tooling must route through.
 *
 * SAFETY POSTURE:
 *   - Audit logging is ALWAYS on. Recording an access is never harmful, and an
 *     unlogged access is the exact failure this module prevents.
 *   - ENFORCEMENT (blocking access until two distinct approvals exist, or a
 *     break-glass justification is supplied) is gated behind
 *     INSIDER_THREAT_ENFORCEMENT_ENABLED, default OFF, so this ships dark and is
 *     turned on deliberately. When enforcement is OFF, access is still LOGGED.
 *   - FAIL-CLOSED: when enforcement is ON and approval state cannot be
 *     determined, access is DENIED.
 *   - sensitiveAccessLog is itself sensitive: admin-SDK-write-only and
 *     client-read-denied (see firestore.rules). Oversight reads go through the
 *     getSensitiveAccessLog callable, restricted to executive_admin/owner.
 *
 * This module is purely additive. It does not modify submitReport.ts or the
 * ingestion review workflow; it provides the gate those surfaces should call.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

const db = () => admin.firestore();
const now = () => admin.firestore.FieldValue.serverTimestamp();

// ─── Configuration ─────────────────────────────────────────────────────────────

/**
 * Master enforcement switch. Default OFF: access is logged but never blocked.
 * Flip to "true" (env var INSIDER_THREAT_ENFORCEMENT_ENABLED) only after the
 * audit log and approval flows have been validated end-to-end.
 */
const ENFORCEMENT_ENABLED =
    (process.env.INSIDER_THREAT_ENFORCEMENT_ENABLED ?? "false") === "true";

/** Number of distinct approvers required to satisfy the two-person rule. */
const REQUIRED_APPROVERS = 2;

/** Roles permitted to perform sensitive access / approvals (trained reviewers). */
const REVIEWER_ROLES = new Set([
    "owner",
    "executive_admin",
    "pastor",
    "moderator",
]);

/** Roles permitted to read the access-audit log (oversight only). */
const OVERSIGHT_ROLES = new Set(["owner", "executive_admin"]);

// ─── Types ──────────────────────────────────────────────────────────────────────

export type SensitiveResourceType =
    | "dm"
    | "prayer_request"
    | "minor_data"
    | "evidence_vault"
    | "moderation_case"
    | "user_pii";

export type AccessAction = "view" | "export" | "modify" | "delete";

export interface SensitiveAccessParams {
    /** UID of the staff member performing the access. */
    actorUid: string;
    /** Class of sensitive resource being touched. */
    resourceType: SensitiveResourceType;
    /** Document / conversation / case identifier being accessed. */
    resourceId: string;
    /** What the actor is doing with the resource. */
    action: AccessAction;
    /** Optional subject — the user whose private data this is. */
    subjectUid?: string | null;
    /** Free-text reason. REQUIRED when breakGlass is true. */
    justification?: string | null;
    /** True when the actor is bypassing a normal restriction to view private content. */
    breakGlass?: boolean;
    /** Any additional structured context (case tier, channel, etc.). */
    metadata?: Record<string, unknown>;
}

interface StaffClaims {
    isAdmin: boolean;
    role: string;
}

interface DualApprovalState {
    /** Whether this case is flagged as requiring two-person approval. */
    required: boolean;
    /** Distinct approvers recorded so far. */
    approverCount: number;
    /** True once approverCount >= REQUIRED_APPROVERS (or not required). */
    satisfied: boolean;
    /** Whether the case requires break-glass for private content. */
    breakGlassRequired: boolean;
}

export interface AccessDecision {
    authorized: boolean;
    /** Machine reason code: "logged_only", "approved", "denied_pending_approval", etc. */
    reason: string;
    /** ID of the audit-log entry recorded for this decision. */
    auditId: string;
    dualApproval?: DualApprovalState;
}

// ─── Claims / role helpers ──────────────────────────────────────────────────────

async function loadClaims(uid: string): Promise<StaffClaims> {
    const record = await admin.auth().getUser(uid);
    const claims = record.customClaims ?? {};
    return {
        isAdmin: claims["admin"] === true,
        role: typeof claims["role"] === "string" ? (claims["role"] as string) : "",
    };
}

function isReviewer(claims: StaffClaims): boolean {
    return claims.isAdmin || REVIEWER_ROLES.has(claims.role);
}

function requireAuthUid(request: { auth?: { uid?: string } | null }): string {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Auth required");
    return uid;
}

// ─── Audit log (always-on) ──────────────────────────────────────────────────────

/**
 * Append an immutable record to /sensitiveAccessLog. This is the single source of
 * truth for "who looked at whose private data, when, and why." Never throws on a
 * logging failure path silently — a failure to record an access is surfaced to the
 * caller so the access can itself be blocked when enforcement is on.
 *
 * @returns the audit-log document ID.
 */
export async function recordSensitiveAccess(
    params: SensitiveAccessParams
): Promise<string> {
    const ref = db().collection("sensitiveAccessLog").doc();
    await ref.set({
        auditId: ref.id,
        actorUid: params.actorUid,
        resourceType: params.resourceType,
        resourceId: params.resourceId,
        action: params.action,
        subjectUid: params.subjectUid ?? null,
        justification: params.justification ?? null,
        breakGlass: params.breakGlass === true,
        metadata: params.metadata ?? {},
        enforcementEnabled: ENFORCEMENT_ENABLED,
        createdAt: now(),
    });
    logger.info(
        `[InsiderThreatAudit] ${params.actorUid} ${params.action} ` +
            `${params.resourceType}:${params.resourceId}` +
            (params.breakGlass ? " [BREAK-GLASS]" : "")
    );
    return ref.id;
}

// ─── Dual-approval (two-person rule) ────────────────────────────────────────────

/**
 * Read the dual-approval state for a moderation case. The flags themselves are
 * written by submitReport.ts; the approvers live in the case's `approvals`
 * subcollection (one doc per distinct approver — see recordApproval).
 */
export async function evaluateDualApproval(
    caseId: string
): Promise<DualApprovalState> {
    const caseRef = db().collection("moderationCases").doc(caseId);
    const [caseSnap, approvals] = await Promise.all([
        caseRef.get(),
        caseRef.collection("approvals").get(),
    ]);

    const data = caseSnap.data() ?? {};
    const required = data["dualApprovalRequired"] === true;
    const breakGlassRequired = data["breakGlassRequiredForPrivateContent"] === true;

    // Distinct approvers — the subcollection is keyed by approver UID, so size is
    // already the distinct count, but we guard against legacy auto-id docs.
    const distinct = new Set<string>();
    approvals.forEach((doc) => {
        const approverUid = (doc.data()?.["approverUid"] as string) ?? doc.id;
        if (approverUid) distinct.add(approverUid);
    });

    const approverCount = distinct.size;
    const satisfied = !required || approverCount >= REQUIRED_APPROVERS;

    return { required, approverCount, satisfied, breakGlassRequired };
}

/**
 * Record one approval for a case. Idempotent per approver (keyed by UID), so the
 * same reviewer approving twice does not count twice toward the two-person rule.
 */
export async function recordApproval(
    caseId: string,
    approverUid: string
): Promise<DualApprovalState> {
    const approvalRef = db()
        .collection("moderationCases")
        .doc(caseId)
        .collection("approvals")
        .doc(approverUid);
    await approvalRef.set(
        { approverUid, approvedAt: now() },
        { merge: true }
    );
    return evaluateDualApproval(caseId);
}

// ─── The gate ───────────────────────────────────────────────────────────────────

/**
 * Authorize (and always log) an access to sensitive data.
 *
 * Behavior:
 *   - ALWAYS records the access in the audit log.
 *   - When ENFORCEMENT is OFF: authorizes everything (reason "logged_only").
 *   - When ENFORCEMENT is ON:
 *       • break-glass requires a non-empty justification, else DENY.
 *       • a case requiring dual approval that is not yet satisfied is DENY,
 *         UNLESS a valid break-glass justification is supplied (which is itself
 *         loudly logged for after-the-fact review).
 *   - Fails closed: any error evaluating approval state DENIES when enforcement
 *     is on.
 */
export async function authorizeSensitiveAccess(
    params: SensitiveAccessParams & { caseId?: string }
): Promise<AccessDecision> {
    const auditId = await recordSensitiveAccess(params);

    if (!ENFORCEMENT_ENABLED) {
        return { authorized: true, reason: "logged_only", auditId };
    }

    const hasJustification =
        typeof params.justification === "string" &&
        params.justification.trim().length > 0;

    // Break-glass demands a reason, enforcement on or off in spirit, hard here.
    if (params.breakGlass && !hasJustification) {
        return {
            authorized: false,
            reason: "denied_break_glass_requires_justification",
            auditId,
        };
    }

    // No case context → nothing to two-person-gate; the log + break-glass rule
    // above are the controls.
    if (!params.caseId) {
        return { authorized: true, reason: "approved_no_case_context", auditId };
    }

    try {
        const state = await evaluateDualApproval(params.caseId);

        if (state.satisfied) {
            return { authorized: true, reason: "approved", auditId, dualApproval: state };
        }

        // Not satisfied — break-glass with justification is the only override,
        // and it is conspicuously logged for oversight.
        if (params.breakGlass && hasJustification) {
            logger.warn(
                `[InsiderThreatAudit] BREAK-GLASS override on case ${params.caseId} ` +
                    `by ${params.actorUid}: ${params.justification}`
            );
            return {
                authorized: true,
                reason: "approved_break_glass_override",
                auditId,
                dualApproval: state,
            };
        }

        return {
            authorized: false,
            reason: "denied_pending_dual_approval",
            auditId,
            dualApproval: state,
        };
    } catch (err) {
        // Fail closed.
        logger.error(
            `[InsiderThreatAudit] approval evaluation failed for case ` +
                `${params.caseId}; failing closed: ${(err as Error).message}`
        );
        return { authorized: false, reason: "denied_evaluation_error", auditId };
    }
}

// ─── Callables ──────────────────────────────────────────────────────────────────

/**
 * approveSensitiveCase — a trained reviewer casts ONE approval on a case.
 * Two distinct reviewers must call this before the case is dual-approved.
 */
export const approveSensitiveCase = onCall(
    { enforceAppCheck: true },
    async (request) => {
        const uid = requireAuthUid(request);
        const claims = await loadClaims(uid);
        if (!isReviewer(claims)) {
            throw new HttpsError("permission-denied", "Reviewer role required");
        }

        const data = (request.data ?? {}) as Record<string, unknown>;
        const caseId =
            typeof data["caseId"] === "string" ? (data["caseId"] as string).trim() : "";
        if (!caseId) throw new HttpsError("invalid-argument", "caseId required");

        const state = await recordApproval(caseId, uid);
        await recordSensitiveAccess({
            actorUid: uid,
            resourceType: "moderation_case",
            resourceId: caseId,
            action: "modify",
            metadata: { event: "approval_cast", approverCount: state.approverCount },
        });

        return {
            caseId,
            approverCount: state.approverCount,
            requiredApprovers: REQUIRED_APPROVERS,
            satisfied: state.satisfied,
        };
    }
);

/**
 * accessSensitiveCase — the gated read path for a Tier-1 moderation case and its
 * preserved evidence. Enforces the two-person rule + break-glass and always logs.
 * Returns case + evidence-vault data only when authorized.
 */
export const accessSensitiveCase = onCall(
    { enforceAppCheck: true },
    async (request) => {
        const uid = requireAuthUid(request);
        const claims = await loadClaims(uid);
        if (!isReviewer(claims)) {
            throw new HttpsError("permission-denied", "Reviewer role required");
        }

        const data = (request.data ?? {}) as Record<string, unknown>;
        const caseId =
            typeof data["caseId"] === "string" ? (data["caseId"] as string).trim() : "";
        if (!caseId) throw new HttpsError("invalid-argument", "caseId required");
        const breakGlass = data["breakGlass"] === true;
        const justification =
            typeof data["justification"] === "string"
                ? (data["justification"] as string)
                : null;

        const decision = await authorizeSensitiveAccess({
            actorUid: uid,
            resourceType: "evidence_vault",
            resourceId: caseId,
            action: "view",
            caseId,
            breakGlass,
            justification,
            metadata: { role: claims.role || (claims.isAdmin ? "admin" : "") },
        });

        if (!decision.authorized) {
            throw new HttpsError(
                "permission-denied",
                `Access denied: ${decision.reason}`
            );
        }

        const [caseSnap, evidenceSnap] = await Promise.all([
            db().collection("moderationCases").doc(caseId).get(),
            db().collection("evidenceVault").doc(caseId).get(),
        ]);

        return {
            authorized: true,
            reason: decision.reason,
            auditId: decision.auditId,
            dualApproval: decision.dualApproval ?? null,
            case: caseSnap.exists ? caseSnap.data() : null,
            evidence: evidenceSnap.exists ? evidenceSnap.data() : null,
        };
    }
);

/**
 * getSensitiveAccessLog — oversight read of recent audit entries. Restricted to
 * owner / executive_admin so reviewers cannot quietly inspect (or learn to evade)
 * the very log that watches them.
 */
export const getSensitiveAccessLog = onCall(
    { enforceAppCheck: true },
    async (request) => {
        const uid = requireAuthUid(request);
        const claims = await loadClaims(uid);
        if (!(claims.isAdmin || OVERSIGHT_ROLES.has(claims.role))) {
            throw new HttpsError("permission-denied", "Oversight role required");
        }

        const data = (request.data ?? {}) as Record<string, unknown>;
        const rawLimit = typeof data["limit"] === "number" ? (data["limit"] as number) : 100;
        const limit = Math.max(1, Math.min(500, Math.floor(rawLimit)));
        const filterActor =
            typeof data["actorUid"] === "string" ? (data["actorUid"] as string) : null;

        let query: admin.firestore.Query = db()
            .collection("sensitiveAccessLog")
            .orderBy("createdAt", "desc")
            .limit(limit);
        if (filterActor) {
            query = db()
                .collection("sensitiveAccessLog")
                .where("actorUid", "==", filterActor)
                .orderBy("createdAt", "desc")
                .limit(limit);
        }

        const snap = await query.get();
        // Reading the audit log is itself an oversight action — record it.
        await recordSensitiveAccess({
            actorUid: uid,
            resourceType: "user_pii",
            resourceId: "sensitiveAccessLog",
            action: "view",
            metadata: { event: "oversight_read", returned: snap.size, filterActor },
        });

        return {
            entries: snap.docs.map((d) => d.data()),
            count: snap.size,
            enforcementEnabled: ENFORCEMENT_ENABLED,
        };
    }
);
