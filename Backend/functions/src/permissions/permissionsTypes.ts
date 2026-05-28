/**
 * permissionsTypes.ts
 *
 * Shared types for the Amen Permissions Engine.
 * Consumed by permissionsEngine, permissionsCallables, and permissionsTriggers.
 *
 * AgeTier vocabulary deliberately differs from YouthSafetyService ("minor"|"teen"|"adult")
 * to avoid implicit aliasing. The resolver function reads the raw ageTier from users/{uid}
 * and normalizes it. Stored in permissions/{uid} as the new vocabulary.
 */

// ─── Core Types ───────────────────────────────────────────────────────────────

// v1 ships with teen + adult only. under13 (COPPA / Family Mode) is added in a future release.
export type AgeTier = "teen" | "adult";

export type IdentityMode =
  | "social"
  | "discussion"
  | "study"
  | "quiet"
  | "postless"
  | "campus"
  | "family";

/** Ordered least → most permissive: none < trustedOnly < mutualOnly < open */
export type DMPolicy = "none" | "trustedOnly" | "mutualOnly" | "open";

/** Ordered least → most permissive: restricted < normal < amplified */
export type ReachTier = "restricted" | "normal" | "amplified";

export interface PermissionSet {
  canPostPublic: boolean;
  canBeDiscovered: boolean;
  canCreateGroup: boolean;
  canUploadMedia: boolean;
  sendDM: DMPolicy;
  receiveDM: DMPolicy;
  reachTier: ReachTier;
  /** Pre-distribution human/quarantine hold — not the fast ML classifier which applies to all. */
  requiresPrePublishReview: boolean;
  /** Adult-side flag; default false. Only via verified + mentorApproved hard condition. */
  canContactMinors: boolean;
}

/** Fields read from users/{uid} to drive resolution. */
export interface AccountSnapshot {
  uid: string;
  ageTier: AgeTier;
  mode: IdentityMode;
  verificationStatus: "none" | "pending" | "verified";
  mentorApproved: boolean;
  /** 0–5 from ProgressiveTrustService — consumed here, not computed. */
  trustLevel: number;
  accountState: "active" | "pending" | "suspended";
  guardianConsentStatus: "n/a" | "pending" | "confirmed";
  /** Set by moderation module on CSAM/grooming signal. */
  csamFlag?: boolean;
}

/**
 * Shape of the document stored in permissions/{uid}.
 * resolvedAt is a Firestore server timestamp (admin.firestore.FieldValue.serverTimestamp()).
 * ceilingTier is preserved for invariant auditing.
 */
export interface StoredPermissionSet extends PermissionSet {
  resolvedAt: unknown; // Firestore server timestamp sentinel at write; Timestamp at read
  ceilingTier: AgeTier;
}
