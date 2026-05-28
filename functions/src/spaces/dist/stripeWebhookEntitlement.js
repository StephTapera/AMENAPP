"use strict";
// stripeWebhookEntitlement.ts
// AMEN Spaces — Stripe Webhook: Entitlement Lifecycle
//
// HTTP endpoint (not callable): receives Stripe webhook events for Space subscriptions.
// NEVER deletes the entitlement row — status flips only.
//
// Lifecycle:
//   invoice.payment_succeeded          → any status → active
//   customer.subscription.deleted      → active → grace (3-day window)
//   invoice.payment_failed             → active → grace (3-day window)
//   invoice.payment_failed (repeated)  → grace → expired (when past grace period)
//
// The Stripe metadata on the subscription must include:
//   metadata.amenUserId  = Firebase uid
//   metadata.amenSpaceId = Firestore spaceId
//
// Contract:
//   Collection: entitlements/{userId}_{spaceId}
//   Field: status ("active" | "grace" | "expired"), stripeSubId, updatedAt, expiresAt
//   NEVER hard-delete the entitlement document.
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.handleStripeSpaceWebhook = void 0;
const logger = __importStar(require("firebase-functions/logger"));
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const stripe_1 = __importDefault(require("stripe"));
if (!admin.apps.length) {
    admin.initializeApp();
}
const db = admin.firestore();
// Set via: firebase functions:secrets:set STRIPE_SECRET_KEY
const stripeWebhookSecret = process.env.STRIPE_WEBHOOK_SECRET || "";
let _stripe = null;
function getStripe() {
    if (!_stripe) {
        const key = process.env.STRIPE_SECRET_KEY;
        if (!key)
            throw new Error("STRIPE_SECRET_KEY not set");
        _stripe = new stripe_1.default(key, { apiVersion: "2025-02-24.acacia" });
    }
    return _stripe;
}
// Grace period: 3 calendar days after subscription deletion or failed payment
const GRACE_PERIOD_DAYS = 3;
// MARK: - Webhook Handler
exports.handleStripeSpaceWebhook = (0, https_1.onRequest)(async (req, res) => {
    if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
    }
    // Verify Stripe signature
    const sig = req.headers["stripe-signature"];
    if (!sig || !stripeWebhookSecret) {
        logger.error("[stripeWebhookEntitlement] Missing stripe-signature or webhook secret.");
        res.status(400).send("Webhook signature missing.");
        return;
    }
    let event;
    try {
        event = getStripe().webhooks.constructEvent(req.rawBody, sig, stripeWebhookSecret);
    }
    catch (err) {
        logger.error("[stripeWebhookEntitlement] Signature verification failed:", err);
        res.status(400).send("Webhook signature verification failed.");
        return;
    }
    logger.info(`[stripeWebhookEntitlement] Processing event: ${event.type}`);
    try {
        switch (event.type) {
            case "invoice.payment_succeeded":
                await handlePaymentSucceeded(event.data.object);
                break;
            case "customer.subscription.deleted":
                await handleSubscriptionDeleted(event.data.object);
                break;
            case "invoice.payment_failed":
                await handlePaymentFailed(event.data.object);
                break;
            default:
                // Unhandled event type — log and ack without error
                logger.debug(`[stripeWebhookEntitlement] Unhandled event type: ${event.type}`);
                break;
        }
        res.json({ received: true });
    }
    catch (err) {
        logger.error(`[stripeWebhookEntitlement] Error processing ${event.type}:`, err);
        // Return 200 to prevent Stripe from retrying; log the error for investigation
        res.json({ received: true, error: "Processing error logged." });
    }
});
// MARK: - Event Handlers
/**
 * invoice.payment_succeeded:
 * Flip any status → active. Renews grace-period or expired entitlements.
 */
async function handlePaymentSucceeded(invoice) {
    const { amenUserId, amenSpaceId } = extractMetadata(invoice);
    if (!amenUserId || !amenSpaceId) {
        logger.warn("[stripeWebhookEntitlement] payment_succeeded: missing amenUserId or amenSpaceId in metadata.", { invoiceId: invoice.id });
        return;
    }
    const subId = typeof invoice.subscription === "string"
        ? invoice.subscription
        : invoice.subscription?.id ?? null;
    const entitlementRef = db.collection("entitlements").doc(`${amenUserId}_${amenSpaceId}`);
    await entitlementRef.set({
        userId: amenUserId,
        spaceId: amenSpaceId,
        status: "active",
        source: "purchase",
        stripeSubId: subId,
        expiresAt: null, // null = lifetime (while subscription active)
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    logger.info(`[stripeWebhookEntitlement] payment_succeeded → active: user=${amenUserId} space=${amenSpaceId}`);
}
/**
 * customer.subscription.deleted:
 * active → grace. Sets expiresAt to now + GRACE_PERIOD_DAYS.
 * If already grace/expired, do not reactivate.
 */
async function handleSubscriptionDeleted(subscription) {
    const { amenUserId, amenSpaceId } = extractMetadataFromSubscription(subscription);
    if (!amenUserId || !amenSpaceId) {
        logger.warn("[stripeWebhookEntitlement] subscription.deleted: missing amenUserId or amenSpaceId in metadata.", { subscriptionId: subscription.id });
        return;
    }
    const entitlementRef = db.collection("entitlements").doc(`${amenUserId}_${amenSpaceId}`);
    const doc = await entitlementRef.get();
    if (!doc.exists) {
        // No entitlement to revoke — log and skip
        logger.warn(`[stripeWebhookEntitlement] subscription.deleted: no entitlement found for ${amenUserId}_${amenSpaceId}`);
        return;
    }
    const currentStatus = doc.data()?.status;
    // Only flip from active → grace; do not re-activate from expired
    if (currentStatus === "active") {
        const graceEnd = new Date();
        graceEnd.setDate(graceEnd.getDate() + GRACE_PERIOD_DAYS);
        await entitlementRef.update({
            status: "grace",
            expiresAt: admin.firestore.Timestamp.fromDate(graceEnd),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        logger.info(`[stripeWebhookEntitlement] subscription.deleted → grace: user=${amenUserId} space=${amenSpaceId} graceUntil=${graceEnd.toISOString()}`);
    }
    else {
        logger.info(`[stripeWebhookEntitlement] subscription.deleted: status already ${currentStatus}, no change.`);
    }
}
/**
 * invoice.payment_failed:
 * active → grace (3-day window).
 * grace (after grace period expired) → expired.
 * If already expired, do not change.
 */
async function handlePaymentFailed(invoice) {
    const { amenUserId, amenSpaceId } = extractMetadata(invoice);
    if (!amenUserId || !amenSpaceId) {
        logger.warn("[stripeWebhookEntitlement] payment_failed: missing amenUserId or amenSpaceId in metadata.", { invoiceId: invoice.id });
        return;
    }
    const entitlementRef = db.collection("entitlements").doc(`${amenUserId}_${amenSpaceId}`);
    const doc = await entitlementRef.get();
    if (!doc.exists) {
        logger.warn(`[stripeWebhookEntitlement] payment_failed: no entitlement found for ${amenUserId}_${amenSpaceId}`);
        return;
    }
    const data = doc.data();
    const currentStatus = data.status;
    const now = new Date();
    if (currentStatus === "active") {
        // First failure: move to grace period
        const graceEnd = new Date();
        graceEnd.setDate(graceEnd.getDate() + GRACE_PERIOD_DAYS);
        await entitlementRef.update({
            status: "grace",
            expiresAt: admin.firestore.Timestamp.fromDate(graceEnd),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        logger.info(`[stripeWebhookEntitlement] payment_failed → grace: user=${amenUserId} space=${amenSpaceId}`);
    }
    else if (currentStatus === "grace") {
        // Check if grace period has elapsed
        const expiresAt = data.expiresAt;
        if (expiresAt && expiresAt.toDate() <= now) {
            await entitlementRef.update({
                status: "expired",
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
            logger.info(`[stripeWebhookEntitlement] payment_failed → expired (grace elapsed): user=${amenUserId} space=${amenSpaceId}`);
        }
        else {
            logger.info(`[stripeWebhookEntitlement] payment_failed: already in grace, grace period not yet elapsed for user=${amenUserId}`);
        }
    }
    else {
        logger.info(`[stripeWebhookEntitlement] payment_failed: status already ${currentStatus}, no change.`);
    }
}
/**
 * Extract amenUserId and amenSpaceId from an Invoice.
 * Looks in subscription_details.metadata first, then top-level metadata.
 */
function extractMetadata(invoice) {
    // Stripe may attach metadata on the subscription or the invoice itself
    const subMeta = invoice.subscription_details?.metadata ?? {};
    const invoiceMeta = invoice.metadata ?? {};
    const amenUserId = subMeta.amenUserId || invoiceMeta.amenUserId || null;
    const amenSpaceId = subMeta.amenSpaceId || invoiceMeta.amenSpaceId || null;
    return { amenUserId, amenSpaceId };
}
/**
 * Extract amenUserId and amenSpaceId from a Subscription.
 */
function extractMetadataFromSubscription(subscription) {
    const meta = subscription.metadata ?? {};
    return {
        amenUserId: meta.amenUserId || null,
        amenSpaceId: meta.amenSpaceId || null,
    };
}
