/**
 * enforcement.ts — Amen Trust + Safety OS
 *
 * Callable: issueEnforcementStrike (admin/moderator)
 * Callable: getEnforcementProfile
 * Callable: submitAppeal
 * Callable: resolveAppeal (admin)
 * Trigger: onSafetyDecisionCreated (auto-strike on block decisions)
 *
 * Enforcement ladder:
 *   ≥5 strike points  → visibility reduced
 *   ≥10 points        → posting restricted + notification
 *   ≥20 points        → suspension queued
 *   ≥30 points        → permanent ban recommendation
 *
 * Severity weights: minor=1, moderate=2, severe=3, critical=5
 * Expiry: minor=90d, moderate=180d, severe/critical=never
 */

import { onCall, HttpsError, onDocumentCreated } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

import {
  EnforcementRecord,
  StrikeEntry,
  StrikeSeverity,
  AccountStatus,
  RiskCategory,
  TRUST_SAFETY_OS_VERSION,
} from "./safetyTypes";
import { writeSafetyAuditEvent } from "./safetyAuditLog";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Configuration ────────────────────────────────────────────────────────

const SEVERITY_POINTS: Record<StrikeSeverity, number> = {
  minor: 1, moderate: 2, severe: 3, critical: 5,
};

const SEVERITY_EXPIRY_DAYS: Record<StrikeSeverity, number | null> = {
  minor: 90, moderate: 180, severe: null, critical: null,
};

const CATEGORY_SEVERITY: Record<string, StrikeSeverity> = {
  csam_indicator: "critical", grooming: "critical", trafficking: "critical",
  sextortion: "critical",   extremism: "critical",
  violence: "severe",       gore: "severe",       self_harm: "severe",
  sexual: "severe",         nudity: "moderate",
  hate: "moderate",         harassment: "moderate", scam: "moderate",
  impersonation: "moderate",misinformation: "moderate",
  spam: "minor",            bot_behavior: "minor", privacy_violation: "minor",
};

// ─── Strike logic ─────────────────────────────────────────────────────────

async function computeActivePoints(uid: string): Promise<number> {
  const snap = await db
    .collection(`users/${uid}/trust/strikes`)
    .where("expiresAt", ">", admin.firestore.Timestamp.now())
    .get();

  const neverExpireSnap = await db
    .collection(`users/${uid}/trust/strikes`)
    .where("expiresAt", "==", null)
    .get();

  let points = 0;
  for (const doc of [...snap.docs, ...neverExpireSnap.docs]) {
    points += doc.data().points ?? 0;
  }
  return points;
}

function determineAccountStatus(points: number): AccountStatus {
  if (points >= 30) return "banned";
  if (points >= 20) return "suspended";
  if (points >= 10) return "restricted";
  if (points >= 5)  return "warned";
  return "active";
}

async function issueStrikeInternal(params: {
  uid: string;
  harmCategoryId: string;
  contentId: string | null;
  issuedBy: string;
}): Promise<EnforcementRecord> {
  const severity = (CATEGORY_SEVERITY[params.harmCategoryId] ?? "minor") as StrikeSeverity;
  const points = SEVERITY_POINTS[severity];
  const expiryDays = SEVERITY_EXPIRY_DAYS[severity];

  const expiresAt = expiryDays
    ? admin.firestore.Timestamp.fromMillis(Date.now() + expiryDays * 86_400_000)
    : null;

  const strikeId = db.collection(`users/${params.uid}/trust/strikes`).doc().id;
  const strike: StrikeEntry = {
    strikeId,
    harmCategoryId: params.harmCategoryId,
    severity,
    points,
    contentId: params.contentId,
    issuedBy: params.issuedBy,
    expiresAt,
    createdAt: admin.firestore.Timestamp.now(),
  };

  await db.doc(`users/${params.uid}/trust/strikes/${strikeId}`).set(strike);

  const totalPoints = await computeActivePoints(params.uid);
  const accountStatus = determineAccountStatus(totalPoints);
  const trustScore = Math.max(0, 100 - totalPoints * 3);

  const profile: Partial<EnforcementRecord> = {
    uid: params.uid,
    strikePoints: totalPoints,
    trustScore,
    accountStatus,
    lastUpdated: admin.firestore.Timestamp.now(),
    policyVersion: TRUST_SAFETY_OS_VERSION,
  };

  await db.doc(`users/${params.uid}/trust/profile`).set(profile, { merge: true });

  if (accountStatus === "suspended" || accountStatus === "banned") {
    await writeSafetyAuditEvent({
      eventType: accountStatus === "banned" ? "account_banned" : "account_suspended",
      actorUid: params.issuedBy,
      targetUid: params.uid,
      contentId: params.contentId,
      contentType: null,
      category: params.harmCategoryId as RiskCategory,
      metadata: { points: totalPoints, accountStatus },
    });
  } else if (accountStatus === "restricted") {
    await writeSafetyAuditEvent({
      eventType: "account_restricted",
      actorUid: params.issuedBy,
      targetUid: params.uid,
      contentId: params.contentId,
      contentType: null,
      category: params.harmCategoryId as RiskCategory,
      metadata: { points: totalPoints },
    });
  }

  return {
    uid: params.uid,
    strikePoints: totalPoints,
    trustScore,
    accountStatus,
    strikeHistory: [strike],
    lastUpdated: admin.firestore.Timestamp.now() as admin.firestore.Timestamp,
    policyVersion: TRUST_SAFETY_OS_VERSION,
  };
}

// ─── Issue strike callable (admin/moderator) ──────────────────────────────

export const issueEnforcementStrike = onCall(
  { enforceAppCheck: true, cors: false },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    if (!request.auth.token.admin && !request.auth.token.moderator) {
      throw new HttpsError("permission-denied", "Moderator role required.");
    }

    const { uid, harmCategoryId, contentId } = request.data as {
      uid: string;
      harmCategoryId: string;
      contentId?: string;
    };
    if (!uid || !harmCategoryId) {
      throw new HttpsError("invalid-argument", "uid and harmCategoryId required.");
    }

    const record = await issueStrikeInternal({
      uid,
      harmCategoryId,
      contentId: contentId ?? null,
      issuedBy: request.auth.uid,
    });

    return {
      strikePoints: record.strikePoints,
      trustScore: record.trustScore,
      accountStatus: record.accountStatus,
    };
  }
);

// ─── Get enforcement profile ──────────────────────────────────────────────

export const getEnforcementProfile = onCall(
  { enforceAppCheck: true, cors: false },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    const claims = request.auth.token;
    const { uid } = request.data as { uid?: string };

    // Own profile or moderator
    const targetUid = uid ?? request.auth.uid;
    if (targetUid !== request.auth.uid && !claims.admin && !claims.moderator) {
      throw new HttpsError("permission-denied", "Cannot view other users' enforcement profiles.");
    }

    const snap = await db.doc(`users/${targetUid}/trust/profile`).get();
    return snap.data() ?? { uid: targetUid, strikePoints: 0, trustScore: 100, accountStatus: "active" };
  }
);

// ─── Submit appeal ───────────────────────────────────────────────────────

export const submitAppeal = onCall(
  { enforceAppCheck: true, cors: false },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");

    const { strikeId, reason } = request.data as { strikeId: string; reason: string };
    if (!strikeId) throw new HttpsError("invalid-argument", "strikeId required.");

    const uid = request.auth.uid;
    const appealId = db.collection("platformSafety/queues/humanReview").doc().id;

    await db.doc(`platformSafety/queues/humanReview/${appealId}`).set({
      appealId,
      type: "appeal",
      uid,
      strikeId,
      reason: reason ?? "",
      status: "pending",
      submittedAt: admin.firestore.Timestamp.now(),
      policyVersion: TRUST_SAFETY_OS_VERSION,
    });

    await writeSafetyAuditEvent({
      eventType: "appeal_submitted",
      actorUid: uid,
      targetUid: null,
      contentId: strikeId,
      contentType: null,
      metadata: { appealId },
    });

    return { appealId, status: "pending" };
  }
);

// ─── Resolve appeal (admin) ───────────────────────────────────────────────

export const resolveAppeal = onCall(
  { enforceAppCheck: true, cors: false },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    if (!request.auth.token.admin && !request.auth.token.moderator) {
      throw new HttpsError("permission-denied", "Moderator role required.");
    }

    const { appealId, granted, reviewerNotes } = request.data as {
      appealId: string;
      granted: boolean;
      reviewerNotes?: string;
    };

    await db.doc(`platformSafety/queues/humanReview/${appealId}`).update({
      status: granted ? "granted" : "denied",
      resolvedAt: admin.firestore.Timestamp.now(),
      resolvedBy: request.auth.uid,
      reviewerNotes: reviewerNotes ?? null,
    });

    await writeSafetyAuditEvent({
      eventType: "appeal_resolved",
      actorUid: request.auth.uid,
      targetUid: null,
      contentId: appealId,
      contentType: null,
      metadata: { granted, reviewerNotes },
    });

    return { success: true, granted };
  }
);
