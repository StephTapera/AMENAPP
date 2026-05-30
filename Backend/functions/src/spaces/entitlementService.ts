import * as admin from "firebase-admin";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import Stripe = require("stripe");
import type { StripeEvent, StripeSubscription, StripePaymentIntent, StripeSubscriptionStatus } from "../stripeHelper";

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const stripeEntitlementWebhookSecret = defineSecret("STRIPE_ENTITLEMENT_WEBHOOK_SECRET");
const db = admin.firestore();

// ── Helpers ──────────────────────────────────────────────────────────────────

async function assertSpaceAdminOrOwner(spaceId: string, uid: string): Promise<void> {
    const memberSnap = await db
        .collection("spaces").doc(spaceId)
        .collection("members").doc(uid)
        .get();
    if (!memberSnap.exists) {
        throw new HttpsError("permission-denied", "Not a member of this space.");
    }
    const role = memberSnap.data()?.role as string | undefined;
    if (role !== "owner" && role !== "admin") {
        throw new HttpsError("permission-denied", "Admin or owner role required.");
    }
}

function stripeClient(key: string) {
    if (!key) throw new HttpsError("internal", "Stripe secret key not configured.");
    return new Stripe(key, { apiVersion: "2026-05-27.dahlia" });
}

// ── grantAccess ───────────────────────────────────────────────────────────────
// Only callable by space owner/admin. Writes entitlement with source:"grant".
// External-member comps flow here. Money never crosses a community link in v1.

export const grantAccess = onCall(async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) throw new HttpsError("unauthenticated", "Authentication required.");

    const { spaceId, targetUserId, expiresAt } = request.data as {
        spaceId: string;
        targetUserId: string;
        expiresAt?: string | null;
    };

    if (!spaceId || !targetUserId) {
        throw new HttpsError("invalid-argument", "spaceId and targetUserId are required.");
    }

    await assertSpaceAdminOrOwner(spaceId, callerUid);

    const spaceSnap = await db.collection("spaces").doc(spaceId).get();
    if (!spaceSnap.exists) throw new HttpsError("not-found", "Space not found.");

    // Reject purchase-path requests for external members — use grant path only.
    const memberSnap = await db
        .collection("spaces").doc(spaceId)
        .collection("members").doc(targetUserId)
        .get();
    const homeCommunityId = memberSnap.data()?.homeCommunityId as string | undefined;
    const spaceCommunityId = spaceSnap.data()?.communityId as string;
    if (homeCommunityId && homeCommunityId !== spaceCommunityId) {
        // External member — grant path is correct; no validation failure.
    }

    const docId = `${targetUserId}_${spaceId}`;
    const now = admin.firestore.FieldValue.serverTimestamp();

    const payload: Record<string, unknown> = {
        userId: targetUserId,
        spaceId,
        status: "active",
        source: "grant",
        stripeSubId: null,
        expiresAt: expiresAt ? admin.firestore.Timestamp.fromDate(new Date(expiresAt)) : null,
        updatedAt: now,
    };

    await db.collection("entitlements").doc(docId).set(payload, { merge: true });

    logger.info("[grantAccess] Entitlement granted", { docId, callerUid });
    return { success: true, entitlementId: docId };
});

// ── revokeAccess ──────────────────────────────────────────────────────────────
// Sets entitlement status to "expired". Never deletes the document.

export const revokeAccess = onCall(async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) throw new HttpsError("unauthenticated", "Authentication required.");

    const { spaceId, targetUserId } = request.data as {
        spaceId: string;
        targetUserId: string;
    };

    if (!spaceId || !targetUserId) {
        throw new HttpsError("invalid-argument", "spaceId and targetUserId are required.");
    }

    await assertSpaceAdminOrOwner(spaceId, callerUid);

    const docId = `${targetUserId}_${spaceId}`;
    const entSnap = await db.collection("entitlements").doc(docId).get();
    if (!entSnap.exists) throw new HttpsError("not-found", "Entitlement not found.");

    await db.collection("entitlements").doc(docId).update({
        status: "expired",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info("[revokeAccess] Entitlement expired", { docId, callerUid });
    return { success: true };
});

// ── stripeWebhookEntitlementHandler ──────────────────────────────────────────
// Stripe webhook handler. Verifies the Stripe-Signature header before processing.
// All writes are status flips — never deletes entitlement docs.

export const stripeWebhookEntitlementHandler = onRequest(
    { invoker: "public", secrets: [stripeSecretKey, stripeEntitlementWebhookSecret] },
    async (req, res) => {
        const sig = req.headers["stripe-signature"];
        const webhookSecret = stripeEntitlementWebhookSecret.value();

        if (!sig || !webhookSecret) {
            logger.error("[stripeWebhookEntitlementHandler] Missing signature or webhook secret.");
            res.status(400).send("Bad request");
            return;
        }

        let event: StripeEvent;
        try {
            event = stripeClient(stripeSecretKey.value()).webhooks.constructEvent(
                (req as unknown as { rawBody: Buffer }).rawBody,
                sig,
                webhookSecret
            );
        } catch (err) {
            logger.error("[stripeWebhookEntitlementHandler] Signature verification failed", { err });
            res.status(400).send("Webhook signature verification failed.");
            return;
        }

        try {
            await dispatchStripeEvent(event);
            res.status(200).json({ received: true });
        } catch (err) {
            logger.error("[stripeWebhookEntitlementHandler] Dispatch error", { err });
            res.status(500).send("Internal error.");
        }
    }
);

async function dispatchStripeEvent(event: StripeEvent): Promise<void> {
    const now = admin.firestore.FieldValue.serverTimestamp();

    switch (event.type) {

        case "payment_intent.succeeded": {
            const pi = event.data.object as StripePaymentIntent;
            const spaceId = pi.metadata?.spaceId;
            const userId  = pi.metadata?.userId ?? pi.metadata?.uid;
            if (!spaceId || !userId) {
                logger.warn("[stripeWebhookEntitlementHandler] payment_intent.succeeded: missing metadata", {
                    paymentIntentId: pi.id,
                });
                return;
            }
            const docId = `${userId}_${spaceId}`;
            await db.collection("entitlements").doc(docId).set({
                userId,
                spaceId,
                status: "active",
                source: "purchase",
                stripeSubId: null,
                expiresAt: null,
                updatedAt: now,
            }, { merge: true });
            logger.info("[stripeWebhookEntitlementHandler] OneTime grant written", { docId });
            return;
        }

        case "customer.subscription.updated": {
            const sub = event.data.object as StripeSubscription;
            const spaceId = sub.metadata?.spaceId;
            const userId  = sub.metadata?.userId ?? sub.metadata?.uid;
            if (!spaceId || !userId) {
                logger.warn("[stripeWebhookEntitlementHandler] subscription.updated: missing metadata", {
                    subscriptionId: sub.id,
                });
                return;
            }
            const status = entitlementStatusFromStripe(sub.status);
            const docId = `${userId}_${spaceId}`;
            await db.collection("entitlements").doc(docId).set({
                userId,
                spaceId,
                status,
                source: "purchase",
                stripeSubId: sub.id,
                expiresAt: null,
                updatedAt: now,
            }, { merge: true });
            logger.info("[stripeWebhookEntitlementHandler] Subscription updated", { docId, status });
            return;
        }

        case "customer.subscription.deleted": {
            const sub = event.data.object as StripeSubscription;
            const spaceId = sub.metadata?.spaceId;
            const userId  = sub.metadata?.userId ?? sub.metadata?.uid;
            if (!spaceId || !userId) return;
            const docId = `${userId}_${spaceId}`;
            await db.collection("entitlements").doc(docId).update({
                status: "expired",
                updatedAt: now,
            });
            logger.info("[stripeWebhookEntitlementHandler] Subscription deleted → expired", { docId });
            return;
        }

        default:
            // All other event types are ignored.
            return;
    }
}

function entitlementStatusFromStripe(
    stripeStatus: StripeSubscriptionStatus
): "active" | "grace" | "expired" {
    switch (stripeStatus) {
        case "active":
        case "trialing":
            return "active";
        case "past_due":
            return "grace";
        default:
            return "expired";
    }
}
