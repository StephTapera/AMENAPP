/**
 * TrustAndStrikeService.ts
 *
 * Strike tracking and trust score management for Amen Safety OS.
 *
 * Strike model:
 *   - Every confirmed policy violation adds a strike to the account.
 *   - Strikes are weighted by severity (minor=1, moderate=2, severe=3, critical=5).
 *   - The account's trustScore (0–100) is derived from strike history.
 *   - Thresholds trigger automatic actions:
 *       strikePoints >= 5   → content visibility reduction (shadow restrictions)
 *       strikePoints >= 10  → posting restrictions
 *       strikePoints >= 20  → account suspension (triggers accountSuspension.ts)
 *       strikePoints >= 30  → permanent ban recommendation for human review
 *
 *   - Strikes expire: minor strikes in 90 days, moderate in 180 days,
 *     severe never expire. Critical strikes permanently affect the account.
 *
 * Data model:
 *   strikes/{strikeId}
 *     uid: string
 *     weight: number
 *     severity: "minor" | "moderate" | "severe" | "critical"
 *     harmCategoryId: string
 *     contentId?: string
 *     expiresAt?: Timestamp
 *     issuedAt: Timestamp
 *     issuedBy: "server" | "admin:{uid}"
 *
 *   users/{uid}.trustScore: number (0–100)
 *   users/{uid}.strikePoints: number
 *   users/{uid}.accountStatus: "active" | "restricted" | "suspended" | "banned"
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { requiresAccountSuspension, AMEN_SAFETY_POLICY_VERSION } from "./AmenSafetyPolicy";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const auth = admin.auth();

// ─── Types ────────────────────────────────────────────────────────────────────

export type StrikeSeverity = "minor" | "moderate" | "severe" | "critical";

const STRIKE_WEIGHTS: Record<StrikeSeverity, number> = {
  minor: 1,
  moderate: 2,
  severe: 3,
  critical: 5,
};

const STRIKE_EXPIRY_DAYS: Record<StrikeSeverity, number | null> = {
  minor: 90,
  moderate: 180,
  severe: null,    // No expiry
  critical: null,  // No expiry
};

// Map harm categories to strike severity
const HARM_TO_SEVERITY: Record<string, StrikeSeverity> = {
  csam: "critical",
  grooming: "critical",
  sex_trafficking: "critical",
  human_trafficking: "critical",
  online_enticement: "critical",
  sexualized_minor: "critical",
  sexual_violence: "critical",
  terrorism: "critical",
  murder_assault_footage: "critical",
  sextortion: "severe",
  non_consensual_intimate_imagery: "severe",
  blackmail: "severe",
  stalking: "severe",
  violence_threat: "severe",
  extremism: "severe",
  drug_sales: "severe",
  illegal_weapon_sales: "severe",
  financial_fraud: "severe",
  pornography: "moderate",
  nudity: "moderate",
  sexual_content: "moderate",
  sexual_solicitation: "moderate",
  sexual_harassment: "moderate",
  graphic_violence: "moderate",
  gore: "moderate",
  hate_speech: "moderate",
  racism: "moderate",
  doxxing: "moderate",
  self_harm_encouragement: "moderate",
  scam_phishing: "moderate",
  identity_theft: "moderate",
  harassment: "minor",
  cyberbullying: "minor",
  profanity: "minor",
  spam_bot: "minor",
  misinformation: "minor",
  privacy_violation: "minor",
};

// ─── Core Strike Logic ────────────────────────────────────────────────────────

export interface StrikeRecord {
  strikeId: string;
  uid: string;
  weight: number;
  severity: StrikeSeverity;
  harmCategoryId: string;
  contentId?: string;
  expiresAt?: Date;
  issuedAt: Date;
  issuedBy: string;
}

export async function issueStrike(
  uid: string,
  harmCategoryId: string,
  contentId: string | undefined,
  issuedBy: string
): Promise<{ strikeId: string; newStrikePoints: number; actionTaken: string }> {
  const severity = HARM_TO_SEVERITY[harmCategoryId] ?? "minor";
  const weight = STRIKE_WEIGHTS[severity];
  const expiryDays = STRIKE_EXPIRY_DAYS[severity];

  const expiresAt = expiryDays
    ? new Date(Date.now() + expiryDays * 24 * 60 * 60 * 1000)
    : null;

  const strikeRef = db.collection("strikes").doc();
  await strikeRef.set({
    uid,
    weight,
    severity,
    harmCategoryId,
    contentId: contentId ?? null,
    expiresAt: expiresAt ? admin.firestore.Timestamp.fromDate(expiresAt) : null,
    issuedAt: admin.firestore.FieldValue.serverTimestamp(),
    issuedBy,
    policyVersion: AMEN_SAFETY_POLICY_VERSION,
  });

  // Recalculate strike points (excluding expired)
  const newPoints = await recalculateStrikePoints(uid);

  // Enforce account actions based on new total
  const actionTaken = await enforceStrikeThresholds(uid, newPoints, harmCategoryId);

  logger.info(`[TrustAndStrikeService] Strike issued uid=${uid} severity=${severity} points=${newPoints} action=${actionTaken}`);

  return { strikeId: strikeRef.id, newStrikePoints: newPoints, actionTaken };
}

async function recalculateStrikePoints(uid: string): Promise<number> {
  const now = admin.firestore.Timestamp.now();

  // Count active (non-expired) strikes
  const activeStrikes = await db.collection("strikes")
    .where("uid", "==", uid)
    .where("expiresAt", ">", now)
    .get();

  const neverExpiresStrikes = await db.collection("strikes")
    .where("uid", "==", uid)
    .where("expiresAt", "==", null)
    .get();

  let total = 0;
  activeStrikes.forEach((d) => { total += d.data().weight ?? 0; });
  neverExpiresStrikes.forEach((d) => { total += d.data().weight ?? 0; });

  // Update user document with new score
  const trustScore = Math.max(0, 100 - total * 3);
  await db.collection("users").doc(uid).set(
    { strikePoints: total, trustScore },
    { merge: true }
  );

  return total;
}

async function enforceStrikeThresholds(
  uid: string,
  strikePoints: number,
  harmCategoryId: string
): Promise<string> {
  // Critical harm always escalates immediately regardless of threshold
  if (requiresAccountSuspension(harmCategoryId)) {
    await db.collection("moderationQueue").add({
      type: "critical_harassment_pattern",
      offenderId: uid,
      priority: "immediate",
      harmCategoryId,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return "escalated_to_moderation_queue";
  }

  if (strikePoints >= 20) {
    // Trigger account suspension via moderationQueue (picked up by accountSuspension.ts trigger)
    await db.collection("moderationQueue").add({
      type: "critical_harassment_pattern",
      offenderId: uid,
      priority: "high",
      reason: `Strike threshold reached: ${strikePoints} points`,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return "suspension_queued";
  }

  if (strikePoints >= 10) {
    await db.collection("users").doc(uid).set(
      { accountStatus: "restricted", postingRestricted: true },
      { merge: true }
    );
    await sendAccountRestrictionNotification(uid, "posting_restricted");
    return "posting_restricted";
  }

  if (strikePoints >= 5) {
    await db.collection("users").doc(uid).set(
      { accountStatus: "restricted", visibilityReduced: true },
      { merge: true }
    );
    return "visibility_reduced";
  }

  return "none";
}

async function sendAccountRestrictionNotification(uid: string, restrictionType: string): Promise<void> {
  try {
    await db.collection("users").doc(uid).collection("notifications").add({
      type: "account_restriction",
      restrictionType,
      title: "Account Restriction",
      body: "Your account has been restricted due to repeated violations of our community guidelines.",
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    logger.warn("[TrustAndStrikeService] Failed to send restriction notification.", err);
  }
}

// ─── Trigger: Auto-issue strike on confirmed moderation action ────────────────

/**
 * When a safetyDecision document is created with action="block" or "escalate",
 * automatically issue a strike on the content author.
 */
export const autoIssueStrikeOnBlock = onDocumentCreated(
  "safetyDecisions/{decisionId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const action: string = data.actions?.[0] ?? "";
    const actorUid: string = data.actorUid ?? "";
    const harmCategory: string = data.riskCategories?.[0] ?? "";
    const contentId: string | undefined = data.contentId;

    if (!actorUid || !harmCategory) return;
    if (!["block_send", "preserve_evidence"].includes(action)) return;

    try {
      await issueStrike(actorUid, harmCategory, contentId, "server");
    } catch (err) {
      logger.error("[TrustAndStrikeService] Failed to auto-issue strike.", err);
    }
  }
);

// ─── Callable: Admin Strike Management ───────────────────────────────────────

export const adminIssueStrike = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{
    uid: string;
    harmCategoryId: string;
    contentId?: string;
    reason?: string;
  }>): Promise<{ strikeId: string; newStrikePoints: number; actionTaken: string }> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
    const token = request.auth.token as Record<string, unknown>;
    if (!token.admin && !token.moderator) {
      throw new HttpsError("permission-denied", "Moderator or admin access required.");
    }

    const { uid, harmCategoryId, contentId } = request.data;
    if (!uid || !harmCategoryId) throw new HttpsError("invalid-argument", "uid and harmCategoryId required.");

    return issueStrike(uid, harmCategoryId, contentId, `admin:${request.auth.uid}`);
  }
);

export const adminGetTrustProfile = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{ uid: string }>): Promise<{
    uid: string;
    strikePoints: number;
    trustScore: number;
    accountStatus: string;
    recentStrikes: unknown[];
  }> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
    const token = request.auth.token as Record<string, unknown>;
    if (!token.admin && !token.moderator) {
      throw new HttpsError("permission-denied", "Moderator or admin access required.");
    }

    const { uid } = request.data;
    if (!uid) throw new HttpsError("invalid-argument", "uid required.");

    const userDoc = await db.collection("users").doc(uid).get();
    const userData = userDoc.data() ?? {};

    const recentStrikesSnap = await db.collection("strikes")
      .where("uid", "==", uid)
      .orderBy("issuedAt", "desc")
      .limit(20)
      .get();

    return {
      uid,
      strikePoints: userData.strikePoints ?? 0,
      trustScore: userData.trustScore ?? 100,
      accountStatus: userData.accountStatus ?? "active",
      recentStrikes: recentStrikesSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
    };
  }
);
