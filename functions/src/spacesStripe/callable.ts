// callable.ts — Stripe Connect onboarding Cloud Functions
//
// Setup: run `npm install stripe` in the functions/ directory if not already
// installed, then set STRIPE_SECRET_KEY in Firebase environment config:
//   firebase functions:secrets:set STRIPE_SECRET_KEY
//
// Stripe SDK version used: ^17.0.0 (already in package.json)

import * as functions from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

// ── Stripe initialisation ─────────────────────────────────────────────────────
//
// Import is guarded so the function module still loads during local emulation
// when STRIPE_SECRET_KEY is absent — it will throw at call-time only.

// eslint-disable-next-line @typescript-eslint/no-require-imports
const Stripe = require("stripe");

function getStripe(): InstanceType<typeof import("stripe").default> {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) {
    throw new functions.HttpsError(
      "failed-precondition",
      "Stripe is not configured. Set STRIPE_SECRET_KEY in Firebase secrets."
    );
  }
  return new Stripe(key, { apiVersion: "2024-06-20" });
}

// ── Firestore ─────────────────────────────────────────────────────────────────

const db = getFirestore();

// ── Types ─────────────────────────────────────────────────────────────────────

interface CreateStripeConnectAccountInput {
  spaceId: string;
}

interface HostProfileDoc {
  stripeAccountId?: string;
  stripeOnboardingStartedAt?: FirebaseFirestore.FieldValue;
  stripeOnboardingCompletedAt?: FirebaseFirestore.FieldValue | null;
  verificationStatus?: string;
  updatedAt?: FirebaseFirestore.FieldValue;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Returns the shared host-profile document reference for a space. */
function hostProfileRef(spaceId: string): FirebaseFirestore.DocumentReference {
  return db.collection("spaces").doc(spaceId).collection("hostProfile").doc("profile");
}

/**
 * Builds a Stripe Account Link URL for the given Express account.
 * Used both for first-time onboarding and for resuming incomplete flows.
 */
async function buildAccountLink(
  stripe: InstanceType<typeof import("stripe").default>,
  accountId: string,
  spaceId: string
): Promise<string> {
  const appBaseUrl = process.env.STRIPE_RETURN_BASE_URL ?? "https://amenapp.com";
  const link = await stripe.accountLinks.create({
    account: accountId,
    refresh_url: `${appBaseUrl}/spaces/${spaceId}/stripe/refresh`,
    return_url: `${appBaseUrl}/spaces/${spaceId}/stripe/return`,
    type: "account_onboarding",
    collect: "eventually_due",
  });
  return link.url;
}

// ── createStripeConnectAccount ────────────────────────────────────────────────

export const createStripeConnectAccount = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new functions.HttpsError("unauthenticated", "Must be signed in.");
    }

    const data = request.data as CreateStripeConnectAccountInput;
    const spaceId = String(data?.spaceId ?? "").trim();

    if (!spaceId || spaceId.length < 2 || spaceId.length > 128) {
      throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    }

    // ── Authorisation: caller must be the space host ──────────────────────────
    const spaceSnap = await db.collection("spaces").doc(spaceId).get();
    if (!spaceSnap.exists) {
      throw new functions.HttpsError("not-found", "Space not found.");
    }
    const spaceData = spaceSnap.data() as { hostUserId?: string };
    if (spaceData?.hostUserId !== userId) {
      throw new functions.HttpsError(
        "permission-denied",
        "Only the space host may configure Stripe Connect."
      );
    }

    const stripe = getStripe();
    const profileRef = hostProfileRef(spaceId);
    const profileSnap = await profileRef.get();
    const existingProfile = profileSnap.data() as HostProfileDoc | undefined;

    let accountId: string;
    let isNewAccount = false;

    if (existingProfile?.stripeAccountId) {
      // ── Returning host: create a fresh account link for the existing account
      accountId = existingProfile.stripeAccountId;
      logger.info(
        `createStripeConnectAccount: resuming onboarding for existing account`,
        { spaceId, userId, accountId }
      );
    } else {
      // ── New host: create a Stripe Express account ─────────────────────────
      //
      // We use the `express` type so AMEN controls the payout schedule and
      // platform fee configuration, while Stripe handles identity verification.
      const emailSnap = await db.collection("users").doc(userId).get();
      const userEmail = (emailSnap.data() as { email?: string } | undefined)?.email;

      const account = await stripe.accounts.create({
        type: "express",
        country: "US",
        email: userEmail,
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
        },
        business_type: "individual",
        metadata: {
          amenSpaceId: spaceId,
          amenUserId: userId,
        },
      });

      accountId = account.id;
      isNewAccount = true;

      // Persist the new accountId before generating the link so a CF retry
      // or network failure never creates a second Stripe account.
      await profileRef.set(
        {
          stripeAccountId: accountId,
          stripeOnboardingStartedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        } satisfies Partial<HostProfileDoc>,
        { merge: true }
      );

      logger.info(
        `createStripeConnectAccount: new Express account created`,
        { spaceId, userId, accountId }
      );
    }

    // ── Build an account link URL ─────────────────────────────────────────────
    const url = await buildAccountLink(stripe, accountId, spaceId);

    // ── Update Firestore: record that onboarding was (re-)initiated ───────────
    const profileUpdate: Partial<HostProfileDoc> = {
      stripeOnboardingStartedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    await profileRef.set(profileUpdate, { merge: true });

    return {
      url,
      accountId,
      isNewAccount,
    };
  }
);
