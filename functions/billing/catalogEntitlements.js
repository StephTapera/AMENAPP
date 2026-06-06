/**
 * billing/catalogEntitlements.js
 * Server-side catalog entitlement enforcement for AMEN Catalog + Knowledge Network.
 *
 * Entitlement matrix:
 *   free            — catalog_read only
 *   creator_pro     — + ask_creator, catalog_create; work limit 500
 *   creator_studio  — + knowledge_map, unlimited_works, transcript_search
 *   organization    — all creator_studio + org-level access
 *
 * Platform fees (applied server-side via Stripe application_fee_amount):
 *   course / digital_product : 15%
 *   membership / coaching    : 12%
 *   event                    : 10%
 *   tip                      : 5%
 *
 * Required environment / secrets:
 *   STRIPE_SECRET_KEY              — Firebase secret
 *   STRIPE_PRICE_CREATOR_PRO       — env var (Stripe Price ID for $19/mo)
 *   STRIPE_PRICE_CREATOR_STUDIO    — env var (Stripe Price ID for $49/mo)
 *   STRIPE_CHECKOUT_SUCCESS_URL    — env var
 *   STRIPE_CHECKOUT_CANCEL_URL     — env var
 */

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

const db = () => admin.firestore();

// ─── Stripe lazy init ────────────────────────────────────────────────────────

let stripeClient = null;
function getStripe() {
  if (!stripeClient) {
    const key = process.env.STRIPE_SECRET_KEY;
    if (!key) throw new HttpsError("failed-precondition", "Stripe not configured");
    stripeClient = require("stripe")(key);
  }
  return stripeClient;
}

// ─── Constants ───────────────────────────────────────────────────────────────

const VALID_FEATURES = [
  "catalog_read",
  "ask_creator",
  "knowledge_map",
  "catalog_create",
  "unlimited_works",
  "transcript_search",
];

const WORK_LIMITS = {
  free: 0,
  creator_pro: 500,
  creator_studio: Infinity,
  organization: Infinity,
};

const FEE_TABLE = {
  course: 15,
  digital_product: 15,
  membership: 12,
  coaching: 12,
  event: 10,
  tip: 5,
};

// ─── Internal helpers ────────────────────────────────────────────────────────

/**
 * Fetch tier string from Firestore. Returns 'free' on any failure (fail closed).
 * @param {string} uid
 * @returns {Promise<string>}
 */
async function fetchTier(uid) {
  try {
    const snap = await db()
        .collection("users")
        .doc(uid)
        .collection("entitlements")
        .doc("platform")
        .get();
    return snap.data()?.tier || "free";
  } catch {
    return "free";
  }
}

/**
 * Resolve the feature allow/deny for a given tier.
 * @param {string} feature
 * @param {string} tier
 * @returns {{ allowed: boolean, reason?: string }}
 */
function resolveFeature(feature, tier) {
  switch (feature) {
    case "catalog_read":
      return {allowed: true};

    case "catalog_create":
      if (tier === "creator_pro" || tier === "creator_studio" || tier === "organization") {
        return {allowed: true};
      }
      return {allowed: false, reason: "Requires Creator Pro or higher"};

    case "ask_creator":
      if (tier === "creator_pro" || tier === "creator_studio" || tier === "organization") {
        return {allowed: true};
      }
      return {allowed: false, reason: "Requires Creator Pro or higher"};

    case "knowledge_map":
      if (tier === "creator_studio" || tier === "organization") {
        return {allowed: true};
      }
      return {allowed: false, reason: "Requires Creator Studio or higher"};

    case "unlimited_works":
      if (tier === "creator_studio" || tier === "organization") {
        return {allowed: true};
      }
      return {allowed: false, reason: "Requires Creator Studio or higher"};

    case "transcript_search":
      if (tier === "creator_studio" || tier === "organization") {
        return {allowed: true};
      }
      return {allowed: false, reason: "Requires Creator Studio or higher"};

    default:
      return {allowed: false, reason: "Unknown feature"};
  }
}

// ─── calculatePlatformFee (internal utility) ─────────────────────────────────

/**
 * Calculate platform fee and creator proceeds for a given amount and work type.
 * All amounts in the smallest currency unit (cents for USD).
 * @param {{ amount: number, type: string }} params
 * @returns {{ platformFeeAmount: number, creatorProceeds: number, feePercent: number }}
 */
function calculatePlatformFee({amount, type}) {
  if (typeof amount !== "number" || amount <= 0) {
    throw new HttpsError("invalid-argument", "amount must be a positive number");
  }
  const feePercent = FEE_TABLE[type];
  if (feePercent === undefined) {
    throw new HttpsError(
        "invalid-argument",
        `Unknown work type '${type}'. Valid types: ${Object.keys(FEE_TABLE).join(", ")}`,
    );
  }
  const platformFeeAmount = Math.round(amount * (feePercent / 100));
  const creatorProceeds = amount - platformFeeAmount;
  return {platformFeeAmount, creatorProceeds, feePercent};
}

// ─── enforceWorkLimit (internal) ─────────────────────────────────────────────

/**
 * Returns true if the creator is within their tier's work limit.
 * Throws HttpsError("resource-exhausted") if over limit.
 * Intended to be called by ingestion Cloud Functions before writing a new work.
 * @param {string} uid
 * @returns {Promise<true>}
 */
async function enforceWorkLimit(uid) {
  const tier = await fetchTier(uid);
  const limit = WORK_LIMITS[tier] ?? 0;

  if (limit === 0) {
    throw new HttpsError(
        "permission-denied",
        "Your plan does not allow catalog creation. Upgrade to Creator Pro.",
    );
  }

  if (limit === Infinity) return true;

  const worksSnap = await db()
      .collection("catalogWorks")
      .where("creatorId", "==", uid)
      .where("status", "==", "published")
      .get();

  const count = worksSnap.size;
  if (count >= limit) {
    throw new HttpsError(
        "resource-exhausted",
        `Work limit of ${limit} reached for your plan. Upgrade to Creator Studio for unlimited works.`,
    );
  }

  return true;
}

// ─── grantCatalogAccess (internal, called by Stripe webhook) ─────────────────

/**
 * Writes a catalog access grant for a buyer.
 * @param {{ buyerId: string, workId: string, expiresAt?: Date|null }} params
 */
async function grantCatalogAccess({buyerId, workId, expiresAt = null}) {
  await db()
      .collection("users")
      .doc(buyerId)
      .collection("catalogAccess")
      .doc(workId)
      .set({
        grantedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: expiresAt ?? null,
        workId,
      });
}

// ─── checkCatalogEntitlement (CF onCall) ────────────────────────────────────

const checkCatalogEntitlement = onCall(
    {region: "us-central1"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {feature} = request.data;
      if (!feature || !VALID_FEATURES.includes(feature)) {
        throw new HttpsError(
            "invalid-argument",
            `feature must be one of: ${VALID_FEATURES.join(", ")}`,
        );
      }

      const tier = await fetchTier(uid);
      const {allowed, reason} = resolveFeature(feature, tier);

      return {allowed, tier, ...(reason ? {reason} : {})};
    },
);

// ─── getCreatorCatalogSettings (CF onCall) ──────────────────────────────────

const getCreatorCatalogSettings = onCall(
    {region: "us-central1"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const tier = await fetchTier(uid);
      const workLimit = WORK_LIMITS[tier] ?? 0;

      // Count published works
      const worksSnap = await db()
          .collection("catalogWorks")
          .where("creatorId", "==", uid)
          .where("status", "==", "published")
          .get();
      const workCount = worksSnap.size;

      // Pull connected source IDs from creator profile (best-effort)
      let connectedSources = [];
      try {
        const profileSnap = await db().collection("creatorProfiles").doc(uid).get();
        connectedSources = profileSnap.data()?.connectedSources || [];
      } catch {
        // non-fatal
      }

      const askEnabled =
        tier === "creator_pro" ||
        tier === "creator_studio" ||
        tier === "organization";

      const analyticsEnabled =
        tier === "creator_studio" || tier === "organization";

      return {
        tier,
        workCount,
        workLimit: workLimit === Infinity ? null : workLimit,
        askEnabled,
        analyticsEnabled,
        connectedSources,
      };
    },
);

// ─── createCatalogCheckoutSession (CF onCall) ────────────────────────────────

const createCatalogCheckoutSession = onCall(
    {region: "us-central1", secrets: ["STRIPE_SECRET_KEY"]},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {plan} = request.data; // 'creator_pro' | 'creator_studio'
      const validPlans = ["creator_pro", "creator_studio"];
      if (!plan || !validPlans.includes(plan)) {
        throw new HttpsError(
            "invalid-argument",
            `plan must be one of: ${validPlans.join(", ")}`,
        );
      }

      // Resolve Stripe Price ID from environment (never hardcode)
      const priceId =
        plan === "creator_pro"
          ? process.env.STRIPE_PRICE_CREATOR_PRO
          : process.env.STRIPE_PRICE_CREATOR_STUDIO;

      if (!priceId) {
        throw new HttpsError(
            "failed-precondition",
            `Stripe Price ID for plan '${plan}' is not configured`,
        );
      }

      const successUrl = process.env.STRIPE_CHECKOUT_SUCCESS_URL;
      const cancelUrl = process.env.STRIPE_CHECKOUT_CANCEL_URL;

      if (!successUrl || !cancelUrl) {
        throw new HttpsError("failed-precondition", "Checkout redirect URLs not configured");
      }

      const stripe = getStripe();

      const session = await stripe.checkout.sessions.create({
        mode: "subscription",
        line_items: [{price: priceId, quantity: 1}],
        success_url: `${successUrl}?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: cancelUrl,
        metadata: {amenUserId: uid, catalogPlan: plan},
        subscription_data: {
          metadata: {amenUserId: uid, catalogPlan: plan},
        },
      });

      // On success, the Stripe webhook (stripeWebhook.js) must update
      // users/{uid}/entitlements/platform tier to the purchased plan.
      return {sessionId: session.id, url: session.url};
    },
);

// ─── createWorkPaymentIntent (CF onCall) ─────────────────────────────────────

const createWorkPaymentIntent = onCall(
    {region: "us-central1", secrets: ["STRIPE_SECRET_KEY"]},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {workId, buyerId} = request.data;
      if (!workId || !buyerId) {
        throw new HttpsError("invalid-argument", "workId and buyerId are required");
      }

      // Verify caller is the buyer
      if (uid !== buyerId) {
        throw new HttpsError("permission-denied", "buyerId must match authenticated user");
      }

      // Load work document
      const workSnap = await db().collection("catalogWorks").doc(workId).get();
      if (!workSnap.exists) {
        throw new HttpsError("not-found", "Work not found");
      }
      const work = workSnap.data();

      // Verify work is published and monetized
      if (work.status !== "published") {
        throw new HttpsError("failed-precondition", "Work is not published");
      }
      if (work.visibility !== "paid_members") {
        throw new HttpsError(
            "failed-precondition",
            "Work is not configured for paid access",
        );
      }
      if (!work.priceAmountCents || work.priceAmountCents <= 0) {
        throw new HttpsError("failed-precondition", "Work has no valid price");
      }

      // Check buyer does not already have access
      const accessSnap = await db()
          .collection("users")
          .doc(buyerId)
          .collection("catalogAccess")
          .doc(workId)
          .get();
      if (accessSnap.exists) {
        throw new HttpsError("already-exists", "Buyer already has access to this work");
      }

      // Get creator's Stripe connected account
      const creatorProfileSnap = await db()
          .collection("creatorProfiles")
          .doc(work.creatorId)
          .get();
      const stripeAccountId = creatorProfileSnap.data()?.stripeConnectedAccountId;
      if (!stripeAccountId) {
        throw new HttpsError(
            "failed-precondition",
            "Creator has not set up payouts",
        );
      }

      // Calculate platform fee server-side
      const {platformFeeAmount, creatorProceeds} = calculatePlatformFee({
        amount: work.priceAmountCents,
        type: work.workType || "digital_product",
      });

      const stripe = getStripe();

      const paymentIntent = await stripe.paymentIntents.create({
        amount: work.priceAmountCents,
        currency: work.currency || "usd",
        application_fee_amount: platformFeeAmount,
        transfer_data: {destination: stripeAccountId},
        metadata: {
          workId,
          buyerId,
          creatorId: work.creatorId,
          workType: work.workType || "digital_product",
        },
      });

      // On payment confirmation the Stripe webhook calls grantCatalogAccess
      return {
        clientSecret: paymentIntent.client_secret,
        platformFee: platformFeeAmount,
        creatorProceeds,
      };
    },
);

// ─── Exports ─────────────────────────────────────────────────────────────────

module.exports = {
  // Cloud Functions (onCall)
  checkCatalogEntitlement,
  getCreatorCatalogSettings,
  createCatalogCheckoutSession,
  createWorkPaymentIntent,

  // Internal utilities (consumed by other CFs / webhook handlers)
  calculatePlatformFee,
  enforceWorkLimit,
  grantCatalogAccess,
};
