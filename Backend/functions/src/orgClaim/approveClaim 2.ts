/**
 * approveClaim.ts
 *
 * Callable: approveClaim  (admin only)
 *
 * Transitions a pending ClaimRequest → approved.
 * Sets org.claimStatus = 'verified', org.ownerUid = claimer.
 * Sends push notification to the claimer.
 * Triggers Algolia index update via `algolia_syncOrg` callable.
 *
 * Security:
 *  - request.auth.token.admin === true required.
 *  - ClaimRequest must be in 'pending' state.
 *  - reviewedBy is always the admin UID from request.auth, never client data.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";
import { ApproveClaimResult } from "./orgClaimModels";

const db = getFirestore();

export const approveClaim = onCall(
    { region: "us-central1", enforceAppCheck: true },
    async (request): Promise<ApproveClaimResult> => {
        // ── 1. Auth + admin check ───────────────────────────────────────────
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }
        if (!request.auth.token?.admin) {
            throw new HttpsError("permission-denied", "Admin access required.");
        }
        const adminUid = request.auth.uid;

        // ── 2. Input validation ─────────────────────────────────────────────
        const { orgId, claimId, notes } = request.data as {
            orgId: string;
            claimId: string;
            notes?: string;
        };

        if (!orgId || !claimId) {
            throw new HttpsError("invalid-argument", "orgId and claimId are required.");
        }

        // ── 3. Read claim request ───────────────────────────────────────────
        const claimRef = db
            .collection("organizations")
            .doc(orgId)
            .collection("claims")
            .doc(claimId);

        const claimSnap = await claimRef.get();
        if (!claimSnap.exists) {
            throw new HttpsError("not-found", "Claim request not found.");
        }
        const claimData = claimSnap.data()!;

        if (claimData.status !== "pending") {
            throw new HttpsError(
                "failed-precondition",
                `Claim is not in pending state (current: ${claimData.status}).`
            );
        }

        const claimer: string = claimData.requestedBy;
        if (!claimer) {
            throw new HttpsError("internal", "Claim request is missing requestedBy.");
        }

        // ── 4. Read org name for notification ───────────────────────────────
        const orgRef = db.collection("organizations").doc(orgId);
        const orgSnap = await orgRef.get();
        if (!orgSnap.exists) {
            throw new HttpsError("not-found", "Organization not found.");
        }
        const orgName: string = orgSnap.data()?.name ?? "Organization";

        const now = FieldValue.serverTimestamp();

        // ── 5. Atomic batch: org update + claim update + user record update ─
        const userClaimRef = db
            .collection("users")
            .doc(claimer)
            .collection("organizationClaims")
            .doc(orgId);

        const batch = db.batch();

        batch.update(orgRef, {
            claimStatus: "verified",
            claimedBy: claimer,
            ownerUid: claimer,
            updatedAt: now,
        });

        batch.update(claimRef, {
            status: "approved",
            reviewedBy: adminUid,
            reviewedAt: now,
            updatedAt: now,
            ...(notes ? { adminNotes: notes } : {}),
        });

        batch.update(userClaimRef, {
            status: "approved",
        });

        await batch.commit();

        // ── 6. orgOpsRuns audit log ─────────────────────────────────────────
        db.collection("orgOpsRuns").add({
            job: "claim_approved",
            orgId,
            claimId,
            claimer,
            reviewedBy: adminUid,
            createdAt: now,
        }).catch((e) => logger.warn("approveClaim: orgOpsRuns write failed", e));

        // ── 7. Push notification to claimer ─────────────────────────────────
        try {
            const userSnap = await db.collection("users").doc(claimer).get();
            const fcmToken = userSnap.data()?.fcmToken as string | undefined;
            if (fcmToken) {
                await getMessaging().send({
                    token: fcmToken,
                    notification: {
                        title: "Claim Approved!",
                        body: `Your claim for ${orgName} has been approved. You can now manage this profile.`,
                    },
                    data: {
                        orgId,
                        claimId,
                        type: "org_claim_approved",
                    },
                });
            }
        } catch (e) {
            logger.warn("approveClaim: FCM send failed", e);
        }

        // ── 8. Algolia sync ─────────────────────────────────────────────────
        // Write a sync request to algoliaOrgSyncQueue so the Algolia org index
        // stays current. The queue document is picked up by the algoliaSync trigger.
        db.collection("algoliaOrgSyncQueue").add({
            orgId,
            action: "upsert",
            triggeredBy: "approveClaim",
            createdAt: now,
        }).catch((e) => logger.warn("approveClaim: algoliaOrgSyncQueue write failed", e));

        logger.info("approveClaim: success", { adminUid, orgId, claimId, claimer });

        return { success: true, orgId, claimId };
    }
);
