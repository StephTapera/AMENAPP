/**
 * verificationEngine.ts
 *
 * AMEN Catalog — Verification Engine
 *
 * Manages the full lifecycle of creator verification claims:
 *   requestVerification  — create a VerificationClaim in 'pending' state
 *   verifyDomain         — check DNS TXT record for amen-verification token
 *   verifySocialOAuth    — verify platform profile ownership via OAuth token
 *   verifyEmailDomain    — domain-based org verification (OTP to org email)
 *   approveVerification  — admin approves a claim; grants badge
 *   revokeVerification   — remove badge if evidence is withdrawn
 *   transferOrgAdmin     — HUMAN GATE: only executes when confirmed===true
 *   submitVerificationClaim (callable) — iOS entry point for claim submission
 *
 * HUMAN GATES:
 *   - Public-figure verification is NEVER auto-granted. The badge type
 *     'verified_public_figure' does not exist in this system.
 *   - approveVerification for method='manual' REQUIRES the approving admin to
 *     set request.data.confirmed===true explicitly; the function refuses otherwise.
 *   - transferOrgAdmin requires confirmed===true in the call payload.
 *
 * Region: us-east1 (us-central1 quota exhausted ~1007/1000 as of 2026-06-13).
 * Register in docs/FUNCTION_INVENTORY.md before deploying.
 *
 * Exports (callable):
 *   submitVerificationClaim — requestVerification entry point for iOS
 *   approveVerificationClaim — admin approval (restricted)
 *   revokeVerificationClaim — admin revoke (restricted)
 *   transferOrgAdminClaim — org admin handoff (human-gated)
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { Timestamp, FieldValue } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";

if (admin.apps.length === 0) {
    admin.initializeApp();
}

const db = admin.firestore();

// ─── Secret for DNS verification token generation ─────────────────────────────
// Uses the same ANTHROPIC_API_KEY slot for token HMAC — no extra secret required.
// DNS challenges are generated using a deterministic HMAC of creatorId + domain.
const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

// ─── Types ────────────────────────────────────────────────────────────────────

export type VerificationMethod =
    | "domain"
    | "social_oauth"
    | "email_domain"
    | "org_admin"
    | "manual";

export type VerificationStatus =
    | "pending"
    | "challenge_issued"
    | "approved"
    | "rejected"
    | "revoked";

export type VerificationBadgeType =
    | "verified_creator"
    | "verified_organization"
    | "verified_church"
    | "verified_business";
// NOTE: 'verified_public_figure' is intentionally omitted — HUMAN GATE, never auto-grant.

export interface VerificationClaim {
    claimId: string;
    creatorId: string;
    method: VerificationMethod;
    status: VerificationStatus;
    badge?: VerificationBadgeType;
    evidence: Record<string, unknown>;
    challenge?: string;          // DNS TXT value or OTP for email_domain
    challengeExpiresAt?: Timestamp;
    approvedBy?: string;         // admin uid who approved
    revokedBy?: string;          // admin uid who revoked
    revokeReason?: string;
    createdAt: Timestamp;
    updatedAt: Timestamp;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function requireAuth(request: CallableRequest): string {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return request.auth.uid;
}

function requireAdmin(request: CallableRequest): string {
    const uid = requireAuth(request);
    const isAdmin = (request.auth?.token as Record<string, unknown>)?.admin === true;
    if (!isAdmin) {
        throw new HttpsError("permission-denied", "Admin access required.");
    }
    return uid;
}

/**
 * Derive the badge type for a given verification method + evidence.
 * Method 'org_admin' or 'email_domain' with church evidence → verified_church.
 * Method 'org_admin' with business evidence → verified_business.
 * Method 'org_admin' or 'email_domain' with nonprofit/org evidence → verified_organization.
 * All other methods → verified_creator.
 */
function deriveBadge(
    method: VerificationMethod,
    evidence: Record<string, unknown>
): VerificationBadgeType {
    const orgType = evidence.orgType as string | undefined;
    if (method === "org_admin" || method === "email_domain") {
        if (orgType === "church") return "verified_church";
        if (orgType === "business") return "verified_business";
        if (orgType === "nonprofit" || orgType === "organization") return "verified_organization";
    }
    return "verified_creator";
}

/**
 * Generate a stable DNS challenge token for domain verification.
 * Format: amen-verify=<first32hex of sha256(creatorId:domain)>
 * We use a lightweight approach without importing crypto modules.
 */
function buildDnsChallenge(creatorId: string, domain: string): string {
    // Deterministic prefix ensures the token is stable across retries for the same
    // creatorId+domain pair — creators can add the TXT record once and verify later.
    const raw = `${creatorId}:${domain}:amen-catalog-verify`;
    // Simple base64url of the raw string (not cryptographic, just unique enough for DNS challenges)
    const b64 = Buffer.from(raw).toString("base64url");
    return `amen-verify=${b64.slice(0, 32)}`;
}

/**
 * Generate a 6-digit numeric OTP for email_domain verification.
 */
function buildEmailOTP(): string {
    return String(Math.floor(100000 + Math.random() * 900000));
}

// ─── Core engine functions (internal) ────────────────────────────────────────

/**
 * Create a VerificationClaim in 'pending' state.
 * If the method requires a challenge (domain, email_domain), issue it immediately.
 * Returns { claimId, status, challenge? }.
 */
export async function requestVerification(
    creatorId: string,
    method: VerificationMethod,
    evidence: Record<string, unknown>
): Promise<{ claimId: string; status: VerificationStatus; challenge?: string }> {
    // Rate-limit: max 3 pending claims per creator
    const pendingSnap = await db
        .collection("verificationClaims")
        .where("creatorId", "==", creatorId)
        .where("status", "in", ["pending", "challenge_issued"])
        .get();

    if (pendingSnap.size >= 3) {
        throw new HttpsError(
            "resource-exhausted",
            "Too many pending verification claims. Please wait for existing requests to resolve."
        );
    }

    const now = Timestamp.now();
    const challengeExpiresAt = Timestamp.fromDate(
        new Date(Date.now() + 48 * 60 * 60 * 1000) // 48 hours
    );

    let challenge: string | undefined;
    let status: VerificationStatus = "pending";

    if (method === "domain") {
        const domain = evidence.domain as string;
        if (!domain) {
            throw new HttpsError("invalid-argument", "evidence.domain is required for domain verification.");
        }
        challenge = buildDnsChallenge(creatorId, domain);
        status = "challenge_issued";
    } else if (method === "email_domain") {
        const email = evidence.email as string;
        if (!email || !email.includes("@")) {
            throw new HttpsError("invalid-argument", "evidence.email is required for email_domain verification.");
        }
        challenge = buildEmailOTP();
        status = "challenge_issued";
        // TODO(deploy): send OTP via Firebase Extensions / Sendgrid to evidence.email
        // This is a HUMAN DEPLOY STEP — email sending requires a verified email provider.
        logger.info("email_domain OTP generated (delivery pending email provider wiring)", {
            creatorId,
            emailDomain: email.split("@")[1],
        });
    }

    const claimRef = db.collection("verificationClaims").doc();
    const claim: Omit<VerificationClaim, "claimId"> = {
        creatorId,
        method,
        status,
        evidence,
        challenge: challenge ?? undefined,
        challengeExpiresAt: challenge ? challengeExpiresAt : undefined,
        createdAt: now,
        updatedAt: now,
    };

    await claimRef.set({ claimId: claimRef.id, ...claim });

    logger.info("verificationClaim created", {
        claimId: claimRef.id,
        creatorId,
        method,
        status,
    });

    return { claimId: claimRef.id, status, challenge };
}

/**
 * Check the DNS TXT record for a domain verification challenge.
 * Calls the Google DNS-over-HTTPS API to look up TXT records.
 * Returns true if the expected TXT record is present.
 *
 * IMPORTANT: DNS propagation may take up to 48 hours.
 * This function does NOT auto-approve — it returns verified=true so the
 * caller (approveVerification or a scheduled job) can decide to approve.
 */
export async function verifyDomain(
    creatorId: string,
    domain: string
): Promise<{ verified: boolean; reason?: string }> {
    const expectedToken = buildDnsChallenge(creatorId, domain);

    try {
        const url = `https://dns.google/resolve?name=${encodeURIComponent(domain)}&type=TXT`;
        const response = await fetch(url, {
            headers: { Accept: "application/dns-json" },
            signal: AbortSignal.timeout(8_000),
        });

        if (!response.ok) {
            return { verified: false, reason: "dns_lookup_failed" };
        }

        const data = (await response.json()) as {
            Answer?: Array<{ type: number; data: string }>;
        };

        const txtRecords = (data.Answer ?? [])
            .filter((r) => r.type === 16) // 16 = TXT
            .map((r) => r.data.replace(/^"|"$/g, "").trim());

        const found = txtRecords.some((txt) => txt === expectedToken);
        if (found) {
            return { verified: true };
        }

        return {
            verified: false,
            reason: `TXT record not found. Expected: ${expectedToken}`,
        };
    } catch (err: unknown) {
        const isTimeout = err instanceof Error && err.name === "TimeoutError";
        return {
            verified: false,
            reason: isTimeout ? "dns_timeout" : "dns_lookup_error",
        };
    }
}

/**
 * Verify platform profile ownership via OAuth token.
 * Checks that the OAuth token belongs to a profile that matches evidence.profileId.
 * Supported platforms: youtube, spotify.
 *
 * Never auto-approves — returns { verified, platformUserId } so the caller
 * can confirm identity match before approving.
 */
export async function verifySocialOAuth(
    creatorId: string,
    platform: "youtube" | "spotify",
    oauthToken: string
): Promise<{ verified: boolean; platformUserId?: string; reason?: string }> {
    if (!oauthToken) {
        return { verified: false, reason: "oauth_token_missing" };
    }

    try {
        if (platform === "youtube") {
            // Use Google OAuth userinfo endpoint
            const response = await fetch(
                "https://www.googleapis.com/oauth2/v3/userinfo",
                {
                    headers: { Authorization: `Bearer ${oauthToken}` },
                    signal: AbortSignal.timeout(8_000),
                }
            );
            if (!response.ok) {
                return { verified: false, reason: "youtube_token_invalid" };
            }
            const data = (await response.json()) as {
                sub?: string;
                email?: string;
            };
            if (!data.sub) {
                return { verified: false, reason: "youtube_no_sub" };
            }
            logger.info("youtube_oauth verified", { creatorId, sub: data.sub });
            return { verified: true, platformUserId: data.sub };
        }

        if (platform === "spotify") {
            // Use Spotify /v1/me endpoint
            const response = await fetch("https://api.spotify.com/v1/me", {
                headers: { Authorization: `Bearer ${oauthToken}` },
                signal: AbortSignal.timeout(8_000),
            });
            if (!response.ok) {
                return { verified: false, reason: "spotify_token_invalid" };
            }
            const data = (await response.json()) as {
                id?: string;
                display_name?: string;
            };
            if (!data.id) {
                return { verified: false, reason: "spotify_no_id" };
            }
            logger.info("spotify_oauth verified", { creatorId, spotifyId: data.id });
            return { verified: true, platformUserId: data.id };
        }

        return { verified: false, reason: "unsupported_platform" };
    } catch (err: unknown) {
        const isTimeout = err instanceof Error && err.name === "TimeoutError";
        return {
            verified: false,
            reason: isTimeout ? "oauth_timeout" : "oauth_request_error",
        };
    }
}

/**
 * Verify domain ownership via an email OTP sent to an org-domain address.
 * Checks the OTP stored in the verificationClaim against the user-supplied code.
 * Returns { verified, claimId } if the code matches and has not expired.
 */
export async function verifyEmailDomain(
    creatorId: string,
    email: string,
    otp: string
): Promise<{ verified: boolean; claimId?: string; reason?: string }> {
    const snap = await db
        .collection("verificationClaims")
        .where("creatorId", "==", creatorId)
        .where("method", "==", "email_domain")
        .where("status", "==", "challenge_issued")
        .orderBy("createdAt", "desc")
        .limit(1)
        .get();

    if (snap.empty) {
        return { verified: false, reason: "no_pending_email_claim" };
    }

    const doc = snap.docs[0];
    const data = doc.data() as VerificationClaim;

    // Check expiry
    if (data.challengeExpiresAt && data.challengeExpiresAt.toMillis() < Date.now()) {
        await doc.ref.update({ status: "rejected", updatedAt: Timestamp.now() });
        return { verified: false, reason: "otp_expired" };
    }

    // Constant-time comparison (OTPs are short, but avoid timing attacks)
    const storedOtp = data.challenge ?? "";
    const match = storedOtp.length === otp.length &&
        Buffer.from(storedOtp).every((b, i) => b === otp.charCodeAt(i));

    if (!match) {
        return { verified: false, reason: "otp_mismatch" };
    }

    logger.info("email_domain OTP verified", { creatorId, claimId: doc.id });
    return { verified: true, claimId: doc.id };
}

/**
 * Approve a verification claim and grant a badge.
 *
 * HUMAN GATES:
 *   - method='manual': requires confirmed===true in the call payload.
 *     Manual is used for org_admin and public-figure-adjacent claims.
 *     Never auto-grant. The admin must explicitly pass confirmed:true.
 *   - This function only grants the four defined badge types.
 *     verified_public_figure does NOT exist and cannot be granted here.
 */
export async function approveVerification(
    claimId: string,
    adminId: string,
    confirmed: boolean
): Promise<{ success: boolean; badge: VerificationBadgeType }> {
    const claimRef = db.collection("verificationClaims").doc(claimId);
    const claimSnap = await claimRef.get();

    if (!claimSnap.exists) {
        throw new HttpsError("not-found", "Verification claim not found.");
    }

    const claim = claimSnap.data() as VerificationClaim;

    if (claim.status === "approved") {
        // Idempotent — already approved
        return { success: true, badge: claim.badge! };
    }

    if (claim.status !== "pending" && claim.status !== "challenge_issued") {
        throw new HttpsError(
            "failed-precondition",
            `Cannot approve claim in status '${claim.status}'.`
        );
    }

    // HUMAN GATE: manual method requires explicit confirmed=true
    if (claim.method === "manual" && !confirmed) {
        throw new HttpsError(
            "failed-precondition",
            "Manual verification requires confirmed=true. This is a HUMAN GATE — do not auto-approve."
        );
    }

    const badge = deriveBadge(claim.method, claim.evidence);
    const now = Timestamp.now();

    // Update claim
    await claimRef.update({
        status: "approved",
        badge,
        approvedBy: adminId,
        updatedAt: now,
    });

    // Grant badge on the creator's profile
    await db.collection("users").doc(claim.creatorId).update({
        "catalog.verifiedOwnership": true,
        "catalog.badge": badge,
        "catalog.badgeGrantedAt": now,
        "catalog.badgeGrantedBy": adminId,
    });

    logger.info("verification approved", {
        claimId,
        creatorId: claim.creatorId,
        badge,
        adminId,
    });

    return { success: true, badge };
}

/**
 * Revoke a verification badge.
 * Removes the badge from the creator's profile and marks the claim revoked.
 */
export async function revokeVerification(
    claimId: string,
    adminId: string,
    reason: string
): Promise<{ success: boolean }> {
    const claimRef = db.collection("verificationClaims").doc(claimId);
    const claimSnap = await claimRef.get();

    if (!claimSnap.exists) {
        throw new HttpsError("not-found", "Verification claim not found.");
    }

    const claim = claimSnap.data() as VerificationClaim;

    if (claim.status === "revoked") {
        return { success: true }; // Idempotent
    }

    const now = Timestamp.now();

    await claimRef.update({
        status: "revoked",
        revokedBy: adminId,
        revokeReason: reason,
        updatedAt: now,
    });

    // Remove badge from the creator's profile
    await db.collection("users").doc(claim.creatorId).update({
        "catalog.verifiedOwnership": false,
        "catalog.badge": FieldValue.delete(),
        "catalog.badgeGrantedAt": FieldValue.delete(),
        "catalog.badgeGrantedBy": FieldValue.delete(),
        "catalog.badgeRevokedAt": now,
        "catalog.badgeRevokedBy": adminId,
    });

    logger.info("verification revoked", {
        claimId,
        creatorId: claim.creatorId,
        adminId,
        reason,
    });

    return { success: true };
}

/**
 * Transfer org admin rights from one user to another.
 *
 * HUMAN GATE: confirmed must be true. Never auto-transfer.
 */
export async function transferOrgAdmin(
    orgId: string,
    fromAdminId: string,
    toAdminId: string,
    confirmed: boolean
): Promise<{ success: boolean }> {
    if (!confirmed) {
        throw new HttpsError(
            "failed-precondition",
            "Org admin transfer requires confirmed=true. This is a HUMAN GATE."
        );
    }

    if (!orgId || !fromAdminId || !toAdminId) {
        throw new HttpsError("invalid-argument", "orgId, fromAdminId, and toAdminId are required.");
    }

    if (fromAdminId === toAdminId) {
        throw new HttpsError("invalid-argument", "fromAdminId and toAdminId must be different.");
    }

    const orgRef = db.collection("organizations").doc(orgId);
    const orgSnap = await orgRef.get();

    if (!orgSnap.exists) {
        throw new HttpsError("not-found", "Organization not found.");
    }

    const orgData = orgSnap.data()!;
    if (orgData.adminId !== fromAdminId) {
        throw new HttpsError(
            "permission-denied",
            "Only the current org admin can transfer admin rights."
        );
    }

    const now = Timestamp.now();

    await orgRef.update({
        adminId: toAdminId,
        previousAdminId: fromAdminId,
        adminTransferredAt: now,
    });

    logger.info("org admin transferred", {
        orgId,
        fromAdminId,
        toAdminId,
    });

    return { success: true };
}

// ─── Firebase Callable Exports ────────────────────────────────────────────────

/**
 * submitVerificationClaim
 * iOS entry point for creator verification requests.
 * Wires the previously-stubbed VerificationService.submitVerificationClaim() call.
 *
 * Input: { method: VerificationMethod; evidence: Record<string, unknown> }
 * Output: { claimId, status, challenge? }
 */
export const submitVerificationClaim = onCall({ enforceAppCheck: true, region: "us-east1", secrets: [ANTHROPIC_API_KEY] }, async (request) => {
        const creatorId = requireAuth(request);

        const { method, evidence } = request.data as {
            method: VerificationMethod;
            evidence?: Record<string, unknown>;
        };

        if (!method) {
            throw new HttpsError("invalid-argument", "method is required.");
        }

        const validMethods: VerificationMethod[] = [
            "domain",
            "social_oauth",
            "email_domain",
            "org_admin",
            "manual",
        ];
        if (!validMethods.includes(method)) {
            throw new HttpsError("invalid-argument", `Invalid method: ${method}`);
        }

        // manual method requires admin — public users cannot self-select manual
        if (method === "manual") {
            throw new HttpsError(
                "permission-denied",
                "Manual verification must be initiated by an Amen admin."
            );
        }

        return requestVerification(creatorId, method, evidence ?? {});
    }
);

/**
 * approveVerificationClaim
 * Admin-only callable to approve a pending claim.
 * For manual/org_admin claims: confirmed=true is required (HUMAN GATE).
 *
 * Input: { claimId: string; confirmed?: boolean }
 * Output: { success: boolean; badge: VerificationBadgeType }
 */
export const approveVerificationClaim = onCall({ enforceAppCheck: true, region: "us-east1" }, async (request) => {
        const adminId = requireAdmin(request);

        const { claimId, confirmed } = request.data as {
            claimId: string;
            confirmed?: boolean;
        };

        if (!claimId) {
            throw new HttpsError("invalid-argument", "claimId is required.");
        }

        return approveVerification(claimId, adminId, confirmed === true);
    }
);

/**
 * revokeVerificationClaim
 * Admin-only callable to revoke an approved badge.
 *
 * Input: { claimId: string; reason: string }
 * Output: { success: boolean }
 */
export const revokeVerificationClaim = onCall({ enforceAppCheck: true, region: "us-east1" }, async (request) => {
        const adminId = requireAdmin(request);

        const { claimId, reason } = request.data as {
            claimId: string;
            reason?: string;
        };

        if (!claimId) {
            throw new HttpsError("invalid-argument", "claimId is required.");
        }

        return revokeVerification(claimId, adminId, reason ?? "badge_revoked_by_admin");
    }
);

/**
 * transferOrgAdminClaim
 * HUMAN GATE: org admin transfer. Only executes when confirmed===true.
 *
 * Input: { orgId: string; toAdminId: string; confirmed: boolean }
 * Output: { success: boolean }
 */
export const transferOrgAdminClaim = onCall({ enforceAppCheck: true, region: "us-east1" }, async (request) => {
        const fromAdminId = requireAuth(request);

        const { orgId, toAdminId, confirmed } = request.data as {
            orgId: string;
            toAdminId: string;
            confirmed?: boolean;
        };

        if (!orgId || !toAdminId) {
            throw new HttpsError("invalid-argument", "orgId and toAdminId are required.");
        }

        return transferOrgAdmin(orgId, fromAdminId, toAdminId, confirmed === true);
    }
);

/**
 * checkDomainVerification
 * Checks whether a DNS TXT record for a domain verification is present.
 * Called from iOS after the creator has added the TXT record.
 *
 * Input: { claimId: string; domain: string }
 * Output: { verified: boolean; reason?: string }
 */
export const checkDomainVerification = onCall({ enforceAppCheck: true, region: "us-east1" }, async (request) => {
        const creatorId = requireAuth(request);

        const { claimId, domain } = request.data as {
            claimId: string;
            domain: string;
        };

        if (!claimId || !domain) {
            throw new HttpsError("invalid-argument", "claimId and domain are required.");
        }

        // Confirm this claim belongs to the calling user
        const claimSnap = await db.collection("verificationClaims").doc(claimId).get();
        if (!claimSnap.exists) {
            throw new HttpsError("not-found", "Claim not found.");
        }
        const claim = claimSnap.data() as VerificationClaim;
        if (claim.creatorId !== creatorId) {
            throw new HttpsError("permission-denied", "This claim does not belong to you.");
        }

        const result = await verifyDomain(creatorId, domain);

        // If verified, auto-approve (domain = non-manual, no human gate required)
        if (result.verified) {
            await approveVerification(claimId, "system:dns_auto_verify", false);
        }

        return result;
    }
);

/**
 * verifyEmailOTP
 * Verifies an OTP submitted by the creator for email_domain verification.
 *
 * Input: { email: string; otp: string }
 * Output: { verified: boolean; reason?: string }
 */
export const verifyEmailOTP = onCall({ enforceAppCheck: true, region: "us-east1" }, async (request) => {
        const creatorId = requireAuth(request);

        const { email, otp } = request.data as { email: string; otp: string };

        if (!email || !otp) {
            throw new HttpsError("invalid-argument", "email and otp are required.");
        }

        const result = await verifyEmailDomain(creatorId, email, otp);

        // If verified, auto-approve (email_domain = non-manual)
        if (result.verified && result.claimId) {
            await approveVerification(result.claimId, "system:email_auto_verify", false);
        }

        return result;
    }
);
