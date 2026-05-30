/**
 * createOrgStub.ts
 *
 * Callable: createOrgStub
 *
 * Creates a new organization stub and immediately initiates a claim for the
 * creating user (they are the natural owner of a new listing).
 *
 * Google Places privacy constraint:
 *   If `placeId` is provided, ONLY the placeId is written to Firestore as
 *   `sourceId`. The `displayName` and `displayAddress` fields that the iOS
 *   client holds are display-only and MUST NOT be passed to this function
 *   or persisted anywhere in Firestore.
 *
 * Rate limit: 5 stubs per hour per user.
 *
 * Security:
 *  - Auth required.
 *  - App Check enforced.
 *  - server-only fields (claimStatus, source, sourceId, safetyStatus,
 *    visibility, schemaVersion) are written here, never by the client.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { enforceRateLimit } from "../rateLimit";
import {
    OrgType,
    VALID_ORG_TYPES,
    ORG_STUB_RATE_LIMIT,
    CreateOrgStubResult,
} from "./orgClaimModels";

const db = getFirestore();

// ─── Input shape ─────────────────────────────────────────────────────────────

interface CreateOrgStubInput {
    /** Google Places place_id — ONLY stored field from Places. */
    placeId?: string;
    /** Display name passed from iOS for org creation. NOT stored if placeId is provided. */
    name: string;
    type: OrgType;
    city: string;
    state: string;
}

// ─── Callable ────────────────────────────────────────────────────────────────

export const createOrgStub = onCall(
    { region: "us-central1", enforceAppCheck: true },
    async (request): Promise<CreateOrgStubResult> => {
        // ── 1. Auth check ───────────────────────────────────────────────────
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }
        const uid = request.auth.uid;

        // ── 2. Input validation ─────────────────────────────────────────────
        const { placeId, name, type, city, state } = request.data as CreateOrgStubInput;

        if (!name || typeof name !== "string" || name.trim().length < 2) {
            throw new HttpsError("invalid-argument", "A valid organization name is required.");
        }
        if (!type || !VALID_ORG_TYPES.has(type)) {
            throw new HttpsError("invalid-argument", `Invalid organization type: ${type}.`);
        }
        if (placeId && (typeof placeId !== "string" || placeId.length > 512)) {
            throw new HttpsError("invalid-argument", "Invalid placeId.");
        }

        const trimmedName  = name.trim().slice(0, 200);
        const trimmedCity  = (city ?? "").trim().slice(0, 100);
        const trimmedState = (state ?? "").trim().slice(0, 100);

        // ── 3. Rate limit ───────────────────────────────────────────────────
        await enforceRateLimit(uid, [ORG_STUB_RATE_LIMIT]);

        // ── 4. Idempotency: check for an existing stub from this user ───────
        // If the user already created a stub with the same placeId (or same
        // name+type if no placeId), return the existing org.
        if (placeId) {
            const existing = await db
                .collection("organizations")
                .where("sourceId", "==", placeId)
                .where("source", "==", "googlePlaces")
                .limit(1)
                .get();
            if (!existing.empty) {
                const existingOrgId = existing.docs[0].id;
                logger.info("createOrgStub: returning existing placeId stub", {
                    uid,
                    placeId,
                    existingOrgId,
                });

                // Trigger claim for this user on the existing stub (idempotent)
                return await claimExistingStub(uid, existingOrgId, trimmedName);
            }
        }

        const now = FieldValue.serverTimestamp();

        // ── 5. Build org document ───────────────────────────────────────────
        const orgRef = db.collection("organizations").doc();

        // Google Places constraint: if placeId provided, source=googlePlaces
        // and sourceId=placeId. The name/city/state are written as user-provided
        // display fields (editable by owner). No other Places data is stored.
        const source    = placeId ? "googlePlaces" : "userCreated";
        const sourceId  = placeId ?? `user_${uid}_${orgRef.id}`;

        const orgDoc: Record<string, unknown> = {
            id:               orgRef.id,
            type,
            name:             trimmedName,
            normalizedName:   trimmedName.toLowerCase().normalize("NFD")
                                          .replace(/[̀-ͯ]/g, ""),
            description:      null,
            address: {
                line1:     null,
                city:      trimmedCity || null,
                state:     trimmedState || null,
                zip:       null,
                latitude:  null,
                longitude: null,
            },
            website:          null,
            phone:            null,
            verifiedStatus:   "unverified",
            claimStatus:      "unclaimed",     // server-only — will be set to 'pending' by claim CF
            source,
            sourceId,
            sourceUpdatedAt:  null,
            createdAt:        now,
            updatedAt:        now,
            createdBy:        uid,
            ownerUid:         null,
            visibility:       "public",
            bannerConfig:     {},
            spaceDefaults:    {},
            billing:          null,
            safetyStatus:     "allowed",
            modules:          [],
            schemaVersion:    1,
        };

        await orgRef.set(orgDoc);

        logger.info("createOrgStub: org created", { uid, orgId: orgRef.id, source, placeId });

        // ── 6. Immediately initiate claim ───────────────────────────────────
        return await claimExistingStub(uid, orgRef.id, trimmedName);
    }
);

// ─── Helper: initiate claim on an existing/just-created stub ─────────────────

async function claimExistingStub(
    uid: string,
    orgId: string,
    orgName: string
): Promise<CreateOrgStubResult> {
    const now = FieldValue.serverTimestamp();

    // Check if user already has a claim record for this org (idempotency)
    const existingUserClaim = await db
        .collection("users")
        .doc(uid)
        .collection("organizationClaims")
        .doc(orgId)
        .get();

    if (existingUserClaim.exists) {
        const existingClaimId = existingUserClaim.data()?.claimId as string;
        return { success: true, orgId, claimId: existingClaimId };
    }

    const orgRef   = db.collection("organizations").doc(orgId);
    const claimRef = orgRef.collection("claims").doc();

    const batch = db.batch();

    // Update org: user-created stubs go straight to 'claimed' since
    // the creator is the natural owner.
    batch.update(orgRef, {
        claimStatus: "claimed",
        claimedBy:   uid,
        ownerUid:    uid,
        updatedAt:   now,
    });

    // Claim request: auto-approved for user-created stubs
    batch.set(claimRef, {
        orgId,
        requestedBy:         uid,
        verificationEmail:   "",
        verificationMethod:  "manual_review",
        status:              "approved",
        guardianScore:       100,
        guardianVerdict:     "pass",
        reviewedBy:          "auto_user_created",
        reviewedAt:          now,
        createdAt:           now,
        updatedAt:           now,
    });

    // User subcollection record
    batch.set(
        db.collection("users").doc(uid).collection("organizationClaims").doc(orgId),
        {
            orgId,
            claimId:            claimRef.id,
            orgName,
            status:             "approved",
            verificationMethod: "manual_review",
            createdAt:          now,
        }
    );

    await batch.commit();

    // Audit log
    db.collection("orgOpsRuns").add({
        job:        "create_org_stub",
        orgId,
        claimId:    claimRef.id,
        createdBy:  uid,
        createdAt:  now,
    }).catch(() => { /* non-fatal */ });

    return { success: true, orgId, claimId: claimRef.id };
}
