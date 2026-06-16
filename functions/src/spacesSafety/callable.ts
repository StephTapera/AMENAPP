// callable.ts — Callable Cloud Functions for Spaces Safety (scam scan, host verify, moderation)

import * as functions from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

const db = getFirestore();

// ── Types ─────────────────────────────────────────────────────────────────────

interface ScanMessageRequest {
  messageId: string;
  authorId: string;
  text: string;
}

interface VerifyHostRequest {
  spaceId: string;
}

interface ModerationActionRequest {
  spaceId: string;
  targetUserId: string;
  actionType: string;
  reason: string;
}

interface ReviewJoinRequestPayload {
  spaceId: string;
  requestUserId: string;
  approved: boolean;
}

interface ScamFlag {
  id: string;
  messageId: string;
  authorId: string;
  reporterUid: string;
  flagTypes: string[];
  confidence: number;
  surfaced: boolean;
  reviewedByHuman: boolean;
  flaggedAt: ReturnType<typeof Timestamp.now>;
}

interface SpaceDoc {
  hostUserId: string;
  modIds?: string[];
  memberIds?: string[];
}

interface JoinRequestDoc {
  requestUserId: string;
  status: string;
}

type ModerationActionType =
  | "mute"
  | "unmute"
  | "block"
  | "removePost"
  | "approveJoin"
  | "denyJoin"
  | "assignModRole"
  | "removeModRole"
  | "reportToReviewQueue";

const VALID_ACTION_TYPES: ModerationActionType[] = [
  "mute",
  "unmute",
  "block",
  "removePost",
  "approveJoin",
  "denyJoin",
  "assignModRole",
  "removeModRole",
  "reportToReviewQueue",
];

// ── Helpers ───────────────────────────────────────────────────────────────────

async function assertHostOrMod(spaceId: string, userId: string): Promise<SpaceDoc> {
  const spaceSnap = await db.collection("spaces").doc(spaceId).get();
  if (!spaceSnap.exists) {
    throw new functions.HttpsError("not-found", "Space not found.");
  }
  const space = spaceSnap.data() as SpaceDoc;
  const isHost = space.hostUserId === userId;
  const isMod = (space.modIds ?? []).includes(userId);
  if (!isHost && !isMod) {
    throw new functions.HttpsError("permission-denied", "Only the host or a moderator can perform this action.");
  }
  return space;
}

// ── scanMessageForScam ────────────────────────────────────────────────────────

export const scanMessageForScam = functions.onCall(
  { enforceAppCheck: true // enforceAppCheck: true — requires App Check token; disable locally via FUNCTIONS_EMULATOR env var if needed },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as ScanMessageRequest;
    const messageId = String(data?.messageId ?? "").trim();
    const authorId = String(data?.authorId ?? "").trim();
    const text = String(data?.text ?? "").trim();

    if (!messageId) throw new functions.HttpsError("invalid-argument", "messageId is required.");
    if (!authorId) throw new functions.HttpsError("invalid-argument", "authorId is required.");
    if (!text || text.length < 1) {
      throw new functions.HttpsError("invalid-argument", "text is required.");
    }
    if (text.length > 2000) {
      throw new functions.HttpsError("invalid-argument", "text must be 2000 characters or fewer.");
    }

    const patterns: Record<string, RegExp> = {
      moneyRequest: /send me|transfer|venmo|zelle|payment/i,
      giftCardRequest: /gift card|apple card|google play/i,
      cryptoRequest: /bitcoin|crypto|wallet address|eth |usdt/i,
      offPlatformPayment: /outside the app|off platform|direct pay/i,
      impersonation: /i am the (pastor|bishop|admin|official)/i,
    };

    const flagTypes: string[] = [];
    for (const [flagType, pattern] of Object.entries(patterns)) {
      if (pattern.test(text)) {
        flagTypes.push(flagType);
      }
    }

    if (flagTypes.length === 0) {
      return { flag: null };
    }

    const flag: ScamFlag = {
      id: messageId,
      messageId,
      authorId,
      reporterUid: userId,
      flagTypes,
      confidence: 0.85,
      surfaced: true,
      reviewedByHuman: false,
      flaggedAt: Timestamp.now(),
    };

    await db.collection("scamFlags").doc(messageId).set(flag);
    logger.warn(`scanMessageForScam: message ${messageId} flagged for [${flagTypes.join(", ")}]`);

    return { flag };
  }
);

// ── verifyHost ────────────────────────────────────────────────────────────────

export const verifyHost = functions.onCall(
  { enforceAppCheck: true // enforceAppCheck: true — requires App Check token; disable locally via FUNCTIONS_EMULATOR env var if needed },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as VerifyHostRequest;
    const spaceId = String(data?.spaceId ?? "").trim();

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");

    // Verify the caller is a platform admin
    const adminSnap = await db.collection("admins").doc(userId).get();
    if (!adminSnap.exists) {
      throw new functions.HttpsError("permission-denied", "Only platform admins can verify hosts.");
    }

    const hostProfileRef = db.collection("spaces").doc(spaceId).collection("settings").doc("hostProfile");
    await hostProfileRef.set(
      {
        verificationStatus: "verified",
        verifiedAt: FieldValue.serverTimestamp(),
        verifiedBy: userId,
      },
      { merge: true }
    );

    logger.info(`verifyHost: space ${spaceId} verified by admin ${userId}`);

    return { ok: true, verificationStatus: "verified" };
  }
);

// ── submitModerationAction ────────────────────────────────────────────────────

export const submitModerationAction = functions.onCall(
  { enforceAppCheck: true // enforceAppCheck: true — requires App Check token; disable locally via FUNCTIONS_EMULATOR env var if needed },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as ModerationActionRequest;
    const spaceId = String(data?.spaceId ?? "").trim();
    const targetUserId = String(data?.targetUserId ?? "").trim();
    const actionType = String(data?.actionType ?? "").trim();
    const reason = String(data?.reason ?? "").trim();

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!targetUserId) throw new functions.HttpsError("invalid-argument", "targetUserId is required.");
    if (!reason) throw new functions.HttpsError("invalid-argument", "reason is required.");

    if (!(VALID_ACTION_TYPES as string[]).includes(actionType)) {
      throw new functions.HttpsError(
        "invalid-argument",
        `actionType must be one of: ${VALID_ACTION_TYPES.join(", ")}.`
      );
    }

    const typedAction = actionType as ModerationActionType;

    await assertHostOrMod(spaceId, userId);

    const logRef = db.collection("spaces").doc(spaceId).collection("moderationLog").doc();
    const actionId = logRef.id;

    const batch = db.batch();

    batch.set(logRef, {
      id: actionId,
      targetUserId,
      spaceId,
      actionType: typedAction,
      reason,
      performedBy: userId,
      performedAt: FieldValue.serverTimestamp(),
    });

    const spaceRef = db.collection("spaces").doc(spaceId);

    if (typedAction === "mute") {
      const muteRef = spaceRef.collection("mutes").doc(targetUserId);
      batch.set(muteRef, { mutedBy: userId, mutedAt: Timestamp.now() });
    } else if (typedAction === "block") {
      const blockRef = spaceRef.collection("blocks").doc(targetUserId);
      batch.set(blockRef, { blockedBy: userId, blockedAt: Timestamp.now() });
    } else if (typedAction === "assignModRole") {
      batch.update(spaceRef, { modIds: FieldValue.arrayUnion(targetUserId) });
    } else if (typedAction === "removeModRole") {
      batch.update(spaceRef, { modIds: FieldValue.arrayRemove(targetUserId) });
    }

    await batch.commit();
    logger.info(`submitModerationAction: ${typedAction} on ${targetUserId} in space ${spaceId} by ${userId}`);

    return { ok: true, actionId };
  }
);

// ── reviewJoinRequest ─────────────────────────────────────────────────────────

export const reviewJoinRequest = functions.onCall(
  { enforceAppCheck: true // enforceAppCheck: true — requires App Check token; disable locally via FUNCTIONS_EMULATOR env var if needed },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as ReviewJoinRequestPayload;
    const spaceId = String(data?.spaceId ?? "").trim();
    const requestUserId = String(data?.requestUserId ?? "").trim();
    const approved = Boolean(data?.approved);

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!requestUserId) throw new functions.HttpsError("invalid-argument", "requestUserId is required.");

    await assertHostOrMod(spaceId, userId);

    const joinRequestRef = db
      .collection("spaces").doc(spaceId)
      .collection("joinRequests").doc(requestUserId);
    const joinRequestSnap = await joinRequestRef.get();

    if (!joinRequestSnap.exists) {
      throw new functions.HttpsError("not-found", "Join request not found.");
    }

    const joinRequest = joinRequestSnap.data() as JoinRequestDoc;
    if (joinRequest.status !== "pending") {
      throw new functions.HttpsError(
        "failed-precondition",
        `Join request is already ${joinRequest.status}.`
      );
    }

    const spaceRef = db.collection("spaces").doc(spaceId);
    const logRef = spaceRef.collection("moderationLog").doc();
    const batch = db.batch();

    if (approved) {
      // Add to memberIds and remove the join request
      batch.update(spaceRef, { memberIds: FieldValue.arrayUnion(requestUserId) });
      batch.delete(joinRequestRef);
      batch.set(logRef, {
        id: logRef.id,
        targetUserId: requestUserId,
        spaceId,
        actionType: "approveJoin",
        reason: "Join request approved.",
        performedBy: userId,
        performedAt: FieldValue.serverTimestamp(),
      });
    } else {
      // Mark denied; keep the request doc for audit purposes
      batch.update(joinRequestRef, { status: "denied", reviewedBy: userId, reviewedAt: Timestamp.now() });
      batch.set(logRef, {
        id: logRef.id,
        targetUserId: requestUserId,
        spaceId,
        actionType: "denyJoin",
        reason: "Join request denied.",
        performedBy: userId,
        performedAt: FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    logger.info(`reviewJoinRequest: user ${requestUserId} ${approved ? "approved" : "denied"} for space ${spaceId} by ${userId}`);

    return { ok: true, approved };
  }
);
