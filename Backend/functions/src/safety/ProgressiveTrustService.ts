/**
 * ProgressiveTrustService.ts
 *
 * Progressive trust system for Amen — positive side of the trust model.
 *
 * New accounts start at Level 0 with minimal capabilities and earn their way
 * to higher levels through verified, healthy behavior over time.  This is the
 * counterpart to TrustAndStrikeService (which handles the punitive side);
 * trust level can only increase here — decreases are never applied.
 *
 * Trust level → capability mapping:
 *   0  New             read, react, comment in public groups
 *   1  Established     + limited public text posting
 *   2  Trusted         + DMs with verified users, image uploads
 *   3  Verified        + unrestricted DMs, video uploads
 *   4  Community Builder + group creation, event hosting
 *   5  Ambassador       + mentorship connections, verification badge
 *
 * Data model:
 *   users/{uid}
 *     trustLevel: 0–5
 *     trustPoints: number
 *     trustCapabilities: TrustCapabilities
 *
 *   trustEvents/{uid}/events/{eventId}
 *     eventType: string
 *     points: number
 *     createdAt: Timestamp
 *
 *   trustAuditLog/{logId}  (admin grants only)
 *     uid, eventType, reason, grantedBy, grantedAt
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Types ────────────────────────────────────────────────────────────────────

export interface TrustCapabilities {
  canDM: boolean;
  /** "verified_only" | "unrestricted" | false */
  dmScope: "verified_only" | "unrestricted" | false;
  canUploadMedia: boolean;
  /** "image" | "image_and_video" | false */
  mediaScope: "image" | "image_and_video" | false;
  canCreateGroup: boolean;
  canPostPublicly: boolean;
  canMentor: boolean;
  maxDailyComments: number;
}

interface TrustLevelDefinition {
  label: string;
  capabilities: TrustCapabilities;
}

// ─── Constants ────────────────────────────────────────────────────────────────

export const TRUST_LEVELS: Record<number, TrustLevelDefinition> = {
  0: {
    label: "New",
    capabilities: {
      canDM: false,
      dmScope: false,
      canUploadMedia: false,
      mediaScope: false,
      canCreateGroup: false,
      canPostPublicly: false,
      canMentor: false,
      maxDailyComments: 10,
    },
  },
  1: {
    label: "Established",
    capabilities: {
      canDM: false,
      dmScope: false,
      canUploadMedia: false,
      mediaScope: false,
      canCreateGroup: false,
      canPostPublicly: true,
      canMentor: false,
      maxDailyComments: 25,
    },
  },
  2: {
    label: "Trusted",
    capabilities: {
      canDM: true,
      dmScope: "verified_only",
      canUploadMedia: true,
      mediaScope: "image",
      canCreateGroup: false,
      canPostPublicly: true,
      canMentor: false,
      maxDailyComments: 50,
    },
  },
  3: {
    label: "Verified",
    capabilities: {
      canDM: true,
      dmScope: "unrestricted",
      canUploadMedia: true,
      mediaScope: "image_and_video",
      canCreateGroup: false,
      canPostPublicly: true,
      canMentor: false,
      maxDailyComments: 100,
    },
  },
  4: {
    label: "Community Builder",
    capabilities: {
      canDM: true,
      dmScope: "unrestricted",
      canUploadMedia: true,
      mediaScope: "image_and_video",
      canCreateGroup: true,
      canPostPublicly: true,
      canMentor: false,
      maxDailyComments: 200,
    },
  },
  5: {
    label: "Ambassador",
    capabilities: {
      canDM: true,
      dmScope: "unrestricted",
      canUploadMedia: true,
      mediaScope: "image_and_video",
      canCreateGroup: true,
      canPostPublicly: true,
      canMentor: true,
      maxDailyComments: 500,
    },
  },
};

/**
 * Points awarded for each verifiable trust-earning event.
 * Events are additive — points never expire.
 */
export const TRUST_EVENTS: Record<string, number> = {
  account_age_7d: 5,
  account_age_30d: 10,
  account_age_90d: 15,
  phone_verified: 10,
  email_verified: 5,
  church_connection_verified: 20,
  mentorship_connection_approved: 15,
  healthy_interaction_streak_10: 5,    // 10 consecutive interactions without moderation flags
  healthy_interaction_streak_50: 10,
  community_report_validated: 8,       // user filed a report that was upheld
  identity_document_verified: 25,
};

/**
 * Cumulative points required to reach each level.
 * Level 0 is the starting state (0 points needed).
 *
 * 0 → 1: 5 pts
 * 1 → 2: 20 pts total (15 additional)
 * 2 → 3: 45 pts total (25 additional)
 * 3 → 4: 80 pts total (35 additional)
 * 4 → 5: 120 pts total (40 additional)
 */
const LEVEL_THRESHOLDS: Record<number, number> = {
  0: 0,
  1: 5,
  2: 20,
  3: 45,
  4: 80,
  5: 120,
};

const MAX_TRUST_LEVEL = 5;

// ─── Friendly level-up messages ───────────────────────────────────────────────

const LEVEL_UP_MESSAGES: Record<number, { title: string; body: string }> = {
  1: {
    title: "Welcome to the community!",
    body: "You've reached Established status. You can now post publicly on Amen — share what's on your heart.",
  },
  2: {
    title: "You're Trusted!",
    body: "You can now send direct messages to verified members and share images. Keep building those connections.",
  },
  3: {
    title: "Verified member!",
    body: "Your account is now Verified. Unrestricted DMs and video sharing are unlocked. Thank you for being a trustworthy voice.",
  },
  4: {
    title: "Community Builder!",
    body: "You can now create groups and host events on Amen. Help others find community.",
  },
  5: {
    title: "Amen Ambassador!",
    body: "You've reached the highest trust level. Mentorship connections are now open. Lead with grace.",
  },
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

function trustLevelFromPoints(points: number): number {
  let level = 0;
  for (let l = MAX_TRUST_LEVEL; l >= 1; l--) {
    if (points >= LEVEL_THRESHOLDS[l]) {
      level = l;
      break;
    }
  }
  return level;
}

function nextLevelRequirement(currentPoints: number, currentLevel: number): number | null {
  if (currentLevel >= MAX_TRUST_LEVEL) return null;
  const nextThreshold = LEVEL_THRESHOLDS[currentLevel + 1];
  return Math.max(0, nextThreshold - currentPoints);
}

// ─── Core: recordTrustEvent ───────────────────────────────────────────────────

/**
 * Records a verified trust-earning event for a user and recalculates their
 * trust level.  Trust level can only increase, never decrease.
 *
 * Called by other server-side services (not exposed as a callable directly).
 */
export async function recordTrustEvent(uid: string, eventType: string): Promise<void> {
  // Validate event type
  const points = TRUST_EVENTS[eventType];
  if (points === undefined) {
    throw new Error(`[ProgressiveTrustService] Unknown eventType="${eventType}"`);
  }

  // Write the event record
  await db
    .collection("trustEvents")
    .doc(uid)
    .collection("events")
    .add({
      eventType,
      points,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  // Recalculate total trust points from all events in the last 365 days.
  // Trust points do not expire, but we gate the query to a rolling year to
  // keep the dataset manageable for very old accounts with many events.
  const cutoff = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - 365 * 24 * 60 * 60 * 1000)
  );

  const eventsSnap = await db
    .collection("trustEvents")
    .doc(uid)
    .collection("events")
    .where("createdAt", ">=", cutoff)
    .get();

  let totalPoints = 0;
  eventsSnap.forEach((doc) => {
    totalPoints += (doc.data().points as number) ?? 0;
  });

  // Determine new trust level — only ever increases
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const currentLevel: number = (userSnap.data()?.trustLevel as number) ?? 0;

  const newLevel = Math.max(currentLevel, trustLevelFromPoints(totalPoints));
  const newCapabilities = TRUST_LEVELS[newLevel].capabilities;

  await userRef.set(
    {
      trustPoints: totalPoints,
      trustLevel: newLevel,
      trustCapabilities: newCapabilities,
    },
    { merge: true }
  );

  // Send a friendly in-app notification if the level increased
  if (newLevel > currentLevel) {
    const msg = LEVEL_UP_MESSAGES[newLevel];
    if (msg) {
      try {
        await userRef.collection("notifications").add({
          type: "trust_level_up",
          trustLevel: newLevel,
          trustLevelLabel: TRUST_LEVELS[newLevel].label,
          title: msg.title,
          body: msg.body,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (err) {
        logger.warn("[ProgressiveTrustService] Failed to send level-up notification.", err);
      }
    }
  }

  logger.info(
    `[ProgressiveTrustService] Trust event uid=${uid} event=${eventType} points=${totalPoints} newLevel=${newLevel}`
  );
}

// ─── Trigger: initializeNewAccount ───────────────────────────────────────────

/**
 * Firestore trigger: when a new user document is created, initialize trust
 * defaults at Level 0.  Skips accounts managed by YouthSafetyService
 * (ageTier "minor" or "teen") so those services can set appropriate defaults.
 */
export const initializeNewAccount = onDocumentCreated(
  "users/{uid}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    // YouthSafetyService owns minor/teen defaults — do not override
    const ageTier: string = data.ageTier ?? "";
    if (ageTier === "minor" || ageTier === "teen") return;

    const uid = event.params.uid;

    try {
      await db.collection("users").doc(uid).set(
        {
          // Trust baseline
          trustLevel: 0,
          trustPoints: 0,
          trustCapabilities: TRUST_LEVELS[0].capabilities,
          // Explicit restriction flags mirrored from Level 0 capabilities
          // so other services can read a single flat field without unpacking
          // the nested trustCapabilities object.
          dmEnabled: false,
          imagePostingAllowed: false,
          videoPostingAllowed: false,
          canCreateGroup: false,
          canPostPublicly: false,
        },
        { merge: true }
      );

      logger.info(`[ProgressiveTrustService] Initialized trust defaults for uid=${uid}`);
    } catch (err) {
      logger.error("[ProgressiveTrustService] Failed to initialize account trust defaults.", err);
    }
  }
);

// ─── Callable: getTrustProfile ────────────────────────────────────────────────

interface GetTrustProfileRequest {
  uid?: string;
}

interface GetTrustProfileResponse {
  trustLevel: number;
  trustPoints: number;
  trustCapabilities: TrustCapabilities;
  /** Points still required to reach the next level, or null at max level. */
  nextLevelRequirement: number | null;
  recentEvents: Array<{
    id: string;
    eventType: string;
    points: number;
    createdAt: admin.firestore.Timestamp;
  }>;
}

export const getTrustProfile = onCall(
  { enforceAppCheck: true },
  async (
    request: CallableRequest<GetTrustProfileRequest>
  ): Promise<GetTrustProfileResponse> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const callerUid = request.auth.uid;
    const targetUid = request.data.uid ?? callerUid;

    // If fetching another user's profile, require admin token
    if (targetUid !== callerUid) {
      const token = request.auth.token as Record<string, unknown>;
      if (!token.admin) {
        throw new HttpsError(
          "permission-denied",
          "Admin access required to view another user's trust profile."
        );
      }
    }

    const userSnap = await db.collection("users").doc(targetUid).get();
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "User not found.");
    }

    const userData = userSnap.data() ?? {};
    const trustLevel: number = userData.trustLevel ?? 0;
    const trustPoints: number = userData.trustPoints ?? 0;
    const trustCapabilities: TrustCapabilities =
      userData.trustCapabilities ?? TRUST_LEVELS[0].capabilities;

    // Fetch 10 most recent trust events
    const eventsSnap = await db
      .collection("trustEvents")
      .doc(targetUid)
      .collection("events")
      .orderBy("createdAt", "desc")
      .limit(10)
      .get();

    const recentEvents = eventsSnap.docs.map((doc) => ({
      id: doc.id,
      eventType: doc.data().eventType as string,
      points: doc.data().points as number,
      createdAt: doc.data().createdAt as admin.firestore.Timestamp,
    }));

    return {
      trustLevel,
      trustPoints,
      trustCapabilities,
      nextLevelRequirement: nextLevelRequirement(trustPoints, trustLevel),
      recentEvents,
    };
  }
);

// ─── Callable: adminGrantTrustEvent ──────────────────────────────────────────

interface AdminGrantTrustEventRequest {
  uid: string;
  eventType: string;
  reason: string;
}

interface AdminGrantTrustEventResponse {
  success: boolean;
  auditLogId: string;
}

export const adminGrantTrustEvent = onCall(
  { enforceAppCheck: true },
  async (
    request: CallableRequest<AdminGrantTrustEventRequest>
  ): Promise<AdminGrantTrustEventResponse> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const token = request.auth.token as Record<string, unknown>;
    if (!token.admin) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }

    const { uid, eventType, reason } = request.data;

    if (!uid || !eventType || !reason) {
      throw new HttpsError(
        "invalid-argument",
        "uid, eventType, and reason are all required."
      );
    }

    if (!(eventType in TRUST_EVENTS)) {
      throw new HttpsError(
        "invalid-argument",
        `Unknown eventType="${eventType}". Valid events: ${Object.keys(TRUST_EVENTS).join(", ")}`
      );
    }

    // Apply the trust event
    await recordTrustEvent(uid, eventType);

    // Write an audit log entry
    const auditRef = await db.collection("trustAuditLog").add({
      uid,
      eventType,
      points: TRUST_EVENTS[eventType],
      reason,
      grantedBy: `admin:${request.auth.uid}`,
      grantedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(
      `[ProgressiveTrustService] Admin grant uid=${uid} event=${eventType} by=${request.auth.uid} auditLog=${auditRef.id}`
    );

    return { success: true, auditLogId: auditRef.id };
  }
);

// ─── Exported helper: checkAccountCapability ─────────────────────────────────

/**
 * Returns whether a user currently holds a specific trust capability.
 * Fails closed — returns false if the user document is missing or the field
 * is absent, so new or unknown accounts are always restricted.
 *
 * Used by other services (e.g. messaging, media upload) to gate actions.
 */
export async function checkAccountCapability(
  uid: string,
  capability: keyof TrustCapabilities
): Promise<boolean> {
  try {
    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) return false;

    const capabilities = userSnap.data()?.trustCapabilities as
      | TrustCapabilities
      | undefined;
    if (!capabilities) return false;

    const value = capabilities[capability];

    // Boolean capabilities
    if (typeof value === "boolean") return value;

    // Scoped capabilities ("verified_only" | "unrestricted" | "image" | "image_and_video")
    // Any non-false string scope value counts as the capability being enabled.
    if (typeof value === "string") return true;

    return false;
  } catch (err) {
    logger.error(
      `[ProgressiveTrustService] checkAccountCapability failed uid=${uid} capability=${capability}`,
      err
    );
    // Fail closed
    return false;
  }
}
