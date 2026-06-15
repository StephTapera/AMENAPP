/**
 * catalogEntitlements.ts
 *
 * Server-side entitlement checks for the Catalog + Knowledge Network.
 * ALL access decisions are made here — never trust client-side claims.
 *
 * Tiers:
 *   free            – catalog browsing (public works only), 3 Ask This Creator/day
 *   creator_pro     – full catalog management, unlimited Ask This Creator,
 *                     affiliate links, up to 500 published works  ($19/mo)
 *   creator_studio  – everything + team members, advanced analytics,
 *                     course/event hosting, transcript search,
 *                     unlimited works ($49/mo)
 *   organization    – multi-creator org, verified org badge, bulk import,
 *                     community brain ($199+/mo — custom Stripe or sales)
 *
 * Firestore paths:
 *   users/{uid}/entitlements/catalog   — {tier, active, expiresAt}
 *   users/{uid}/entitlements/platform  — {tier} (legacy; also read for compat)
 *   catalogUsage/{uid}/dailyAsk        — {date, count} for free-tier rate limiting
 *
 * Deploy: us-east1 only (us-central1 quota exhausted as of 2026-06-13).
 * Add every function name to docs/FUNCTION_INVENTORY.md Interim Region Table.
 *
 * STRIPE_PRICE_CREATOR_PRO and STRIPE_PRICE_CREATOR_STUDIO must be set
 * as Firebase secrets before deploy:
 *   firebase functions:secrets:set STRIPE_PRICE_CREATOR_PRO
 *   firebase functions:secrets:set STRIPE_PRICE_CREATOR_STUDIO
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

// ─── Secrets ──────────────────────────────────────────────────────────────────

export const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
export const STRIPE_PRICE_CREATOR_PRO = defineSecret("STRIPE_PRICE_CREATOR_PRO");
export const STRIPE_PRICE_CREATOR_STUDIO = defineSecret("STRIPE_PRICE_CREATOR_STUDIO");

// ─── Constants ────────────────────────────────────────────────────────────────

const db = getFirestore();

// Region for all billing callables
const REGION = "us-east1";

export const CATALOG_TIERS = ["free", "creator_pro", "creator_studio", "organization"] as const;
export type CatalogTier = typeof CATALOG_TIERS[number];

// Free-tier daily limit for Ask This Creator
const FREE_ASK_DAILY_LIMIT = 3;

// Work count cap for creator_pro (studio+ is unlimited)
export const CREATOR_PRO_WORK_LIMIT = 500;

// ─── Tier rank helpers ────────────────────────────────────────────────────────

const TIER_RANK: Record<CatalogTier, number> = {
  free: 0,
  creator_pro: 1,
  creator_studio: 2,
  organization: 3,
};

/** True if the user's tier meets or exceeds the required tier. */
function meetsOrExceeds(userTier: CatalogTier, required: CatalogTier): boolean {
  return TIER_RANK[userTier] >= TIER_RANK[required];
}

// ─── Firestore helpers ────────────────────────────────────────────────────────

/**
 * Reads the authoritative catalog entitlement for a uid from Firestore.
 * Falls back to the legacy platform doc if catalog doc is absent.
 * Returns "free" on any error (fail-closed).
 */
async function getEntitlementTier(uid: string): Promise<CatalogTier> {
  try {
    // Primary path: users/{uid}/entitlements/catalog
    const catalogDoc = await db
      .collection("users")
      .doc(uid)
      .collection("entitlements")
      .doc("catalog")
      .get();

    if (catalogDoc.exists) {
      const data = catalogDoc.data()!;
      const active: boolean = data["active"] === true;
      if (!active) return "free";

      // Check expiry
      const expiresAt = data["expiresAt"] as Timestamp | null | undefined;
      if (expiresAt && expiresAt.toDate() < new Date()) return "free";

      const rawTier = data["tier"] as string | undefined;
      if (rawTier && CATALOG_TIERS.includes(rawTier as CatalogTier)) {
        return rawTier as CatalogTier;
      }
    }

    // Legacy fallback: users/{uid}/entitlements/platform
    const platformDoc = await db
      .collection("users")
      .doc(uid)
      .collection("entitlements")
      .doc("platform")
      .get();

    if (platformDoc.exists) {
      const rawTier = platformDoc.data()?.["tier"] as string | undefined;
      if (rawTier && CATALOG_TIERS.includes(rawTier as CatalogTier)) {
        return rawTier as CatalogTier;
      }
    }

    return "free";
  } catch (err) {
    logger.warn("getEntitlementTier: error reading Firestore; defaulting to free", { uid, err });
    return "free";
  }
}

/**
 * Returns today's ISO date string (YYYY-MM-DD) in UTC for usage-bucketing.
 */
function todayUTC(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * Increments and checks the daily Ask This Creator usage counter for a free-tier user.
 * Returns true if the user is within the free limit (i.e. allowed).
 * Uses a Firestore transaction to prevent races.
 */
async function checkAndIncrementFreeTierAsk(uid: string): Promise<boolean> {
  const today = todayUTC();
  const ref = db.collection("catalogUsage").doc(uid).collection("dailyAsk").doc(today);

  try {
    const allowed = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const current: number = snap.exists ? (snap.data()?.["count"] as number ?? 0) : 0;
      if (current >= FREE_ASK_DAILY_LIMIT) {
        return false;
      }
      tx.set(
        ref,
        { date: today, count: FieldValue.increment(1), uid },
        { merge: true }
      );
      return true;
    });
    return allowed;
  } catch (err) {
    logger.warn("checkAndIncrementFreeTierAsk: transaction failed; allowing (fail-open for UX)", {
      uid,
      err,
    });
    // Fail-open here only for rate-limiting (not a security gate): if Firestore
    // is momentarily unavailable we prefer a slightly-over-limit UX over blocking
    // a real question. The real security gate is CF auth.
    return true;
  }
}

// ─── checkCatalogEntitlement — authoritative gate ─────────────────────────────

interface CheckEntitlementInput {
  feature:
    | "catalog_read"
    | "ask_creator"
    | "catalog_create"
    | "knowledge_map"
    | "team_members"
    | "org_features"
    | "transcript_search"
    | "unlimited_works"
    | "deep_link"; // Always allowed — never gate
}

interface CheckEntitlementOutput {
  allowed: boolean;
  tier: CatalogTier;
  reason?: string;
  /** For ask_creator on free tier: remaining queries today. */
  remainingFreeTierAsks?: number;
}

/**
 * Authoritative server-side entitlement gate for Catalog features.
 * Called by iOS CatalogEntitlementService before showing locked UI.
 *
 * Deep-links (listen/buy/watch) are ALWAYS allowed — never gated.
 * free tier: catalog_read allowed; ask_creator allowed up to 3/day.
 */
export const checkCatalogEntitlement = onCall(
  { region: REGION, secrets: [] },
  async (req): Promise<CheckEntitlementOutput> => {
    if (!req.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const uid = req.auth.uid;
    const data = req.data as CheckEntitlementInput;
    const feature = data?.feature;

    if (!feature) {
      throw new HttpsError("invalid-argument", "feature is required.");
    }

    // Deep-links are unconditionally free — never gate buy/listen/watch
    if (feature === "deep_link" || feature === "catalog_read") {
      const tier = await getEntitlementTier(uid);
      return { allowed: true, tier };
    }

    const tier = await getEntitlementTier(uid);

    // ask_creator: creator_pro+ OR free tier with daily quota
    if (feature === "ask_creator") {
      if (meetsOrExceeds(tier, "creator_pro")) {
        return { allowed: true, tier };
      }
      // Free tier: check daily limit
      const withinLimit = await checkAndIncrementFreeTierAsk(uid);
      if (withinLimit) {
        // Return remaining count (best-effort; may be approximate)
        const today = todayUTC();
        let remaining = FREE_ASK_DAILY_LIMIT - 1;
        try {
          const snap = await db
            .collection("catalogUsage")
            .doc(uid)
            .collection("dailyAsk")
            .doc(today)
            .get();
          remaining = Math.max(0, FREE_ASK_DAILY_LIMIT - (snap.data()?.["count"] as number ?? 1));
        } catch {
          // ignore
        }
        return { allowed: true, tier, remainingFreeTierAsks: remaining };
      }
      return {
        allowed: false,
        tier,
        reason: "free_tier_daily_limit",
        remainingFreeTierAsks: 0,
      };
    }

    // catalog_create, affiliate_links: creator_pro+
    if (feature === "catalog_create") {
      const allowed = meetsOrExceeds(tier, "creator_pro");
      return { allowed, tier, reason: allowed ? undefined : "requires_creator_pro" };
    }

    // knowledge_map, transcript_search, unlimited_works: creator_studio+
    if (
      feature === "knowledge_map" ||
      feature === "transcript_search" ||
      feature === "unlimited_works"
    ) {
      const allowed = meetsOrExceeds(tier, "creator_studio");
      return { allowed, tier, reason: allowed ? undefined : "requires_creator_studio" };
    }

    // team_members: creator_studio+
    if (feature === "team_members") {
      const allowed = meetsOrExceeds(tier, "creator_studio");
      return { allowed, tier, reason: allowed ? undefined : "requires_creator_studio" };
    }

    // org_features: organization only
    if (feature === "org_features") {
      const allowed = tier === "organization";
      return { allowed, tier, reason: allowed ? undefined : "requires_organization" };
    }

    // Unknown feature — fail-closed
    logger.warn("checkCatalogEntitlement: unknown feature requested", { uid, feature });
    return { allowed: false, tier, reason: "unknown_feature" };
  }
);

// ─── createCatalogCheckoutSession — Stripe checkout ──────────────────────────

interface CheckoutInput {
  /** "creator_pro" | "creator_studio" */
  targetTier: "creator_pro" | "creator_studio";
  successUrl: string;
  cancelUrl: string;
}

interface CheckoutOutput {
  url: string;
}

/**
 * Creates a Stripe Checkout Session for a catalog subscription upgrade.
 * Organization tier is enterprise/sales-only — not available via this CF.
 *
 * DEPLOY STEP: Secrets must be set before first deploy:
 *   firebase functions:secrets:set STRIPE_SECRET_KEY
 *   firebase functions:secrets:set STRIPE_PRICE_CREATOR_PRO    (Stripe price ID: price_xxx)
 *   firebase functions:secrets:set STRIPE_PRICE_CREATOR_STUDIO (Stripe price ID: price_xxx)
 */
export const createCatalogCheckoutSession = onCall(
  {
    region: REGION,
    secrets: [STRIPE_SECRET_KEY, STRIPE_PRICE_CREATOR_PRO, STRIPE_PRICE_CREATOR_STUDIO],
  },
  async (req): Promise<CheckoutOutput> => {
    if (!req.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const uid = req.auth.uid;
    const data = req.data as CheckoutInput;

    if (data.targetTier !== "creator_pro" && data.targetTier !== "creator_studio") {
      throw new HttpsError(
        "invalid-argument",
        "targetTier must be creator_pro or creator_studio. Organization tier is available via sales."
      );
    }

    const stripeKey = STRIPE_SECRET_KEY.value();
    if (!stripeKey) {
      logger.error("createCatalogCheckoutSession: STRIPE_SECRET_KEY not available");
      throw new HttpsError("internal", "Payment service unavailable.");
    }

    const priceId =
      data.targetTier === "creator_pro"
        ? STRIPE_PRICE_CREATOR_PRO.value()
        : STRIPE_PRICE_CREATOR_STUDIO.value();

    if (!priceId) {
      logger.error("createCatalogCheckoutSession: Stripe price ID secret not set", {
        targetTier: data.targetTier,
      });
      throw new HttpsError("internal", "Payment service misconfigured. Contact support.");
    }

    // Read user email for Stripe customer (best-effort)
    let customerEmail: string | undefined;
    try {
      const userDoc = await db.collection("users").doc(uid).get();
      customerEmail = userDoc.data()?.["email"] as string | undefined;
    } catch {
      // Non-fatal: Stripe will allow checkout without pre-filling email
    }

    // Call Stripe API
    const body: Record<string, unknown> = {
      mode: "subscription",
      line_items: [{ price: priceId, quantity: 1 }],
      success_url: data.successUrl,
      cancel_url: data.cancelUrl,
      client_reference_id: uid,
      metadata: { uid, targetTier: data.targetTier },
    };
    if (customerEmail) {
      body.customer_email = customerEmail;
    }

    const stripeResponse = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${stripeKey}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams(
        Object.entries(body).flatMap(([k, v]) =>
          typeof v === "object"
            ? (v as Array<Record<string, unknown>>).flatMap((item, i) =>
                Object.entries(item).map(([ik, iv]) => [`${k}[${i}][${ik}]`, String(iv)])
              )
            : [[k, String(v)]]
        )
      ).toString(),
      signal: AbortSignal.timeout(15_000),
    });

    if (!stripeResponse.ok) {
      const errText = await stripeResponse.text().catch(() => "(unreadable)");
      logger.error("createCatalogCheckoutSession: Stripe error", {
        uid,
        status: stripeResponse.status,
        body: errText,
      });
      throw new HttpsError("internal", "Payment service returned an error.");
    }

    const session = (await stripeResponse.json()) as { url?: string };
    if (!session.url) {
      throw new HttpsError("internal", "Stripe did not return a checkout URL.");
    }

    // Audit log
    await db.collection("billingAudit").add({
      uid,
      event: "checkout_session_created",
      targetTier: data.targetTier,
      stripeSessionUrl: session.url,
      createdAt: FieldValue.serverTimestamp(),
    });

    return { url: session.url };
  }
);
