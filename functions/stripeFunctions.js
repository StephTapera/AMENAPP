/**
 * stripeFunctions.js
 * Stripe Connect integration for Creator Studio payouts.
 *
 * Requires:
 *   firebase functions:secrets:set STRIPE_SECRET_KEY
 *   npm install stripe (add to package.json)
 *
 * Functions:
 *   stripeCreateConnectedAccount — Create Express connected account + onboarding link
 *   stripeGetAccountStatus — Check account status + balance
 *   stripeCreatePaymentIntent — Create payment intent for studio purchase
 *   stripeRequestPayout — Request payout to creator's bank
 */

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

const db = () => admin.firestore();

// Lazy-init Stripe client
let stripeClient = null;
function getStripe() {
  if (!stripeClient) {
    const secretKey = process.env.STRIPE_SECRET_KEY;
    if (!secretKey) {
      throw new HttpsError("failed-precondition", "Stripe not configured");
    }
    stripeClient = require("stripe")(secretKey);
  }
  return stripeClient;
}

// Platform fee percentage (5%)
const PLATFORM_FEE_PERCENT = 5;

// ─── Create Connected Account ────────────────────────────────────────────────

const stripeCreateConnectedAccount = onCall(
    {region: "us-central1", secrets: ["STRIPE_SECRET_KEY"]},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const stripe = getStripe();

      // Check if user already has a connected account
      const userDoc = await db().collection("users").doc(uid).get();
      const existingAccountId = userDoc.data()?.stripeConnectedAccountId;

      if (existingAccountId) {
        // Generate new onboarding link for existing account
        const accountLink = await stripe.accountLinks.create({
          account: existingAccountId,
          refresh_url: `https://amenapp.com/studio/stripe-refresh?uid=${uid}`,
          return_url: `https://amenapp.com/studio/stripe-complete?uid=${uid}`,
          type: "account_onboarding",
        });
        return {onboardingUrl: accountLink.url, accountId: existingAccountId};
      }

      // Create new Express connected account
      const account = await stripe.accounts.create({
        type: "express",
        metadata: {amenUserId: uid},
        capabilities: {
          card_payments: {requested: true},
          transfers: {requested: true},
        },
      });

      // Save account ID to Firestore
      await db().collection("users").doc(uid).update({
        stripeConnectedAccountId: account.id,
      });
      await db().collection("studioProfiles").doc(uid).set({
        stripeConnectedAccountId: account.id,
        payoutStatus: "pending",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      // Generate onboarding link
      const accountLink = await stripe.accountLinks.create({
        account: account.id,
        refresh_url: `https://amenapp.com/studio/stripe-refresh?uid=${uid}`,
        return_url: `https://amenapp.com/studio/stripe-complete?uid=${uid}`,
        type: "account_onboarding",
      });

      return {onboardingUrl: accountLink.url, accountId: account.id};
    },
);

// ─── Get Account Status ──────────────────────────────────────────────────────

const stripeGetAccountStatus = onCall(
    {region: "us-central1", secrets: ["STRIPE_SECRET_KEY"]},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const userDoc = await db().collection("users").doc(uid).get();
      const accountId = userDoc.data()?.stripeConnectedAccountId;

      if (!accountId) {
        return {status: "none", pendingBalance: 0, availableBalance: 0};
      }

      const stripe = getStripe();
      const account = await stripe.accounts.retrieve(accountId);
      const balance = await stripe.balance.retrieve({stripeAccount: accountId});

      let status = "none";
      if (account.charges_enabled && account.payouts_enabled) {
        status = "active";
      } else if (account.requirements?.disabled_reason) {
        status = "disabled";
      } else if (account.requirements?.currently_due?.length > 0) {
        status = "restricted";
      } else {
        status = "pending";
      }

      const pending = balance.pending?.reduce((sum, b) => sum + b.amount, 0) || 0;
      const available = balance.available?.reduce((sum, b) => sum + b.amount, 0) || 0;

      return {
        status,
        pendingBalance: pending / 100, // Convert cents to dollars
        availableBalance: available / 100,
        chargesEnabled: account.charges_enabled,
        payoutsEnabled: account.payouts_enabled,
      };
    },
);

// ─── Create Payment Intent ───────────────────────────────────────────────────

const stripeCreatePaymentIntent = onCall(
    {region: "us-central1", secrets: ["STRIPE_SECRET_KEY"]},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {creatorId, amount, currency, description} = request.data;
      if (!creatorId || !amount) {
        throw new HttpsError("invalid-argument", "creatorId and amount required");
      }

      // Get creator's connected account
      const creatorDoc = await db().collection("users").doc(creatorId).get();
      const connectedAccountId = creatorDoc.data()?.stripeConnectedAccountId;
      if (!connectedAccountId) {
        throw new HttpsError("failed-precondition", "Creator has no payout account");
      }

      const stripe = getStripe();
      const platformFee = Math.round(amount * PLATFORM_FEE_PERCENT / 100);

      const paymentIntent = await stripe.paymentIntents.create({
        amount,
        currency: currency || "usd",
        description: description || "AMEN Studio purchase",
        application_fee_amount: platformFee,
        transfer_data: {
          destination: connectedAccountId,
        },
        metadata: {
          buyerUserId: uid,
          creatorUserId: creatorId,
          platform: "amen",
        },
      });

      // Log transaction
      await db().collection("creatorTransactions").add({
        creatorId,
        buyerId: uid,
        stripePaymentIntentId: paymentIntent.id,
        grossAmount: amount / 100,
        platformFee: platformFee / 100,
        netAmount: (amount - platformFee) / 100,
        currency: currency || "usd",
        description,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {clientSecret: paymentIntent.client_secret};
    },
);

// ─── Request Payout ──────────────────────────────────────────────────────────

const stripeRequestPayout = onCall(
    {region: "us-central1", secrets: ["STRIPE_SECRET_KEY"]},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {amount} = request.data;
      if (!amount || amount <= 0) {
        throw new HttpsError("invalid-argument", "Valid amount required");
      }

      const userDoc = await db().collection("users").doc(uid).get();
      const accountId = userDoc.data()?.stripeConnectedAccountId;
      if (!accountId) {
        throw new HttpsError("failed-precondition", "No payout account");
      }

      const stripe = getStripe();

      const payout = await stripe.payouts.create(
          {amount: amount, currency: "usd"},
          {stripeAccount: accountId},
      );

      return {payoutId: payout.id, status: payout.status};
    },
);

module.exports = {
  stripeCreateConnectedAccount,
  stripeGetAccountStatus,
  stripeCreatePaymentIntent,
  stripeRequestPayout,
};
