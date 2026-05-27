/**
 * getProfileHeaderPayload.ts
 *
 * Cloud Function (Gen2 onCall): `getProfileHeaderPayload`
 *
 * Returns the full Profile Header v2 payload for a given user.
 * Public callable — any signed-in user may fetch any other user's profile.
 *
 * Request:  { userId: string, viewerId: string }
 * Response: ProfileHeaderPayload (see type below)
 *
 * Error codes:
 *   unauthenticated  — caller is not signed in
 *   invalid-argument — userId is empty or missing
 *   not-found        — user document does not exist
 *   internal         — unexpected Firestore failure
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// ── Types ──────────────────────────────────────────────────────────────────

interface ProfileLink {
  id: string;
  type: string;
  url: string;
  label: string;
  order: number;
}

interface RoleFlags {
  isMentor: boolean;
  isCreator: boolean;
  isMinistryLeader: boolean;
  isChurchAccount: boolean;
  churchId: string | null;
}

interface ProfileMetrics {
  peopleDiscipled: number;
  versesShared: number;
  yearsWalkingWithChrist: number | null;
  testimoniesGiven: number;
  prayersOffered: number;
}

interface ProfileHeaderPayload {
  userId: string;
  links: ProfileLink[];
  pinSlotIds: string[];
  roleFlags: RoleFlags;
  profileMetrics: ProfileMetrics;
  bereanAboutOptIn: boolean;
  hasGivingEnabled: boolean;
  hasSubscriptionEnabled: boolean;
  visitChurchURL: string | null;
}

// ── Defaults ───────────────────────────────────────────────────────────────

const DEFAULT_ROLE_FLAGS: RoleFlags = {
  isMentor: false,
  isCreator: false,
  isMinistryLeader: false,
  isChurchAccount: false,
  churchId: null,
};

const DEFAULT_PROFILE_METRICS: ProfileMetrics = {
  peopleDiscipled: 0,
  versesShared: 0,
  yearsWalkingWithChrist: null,
  testimoniesGiven: 0,
  prayersOffered: 0,
};

// ── Callable ───────────────────────────────────────────────────────────────

export const getProfileHeaderPayload = onCall(async (request) => {
  // 1. Auth guard
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in to view profile headers.");
  }

  // 2. Input validation
  const { userId, viewerId } = (request.data ?? {}) as {
    userId?: string;
    viewerId?: string;
  };

  if (!userId || typeof userId !== "string" || userId.trim() === "") {
    throw new HttpsError("invalid-argument", "userId is required and must be a non-empty string.");
  }

  const db = admin.firestore();

  // 3. Fetch user document
  let userSnap: admin.firestore.DocumentSnapshot;
  try {
    userSnap = await db.collection("users").doc(userId).get();
  } catch (err) {
    throw new HttpsError("internal", "Failed to read user document.");
  }

  if (!userSnap.exists) {
    throw new HttpsError("not-found", `User '${userId}' does not exist.`);
  }

  const userData = userSnap.data() ?? {};
  const profile = (userData.profile ?? {}) as Record<string, unknown>;

  // 4. Extract profile sub-fields with safe defaults
  const links: ProfileLink[] = Array.isArray(profile.links) ? (profile.links as ProfileLink[]) : [];
  const pinSlotIds: string[] = Array.isArray(profile.pinSlots)
    ? (profile.pinSlots as string[]).slice(0, 3)
    : [];
  const roleFlags: RoleFlags = profile.roleFlags
    ? { ...DEFAULT_ROLE_FLAGS, ...(profile.roleFlags as Partial<RoleFlags>) }
    : { ...DEFAULT_ROLE_FLAGS };
  const profileMetrics: ProfileMetrics = profile.profileMetrics
    ? { ...DEFAULT_PROFILE_METRICS, ...(profile.profileMetrics as Partial<ProfileMetrics>) }
    : { ...DEFAULT_PROFILE_METRICS };
  const bereanAboutOptIn = profile.bereanAboutOptIn === true;

  // 5. Resolve churchId from roleFlags or top-level field
  const churchId: string | null = roleFlags.churchId ?? (userData.churchId as string | null) ?? null;
  // Keep roleFlags.churchId consistent
  roleFlags.churchId = churchId;

  // 6. Resolve church URL if churchId is present
  let visitChurchURL: string | null = null;
  if (churchId) {
    try {
      const churchSnap = await db.collection("churches").doc(churchId).get();
      if (churchSnap.exists) {
        const churchData = churchSnap.data() ?? {};
        visitChurchURL = (churchData.websiteUrl as string | null) ?? null;
      }
    } catch {
      // Non-fatal — church URL is optional enrichment
      visitChurchURL = null;
    }
  }

  // 7. Resolve giving enabled: Stripe Connect active OR church has giving link
  let hasGivingEnabled = false;
  try {
    const stripeSnap = await db.collection("stripeConnect").doc(userId).get();
    if (stripeSnap.exists) {
      const stripeData = stripeSnap.data() ?? {};
      hasGivingEnabled = stripeData.payoutsEnabled === true;
    }
  } catch {
    // Non-fatal — default to false
  }

  if (!hasGivingEnabled && churchId) {
    try {
      const churchSnap = await db.collection("churches").doc(churchId).get();
      if (churchSnap.exists) {
        const churchData = churchSnap.data() ?? {};
        hasGivingEnabled = !!(churchData.givingUrl || churchData.givingEnabled);
      }
    } catch {
      // Non-fatal
    }
  }

  // 8. Resolve subscription enabled: isCreator with serial content
  //    Defined as: roleFlags.isCreator === true AND postsCount > 0
  const hasSubscriptionEnabled =
    roleFlags.isCreator === true && (userData.postsCount as number ?? 0) > 0;

  // 9. Build and return payload
  const payload: ProfileHeaderPayload = {
    userId,
    links,
    pinSlotIds,
    roleFlags,
    profileMetrics,
    bereanAboutOptIn,
    hasGivingEnabled,
    hasSubscriptionEnabled,
    visitChurchURL,
  };

  return payload;
});
