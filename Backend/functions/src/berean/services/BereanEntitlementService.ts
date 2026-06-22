/**
 * BereanEntitlementService.ts
 *
 * Authoritative server-side entitlement layer for Berean AI model selection.
 *
 * AUTHORITY MODEL:
 *   Reads from `userSubscriptions/{uid}` — a collection that is:
 *   - Write-restricted to Cloud Functions only (Firestore rules: no client write)
 *   - Written by subscription webhooks (RevenueCat, Stripe, manual grant)
 *   - NEVER read from client-supplied fields or bereanSettings/preferences.tier
 *
 * TIER RULES:
 *   free    → core only, 0 deep credits
 *   plus    → core + limited deep (100 credits/month)
 *   pro     → core + deep + adaptive (500 credits/month, when flag enabled)
 *   founder → all modes, 2000 credits/month
 */

import * as admin from "firebase-admin";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type BereanTier = "free" | "plus" | "pro" | "founder";
export type BereanModelMode = "core" | "deep" | "adaptive";

export interface BereanEntitlement {
  tier: BereanTier;
  deepCreditsRemaining: number;
  canUseDeep: boolean;
  canUseAdaptive: boolean;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Monthly deep credit budgets by tier. Applied when account is first created
 *  or at monthly reset (scheduled function). */
export const MONTHLY_DEEP_CREDIT_BUDGET: Record<BereanTier, number> = {
  free: 0,
  plus: 100,
  pro: 500,
  founder: 2000,
};

/** Credit units deducted per successful deep/adaptive generation. Core is free. */
export const MODE_CREDIT_COST: Record<BereanModelMode, number> = {
  core: 0,
  deep: 3,
  adaptive: 2,
};

/** Which Anthropic model tier to request per Berean mode. */
export const MODE_TO_MODEL: Record<BereanModelMode, "haiku" | "sonnet" | "opus"> = {
  core: "haiku",
  deep: "sonnet",
  adaptive: "haiku",   // adaptive routes internally; starts fast, escalates if needed
};

/** Concrete Anthropic model IDs. Swapped here to avoid scatter across the codebase. */
export const ANTHROPIC_MODELS = {
  haiku:  "claude-3-haiku-20240307",
  sonnet: "claude-3-5-sonnet-20241022",
  opus:   "claude-3-opus-20240229",
} as const;

// ---------------------------------------------------------------------------
// Core entitlement read
// ---------------------------------------------------------------------------

/**
 * Reads the user's authoritative entitlement from `userSubscriptions/{uid}`.
 *
 * Falls back to "free" / 0 credits if the document is missing — the
 * safe-by-default posture. Never trusts client-supplied tier values.
 */
export async function getBereanEntitlement(userId: string): Promise<BereanEntitlement> {
  const snap = await admin.firestore()
    .collection("userSubscriptions")
    .doc(userId)
    .get();

  const data = snap.data();
  const tier: BereanTier = isValidTier(data?.tier) ? (data!.tier as BereanTier) : "free";
  const deepCreditsRemaining: number =
    typeof data?.deepCreditsRemaining === "number"
      ? Math.max(0, data.deepCreditsRemaining)
      : 0;

  return {
    tier,
    deepCreditsRemaining,
    canUseDeep: tierCanAccessDeep(tier) && deepCreditsRemaining > 0,
    canUseAdaptive: tierCanAccessAdaptive(tier) && deepCreditsRemaining > 0,
  };
}

// ---------------------------------------------------------------------------
// Mode validation
// ---------------------------------------------------------------------------

/**
 * Returns true if the entitlement permits the requested mode.
 * This is the single source of truth for mode gating — call BEFORE generation.
 */
export function modeAllowedForEntitlement(
  mode: BereanModelMode,
  entitlement: BereanEntitlement
): boolean {
  switch (mode) {
    case "core":     return true;
    case "deep":     return entitlement.canUseDeep;
    case "adaptive": return entitlement.canUseAdaptive;
    default:         return false;
  }
}

/**
 * Returns whether the quota (credits) is the limiting factor vs. the tier itself.
 * Used to construct precise fallback reason strings.
 */
export function quotaIsLimitingFactor(
  mode: BereanModelMode,
  entitlement: BereanEntitlement
): boolean {
  if (mode === "core") return false;
  const tierCanAccess = mode === "adaptive"
    ? tierCanAccessAdaptive(entitlement.tier)
    : tierCanAccessDeep(entitlement.tier);
  return tierCanAccess && entitlement.deepCreditsRemaining === 0;
}

// ---------------------------------------------------------------------------
// Credit charging (call ONLY after successful response generation)
// ---------------------------------------------------------------------------

/**
 * Atomically deducts deep credits for the given mode after a successful generation.
 *
 * - Uses a Firestore transaction to prevent race conditions under concurrent requests.
 * - Core mode (cost = 0) is a no-op; returns -1 to signal "no charge applied".
 * - Returns the remaining credit balance after deduction.
 *
 * IMPORTANT: Call this ONLY after the LLM response is validated and returned.
 *            A failed or safety-blocked generation should NOT charge credits.
 */
export async function chargeDeepCredits(
  userId: string,
  mode: BereanModelMode
): Promise<number> {
  const cost = MODE_CREDIT_COST[mode];
  if (cost === 0) return -1;

  const ref = admin.firestore().collection("userSubscriptions").doc(userId);

  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current =
      typeof snap.data()?.deepCreditsRemaining === "number"
        ? (snap.data()!.deepCreditsRemaining as number)
        : 0;
    const updated = Math.max(0, current - cost);
    tx.update(ref, {
      deepCreditsRemaining: updated,
      lastChargedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastChargedMode: mode,
    });
    return updated;
  });
}

// ---------------------------------------------------------------------------
// Tier helpers (private — consistent single source of logic)
// ---------------------------------------------------------------------------

function tierCanAccessDeep(tier: BereanTier): boolean {
  return tier === "plus" || tier === "pro" || tier === "founder";
}

function tierCanAccessAdaptive(tier: BereanTier): boolean {
  return tier === "pro" || tier === "founder";
}

function isValidTier(value: unknown): value is BereanTier {
  return value === "free" || value === "plus" || value === "pro" || value === "founder";
}
