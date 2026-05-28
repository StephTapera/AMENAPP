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

import * as logger from "firebase-functions/logger";
import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import Stripe from "stripe";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// Set via: firebase functions:secrets:set STRIPE_SECRET_KEY
const stripeWebhookSecret = process.env.STRIPE_WEBHOOK_SECRET || "";
let _stripe: Stripe | null = null;
function getStripe(): Stripe {
  if (!_stripe) {
    const key = process.env.STRIPE_SECRET_KEY;
    if (!key) throw new Error("STRIPE_SECRET_KEY not set");
    _stripe = new Stripe(key, { apiVersion: "2025-02-24.acacia" });
  }
  return _stripe;
}

// Grace period: 3 calendar days after subscription deletion or failed payment
const GRACE_PERIOD_DAYS = 3;

// MARK: - Webhook Handler

export const handleStripeSpaceWebhook = onRequest(async (req, res) => {
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

  let event: Stripe.Event;
  try {
    event = getStripe().webhooks.constructEvent(
      req.rawBody as Buffer,
      sig,
      stripeWebhookSecret
    );
  } catch (err) {
    logger.error("[stripeWebhookEntitlement] Signature verification failed:", err);
    res.status(400).send("Webhook signature verification failed.");
    return;
  }

  logger.info(`[stripeWebhookEntitlement] Processing event: ${event.type}`);

  try {
    switch (event.type) {
      case "invoice.payment_succeeded":
        await handlePaymentSucceeded(event.data.object as Stripe.Invoice);
        break;

      case "customer.subscription.deleted":
        await handleSubscriptionDeleted(event.data.object as Stripe.Subscription);
        break;

      case "invoice.payment_failed":
        await handlePaymentFailed(event.data.object as Stripe.Invoice);
        break;

      default:
        // Unhandled event type — log and ack without error
        logger.debug(`[stripeWebhookEntitlement] Unhandled event type: ${event.type}`);
        break;
    }

    res.json({ received: true });
  } catch (err) {
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
async function handlePaymentSucceeded(invoice: Stripe.Invoice): Promise<void> {
  const { amenUserId, amenSpaceId } = extractMetadata(invoice);
  if (!amenUserId || !amenSpaceId) {
    logger.warn(
      "[stripeWebhookEntitlement] payment_succeeded: missing amenUserId or amenSpaceId in metadata.",
      { invoiceId: invoice.id }
    );
    return;
  }

  const subId = typeof invoice.subscription === "string"
    ? invoice.subscription
    : invoice.subscription?.id ?? null;

  const entitlementRef = db.collection("entitlements").doc(`${amenUserId}_${amenSpaceId}`);

  await entitlementRef.set(
    {
      userId: amenUserId,
      spaceId: amenSpaceId,
      status: "active",
      source: "purchase",
      stripeSubId: subId,
      expiresAt: null,           // null = lifetime (while subscription active)
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  logger.info(
    `[stripeWebhookEntitlement] payment_succeeded → active: user=${amenUserId} space=${amenSpaceId}`
  );
}

/**
 * customer.subscription.deleted:
 * active → grace. Sets expiresAt to now + GRACE_PERIOD_DAYS.
 * If already grace/expired, do not reactivate.
 */
async function handleSubscriptionDeleted(subscription: Stripe.Subscription): Promise<void> {
  const { amenUserId, amenSpaceId } = extractMetadataFromSubscription(subscription);
  if (!amenUserId || !amenSpaceId) {
    logger.warn(
      "[stripeWebhookEntitlement] subscription.deleted: missing amenUserId or amenSpaceId in metadata.",
      { subscriptionId: subscription.id }
    );
    return;
  }

  const entitlementRef = db.collection("entitlements").doc(`${amenUserId}_${amenSpaceId}`);
  const doc = await entitlementRef.get();

  if (!doc.exists) {
    // No entitlement to revoke — log and skip
    logger.warn(
      `[stripeWebhookEntitlement] subscription.deleted: no entitlement found for ${amenUserId}_${amenSpaceId}`
    );
    return;
  }

  const currentStatus = doc.data()?.status as string;

  // Only flip from active → grace; do not re-activate from expired
  if (currentStatus === "active") {
    const graceEnd = new Date();
    graceEnd.setDate(graceEnd.getDate() + GRACE_PERIOD_DAYS);

    await entitlementRef.update({
      status: "grace",
      expiresAt: admin.firestore.Timestamp.fromDate(graceEnd),
      updatedAt: FieldValue.serverTimestamp(),
    });

    logger.info(
      `[stripeWebhookEntitlement] subscription.deleted → grace: user=${amenUserId} space=${amenSpaceId} graceUntil=${graceEnd.toISOString()}`
    );
  } else {
    logger.info(
      `[stripeWebhookEntitlement] subscription.deleted: status already ${currentStatus}, no change.`
    );
  }
}

/**
 * invoice.payment_failed:
 * active → grace (3-day window).
 * grace (after grace period expired) → expired.
 * If already expired, do not change.
 */
async function handlePaymentFailed(invoice: Stripe.Invoice): Promise<void> {
  const { amenUserId, amenSpaceId } = extractMetadata(invoice);
  if (!amenUserId || !amenSpaceId) {
    logger.warn(
      "[stripeWebhookEntitlement] payment_failed: missing amenUserId or amenSpaceId in metadata.",
      { invoiceId: invoice.id }
    );
    return;
  }

  const entitlementRef = db.collection("entitlements").doc(`${amenUserId}_${amenSpaceId}`);
  const doc = await entitlementRef.get();

  if (!doc.exists) {
    logger.warn(
      `[stripeWebhookEntitlement] payment_failed: no entitlement found for ${amenUserId}_${amenSpaceId}`
    );
    return;
  }

  const data = doc.data()!;
  const currentStatus = data.status as string;
  const now = new Date();

  if (currentStatus === "active") {
    // First failure: move to grace period
    const graceEnd = new Date();
    graceEnd.setDate(graceEnd.getDate() + GRACE_PERIOD_DAYS);

    await entitlementRef.update({
      status: "grace",
      expiresAt: admin.firestore.Timestamp.fromDate(graceEnd),
      updatedAt: FieldValue.serverTimestamp(),
    });

    logger.info(
      `[stripeWebhookEntitlement] payment_failed → grace: user=${amenUserId} space=${amenSpaceId}`
    );
  } else if (currentStatus === "grace") {
    // Check if grace period has elapsed
    const expiresAt = data.expiresAt as admin.firestore.Timestamp | null;
    if (expiresAt && expiresAt.toDate() <= now) {
      await entitlementRef.update({
        status: "expired",
        updatedAt: FieldValue.serverTimestamp(),
      });

      logger.info(
        `[stripeWebhookEntitlement] payment_failed → expired (grace elapsed): user=${amenUserId} space=${amenSpaceId}`
      );
    } else {
      logger.info(
        `[stripeWebhookEntitlement] payment_failed: already in grace, grace period not yet elapsed for user=${amenUserId}`
      );
    }
  } else {
    logger.info(
      `[stripeWebhookEntitlement] payment_failed: status already ${currentStatus}, no change.`
    );
  }
}

// MARK: - Metadata Extraction

interface SpaceMetadata {
  amenUserId: string | null;
  amenSpaceId: string | null;
}

/**
 * Extract amenUserId and amenSpaceId from an Invoice.
 * Looks in subscription_details.metadata first, then top-level metadata.
 */
function extractMetadata(invoice: Stripe.Invoice): SpaceMetadata {
  // Stripe may attach metadata on the subscription or the invoice itself
  const subMeta = (invoice as any).subscription_details?.metadata ?? {};
  const invoiceMeta = invoice.metadata ?? {};

  const amenUserId =
    subMeta.amenUserId || invoiceMeta.amenUserId || null;
  const amenSpaceId =
    subMeta.amenSpaceId || invoiceMeta.amenSpaceId || null;

  return { amenUserId, amenSpaceId };
}

/**
 * Extract amenUserId and amenSpaceId from a Subscription.
 */
function extractMetadataFromSubscription(subscription: Stripe.Subscription): SpaceMetadata {
  const meta = subscription.metadata ?? {};
  return {
    amenUserId: meta.amenUserId || null,
    amenSpaceId: meta.amenSpaceId || null,
  };
}
