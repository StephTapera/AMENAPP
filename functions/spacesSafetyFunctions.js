/**
 * spacesSafetyFunctions.js
 * AMEN Spaces — Safety callables
 * Handles: scanMessageForScam, verifyHost, submitModerationAction, reviewJoinRequest
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const db = getFirestore();

// Local keyword patterns for fast server-side prescreening (mirrors AmenScamShieldService.swift)
const SCAM_PATTERNS = {
  moneyRequest: [/send me \$/, /transfer.*funds/, /wire.*money/, /zelle me/, /cashapp me/, /venmo me/i, /need.*\$\d+/, /pay me/i],
  giftCard: [/gift card/i, /itunes card/i, /google play card/i, /amazon card/i, /buy.*card.*send/i],
  crypto: [/bitcoin/i, /ethereum/i, /crypto/i, /wallet address/i, /btc/i, /eth/i, /usdt/i, /send.*coin/i],
  offPlatform: [/whatsapp/i, /telegram/i, /signal me/i, /text me at/i, /my personal number/i, /dm me on instagram/i, /move.*off.*platform/i],
};

function localPrescreen(text) {
  for (const [flagType, patterns] of Object.entries(SCAM_PATTERNS)) {
    for (const pattern of patterns) {
      if (pattern.test(text)) return flagType;
    }
  }
  return null;
}

// ── scanMessageForScam ────────────────────────────────────────────────────────

exports.scanMessageForScam = onCall({ enforceAppCheck: false }, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, messageText, senderId } = request.data ?? {};
  if (!spaceId || !messageText) {
    throw new HttpsError("invalid-argument", "spaceId and messageText are required.");
  }

  const flagType = localPrescreen(messageText);
  if (!flagType) return { flagged: false, flag: null };

  const flagId = `flag_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
  const flag = {
    id: flagId, spaceId,
    flagType, messageText,
    suspectedUserId: senderId ?? userId,
    reportedAt: FieldValue.serverTimestamp(),
    isReviewed: false, reviewedAt: null,
    resolvedAction: null,
  };

  await db.collection("spaces").doc(spaceId).collection("scamFlags").doc(flagId).set(flag);

  return { flagged: true, flag: { ...flag, reportedAt: null } };
});

// ── verifyHost ────────────────────────────────────────────────────────────────

exports.verifyHost = onCall({ enforceAppCheck: false }, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, verificationStatus } = request.data ?? {};
  if (!spaceId) throw new HttpsError("invalid-argument", "spaceId is required.");
  if (!["verified", "rejected", "pending"].includes(verificationStatus)) {
    throw new HttpsError("invalid-argument", "verificationStatus must be verified, rejected, or pending.");
  }

  // Only an admin-flagged user can call verify (production: check admin custom claim)
  // For now we do a Firestore-level admin check
  const adminSnap = await db.collection("admins").doc(userId).get();
  if (!adminSnap.exists) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }

  await db.collection("spaces").doc(spaceId).collection("settings").doc("hostProfile").update({
    verificationStatus,
    verifiedAt: verificationStatus === "verified" ? FieldValue.serverTimestamp() : null,
    verifiedBy: verificationStatus === "verified" ? userId : null,
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { ok: true, verificationStatus };
});

// ── submitModerationAction ────────────────────────────────────────────────────

exports.submitModerationAction = onCall({ enforceAppCheck: false }, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, targetUserId, actionType, reason, reportId } = request.data ?? {};
  if (!spaceId || !targetUserId || !actionType) {
    throw new HttpsError("invalid-argument", "spaceId, targetUserId, and actionType are required.");
  }

  const validActions = ["warn", "mute", "kick", "ban", "approveJoin", "denyJoin", "clearReport"];
  if (!validActions.includes(actionType)) {
    throw new HttpsError("invalid-argument", `actionType must be one of: ${validActions.join(", ")}.`);
  }

  const spaceSnap = await db.collection("spaces").doc(spaceId).get();
  const isHostOrMod = spaceSnap.data()?.hostUserId === userId ||
    (spaceSnap.data()?.moderatorIds ?? []).includes(userId);
  if (!isHostOrMod) {
    throw new HttpsError("permission-denied", "Only the host or mods can take moderation actions.");
  }

  const actionId = `mod_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
  const batch = db.batch();

  batch.set(db.collection("spaces").doc(spaceId).collection("moderationLog").doc(actionId), {
    id: actionId, spaceId,
    actorUserId: userId, targetUserId,
    actionType, reason: reason ?? null,
    reportId: reportId ?? null,
    createdAt: FieldValue.serverTimestamp(),
  });

  if (actionType === "ban") {
    batch.set(
      db.collection("spaces").doc(spaceId).collection("bans").doc(targetUserId),
      { userId: targetUserId, bannedAt: FieldValue.serverTimestamp(), bannedBy: userId }
    );
  }

  if (reportId && actionType === "clearReport") {
    batch.update(
      db.collection("spaces").doc(spaceId).collection("reports").doc(reportId),
      { resolved: true, resolvedAt: FieldValue.serverTimestamp(), resolvedBy: userId }
    );
  }

  await batch.commit();
  return { actionId, ok: true };
});

// ── reviewJoinRequest ─────────────────────────────────────────────────────────

exports.reviewJoinRequest = onCall({ enforceAppCheck: false }, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, requestUserId, decision } = request.data ?? {};
  if (!spaceId || !requestUserId) {
    throw new HttpsError("invalid-argument", "spaceId and requestUserId are required.");
  }
  if (!["approve", "deny"].includes(decision)) {
    throw new HttpsError("invalid-argument", "decision must be approve or deny.");
  }

  const spaceSnap = await db.collection("spaces").doc(spaceId).get();
  const isHostOrMod = spaceSnap.data()?.hostUserId === userId ||
    (spaceSnap.data()?.moderatorIds ?? []).includes(userId);
  if (!isHostOrMod) {
    throw new HttpsError("permission-denied", "Only the host or mods can review join requests.");
  }

  const joinReqRef = db.collection("spaces").doc(spaceId)
    .collection("joinRequests").doc(requestUserId);
  const batch = db.batch();

  batch.update(joinReqRef, {
    status: decision === "approve" ? "approved" : "denied",
    reviewedBy: userId,
    reviewedAt: FieldValue.serverTimestamp(),
  });

  if (decision === "approve") {
    batch.set(
      db.collection("spaces").doc(spaceId).collection("members").doc(requestUserId),
      { userId: requestUserId, joinedAt: FieldValue.serverTimestamp(), role: "member" }
    );
  }

  await batch.commit();
  return { ok: true, decision };
});
