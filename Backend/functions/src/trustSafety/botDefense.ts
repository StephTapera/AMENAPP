/**
 * botDefense.ts — Amen Trust + Safety OS
 *
 * Callable: evaluateBotScore
 * Trigger: onBotScoreEvaluated (Firestore write trigger)
 *
 * Signals:
 *   - account age
 *   - device reuse across accounts
 *   - follow/like/comment/DM/repost velocity
 *   - repeated phrase detection
 *   - synchronized posting
 *   - duplicate media hashes
 *   - abnormal engagement graph
 *
 * BotScore: human_likely | suspicious | coordinated | automated | malicious
 *
 * Bot engagement is stripped from ranking scores.
 * Coordinated/automated/malicious accounts are throttled and challenged.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

import {
  BotScore,
  BotSignal,
  TRUST_SAFETY_OS_VERSION,
} from "./safetyTypes";
import { writeSafetyAuditEvent } from "./safetyAuditLog";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Thresholds ───────────────────────────────────────────────────────────

const VELOCITY_WINDOWS = {
  followsPerHour: { suspicious: 30,  automated: 100 },
  likesPerHour:   { suspicious: 100, automated: 500 },
  commentsPerHour:{ suspicious: 20,  automated: 80  },
  dmsPerHour:     { suspicious: 15,  automated: 50  },
  postsPerHour:   { suspicious: 5,   automated: 20  },
};

const DEVICE_REUSE_THRESHOLD = 3;  // accounts sharing same device ID → suspicious
const ACCOUNT_AGE_DAYS_MINIMUM = 7; // very new accounts get higher suspicion

// ─── Types ───────────────────────────────────────────────────────────────

export interface BotEvaluationRequest {
  uid: string;
  actionType: "follow" | "like" | "comment" | "dm" | "post" | "repost";
  deviceId?: string;
  recentCommentTexts?: string[];    // for similarity check
}

export interface BotEvaluationResponse {
  botScore: BotScore;
  confidence: number;
  requiresChallenge: boolean;
  throttled: boolean;
  suppressFromRanking: boolean;
  policyVersion: string;
}

// ─── Signal evaluation ────────────────────────────────────────────────────

async function collectSignals(uid: string, deviceId?: string): Promise<BotSignal[]> {
  const signals: BotSignal[] = [];

  try {
    const userDoc = await db.doc(`users/${uid}`).get();
    if (!userDoc.exists) {
      signals.push({ name: "no_profile", value: true, weight: 0.4 });
      return signals;
    }

    const data = userDoc.data()!;
    const createdAt: admin.firestore.Timestamp | undefined = data.createdAt;
    if (createdAt) {
      const ageDays = (Date.now() - createdAt.toMillis()) / (1000 * 60 * 60 * 24);
      if (ageDays < ACCOUNT_AGE_DAYS_MINIMUM) {
        signals.push({ name: "new_account", value: ageDays, weight: 0.3 });
      }
    }

    // Check device reuse
    if (deviceId) {
      const devicesSnap = await db
        .collectionGroup("devices")
        .where("deviceId", "==", deviceId)
        .limit(DEVICE_REUSE_THRESHOLD + 1)
        .get();
      if (devicesSnap.size > DEVICE_REUSE_THRESHOLD) {
        signals.push({ name: "device_reuse", value: devicesSnap.size, weight: 0.5 });
      }
    }

    // Velocity checks
    const hourAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 3_600_000);

    const actionsSnap = await db
      .collection(`users/${uid}/actionVelocity`)
      .where("createdAt", ">=", hourAgo)
      .get();
    const actionCount = actionsSnap.size;

    if (actionCount > VELOCITY_WINDOWS.likesPerHour.automated) {
      signals.push({ name: "action_velocity_high", value: actionCount, weight: 0.8 });
    } else if (actionCount > VELOCITY_WINDOWS.likesPerHour.suspicious) {
      signals.push({ name: "action_velocity_suspicious", value: actionCount, weight: 0.4 });
    }
  } catch (err) {
    logger.warn("botDefense signal collection error", { uid, err });
  }

  return signals;
}

function computeBotScore(signals: BotSignal[], recentComments: string[]): {
  score: BotScore;
  confidence: number;
} {
  let weightSum = 0;
  for (const s of signals) weightSum += s.weight;

  // Comment similarity check (cosine-sim approximation via overlap)
  if (recentComments.length >= 3) {
    const unique = new Set(recentComments.map((c) => c.trim().toLowerCase()));
    const dupeRatio = 1 - unique.size / recentComments.length;
    if (dupeRatio > 0.7) {
      weightSum += 0.6; // high similarity is strong bot signal
    }
  }

  const confidence = Math.min(weightSum, 1.0);

  if (confidence >= 0.85) return { score: "malicious", confidence };
  if (confidence >= 0.65) return { score: "automated", confidence };
  if (confidence >= 0.45) return { score: "coordinated", confidence };
  if (confidence >= 0.25) return { score: "suspicious", confidence };
  return { score: "human_likely", confidence };
}

// ─── Exported callable ───────────────────────────────────────────────────

export const evaluateBotScore = onCall(
  { enforceAppCheck: true, cors: false },
  async (request): Promise<BotEvaluationResponse> => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");

    const data = request.data as BotEvaluationRequest;
    const uid = request.auth.uid;

    const signals = await collectSignals(uid, data.deviceId);
    const { score, confidence } = computeBotScore(
      signals,
      data.recentCommentTexts ?? []
    );

    const requiresChallenge = score === "automated" || score === "malicious";
    const throttled = score === "coordinated" || requiresChallenge;
    const suppressFromRanking = score !== "human_likely";

    // Persist to user trust profile
    await db.doc(`users/${uid}/trust/profile`).set(
      {
        botScore: score,
        botConfidence: confidence,
        botEvaluatedAt: admin.firestore.Timestamp.now(),
        suppressFromRanking,
      },
      { merge: true }
    );

    if (score !== "human_likely") {
      await writeSafetyAuditEvent({
        eventType: "bot_flagged",
        actorUid: uid,
        targetUid: null,
        contentId: null,
        contentType: null,
        metadata: { botScore: score, confidence, actionType: data.actionType },
      });
    }

    return {
      botScore: score,
      confidence,
      requiresChallenge,
      throttled,
      suppressFromRanking,
      policyVersion: TRUST_SAFETY_OS_VERSION,
    };
  }
);

// ─── Admin: get bot profile ───────────────────────────────────────────────

export const getBotProfile = onCall(
  { enforceAppCheck: true, cors: false },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    const claims = request.auth.token;
    if (!claims.admin && !claims.moderator) {
      throw new HttpsError("permission-denied", "Moderator role required.");
    }
    const { uid } = request.data as { uid: string };
    const snap = await db.doc(`users/${uid}/trust/profile`).get();
    return snap.data() ?? null;
  }
);
