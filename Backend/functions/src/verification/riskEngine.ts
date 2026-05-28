/**
 * riskEngine.ts
 *
 * Verification risk scoring and per-action rate limiting.
 *
 * Risk signals are fetched from Firestore users/{uid} and related collections.
 * Each signal contributes a point value; the total maps to a risk level:
 *   0–2   → low
 *   3–5   → medium
 *   6–9   → high
 *   10+   → blocked
 *
 * Rate limiting uses Firestore rateLimits/{uid}/actions/{action} with a
 * sliding-window count + windowStart field (1-hour window).
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

const db = admin.firestore();
const auth = admin.auth();

// ─── Types ────────────────────────────────────────────────────────────────────

export type RiskLevel = "low" | "medium" | "high" | "blocked";

export interface RiskResult {
    level: RiskLevel;
    score: number;
    signals: string[];
}

// ─── Scoring constants ────────────────────────────────────────────────────────

const SCORE_LOW    = 1;
const SCORE_MEDIUM = 2;
const SCORE_HIGH   = 3;
const SCORE_BLOCK  = 10; // instant blocked level

const THRESHOLD_BLOCKED = 10;
const THRESHOLD_HIGH    = 6;
const THRESHOLD_MEDIUM  = 3;

// ─── calculateRiskScore ───────────────────────────────────────────────────────

/**
 * Calculates a composite risk score for the given uid by evaluating multiple
 * signals from Firestore and Firebase Auth. Returns the risk level, numeric
 * score, and array of triggered signal names.
 */
export async function calculateRiskScore(uid: string): Promise<RiskResult> {
    const now = Date.now();
    const signals: string[] = [];
    let score = 0;

    // ── Fetch user document ──────────────────────────────────────────────────
    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.exists ? (userSnap.data() as Record<string, unknown>) : {};

    // ── Signal: account age ──────────────────────────────────────────────────
    const createdAt = toMs(userData.createdAt);
    if (createdAt !== null) {
        const ageMs = now - createdAt;
        const ageDays = ageMs / (1000 * 60 * 60 * 24);
        if (ageDays < 7) {
            signals.push("account_age_very_new");
            score += SCORE_HIGH;
        } else if (ageDays < 30) {
            signals.push("account_age_new");
            score += SCORE_MEDIUM;
        }
    }

    // ── Signal: email verified (from Firebase Auth) ──────────────────────────
    try {
        const userRecord = await auth.getUser(uid);
        if (!userRecord.emailVerified) {
            signals.push("email_not_verified");
            score += SCORE_MEDIUM;
        }
    } catch {
        // If user record is not found, treat email as unverified
        signals.push("email_not_verified");
        score += SCORE_MEDIUM;
    }

    // ── Signal: phone verified ────────────────────────────────────────────────
    if (userData.phoneVerified !== true) {
        signals.push("phone_not_verified");
        score += SCORE_LOW;
    }

    // ── Signal: recent password reset ─────────────────────────────────────────
    // lastPasswordResetAt > 7 days ago = medium risk
    const lastPasswordResetAt = toMs(userData.lastPasswordResetAt);
    if (lastPasswordResetAt !== null) {
        const daysSinceReset = (now - lastPasswordResetAt) / (1000 * 60 * 60 * 24);
        if (daysSinceReset <= 7) {
            signals.push("recent_password_reset");
            score += SCORE_MEDIUM;
        }
    }

    // ── Signal: recent email change ───────────────────────────────────────────
    // lastEmailChangedAt within last 30 days = high risk
    const lastEmailChangedAt = toMs(userData.lastEmailChangedAt);
    if (lastEmailChangedAt !== null) {
        const daysSinceEmailChange = (now - lastEmailChangedAt) / (1000 * 60 * 60 * 24);
        if (daysSinceEmailChange <= 30) {
            signals.push("recent_email_change");
            score += SCORE_HIGH;
        }
    }

    // ── Signal: recent phone change ───────────────────────────────────────────
    // lastPhoneChangedAt within last 30 days = medium risk
    const lastPhoneChangedAt = toMs(userData.lastPhoneChangedAt);
    if (lastPhoneChangedAt !== null) {
        const daysSincePhoneChange = (now - lastPhoneChangedAt) / (1000 * 60 * 60 * 24);
        if (daysSincePhoneChange <= 30) {
            signals.push("recent_phone_change");
            score += SCORE_MEDIUM;
        }
    }

    // ── Signal: prior moderation actions ─────────────────────────────────────
    const moderationActionCount = typeof userData.moderationActionCount === "number"
        ? userData.moderationActionCount
        : 0;
    if (moderationActionCount > 3) {
        signals.push("prior_moderation_actions_severe");
        score += SCORE_HIGH;
    } else if (moderationActionCount > 0) {
        signals.push("prior_moderation_actions");
        score += SCORE_MEDIUM;
    }

    // ── Signal: open impersonation reports ───────────────────────────────────
    const impersonationSnap = await db
        .collection("impersonationReports")
        .where("targetUid", "==", uid)
        .where("status", "==", "open")
        .get();
    if (!impersonationSnap.empty) {
        signals.push("open_impersonation_reports");
        score += SCORE_HIGH;
    }

    // ── Signal: unusual request volume (blocked threshold) ───────────────────
    const sevenDaysAgo = new Date(now - 7 * 24 * 60 * 60 * 1000);
    const verificationRequestsSnap = await db
        .collection("users")
        .doc(uid)
        .collection("verificationRequests")
        .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(sevenDaysAgo))
        .get();
    if (verificationRequestsSnap.size > 5) {
        signals.push("unusual_request_volume");
        score += SCORE_BLOCK;
    }

    // ── Determine level ───────────────────────────────────────────────────────
    let level: RiskLevel;
    if (score >= THRESHOLD_BLOCKED) {
        level = "blocked";
    } else if (score >= THRESHOLD_HIGH) {
        level = "high";
    } else if (score >= THRESHOLD_MEDIUM) {
        level = "medium";
    } else {
        level = "low";
    }

    return { level, score, signals };
}

// ─── checkRateLimit ───────────────────────────────────────────────────────────

/**
 * Enforces a per-user, per-action rate limit using a 1-hour sliding window.
 * Uses Firestore rateLimits/{uid}/actions/{action} with count + windowStart.
 * Throws HttpsError("resource-exhausted") if the limit is exceeded.
 */
export async function checkRateLimit(
    uid: string,
    action: string,
    maxPerHour: number
): Promise<void> {
    const now = Date.now();
    const windowMs = 60 * 60 * 1000; // 1 hour
    const windowStart = Math.floor(now / windowMs) * windowMs;

    const ref = db
        .collection("rateLimits")
        .doc(uid)
        .collection("actions")
        .doc(action);

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const data = snap.exists
            ? (snap.data() as { count: number; windowStart: number })
            : null;

        // If the stored window has expired, reset count
        const currentCount =
            data && data.windowStart === windowStart ? data.count : 0;

        if (currentCount >= maxPerHour) {
            const retryAfterSec = Math.ceil((windowStart + windowMs - now) / 1000);
            throw new functions.https.HttpsError(
                "resource-exhausted",
                `Too many requests. Please wait ${retryAfterSec} seconds before trying again.`
            );
        }

        tx.set(ref, {
            count: currentCount + 1,
            windowStart,
            uid,
            action,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    });
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Converts a Firestore Timestamp, Date, or number to a Unix millisecond value.
 * Returns null if the value is absent or unrecognised.
 */
function toMs(value: unknown): number | null {
    if (value == null) return null;
    if (typeof value === "number") return value;
    if (value instanceof Date) return value.getTime();
    // Firestore Timestamp shape
    if (
        typeof value === "object" &&
        value !== null &&
        "toMillis" in value &&
        typeof (value as { toMillis: unknown }).toMillis === "function"
    ) {
        return (value as { toMillis: () => number }).toMillis();
    }
    if (
        typeof value === "object" &&
        value !== null &&
        "seconds" in value &&
        typeof (value as { seconds: unknown }).seconds === "number"
    ) {
        return (value as { seconds: number }).seconds * 1000;
    }
    return null;
}
