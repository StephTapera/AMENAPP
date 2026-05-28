// purchaseService.ts
// AMENAPP — Spaces Monetization (Agent E)
//
// purchaseSpaceAccess: onCall — creates a Stripe PaymentIntent (oneTime) or
// Subscription (recurring) on the owning community's Connect account.
//
// Money routing rule: owning community's stripeConnectAccountId ALWAYS collects.
// External (linked) members pay the same price as owning-community members.
// Revenue-split is a fast-follow; do NOT implement cross-link transfers here.
//
// Entitlement lifecycle (status flips only; never hard-delete):
//   payment_intent.succeeded or subscription.updated → stripeWebhookEntitlementHandler
//   writes/updates entitlements/{userId}_{spaceId} with status: "active"

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import Stripe from "stripe";

const db = admin.firestore();

// ── Helpers ───────────────────────────────────────────────────────────────────

function stripeClient(): Stripe {
    const key = process.env.STRIPE_SECRET_KEY;
    if (!key) throw new HttpsError("internal", "Stripe secret key not configured.");
    return new Stripe(key, { apiVersion: "2023-10-16" });
}

async function getConnectAccountId(communityId: string): Promise<string> {
    const communitySnap = await db.collection("communities").doc(communityId).get();
    if (!communitySnap.exists) {
        throw new HttpsError("not-found", "Owning community not found.");
    }
    const connectId = communitySnap.data()?.stripeConnectAccountId as string | undefined;
    if (!connectId || connectId.trim() === "") {
        throw new HttpsError(
            "failed-precondition",
            "This community has not set up payment processing yet."
        );
    }
    return connectId;
}

// ── purchaseSpaceAccess ───────────────────────────────────────────────────────
//
// Input:
//   { spaceId: string, userId: string, communityId: string,
//     priceConfig: { amountCents: number, currency: string, interval?: string } }
//
// Output:
//   { clientSecret: string }  — iOS confirms with Stripe SDK / Apple Pay
//
// The iOS client MUST pass the returned clientSecret to the Stripe payment sheet.
// The webhook (stripeWebhookEntitlementHandler) fires after confirmation and
// writes the entitlement document.

export const purchaseSpaceAccess = onCall(async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { spaceId, userId, communityId, priceConfig } = request.data as {
        spaceId: string;
        userId: string;
        communityId: string;
        priceConfig: {
            amountCents: number;
            currency: string;
            interval?: string;
        };
    };

    // Input validation
    if (!spaceId || !userId || !communityId) {
        throw new HttpsError("invalid-argument", "spaceId, userId, and communityId are required.");
    }
    if (!priceConfig || typeof priceConfig.amountCents !== "number" || priceConfig.amountCents <= 0) {
        throw new HttpsError("invalid-argument", "priceConfig.amountCents must be a positive integer.");
    }
    if (!priceConfig.currency || priceConfig.currency.length < 3) {
        throw new HttpsError("invalid-argument", "priceConfig.currency is required (e.g. 'usd').");
    }

    // Caller must be the user making the purchase, or an admin (v1: must match)
    if (callerUid !== userId) {
        throw new HttpsError("permission-denied", "You may only purchase access for your own account.");
    }

    // Validate space exists and is not free
    const spaceSnap = await db.collection("spaces").doc(spaceId).get();
    if (!spaceSnap.exists) {
        throw new HttpsError("not-found", "Space not found.");
    }
    const spaceData = spaceSnap.data();
    if (!spaceData) {
        throw new HttpsError("not-found", "Space data missing.");
    }
    const accessPolicy = spaceData.accessPolicy as string | undefined;
    if (accessPolicy === "free" || !accessPolicy) {
        throw new HttpsError("failed-precondition", "This space is free and does not require purchase.");
    }
    if (spaceData.isDeleted === true) {
        throw new HttpsError("not-found", "This space is no longer available.");
    }

    // Validate communityId matches the space's owning community (no cross-link money)
    const spaceCommunityId = spaceData.communityId as string | undefined;
    if (!spaceCommunityId || spaceCommunityId !== communityId) {
        throw new HttpsError(
            "permission-denied",
            "communityId does not match the owning community of this space."
        );
    }

    // Fetch owning community's Connect account
    const connectAccountId = await getConnectAccountId(communityId);

    const stripe = stripeClient();
    const currency = priceConfig.currency.toLowerCase();
    const metadataBase: Stripe.MetadataParam = {
        spaceId,
        userId,
        communityId,
    };

    // ── One-time purchase ──────────────────────────────────────────────────────
    if (accessPolicy === "oneTime") {
        const paymentIntent = await stripe.paymentIntents.create({
            amount: priceConfig.amountCents,
            currency,
            transfer_data: {
                destination: connectAccountId,
            },
            metadata: metadataBase,
        });

        if (!paymentIntent.client_secret) {
            throw new HttpsError("internal", "Failed to create payment intent.");
        }

        logger.info("[purchaseSpaceAccess] PaymentIntent created", {
            paymentIntentId: paymentIntent.id,
            spaceId,
            userId,
        });

        return { clientSecret: paymentIntent.client_secret };
    }

    // ── Recurring subscription ─────────────────────────────────────────────────
    if (accessPolicy === "recurring") {
        const interval = priceConfig.interval ?? "month";
        if (interval !== "month" && interval !== "year") {
            throw new HttpsError("invalid-argument", "interval must be 'month' or 'year'.");
        }

        // Create an ad-hoc price for this space (v1: per-space prices, no shared Price objects)
        // In v2, creator wizard (Agent D) would pre-create reusable Stripe Price IDs.
        const price = await stripe.prices.create(
            {
                unit_amount: priceConfig.amountCents,
                currency,
                recurring: { interval: interval as "month" | "year" },
                product_data: {
                    name: `Space Access: ${spaceId}`,
                    metadata: { spaceId },
                },
            },
            { stripeAccount: connectAccountId }
        );

        // SetupIntent for subscription — client confirms card then backend creates subscription.
        // Alternatively: create a subscription with payment_behavior:"default_incomplete"
        // and return the latest_invoice.payment_intent.client_secret.
        // We use the direct subscription approach here for predictability.

        // Find or create a Stripe Customer for this userId on the Connect account
        // (v1: use metadata to correlate; no cross-account customer sharing)
        let customerId: string;
        const existingCustomers = await stripe.customers.list(
            { limit: 1, metadata: { userId } as unknown as Stripe.CustomerListParams },
            { stripeAccount: connectAccountId }
        );
        if (existingCustomers.data.length > 0 && existingCustomers.data[0].id) {
            customerId = existingCustomers.data[0].id;
        } else {
            const customer = await stripe.customers.create(
                { metadata: { userId } },
                { stripeAccount: connectAccountId }
            );
            customerId = customer.id;
        }

        const subscription = await stripe.subscriptions.create(
            {
                customer: customerId,
                items: [{ price: price.id }],
                payment_behavior: "default_incomplete",
                payment_settings: { save_default_payment_method: "on_subscription" },
                expand: ["latest_invoice.payment_intent"],
                metadata: metadataBase,
            },
            { stripeAccount: connectAccountId }
        );

        // Extract client_secret from the expanded latest_invoice.payment_intent
        const latestInvoice = subscription.latest_invoice as Stripe.Invoice | null;
        const paymentIntent = latestInvoice?.payment_intent as Stripe.PaymentIntent | null;
        const clientSecret = paymentIntent?.client_secret;

        if (!clientSecret) {
            throw new HttpsError("internal", "Failed to retrieve subscription payment intent.");
        }

        logger.info("[purchaseSpaceAccess] Subscription created", {
            subscriptionId: subscription.id,
            spaceId,
            userId,
        });

        return { clientSecret };
    }

    // Unreachable in practice — accessPolicy validated above.
    throw new HttpsError("invalid-argument", `Unsupported accessPolicy: ${accessPolicy}`);
});
