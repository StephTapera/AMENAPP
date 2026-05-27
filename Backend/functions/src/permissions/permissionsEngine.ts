/**
 * permissionsEngine.ts
 *
 * Single source of truth for resolving what an Amen account is allowed to do.
 * Consumes: ageTier, identityMode, trustLevel, verificationStatus, accountState.
 * Produces:  PermissionSet (stored in permissions/{uid} and Auth custom claims).
 *
 * Resolution order (§1):
 *   effective = applyHardOverrides(
 *                 applyTrustModifiers(
 *                   intersect(ageTierCeiling(tier), modeGrant(mode)),
 *                   account, ceiling),
 *                 account)
 *
 * Key rule: a mode can only narrow permissions, never grant more than the
 * age-tier ceiling. Trust can raise, but only up to that same ceiling.
 * Hard overrides win over everything and run last.
 *
 * Safety invariants (§9) — all verified by permissionsEngine.test.ts:
 *   1. effective ⊆ ceiling(ageTier) — no field exceeds the tier ceiling
 *   2. under13 ⇒ !canPostPublic ∧ !canBeDiscovered ∧ sendDM ≤ trustedOnly
 *   3. teen ⇒ reachTier ≤ normal ∧ sendDM ≤ trustedOnly ∧ receiveDM ≤ trustedOnly
 *   4. Recipient is minor + sender is adult ⇒ canMessage false unless canContactMinors ∧ trustEdge
 *   5. canContactMinors === true ⇒ verified ∧ mentorApproved
 *   6. Mode change never produces a field above ceiling(ageTier)
 *   7. Active strike or CSAM flag ⇒ all permissions at restricted base
 *   8. under13 + guardianConsentStatus !== 'confirmed' ⇒ zero capabilities
 */

import {
  AgeTier,
  IdentityMode,
  DMPolicy,
  ReachTier,
  PermissionSet,
  AccountSnapshot,
} from "./permissionsTypes";

// ─── Ordering helpers ─────────────────────────────────────────────────────────

const DM_ORDER: Record<DMPolicy, number> = {
  none: 0, trustedOnly: 1, mutualOnly: 2, open: 3,
};
const REACH_ORDER: Record<ReachTier, number> = {
  restricted: 0, normal: 1, amplified: 2,
};

export function minDMPolicy(a: DMPolicy, b: DMPolicy): DMPolicy {
  return DM_ORDER[a] <= DM_ORDER[b] ? a : b;
}
export function maxDMPolicy(a: DMPolicy, b: DMPolicy): DMPolicy {
  return DM_ORDER[a] >= DM_ORDER[b] ? a : b;
}
function minReach(a: ReachTier, b: ReachTier): ReachTier {
  return REACH_ORDER[a] <= REACH_ORDER[b] ? a : b;
}
function maxReach(a: ReachTier, b: ReachTier): ReachTier {
  return REACH_ORDER[a] >= REACH_ORDER[b] ? a : b;
}

// ─── Restricted base — used by hard overrides ─────────────────────────────────

/** The floor every suspended / CSAM-flagged / unconfirmed-minor account lands on. */
const RESTRICTED_BASE: PermissionSet = {
  canPostPublic: false,
  canBeDiscovered: false,
  canCreateGroup: false,
  canUploadMedia: false,
  sendDM: "none",
  receiveDM: "none",
  reachTier: "restricted",
  requiresPrePublishReview: true,
  canContactMinors: false,
};

// ─── §3 Age-tier ceilings ─────────────────────────────────────────────────────

/**
 * Maximum any account at this tier may ever reach, regardless of mode or trust.
 * The under13/teen DM cap at trustedOnly is a hard ceiling — no path raises it.
 */
export function ageTierCeiling(tier: AgeTier): PermissionSet {
  switch (tier) {
  case "under13":
    return {
      canPostPublic: false,
      canBeDiscovered: false,
      canCreateGroup: false,
      canUploadMedia: false,
      sendDM: "trustedOnly",
      receiveDM: "trustedOnly",
      reachTier: "restricted",
      requiresPrePublishReview: true,
      canContactMinors: false,
    };

  case "teen":
    // Ceiling permits canPostPublic; postless mode is the default that suppresses it.
    // Public posts for teens are always pre-reviewed and never amplified.
    return {
      canPostPublic: true,
      canBeDiscovered: false, // discoverable only within trusted contexts (handled by trust graph)
      canCreateGroup: false,
      canUploadMedia: true,
      sendDM: "trustedOnly", // hard ceiling — no trust/mode can exceed this for teens
      receiveDM: "trustedOnly",
      reachTier: "normal",
      requiresPrePublishReview: true,
      canContactMinors: false,
    };

  case "adult":
    return {
      canPostPublic: true,
      canBeDiscovered: true,
      canCreateGroup: true,
      canUploadMedia: true,
      sendDM: "open",
      receiveDM: "open",
      reachTier: "amplified",
      requiresPrePublishReview: false, // adults still pass fast classifier; no human hold
      canContactMinors: false, // only raised via §5 hard condition
    };
  }
}

// ─── §4 Mode grants ───────────────────────────────────────────────────────────

/**
 * The maximum this mode would ever want — ceiling clamps anything
 * inappropriate for the account's age tier.
 */
export function modeGrant(mode: IdentityMode): PermissionSet {
  switch (mode) {
  case "social":
    return {
      canPostPublic: true,
      canBeDiscovered: true,
      canCreateGroup: true,
      canUploadMedia: true,
      sendDM: "open",
      receiveDM: "open",
      reachTier: "amplified",
      requiresPrePublishReview: false,
      canContactMinors: false,
    };

  case "discussion":
    return {
      canPostPublic: false,
      canBeDiscovered: true,
      canCreateGroup: false,
      canUploadMedia: true,
      sendDM: "trustedOnly",
      receiveDM: "mutualOnly",
      reachTier: "normal",
      requiresPrePublishReview: false,
      canContactMinors: false,
    };

  case "study":
    return {
      canPostPublic: false,
      canBeDiscovered: false,
      canCreateGroup: false,
      canUploadMedia: true,
      sendDM: "trustedOnly",
      receiveDM: "trustedOnly",
      reachTier: "normal",
      requiresPrePublishReview: false,
      canContactMinors: false,
    };

  case "quiet":
    return {
      canPostPublic: false,
      canBeDiscovered: false,
      canCreateGroup: false,
      canUploadMedia: false,
      sendDM: "trustedOnly",
      receiveDM: "trustedOnly",
      reachTier: "restricted",
      requiresPrePublishReview: false,
      canContactMinors: false,
    };

  case "postless":
    // Default for minors and recommended default for adults. Exists without broadcasting.
    return {
      canPostPublic: false,
      canBeDiscovered: false,
      canCreateGroup: false,
      canUploadMedia: false,
      sendDM: "trustedOnly",
      receiveDM: "trustedOnly",
      reachTier: "restricted",
      requiresPrePublishReview: false,
      canContactMinors: false,
    };

  case "campus":
    return {
      canPostPublic: true,
      canBeDiscovered: true,
      canCreateGroup: false,
      canUploadMedia: true,
      sendDM: "mutualOnly",
      receiveDM: "mutualOnly",
      reachTier: "normal",
      requiresPrePublishReview: false,
      canContactMinors: false,
    };

  case "family":
    return {
      canPostPublic: false,
      canBeDiscovered: false,
      canCreateGroup: false,
      canUploadMedia: false,
      sendDM: "trustedOnly",
      receiveDM: "trustedOnly",
      reachTier: "restricted",
      requiresPrePublishReview: false,
      canContactMinors: false,
    };
  }
}

// ─── §1 Intersect ─────────────────────────────────────────────────────────────

/**
 * Takes the more restrictive value for every field.
 * Boolean capabilities: AND (true = more permissive, false wins).
 * Boolean restrictions: OR (true = more restrictive, true wins).
 * Ordered enums: min of the two (lower index = more restrictive).
 */
function intersect(ceiling: PermissionSet, grant: PermissionSet): PermissionSet {
  return {
    canPostPublic: ceiling.canPostPublic && grant.canPostPublic,
    canBeDiscovered: ceiling.canBeDiscovered && grant.canBeDiscovered,
    canCreateGroup: ceiling.canCreateGroup && grant.canCreateGroup,
    canUploadMedia: ceiling.canUploadMedia && grant.canUploadMedia,
    sendDM: minDMPolicy(ceiling.sendDM, grant.sendDM),
    receiveDM: minDMPolicy(ceiling.receiveDM, grant.receiveDM),
    reachTier: minReach(ceiling.reachTier, grant.reachTier),
    // requiresPrePublishReview: restriction, OR gives the more restrictive result
    requiresPrePublishReview: ceiling.requiresPrePublishReview || grant.requiresPrePublishReview,
    canContactMinors: ceiling.canContactMinors && grant.canContactMinors,
  };
}

// ─── §1 Trust modifiers ───────────────────────────────────────────────────────

/**
 * Maps trustLevel (0–5) to the maximum values trust alone can earn.
 * Mirrors ProgressiveTrustService capability unlocks for PermissionSet fields.
 */
function trustEarned(trustLevel: number): Partial<PermissionSet> {
  const earned: Partial<PermissionSet> = {};

  if (trustLevel >= 1) {
    earned.canPostPublic = true;
    earned.reachTier = "normal";
  }
  if (trustLevel >= 2) {
    earned.canUploadMedia = true;
    earned.sendDM = "mutualOnly";
    earned.receiveDM = "mutualOnly";
  }
  if (trustLevel >= 3) {
    earned.sendDM = "open";
    earned.receiveDM = "open";
    earned.reachTier = "amplified";
  }
  if (trustLevel >= 4) {
    earned.canCreateGroup = true;
    earned.canBeDiscovered = true;
  }

  return earned;
}

/**
 * Raises each field to the trust-earned value, then clamps to the ceiling.
 * Formula per §1: min(ceiling, max(effective, earned)).
 * canContactMinors is never raised here — only via §5 hard condition.
 */
export function applyTrustModifiers(
  perms: PermissionSet,
  account: AccountSnapshot,
  ceiling: PermissionSet
): PermissionSet {
  const earned = trustEarned(account.trustLevel);
  const result: PermissionSet = { ...perms };

  if (earned.canPostPublic !== undefined) {
    result.canPostPublic = ceiling.canPostPublic && (perms.canPostPublic || earned.canPostPublic);
  }
  if (earned.canBeDiscovered !== undefined) {
    result.canBeDiscovered = ceiling.canBeDiscovered && (perms.canBeDiscovered || earned.canBeDiscovered);
  }
  if (earned.canCreateGroup !== undefined) {
    result.canCreateGroup = ceiling.canCreateGroup && (perms.canCreateGroup || earned.canCreateGroup);
  }
  if (earned.canUploadMedia !== undefined) {
    result.canUploadMedia = ceiling.canUploadMedia && (perms.canUploadMedia || earned.canUploadMedia);
  }
  if (earned.sendDM !== undefined) {
    result.sendDM = minDMPolicy(ceiling.sendDM, maxDMPolicy(perms.sendDM, earned.sendDM));
  }
  if (earned.receiveDM !== undefined) {
    result.receiveDM = minDMPolicy(ceiling.receiveDM, maxDMPolicy(perms.receiveDM, earned.receiveDM));
  }
  if (earned.reachTier !== undefined) {
    result.reachTier = minReach(ceiling.reachTier, maxReach(perms.reachTier, earned.reachTier));
  }

  return result;
}

// ─── §5 Hard overrides ────────────────────────────────────────────────────────

/**
 * Non-negotiable overrides applied last, in this order:
 *  1. under13 without confirmed guardian consent → zero capabilities (pending state)
 *  2. Suspended account → restricted base (no post, no DM, no discovery)
 *  3. CSAM/grooming flag → same restricted base + caller should emit escalation event
 *  4. Adult→minor contact gate: canContactMinors true only if verified + mentorApproved
 *
 * Items 1-3 return early so item 4 never fires on locked accounts.
 */
export function applyHardOverrides(
  perms: PermissionSet,
  account: AccountSnapshot
): PermissionSet {
  // 1. under13 without confirmed guardian consent — zero capabilities
  if (account.ageTier === "under13" && account.guardianConsentStatus !== "confirmed") {
    return { ...RESTRICTED_BASE };
  }

  // 2 + 3. Active suspension or CSAM flag
  if (account.accountState === "suspended" || account.csamFlag === true) {
    return { ...RESTRICTED_BASE };
  }

  const result: PermissionSet = { ...perms };

  // 4. canContactMinors: positive conditional grant — never default, never from mode/trust
  result.canContactMinors =
    account.ageTier === "adult" &&
    account.verificationStatus === "verified" &&
    account.mentorApproved === true;

  return result;
}

// ─── Main resolver ─────────────────────────────────────────────────────────────

/**
 * Resolves the effective PermissionSet for an account.
 * Called by Firestore triggers, scheduled functions, and the resolvePermissions callable.
 */
export function resolvePermissions(account: AccountSnapshot): PermissionSet {
  const ceiling = ageTierCeiling(account.ageTier);
  const grant = modeGrant(account.mode);
  const afterIntersect = intersect(ceiling, grant);
  const afterTrust = applyTrustModifiers(afterIntersect, account, ceiling);
  return applyHardOverrides(afterTrust, account);
}

// ─── §6 Pairwise messaging eligibility ───────────────────────────────────────

/**
 * Server-side check run inside initiateDM callable.
 * Guarantees no stranger contact for minors, ever.
 *
 * trustEdgeExists is satisfied by: guardian-approved contact, verified mentor
 * in an approved shared space, or mutual membership in a verified trusted group.
 * mutualConnectionExists: bilateral follow relationship.
 *
 * This function is pure — callers supply the edge booleans from the trust graph.
 */
export function canMessage(
  senderPerms: PermissionSet,
  senderAgeTier: AgeTier,
  recipientPerms: PermissionSet,
  recipientAgeTier: AgeTier,
  trustEdgeExists: boolean,
  mutualConnectionExists: boolean
): boolean {
  if (senderPerms.sendDM === "none") return false;
  if (recipientPerms.receiveDM === "none") return false;

  const recipientIsMinor = recipientAgeTier !== "adult";

  // Hard rule: adult → minor requires explicit canContactMinors AND a trust edge.
  if (recipientIsMinor && senderAgeTier === "adult") {
    if (!senderPerms.canContactMinors) return false;
    if (!trustEdgeExists) return false;
  }

  // trustedOnly / mutualOnly enforcement on recipient side
  if (recipientPerms.receiveDM === "trustedOnly") return trustEdgeExists;
  if (recipientPerms.receiveDM === "mutualOnly") return mutualConnectionExists;

  return true; // open
}

// ─── Allowed modes per tier ───────────────────────────────────────────────────

const ALLOWED_MODES: Record<AgeTier, IdentityMode[]> = {
  under13: ["postless", "family"],
  teen: ["postless", "discussion", "study", "quiet", "campus", "family"],
  adult: ["social", "discussion", "study", "quiet", "postless", "campus", "family"],
};

export function isModeAllowedForTier(mode: IdentityMode, tier: AgeTier): boolean {
  return ALLOWED_MODES[tier].includes(mode);
}

export function defaultModeForTier(tier: AgeTier): IdentityMode {
  if (tier === "under13") return "family";
  if (tier === "teen") return "postless";
  return "postless"; // recommended default: let adults opt into broadcasting
}
