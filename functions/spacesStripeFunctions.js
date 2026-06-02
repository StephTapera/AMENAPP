/**
 * spacesStripeFunctions.js
 * AMEN Spaces — Stripe Connect onboarding callable
 * Handles: createStripeConnectAccount
 *
 * Setup before deploying:
 *   firebase functions:secrets:set STRIPE_SECRET_KEY
 *   npm install stripe  (if not already in package.json)
 *
 * The Stripe SDK calls below are gated on the secret being present.
 * If STRIPE_SECRET_KEY is unset the function throws failed-precondition
 * so the emulator still starts cleanly.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const db = getFirestore();

const STRIPE_RETURN_BASE_URL = process.env.STRIPE_RETURN_BASE_URL ?? "https://amenapp.com";

// ── createStripeConnectAccount ────────────────────────────────────────────────

exports.createStripeConnectAccount = onCall({ enforceAppCheck: false }, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId } = request.data ?? {};
  if (!spaceId) throw new HttpsError("invalid-argument", "spaceId is required.");

  const stripeKey = process.env.STRIPE_SECRET_KEY;
  if (!stripeKey) {
    throw new HttpsError("failed-precondition",
      "STRIPE_SECRET_KEY is not configured. Run: firebase functions:secrets:set STRIPE_SECRET_KEY");
  }

  const spaceSnap = await db.collection("spaces").doc(spaceId).get();
  if (!spaceSnap.exists) throw new HttpsError("not-found", "Space not found.");
  if (spaceSnap.data()?.hostUserId !== userId) {
    throw new HttpsError("permission-denied", "Only the host can initiate Stripe onboarding.");
  }

  // Lazily require Stripe so the module loads without the secret in the emulator
  const Stripe = require("stripe");
  const stripe = new Stripe(stripeKey, { apiVersion: "2024-12-18.acacia" });

  const hostProfileRef = db.collection("spaces").doc(spaceId)
    .collection("settings").doc("hostProfile");
  const profileSnap = await hostProfileRef.get();

  let stripeAccountId = profileSnap.data()?.stripeAccountId ?? null;
  let isNewAccount = false;

  if (!stripeAccountId) {
    // Create a new Express account — persist ID before generating link to prevent duplicates on retry
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
});
