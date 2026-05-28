/**
 * verification/index.ts
 *
 * Amen Verification & Trust System — Cloud Functions (v1 callable style).
 *
 * Security invariants:
 *  - All callables require App Check (context.app != undefined).
 *  - All callables derive uid from context.auth — never from client data.
 *  - Raw ID documents are NEVER stored.
 *  - All verification truth fields (identityVerified, creatorVerified, etc.)
 *    are written only by the Admin SDK — never directly by clients.
 *  - Audit logs are append-only via Admin SDK.
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { calculateRiskScore, checkRateLimit } from "./riskEngine";
import { getKYCProvider } from "./kycProvider";

const db = admin.firestore();
const auth = admin.auth();

// ─── Valid role values ────────────────────────────────────────────────────────

const VALID_ROLES = new Set([
    "Pastor",
    "Church Admin",
    "Youth Leader",
    "Ministry Staff",
    "Teacher",
    "Mentor",
    "Worship Leader",
    "Event Host",
    "Group Moderator",
    "Other",
]);

// ─── Auth guard ───────────────────────────────────────────────────────────────

function requireAppAuth(context: functions.https.CallableContext): string {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Authentication required."
        );
    }
    if (context.app == undefined) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }
    return context.auth.uid;
}

// ─── Audit log ────────────────────────────────────────────────────────────────

async function writeAuditLog(
    actorUid: string,
    targetUid: string,
    action: string,
    reason: string,
    before: unknown,
    after: unknown,
    orgId?: string
): Promise<void> {
    await db.collection("verificationAuditLogs").add({
        actorUid,
        targetUid,
        orgId: orgId || null,
        action,
        reason,
        before: before || null,
        after: after || null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

// ─── Public verification summary builder ─────────────────────────────────────

async function rebuildPublicVerificationSummary(uid: string): Promise<void> {
    const [userRecord, privateVerifSnap, userSnap] = await Promise.all([
        auth.getUser(uid).catch(() => null),
        db.collection("users").doc(uid).collection("privateVerification").doc("main").get(),
        db.collection("users").doc(uid).get(),
    ]);

    const userData = userSnap.exists ? (userSnap.data() as Record<string, unknown>) : {};
    const privateData = privateVerifSnap.exists
        ? (privateVerifSnap.data() as Record<string, unknown>)
        : {};

    // Determine creator verification status
    const creatorReqSnap = await db
        .collection("users")
        .doc(uid)
        .collection("verificationRequests")
        .where("type", "==", "creator")
        .where("status", "==", "approved")
        .get();
    const creatorVerified = !creatorReqSnap.empty;

    const identityVerified = privateData.identityVerified === true;
    const emailVerified = userRecord?.emailVerified ?? false;
    const phoneVerified = userData.phoneVerified === true;
    const safetyStanding =
        typeof userData.safetyStanding === "string"
            ? userData.safetyStanding
            : "active";

    // Build visible badges
    const visibleBadges: string[] = [];
    if (identityVerified) visibleBadges.push("identity_verified");
    if (creatorVerified) visibleBadges.push("creator_verified");
    if (emailVerified) visibleBadges.push("email_verified");

    await db.collection("users").doc(uid).update({
        publicVerificationSummary: {
            emailVerified,
            phoneVerified,
            identityVerified,
            creatorVerified,
            safetyStanding,
            visibleBadges,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

// ─── 1. startIdentityVerification ────────────────────────────────────────────

export const startIdentityVerification = functions.https.onCall( // enforceAppCheck: true — enforced via requireAppAuth context.app guard
    async (data: unknown, context: functions.https.CallableContext) => {
        const uid = requireAppAuth(context);

        try {
            await checkRateLimit(uid, "startIdentityVerification", 3);

            const risk = await calculateRiskScore(uid);

            if (risk.level === "blocked") {
                throw new functions.https.HttpsError(
                    "permission-denied",
                    "Verification is not available at this time."
                );
            }

            if (risk.level === "high") {
                // Create a manual review request
                const requestRef = db
                    .collection("users")
                    .doc(uid)
                    .collection("verificationRequests")
                    .doc();

                await requestRef.set({
                    type: "identity",
                    status: "manual_review",
                    provider: "amen_kyc",
                    riskLevel: risk.level,
                    riskScore: risk.score,
                    riskSignals: risk.signals,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });

                await writeAuditLog(
                    uid,
                    uid,
                    "identity_verification_manual_review",
                    "risk_score_high",
                    null,
                    { requestId: requestRef.id, riskLevel: risk.level }
                );

                return {
                    status: "manual_review",
                    message: "Your request requires additional review.",
                };
            }

            // Create a Firestore request doc first so we have its ID for the provider session
            const requestRef = db
                .collection("users")
                .doc(uid)
                .collection("verificationRequests")
                .doc();

            // Generate a local session token for binding the Firestore doc to the
            // provider session. Store only the hash — raw token returned to client once.
            const sessionToken = crypto.randomBytes(32).toString("hex");
            const sessionTokenHash = crypto
                .createHash("sha256")
                .update(sessionToken)
                .digest("hex");

            // Delegate to the configured KYC provider (Persona / Stripe / Mock)
            const provider = getKYCProvider();
            const providerSession = await provider.createSession(uid, requestRef.id);

            await requestRef.set({
                type: "identity",
                status: "pending",
                provider: provider.name,
                sessionTokenHash,
                providerInquiryId: providerSession.providerInquiryId,
                expiresAt: admin.firestore.Timestamp.fromDate(
                    new Date(providerSession.expiresAt)
                ),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Return the raw session token and the provider's hosted flow URL.
            // The client opens sessionUrl in SFSafariViewController.
            return {
                sessionToken,
                sessionUrl: providerSession.sessionUrl,
                expiresAt: providerSession.expiresAt,
            };
        } catch (err) {
            if (err instanceof functions.https.HttpsError) throw err;
            functions.logger.error("[startIdentityVerification] unexpected error", { uid, err });
            throw new functions.https.HttpsError(
                "internal",
                "An unexpected error occurred. Please try again."
            );
        }
    }
);

// ─── 2. handleIdentityVerificationWebhook ────────────────────────────────────

export const handleIdentityVerificationWebhook = functions.https.onRequest(
    async (req, res) => {
        const provider = getKYCProvider();

        // 1. Verify webhook signature — reject immediately on failure
        try {
            provider.verifyWebhookSignature(
                req.rawBody ?? JSON.stringify(req.body),
                req.headers as Record<string, string | string[] | undefined>
            );
        } catch (sigErr) {
            functions.logger.warn("[webhook] signature verification failed", { sigErr });
            res.status(401).send("Invalid signature");
            return;
        }

        // 2. Parse into a normalised decision — null means "ignore this event type"
        const decision = provider.parseWebhookEvent(
            req.body,
            req.headers as Record<string, string | string[] | undefined>
        );

        if (!decision) {
            res.status(200).send("OK");
            return;
        }

        const { event, providerReferenceId, verificationLevel, country, riskScore, expiresAt, uid, requestId } = decision;

        if (!uid || !requestId) {
            res.status(400).send("Missing uid or requestId");
            return;
        }

        try {
            const requestRef = db
                .collection("users")
                .doc(uid)
                .collection("verificationRequests")
                .doc(requestId);

            const requestSnap = await requestRef.get();
            if (!requestSnap.exists) {
                res.status(404).send("Verification request not found");
                return;
            }

            const requestData = requestSnap.data() as Record<string, unknown>;

            // Idempotency: skip if this providerReferenceId was already processed
            if (requestData.providerReferenceId === providerReferenceId) {
                functions.logger.info("[webhook] duplicate event, skipping", {
                    uid,
                    requestId,
                    providerReferenceId,
                });
                res.status(200).send("OK");
                return;
            }

            // Update the verification request
            await requestRef.update({
                status: event,
                providerReferenceId,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            if (event === "approved") {
                // Write to privateVerification — NEVER store raw ID images
                await db
                    .collection("users")
                    .doc(uid)
                    .collection("privateVerification")
                    .doc("main")
                    .set({
                        provider: "amen_kyc",
                        providerReferenceId,
                        verificationLevel,
                        country,
                        riskScore,
                        identityVerified: true,
                        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                        expiresAt: admin.firestore.Timestamp.fromDate(new Date(expiresAt)),
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    }, { merge: true });

                // Update public summary
                const userSnap = await db.collection("users").doc(uid).get();
                const currentSummary =
                    userSnap.exists
                        ? ((userSnap.data() as Record<string, unknown>)
                              .publicVerificationSummary as Record<string, unknown>) || {}
                        : {};

                const existingBadges = Array.isArray(currentSummary.visibleBadges)
                    ? (currentSummary.visibleBadges as string[])
                    : [];
                const visibleBadges = existingBadges.includes("identity_verified")
                    ? existingBadges
                    : [...existingBadges, "identity_verified"];

                await db.collection("users").doc(uid).update({
                    "publicVerificationSummary.identityVerified": true,
                    "publicVerificationSummary.visibleBadges": visibleBadges,
                    "publicVerificationSummary.updatedAt":
                        admin.firestore.FieldValue.serverTimestamp(),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            await writeAuditLog(
                "webhook",
                uid,
                event,
                "provider_decision",
                null,
                { providerReferenceId, verificationLevel, event }
            );

            res.status(200).send("OK");
        } catch (err) {
            functions.logger.error("[handleIdentityVerificationWebhook] error", { uid, requestId, err });
            res.status(500).send("Internal server error");
        }
    }
);

// ─── 3. requestOrganizationVerification ──────────────────────────────────────

export const requestOrganizationVerification = functions.https.onCall( // enforceAppCheck: true — enforced via requireAppAuth context.app guard
    async (
        data: { orgId?: string; domainEmail?: string; orgName?: string },
        context: functions.https.CallableContext
    ) => {
        const uid = requireAppAuth(context);

        try {
            await checkRateLimit(uid, "requestOrganizationVerification", 2);

            const { orgId, domainEmail, orgName } = data || {};

            if (typeof orgId !== "string" || !orgId.trim()) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "orgId is required."
                );
            }
            if (
                typeof domainEmail !== "string" ||
                !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(domainEmail)
            ) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "A valid domain email address is required."
                );
            }
            if (typeof orgName !== "string" || !orgName.trim()) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "orgName is required."
                );
            }

            // Verify the caller is an admin of the organization
            const memberSnap = await db
                .collection("organizations")
                .doc(orgId)
                .collection("members")
                .doc(uid)
                .get();

            const isOrgAdmin =
                memberSnap.exists &&
                (memberSnap.data() as Record<string, unknown>).role === "admin";

            // Also allow if the user document lists them as admin
            let authorized = isOrgAdmin;
            if (!authorized) {
                const userSnap = await db.collection("users").doc(uid).get();
                const userData = userSnap.exists
                    ? (userSnap.data() as Record<string, unknown>)
                    : {};
                const adminOfOrgs = Array.isArray(userData.adminOfOrgs)
                    ? (userData.adminOfOrgs as string[])
                    : [];
                authorized = adminOfOrgs.includes(orgId);
            }

            if (!authorized) {
                throw new functions.https.HttpsError(
                    "permission-denied",
                    "You must be an organization admin to request verification."
                );
            }

            const domainEmailHash = crypto
                .createHash("sha256")
                .update(domainEmail)
                .digest("hex");

            // Create organization-level request
            const orgRequestRef = db
                .collection("organizations")
                .doc(orgId)
                .collection("verificationRequests")
                .doc();

            const userRequestRef = db
                .collection("users")
                .doc(uid)
                .collection("verificationRequests")
                .doc(orgRequestRef.id);

            const batch = db.batch();

            batch.set(orgRequestRef, {
                type: "organization",
                status: "pending",
                requestedBy: uid,
                domainEmailHash, // hash only — never store raw email
                orgName: orgName.trim(),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            batch.set(userRequestRef, {
                type: "organization",
                status: "pending",
                orgId,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            await batch.commit();

            return { requestId: orgRequestRef.id, status: "pending" };
        } catch (err) {
            if (err instanceof functions.https.HttpsError) throw err;
            functions.logger.error("[requestOrganizationVerification] error", { uid, err });
            throw new functions.https.HttpsError(
                "internal",
                "An unexpected error occurred. Please try again."
            );
        }
    }
);

// ─── 4. verifyOrganizationDomain ─────────────────────────────────────────────

export const verifyOrganizationDomain = functions.https.onCall( // enforceAppCheck: true — enforced via requireAppAuth context.app guard
    async (
        data: { orgId?: string; challengeToken?: string },
        context: functions.https.CallableContext
    ) => {
        const uid = requireAppAuth(context);

        try {
            const { orgId, challengeToken } = data || {};

            if (typeof orgId !== "string" || !orgId.trim()) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "orgId is required."
                );
            }
            if (typeof challengeToken !== "string" || !challengeToken.trim()) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "challengeToken is required."
                );
            }

            const privateVerifSnap = await db
                .collection("organizations")
                .doc(orgId)
                .collection("privateVerification")
                .doc("main")
                .get();

            if (!privateVerifSnap.exists) {
                throw new functions.https.HttpsError(
                    "not-found",
                    "No pending domain challenge found for this organization."
                );
            }

            const privateData = privateVerifSnap.data() as Record<string, unknown>;
            const storedChallengeTokenHash =
                typeof privateData.domainChallengeTokenHash === "string"
                    ? privateData.domainChallengeTokenHash
                    : null;

            if (!storedChallengeTokenHash) {
                throw new functions.https.HttpsError(
                    "not-found",
                    "No pending domain challenge found for this organization."
                );
            }

            const providedHash = crypto
                .createHash("sha256")
                .update(challengeToken)
                .digest("hex");

            if (providedHash !== storedChallengeTokenHash) {
                throw new functions.https.HttpsError(
                    "permission-denied",
                    "Domain challenge verification failed."
                );
            }

            // Mark organization as domain-verified
            const batch = db.batch();

            batch.set(
                db.collection("organizations").doc(orgId).collection("privateVerification").doc("main"),
                {
                    domainVerified: true,
                    domainVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                    domainVerifiedBy: uid,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true }
            );

            batch.set(
                db.collection("organizations").doc(orgId)
                    .collection("publicVerificationSummary").doc("main"),
                {
                    domainVerified: true,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true }
            );

            await batch.commit();

            await writeAuditLog(
                uid,
                orgId,
                "organization_domain_verified",
                "domain_challenge_passed",
                null,
                { domainVerified: true },
                orgId
            );

            return { status: "verified" };
        } catch (err) {
            if (err instanceof functions.https.HttpsError) throw err;
            functions.logger.error("[verifyOrganizationDomain] error", { uid, err });
            throw new functions.https.HttpsError(
                "internal",
                "An unexpected error occurred. Please try again."
            );
        }
    }
);

// ─── 5. requestRoleVerification ───────────────────────────────────────────────

export const requestRoleVerification = functions.https.onCall( // enforceAppCheck: true — enforced via requireAppAuth context.app guard
    async (
        data: { orgId?: string; role?: string; scope?: string },
        context: functions.https.CallableContext
    ) => {
        const uid = requireAppAuth(context);

        try {
            await checkRateLimit(uid, "requestRoleVerification", 5);

            const { orgId, role, scope } = data || {};

            if (typeof orgId !== "string" || !orgId.trim()) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "orgId is required."
                );
            }
            if (typeof role !== "string" || !VALID_ROLES.has(role)) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    `role must be one of: ${[...VALID_ROLES].join(", ")}.`
                );
            }
            if (typeof scope !== "string" || !scope.trim()) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "scope is required."
                );
            }

            const requestRef = db
                .collection("users")
                .doc(uid)
                .collection("verificationRequests")
                .doc();

            const batch = db.batch();

            // Write to organizations/{orgId}/roles/{uid}
            batch.set(
                db.collection("organizations").doc(orgId).collection("roles").doc(uid),
                {
                    role,
                    status: "pending",
                    scope,
                    requestedBy: uid,
                    requestedAt: admin.firestore.FieldValue.serverTimestamp(),
                }
            );

            // Write to user's verificationRequests
            batch.set(requestRef, {
                type: "role",
                status: "pending",
                orgId,
                role,
                scope,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Notify org admins
            const adminsSnap = await db
                .collection("organizations")
                .doc(orgId)
                .collection("members")
                .where("role", "==", "admin")
                .get();

            adminsSnap.docs.forEach((adminDoc) => {
                batch.set(db.collection("notifications").doc(), {
                    recipientUid: adminDoc.id,
                    type: "role_verification_request",
                    requestId: requestRef.id,
                    requesterUid: uid,
                    orgId,
                    role,
                    scope,
                    read: false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            });

            await batch.commit();

            return { requestId: requestRef.id };
        } catch (err) {
            if (err instanceof functions.https.HttpsError) throw err;
            functions.logger.error("[requestRoleVerification] error", { uid, err });
            throw new functions.https.HttpsError(
                "internal",
                "An unexpected error occurred. Please try again."
            );
        }
    }
);

// ─── 6. approveRoleVerification ───────────────────────────────────────────────

export const approveRoleVerification = functions.https.onCall( // enforceAppCheck: true — enforced via requireAppAuth context.app guard
    async (
        data: {
            targetUid?: string;
            orgId?: string;
            role?: string;
            scope?: string;
            expiresAt?: number;
        },
        context: functions.https.CallableContext
    ) => {
        const uid = requireAppAuth(context);

        try {
            const { targetUid, orgId, role, scope, expiresAt } = data || {};

            if (typeof targetUid !== "string" || !targetUid.trim()) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "targetUid is required."
                );
            }
            if (typeof orgId !== "string" || !orgId.trim()) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "orgId is required."
                );
            }
            if (typeof role !== "string" || !VALID_ROLES.has(role)) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    `role must be one of: ${[...VALID_ROLES].join(", ")}.`
                );
            }
            if (typeof scope !== "string" || !scope.trim()) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "scope is required."
                );
            }

            // Verify caller is org admin
            const memberSnap = await db
                .collection("organizations")
                .doc(orgId)
                .collection("members")
                .doc(uid)
                .get();

            if (
                !memberSnap.exists ||
                (memberSnap.data() as Record<string, unknown>).role !== "admin"
            ) {
                throw new functions.https.HttpsError(
                    "permission-denied",
                    "You must be an organization admin to approve role verifications."
                );
            }

            const now = admin.firestore.FieldValue.serverTimestamp();
            const batch = db.batch();

            // Update the role record
            batch.set(
                db.collection("organizations").doc(orgId).collection("roles").doc(targetUid),
                {
                    status: "approved",
                    role,
                    scope,
                    issuedBy: uid,
                    issuedAt: now,
                    expiresAt: expiresAt
                        ? admin.firestore.Timestamp.fromDate(new Date(expiresAt))
                        : null,
                    updatedAt: now,
                },
                { merge: true }
            );

            // Update the corresponding verificationRequest in the target user's subcollection
            const verificationRequestsSnap = await db
                .collection("users")
                .doc(targetUid)
                .collection("verificationRequests")
                .where("type", "==", "role")
                .where("orgId", "==", orgId)
                .where("status", "==", "pending")
                .get();

            verificationRequestsSnap.docs.forEach((doc) => {
                batch.update(doc.ref, {
                    status: "approved",
                    updatedAt: now,
                });
            });

            await batch.commit();

            // Rebuild public summary for the target user
            await rebuildPublicVerificationSummary(targetUid);

            await writeAuditLog(
                uid,
                targetUid,
                "role_approved",
                "admin_approval",
                null,
                { role, scope, orgId },
                orgId
            );

            return { status: "approved" };
        } catch (err) {
            if (err instanceof functions.https.HttpsError) throw err;
            functions.logger.error("[approveRoleVerification] error", { uid, err });
            throw new functions.https.HttpsError(
                "internal",
                "An unexpected error occurred. Please try again."
            );
        }
    }
);

// ─── 7. revokeRoleVerification ────────────────────────────────────────────────

export const revokeRoleVerification = functions.https.onCall( // enforceAppCheck: true — enforced via requireAppAuth context.app guard
    async (
        data: { targetUid?: string; orgId?: string; reason?: string },
        context: functions.https.CallableContext
    ) => {
        const uid = requireAppAuth(context);

        try {
            const { targetUid, orgId, reason } = data || {};

            if (typeof targetUid !== "string" || !targetUid.trim()) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "targetUid is required."
                );
            }
            if (typeof orgId !== "string" || !orgId.trim()) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "orgId is required."
                );
            }
            if (typeof reason !== "string" || !reason.trim()) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "reason is required."
                );
            }

            // Verify caller is org admin
            const memberSnap = await db
                .collection("organizations")
                .doc(orgId)
                .collection("members")
                .doc(uid)
                .get();

            if (
                !memberSnap.exists ||
                (memberSnap.data() as Record<string, unknown>).role !== "admin"
            ) {
                throw new functions.https.HttpsError(
                    "permission-denied",
                    "You must be an organization admin to revoke role verifications."
                );
            }

            const now = admin.firestore.FieldValue.serverTimestamp();
            const batch = db.batch();

            // Update the role record
            batch.set(
                db.collection("organizations").doc(orgId).collection("roles").doc(targetUid),
                {
                    status: "revoked",
                    revokedAt: now,
                    revokedBy: uid,
                    revokeReason: reason,
                    updatedAt: now,
                },
                { merge: true }
            );

            // Update corresponding verificationRequest
            const verificationRequestsSnap = await db
                .collection("users")
                .doc(targetUid)
                .collection("verificationRequests")
                .where("type", "==", "role")
                .where("orgId", "==", orgId)
                .where("status", "==", "approved")
                .get();

            verificationRequestsSnap.docs.forEach((doc) => {
                batch.update(doc.ref, {
                    status: "revoked",
                    updatedAt: now,
                });
            });

            await batch.commit();

            // Rebuild public summary
            await rebuildPublicVerificationSummary(targetUid);

            await writeAuditLog(
                uid,
                targetUid,
                "role_revoked",
                reason,
                null,
                { orgId, revokedBy: uid },
                orgId
            );

            // Analytics: log role revocation server-side
            functions.logger.info("[revokeRoleVerification] role_revoked", {
                actorUid: uid,
                targetUid,
                orgId,
                reason,
            });

            return { status: "revoked" };
        } catch (err) {
            if (err instanceof functions.https.HttpsError) throw err;
            functions.logger.error("[revokeRoleVerification] error", { uid, err });
            throw new functions.https.HttpsError(
                "internal",
                "An unexpected error occurred. Please try again."
            );
        }
    }
);

// ─── 8. requestCreatorVerification ───────────────────────────────────────────

export const requestCreatorVerification = functions.https.onCall( // enforceAppCheck: true — enforced via requireAppAuth context.app guard
    async (data: unknown, context: functions.https.CallableContext) => {
        const uid = requireAppAuth(context);

        try {
            // Rate limit: 1 per day
            await checkRateLimit(uid, "requestCreatorVerification_daily", 1);

            const userSnap = await db.collection("users").doc(uid).get();
            if (!userSnap.exists) {
                throw new functions.https.HttpsError(
                    "not-found",
                    "User account not found."
                );
            }

            const userData = userSnap.data() as Record<string, unknown>;

            // Check identity verification prerequisite
            const privateVerifSnap = await db
                .collection("users")
                .doc(uid)
                .collection("privateVerification")
                .doc("main")
                .get();

            const privateData = privateVerifSnap.exists
                ? (privateVerifSnap.data() as Record<string, unknown>)
                : {};

            if (privateData.identityVerified !== true) {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "Identity verification is required for creator verification."
                );
            }

            // Check safety standing
            const publicSummary = (userData.publicVerificationSummary as Record<string, unknown>) || {};
            const safetyStanding =
                typeof publicSummary.safetyStanding === "string"
                    ? publicSummary.safetyStanding
                    : typeof userData.safetyStanding === "string"
                    ? userData.safetyStanding
                    : "active";

            if (safetyStanding !== "active") {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "Your account is not eligible for creator verification at this time."
                );
            }

            // Check account age > 30 days
            const createdAtMs = toMs(userData.createdAt);
            if (createdAtMs !== null) {
                const ageDays = (Date.now() - createdAtMs) / (1000 * 60 * 60 * 24);
                if (ageDays <= 30) {
                    throw new functions.https.HttpsError(
                        "failed-precondition",
                        "Your account must be at least 30 days old to apply for creator verification."
                    );
                }
            }

            // Check no active severe enforcement
            const moderationActionCount =
                typeof userData.moderationActionCount === "number"
                    ? userData.moderationActionCount
                    : 0;

            if (moderationActionCount > 3) {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "Your account is not eligible for creator verification at this time."
                );
            }

            const requestRef = db
                .collection("users")
                .doc(uid)
                .collection("verificationRequests")
                .doc();

            await requestRef.set({
                type: "creator",
                status: "pending",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            return { requestId: requestRef.id, status: "pending" };
        } catch (err) {
            if (err instanceof functions.https.HttpsError) throw err;
            functions.logger.error("[requestCreatorVerification] error", { uid, err });
            throw new functions.https.HttpsError(
                "internal",
                "An unexpected error occurred. Please try again."
            );
        }
    }
);

// ─── 9. refreshVerificationSummary ───────────────────────────────────────────

export const refreshVerificationSummary = functions.https.onCall( // enforceAppCheck: true — enforced via requireAppAuth context.app guard
    async (
        data: { targetUid?: string },
        context: functions.https.CallableContext
    ) => {
        const callerUid = requireAppAuth(context);

        try {
            let targetUid = callerUid;

            // If targetUid provided, caller must be admin
            if (data?.targetUid && data.targetUid !== callerUid) {
                const isAdmin =
                    context.auth?.token?.admin === true ||
                    context.auth?.token?.get?.("admin", false) === true;

                if (!isAdmin) {
                    throw new functions.https.HttpsError(
                        "permission-denied",
                        "Only admins can refresh another user's verification summary."
                    );
                }
                targetUid = data.targetUid;
            }

            await rebuildPublicVerificationSummary(targetUid);

            return { status: "refreshed", targetUid };
        } catch (err) {
            if (err instanceof functions.https.HttpsError) throw err;
            functions.logger.error("[refreshVerificationSummary] error", {
                callerUid,
                err,
            });
            throw new functions.https.HttpsError(
                "internal",
                "An unexpected error occurred. Please try again."
            );
        }
    }
);

// ─── 10. reportImpersonation ─────────────────────────────────────────────────

export const reportImpersonation = functions.https.onCall( // enforceAppCheck: true — enforced via requireAppAuth context.app guard
    async (
        data: { targetUid?: string; reason?: string; evidenceRefs?: string[] },
        context: functions.https.CallableContext
    ) => {
        const uid = requireAppAuth(context);

        try {
            await checkRateLimit(uid, "reportImpersonation", 3);

            const { targetUid, reason, evidenceRefs } = data || {};

            if (typeof targetUid !== "string" || !targetUid.trim()) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "targetUid is required."
                );
            }

            if (targetUid === uid) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "You cannot report yourself for impersonation."
                );
            }

            if (typeof reason !== "string" || !reason.trim()) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "reason is required."
                );
            }

            if (reason.length > 500) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "reason must not exceed 500 characters."
                );
            }

            // Validate evidenceRefs if provided
            const safeEvidenceRefs: string[] = Array.isArray(evidenceRefs)
                ? evidenceRefs
                      .filter((r) => typeof r === "string")
                      .slice(0, 10)
                : [];

            const reportRef = db.collection("impersonationReports").doc();

            const batch = db.batch();

            // Store reporterUid server-side only — never expose in client-readable fields
            batch.set(reportRef, {
                reporterUid: uid, // server-owned; Firestore rules block client reads
                targetUid,
                reason,
                evidenceRefs: safeEvidenceRefs,
                status: "open",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Notify moderation queue
            batch.set(db.collection("moderationQueue").doc(), {
                type: "impersonation_report",
                reportId: reportRef.id,
                targetUid,
                priority: "normal",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            await batch.commit();

            return { reportId: reportRef.id, status: "submitted" };
        } catch (err) {
            if (err instanceof functions.https.HttpsError) throw err;
            functions.logger.error("[reportImpersonation] error", { uid, err });
            throw new functions.https.HttpsError(
                "internal",
                "An unexpected error occurred. Please try again."
            );
        }
    }
);

// ─── Helpers ──────────────────────────────────────────────────────────────────

function toMs(value: unknown): number | null {
    if (value == null) return null;
    if (typeof value === "number") return value;
    if (value instanceof Date) return value.getTime();
    if (
        typeof value === "object" &&
        value !== null &&
        "toMillis" in value &&
        typeof (value as { toMillis: unknown }).toMillis === "function"
    ) {
        return (value as { toMillis: () => number }).toMillis();
    }
    if (
        typeof value === "object" &&
        value !== null &&
        "seconds" in value &&
        typeof (value as { seconds: unknown }).seconds === "number"
    ) {
        return (value as { seconds: number }).seconds * 1000;
    }
    return null;
}
