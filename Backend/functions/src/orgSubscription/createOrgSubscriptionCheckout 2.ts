/**
 * createOrgSubscriptionCheckout
 *
 * Callable Cloud Function that opens a Stripe-hosted checkout session
 * for an org subscription (Plus or Pro tier).
 *
 * Authorization:
 *   - Caller must be authenticated.
 *   - Caller's UID must match org.claimedBy (only the org owner can subscribe).
 *   - org.claimStatus must be "claimed" or "verified".
 *
 * Stripe objects are NEVER created for unclaimed orgs.
 * Billing status is written exclusively by stripeOrgWebhook after payment confirms.
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import Stripe = require("stripe");
import {
    OrgBillingTier,
    getTierPrices,
    orgBillingRef,
} from "./orgSubscriptionModels";

const stripeSecretKey       = defineSecret("STRIPE_SECRET_KEY");
const stripeOrgPlusPriceId  = defineSecret("STRIPE_ORG_PLUS_PRICE_ID");
const stripeOrgProPriceId   = defineSecret("STRIPE_ORG_PRO_PRICE_ID");

interface CheckoutInput {
    orgId: string;
    plan: OrgBillingTier;
}

export const createOrgSubscriptionCheckout = onCall(
    {
        enforceAppCheck: true,
        region: "us-central1",
        secrets: [stripeSecretKey, stripeOrgPlusPriceId, stripeOrgProPriceId],
    },
    async (request) => {
        // ── 1. Auth ────────────────────────────────────────────────────────────
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;

        // ── 2. Input validation ────────────────────────────────────────────────
        const { orgId, plan } = (request.data ?? {}) as Partial<CheckoutInput>;

        if (typeof orgId !== "string" || !orgId.trim()) {
            throw new HttpsError("invalid-argument", "orgId is required.");
        }
        if (plan !== "plus" && plan !== "pro") {
            throw new HttpsError(
                "invalid-argument",
                "plan must be 'plus' or 'pro'. Free tier has no checkout."
            );
        }

        const key = stripeSecretKey.value();
        if (!key) {
            logger.error("[createOrgSubscriptionCheckout] STRIPE_SECRET_KEY not configured");
            throw new HttpsError("internal", "Payment service not configured.");
        }

        const db = admin.firestore();

        // ── 3. Load org + authorization ────────────────────────────────────────
        const orgSnap = await db.collection("organizations").doc(orgId).get();
        if (!orgSnap.exists) {
            throw new HttpsError("not-found", "Organization not found.");
        }
        const orgData = orgSnap.data()!;

        // Only the org owner may subscribe.
        const claimedBy: string | undefined = orgData["claimedBy"] ?? orgData["ownerUid"];
        if (claimedBy !== uid) {
            throw new HttpsError(
                "permission-denied",
                "Only the organization owner can start a subscription."
            );
        }

        // Org must be claimed or verified.
        const claimStatus: string = orgData["claimStatus"] ?? "unclaimed";
        if (claimStatus !== "claimed" && claimStatus !== "verified") {
            throw new HttpsError(
                "failed-precondition",
                "Your organization must be claimed before subscribing. Complete the claim process first."
            );
        }

        // ── 4. Resolve Stripe Price ID ─────────────────────────────────────────
        const tierPrices = getTierPrices();
        const stripePriceId = tierPrices[plan];

        if (!stripePriceId) {
            logger.error("[createOrgSubscriptionCheckout] Missing Stripe Price ID for plan", { plan });
            throw new HttpsError(
                "failed-precondition",
                "This plan is not yet configured for payments. Contact support."
            );
        }

        // ── 5. Resolve caller email for Stripe receipt UX ─────────────────────
        let customerEmail: string | undefined;
        try {
            const userRecord = await admin.auth().getUser(uid);
            customerEmail = userRecord.email ?? undefined;
        } catch {
            // Non-fatal — Stripe creates the session without email.
        }

        // ── 6. Read or create Stripe customer ─────────────────────────────────
        const stripe = new Stripe(key, { apiVersion: "2026-05-27.dahlia" });
        const billingRef = orgBillingRef(db, orgId);
        const billingSnap = await billingRef.get();
        const existingCustomerId: string | undefined = billingSnap.data()?.["stripeCustomerId"];

        let stripeCustomerId: string;
        if (existingCustomerId) {
            stripeCustomerId = existingCustomerId;
        } else {
            const customer = await stripe.customers.create({
                email: customerEmail,
                metadata: { orgId, ownerUid: uid },
            });
            stripeCustomerId = customer.id;

            // Persist customer ID immediately so retry calls reuse the same customer.
            await billingRef.set(
                {
                    stripeCustomerId,
                    tier: "free",
                    status: "unknown",
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true }
            );
        }

        // ── 7. Create Stripe Checkout Session ─────────────────────────────────
        try {
            const session = await stripe.checkout.sessions.create({
                mode: "subscription",
                customer: stripeCustomerId,
                line_items: [{ price: stripePriceId, quantity: 1 }],
                subscription_data: {
                    metadata: { orgId, ownerUid: uid, targetPlan: plan },
                },
                metadata: { orgId, ownerUid: uid, targetPlan: plan },
                client_reference_id: orgId,
                // iOS ASWebAuthenticationSession callback scheme.
                success_url: `amen://org-subscription?result=success&orgId=${encodeURIComponent(orgId)}&plan=${plan}`,
                cancel_url:  `amen://org-subscription?result=cancel&orgId=${encodeURIComponent(orgId)}`,
                allow_promotion_codes: true,
            });

            logger.info("[createOrgSubscriptionCheckout] Session created", {
                sessionId: session.id, orgId, plan, uid,
            });

            return { checkoutUrl: session.url };
        } catch (err) {
            logger.error("[createOrgSubscriptionCheckout] Stripe error", { err, orgId, plan, uid });
            throw new HttpsError("internal", "Failed to create checkout session. Please try again.");
        }
    }
);
