/**
 * orgVerification.ts
 *
 * Organization Identity Verification — Trust OS requirement.
 *
 * Background: processGivingCharge.ts enforces `nonprofit.identityVerified`
 * before any donation transfer is processed. These callables provide the
 * end-to-end pipeline: org admin submits a request → AMEN admin approves or
 * rejects → Firestore org doc is updated server-side only.
 *
 * Security invariants:
 *  - Requires Firebase Auth + App Check on every callable (enforceAppCheck: true).
 *  - Caller identity derived from request.auth — never from client data.
 *  - `identityVerified` and `verificationStatus` on the org doc are written
 *    ONLY by the Admin SDK here. Direct client writes are blocked in Firestore rules.
 *  - All approve/reject actions require request.auth.token.admin === true.
 *  - Audit log entries are append-only via Admin SDK.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {requireAuthAndAppCheck} from "./amenAI/common";
import {enforceRateLimit} from "./rateLimit";
import * as logger from "firebase-functions/logger";

const db = getFirestore();

const ORG_VERIFICATION_RATE_LIMIT = {
    name: "org_verification_submit_1hr",
    windowMs: 3_600_000,
    maxCalls: 3,
};

// ─── Types ────────────────────────────────────────────────────────────────────

type OrgType = "church" | "ministry" | "nonprofit" | "school";

interface SubmitOrgVerificationInput {
    orgId: string;
    orgType: OrgType;
    legalName: string;
    websiteUrl: string;
    einOrCharityNumber?: string;
    jurisdictionCountry: string;
}

interface ApproveOrgVerificationInput {
    orgId: string;
    notes?: string;
}

interface RejectOrgVerificationInput {
    orgId: string;
    reason: string;
}

const VALID_ORG_TYPES = new Set<OrgType>([
    "church", "ministry", "nonprofit", "school",
]);

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Resolves the org document from either the `orgs` or `nonprofits` collection.
 * Returns { ref, data } or throws not-found if neither exists.
 */
async function resolveOrgDoc(orgId: string): Promise<{
    ref: FirebaseFirestore.DocumentReference;
    data: FirebaseFirestore.DocumentData;
    collection: "orgs" | "nonprofits";
}> {
    const orgsSnap = await db.collection("orgs").doc(orgId).get();
    if (orgsSnap.exists) {
        return {ref: orgsSnap.ref, data: orgsSnap.data()!, collection: "orgs"};
    }
    const nonprofitsSnap = await db.collection("nonprofits").doc(orgId).get();
    if (nonprofitsSnap.exists) {
        return {ref: nonprofitsSnap.ref, data: nonprofitsSnap.data()!, collection: "nonprofits"};
    }
    throw new HttpsError("not-found", "Organization not found.");
}

/**
 * Verifies the caller is the owner/admin of the org.
 * Checks org.ownerUid first, then falls back to org.adminUids array.
 */
function assertCallerIsOrgOwner(
    uid: string,
    orgData: FirebaseFirestore.DocumentData,
    orgId: string
): void {
    const ownerUid = orgData.ownerUid as string | undefined;
    const adminUids = Array.isArray(orgData.adminUids)
        ? (orgData.adminUids as string[])
        : [];

    const isOwner = ownerUid === uid;
    const isAdmin = adminUids.includes(uid);

    if (!isOwner && !isAdmin) {
        logger.warn("[orgVerification] unauthorized submit attempt", {uid, orgId});
        throw new HttpsError(
            "permission-denied",
            "You must be the owner or admin of this organization to submit a verification request."
        );
    }
}

/**
 * Requires the caller to have the `admin` custom claim set on their token.
 */
function assertPlatformAdmin(auth: {token?: {admin?: boolean}} | undefined): void {
    if (auth?.token?.admin !== true) {
        throw new HttpsError(
            "permission-denied",
            "This action requires platform admin privileges."
        );
    }
}

/**
 * Appends an entry to trustAuditLog. Non-fatal — failures are logged but
 * never propagated so the primary operation is not blocked.
 */
async function writeTrustAuditLog(
    eventType: string,
    actorUid: string,
    orgId: string,
    extra?: Record<string, unknown>
): Promise<void> {
    try {
        await db.collection("trustAuditLog").add({
            eventType,
            actorUid,
            orgId,
            ...extra,
            createdAt: FieldValue.serverTimestamp(),
        });
    } catch (err) {
        logger.error("[orgVerification] failed to write trustAuditLog — compliance gap", {
            eventType, actorUid, orgId, err,
        });
    }
}

// ─── 1. submitOrgVerificationRequest ─────────────────────────────────────────

/**
 * Called by an org owner/admin to submit an identity verification request.
 *
 * Writes to:
 *   orgVerificationRequests/{orgId}   — verification request document
 *   orgs/{orgId}  OR  nonprofits/{orgId}  — updates verificationStatus: "pending"
 *
 * Returns: { requestId: orgId, status: "pending" }
 */
export const submitOrgVerificationRequest = onCall(
    {enforceAppCheck: true},
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);
        await enforceRateLimit(uid, [ORG_VERIFICATION_RATE_LIMIT]);

        const {
            orgId,
            orgType,
            legalName,
            websiteUrl,
            einOrCharityNumber,
            jurisdictionCountry,
        } = (request.data ?? {}) as Partial<SubmitOrgVerificationInput>;

        // ── 1. Input validation ───────────────────────────────────────────
        if (!orgId || typeof orgId !== "string") {
            throw new HttpsError("invalid-argument", "orgId is required.");
        }
        if (!orgType || !VALID_ORG_TYPES.has(orgType as OrgType)) {
            throw new HttpsError(
                "invalid-argument",
                `orgType must be one of: ${[...VALID_ORG_TYPES].join(", ")}.`
            );
        }
        if (!legalName || typeof legalName !== "string" || !legalName.trim()) {
            throw new HttpsError("invalid-argument", "legalName is required.");
        }
        if (!websiteUrl || typeof websiteUrl !== "string" || !websiteUrl.trim()) {
            throw new HttpsError("invalid-argument", "websiteUrl is required.");
        }
        if (!jurisdictionCountry || typeof jurisdictionCountry !== "string") {
            throw new HttpsError("invalid-argument", "jurisdictionCountry is required.");
        }

        // ── 2. Verify org exists + caller is owner/admin ──────────────────
        const {ref: orgRef, data: orgData} = await resolveOrgDoc(orgId);
        assertCallerIsOrgOwner(uid, orgData, orgId);

        // ── 3. Idempotency: reject if already approved ────────────────────
        if (orgData.identityVerified === true) {
            throw new HttpsError(
                "already-exists",
                "This organization has already been verified."
            );
        }

        // ── 4. Write verification request + update org status in a batch ──
        const batch = db.batch();

        const requestRef = db.collection("orgVerificationRequests").doc(orgId);
        batch.set(requestRef, {
            orgId,
            orgType,
            legalName: legalName.trim(),
            websiteUrl: websiteUrl.trim(),
            einOrCharityNumber: einOrCharityNumber?.trim() ?? null,
            jurisdictionCountry,
            status: "pending",
            submittedAt: FieldValue.serverTimestamp(),
            submittedBy: uid,
        }, {merge: false});

        batch.update(orgRef, {
            verificationStatus: "pending",
            updatedAt: FieldValue.serverTimestamp(),
        });

        await batch.commit();

        logger.info("[submitOrgVerificationRequest] request submitted", {
            orgId, uid, orgType,
        });

        return {requestId: orgId, status: "pending"};
    }
);

// ─── 2. approveOrgVerification ────────────────────────────────────────────────

/**
 * Admin-only. Approves a pending org verification request.
 *
 * Updates:
 *   orgVerificationRequests/{orgId}   — status: "approved", approvedAt, approvedBy
 *   orgs/{orgId}  OR  nonprofits/{orgId} — identityVerified: true, verificationStatus: "approved", verifiedAt
 *
 * Logs to trustAuditLog: eventType "org_verification_approved"
 *
 * Returns: { success: true }
 */
export const approveOrgVerification = onCall(
    {enforceAppCheck: true},
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);
        assertPlatformAdmin(request.auth as {token?: {admin?: boolean}} | undefined);

        const {orgId, notes} =
            (request.data ?? {}) as Partial<ApproveOrgVerificationInput>;

        if (!orgId || typeof orgId !== "string") {
            throw new HttpsError("invalid-argument", "orgId is required.");
        }

        // ── 1. Verify request exists ──────────────────────────────────────
        const requestRef = db.collection("orgVerificationRequests").doc(orgId);
        const requestSnap = await requestRef.get();
        if (!requestSnap.exists) {
            throw new HttpsError("not-found", "No verification request found for this org.");
        }
        const requestData = requestSnap.data()!;
        if (requestData.status !== "pending") {
            throw new HttpsError(
                "failed-precondition",
                `Cannot approve a request with status "${requestData.status}".`
            );
        }

        // ── 2. Resolve org doc ────────────────────────────────────────────
        const {ref: orgRef} = await resolveOrgDoc(orgId);

        // ── 3. Batch-write approval ───────────────────────────────────────
        const batch = db.batch();

        batch.update(requestRef, {
            status: "approved",
            approvedAt: FieldValue.serverTimestamp(),
            approvedBy: uid,
            notes: notes?.trim() ?? null,
        });

        batch.update(orgRef, {
            identityVerified: true,
            verificationStatus: "approved",
            verifiedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
        });

        await batch.commit();

        // ── 4. Audit log ──────────────────────────────────────────────────
        await writeTrustAuditLog("org_verification_approved", uid, orgId, {
            notes: notes?.trim() ?? null,
        });

        logger.info("[approveOrgVerification] org approved", {orgId, approvedBy: uid});

        return {success: true};
    }
);

// ─── 3. rejectOrgVerification ─────────────────────────────────────────────────

/**
 * Admin-only. Rejects a pending org verification request.
 *
 * Updates:
 *   orgVerificationRequests/{orgId}   — status: "rejected", rejectedAt, rejectedBy, rejectionReason
 *   orgs/{orgId}  OR  nonprofits/{orgId} — verificationStatus: "rejected"
 *
 * Logs to trustAuditLog: eventType "org_verification_rejected"
 *
 * Returns: { success: true }
 */
export const rejectOrgVerification = onCall(
    {enforceAppCheck: true},
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);
        assertPlatformAdmin(request.auth as {token?: {admin?: boolean}} | undefined);

        const {orgId, reason} =
            (request.data ?? {}) as Partial<RejectOrgVerificationInput>;

        if (!orgId || typeof orgId !== "string") {
            throw new HttpsError("invalid-argument", "orgId is required.");
        }
        if (!reason || typeof reason !== "string" || !reason.trim()) {
            throw new HttpsError("invalid-argument", "reason is required.");
        }
        if (reason.length > 1000) {
            throw new HttpsError("invalid-argument", "reason must not exceed 1000 characters.");
        }

        // ── 1. Verify request exists ──────────────────────────────────────
        const requestRef = db.collection("orgVerificationRequests").doc(orgId);
        const requestSnap = await requestRef.get();
        if (!requestSnap.exists) {
            throw new HttpsError("not-found", "No verification request found for this org.");
        }
        const requestData = requestSnap.data()!;
        if (requestData.status !== "pending") {
            throw new HttpsError(
                "failed-precondition",
                `Cannot reject a request with status "${requestData.status}".`
            );
        }

        // ── 2. Resolve org doc ────────────────────────────────────────────
        const {ref: orgRef} = await resolveOrgDoc(orgId);

        // ── 3. Batch-write rejection ──────────────────────────────────────
        const batch = db.batch();

        batch.update(requestRef, {
            status: "rejected",
            rejectedAt: FieldValue.serverTimestamp(),
            rejectedBy: uid,
            rejectionReason: reason.trim(),
        });

        batch.update(orgRef, {
            verificationStatus: "rejected",
            updatedAt: FieldValue.serverTimestamp(),
        });

        await batch.commit();

        // ── 4. Audit log ──────────────────────────────────────────────────
        await writeTrustAuditLog("org_verification_rejected", uid, orgId, {
            rejectionReason: reason.trim(),
        });

        logger.info("[rejectOrgVerification] org rejected", {
            orgId, rejectedBy: uid,
        });

        return {success: true};
    }
);
