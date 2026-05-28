/**
 * rateLimitHelper.ts
 *
 * Per-user, per-day rate limiting utility for Berean AI callable functions.
 *
 * Storage layout:
 *   users/{uid}/rateLimits/{limitKey}_{date}
 *     - count:     number  (calls made today)
 *     - limitKey:  string  (e.g. "bereanQuery", "bereanChat")
 *     - uid:       string
 *     - date:      string  (UTC date "YYYY-MM-DD")
 *     - updatedAt: Timestamp
 *     - expiresAt: Timestamp  (48h TTL for automatic cleanup if Firestore TTL policy set)
 *
 * This is the server-side authority. The iOS AIUsageService may mirror the
 * limit for optimistic UX, but this function is the enforcement point — no
 * client can bypass it.
 *
 * Uses UTC day as the window so all server instances agree without clock skew.
 * Throws HttpsError("resource-exhausted") when the limit is exceeded.
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { FieldValue } from "firebase-admin/firestore";

export interface RateLimitConfig {
  /** Max calls allowed within a single UTC calendar day. */
  limitPerDay: number;
  /**
   * Logical key identifying this limit bucket (e.g. "bereanQuery", "bereanChat").
   * Combined with the UTC date to form the Firestore document ID.
   */
  limitKey: string;
}

/**
 * Atomically checks and increments a per-user daily rate-limit counter.
 *
 * - Uses a Firestore transaction to prevent double-counting under concurrent requests.
 * - Window resets at UTC midnight.
 * - Documents carry a 48-hour TTL (`expiresAt`) for automatic Firestore cleanup.
 *   Enable the TTL policy on `expiresAt` in the Firebase console to activate cleanup.
 *
 * @param uid    The authenticated user's UID.
 * @param config Limit key and daily ceiling.
 * @throws HttpsError("resource-exhausted") when the limit is exceeded.
 */
export async function checkAndIncrementDailyRateLimit(
  uid: string,
  config: RateLimitConfig
): Promise<void> {
  const today = new Date().toISOString().slice(0, 10); // "YYYY-MM-DD" in UTC
  const docRef = admin
    .firestore()
    .doc(`users/${uid}/rateLimits/${config.limitKey}_${today}`);

  const result = await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    const current: number = snap.exists ? (snap.data()?.count ?? 0) : 0;

    if (current >= config.limitPerDay) {
      return { allowed: false, count: current };
    }

    tx.set(
      docRef,
      {
        count: FieldValue.increment(1),
        limitKey: config.limitKey,
        uid,
        date: today,
        updatedAt: FieldValue.serverTimestamp(),
        // TTL field — enable "expiresAt" TTL policy in Firestore console to auto-delete
        expiresAt: admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + 2 * 24 * 60 * 60 * 1000) // 48 hours
        ),
      },
      { merge: true }
    );
    return { allowed: true, count: current + 1 };
  });

  if (!result.allowed) {
    logger.warn("[RateLimitHelper] Daily limit exceeded", {
      uid,
      limitKey: config.limitKey,
      date: today,
      count: result.count,
      limit: config.limitPerDay,
    });
    throw new HttpsError(
      "resource-exhausted",
      `You've reached your daily limit for this feature. It resets at midnight UTC.`
    );
  }
}

// ---------------------------------------------------------------------------
// Preset configs — use these in callable handlers for consistent limits.
// ---------------------------------------------------------------------------

/** Default Berean AI daily limits per feature. Adjust per-tier as needed. */
export const BEREAN_DAILY_LIMITS = {
  /** Standard Berean chat / query — 20 calls/day for free tier */
  bereanQuery: { limitPerDay: 20, limitKey: "bereanQuery" } as RateLimitConfig,
  /** Streaming Berean chat — same daily ceiling as the callable */
  bereanChat:  { limitPerDay: 20, limitKey: "bereanChat"  } as RateLimitConfig,
} as const;
