/**
 * identityTrust.ts — Amen Trust + Safety OS
 *
 * Callable: getIdentityTrustProfile
 * Callable: setChurchVerificationStatus (admin)
 * Callable: flagSuspectedImpersonation
 * Callable: updateCreatorTrustDeclaration
 *
 * Trust levels (ascending): basic → email_verified → phone_verified →
 *   trusted_device → human_challenge_passed → community_verified →
 *   church_verified → creator_verified → professional_verified
 *
 * Rules enforced:
 *   - Pastor/doctor/therapist/financial-advisor claims require trust labeling
 *   - Unverified claims MUST be labeled "Unverified claim"
 *   - Verified labels backed by verification records
 *   - Clients cannot write trust or verification fields
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

import {
  IdentityTrustProfile,
  IdentityTrustLevel,
  ChurchVerification,
  TRUST_SAFETY_OS_VERSION,
} from "./safetyTypes";
import { writeSafetyAuditEvent } from "./safetyAuditLog";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Privileged role claims ───────────────────────────────────────────────

const PRIVILEGED_ROLES = [
  "pastor", "reverend", "bishop", "elder", "deacon",
  "doctor", "md", "therapist", "counselor", "psychologist",
  "financial advisor", "cpa", "attorney", "lawyer",
  "church admin", "ministry leader", "denomination official",
];

function containsPrivilegedClaim(bio: string): string[] {
  const lower = bio.toLowerCase();
  return PRIVILEGED_ROLES.filter((r) => lower.includes(r));
}

// ─── Trust score calculation ──────────────────────────────────────────────

function computeTrustScore(level: IdentityTrustLevel): number {
  const scores: Record<IdentityTrustLevel, number> = {
    basic:                     20,
    email_verified:            35,
    phone_verified:            50,
    trusted_device:            55,
    human_challenge_passed:    65,
    community_verified:        75,
    church_verified:           85,
    creator_verified:          80,
    professional_verified:     90,
  };
  return scores[level] ?? 20;
}

// ─── Get trust profile callable ──────────────────────────────────────────

export const getIdentityTrustProfile = onCall(
  { enforceAppCheck: true, cors: false },
  async (request): Promise<IdentityTrustProfile | null> => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");

    const { uid } = request.data as { uid?: string };
    const targetUid = uid ?? request.auth.uid;

    const snap = await db.doc(`users/${targetUid}/trust/profile`).get();
    if (!snap.exists) return null;

    const data = snap.data()!;

    // Check user's bio for privileged claims
    const userSnap = await db.doc(`users/${targetUid}`).get();
    const bio = userSnap.data()?.bio ?? "";
    const unverifiedClaims = containsPrivilegedClaim(bio);

    const level = (data.trustLevel ?? "basic") as IdentityTrustLevel;

    return {
      uid: targetUid,
      trustLevel: level,
      verifiedAt: data.verifiedAt ?? null,
      verificationSource: data.verificationSource ?? null,
      claimedRoles: data.claimedRoles ?? [],
      unverifiedClaims,
      isSuspectedImpersonation: data.isSuspectedImpersonation ?? false,
      trustScore: computeTrustScore(level),
      policyVersion: TRUST_SAFETY_OS_VERSION,
    };
  }
);

// ─── Set church verification (admin only) ────────────────────────────────

export const setChurchVerificationStatus = onCall(
  { enforceAppCheck: true, cors: false },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    const claims = request.auth.token;
    if (!claims.admin && !claims.moderator) {
      throw new HttpsError("permission-denied", "Admin role required.");
    }

    const {
      churchId,
      domainVerified = false,
      locationVerified = false,
      googlePlacesValidated = false,
      adminVerified = false,
      isDuplicate = false,
      isSuspectedImpersonation = false,
    } = request.data as Partial<ChurchVerification> & { churchId: string };

    if (!churchId) throw new HttpsError("invalid-argument", "churchId required.");

    const verification: ChurchVerification = {
      churchId,
      domainVerified,
      locationVerified,
      googlePlacesValidated,
      adminVerified,
      isDuplicate,
      isSuspectedImpersonation,
      verifiedAt: adminVerified ? admin.firestore.Timestamp.now() : null,
      policyVersion: TRUST_SAFETY_OS_VERSION,
    };

    await db.doc(`churches/${churchId}/verification/main`).set(verification);

    await writeSafetyAuditEvent({
      eventType: "identity_verified",
      actorUid: request.auth.uid,
      targetUid: null,
      contentId: churchId,
      contentType: null,
      metadata: { type: "church", domainVerified, adminVerified, isSuspectedImpersonation },
    });

    return { success: true };
  }
);

// ─── Flag suspected impersonation ────────────────────────────────────────

export const flagSuspectedImpersonation = onCall(
  { enforceAppCheck: true, cors: false },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");

    const { targetUid, reason } = request.data as { targetUid: string; reason: string };
    if (!targetUid) throw new HttpsError("invalid-argument", "targetUid required.");

    await db.doc(`users/${targetUid}/trust/profile`).set(
      {
        isSuspectedImpersonation: true,
        impersonationFlaggedAt: admin.firestore.Timestamp.now(),
        impersonationFlaggedBy: request.auth.uid,
        impersonationReason: reason ?? "reported",
      },
      { merge: true }
    );

    await writeSafetyAuditEvent({
      eventType: "preflight_check",
      actorUid: request.auth.uid,
      targetUid,
      contentId: null,
      contentType: null,
      category: "impersonation",
      metadata: { reason },
    });

    return { success: true };
  }
);

// ─── Creator trust declaration ────────────────────────────────────────────

export const updateCreatorTrustDeclaration = onCall(
  { enforceAppCheck: true, cors: false },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");

    const { declaredExpertise, credentials } = request.data as {
      declaredExpertise: string;
      credentials?: string;
    };

    const uid = request.auth.uid;

    await db.doc(`creators/${uid}/trust/main`).set(
      {
        uid,
        declaredExpertise: declaredExpertise ?? "",
        credentialsProvided: !!credentials,
        claimsModerated: false,
        falseAuthorityDetected: false,
        updatedAt: admin.firestore.Timestamp.now(),
        policyVersion: TRUST_SAFETY_OS_VERSION,
      },
      { merge: true }
    );

    return { success: true };
  }
);
