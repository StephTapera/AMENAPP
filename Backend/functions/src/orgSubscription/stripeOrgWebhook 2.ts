/**
 * stripeOrgWebhook
 *
 * HTTPS Cloud Function that handles Stripe webhook events for org subscriptions.
 *
 * Handles:
 *   checkout.session.completed       → activate billing, update modules
 *   customer.subscription.updated    → update tier + status + modules
 *   customer.subscription.deleted    → cancel billing, revert modules to free
 *   invoice.payment_failed           → mark past_due, revert modules to free
 *
 * Idempotency: deduplicates by Stripe event ID using stripeEvents/{eventId}.
 * Module re-locking never deletes underlying data — only updates org.modules[].
 *
 * Deploy:
 *   firebase functions:secrets:set STRIPE_SECRET_KEY
 *   firebase functions:secrets:set STRIPE_ORG_WEBHOOK_SECRET
 */

import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import Stripe = require("stripe");
import type {
    StripeEvent,
    StripeSubscription,
    StripeCheckoutSession,
    StripeCustomer,
    StripeMetadata,
    StripeInstance,
} from "../stripeHelper";
import {
    OrgBillingTier,
    OrgBillingStatus,
    tierFromPriceId,
    orgBillingStatusFromStripe,
    isGrantingOrgAccess,
    TIER_UNLOCKED_MODULES,
    orgBillingRef,
} from "./orgSubscriptionModels";

const stripeSecretKey        = defineSecret("STRIPE_SECRET_KEY");
const stripeOrgWebhookSecret = defineSecret("STRIPE_ORG_WEBHOOK_SECRET");

// ── Metadata helpers ──────────────────────────────────────────────────────────

function extractOrgMetadata(
    metadata: StripeMetadata | null | undefined
): { orgId: string | null; ownerUid: string | null; targetPlan: OrgBillingTier | null } {
    if (!metadata) return { orgId: null, ownerUid: null, targetPlan: null };
    const orgId    = metadata["orgId"]    ?? metadata["org_id"]    ?? null;
    const ownerUid = metadata["ownerUid"] ?? metadata["owner_uid"] ?? metadata["uid"] ?? null;
    const planRaw  = metadata["targetPlan"] ?? null;
    const targetPlan: OrgBillingTier | null =
        planRaw === "plus" || planRaw === "pro" || planRaw === "free" ? planRaw : null;
    return { orgId, ownerUid, targetPlan };
}

// ── Resolve tier from subscription items ──────────────────────────────────────

function resolveTierFromSubscription(subscription: StripeSubscription): OrgBillingTier {
    const items = subscription.items?.data ?? [];
    for (const item of items) {
        const priceId = item.price?.id;
        if (priceId) {
            const tier = tierFromPriceId(priceId);
            if (tier) return tier;
        }
    }
    // Fall back to metadata hint if price ID not recognised (e.g. price not yet seeded in env).
    const { targetPlan } = extractOrgMetadata(subscription.metadata);
    return targetPlan ?? "free";
}

// ── Core Firestore write ──────────────────────────────────────────────────────

export async function writeOrgBilling(params: {
    db: admin.firestore.Firestore;
    orgId: string;
    ownerUid: string;
    stripeCustomerId: string;
    stripeSubscriptionId: string;
    tier: OrgBillingTier;
    status: OrgBillingStatus;
}): Promise<void> {
    const { db, orgId, ownerUid, stripeCustomerId, stripeSubscriptionId, tier, status } = params;
    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();

    // Write billing sub-doc.
    const billingDocRef = orgBillingRef(db, orgId);
    batch.set(
        billingDocRef,
        {
            stripeCustomerId,
            stripeSubscriptionId,
            tier,
            status,
            ownerUid,
            updatedAt: now,
        },
        { merge: true }
    );

    // Update org.modules to reflect the new tier.
    // This never deletes underlying Spaces/Events/Notes data — just shows/hides modules in the profile.
    const effectiveTier: OrgBillingTier = isGrantingOrgAccess(status) ? tier : "free";
    const orgRef = db.collection("organizations").doc(orgId);
    batch.update(orgRef, {
        modules: TIER_UNLOCKED_MODULES[effectiveTier],
        "billing.tier": tier,
        "billing.status": status,
        "billing.stripeCustomerId": stripeCustomerId,
        "billing.subscriptionId": stripeSubscriptionId,
        updatedAt: now,
    });

    await batch.commit();
}

// ── Push notification helper ──────────────────────────────────────────────────

async function notifyOrgOwner(params: {
    db: admin.firestore.Firestore;
    orgId: string;
    ownerUid: string;
    tier: OrgBillingTier;
    status: OrgBillingStatus;
}): Promise<void> {
    const { db, ownerUid, tier, status } = params;
    try {
        const tokenSnap = await db
            .collection("users").doc(ownerUid)
            .collection("fcmTokens").get();

        const tokens: string[] = tokenSnap.docs
            .map(d => d.data()["token"] as string)
            .filter(Boolean);

        if (!tokens.length) return;

        const title = isGrantingOrgAccess(status)
            ? `Your ${tier.charAt(0).toUpperCase() + tier.slice(1)} plan is active`
            : `Plan update: ${status.replace("_", " ")}`;

        const body = isGrantingOrgAccess(status)
            ? `Your organization now has access to all ${tier.charAt(0).toUpperCase() + tier.slice(1)} features.`
            : `Your plan status changed to ${status.replace("_", " ")}. Tap to manage.`;

        const messages: admin.messaging.Message[] = tokens.map(token => ({
            token,
            notification: { title, body },
            data: { type: "org_billing_update", tier, status },
            apns: { payload: { aps: { badge: 1 } } },
        }));

        await admin.messaging().sendEach(messages);
    } catch (err) {
        logger.warn("[stripeOrgWebhook] Failed to send owner notification", { err, ownerUid });
    }
}

// ── Core event dispatch (exported for unit testing) ───────────────────────────

export async function handleOrgStripeEvent(
    event: StripeEvent,
    db: admin.firestore.Firestore,
    stripe: Pick<StripeInstance, "subscriptions">
): Promise<void> {

    switch (event.type) {

        case "checkout.session.completed": {
            const session = event.data.object as StripeCheckoutSession;
            if (session.mode !== "subscription" || !session.subscription) return;

            const subscriptionId = typeof session.subscription === "string"
                ? session.subscription
                : (session.subscription as StripeSubscription).id;

            const subscription = await stripe.subscriptions.retrieve(subscriptionId);

            const { orgId, ownerUid } = extractOrgMetadata(
                Object.keys(subscription.metadata ?? {}).length > 0
                    ? subscription.metadata
                    : session.metadata
            );

            if (!orgId || !ownerUid) {
                logger.warn("[stripeOrgWebhook] checkout.session.completed: missing orgId/ownerUid", {
                    sessionId: session.id,
                });
                return;
            }

            const tier = resolveTierFromSubscription(subscription);
            const status = orgBillingStatusFromStripe(subscription.status);
            const stripeCustomerId = typeof session.customer === "string"
                ? session.customer
                : (session.customer as StripeCustomer | null)?.id ?? "";

            await writeOrgBilling({
                db, orgId, ownerUid, stripeCustomerId,
                stripeSubscriptionId: subscriptionId, tier, status,
            });

            await notifyOrgOwner({ db, orgId, ownerUid, tier, status });

            logger.info("[stripeOrgWebhook] Org billing activated after checkout", { orgId, tier, status });
            return;
        }

        case "customer.subscription.updated": {
            const subscription = event.data.object as StripeSubscription;
            const { orgId, ownerUid } = extractOrgMetadata(subscription.metadata);

            if (!orgId || !ownerUid) {
                logger.warn("[stripeOrgWebhook] customer.subscription.updated: missing metadata", {
                    subscriptionId: subscription.id,
                });
                return;
            }

            const tier = resolveTierFromSubscription(subscription);
            const status = orgBillingStatusFromStripe(subscription.status);
            const stripeCustomerId = typeof subscription.customer === "string"
                ? subscription.customer
                : (subscription.customer as StripeCustomer).id;

            await writeOrgBilling({
                db, orgId, ownerUid, stripeCustomerId,
                stripeSubscriptionId: subscription.id, tier, status,
            });

            await notifyOrgOwner({ db, orgId, ownerUid, tier, status });

            logger.info("[stripeOrgWebhook] Org billing updated", { orgId, tier, status });
            return;
        }

        case "customer.subscription.deleted": {
            const subscription = event.data.object as StripeSubscription;
            const { orgId, ownerUid } = extractOrgMetadata(subscription.metadata);

            if (!orgId || !ownerUid) {
                logger.warn("[stripeOrgWebhook] customer.subscription.deleted: missing metadata", {
                    subscriptionId: subscription.id,
                });
                return;
            }

            const stripeCustomerId = typeof subscription.customer === "string"
                ? subscription.customer
                : (subscription.customer as StripeCustomer).id;

            await writeOrgBilling({
                db, orgId, ownerUid, stripeCustomerId,
                stripeSubscriptionId: subscription.id,
                tier: "free",
                status: "canceled",
            });

            await notifyOrgOwner({ db, orgId, ownerUid, tier: "free", status: "canceled" });

            logger.info("[stripeOrgWebhook] Org subscription canceled, modules reverted to free", { orgId });
            return;
        }

        case "invoice.payment_failed": {
            // invoice object — retrieve subscription from it.
            const invoice = event.data.object as { subscription?: string; customer?: string };
            const subscriptionId = typeof invoice.subscription === "string"
                ? invoice.subscription : null;
            if (!subscriptionId) return;

            const subscription = await stripe.subscriptions.retrieve(subscriptionId);
            const { orgId, ownerUid } = extractOrgMetadata(subscription.metadata);

            if (!orgId || !ownerUid) return;

            const tier = resolveTierFromSubscription(subscription);
            const stripeCustomerId = typeof subscription.customer === "string"
                ? subscription.customer
                : (subscription.customer as StripeCustomer).id;

            await writeOrgBilling({
                db, orgId, ownerUid, stripeCustomerId,
                stripeSubscriptionId: subscriptionId,
                tier,
                status: "past_due",
            });

            await notifyOrgOwner({ db, orgId, ownerUid, tier, status: "past_due" });

            logger.info("[stripeOrgWebhook] Org invoice payment failed, marked past_due", { orgId });
            return;
        }

        default:
            return;
    }
}

// ── Cloud Function ────────────────────────────────────────────────────────────

export const stripeOrgWebhook = onRequest(
    {
        region: "us-central1",
        secrets: [stripeSecretKey, stripeOrgWebhookSecret],
    },
    async (req, res) => {
        if (req.method !== "POST") {
            res.status(405).send("Method Not Allowed");
            return;
        }

        const key           = stripeSecretKey.value();
        const webhookSecret = stripeOrgWebhookSecret.value();

        if (!key || !webhookSecret) {
            logger.error("[stripeOrgWebhook] Missing Stripe credentials in environment");
            res.status(500).send("Server configuration error");
            return;
        }

        const stripe = new Stripe(key, { apiVersion: "2026-05-27.dahlia" });
        const signature = req.headers["stripe-signature"] as string | undefined;

        let event: StripeEvent;
        try {
            event = stripe.webhooks.constructEvent(
                (req as unknown as { rawBody: Buffer }).rawBody,
                signature ?? "",
                webhookSecret
            );
        } catch (err) {
            logger.warn("[stripeOrgWebhook] Webhook signature verification failed", { err });
            res.status(400).send("Webhook signature verification failed");
            return;
        }

        // ── Idempotency: skip already-processed events ────────────────────────
        const db = admin.firestore();
        const eventRef = db.collection("stripeEvents").doc(event.id);
        const eventSnap = await eventRef.get();
        if (eventSnap.exists) {
            logger.info("[stripeOrgWebhook] Duplicate event skipped", { eventId: event.id });
            res.status(200).json({ received: true, duplicate: true });
            return;
        }

        // Mark processed before handling to prevent race conditions.
        await eventRef.set({
            eventId: event.id,
            type: event.type,
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
            source: "stripeOrgWebhook",
        });

        try {
            await handleOrgStripeEvent(event, db, stripe);
            res.status(200).json({ received: true });
        } catch (err) {
            logger.error("[stripeOrgWebhook] Error processing webhook event", {
                eventType: event.type, err,
            });
            res.status(500).send("Internal error processing webhook");
        }
    }
);
