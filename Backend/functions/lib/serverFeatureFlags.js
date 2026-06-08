"use strict";
/**
 * serverFeatureFlags.ts
 *
 * Server-authoritative feature flag evaluation for safety-critical Cloud Functions.
 *
 * WHY THIS EXISTS (CRITICAL-3 from Trust/Safety Audit):
 *   Safety feature flags like moderationV2Enabled, dmEnhancedScanningEnabled, and
 *   antiHarassmentV2Enabled are read from Firebase Remote Config on the client.
 *   A user with a jailbroken device can modify the evaluated flag values to disable
 *   client-side safety checks. Cloud Functions that rely on client-supplied flag
 *   values for their safety logic are similarly vulnerable to request forgery.
 *
 * APPROACH:
 *   Safety-critical flags are stored in a Firestore document that is:
 *     - Readable only by Cloud Functions (admin SDK) — clients cannot read it
 *     - Writable only by Cloud Functions or the Firebase console
 *     - Never passed in from the client request payload
 *
 *   Cloud Functions call getServerSafetyFlags() and use the returned values to
 *   decide whether to run safety checks. The flags have safe defaults (all ON)
 *   so any Firestore read failure leaves enforcement active.
 *
 * DOCUMENT PATH:
 *   system/serverFeatureFlags
 *
 *   This path must be covered by a Firestore rule:
 *     match /system/{docId} {
 *       allow read, write: if false;  // Clients can never access — admin SDK only
 *     }
 *
 * CHANGING FLAGS:
 *   Use the Firebase console or a one-time admin script to write the document.
 *   Example (Firebase console → Firestore → system/serverFeatureFlags):
 *     {
 *       "moderationV2Enabled": true,
 *       "dmEnhancedScanningEnabled": true,
 *       "antiHarassmentV2Enabled": true,
 *       "messagingBlockEnforcementEnabled": true,
 *       "updatedAt": <serverTimestamp>
 *     }
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
exports.invalidateServerFlagCache = void 0;
exports.getServerSafetyFlags = getServerSafetyFlags;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions"));
const https_1 = require("firebase-functions/v2/https");
const db = admin.firestore();
// ─── Safe Defaults (all safety features ON) ──────────────────────────────────
/**
 * Default flags used when the Firestore document cannot be read.
 * ALL safety flags default to ENABLED so enforcement is never accidentally
 * disabled by a Firestore read error or missing document.
 */
const SAFE_DEFAULTS = {
    moderationV2Enabled: true,
    dmEnhancedScanningEnabled: true,
    antiHarassmentV2Enabled: true,
    messagingBlockEnforcementEnabled: true,
    blockAttemptRecordingEnabled: true,
};
// ─── In-memory cache ─────────────────────────────────────────────────────────
let flagsCache = null;
let cacheExpiresAt = 0;
/** Cache TTL: 5 minutes. Keeps Firestore reads low during high-traffic periods. */
const CACHE_TTL_MS = 5 * 60 * 1000;
// ─── Public API ──────────────────────────────────────────────────────────────
/**
 * Fetches server-authoritative safety flags from Firestore.
 *
 * - Results are cached for 5 minutes to avoid a Firestore read on every message.
 * - On any read failure, SAFE_DEFAULTS (all ON) are returned.
 * - Clients NEVER supply these values — they are only read from Firestore.
 *
 * @returns Resolved server safety flags.
 */
async function getServerSafetyFlags() {
    const now = Date.now();
    // Return cached flags if fresh.
    if (flagsCache !== null && now < cacheExpiresAt) {
        return flagsCache;
    }
    try {
        const snap = await db.collection("system").doc("serverFeatureFlags").get();
        if (!snap.exists) {
            // Document doesn't exist yet — use safe defaults and don't cache so
            // we retry on the next call (document may be created momentarily).
            functions.logger.info("[ServerFlags] system/serverFeatureFlags does not exist — using safe defaults.");
            return SAFE_DEFAULTS;
        }
        const data = snap.data() ?? {};
        // Build flags with explicit fallback to SAFE_DEFAULTS for each key,
        // so a partially-written document doesn't accidentally disable enforcement.
        const flags = {
            moderationV2Enabled: typeof data.moderationV2Enabled === "boolean"
                ? data.moderationV2Enabled
                : SAFE_DEFAULTS.moderationV2Enabled,
            dmEnhancedScanningEnabled: typeof data.dmEnhancedScanningEnabled === "boolean"
                ? data.dmEnhancedScanningEnabled
                : SAFE_DEFAULTS.dmEnhancedScanningEnabled,
            antiHarassmentV2Enabled: typeof data.antiHarassmentV2Enabled === "boolean"
                ? data.antiHarassmentV2Enabled
                : SAFE_DEFAULTS.antiHarassmentV2Enabled,
            messagingBlockEnforcementEnabled: typeof data.messagingBlockEnforcementEnabled === "boolean"
                ? data.messagingBlockEnforcementEnabled
                : SAFE_DEFAULTS.messagingBlockEnforcementEnabled,
            blockAttemptRecordingEnabled: typeof data.blockAttemptRecordingEnabled === "boolean"
                ? data.blockAttemptRecordingEnabled
                : SAFE_DEFAULTS.blockAttemptRecordingEnabled,
        };
        // Update cache.
        flagsCache = flags;
        cacheExpiresAt = now + CACHE_TTL_MS;
        return flags;
    }
    catch (err) {
        functions.logger.error("[ServerFlags] Failed to read system/serverFeatureFlags — using safe defaults.", err);
        // Safe defaults — do not cache on error so next call retries Firestore.
        return SAFE_DEFAULTS;
    }
}
/**
 * Callable function: invalidateServerFlagCache
 *
 * Forces the in-process flag cache to expire, so the next call to
 * getServerSafetyFlags() fetches fresh values from Firestore.
 *
 * This is useful immediately after updating flags via the console.
 * Only callable by admin-level callers (Firebase Admin SDK or custom claims check).
 */
exports.invalidateServerFlagCache = (0, https_1.onCall)(async (request) => {
    const _data = request.data;
    const data = _data;
    const context = { auth: request.auth, app: request.app };
    if (!context.auth) {
        throw new https_1.HttpsError("unauthenticated", "Auth required");
    }
    // Only allow users with the "admin" custom claim to flush the cache.
    const tokenClaims = context.auth.token;
    if (!tokenClaims.admin) {
        throw new https_1.HttpsError("permission-denied", "Only admins can invalidate the server flag cache");
    }
    flagsCache = null;
    cacheExpiresAt = 0;
    functions.logger.info(`[ServerFlags] Cache invalidated by admin ${context.auth.uid}`);
    return { ok: true };
});
//# sourceMappingURL=serverFeatureFlags.js.map