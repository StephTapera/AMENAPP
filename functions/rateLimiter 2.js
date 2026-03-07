/**
 * rateLimiter.js
 * Firestore-backed server-side rate limiter for AMEN Cloud Functions.
 *
 * Usage:
 *   const { checkRateLimit } = require("./rateLimiter");
 *   await checkRateLimit(userId, "post_create", 20, 3600);  // 20 per hour
 *
 * Stores counters in: rateLimits/{userId}_{action}
 * Document auto-expires via Cloud Scheduler (or TTL index on expiresAt).
 */

const admin = require("firebase-admin");

const db = () => admin.firestore();

/**
 * Check and increment a rate limit counter.
 *
 * @param {string} userId     - The authenticated user ID
 * @param {string} action     - Action key (e.g. "post_create", "comment_create")
 * @param {number} maxCount   - Maximum allowed within the window
 * @param {number} windowSecs - Rolling window duration in seconds
 * @throws {Error} with code "rate_limit_exceeded" if limit is breached
 * @returns {Promise<{count: number, resetAt: Date}>}
 */
async function checkRateLimit(userId, action, maxCount, windowSecs) {
  if (!userId) throw new Error("userId required for rate limiting");

  const docId = `${userId}_${action}`;
  const ref = db().collection("rateLimits").doc(docId);

  const now = Date.now();
  const windowMs = windowSecs * 1000;

  try {
    const result = await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);

      if (!snap.exists) {
        // First request in window
        const expiresAt = new Date(now + windowMs);
        tx.set(ref, {
          userId,
          action,
          count: 1,
          windowStart: new Date(now),
          expiresAt,
        });
        return { count: 1, resetAt: expiresAt };
      }

      const data = snap.data();
      const windowStart = data.windowStart.toMillis
        ? data.windowStart.toMillis()
        : data.windowStart.getTime();

      if (now - windowStart > windowMs) {
        // Window expired — reset counter
        const expiresAt = new Date(now + windowMs);
        tx.set(ref, {
          userId,
          action,
          count: 1,
          windowStart: new Date(now),
          expiresAt,
        });
        return { count: 1, resetAt: expiresAt };
      }

      const newCount = (data.count || 0) + 1;
      if (newCount > maxCount) {
        const resetAt = new Date(windowStart + windowMs);
        const err = new Error(`Rate limit exceeded for action "${action}". Try again after ${resetAt.toISOString()}.`);
        err.code = "rate_limit_exceeded";
        err.resetAt = resetAt;
        err.retryAfterSeconds = Math.ceil((windowStart + windowMs - now) / 1000);
        throw err;
      }

      tx.update(ref, { count: newCount });
      return { count: newCount, resetAt: new Date(windowStart + windowMs) };
    });

    return result;
  } catch (err) {
    if (err.code === "rate_limit_exceeded") throw err;
    // Fail CLOSED on Firestore errors: a transient DB outage must not become a
    // free pass for spam. Surface a retryable error so the caller can back off.
    console.error(`[rateLimiter] Firestore error for ${docId}:`, err.message);
    const closed = new Error(
      `Rate limiter unavailable for action "${action}". Please retry in a few seconds.`
    );
    closed.code = "rate_limiter_unavailable";
    closed.retryAfterSeconds = 10;
    throw closed;
  }
}

/**
 * Convenience wrapper that throws an HttpsError for use in onCall functions.
 * Converts rate_limit_exceeded into a Firebase "resource-exhausted" error.
 */
async function enforceRateLimit(userId, action, maxCount, windowSecs) {
  const { HttpsError } = require("firebase-functions/v2/https");
  try {
    return await checkRateLimit(userId, action, maxCount, windowSecs);
  } catch (err) {
    if (err.code === "rate_limit_exceeded") {
      throw new HttpsError(
        "resource-exhausted",
        err.message,
        { retryAfterSeconds: err.retryAfterSeconds }
      );
    }
    if (err.code === "rate_limiter_unavailable") {
      // Limiter is down — fail closed with a retriable "unavailable" status.
      throw new HttpsError(
        "unavailable",
        err.message,
        { retryAfterSeconds: err.retryAfterSeconds }
      );
    }
    throw err;
  }
}

/**
 * Default limits per action (can be overridden per call site).
 * Format: { maxCount, windowSecs }
 */
const DEFAULT_LIMITS = {
  login:            { maxCount: 5,   windowSecs: 900   },  // 5 per 15 min
  password_reset:   { maxCount: 3,   windowSecs: 3600  },  // 3 per hour
  follow:           { maxCount: 60,  windowSecs: 3600  },  // 60 per hour
  unfollow:         { maxCount: 60,  windowSecs: 3600  },  // 60 per hour
  post_create:      { maxCount: 20,  windowSecs: 3600  },  // 20 per hour
  comment_create:   { maxCount: 60,  windowSecs: 3600  },  // 60 per hour
  dm_send:          { maxCount: 100, windowSecs: 3600  },  // 100 per hour
  report_submit:    { maxCount: 10,  windowSecs: 3600  },  // 10 per hour
  push_send:        { maxCount: 50,  windowSecs: 3600  },  // 50 per hour
};

/**
 * Apply the default limit for a named action.
 */
async function applyDefaultLimit(userId, action) {
  const limits = DEFAULT_LIMITS[action];
  if (!limits) {
    console.warn(`[rateLimiter] No default limit for action "${action}"`);
    return;
  }
  return enforceRateLimit(userId, action, limits.maxCount, limits.windowSecs);
}

module.exports = { checkRateLimit, enforceRateLimit, applyDefaultLimit, DEFAULT_LIMITS };
