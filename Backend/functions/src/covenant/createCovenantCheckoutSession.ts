import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import Stripe from "stripe";

const stripeSecretKeyParam = defineSecret("STRIPE_SECRET_KEY");

// createCovenantCheckoutSession
//
// Callable function invoked by iOS AmenCovenantCheckoutService.startCheckout().
//
// Creates a Stripe-hosted checkout session for a Covenant tier subscription.
// Membership is NEVER written from the client — stripeCovenantWebhook handles
// covenants/{covenantId}/members/{uid} creation after Stripe confirms payment.
//
// subscription_data.metadata carries { covenantId, userId } so that
// customer.subscription.* events can index the member without relying on the
// checkout session (which may not fire in retry scenarios).

interface CheckoutInput {
    covenantId: string;
    tierId: string;
}

export const createCovenantCheckoutSession = onCall(
    { enforceAppCheck: true, region: "us-central1", secrets: [stripeSecretKeyParam] },
    async (request) => {
        // ── 1. Auth ────────────────────────────────────────────────────────────
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;

        // ── 2. Input validation ────────────────────────────────────────────────
        const { covenantId, tierId } = (request.data ?? {}) as Partial<CheckoutInput>;

        if (typeof covenantId !== "string" || !covenantId.trim()) {
            throw new HttpsError("invalid-argument", "covenantId is required.");
        }
        if (typeof tierId !== "string" || !tierId.trim()) {
            throw new HttpsError("invalid-argument", "tierId is required.");
        }

        const stripeSecretKey = stripeSecretKeyParam.value();
        if (!stripeSecretKey) {
            logger.error("[createCovenantCheckoutSession] STRIPE_SECRET_KEY not configured");
            throw new HttpsError("internal", "Payment service not configured.");
        }

        const db = admin.firestore();

        // ── 3. Load covenant + resolve tier ───────────────────────────────────
        const covenantSnap = await db.collection("covenants").doc(covenantId).get();
        if (!covenantSnap.exists) {
            throw new HttpsError("not-found", "Community not found.");
        }
        const covenantData = covenantSnap.data()!;

        // Tiers are stored as an array on the covenant document.
        const tiers: Array<Record<string, unknown>> = Array.isArray(covenantData.tiers)
            ? (covenantData.tiers as Array<Record<string, unknown>>)
            : [];

        const tier = tiers.find((t) => t["id"] === tierId);
        if (!tier) {
            throw new HttpsError("not-found", `Tier '${tierId}' not found in this community.`);
        }

        // stripePriceId must be pre-configured by the creator when setting up the tier.
        const stripePriceId = tier["stripePriceId"] as string | undefined;
        if (!stripePriceId || typeof stripePriceId !== "string") {
            logger.warn("[createCovenantCheckoutSession] Tier has no stripePriceId", {
                covenantId, tierId,
            });
            throw new HttpsError(
                "failed-precondition",
                "This tier is not configured for payments yet. Contact the community creator."
            );
        }

        // ── 4. Resolve caller email for Stripe (improves receipt UX) ─────────
        let customerEmail: string | undefined;
        try {
            const userRecord = await admin.auth().getUser(uid);
            customerEmail = userRecord.email ?? undefined;
        } catch {
            // Non-fatal — Stripe will still create the session without email.
        }

        // ── 5. Create Stripe checkout session ─────────────────────────────────
        const stripe = new Stripe(stripeSecretKey, { apiVersion: "2026-05-27.dahlia" });

        try {
            const session = await stripe.checkout.sessions.create({
                mode: "subscription",
                line_items: [
                    {
                        price: stripePriceId,
                        quantity: 1,
                    },
                ],
                // subscription_data.metadata is the canonical location so that
                // customer.subscription.created/updated events carry the IDs.
                subscription_data: {
                    metadata: {
                        covenantId,
                        userId: uid,
                    },
                },
                // Session-level metadata as a fallback for checkout.session.completed.
                metadata: {
                    covenantId,
                    userId: uid,
                },
                customer_email: customerEmail,
                // iOS ASWebAuthenticationSession callback scheme.
                success_url: `amen://covenant-checkout?result=success&covenantId=${encodeURIComponent(covenantId)}`,
                cancel_url:  `amen://covenant-checkout?result=cancel`,
                // Allow promotion codes so creators can run discounts.
                allow_promotion_codes: true,
            });

            logger.info("[createCovenantCheckoutSession] Session created", {
                sessionId: session.id, covenantId, tierId, uid,
            });

            return { checkoutUrl: session.url };
        } catch (err) {
            logger.error("[createCovenantCheckoutSession] Stripe error", { err, covenantId, tierId, uid });
            throw new HttpsError("internal", "Failed to create checkout session. Please try again.");
        }
    }
);
