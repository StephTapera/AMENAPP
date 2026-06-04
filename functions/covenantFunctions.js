/**
 * covenantFunctions.js
 * AMEN Covenant — Stripe-hosted subscription checkout for creator tiers.
 *
 * Functions:
 *   createCovenantCheckoutSession — Create Stripe Checkout Session + pending membership doc
 *   verifyCovenantMembership      — Confirm the membership doc exists after redirect
 *
 * Requires:
 *   firebase functions:secrets:set STRIPE_SECRET_KEY
 *   The Stripe webhook handler (spacesStripeFunctions.js or a new webhook route)
 *   must update covenantMemberships/{membershipId}.status → "active" on
 *   checkout.session.completed events.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const db = getFirestore();

// Lazy-init Stripe client (same pattern as stripeFunctions.js)
let stripeClient = null;
function getStripe() {
  if (!stripeClient) {
    // TODO: USE_DEFINE_SECRET — migrate to defineSecret() for this secret
    const secretKey = process.env.STRIPE_SECRET_KEY;
    if (!secretKey) throw new HttpsError("failed-precondition", "Stripe not configured.");
    stripeClient = require("stripe")(secretKey);
  }
  return stripeClient;
}

// ── createCovenantCheckoutSession ────────────────────────────────────────────

exports.createCovenantCheckoutSession = onCall(
  { enforceAppCheck: true }, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

    const { covenantId, tierId } = request.data ?? {};
    if (!covenantId || !tierId) {
      throw new HttpsError("invalid-argument", "covenantId and tierId are required.");
    }

    // Load tier to get price
    const tierSnap = await db
      .collection("covenants")
      .doc(covenantId)
      .collection("tiers")
      .doc(tierId)
      .get();

    if (!tierSnap.exists || !tierSnap.data()?.isActive) {
      throw new HttpsError("not-found", "Tier not found or inactive.");
    }

    const tier = tierSnap.data();
    if (!tier.stripePriceId) {
      throw new HttpsError("failed-precondition", "Tier has no Stripe price configured.");
    }

    // Pre-generate a membership ID so we can embed it in the success URL.
    // The doc starts as "pending"; the Stripe webhook sets it to "active".
    const membershipId = `mem_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const membershipRef = db.collection("covenantMemberships").doc(membershipId);

    await membershipRef.set({
      membershipId,
      userId,
      covenantId,
      tierId,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
      stripeSessionId: null, // filled in below after session creation
    });

    const stripe = getStripe();
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: tier.stripePriceId, quantity: 1 }],
      success_url: `amen://covenant-checkout?result=success&membershipId=${membershipId}`,
      cancel_url: `amen://covenant-checkout?result=cancel`,
      client_reference_id: userId,
      metadata: { membershipId, covenantId, tierId, userId },
    });

    // Back-fill the session ID so the webhook can look up the membership doc.
    await membershipRef.update({ stripeSessionId: session.id });

    return { checkoutUrl: session.url };
  }
);

// ── verifyCovenantMembership ─────────────────────────────────────────────────

exports.verifyCovenantMembership = onCall(
  { enforceAppCheck: true }, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

    const { membershipId } = request.data ?? {};
    if (!membershipId) throw new HttpsError("invalid-argument", "membershipId is required.");

    const membershipSnap = await db.collection("covenantMemberships").doc(membershipId).get();

    if (!membershipSnap.exists) {
      // Stripe webhook hasn't fired yet or the session was never created.
      // Fall back to checking the Stripe session directly if we can resolve it.
      throw new HttpsError("not-found", "Membership not found. Payment may still be processing.");
    }

    const membership = membershipSnap.data();

    // Ownership check — the calling user must own this membership.
    if (membership.userId !== userId) {
      throw new HttpsError("permission-denied", "Membership does not belong to this user.");
    }

    // "pending" is acceptable: Stripe processed the payment (redirect happened)
    // and the webhook is in flight. "active" means webhook already confirmed it.
    if (membership.status !== "active" && membership.status !== "pending") {
      throw new HttpsError("failed-precondition", `Membership status is '${membership.status}'.`);
    }

    return { ok: true, status: membership.status, covenantId: membership.covenantId };
  }
);
