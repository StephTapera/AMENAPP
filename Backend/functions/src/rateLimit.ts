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
    // Church Discovery (smartChurchSearch / bereanChurchChat / searchChurchesByKeyword)
    CHURCH_DISCOVERY_PER_MINUTE: { name: "church_discovery_1min", windowMs: 60_000, maxCalls: 10 } as RateLimitConfig,
    CHURCH_DISCOVERY_PER_DAY:    { name: "church_discovery_1day", windowMs: 86_400_000, maxCalls: 100 } as RateLimitConfig,
    // Church Suggestion (smartCommunitySearch)
    CHURCH_SUGGESTION_PER_MINUTE: { name: "church_suggest_1min", windowMs: 60_000, maxCalls: 10 } as RateLimitConfig,
    CHURCH_SUGGESTION_PER_DAY:    { name: "church_suggest_1day", windowMs: 86_400_000, maxCalls: 100 } as RateLimitConfig,
    // Community Save (setCommunitySaved)
    COMMUNITY_SAVE_PER_MINUTE: { name: "community_save_1min", windowMs: 60_000, maxCalls: 20 } as RateLimitConfig,
    COMMUNITY_SAVE_PER_DAY:    { name: "community_save_1day", windowMs: 86_400_000, maxCalls: 200 } as RateLimitConfig,
    // Smart Message Intelligence
    smartMessagePerMinute: { name: "smart_msg_1min", windowMs: 60_000, maxCalls: 15 } as RateLimitConfig,
    smartMessagePerDay:    { name: "smart_msg_1day", windowMs: 86_400_000, maxCalls: 150 } as RateLimitConfig,
    // Contextual Action Router (bereanContextualActionPerMinute)
    bereanContextualActionPerMinute: { name: "berean_ctx_1min", windowMs: 60_000, maxCalls: 20 } as RateLimitConfig,
    // Community Tone Check (validateCovenantPostSafety)
    COMMUNITY_TONE_CHECK_PER_MINUTE: { name: "community_tone_1min", windowMs: 60_000, maxCalls: 10 } as RateLimitConfig,
    COMMUNITY_TONE_CHECK_PER_DAY:    { name: "community_tone_1day", windowMs: 86_400_000, maxCalls: 100 } as RateLimitConfig,
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

// ── Global circuit breaker ────────────────────────────────────────────────────
//
// A project-wide daily ceiling on total AI calls. Once crossed, all AI proxy
// functions return a graceful degradation response instead of calling Anthropic.
// This catches runaway cost events (bug call loops, coordinated abuse) without
// requiring human intervention.
//
// The ceiling (50,000/day ≈ ~34/min average) is generous for a small app and
// should be raised as the user base grows. Override via Server Feature Flags.
//
// Storage:  globalRateLimits/ai_daily_{YYYY-MM-DD}
//   count:     total AI calls today
//   date:      "YYYY-MM-DD"
//   updatedAt: server timestamp
//   expiresAt: 48h TTL (enable Firestore TTL policy on expiresAt to auto-delete)

const GLOBAL_AI_DAILY_CAP = 50_000;

/**
 * Reads the project-wide daily AI counter and throws if the ceiling is reached.
 * Call BEFORE forwarding to Anthropic or Pinecone.
 */
export async function checkGlobalCircuitBreaker(): Promise<void> {
    const today = new Date().toISOString().slice(0, 10);
    const ref = db.doc(`globalRateLimits/ai_daily_${today}`);
    const snap = await ref.get();
    const count: number = snap.exists ? ((snap.data()?.count as number) ?? 0) : 0;

    if (count >= GLOBAL_AI_DAILY_CAP) {
        functions.logger.error("[GlobalCircuitBreaker] Daily AI ceiling reached", {
            count, cap: GLOBAL_AI_DAILY_CAP, date: today,
        });
        throw new functions.https.HttpsError(
            "resource-exhausted",
            "Our AI service is taking a brief rest for today. Please try again in a few hours."
        );
    }
}

/**
 * Atomically increments the project-wide daily AI request counter.
 * Call AFTER a successful Anthropic response. Fire-and-forget is acceptable
 * (slight under-count is harmless; we never want to block a response on this write).
 */
export async function incrementGlobalAICounter(): Promise<void> {
    const today = new Date().toISOString().slice(0, 10);
    const ref = db.doc(`globalRateLimits/ai_daily_${today}`);
    await ref.set(
        {
            count: admin.firestore.FieldValue.increment(1),
            date: today,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: admin.firestore.Timestamp.fromDate(
                new Date(Date.now() + 2 * 24 * 60 * 60 * 1000)
            ),
        },
        { merge: true }
    );
}
