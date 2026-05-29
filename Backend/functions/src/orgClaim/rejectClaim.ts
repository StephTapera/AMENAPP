/**
 * rejectClaim.ts
 *
 * Callable: rejectClaim  (admin only)
 *
 * Transitions a pending ClaimRequest → rejected.
 * Restores org.claimStatus = 'unclaimed' so it can be claimed again.
 * Removes the user's organizationClaims/{orgId} subcollection record.
 * Sends push notification to the claimer with the rejection reason.
 *
 * Security:
 *  - request.auth.token.admin === true required.
 *  - reviewedBy is always the admin UID from request.auth, never client data.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";
import { RejectClaimResult } from "./orgClaimModels";

const db = getFirestore();

export const rejectClaim = onCall(
    { region: "us-central1", enforceAppCheck: true },
    async (request): Promise<RejectClaimResult> => {
        // ── 1. Auth + admin check ───────────────────────────────────────────
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }
        if (!request.auth.token?.admin) {
            throw new HttpsError("permission-denied", "Admin access required.");
        }
        const adminUid = request.auth.uid;

        // ── 2. Input validation ─────────────────────────────────────────────
        const { orgId, claimId, reason } = request.data as {
            orgId: string;
            claimId: string;
            reason: string;
        };

        if (!orgId || !claimId) {
            throw new HttpsError("invalid-argument", "orgId and claimId are required.");
        }
        if (!reason || typeof reason !== "string" || reason.trim().length < 4) {
            throw new HttpsError("invalid-argument", "A rejection reason is required.");
        }
        const sanitizedReason = reason.trim().slice(0, 500);

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

        // ── 5. Atomic batch ─────────────────────────────────────────────────
        const userClaimRef = db
            .collection("users")
            .doc(claimer)
            .collection("organizationClaims")
            .doc(orgId);

        const batch = db.batch();

        // Restore org to unclaimed so it can be re-claimed
        batch.update(orgRef, {
            claimStatus: "unclaimed",
            claimedBy: null,
            updatedAt: now,
        });

        // Mark claim as rejected
        batch.update(claimRef, {
            status: "rejected",
            reviewedBy: adminUid,
            reviewedAt: now,
            rejectionReason: sanitizedReason,
            updatedAt: now,
        });

        // Remove user subcollection record
        batch.delete(userClaimRef);

        await batch.commit();

        // ── 6. orgOpsRuns audit log ─────────────────────────────────────────
        db.collection("orgOpsRuns").add({
            job: "claim_rejected",
            orgId,
            claimId,
            claimer,
            reviewedBy: adminUid,
            reason: sanitizedReason,
            createdAt: now,
        }).catch((e) => logger.warn("rejectClaim: orgOpsRuns write failed", e));

        // ── 7. Push notification to claimer ─────────────────────────────────
        try {
            const userSnap = await db.collection("users").doc(claimer).get();
            const fcmToken = userSnap.data()?.fcmToken as string | undefined;
            if (fcmToken) {
                await getMessaging().send({
                    token: fcmToken,
                    notification: {
                        title: "Claim Not Approved",
                        body: `Your claim for ${orgName} could not be approved: ${sanitizedReason}`,
                    },
                    data: {
                        orgId,
                        claimId,
                        type: "org_claim_rejected",
                    },
                });
            }
        } catch (e) {
            logger.warn("rejectClaim: FCM send failed", e);
        }

        logger.info("rejectClaim: success", {
            adminUid,
            orgId,
            claimId,
            claimer,
            reason: sanitizedReason,
        });

        return { success: true, claimId };
    }
);
