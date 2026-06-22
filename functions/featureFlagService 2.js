/**
 * featureFlagService.js
 * Server-side feature flag management for AMEN AI features.
 *
 * FLAGS ARE STORED IN FIRESTORE: featureFlags/amen_v1
 * The iOS app fetches flags on startup via getFeatureFlags callable.
 * This replaces the previous UserDefaults approach (which couldn't be
 * disabled globally without an app release).
 *
 * Exports:
 *   getFeatureFlags       — callable: returns all flags for the calling user
 *   updateFeatureFlag     — callable: admin-only flag toggle
 *   isFeatureEnabled      — server-side helper for other Cloud Functions
 *
 * Flag structure in Firestore:
 *   featureFlags/amen_v1: {
 *     textModeration:        true,
 *     churchNotesAI:         true,
 *     bereanRAG:             true,
 *     smartCommentCoach:     true,
 *     dailyDigest:           true,
 *     voiceTTS:              true,
 *     multimodalAnalysis:    false,  // Phase 2
 *     aiActivityLogging:     true,
 *     updatedAt:             Timestamp,
 *   }
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const FLAGS_DOC = "featureFlags/amen_v1";
const REGION    = "us-central1";

// Default flags — used when the Firestore doc does not yet exist.
// All AI features ON by default for V1 (individual flags can disable them).
const DEFAULT_FLAGS = {
  textModeration:     true,
  churchNotesAI:      true,
  bereanRAG:          true,
  smartCommentCoach:  true,
  dailyDigest:        true,
  voiceTTS:           true,
  multimodalAnalysis: false, // Phase 2 only
  aiActivityLogging:  true,
};

// Cache in-process for up to 60 seconds to avoid Firestore reads on every AI call.
let _cachedFlags = null;
let _cacheExpiry = 0;
const CACHE_TTL_MS = 60_000;

/**
 * Fetch flags from Firestore (with in-process cache).
 * @returns {Promise<Object>} flag map
 */
async function getFlags() {
  const now = Date.now();
  if (_cachedFlags && now < _cacheExpiry) return _cachedFlags;

  try {
    const snap = await admin.firestore().doc(FLAGS_DOC).get();
    const data = snap.exists ? snap.data() : {};
    // Merge with defaults so new flags get their default value automatically
    _cachedFlags = { ...DEFAULT_FLAGS, ...data };
    delete _cachedFlags.updatedAt; // strip Firestore timestamp
    _cacheExpiry = now + CACHE_TTL_MS;
  } catch (err) {
    console.error("[featureFlagService] Failed to fetch flags — using defaults:", err.message);
    _cachedFlags = { ...DEFAULT_FLAGS };
    _cacheExpiry = now + 10_000; // shorter TTL on error
  }

  return _cachedFlags;
}

/**
 * Check if a specific feature flag is enabled.
 * Used by other Cloud Functions to guard AI calls.
 *
 * @param {string} flagName
 * @returns {Promise<boolean>}
 */
async function isFeatureEnabled(flagName) {
  const flags = await getFlags();
  return flags[flagName] !== false; // default to true if flag not present
}

// ─── getFeatureFlags callable ──────────────────────────────────────────────────

/**
 * getFeatureFlags — callable
 *
 * Called by the iOS app on startup to receive the current feature flag set.
 * No request data needed — returns the global flag map.
 *
 * Response: { flags: { [flagName]: boolean }, fetchedAt: number }
 */
exports.getFeatureFlags = onCall(
  { region: REGION, timeoutSeconds: 10 },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const flags = await getFlags();

    console.log(`[featureFlagService:getFeatureFlags] uid=${request.auth.uid} flags=${JSON.stringify(flags)}`);
    return { flags, fetchedAt: Date.now() };
  }
);

// ─── updateFeatureFlag callable ────────────────────────────────────────────────

/**
 * updateFeatureFlag — callable (admin only)
 *
 * Toggles a feature flag. Only callable by users with admin custom claim.
 *
 * Request:  { flagName: string, enabled: boolean }
 * Response: { flagName: string, enabled: boolean, updatedAt: number }
 */
exports.updateFeatureFlag = onCall(
  { region: REGION, timeoutSeconds: 15 },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    // Admin check via custom claim
    const isAdmin = request.auth.token?.admin === true;
    if (!isAdmin) {
      throw new HttpsError("permission-denied", "Admin access required to modify feature flags.");
    }

    const { flagName, enabled } = request.data ?? {};

    if (!flagName || typeof flagName !== "string") {
      throw new HttpsError("invalid-argument", "flagName is required.");
    }
    if (typeof enabled !== "boolean") {
      throw new HttpsError("invalid-argument", "enabled must be a boolean.");
    }
    if (!(flagName in DEFAULT_FLAGS)) {
      throw new HttpsError("invalid-argument", `Unknown flag: ${flagName}. Valid flags: ${Object.keys(DEFAULT_FLAGS).join(", ")}`);
    }

    await admin.firestore().doc(FLAGS_DOC).set(
      { [flagName]: enabled, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );

    // Bust in-process cache immediately
    _cachedFlags = null;
    _cacheExpiry = 0;

    console.log(`[featureFlagService:updateFeatureFlag] admin=${request.auth.uid} flag=${flagName} enabled=${enabled}`);
    return { flagName, enabled, updatedAt: Date.now() };
  }
);

module.exports = { isFeatureEnabled, getFlags };
module.exports.getFeatureFlags    = exports.getFeatureFlags;
module.exports.updateFeatureFlag  = exports.updateFeatureFlag;
