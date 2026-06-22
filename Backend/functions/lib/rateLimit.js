"use strict";
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
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.RATE_LIMITS = void 0;
exports.enforceRateLimit = enforceRateLimit;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions"));
const db = admin.firestore();
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
exports.RATE_LIMITS = {
    AI_PER_MINUTE: { name: "ai_1min", windowMs: 60000, maxCalls: 20 },
    AI_PER_DAY: { name: "ai_1day", windowMs: 86400000, maxCalls: 200 },
    SUGGEST_PER_MINUTE: { name: "suggest_1min", windowMs: 60000, maxCalls: 10 },
    SUGGEST_PER_DAY: { name: "suggest_1day", windowMs: 86400000, maxCalls: 100 },
    // Berean Spiritual Intelligence — same budget as AI proxy (used by berean/controllers)
    bereanPerMinute: { name: "berean_1min", windowMs: 60000, maxCalls: 20 },
    bereanDailyBudget: { name: "berean_1day", windowMs: 86400000, maxCalls: 200 },
    bereanContextualActionPerMinute: { name: "berean_contextual_action_1min", windowMs: 60000, maxCalls: 30 },
    COMMUNITY_SAVE_PER_MINUTE: { name: "community_save_1min", windowMs: 60000, maxCalls: 30 },
    COMMUNITY_SAVE_PER_DAY: { name: "community_save_1day", windowMs: 86400000, maxCalls: 300 },
    COMMUNITY_TONE_CHECK_PER_MINUTE: { name: "community_tone_check_1min", windowMs: 60000, maxCalls: 20 },
    COMMUNITY_TONE_CHECK_PER_DAY: { name: "community_tone_check_1day", windowMs: 86400000, maxCalls: 200 },
};
/**
 * Check and increment a rate-limit counter for a user.
 * Throws `functions.https.HttpsError("resource-exhausted", ...)` if the
 * user has exceeded any of the supplied limits.
 *
 * @param uid   The authenticated user's UID.
 * @param limits One or more RateLimitConfig windows to enforce simultaneously.
 */
async function enforceRateLimit(uid, limits) {
    const now = Date.now();
    // Check + increment all windows in parallel.
    await Promise.all(limits.map(async (limit) => {
        // Round down to window boundary for a consistent document key.
        const windowStart = Math.floor(now / limit.windowMs) * limit.windowMs;
        const windowEnd = windowStart + limit.windowMs;
        const docId = `${limit.name}_${windowStart}`;
        const ref = db.collection("rateLimits").doc(uid)
            .collection("windows").doc(docId);
        await db.runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            const data = snap.exists ? snap.data() : null;
            // If the stored window has expired, treat it as zero.
            const currentCount = (data && data.windowEnd > now) ? data.count : 0;
            if (currentCount >= limit.maxCalls) {
                const retryAfterSec = Math.ceil((windowEnd - now) / 1000);
                functions.logger.warn(`[RateLimit] uid=${uid} limit=${limit.name} count=${currentCount}/${limit.maxCalls}`);
                throw new functions.https.HttpsError("resource-exhausted", `Too many requests. Please wait ${retryAfterSec} seconds before trying again.`);
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
//# sourceMappingURL=rateLimit.js.map