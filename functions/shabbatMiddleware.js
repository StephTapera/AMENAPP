/**
 * shabbatMiddleware.js
 * Server-side Shabbat Mode enforcement for AMEN Cloud Functions.
 *
 * Strategy:
 *  1. Look up the user's shabbatModeEnabled flag and timezone from Firestore.
 *  2. If shabbatModeEnabled === true AND it is currently Sunday in that timezone → block.
 *  3. If timezone is missing → fallback to UTC. Client gating still applies; log for remediation.
 *
 * Allowed endpoints (never blocked):
 *  - shareChurchNote, revokeChurchNoteShare, generateChurchNoteShareLink
 *  - findScriptureReferences, summarizeNote  (church-notes AI)
 *  - All auth/2FA/phone functions
 *  - bereanBibleQA, bereanMoralCounsel, bereanBusinessQA, bereanNoteSummary,
 *    bereanScriptureExtract (scripture-grounded AI used in Church Notes)
 *
 * Blocked endpoints (when Shabbat active):
 *  - Post creation / reactions / reposts
 *  - Comment / reply creation
 *  - DM / message creation
 *  - Feed generation
 *  - Profile edits
 *  - bereanPostAssist, bereanCommentAssist, bereanDMSafety (social AI)
 *
 * Error response:
 *  { error: "SHABBAT_MODE_BLOCKED",
 *    message: "This feature is not available during Shabbat Mode (Sundays).",
 *    code: 403 }
 */

const admin = require("firebase-admin");

// Features that are ALWAYS allowed even when Shabbat is active.
const SHABBAT_ALLOWED_FUNCTIONS = new Set([
  // Church Notes
  "shareChurchNote",
  "revokeChurchNoteShare",
  "generateChurchNoteShareLink",
  "findScriptureReferences",
  "summarizeNote",
  // Berean AI (scripture, church notes context)
  "bereanBibleQA",
  "bereanBibleQAFallback",
  "bereanMoralCounsel",
  "bereanBusinessQA",
  "bereanNoteSummary",
  "bereanScriptureExtract",
  "bereanFeedExplainer",
  "bereanNotificationText",
  "bereanGenericProxy",
  // Auth, security, verification
  "request2FAOTP",
  "verify2FAOTP",
  "send2FAEmail",
  "send2FASMS",
  "cleanupExpiredOTPs",
  "checkPhoneVerificationRateLimit",
  "reportPhoneVerificationFailure",
  "unblockPhoneNumber",
  "reserveUsername",
  "checkUsernameAvailability",
  "onUserDeleted",
  "manualCascadeDelete",
  // Daily verse / notification AI (read-only, non-social)
  "generateDailyVerse",
  "generateVerseReflection",
  // Find Church (no mutations needed, but allow AIChurchRecommendation)
  "bereanRankingLabels",
]);

// Features that are explicitly BLOCKED during Shabbat.
// This list is authoritative for callable functions; Firestore trigger functions
// are blocked via the isSundayForUser helper used in each trigger.
const SHABBAT_BLOCKED_FUNCTIONS = new Set([
  // Posts & reactions
  "onPostCreate",
  "onAmenCreate",
  "onAmenDelete",
  "onRepostCreate",
  // Comments
  "onCommentCreate",
  "onCommentReply",
  "onRealtimeCommentCreate",
  "onRealtimeReplyCreate",
  // Messages
  "onMessageSent",
  "onMessageReaction",
  // Feed
  "generatePersonalizedFeed",
  // Social Berean AI
  "bereanPostAssist",
  "bereanCommentAssist",
  "bereanDMSafety",
  "bereanReportTriage",
  // Media / safety (social context)
  "bereanMediaSafety",
]);

/**
 * Determines whether it is currently Sunday in the given IANA timezone.
 * @param {string} timezone - IANA timezone identifier (e.g. "America/New_York")
 * @returns {boolean}
 */
function isSundayInTimezone(timezone) {
  try {
    const tz = timezone || "UTC";
    // Use Intl to get the weekday in the target timezone
    const formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      weekday: "long",
    });
    const weekday = formatter.format(new Date());
    return weekday === "Sunday";
  } catch (_) {
    // Unknown timezone — default to UTC as safe fallback
    const day = new Date().getUTCDay(); // 0 = Sunday
    return day === 0;
  }
}

/**
 * Look up a user's Shabbat Mode settings from Firestore.
 * Returns { shabbatEnabled, timezone }.
 *
 * @param {string} uid - Firebase Auth UID
 * @returns {Promise<{shabbatEnabled: boolean, timezone: string}>}
 */
async function getUserShabbatSettings(uid) {
  try {
    const userDoc = await admin.firestore().collection("users").doc(uid).get();
    if (!userDoc.exists) {
      return {shabbatEnabled: true, timezone: "UTC"}; // Default ON
    }
    const data = userDoc.data();

    // Prefer profile-level timezone; fall back to first device token timezone
    let timezone = data.timezone || null;
    if (!timezone) {
      const tokensSnap = await admin.firestore()
          .collection("users").doc(uid)
          .collection("deviceTokens")
          .where("enabled", "==", true)
          .limit(1)
          .get();
      if (!tokensSnap.empty) {
        timezone = tokensSnap.docs[0].data().timezone || "UTC";
      }
    }

    const shabbatEnabled =
      data.shabbatModeEnabled !== undefined ? data.shabbatModeEnabled : true; // default ON

    if (!timezone) {
      console.warn(`[shabbat] No timezone for uid=${uid}, falling back to UTC`);
    }

    return {shabbatEnabled, timezone: timezone || "UTC"};
  } catch (err) {
    console.error("[shabbat] getUserShabbatSettings error:", err);
    // Fail-safe: block on unknown (server-side default ON)
    return {shabbatEnabled: true, timezone: "UTC"};
  }
}

/**
 * Returns true when the given user's Shabbat Mode is active right now.
 * @param {string} uid
 * @returns {Promise<boolean>}
 */
async function isShabbatActiveForUser(uid) {
  const {shabbatEnabled, timezone} = await getUserShabbatSettings(uid);
  if (!shabbatEnabled) return false;
  return isSundayInTimezone(timezone);
}

/**
 * Middleware function for callable Cloud Functions.
 * Use this at the top of any blocked callable function:
 *
 *   const { assertNotShabbat } = require('./shabbatMiddleware');
 *   exports.myFunction = onCall(async (request) => {
 *     await assertNotShabbat(request.auth?.uid, 'myFunction');
 *     // ... rest of function
 *   });
 *
 * @param {string|undefined} uid - Auth UID from request.auth?.uid
 * @param {string} functionName - Name of the function (for logging)
 * @throws {HttpsError} with code PERMISSION_DENIED if Shabbat is active
 */
async function assertNotShabbat(uid, functionName) {
  // Unauthenticated calls cannot bypass — treat as default-ON
  if (!uid) return; // Let the function's own auth check handle unauthenticated

  const active = await isShabbatActiveForUser(uid);
  if (active) {
    // Log the blocked attempt
    try {
      await admin.firestore().collection("analytics_shabbat_blocks").add({
        event: "shabbat_blocked_server",
        function: functionName,
        userId_hashed: String(uid.split("").reduce((a, c) => (a << 5) - a + c.charCodeAt(0), 0)),
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (_) { /* analytics failure must not block */ }

    const {HttpsError} = require("firebase-functions/v2/https");
    throw new HttpsError(
        "permission-denied",
        "This feature is not available during Shabbat Mode (Sundays).",
        {errorCode: "SHABBAT_MODE_BLOCKED"},
    );
  }
}

/**
 * Firestore/RTDB trigger guard helper.
 * Use this inside Firestore-triggered functions to skip processing on Sundays:
 *
 *   if (await isSundayForUser(uid)) {
 *     console.log('Shabbat active — skipping mutation for', uid);
 *     return null;
 *   }
 *
 * @param {string} uid
 * @returns {Promise<boolean>}
 */
async function isSundayForUser(uid) {
  return await isShabbatActiveForUser(uid);
}

module.exports = {
  assertNotShabbat,
  isSundayForUser,
  isShabbatActiveForUser,
  isSundayInTimezone,
  SHABBAT_ALLOWED_FUNCTIONS,
  SHABBAT_BLOCKED_FUNCTIONS,
};
