"use strict";

/**
 * rateLimits.js
 *
 * Server-side rate limiting for AMEN platform actions, enforced exclusively
 * inside Cloud Functions. The client cannot bypass or inspect these counters.
 *
 * Limits (per-user):
 *   posts    — 20 per hour, 100 per day
 *   comments — 50 per hour
 *   dms      — 100 per day
 *   invites  — 20 per day
 *   reports  — 10 per day  (prevents report-spam attacks)
 *
 * Storage:
 *   rateLimitCounters/{uid}_{action}_{windowBucket}
 *
 *   windowBucket is an opaque string stamped by the calling function before
 *   it calls checkRateLimit / incrementCounter.  Convention:
 *     hourly  → "YYYY-MM-DDTHH"         e.g. "2026-06-10T14"
 *     daily   → "YYYY-MM-DD"            e.g. "2026-06-10"
 *
 * Exports:
 *   checkRateLimit(db, uid, action, currentWindowBucket)
 *   incrementCounter(db, uid, action, currentWindowBucket)
 *   getRateLimitStatus(db, uid)
 */

const { FieldValue } = require("firebase-admin/firestore");

// ─── Configuration ────────────────────────────────────────────────────────────

/**
 * Each action maps to one or more windows that must be checked.
 * windowType: "hourly" | "daily"
 * limit:      maximum count allowed within the window
 *
 * The calling function must supply buckets for every windowType referenced
 * (i.e. pass both an hourly and a daily bucket if the action has two windows).
 * checkRateLimit / incrementCounter each accept a single currentWindowBucket;
 * call them once per window that applies.
 */
const RATE_LIMIT_CONFIG = {
  post: [
    { windowType: "hourly", limit: 20 },
    { windowType: "daily",  limit: 100 },
  ],
  comment: [
    { windowType: "hourly", limit: 50 },
  ],
  dm: [
    { windowType: "daily", limit: 100 },
  ],
  invite: [
    { windowType: "daily", limit: 20 },
  ],
  report: [
    { windowType: "daily", limit: 10 },
  ],
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Resolve the limit for a given action + windowBucket pair.
 * Bucket format determines window type:
 *   10 chars  → daily   "YYYY-MM-DD"
 *   13 chars  → hourly  "YYYY-MM-DDTHH"
 *
 * Returns null if the action is unknown or the window has no configured limit.
 */
function resolveLimit(action, windowBucket) {
  const configs = RATE_LIMIT_CONFIG[action];
  if (!configs) return null;

  const windowType = windowBucket.length === 10 ? "daily" : "hourly";
  const cfg = configs.find((c) => c.windowType === windowType);
  return cfg ? cfg.limit : null;
}

/** Firestore document ID for a counter. */
function counterId(uid, action, windowBucket) {
  return `${uid}_${action}_${windowBucket}`;
}

// ─── RateLimitError ───────────────────────────────────────────────────────────

class RateLimitError extends Error {
  /**
   * @param {string} action
   * @param {number} limit
   * @param {string} windowBucket
   */
  constructor(action, limit, windowBucket) {
    super(
      `Rate limit exceeded for action="${action}" ` +
      `(limit=${limit}, window="${windowBucket}")`
    );
    this.name       = "RateLimitError";
    this.action     = action;
    this.limit      = limit;
    this.windowBucket = windowBucket;
    // Preserve the stack for Cloud Functions structured logging.
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, RateLimitError);
    }
  }
}

// ─── checkRateLimit ───────────────────────────────────────────────────────────

/**
 * Atomically reads the counter for (uid, action, currentWindowBucket) and
 * throws RateLimitError if the current count is already at or above the limit.
 *
 * This is a READ-ONLY check — call incrementCounter separately after the
 * action succeeds to avoid counting failed attempts.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 * @param {string} action   One of: post | comment | dm | invite | report
 * @param {string} currentWindowBucket
 * @throws {RateLimitError}
 * @throws {Error} if action is unknown or bucket format is invalid
 */
async function checkRateLimit(db, uid, action, currentWindowBucket) {
  if (!db)                    throw new Error("[rateLimits] db is required");
  if (!uid)                   throw new Error("[rateLimits] uid is required");
  if (!action)                throw new Error("[rateLimits] action is required");
  if (!currentWindowBucket)   throw new Error("[rateLimits] currentWindowBucket is required");

  const limit = resolveLimit(action, currentWindowBucket);
  if (limit === null) {
    throw new Error(
      `[rateLimits] Unknown action "${action}" or no limit defined for ` +
      `window bucket "${currentWindowBucket}"`
    );
  }

  const docRef = db
    .collection("rateLimitCounters")
    .doc(counterId(uid, action, currentWindowBucket));

  const snap = await docRef.get();
  const count = snap.exists ? (snap.data().count ?? 0) : 0;

  if (count >= limit) {
    console.warn(
      `[rateLimits] RATE LIMIT HIT uid=${uid} action=${action} ` +
      `window=${currentWindowBucket} count=${count} limit=${limit}`
    );
    throw new RateLimitError(action, limit, currentWindowBucket);
  }
}

// ─── incrementCounter ─────────────────────────────────────────────────────────

/**
 * Atomically increments the counter for (uid, action, currentWindowBucket)
 * using a Firestore transaction.  Also records a TTL field so a scheduled
 * cleanup job can purge stale documents (no Firestore TTL policy required,
 * but the field is set for forward-compatibility).
 *
 * Call this AFTER the action has been successfully performed, not before.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 * @param {string} action
 * @param {string} currentWindowBucket
 * @returns {Promise<number>} the new count after increment
 */
async function incrementCounter(db, uid, action, currentWindowBucket) {
  if (!db)                    throw new Error("[rateLimits] db is required");
  if (!uid)                   throw new Error("[rateLimits] uid is required");
  if (!action)                throw new Error("[rateLimits] action is required");
  if (!currentWindowBucket)   throw new Error("[rateLimits] currentWindowBucket is required");

  const docRef = db
    .collection("rateLimitCounters")
    .doc(counterId(uid, action, currentWindowBucket));

  // TTL: daily buckets expire after 2 days; hourly buckets after 2 hours.
  const isDaily    = currentWindowBucket.length === 10;
  const ttlSeconds = isDaily ? 2 * 24 * 3600 : 2 * 3600;
  const expiresAt  = new Date(Date.now() + ttlSeconds * 1000);

  let newCount;
  await db.runTransaction(async (txn) => {
    const snap = await txn.get(docRef);
    if (snap.exists) {
      newCount = (snap.data().count ?? 0) + 1;
      txn.update(docRef, {
        count:     newCount,
        updatedAt: FieldValue.serverTimestamp(),
        expiresAt,
      });
    } else {
      newCount = 1;
      txn.set(docRef, {
        uid,
        action,
        windowBucket: currentWindowBucket,
        count:        1,
        createdAt:    FieldValue.serverTimestamp(),
        updatedAt:    FieldValue.serverTimestamp(),
        expiresAt,
      });
    }
  });

  return newCount;
}

// ─── getRateLimitStatus ───────────────────────────────────────────────────────

/**
 * Returns a snapshot of all rate-limit counters currently stored for a user.
 * Intended for admin dashboards and trust-score computation — not for client
 * consumption (clients should never know their exact counter values).
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 * @returns {Promise<Array<{id: string, uid: string, action: string, windowBucket: string, count: number, expiresAt: Date|null}>>}
 */
async function getRateLimitStatus(db, uid) {
  if (!db)  throw new Error("[rateLimits] db is required");
  if (!uid) throw new Error("[rateLimits] uid is required");

  // Query by uid prefix — all counter IDs begin with "{uid}_"
  const snap = await db
    .collection("rateLimitCounters")
    .where("uid", "==", uid)
    .get();

  return snap.docs.map((doc) => {
    const d = doc.data();
    return {
      id:           doc.id,
      uid:          d.uid,
      action:       d.action,
      windowBucket: d.windowBucket,
      count:        d.count ?? 0,
      expiresAt:    d.expiresAt ? d.expiresAt.toDate() : null,
    };
  });
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = {
  RateLimitError,
  RATE_LIMIT_CONFIG,
  checkRateLimit,
  incrementCounter,
  getRateLimitStatus,
};
