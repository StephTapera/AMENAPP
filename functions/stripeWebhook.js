// stripeWebhook.js
// Stripe webhook endpoint with mandatory signature verification.
// Every event is verified with stripe.webhooks.constructEvent() before processing.
// STRIPE_WEBHOOK_SECRET must be set:
//   firebase functions:secrets:set STRIPE_WEBHOOK_SECRET

const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");

const db = () => admin.firestore();
const serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp();

// Lazy-init Stripe client
let stripeClient = null;
function getStripe() {
  if (!stripeClient) {
    stripeClient = require("stripe")(STRIPE_SECRET_KEY.value());
  }
  return stripeClient;
}

// ─── Webhook Entry Point ─────────────────────────────────────────────────────

exports.stripeWebhook = onRequest(
  { region: "us-central1", secrets: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"] },
  async (req, res) => {
    const sig = req.headers["stripe-signature"];

    let event;
    try {
      event = getStripe().webhooks.constructEvent(
        req.rawBody,
        sig,
        STRIPE_WEBHOOK_SECRET.value()
      );
    } catch (err) {
      console.error("[Stripe] Signature verification failed:", err.message);
      return res.status(400).send(`Webhook signature verification failed: ${err.message}`);
    }

    try {
      switch (event.type) {
        case "payment_intent.succeeded":
          console.log(`[Stripe] payment_intent.succeeded: ${event.id}`);
          await handlePaymentSucceeded(event.data.object, event.id);
          break;
        case "customer.subscription.updated":
          await handleSubscriptionUpdated(event.data.object, event.id);
          break;
        case "customer.subscription.deleted":
          await handleSubscriptionDeleted(event.data.object, event.id);
          break;
        case "account.updated":
          await handleConnectAccountUpdated(event.data.object, event.id);
          break;
        default:
          console.log(`[Stripe] Unhandled event type: ${event.type} (${event.id})`);
      }
    } catch (err) {
      console.error(`[Stripe] Handler error for event ${event.id}:`, err);
      try {
        await db().collection("webhookErrors").doc(event.id).set({
          eventId: event.id,
          eventType: event.type,
          error: err.message,
          stack: err.stack || null,
          occurredAt: serverTimestamp(),
        });
      } catch (writeErr) {
        console.error("[Stripe] Failed to write webhookErrors doc:", writeErr);
      }
    }

    return res.status(200).send({ received: true });
  }
);

// ─── Handlers ────────────────────────────────────────────────────────────────

async function handlePaymentSucceeded(paymentIntent, eventId) {
  const { userId, productType } = paymentIntent.metadata || {};

  if (userId && productType === "covenant_membership") {
    await db().collection("users").doc(userId).update({
      covenantStatus: "active",
      lastPaymentAt: serverTimestamp(),
    });
  }

  await db().collection("paymentEvents").doc(paymentIntent.id).set({
    userId: userId || null,
    type: "payment_succeeded",
    amount: paymentIntent.amount,
    currency: paymentIntent.currency,
    processedAt: serverTimestamp(),
  });
}

async function handleSubscriptionUpdated(subscription, eventId) {
  const userId = subscription.metadata?.userId;
  if (!userId) {
    console.warn(`[Stripe] subscription.updated ${subscription.id} has no metadata.userId`);
    return;
  }

  await db().collection("users").doc(userId).update({
    subscriptionStatus: subscription.status,
    subscriptionPeriodEnd: subscription.current_period_end,
  });
}

async function handleSubscriptionDeleted(subscription, eventId) {
  const userId = subscription.metadata?.userId;
  if (!userId) {
    console.warn(`[Stripe] subscription.deleted ${subscription.id} has no metadata.userId`);
    return;
  }

  await db().collection("users").doc(userId).update({
    subscriptionStatus: "canceled",
    covenantStatus: "inactive",
  });
}

async function handleConnectAccountUpdated(account, eventId) {
  const snapshot = await db()
    .collection("users")
    .where("stripeConnectedAccountId", "==", account.id)
    .limit(1)
    .get();

  if (snapshot.empty) {
    console.warn(`[Stripe] account.updated: no user found for Stripe account ${account.id}`);
    return;
  }

  const userId = snapshot.docs[0].id;
  await db().collection("users").doc(userId).update({
    stripeAccountStatus: account.payouts_enabled ? "active" : "pending",
  });
}
