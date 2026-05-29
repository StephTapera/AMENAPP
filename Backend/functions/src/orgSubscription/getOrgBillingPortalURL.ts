/**
 * getOrgBillingPortalURL
 *
 * Callable Cloud Function that creates a Stripe Customer Portal session
 * for an org's billing management.
 *
 * Authorization:
 *   - Caller must be the org owner (org.claimedBy / org.ownerUid).
 *   - Org must have a stripeCustomerId (i.e. must have subscribed at least once).
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import Stripe = require("stripe");
import { orgBillingRef } from "./orgSubscriptionModels";

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");

interface PortalInput {
    orgId: string;
}

export const getOrgBillingPortalURL = onCall(
    {
        enforceAppCheck: true,
        region: "us-central1",
        secrets: [stripeSecretKey],
    },
    async (request) => {
        // ── 1. Auth ────────────────────────────────────────────────────────────
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;

        // ── 2. Input validation ────────────────────────────────────────────────
        const { orgId } = (request.data ?? {}) as Partial<PortalInput>;

        if (typeof orgId !== "string" || !orgId.trim()) {
            throw new HttpsError("invalid-argument", "orgId is required.");
        }

        const key = stripeSecretKey.value();
        if (!key) {
            logger.error("[getOrgBillingPortalURL] STRIPE_SECRET_KEY not configured");
            throw new HttpsError("internal", "Payment service not configured.");
        }

        const db = admin.firestore();

        // ── 3. Load org + authorization ────────────────────────────────────────
        const orgSnap = await db.collection("organizations").doc(orgId).get();
        if (!orgSnap.exists) {
            throw new HttpsError("not-found", "Organization not found.");
        }
        const orgData = orgSnap.data()!;

        const claimedBy: string | undefined = orgData["claimedBy"] ?? orgData["ownerUid"];
        if (claimedBy !== uid) {
            throw new HttpsError(
                "permission-denied",
                "Only the organization owner can access billing management."
            );
        }

        // ── 4. Get Stripe customer ID ──────────────────────────────────────────
        const billingSnap = await orgBillingRef(db, orgId).get();
        const stripeCustomerId: string | undefined = billingSnap.data()?.["stripeCustomerId"];

        if (!stripeCustomerId) {
            throw new HttpsError(
                "failed-precondition",
                "No billing account found for this organization. Subscribe first to manage your plan."
            );
        }

        // ── 5. Create Stripe billing portal session ────────────────────────────
        const stripe = new Stripe(key, { apiVersion: "2026-05-27.dahlia" });

        try {
            const portalSession = await stripe.billingPortal.sessions.create({
                customer: stripeCustomerId,
                return_url: `amen://org-subscription?result=portal_return&orgId=${encodeURIComponent(orgId)}`,
            });

            logger.info("[getOrgBillingPortalURL] Portal session created", {
                orgId, uid, sessionId: portalSession.id,
            });

            return { portalUrl: portalSession.url };
        } catch (err) {
            logger.error("[getOrgBillingPortalURL] Stripe error", { err, orgId, uid });
            throw new HttpsError("internal", "Failed to open billing portal. Please try again.");
        }
    }
);
