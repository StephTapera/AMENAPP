/**
 * crisisBulletins.ts
 * AMEN — Global Resilience: Crisis Bulletin Management
 *
 * Firebase Gen-2 callable Cloud Functions (region: us-east1):
 *
 *   publishCrisisBulletin  — Org-gated write to /crisisBulletins/{newId},
 *                            FCM topic push to "crisis_bulletins", and
 *                            immutable /safetyAuditLog entry.
 *   expireCrisisBulletin   — Org-owned or admin. Sets expiresAt = now on an
 *                            existing bulletin, effectively removing it from
 *                            active client queries.
 *
 * Org verification requirement for publishCrisisBulletin:
 *   The calling org must have verificationTier in
 *   ["ministry", "charityDonation", "churchLinked"] sourced from either:
 *     1. /orgVerificationRequests/{orgId}.verificationTier (preferred), OR
 *     2. /trustProfiles/{orgId}.identityTier (fallback).
 *
 * Auth: every callable requires a valid Firebase Auth token (uid in request.auth).
 * App Check: enforced via { enforceAppCheck: true }.
 *
 * Firestore paths:
 *   /crisisBulletins/{bulletinId}          — CrisisBulletin documents
 *   /orgVerificationRequests/{orgId}        — Org verification records
 *   /trustProfiles/{orgId}                  — Trust profile fallback
 *   /safetyAuditLog/{newId}                 — Immutable audit entries
 *
 * FCM topic: "crisis_bulletins"
 */

import * as admin from "firebase-admin";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import type { BulletinSeverity, VerificationTier } from "./contracts";

// ─── Constants ────────────────────────────────────────────────────────────────

const REGION = "us-east1";

/** FCM topic all crisis bulletin subscribers are subscribed to. */
const CRISIS_BULLETINS_TOPIC = "crisis_bulletins";

/** Org verification tiers that are permitted to publish crisis bulletins. */
const AUTHORIZED_ORG_TIERS: ReadonlyArray<VerificationTier> = [
    "ministry",
    "charityDonation",
    "churchLinked",
];

/** Maximum length for bulletin title. */
const TITLE_MAX_LEN = 200;

/** Maximum length for bulletin body text. */
const BODY_MAX_LEN = 2000;

/** Maximum length for regionScope (ISO 3166-1 alpha-2 or "global"). */
const REGION_SCOPE_MAX_LEN = 16;

// ─── Input validation helpers ──────────────────────────────────────────────────

function requireNonEmptyString(value: unknown, field: string, maxLen: number): string {
    if (typeof value !== "string" || !value.trim()) {
        throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
    }
    if (value.length > maxLen) {
        throw new HttpsError(
            "invalid-argument",
            `${field} exceeds maximum length of ${maxLen} characters.`
        );
    }
    return value.trim();
}

function requireAuth(auth: { uid: string } | undefined | null): string {
    if (!auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return auth.uid;
}

function isValidSeverity(value: string): value is BulletinSeverity {
    return ["info", "warning", "critical", "emergency"].includes(value);
}

// ─── Org verification helper ───────────────────────────────────────────────────

/**
 * Checks whether orgId holds an authorized verification tier.
 *
 * Reads /orgVerificationRequests/{orgId}.verificationTier first; on miss or
 * absence falls back to /trustProfiles/{orgId}.identityTier.
 *
 * Returns the resolved tier string if authorized, throws permission-denied otherwise.
 */
async function requireAuthorizedOrgTier(
    db: FirebaseFirestore.Firestore,
    orgId: string,
    callerUid: string
): Promise<VerificationTier> {
    let resolvedTier: VerificationTier | null = null;

    // ── 1. Primary: /orgVerificationRequests/{orgId} ──────────────────────────
    try {
        const orgVerifSnap = await db
            .collection("orgVerificationRequests")
            .doc(orgId)
            .get();

        if (orgVerifSnap.exists) {
            const data = orgVerifSnap.data() ?? {};
            const tier = data.verificationTier as string | undefined;
            if (tier && AUTHORIZED_ORG_TIERS.includes(tier as VerificationTier)) {
                resolvedTier = tier as VerificationTier;
            }
        }
    } catch (err) {
        logger.warn(
            "[crisisBulletins] Could not read orgVerificationRequests",
            { orgId },
            err
        );
    }

    // ── 2. Fallback: /trustProfiles/{orgId} ───────────────────────────────────
    if (!resolvedTier) {
        try {
            const trustSnap = await db.collection("trustProfiles").doc(orgId).get();
            if (trustSnap.exists) {
                const data = trustSnap.data() ?? {};
                const tier = data.identityTier as string | undefined;
                if (tier && AUTHORIZED_ORG_TIERS.includes(tier as VerificationTier)) {
                    resolvedTier = tier as VerificationTier;
                }
            }
        } catch (err) {
            logger.warn(
                "[crisisBulletins] Could not read trustProfiles fallback",
                { orgId },
                err
        );
        }
    }

    if (!resolvedTier) {
        logger.warn("[crisisBulletins] Org not authorized to publish bulletin", {
            orgId,
            callerUid,
        });
        throw new HttpsError(
            "permission-denied",
            "Organization does not hold a verification tier that permits publishing crisis bulletins. " +
            "Required: ministry, charityDonation, or churchLinked."
        );
    }

    return resolvedTier;
}

// ─── publishCrisisBulletin ────────────────────────────────────────────────────

interface PublishCrisisBulletinRequest {
    orgId: unknown;
    title: unknown;
    bodyText: unknown;
    severity: unknown;
    regionScope: unknown;
    /** ISO 8601 string or Unix epoch milliseconds */
    expiresAt: unknown;
    lowDataOnly?: unknown;
}

interface PublishCrisisBulletinResponse {
    bulletinId: string;
}

/**
 * publishCrisisBulletin
 *
 * 1. Validates caller auth + input fields.
 * 2. Verifies the org has an authorized verificationTier.
 * 3. Writes the bulletin document to /crisisBulletins/{newId}.
 * 4. Sends an FCM topic message to "crisis_bulletins" (non-blocking on failure).
 * 5. Writes an immutable entry to /safetyAuditLog.
 * 6. Returns { bulletinId }.
 */
export const publishCrisisBulletin = onCall<
    PublishCrisisBulletinRequest,
    Promise<PublishCrisisBulletinResponse>
>(
    { enforceAppCheck: true, region: REGION },
    async (request): Promise<PublishCrisisBulletinResponse> => {
        const callerUid = requireAuth(request.auth);
        const data = request.data as PublishCrisisBulletinRequest;

        // ── 1. Validate inputs ─────────────────────────────────────────────────
        const orgId       = requireNonEmptyString(data.orgId,       "orgId",       256);
        const title       = requireNonEmptyString(data.title,       "title",       TITLE_MAX_LEN);
        const bodyText    = requireNonEmptyString(data.bodyText,     "bodyText",    BODY_MAX_LEN);
        const regionScope = requireNonEmptyString(data.regionScope,  "regionScope", REGION_SCOPE_MAX_LEN);

        const rawSeverity = requireNonEmptyString(data.severity, "severity", 20);
        if (!isValidSeverity(rawSeverity)) {
            throw new HttpsError(
                "invalid-argument",
                `severity must be one of: info, warning, critical, emergency. Received: "${rawSeverity}".`
            );
        }
        const severity = rawSeverity as BulletinSeverity;

        // Parse expiresAt — accept ISO 8601 string or numeric epoch ms.
        let expiresAtMs: number;
        if (typeof data.expiresAt === "number") {
            expiresAtMs = data.expiresAt;
        } else if (typeof data.expiresAt === "string") {
            expiresAtMs = Date.parse(data.expiresAt);
            if (isNaN(expiresAtMs)) {
                throw new HttpsError(
                    "invalid-argument",
                    "expiresAt must be a valid ISO 8601 date string or Unix epoch milliseconds."
                );
            }
        } else {
            throw new HttpsError(
                "invalid-argument",
                "expiresAt must be a valid ISO 8601 date string or Unix epoch milliseconds."
            );
        }

        const expiresAtTimestamp = Timestamp.fromMillis(expiresAtMs);

        // Prevent publishing bulletins that are already expired.
        if (expiresAtMs <= Date.now()) {
            throw new HttpsError(
                "invalid-argument",
                "expiresAt must be in the future."
            );
        }

        const lowDataOnly: boolean =
            typeof data.lowDataOnly === "boolean" ? data.lowDataOnly : false;

        const db = getFirestore();

        // ── 2. Verify org tier ─────────────────────────────────────────────────
        const resolvedTier = await requireAuthorizedOrgTier(db, orgId, callerUid);

        // ── 3. Write bulletin document ─────────────────────────────────────────
        const bulletinRef = db.collection("crisisBulletins").doc();
        const bulletinId = bulletinRef.id;

        await bulletinRef.set({
            title,
            bodyText,
            severity,
            regionScope,
            expiresAt:        expiresAtTimestamp,
            lowDataOnly,
            publishedByOrgId: orgId,
            publishedByUid:   callerUid,
            createdAt:        FieldValue.serverTimestamp(),
        });

        logger.info("[publishCrisisBulletin] Bulletin written", {
            bulletinId,
            orgId,
            severity,
            regionScope,
        });

        // ── 4. FCM topic push (non-blocking — failure must not fail callable) ──
        try {
            const message: admin.messaging.Message = {
                topic: CRISIS_BULLETINS_TOPIC,
                notification: {
                    title: "Crisis Bulletin",
                    body:  title,
                },
                data: {
                    bulletinId,
                    severity,
                    regionScope,
                },
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                            "content-available": 1,
                            "mutable-content": 1,
                        },
                    },
                },
            };
            await admin.messaging().send(message);
            logger.info("[publishCrisisBulletin] FCM topic push sent", { bulletinId });
        } catch (fcmErr) {
            logger.error(
                "[publishCrisisBulletin] FCM topic push failed (non-fatal)",
                { bulletinId },
                fcmErr
            );
        }

        // ── 5. Write immutable audit log ───────────────────────────────────────
        await db.collection("safetyAuditLog").doc().set({
            event:           "crisis_bulletin_published",
            bulletinId,
            orgId,
            callerUid,
            severity,
            regionScope,
            resolvedOrgTier: resolvedTier,
            timestamp:       FieldValue.serverTimestamp(),
        });

        // ── 6. Return bulletinId ───────────────────────────────────────────────
        return { bulletinId };
    }
);

// ─── expireCrisisBulletin ─────────────────────────────────────────────────────

interface ExpireCrisisBulletinRequest {
    bulletinId: unknown;
}

interface ExpireCrisisBulletinResponse {
    bulletinId: string;
    expiredAt: string;
}

/**
 * expireCrisisBulletin
 *
 * Sets expiresAt = now on an existing bulletin, effectively removing it from
 * active client Firestore queries (which filter expiresAt > now).
 *
 * Caller must be:
 *   - The org that published the bulletin (publishedByOrgId == callerUid or
 *     callerUid is a member of the publishing org), OR
 *   - A platform admin (users/{uid}.isAdmin === true).
 *
 * Writes an immutable /safetyAuditLog entry.
 */
export const expireCrisisBulletin = onCall<
    ExpireCrisisBulletinRequest,
    Promise<ExpireCrisisBulletinResponse>
>(
    { enforceAppCheck: true, region: REGION },
    async (request): Promise<ExpireCrisisBulletinResponse> => {
        const callerUid = requireAuth(request.auth);
        const data = request.data as ExpireCrisisBulletinRequest;

        const bulletinId = requireNonEmptyString(data.bulletinId, "bulletinId", 256);

        const db = getFirestore();

        // ── 1. Read the existing bulletin ──────────────────────────────────────
        const bulletinRef = db.collection("crisisBulletins").doc(bulletinId);
        const bulletinSnap = await bulletinRef.get();

        if (!bulletinSnap.exists) {
            throw new HttpsError("not-found", `Crisis bulletin "${bulletinId}" does not exist.`);
        }

        const bulletinData = bulletinSnap.data() ?? {};
        const publishedByOrgId: string =
            typeof bulletinData.publishedByOrgId === "string"
                ? bulletinData.publishedByOrgId
                : "";
        const publishedByUid: string =
            typeof bulletinData.publishedByUid === "string"
                ? bulletinData.publishedByUid
                : "";

        // ── 2. Authorization check ─────────────────────────────────────────────
        // Allow: direct publisher uid, org owner check, or platform admin.
        let isAuthorized = callerUid === publishedByUid;

        // Check platform admin flag.
        if (!isAuthorized) {
            try {
                const userSnap = await db.collection("users").doc(callerUid).get();
                if (userSnap.exists) {
                    const userData = userSnap.data() ?? {};
                    isAuthorized = userData.isAdmin === true;
                }
            } catch (err) {
                logger.warn(
                    "[expireCrisisBulletin] Could not read user admin flag",
                    { callerUid },
                    err
                );
            }
        }

        // Check org membership (caller is a member of the publishing org).
        if (!isAuthorized && publishedByOrgId) {
            try {
                const memberSnap = await db
                    .collection("orgVerificationRequests")
                    .doc(publishedByOrgId)
                    .collection("members")
                    .doc(callerUid)
                    .get();
                isAuthorized = memberSnap.exists;
            } catch (err) {
                logger.warn(
                    "[expireCrisisBulletin] Could not read org membership",
                    { callerUid, publishedByOrgId },
                    err
                );
            }
        }

        if (!isAuthorized) {
            throw new HttpsError(
                "permission-denied",
                "You do not have permission to expire this bulletin."
            );
        }

        // ── 3. Set expiresAt = now ─────────────────────────────────────────────
        const expiredAtTimestamp = Timestamp.now();
        await bulletinRef.update({ expiresAt: expiredAtTimestamp });

        logger.info("[expireCrisisBulletin] Bulletin expired", {
            bulletinId,
            callerUid,
            publishedByOrgId,
        });

        // ── 4. Write immutable audit log ───────────────────────────────────────
        await db.collection("safetyAuditLog").doc().set({
            event:           "crisis_bulletin_expired",
            bulletinId,
            callerUid,
            publishedByOrgId,
            expiredAt:       expiredAtTimestamp,
            timestamp:       FieldValue.serverTimestamp(),
        });

        return {
            bulletinId,
            expiredAt: expiredAtTimestamp.toDate().toISOString(),
        };
    }
);
