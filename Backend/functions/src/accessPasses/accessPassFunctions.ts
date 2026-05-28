// accessPassFunctions.ts — Firebase Callable Functions for Access Passes
//
// Security: App Check enforced, auth enforced where required,
// all mutations backend-only, tokenHash never returned to client.

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {
  AmenAccessPass,
  AmenAccessRequest,
  AmenAccessCheckIn,
  AccessPassAdminSummary,
} from "./accessPassTypes";
import {
  generateRawToken,
  hashToken,
  buildUniversalLink,
  buildDeepLink,
} from "./accessPassToken";
import {
  loadAndValidatePass,
  validateModeForTarget,
  checkMaxUses,
  checkMaxUsesPerUser,
  verifyRoleGatedEligibility,
  checkIfAlreadyMember,
  checkIfRequestPending,
} from "./accessPassValidation";
import {
  verifyAdminForTarget,
  verifyPassAdmin,
  verifyRequestAdmin,
} from "./accessPassPermissions";
import { enforceRateLimit, recordInvalidTokenAttempt } from "./accessPassRateLimit";
import { buildPreviewResponse } from "./accessPassPreview";
import {
  logResolved,
  logJoined,
  logRequested,
  logCheckedIn,
  logPreviewed,
  logRevoked,
  logRateLimited,
} from "./accessPassAudit";

const db = admin.firestore();

// ---------------------------------------------------------------------------
// 1. createAccessPass
// ---------------------------------------------------------------------------
export const createAccessPass = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "auth-required");
  }
  const uid = context.auth.uid;

  const {
    targetType,
    targetId,
    orgId,
    churchId,
    spaceId,
    mode,
    title,
    subtitle,
    description,
    requiresAuth,
    requiresApproval,
    allowedEmailDomains,
    allowedRoleIds,
    allowedMemberUids,
    maxUses,
    maxUsesPerUser,
    startsAt,
    expiresAt,
    checkInDurationMinutes,
    safetyProfile,
    landingConfig,
  } = data;

  if (!targetType || !targetId || !mode || !title) {
    throw new functions.https.HttpsError("invalid-argument", "missing-required-fields");
  }

  // Verify admin for target
  await verifyAdminForTarget(uid, targetType, targetId);

  // Validate mode vs sensitivity
  if (safetyProfile?.isSensitive) {
    validateModeForTarget(mode, targetType, true);
  }

  // Get display name
  const userRecord = await admin.auth().getUser(uid);
  const displayName = userRecord.displayName ?? undefined;

  // Generate token
  const rawToken = generateRawToken();
  const tokenHash = hashToken(rawToken);

  const now = admin.firestore.Timestamp.now();
  const passId = db.collection("accessPasses").doc().id;

  const pass: AmenAccessPass = {
    accessPassId: passId,
    tokenHash,
    tokenVersion: 1,
    targetType,
    targetId,
    orgId,
    churchId,
    spaceId,
    createdByUid: uid,
    createdByDisplayName: displayName,
    mode,
    status: "active",
    title,
    subtitle,
    description,
    requiresAuth: requiresAuth ?? true,
    requiresApproval: requiresApproval ?? false,
    allowedEmailDomains: allowedEmailDomains ?? [],
    allowedRoleIds: allowedRoleIds ?? [],
    allowedMemberUids: allowedMemberUids ?? [],
    maxUses,
    usesCount: 0,
    maxUsesPerUser: maxUsesPerUser ?? 1,
    startsAt: startsAt ? admin.firestore.Timestamp.fromMillis(startsAt) : undefined,
    expiresAt: expiresAt ? admin.firestore.Timestamp.fromMillis(expiresAt) : undefined,
    checkInDurationMinutes,
    safetyProfile: {
      isSensitive: safetyProfile?.isSensitive ?? false,
      requiresModeratorApproval: safetyProfile?.requiresModeratorApproval ?? false,
      allowYouthAccess: safetyProfile?.allowYouthAccess ?? false,
      allowGuestPreview: safetyProfile?.allowGuestPreview ?? false,
      showMemberVisibilityWarning: safetyProfile?.showMemberVisibilityWarning ?? true,
      showPrayerPrivacyWarning: safetyProfile?.showPrayerPrivacyWarning ?? false,
    },
    landingConfig: {
      headline: landingConfig?.headline ?? title,
      body: landingConfig?.body ?? "",
      primaryActionLabel: landingConfig?.primaryActionLabel ?? "Join",
      secondaryActionLabel: landingConfig?.secondaryActionLabel,
      allowedActions: landingConfig?.allowedActions ?? ["join", "preview"],
    },
    audit: {
      createdAt: now,
      updatedAt: now,
    },
  };

  await db.collection("accessPasses").doc(passId).set(pass);

  const universalLink = buildUniversalLink(passId, rawToken);
  const deepLink = buildDeepLink(passId, rawToken);

  return {
    accessPassId: passId,
    rawToken,                     // Returned once only — never stored
    universalLink,
    qrPayload: universalLink,
    nfcPayload: deepLink,
    shareLink: universalLink,
    previewTitle: title,
    previewSubtitle: subtitle ?? null,
  };
});

// ---------------------------------------------------------------------------
// 2. resolveAccessPass
// ---------------------------------------------------------------------------
export const resolveAccessPass = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  const { accessPassId, token, anonymousSessionId, devicePlatform, appVersion } = data;

  if (!accessPassId || !token) {
    throw new functions.https.HttpsError("invalid-argument", "missing-fields");
  }

  const identity = uid ?? anonymousSessionId ?? "anon";

  // Rate limit
  try {
    await enforceRateLimit("resolve", identity);
  } catch (e) {
    if (anonymousSessionId || uid) {
      await logRateLimited(accessPassId, "unknown", "unknown", uid).catch(() => {});
    }
    throw e;
  }

  let pass: AmenAccessPass;
  try {
    pass = await loadAndValidatePass(accessPassId, token);
  } catch (err: any) {
    if (err.message === "invalid-pass") {
      await recordInvalidTokenAttempt(identity).catch(() => {});
    }
    throw err;
  }

  // Auth gate
  if (pass.requiresAuth && !uid) {
    throw new functions.https.HttpsError("unauthenticated", "auth-required");
  }

  // Guest preview gate
  if (!pass.requiresAuth && !uid && !pass.safetyProfile.allowGuestPreview) {
    throw new functions.https.HttpsError("unauthenticated", "auth-required");
  }

  const alreadyMember = uid
    ? await checkIfAlreadyMember(pass.targetType, pass.targetId, uid)
    : false;
  const existingRequestPending = uid
    ? await checkIfRequestPending(accessPassId, uid)
    : false;

  // Log resolve event
  await logResolved(
    accessPassId,
    pass.targetType,
    pass.targetId,
    uid,
    anonymousSessionId,
    devicePlatform,
    appVersion
  ).catch(() => {});

  // Update lastUsedAt
  await db.collection("accessPasses").doc(accessPassId).update({
    "audit.lastUsedAt": admin.firestore.Timestamp.now(),
  });

  return buildPreviewResponse(pass, alreadyMember, existingRequestPending);
});

// ---------------------------------------------------------------------------
// 3. acceptAccessPass
// ---------------------------------------------------------------------------
export const acceptAccessPass = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "auth-required");
  }
  const uid = context.auth.uid;
  const { accessPassId, token, action, requestMessage } = data;

  if (!accessPassId || !token || !action) {
    throw new functions.https.HttpsError("invalid-argument", "missing-fields");
  }

  await enforceRateLimit("accept", uid);

  const pass = await loadAndValidatePass(accessPassId, token);

  // Check user eligibility
  if (pass.mode === "roleGated") {
    const userRecord = await admin.auth().getUser(uid);
    await verifyRoleGatedEligibility(pass, uid, userRecord.email ?? undefined);
  }

  await checkMaxUsesPerUser(pass, uid);

  const now = admin.firestore.Timestamp.now();
  const passRef = db.collection("accessPasses").doc(accessPassId);

  switch (action) {
    case "preview": {
      await logPreviewed(accessPassId, pass.targetType, pass.targetId, uid).catch(() => {});
      return {
        success: true,
        action: "preview",
        targetId: pass.targetId,
        targetType: pass.targetType,
        routePayload: `amen://${pass.targetType}/${pass.targetId}`,
        message: "Preview opened.",
      };
    }

    case "join": {
      // Block sensitive direct join
      if (pass.safetyProfile.isSensitive) {
        validateModeForTarget("join", pass.targetType, true);
      }

      // Transactional join + usesCount increment
      await db.runTransaction(async (tx) => {
        const freshSnap = await tx.get(passRef);
        const fresh = freshSnap.data() as AmenAccessPass;
        checkMaxUses(fresh);

        // Write membership using existing membership pattern
        const memberRef = db
          .collection(`${pass.targetType}s`)
          .doc(pass.targetId)
          .collection("members")
          .doc(uid);

        tx.set(memberRef, {
          userId: uid,
          joinedAt: now,
          role: "member",
          accessPassId,
          joinMethod: "accessPass",
        }, { merge: true });

        tx.update(passRef, {
          usesCount: admin.firestore.FieldValue.increment(1),
          "audit.updatedAt": now,
        });
      });

      await logJoined(accessPassId, pass.targetType, pass.targetId, uid).catch(() => {});

      return {
        success: true,
        action: "join",
        targetId: pass.targetId,
        targetType: pass.targetType,
        routePayload: `amen://${pass.targetType}/${pass.targetId}`,
        message: "Welcome! You've joined.",
      };
    }

    case "request": {
      // Check if already pending
      const alreadyPending = await checkIfRequestPending(accessPassId, uid);
      if (alreadyPending) {
        return {
          success: true,
          action: "request",
          targetId: pass.targetId,
          targetType: pass.targetType,
          message: "Your request is already pending.",
        };
      }

      const requestId = db.collection("accessRequests").doc().id;
      const userRecord = await admin.auth().getUser(uid);

      const request: AmenAccessRequest = {
        requestId,
        accessPassId,
        targetType: pass.targetType,
        targetId: pass.targetId,
        requesterUid: uid,
        requesterDisplayName: userRecord.displayName ?? undefined,
        requesterPhotoURL: userRecord.photoURL ?? undefined,
        orgId: pass.orgId,
        churchId: pass.churchId,
        spaceId: pass.spaceId,
        status: "pending",
        requestMessage: requestMessage ?? undefined,
        createdAt: now,
        updatedAt: now,
      };

      await db.collection("accessRequests").doc(requestId).set(request);
      await logRequested(accessPassId, pass.targetType, pass.targetId, uid).catch(() => {});

      return {
        success: true,
        action: "request",
        requestId,
        targetId: pass.targetId,
        targetType: pass.targetType,
        message: "Your request has been sent to the host.",
      };
    }

    case "checkIn": {
      const durationMinutes = pass.checkInDurationMinutes ?? 120;
      const expiresAt = admin.firestore.Timestamp.fromMillis(
        now.toMillis() + durationMinutes * 60_000
      );

      const checkInId = db.collection("activeCheckIns").doc().id;
      const checkIn: AmenAccessCheckIn = {
        checkInId,
        accessPassId,
        uid,
        targetType: pass.targetType,
        targetId: pass.targetId,
        startedAt: now,
        expiresAt,
        status: "active",
      };

      await db.runTransaction(async (tx) => {
        const freshSnap = await tx.get(passRef);
        const fresh = freshSnap.data() as AmenAccessPass;
        checkMaxUses(fresh);

        tx.set(db.collection("activeCheckIns").doc(checkInId), checkIn);
        tx.update(passRef, {
          usesCount: admin.firestore.FieldValue.increment(1),
          "audit.updatedAt": now,
        });
      });

      await logCheckedIn(accessPassId, pass.targetType, pass.targetId, uid).catch(() => {});

      return {
        success: true,
        action: "checkIn",
        targetId: pass.targetId,
        targetType: pass.targetType,
        checkInExpiresAt: expiresAt.toMillis(),
        message: `You're checked in for ${durationMinutes} minutes.`,
      };
    }

    case "openSermonNotes":
    case "askForPrayer":
    case "meetLeader":
    case "followChurch": {
      return {
        success: true,
        action,
        targetId: pass.targetId,
        targetType: pass.targetType,
        routePayload: `amen://${pass.targetType}/${pass.targetId}/${action}`,
        message: "Action available.",
      };
    }

    default:
      throw new functions.https.HttpsError("invalid-argument", "unknown-action");
  }
});

// ---------------------------------------------------------------------------
// 4. revokeAccessPass
// ---------------------------------------------------------------------------
export const revokeAccessPass = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "auth-required");
  }
  const uid = context.auth.uid;
  const { accessPassId, reason } = data;

  await verifyPassAdmin(uid, accessPassId);

  const passSnap = await db.collection("accessPasses").doc(accessPassId).get();
  const pass = passSnap.data() as AmenAccessPass;
  const now = admin.firestore.Timestamp.now();

  await db.collection("accessPasses").doc(accessPassId).update({
    status: "revoked",
    "audit.revokedAt": now,
    "audit.revokedByUid": uid,
    "audit.revokeReason": reason ?? null,
    "audit.updatedAt": now,
  });

  await logRevoked(accessPassId, pass.targetType, pass.targetId, uid, reason).catch(() => {});

  return { success: true };
});

// ---------------------------------------------------------------------------
// 5. pauseAccessPass
// ---------------------------------------------------------------------------
export const pauseAccessPass = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "auth-required");
  }
  await verifyPassAdmin(context.auth.uid, data.accessPassId);

  await db.collection("accessPasses").doc(data.accessPassId).update({
    status: "paused",
    "audit.updatedAt": admin.firestore.Timestamp.now(),
  });

  return { success: true };
});

// ---------------------------------------------------------------------------
// 6. resumeAccessPass
// ---------------------------------------------------------------------------
export const resumeAccessPass = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "auth-required");
  }
  await verifyPassAdmin(context.auth.uid, data.accessPassId);

  const snap = await db.collection("accessPasses").doc(data.accessPassId).get();
  const pass = snap.data() as AmenAccessPass;

  if (pass.status === "revoked" || pass.status === "expired") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "cannot-resume-revoked-or-expired"
    );
  }

  await db.collection("accessPasses").doc(data.accessPassId).update({
    status: "active",
    "audit.updatedAt": admin.firestore.Timestamp.now(),
  });

  return { success: true };
});

// ---------------------------------------------------------------------------
// 7. rotateAccessPassToken
// ---------------------------------------------------------------------------
export const rotateAccessPassToken = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "auth-required");
  }
  await verifyPassAdmin(context.auth.uid, data.accessPassId);

  const newRawToken = generateRawToken();
  const newTokenHash = hashToken(newRawToken);

  await db.collection("accessPasses").doc(data.accessPassId).update({
    tokenHash: newTokenHash,
    tokenVersion: admin.firestore.FieldValue.increment(1),
    "audit.updatedAt": admin.firestore.Timestamp.now(),
  });

  const universalLink = buildUniversalLink(data.accessPassId, newRawToken);
  const deepLink = buildDeepLink(data.accessPassId, newRawToken);

  return {
    accessPassId: data.accessPassId,
    newRawToken,                   // Returned once only
    newUniversalLink: universalLink,
    newQrPayload: universalLink,
    newShareLink: universalLink,
    newNfcPayload: deepLink,
  };
});

// ---------------------------------------------------------------------------
// 8. approveAccessRequest
// ---------------------------------------------------------------------------
export const approveAccessRequest = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "auth-required");
  }
  const uid = context.auth.uid;
  const { requestId } = data;

  await verifyRequestAdmin(uid, requestId);

  const reqSnap = await db.collection("accessRequests").doc(requestId).get();
  const req = reqSnap.data() as AmenAccessRequest;

  if (req.status !== "pending") {
    return { success: true, alreadyProcessed: true };
  }

  const now = admin.firestore.Timestamp.now();

  await db.runTransaction(async (tx) => {
    tx.update(db.collection("accessRequests").doc(requestId), {
      status: "approved",
      reviewedByUid: uid,
      reviewedAt: now,
      updatedAt: now,
    });

    // Create membership using existing Amen membership paths
    const memberRef = db
      .collection(`${req.targetType}s`)
      .doc(req.targetId)
      .collection("members")
      .doc(req.requesterUid);

    tx.set(memberRef, {
      userId: req.requesterUid,
      joinedAt: now,
      role: "member",
      accessPassId: req.accessPassId,
      joinMethod: "accessPassRequest",
    }, { merge: true });
  });

  return { success: true };
});

// ---------------------------------------------------------------------------
// 9. denyAccessRequest
// ---------------------------------------------------------------------------
export const denyAccessRequest = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "auth-required");
  }
  await verifyRequestAdmin(context.auth.uid, data.requestId);

  const now = admin.firestore.Timestamp.now();
  await db.collection("accessRequests").doc(data.requestId).update({
    status: "denied",
    reviewedByUid: context.auth.uid,
    reviewedAt: now,
    denialReason: data.denialReason ?? null,
    updatedAt: now,
  });

  return { success: true };
});

// ---------------------------------------------------------------------------
// 10. listAccessPassesForTarget
// ---------------------------------------------------------------------------
export const listAccessPassesForTarget = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "auth-required");
  }
  const { targetType, targetId } = data;
  await verifyAdminForTarget(context.auth.uid, targetType, targetId);

  const passesSnap = await db
    .collection("accessPasses")
    .where("targetType", "==", targetType)
    .where("targetId", "==", targetId)
    .orderBy("audit.createdAt", "desc")
    .limit(50)
    .get();

  const passes: AccessPassAdminSummary[] = passesSnap.docs.map((doc) => {
    const pass = doc.data() as AmenAccessPass;
    // Strip tokenHash before returning to client
    const safe = { ...pass };
    delete (safe as Partial<AmenAccessPass>).tokenHash;
    delete (safe as Partial<AmenAccessPass>).tokenVersion;
    return safe as AccessPassAdminSummary;
  });

  return { passes };
});

// ---------------------------------------------------------------------------
// 11. listAccessRequestsForTarget
// ---------------------------------------------------------------------------
export const listAccessRequestsForTarget = functions.runWith({ enforceAppCheck: true }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "auth-required");
  }
  const { targetType, targetId } = data;
  await verifyAdminForTarget(context.auth.uid, targetType, targetId);

  const reqSnap = await db
    .collection("accessRequests")
    .where("targetType", "==", targetType)
    .where("targetId", "==", targetId)
    .orderBy("createdAt", "desc")
    .limit(100)
    .get();

  const requests = reqSnap.docs.map((doc) => doc.data() as AmenAccessRequest);

  return { requests };
});
