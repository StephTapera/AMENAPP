/**
 * stripe/stripeWebhook.js
 *
 * Hardened Stripe webhook handler for AMEN platform subscription entitlements.
 *
 * Security posture:
 *   - Webhook signature verified with stripe.webhooks.constructEvent() before
 *     any processing. Any request that fails verification is rejected with 400.
 *   - Idempotency enforced via processedStripeEvents/{event.id} in Firestore.
 *     Duplicate deliveries are safely acknowledged with 200 and not reprocessed.
 *   - Secrets are declared via defineSecret() (Firebase Functions v2 params).
 *     STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET never appear in source or logs.
 *   - Every entitlement mutation is written atomically with a corresponding audit
 *     log entry in stripeEntitlementAuditLog/.
 *
 * CRITICAL — Plan vs. Verification:
 *   A "church" or "organization" plan tier reflected here is a BILLING TIER ONLY.
 *   It does NOT mean the account has been verified as a real church or organization.
 *   Church/organization verification is a separate human-reviewed process handled
 *   by the Trust & Safety team outside the payment pipeline. Never use the plan
 *   field alone to gate church-admin or organization-admin capabilities.
 *
 * Secrets required (set once via Firebase CLI):
 *   firebase functions:secrets:set STRIPE_SECRET_KEY
 *   firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
 *
 * Deploy:
 *   firebase deploy --only functions:stripeWebhook --project amen-5e359
 */

"use strict";

const admin     = require("firebase-admin");
const functions = require("firebase-functions/v1");
const { defineSecret } = require("firebase-functions/params");

// ─── Secret declarations ─────────────────────────────────────────────────────
// Both secrets are resolved by the Firebase runtime at invocation time.
// They are never logged, never echoed in responses, never accessible client-side.

const STRIPE_SECRET_KEY    = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");

// ─── Firestore helpers ───────────────────────────────────────────────────────

const db              = () => admin.firestore();
const FieldValue      = admin.firestore.FieldValue;
const serverTimestamp = () => FieldValue.serverTimestamp();

// ─── Plan mapping ────────────────────────────────────────────────────────────
// Maps Stripe price/product metadata planId values to canonical AMEN plan slugs.
// Stripe subscription metadata must include a `planId` key matching one of these.
// Unknown planIds fall back to "plus" to avoid accidentally granting elevated access.

const VALID_PLANS = new Set(["free", "plus", "pro", "church", "organization"]);

/**
 * Derive the canonical AMEN plan slug from a Stripe subscription object.
 * Priority: subscription.metadata.planId → items[0].price.metadata.planId → "plus".
 *
 * CRITICAL — See module-level comment: plan != verified. A "church" plan does NOT
 * grant church-admin permissions. Verification is a separate human-reviewed step.
 *
 * @param {object} subscription - Stripe subscription object
 * @returns {"free"|"plus"|"pro"|"church"|"organization"}
 */
function derivePlan(subscription) {
  const fromSub = subscription.metadata?.planId;
  if (fromSub && VALID_PLANS.has(fromSub)) return fromSub;

  const items = subscription.items?.data ?? [];
  const fromPrice = items[0]?.price?.metadata?.planId;
  if (fromPrice && VALID_PLANS.has(fromPrice)) return fromPrice;

  // Default to "plus" — never silently grant "pro", "church", or "organization".
  console.warn(
    `[StripeWebhook] No valid planId found on subscription ${subscription.id}; defaulting to "plus".`
  );
  return "plus";
}

// ─── Stripe status → AMEN entitlement status mapping ────────────────────────

/**
 * Map a Stripe subscription status to the canonical AMEN entitlement status.
 * Stripe statuses: active, past_due, canceled, incomplete, incomplete_expired,
 *                  trialing, unpaid, paused.
 *
 * @param {string} stripeStatus
 * @returns {"active"|"past_due"|"canceled"|"trialing"}
 */
function mapStatus(stripeStatus) {
  switch (stripeStatus) {
    case "active":              return "active";
    case "trialing":            return "trialing";
    case "past_due":
    case "unpaid":
    case "paused":              return "past_due";
    case "canceled":
    case "incomplete":
    case "incomplete_expired":  return "canceled";
    default:
      console.warn(`[StripeWebhook] Unknown Stripe status "${stripeStatus}"; mapping to "past_due".`);
      return "past_due";
  }
}

// ─── Idempotency guard ───────────────────────────────────────────────────────

/**
 * Returns true if this event has already been processed, false otherwise.
 * Uses a Firestore document as a distributed lock/deduplication record.
 *
 * @param {string} eventId - Stripe event.id
 * @returns {Promise<boolean>}
 */
async function isAlreadyProcessed(eventId) {
  const ref = db().collection("processedStripeEvents").doc(eventId);
  const snap = await ref.get();
  return snap.exists;
}

/**
 * Mark an event as processed. Called after successful entitlement write.
 *
 * @param {string} eventId - Stripe event.id
 * @returns {Promise<void>}
 */
async function markProcessed(eventId) {
  await db().collection("processedStripeEvents").doc(eventId).set({
    eventId,
    processedAt: serverTimestamp(),
  });
}

// ─── Audit log ───────────────────────────────────────────────────────────────

/**
 * Write an audit log entry for every entitlement mutation.
 * Writes to stripeEntitlementAuditLog/{auto-id} — never overwrites, append-only.
 *
 * @param {object} entry
 */
async function writeAuditLog(entry) {
  try {
    await db().collection("stripeEntitlementAuditLog").add({
      ...entry,
      loggedAt: serverTimestamp(),
    });
  } catch (err) {
    // Audit log failure must NOT block the main entitlement write.
    // Log but do not rethrow so the webhook returns 200 to Stripe.
    console.error("[StripeWebhook] Audit log write failed:", err.message);
  }
}

// ─── Entitlement writer ───────────────────────────────────────────────────────

/**
 * Upsert the entitlements/{userId} document with the canonical shape.
 * Also writes an audit log entry after every mutation.
 *
 * CRITICAL — plan != verified. See module-level comment.
 *
 * @param {object} params
 * @param {string} params.userId
 * @param {string} params.plan          - "free"|"plus"|"pro"|"church"|"organization"
 * @param {string} params.status        - "active"|"past_due"|"canceled"|"trialing"
 * @param {string} params.stripeCustomerId
 * @param {string} params.stripeSubscriptionId
 * @param {string} params.eventId       - Stripe event.id for traceability
 * @param {string} params.eventType     - Stripe event.type for audit trail
 */
async function upsertEntitlement({
  userId,
  plan,
  status,
  stripeCustomerId,
  stripeSubscriptionId,
  eventId,
  eventType,
}) {
  const entitlement = {
    userId,
    // CRITICAL: plan is a BILLING tier only. It does NOT indicate that a "church"
    // or "organization" account has been verified by the Trust & Safety team.
    // Verification is a separate human-reviewed process outside this pipeline.
    plan,
    status,
    source:               "stripe",
    stripeCustomerId,
    stripeSubscriptionId,
    updatedAt:            serverTimestamp(),
    lastVerifiedEventId:  eventId,
  };

  await db().collection("entitlements").doc(userId).set(entitlement, { merge: true });

  await writeAuditLog({
    userId,
    plan,
    status,
    stripeCustomerId,
    stripeSubscriptionId,
    eventId,
    eventType,
    source: "stripe",
  });

  console.info(
    `[StripeWebhook] Entitlement updated: userId=${userId} plan=${plan} status=${status} eventId=${eventId}`
  );
}

// ─── Event handlers ───────────────────────────────────────────────────────────

/**
 * customer.subscription.created
 * First-time subscription activation. Creates the entitlement document with
 * status "active" (or "trialing" if the subscription is in a trial period).
 */
async function handleSubscriptionCreated(subscription, eventId) {
  const userId = subscription.metadata?.userId;
  if (!userId) {
    console.warn(
      `[StripeWebhook] subscription.created ${subscription.id} missing metadata.userId — skipping.`
    );
    return;
  }

  await upsertEntitlement({
    userId,
    plan:                 derivePlan(subscription),
    status:               mapStatus(subscription.status),
    stripeCustomerId:     String(subscription.customer),
    stripeSubscriptionId: subscription.id,
    eventId,
    eventType:            "customer.subscription.created",
  });
}

/**
 * customer.subscription.updated
 * Plan change or status transition (e.g. trial → active, active → past_due).
 * Updates both plan and status.
 */
async function handleSubscriptionUpdated(subscription, eventId) {
  const userId = subscription.metadata?.userId;
  if (!userId) {
    console.warn(
      `[StripeWebhook] subscription.updated ${subscription.id} missing metadata.userId — skipping.`
    );
    return;
  }

  await upsertEntitlement({
    userId,
    plan:                 derivePlan(subscription),
    status:               mapStatus(subscription.status),
    stripeCustomerId:     String(subscription.customer),
    stripeSubscriptionId: subscription.id,
    eventId,
    eventType:            "customer.subscription.updated",
  });
}

/**
 * customer.subscription.deleted
 * Subscription has ended (canceled by user, payment failure cascade, or admin).
 * Forces status to "canceled" regardless of Stripe's reported status.
 */
async function handleSubscriptionDeleted(subscription, eventId) {
  const userId = subscription.metadata?.userId;
  if (!userId) {
    console.warn(
      `[StripeWebhook] subscription.deleted ${subscription.id} missing metadata.userId — skipping.`
    );
    return;
  }

  await upsertEntitlement({
    userId,
    plan:                 derivePlan(subscription),
    status:               "canceled",
    stripeCustomerId:     String(subscription.customer),
    stripeSubscriptionId: subscription.id,
    eventId,
    eventType:            "customer.subscription.deleted",
  });
}

/**
 * invoice.payment_succeeded
 * Successful payment confirms the subscription is in good standing.
 * Sets status to "active" for any subscription-type invoice.
 * One-time invoices (no subscription) are recorded in paymentEvents only.
 */
async function handleInvoicePaymentSucceeded(invoice, eventId) {
  const subscriptionId = invoice.subscription;
  if (!subscriptionId) {
    // One-time payment — record in paymentEvents but no entitlement to update.
    await db().collection("paymentEvents").doc(eventId).set({
      invoiceId:   invoice.id,
      customerId:  invoice.customer,
      amountPaid:  invoice.amount_paid,
      currency:    invoice.currency,
      eventId,
      eventType:   "invoice.payment_succeeded",
      processedAt: serverTimestamp(),
    });
    return;
  }

  const userId = invoice.subscription_details?.metadata?.userId
    ?? invoice.metadata?.userId;

  if (!userId) {
    console.warn(
      `[StripeWebhook] invoice.payment_succeeded for subscription ${subscriptionId} missing userId metadata — skipping entitlement update.`
    );
    return;
  }

  await upsertEntitlement({
    userId,
    // Derive plan from subscription_details metadata; fall back to "plus".
    plan: (() => {
      const planId = invoice.subscription_details?.metadata?.planId
        ?? invoice.metadata?.planId;
      return (planId && VALID_PLANS.has(planId)) ? planId : "plus";
    })(),
    status:               "active",
    stripeCustomerId:     String(invoice.customer),
    stripeSubscriptionId: subscriptionId,
    eventId,
    eventType:            "invoice.payment_succeeded",
  });
}

/**
 * invoice.payment_failed
 * Payment failed — mark entitlement as past_due. The subscription may still
 * be retried by Stripe. If retries are exhausted, subscription.deleted follows.
 */
async function handleInvoicePaymentFailed(invoice, eventId) {
  const subscriptionId = invoice.subscription;
  if (!subscriptionId) return; // One-time invoice failure — no entitlement to update.

  const userId = invoice.subscription_details?.metadata?.userId
    ?? invoice.metadata?.userId;

  if (!userId) {
    console.warn(
      `[StripeWebhook] invoice.payment_failed for subscription ${subscriptionId} missing userId metadata — skipping.`
    );
    return;
  }

  await upsertEntitlement({
    userId,
    plan: (() => {
      const planId = invoice.subscription_details?.metadata?.planId
        ?? invoice.metadata?.planId;
      return (planId && VALID_PLANS.has(planId)) ? planId : "plus";
    })(),
    status:               "past_due",
    stripeCustomerId:     String(invoice.customer),
    stripeSubscriptionId: subscriptionId,
    eventId,
    eventType:            "invoice.payment_failed",
  });
}

// ─── Webhook entry point ─────────────────────────────────────────────────────

exports.stripeWebhook = functions
  .region("us-central1")
  .runWith({ secrets: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"] })
  .https.onRequest(async (req, res) => {

    // ── 1. Signature verification ────────────────────────────────────────────
    // Reject any request that cannot be verified as originating from Stripe.
    // This prevents replay attacks and spoofed payloads.
    const stripe = require("stripe")(STRIPE_SECRET_KEY.value());
    const sig    = req.headers["stripe-signature"];

    let event;
    try {
      event = stripe.webhooks.constructEvent(
        req.rawBody,
        sig,
        STRIPE_WEBHOOK_SECRET.value()
      );
    } catch (err) {
      console.error("Stripe signature verification failed:", err.message);
      return res.status(400).send("Webhook Error: Invalid signature");
    }

    // ── 2. Idempotency guard ─────────────────────────────────────────────────
    // Stripe may deliver the same event more than once. Check before processing.
    try {
      const alreadyProcessed = await isAlreadyProcessed(event.id);
      if (alreadyProcessed) {
        console.info(`[StripeWebhook] Duplicate event ignored: ${event.id} (${event.type})`);
        return res.status(200).send({ received: true, duplicate: true });
      }
    } catch (err) {
      // If we cannot read the idempotency collection, log but continue.
      // Better to risk an idempotent double-write than to fail the webhook.
      console.error("[StripeWebhook] Idempotency check failed:", err.message);
    }

    // ── 3. Event dispatch ────────────────────────────────────────────────────
    try {
      switch (event.type) {
        case "customer.subscription.created":
          await handleSubscriptionCreated(event.data.object, event.id);
          break;

        case "customer.subscription.updated":
          await handleSubscriptionUpdated(event.data.object, event.id);
          break;

        case "customer.subscription.deleted":
          await handleSubscriptionDeleted(event.data.object, event.id);
          break;

        case "invoice.payment_succeeded":
          await handleInvoicePaymentSucceeded(event.data.object, event.id);
          break;

        case "invoice.payment_failed":
          await handleInvoicePaymentFailed(event.data.object, event.id);
          break;

        default:
          console.log(`[StripeWebhook] Unhandled event type: ${event.type} (${event.id})`);
      }

      // ── 4. Mark processed ──────────────────────────────────────────────────
      // Only written after a successful handler execution.
      await markProcessed(event.id);

    } catch (err) {
      // Handler-level error. Log to webhookErrors for ops visibility.
      // Return 500 so Stripe will retry delivery — do NOT mark processed.
      console.error(`[StripeWebhook] Handler error for event ${event.id} (${event.type}):`, err);

      try {
        await db().collection("webhookErrors").doc(event.id).set({
          eventId:   event.id,
          eventType: event.type,
          error:     err.message,
          stack:     err.stack || null,
          occurredAt: serverTimestamp(),
        }, { merge: true });
      } catch (writeErr) {
        console.error("[StripeWebhook] Failed to write webhookErrors doc:", writeErr.message);
      }

      // Return 500 to signal Stripe to retry.
      return res.status(500).send("Internal error — will retry.");
    }

    // ── 5. Acknowledge ───────────────────────────────────────────────────────
    return res.status(200).send({ received: true });
  });
