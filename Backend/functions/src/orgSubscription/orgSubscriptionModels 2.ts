/**
 * orgSubscriptionModels.ts
 *
 * Canonical tier + module definitions for the Org Subscription system.
 * Both `createOrgSubscriptionCheckout` and `stripeOrgWebhook` import from here.
 *
 * Stripe Price IDs are read from Firebase secrets at function runtime:
 *   firebase functions:secrets:set STRIPE_ORG_PLUS_PRICE_ID
 *   firebase functions:secrets:set STRIPE_ORG_PRO_PRICE_ID
 */

import type * as admin from "firebase-admin";

// ── Tier types ────────────────────────────────────────────────────────────────

export type OrgBillingTier = "free" | "plus" | "pro";
export type OrgBillingStatus = "active" | "trialing" | "past_due" | "canceled" | "unknown";

// ── Stripe price ID map ───────────────────────────────────────────────────────
// Read at runtime so secrets are never baked into the bundle.
export function getTierPrices(): Record<OrgBillingTier, string> {
    return {
        free: "",
        plus: process.env.STRIPE_ORG_PLUS_PRICE_ID ?? "",
        pro:  process.env.STRIPE_ORG_PRO_PRICE_ID  ?? "",
    };
}

/**
 * Resolve the OrgBillingTier for a given Stripe Price ID.
 * Used by the webhook to map subscription.items.data[0].price.id → tier.
 */
export function tierFromPriceId(priceId: string): OrgBillingTier | null {
    const prices = getTierPrices();
    for (const [tier, pid] of Object.entries(prices)) {
        if (pid && pid === priceId) return tier as OrgBillingTier;
    }
    return null;
}

// ── Module unlock table (mirrors AmenOrganizationBillingPlan.unlockedModules) ─

export const TIER_UNLOCKED_MODULES: Record<OrgBillingTier, string[]> = {
    free: [
        "heroBanner",
        "identityHeader",
        "safetyTransparency",
        "adminTools",
    ],
    plus: [
        "heroBanner",
        "identityHeader",
        "safetyTransparency",
        "adminTools",
        "spacesPreview",
        "eventsPreview",
        "schoolNotesPreview",
        "smartNotesPreview",
        "giving",
    ],
    pro: [
        "heroBanner",
        "identityHeader",
        "safetyTransparency",
        "adminTools",
        "spacesPreview",
        "eventsPreview",
        "schoolNotesPreview",
        "smartNotesPreview",
        "giving",
        "mediaPreview",
        "analytics",
    ],
};

// ── Billing status from Stripe subscription status ────────────────────────────

export function orgBillingStatusFromStripe(
    stripeStatus: string
): OrgBillingStatus {
    switch (stripeStatus) {
        case "active":    return "active";
        case "trialing":  return "trialing";
        case "past_due":  return "past_due";
        case "canceled":  return "canceled";
        default:          return "unknown";
    }
}

// ── Is access granted for a given billing status? ────────────────────────────

export function isGrantingOrgAccess(status: OrgBillingStatus): boolean {
    return status === "active" || status === "trialing";
}

// ── Firestore paths ───────────────────────────────────────────────────────────

export const ORG_BILLING_DOC = "subscription"; // organizations/{orgId}/billing/subscription

export function orgBillingRef(
    db: admin.firestore.Firestore,
    orgId: string
): admin.firestore.DocumentReference {
    return db
        .collection("organizations").doc(orgId)
        .collection("billing").doc(ORG_BILLING_DOC);
}
