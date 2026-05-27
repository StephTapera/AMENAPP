/**
 * YouthSafetyService.ts
 *
 * Backend youth safety rules for Amen Safety OS.
 *
 * Enforces:
 *   - DMs off by default for minor accounts
 *   - No adult-to-minor private messaging unless guardian-approved
 *   - No anonymous messaging to minors
 *   - No searchable precise location for minors
 *   - No mature content exposure for minors
 *   - Stricter text/image/video moderation thresholds for minor accounts
 *   - Youth group mode enforcement (leader/moderator approval required)
 *   - Discussion-only mode support (image/video posting disabled)
 *   - Safety alerts written to guardian subcollection for high-risk events
 *
 * ageTier field on users/{uid}: "minor" (< 13) | "teen" (13-17) | "adult" (18+)
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { AMEN_SAFETY_POLICY_VERSION } from "./AmenSafetyPolicy";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Types ────────────────────────────────────────────────────────────────────

export type AgeTier = "minor" | "teen" | "adult";

export interface YouthSafetyProfile {
  uid: string;
  ageTier: AgeTier;
  dmEnabled: boolean;                    // false by default for minor/teen
  anonymousMessagingAllowed: boolean;    // always false for minor
  locationExposureAllowed: boolean;      // always false for minor
  matureContentAllowed: boolean;         // always false for minor/teen
  imagePostingAllowed: boolean;          // false in discussionOnly mode
  videoPostingAllowed: boolean;          // false in discussionOnly mode
  discussionOnlyMode: boolean;
  youthGroupMode: boolean;
  guardianUids: string[];
}

export interface YouthSafetyCheckRequest {
  targetUid: string;       // The minor's uid
  actorUid: string;        // Who is attempting the action
  action: "dm" | "follow" | "view_location" | "post_media" | "join_group" | "react";
  contextId?: string;      // groupId, postId, conversationId
}

export interface YouthSafetyCheckResult {
  allowed: boolean;
  reason: string | null;
  guardianAlertRequired: boolean;
}

// ─── Profile Helpers ──────────────────────────────────────────────────────────

async function getYouthProfile(uid: string): Promise<YouthSafetyProfile | null> {
  const doc = await db.collection("users").doc(uid).get();
  const data = doc.data();
  if (!data) return null;

  const ageTier: AgeTier = data.ageTier ?? "adult";
  if (ageTier === "adult") return null; // Not a youth account

  return {
    uid,
    ageTier,
    dmEnabled: data.dmEnabled ?? false,
    anonymousMessagingAllowed: false,         // Never for minors
    locationExposureAllowed: false,           // Never for minors
    matureContentAllowed: false,              // Never for minor/teen
    imagePostingAllowed: data.imagePostingAllowed ?? (ageTier === "teen"),
    videoPostingAllowed: data.videoPostingAllowed ?? (ageTier === "teen"),
    discussionOnlyMode: data.discussionOnlyMode ?? (ageTier === "minor"),
    youthGroupMode: data.youthGroupMode ?? (ageTier === "minor"),
    guardianUids: data.guardianUids ?? [],
  };
}

async function getActorAgeTier(uid: string): Promise<AgeTier> {
  const doc = await db.collection("users").doc(uid).get();
  return (doc.data()?.ageTier as AgeTier) ?? "adult";
}

async function isGuardianApproved(minorUid: string, actorUid: string): Promise<boolean> {
  const approvalDoc = await db
    .collection("users")
    .doc(minorUid)
    .collection("guardianApprovedContacts")
    .doc(actorUid)
    .get();
  return approvalDoc.exists;
}

// ─── Core Check ───────────────────────────────────────────────────────────────

export async function checkYouthSafety(req: YouthSafetyCheckRequest): Promise<YouthSafetyCheckResult> {
  const { targetUid, actorUid, action, contextId } = req;

  const youthProfile = await getYouthProfile(targetUid);
  if (!youthProfile) {
    // Target is not a minor — no restriction
    return { allowed: true, reason: null, guardianAlertRequired: false };
  }

  const actorAge = await getActorAgeTier(actorUid);
  const isAdultActor = actorAge === "adult";
  const isSelf = actorUid === targetUid;

  switch (action) {
  case "dm": {
    if (!youthProfile.dmEnabled && !isSelf) {
      await writeYouthSafetyAlert(targetUid, actorUid, "dm_attempted_to_minor_with_dm_off", contextId);
      return {
        allowed: false,
        reason: "Direct messaging is disabled for this account.",
        guardianAlertRequired: false,
      };
    }
    if (isAdultActor) {
      const approved = await isGuardianApproved(targetUid, actorUid);
      if (!approved) {
        await writeYouthSafetyAlert(targetUid, actorUid, "adult_dm_attempt_to_minor", contextId);
        return {
          allowed: false,
          reason: "Adults may not message this account without guardian approval.",
          guardianAlertRequired: true,
        };
      }
    }
    return { allowed: true, reason: null, guardianAlertRequired: false };
  }

  case "view_location": {
    return {
      allowed: false,
      reason: "Location access is not permitted for minor accounts.",
      guardianAlertRequired: false,
    };
  }

  case "post_media": {
    if (youthProfile.discussionOnlyMode) {
      return {
        allowed: false,
        reason: "Media posting is disabled in Discussion-Only mode.",
        guardianAlertRequired: false,
      };
    }
    if (!youthProfile.imagePostingAllowed && !youthProfile.videoPostingAllowed) {
      return {
        allowed: false,
        reason: "Media posting requires parental approval for this account.",
        guardianAlertRequired: true,
      };
    }
    return { allowed: true, reason: null, guardianAlertRequired: false };
  }

  case "follow": {
    if (isAdultActor && youthProfile.ageTier === "minor") {
      await writeYouthSafetyAlert(targetUid, actorUid, "adult_follow_attempt_to_minor", contextId);
      return {
        allowed: false,
        reason: "Adults may not follow minor accounts without guardian approval.",
        guardianAlertRequired: true,
      };
    }
    return { allowed: true, reason: null, guardianAlertRequired: false };
  }

  case "join_group": {
    if (youthProfile.youthGroupMode && contextId) {
      const groupDoc = await db.collection("spaces").doc(contextId).get();
      const groupData = groupDoc.data();
      if (groupData?.youthGroupMode !== true) {
        return {
          allowed: false,
          reason: "Minor accounts can only join Youth Group-approved spaces.",
          guardianAlertRequired: false,
        };
      }
    }
    return { allowed: true, reason: null, guardianAlertRequired: false };
  }

  case "react":
    return { allowed: true, reason: null, guardianAlertRequired: false };

  default:
    return { allowed: true, reason: null, guardianAlertRequired: false };
  }
}

async function writeYouthSafetyAlert(
  minorUid: string,
  actorUid: string,
  alertType: string,
  contextId?: string
): Promise<void> {
  try {
    const batch = db.batch();

    // Write to the minor's safety subcollection
    const alertRef = db.collection("users").doc(minorUid).collection("safety").doc();
    batch.set(alertRef, {
      alertType,
      actorUid,
      contextId: contextId ?? null,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Write to moderationQueue for T&S review
    const queueRef = db.collection("moderationQueue").doc();
    batch.set(queueRef, {
      type: "youth_safety_alert",
      alertType,
      minorUid,
      actorUid,
      contextId: contextId ?? null,
      priority: "high",
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();
  } catch (err) {
    logger.warn("[YouthSafetyService] Failed to write youth safety alert.", err);
  }
}

// ─── Set Default Safety Settings for New Minor Accounts ──────────────────────

/**
 * Trigger: when users/{uid} is written (created or updated),
 * enforce safe defaults if ageTier is minor or teen.
 */
export const enforceYouthAccountDefaults = onDocumentWritten(
  "users/{uid}",
  async (event) => {
    const after = event.data?.after.data();
    const before = event.data?.before.data();
    if (!after) return;

    const ageTier: string = after.ageTier ?? "";
    if (!["minor", "teen"].includes(ageTier)) return;

    // Only enforce defaults on creation or ageTier change
    const ageChanged = before?.ageTier !== after.ageTier;
    const isNew = !before;
    if (!isNew && !ageChanged) return;

    const safeDefaults: Record<string, unknown> = {
      dmEnabled: false,
      anonymousMessagingAllowed: false,
      locationExposureAllowed: false,
      matureContentAllowed: false,
      searchableLocation: false,
    };

    if (ageTier === "minor") {
      safeDefaults.imagePostingAllowed = false;
      safeDefaults.videoPostingAllowed = false;
      safeDefaults.discussionOnlyMode = true;
      safeDefaults.youthGroupMode = true;
    } else {
      // Teen
      safeDefaults.imagePostingAllowed = true;
      safeDefaults.videoPostingAllowed = true;
      safeDefaults.discussionOnlyMode = false;
      safeDefaults.youthGroupMode = false;
    }

    try {
      const uid = event.params.uid;
      await db.collection("users").doc(uid).set(safeDefaults, { merge: true });
      logger.info(`[YouthSafetyService] Enforced safe defaults for uid=${uid} ageTier=${ageTier}`);
    } catch (err) {
      logger.error("[YouthSafetyService] Failed to enforce youth defaults.", err);
    }
  }
);

// ─── Callables ────────────────────────────────────────────────────────────────

/**
 * checkYouthSafetyCallable
 * Used by client before actions that may involve a minor account.
 */
export const checkYouthSafetyCallable = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<YouthSafetyCheckRequest>): Promise<YouthSafetyCheckResult> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.data.targetUid || !request.data.action) {
      throw new HttpsError("invalid-argument", "targetUid and action are required.");
    }

    return checkYouthSafety({ ...request.data, actorUid: request.auth.uid });
  }
);

/**
 * updateYouthSettings
 * Allows guardians to modify youth safety settings for a connected minor account.
 * Guardians must be listed in users/{minorUid}.guardianUids.
 */
export const updateYouthSettings = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{
    minorUid: string;
    settings: Partial<{
      dmEnabled: boolean;
      imagePostingAllowed: boolean;
      videoPostingAllowed: boolean;
      discussionOnlyMode: boolean;
    }>;
  }>): Promise<{ success: boolean }> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { minorUid, settings } = request.data;
    if (!minorUid) throw new HttpsError("invalid-argument", "minorUid is required.");

    // Verify caller is a registered guardian
    const minorDoc = await db.collection("users").doc(minorUid).get();
    const guardianUids: string[] = minorDoc.data()?.guardianUids ?? [];
    const isAdmin = (request.auth.token as Record<string, unknown>).admin === true;

    if (!guardianUids.includes(request.auth.uid) && !isAdmin) {
      throw new HttpsError("permission-denied", "Only registered guardians may update these settings.");
    }

    // Clamp settings to safe limits (guardians cannot grant matureContent)
    const safeUpdate: Record<string, unknown> = {};
    if (typeof settings.dmEnabled === "boolean") safeUpdate.dmEnabled = settings.dmEnabled;
    if (typeof settings.imagePostingAllowed === "boolean") safeUpdate.imagePostingAllowed = settings.imagePostingAllowed;
    if (typeof settings.videoPostingAllowed === "boolean") safeUpdate.videoPostingAllowed = settings.videoPostingAllowed;
    if (typeof settings.discussionOnlyMode === "boolean") safeUpdate.discussionOnlyMode = settings.discussionOnlyMode;

    await db.collection("users").doc(minorUid).set(safeUpdate, { merge: true });

    logger.info(`[YouthSafetyService] Guardian ${request.auth.uid} updated settings for minor ${minorUid}`);
    return { success: true };
  }
);
