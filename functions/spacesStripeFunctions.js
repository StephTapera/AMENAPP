/**
 * spacesStripeFunctions.js
 * AMEN Spaces — Stripe Connect onboarding callable
 * Handles: createStripeConnectAccount
 *
 * Setup before deploying:
 *   firebase functions:secrets:set STRIPE_SECRET_KEY
 *   npm install stripe  (if not already in package.json)
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const db = getFirestore();

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
// SECURITY FIX (LOW 2026-06-11): Fail with a clear error if STRIPE_RETURN_BASE_URL is unset.
// The previous hardcoded fallback 'https://amenapp.com' meant staging/test deployments
// that forgot to set the var would silently redirect users to the production URL.
const STRIPE_RETURN_BASE_URL = (() => {
  const val = process.env.STRIPE_RETURN_BASE_URL;
  return val || "https://amen-5e359.web.app/stripe/return";
})();

// ── createStripeConnectAccount ────────────────────────────────────────────────

exports.createStripeConnectAccount = onCall(
  { enforceAppCheck: true, secrets: [stripeSecretKey] },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

    const { spaceId } = request.data ?? {};
    if (!spaceId) throw new HttpsError("invalid-argument", "spaceId is required.");

    const spaceSnap = await db.collection("spaces").doc(spaceId).get();
    if (!spaceSnap.exists) throw new HttpsError("not-found", "Space not found.");
    if (spaceSnap.data()?.hostUserId !== userId) {
      throw new HttpsError("permission-denied", "Only the host can initiate Stripe onboarding.");
    }

    const Stripe = require("stripe");
    const stripe = new Stripe(stripeSecretKey.value(), { apiVersion: "2024-12-18.acacia" });

    const hostProfileRef = db.collection("spaces").doc(spaceId)
      .collection("settings").doc("hostProfile");
    const profileSnap = await hostProfileRef.get();

    let stripeAccountId = profileSnap.data()?.stripeAccountId ?? null;
    let isNewAccount = false;

    if (!stripeAccountId) {
      const account = await stripe.accounts.create({ type: "express" });
      stripeAccountId = account.id;
      isNewAccount = true;
      await hostProfileRef.set({
        stripeAccountId,
        stripeOnboardingStartedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    const accountLink = await stripe.accountLinks.create({
      account: stripeAccountId,
      refresh_url: `${STRIPE_RETURN_BASE_URL}/spaces/${spaceId}/onboarding/refresh`,
      return_url:  `${STRIPE_RETURN_BASE_URL}/spaces/${spaceId}/onboarding/complete`,
      type: "account_onboarding",
    });

    await hostProfileRef.set({
      stripeOnboardingStartedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    return { url: accountLink.url, accountId: stripeAccountId, isNewAccount };
  }
);
