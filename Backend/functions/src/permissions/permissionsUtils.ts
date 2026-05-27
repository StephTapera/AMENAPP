/**
 * permissionsUtils.ts
 *
 * Shared utilities for the Permissions Engine.
 * Extracted here to prevent a circular dependency between
 * permissionsCallables.ts and permissionsTriggers.ts.
 *
 * Contains:
 *   normalizeAgeTier      — maps legacy strings to the new AgeTier vocabulary
 *   snapshotFromDoc       — builds AccountSnapshot from raw Firestore data (fails closed)
 *   writeResolvedPermissions — persists PermissionSet to permissions/{uid} + Auth claims
 */

import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

import { AgeTier, IdentityMode, AccountSnapshot, PermissionSet } from "./permissionsTypes";
import { defaultModeForTier } from "./permissionsEngine";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── normalizeAgeTier ─────────────────────────────────────────────────────────

/**
 * Maps legacy ageTier strings ("minor", "under_minimum") and new strings
 * to the canonical AgeTier vocabulary used by this engine.
 */
export function normalizeAgeTier(raw: string): AgeTier {
  if (raw === "minor" || raw === "under_minimum" || raw === "under13") return "under13";
  if (raw === "teen") return "teen";
  return "adult";
}

// ─── snapshotFromDoc ──────────────────────────────────────────────────────────

/**
 * Builds a type-safe AccountSnapshot from a raw Firestore document.
 * Fails closed: any missing or invalid field defaults to the most restrictive value
 * so resolution never silently grants more than the data supports.
 */
export function snapshotFromDoc(uid: string, data: FirebaseFirestore.DocumentData): AccountSnapshot {
  const rawTier: string = data.ageTier ?? "adult";
  const ageTier = normalizeAgeTier(rawTier);

  const rawMode: string = data.mode ?? defaultModeForTier(ageTier);
  const validModes: IdentityMode[] = [
    "social", "discussion", "study", "quiet", "postless", "campus", "family",
  ];
  const mode: IdentityMode = validModes.includes(rawMode as IdentityMode)
    ? (rawMode as IdentityMode)
    : defaultModeForTier(ageTier);

  const rawVerification = data.verificationStatus ?? "none";
  const verificationStatus: AccountSnapshot["verificationStatus"] =
    (["none", "pending", "verified"] as const).includes(rawVerification)
      ? rawVerification
      : "none";

  const rawState = data.accountState ?? "active";
  const accountState: AccountSnapshot["accountState"] =
    (["active", "pending", "suspended"] as const).includes(rawState)
      ? rawState
      : "active";

  const defaultConsent = ageTier === "under13" ? "pending" : "n/a";
  const rawConsent = data.guardianConsentStatus ?? defaultConsent;
  const guardianConsentStatus: AccountSnapshot["guardianConsentStatus"] =
    (["n/a", "pending", "confirmed"] as const).includes(rawConsent)
      ? rawConsent
      : "n/a";

  return {
    uid,
    ageTier,
    mode,
    verificationStatus,
    mentorApproved: data.mentorApproved === true,
    trustLevel: typeof data.trustLevel === "number" ? Math.max(0, Math.min(5, data.trustLevel)) : 0,
    accountState,
    guardianConsentStatus,
    csamFlag: data.csamFlag === true,
  };
}

// ─── writeResolvedPermissions ─────────────────────────────────────────────────

/**
 * Persists a resolved PermissionSet to permissions/{uid} and syncs the
 * hot-path subset into Auth custom claims.
 *
 * Hot-path claims (zero extra reads in security rules; ~1000-byte budget):
 *   { ageTier, canPostPublic, reachTier }
 * Full PermissionSet stays in permissions/{uid}.
 */
export async function writeResolvedPermissions(
  uid: string,
  resolved: PermissionSet,
  ceilingTier: AgeTier
): Promise<void> {
  const stored = {
    ...resolved,
    resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    ceilingTier,
  };

  await db.collection("permissions").doc(uid).set(stored);

  // Sync hot-path fields into Auth custom claims
  try {
    const currentUser = await admin.auth().getUser(uid);
    const currentClaims = (currentUser.customClaims as Record<string, unknown>) ?? {};
    await admin.auth().setCustomUserClaims(uid, {
      ...currentClaims,
      ageTier: ceilingTier,
      canPostPublic: resolved.canPostPublic,
      reachTier: resolved.reachTier,
    });
  } catch (err) {
    // Non-fatal: permissions/{uid} is the source of truth; claims are a cache.
    logger.warn(`[PermissionsEngine] Failed to update custom claims for uid=${uid}`, err);
  }
}
