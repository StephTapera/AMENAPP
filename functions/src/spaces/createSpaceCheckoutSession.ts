// createSpaceCheckoutSession.ts
// AMEN Spaces — Cloud Function: Create Stripe Checkout Session for a paid Space
//
// Callable: { spaceId: string }
//
// Flow:
//   1. Validate caller is authenticated.
//   2. Validate space exists, has accessPolicy != "free", and has priceConfig.
//   3. Reject if caller already has an active/grace entitlement.
//   4. Resolve the owning community's stripeConnectAccountId.
//   5. Create a Stripe Checkout Session (one-time) or Subscription (recurring)
//      against the Connect account.
//   6. Metadata MUST include amenUserId + amenSpaceId for webhook routing.
//   7. Returns { checkoutURL: string }.
//
// Entitlement write:
//   The webhook handler (stripeWebhookEntitlement.ts) writes the entitlement
//   when Stripe fires invoice.payment_succeeded. Client NEVER writes entitlements.
//
// Hard constraints:
//   - Money never crosses a community Link — owning community's Connect account only.
//   - Metadata MUST include amenUserId and amenSpaceId.
//   - No hard-delete of any document.

import * as logger from "firebase-functions/logger";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import Stripe from "stripe";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// Stripe is initialized lazily so the secret is resolved at runtime.
// Set via: firebase functions:secrets:set STRIPE_SECRET_KEY
let stripeClient: Stripe | null = null;
function getStripe(): Stripe {
  if (!stripeClient) {
    const key = process.env.STRIPE_SECRET_KEY;
    if (!key) {
      throw new HttpsError(
        "failed-precondition",
        "Stripe secret key is not configured."
      );
    }
    stripeClient = new Stripe(key, { apiVersion: "2025-02-24.acacia" });
  }
  return stripeClient;
}

// The callback URL deep-links back into the AMEN app.
// iOS registers `amen://` as a custom URL scheme (see Info.plist).
const SUCCESS_URL = "https://amenapp.com/spaces/checkout-complete?spaceId={SPACE_ID}";
const CANCEL_URL  = "https://amenapp.com/spaces/checkout-cancel?spaceId={SPACE_ID}";

// MARK: - Callable

export const createSpaceCheckoutSession = onCall(
  {
    enforceAppCheck: true,
    secrets: ["STRIPE_SECRET_KEY"],
  },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const { spaceId } = request.data as { spaceId?: string };

    if (!spaceId || typeof spaceId !== "string" || spaceId.trim() === "") {
      throw new HttpsError("invalid-argument", "spaceId is required.");
    }

    // ── 1. Resolve space ──────────────────────────────────────────────────────

    const spaceDoc = await db.collection("spaces").doc(spaceId).get();
    if (!spaceDoc.exists) {
      throw new HttpsError("not-found", `Space ${spaceId} not found.`);
    }

    const spaceData = spaceDoc.data()!;
    const accessPolicy: string = spaceData.accessPolicy ?? "free";
    const priceConfig: {
      amountCents: number;
      currency: string;
      interval?: string;
    } | null = spaceData.priceConfig ?? null;
    const communityId: string = spaceData.communityId ?? "";

    if (accessPolicy === "free") {
      throw new HttpsError(
        "invalid-argument",
        "This Space is free — no purchase required."
      );
    }

    if (!priceConfig || !priceConfig.amountCents || !priceConfig.currency) {
      throw new HttpsError(
        "failed-precondition",
        "This Space does not have a price configured."
      );
    }

    if (!communityId) {
      throw new HttpsError("internal", "Space is missing communityId.");
    }

    // ── 2. Check existing entitlement ─────────────────────────────────────────

    const entitlementId = `${callerUid}_${spaceId}`;
    const entitlementDoc = await db
      .collection("entitlements")
      .doc(entitlementId)
      .get();

    if (entitlementDoc.exists) {
      const status = entitlementDoc.data()?.status as string | undefined;
      if (status === "active" || status === "grace") {
        throw new HttpsError(
          "already-exists",
          "You already have access to this Space."
        );
      }
    }

    // ── 3. Resolve community's Stripe Connect account ────────────────────────

    const communityDoc = await db
      .collection("amenCommunities")
      .doc(communityId)
      .get();

    if (!communityDoc.exists) {
      throw new HttpsError("not-found", `Community ${communityId} not found.`);
    }

    const stripeConnectAccountId: string | undefined =
      communityDoc.data()?.stripeConnectAccountId;

    if (!stripeConnectAccountId) {
      throw new HttpsError(
        "failed-precondition",
        "This community has not set up Stripe Connect. The owner must enable paid Spaces first."
      );
    }

    // ── 4. Create Stripe Checkout Session ────────────────────────────────────

    const stripe = getStripe();

    const successURL = SUCCESS_URL.replace("{SPACE_ID}", spaceId);
    const cancelURL = CANCEL_URL.replace("{SPACE_ID}", spaceId);

    // Shared metadata required by the webhook handler (stripeWebhookEntitlement.ts)
    // MUST include amenUserId and amenSpaceId for status routing.
    const stripeMetadata: Record<string, string> = {
      amenUserId: callerUid,
      amenSpaceId: spaceId,
    };

    let checkoutURL: string;

    if (accessPolicy === "recurring" && priceConfig.interval) {
      // ── Recurring: create Checkout Session in subscription mode ────────────

      // Create or reuse a Stripe Price object for this Space's product.
      // In production, the Space's priceId should be stored in Firestore to avoid
      // creating duplicate Price objects on every session. For v1 we create inline.
      const session = await stripe.checkout.sessions.create(
        {
          mode: "subscription",
          line_items: [
            {
              price_data: {
                currency: priceConfig.currency.toLowerCase(),
                unit_amount: priceConfig.amountCents,
                recurring: {
                  interval: (priceConfig.interval as Stripe.Price.Recurring.Interval) || "month",
                },
                product_data: {
                  name: spaceData.title ?? "Community Space",
                  metadata: stripeMetadata,
                },
              },
              quantity: 1,
            },
          ],
          subscription_data: {
            metadata: stripeMetadata,
          },
          metadata: stripeMetadata,
          success_url: successURL,
          cancel_url: cancelURL,
        },
        {
          stripeAccount: stripeConnectAccountId,
        }
      );

      if (!session.url) {
        throw new HttpsError("internal", "Stripe did not return a checkout URL.");
      }

      checkoutURL = session.url;

      logger.info(
        `[createSpaceCheckoutSession] Created recurring session: spaceId=${spaceId} user=${callerUid} sessionId=${session.id}`
      );

    } else {
      // ── One-time: create Checkout Session in payment mode ──────────────────

      const session = await stripe.checkout.sessions.create(
        {
          mode: "payment",
          line_items: [
            {
              price_data: {
                currency: priceConfig.currency.toLowerCase(),
                unit_amount: priceConfig.amountCents,
                product_data: {
                  name: spaceData.title ?? "Community Space",
                  metadata: stripeMetadata,
                },
              },
              quantity: 1,
            },
          ],
          payment_intent_data: {
            metadata: stripeMetadata,
          },
          metadata: stripeMetadata,
          success_url: successURL,
          cancel_url: cancelURL,
        },
        {
          stripeAccount: stripeConnectAccountId,
        }
      );

      if (!session.url) {
        throw new HttpsError("internal", "Stripe did not return a checkout URL.");
      }

      checkoutURL = session.url;

      logger.info(
        `[createSpaceCheckoutSession] Created one-time session: spaceId=${spaceId} user=${callerUid} sessionId=${session.id}`
      );
    }

    return { checkoutURL };
  }
);
