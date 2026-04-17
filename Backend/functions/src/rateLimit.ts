/**
 * rateLimit.ts
 *
 * Shared per-user rate limiting for Cloud Functions.
 * Uses Firestore transactions to atomically increment a sliding-window counter.
 *
 * Storage layout:
 *   rateLimits/{uid}/windows/{windowKey}
 *     - count:     number  (calls in current window)
 *     - windowEnd: number  (Unix ms when the current window expires)
 *
 * The windowKey is "{functionName}_{windowSizeMs}_{windowStartMs}" — using the
 * window-start epoch rounded to windowSizeMs ensures every process agrees on
 * the same document without clock skew.
 *
 * CRITICAL-CF FIX: Without per-user rate limiting, a single authenticated user
 * can hammer bereanChatProxy / openAIProxy in a tight loop and exhaust the
 * project's API quota or generate large unexpected AI spend.
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

const db = admin.firestore();

export interface RateLimitConfig {
    /** Logical name for the limit window (e.g. "berean_1min") */
    name: string;
    /** Window length in milliseconds */
    windowMs: number;
    /** Maximum calls allowed within the window */
    maxCalls: number;
}

/**
 * Standard presets used across the project.
 *
 * AI Proxies:
 *   - 20 calls / minute   — prevents burst abuse while covering legitimate fast use
 *   - 200 calls / day     — daily token budget cap per user (~$0.05 at Haiku pricing)
 *
 * Suggested accounts rail:
 *   - 10 calls / minute   — heavy Firestore reads; cache should handle most traffic
 *   - 100 calls / day     — generous enough for normal app sessions
 */
export const RATE_LIMITS = {
    AI_PER_MINUTE: { name: "ai_1min", windowMs: 60_000, maxCalls: 20 } as RateLimitConfig,
    AI_PER_DAY:    { name: "ai_1day", windowMs: 86_400_000, maxCalls: 200 } as RateLimitConfig,
    SUGGEST_PER_MINUTE: { name: "suggest_1min", windowMs: 60_000, maxCalls: 10 } as RateLimitConfig,
    SUGGEST_PER_DAY:    { name: "suggest_1day", windowMs: 86_400_000, maxCalls: 100 } as RateLimitConfig,
    // Berean Spiritual Intelligence — same budget as AI proxy (used by berean/controllers)
    bereanPerMinute:    { name: "berean_1min", windowMs: 60_000, maxCalls: 20 } as RateLimitConfig,
    bereanDailyBudget:  { name: "berean_1day", windowMs: 86_400_000, maxCalls: 200 } as RateLimitConfig,
} as const;

/**
 * Check and increment a rate-limit counter for a user.
 * Throws `functions.https.HttpsError("resource-exhausted", ...)` if the
 * user has exceeded any of the supplied limits.
 *
 * @param uid   The authenticated user's UID.
 * @param limits One or more RateLimitConfig windows to enforce simultaneously.
 */
export async function enforceRateLimit(
    uid: string,
    limits: RateLimitConfig[]
): Promise<void> {
    const now = Date.now();

    // Check + increment all windows in parallel.
    await Promise.all(limits.map(async (limit) => {
        // Round down to window boundary for a consistent document key.
        const windowStart = Math.floor(now / limit.windowMs) * limit.windowMs;
        const windowEnd   = windowStart + limit.windowMs;
        const docId       = `${limit.name}_${windowStart}`;
        const ref         = db.collection("rateLimits").doc(uid)
                              .collection("windows").doc(docId);

        await db.runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            const data = snap.exists ? (snap.data() as { count: number; windowEnd: number }) : null;

            // If the stored window has expired, treat it as zero.
            const currentCount = (data && data.windowEnd > now) ? data.count : 0;

            if (currentCount >= limit.maxCalls) {
                const retryAfterSec = Math.ceil((windowEnd - now) / 1000);
                functions.logger.warn(
                    `[RateLimit] uid=${uid} limit=${limit.name} count=${currentCount}/${limit.maxCalls}`
                );
                throw new functions.https.HttpsError(
                    "resource-exhausted",
                    `Too many requests. Please wait ${retryAfterSec} seconds before trying again.`
                );
            }

            // Increment within the transaction.
            tx.set(ref, {
                count: currentCount + 1,
                windowEnd,
                uid,
                limitName: limit.name,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        });
    }));
}
