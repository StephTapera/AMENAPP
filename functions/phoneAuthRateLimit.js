/**
 * Phone Authentication Rate Limiting - P0 Security
 *
 * Prevents abuse of phone OTP system by implementing server-side rate limiting.
 * Tracks phone verification requests and blocks suspicious activity.
 *
 * Security measures:
 * - Max 3 OTP sends per phone number per 15 minutes
 * - Exponential backoff on repeated failures
 * - IP-based tracking for suspicious patterns
 * - Audit logging for security monitoring
 */

const crypto = require("crypto");
const admin = require("firebase-admin");
const {onCall} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");

// GAP P0-2: server-side pepper for HMAC-hashing phone numbers. Set once via
//   firebase functions:secrets:set PHONE_HASH_PEPPER
// Without a secret pepper a bare hash of an E.164 number is brute-forceable
// (the phone-number space is small), so the pepper is required for real privacy.
const PHONE_HASH_PEPPER = defineSecret("PHONE_HASH_PEPPER");

/**
 * GAP P0-2: deterministic HMAC-SHA256 of an E.164 phone number, peppered with a
 * server secret. Stable enough to use as a Firestore doc ID and as a query key,
 * so the raw phone number is NEVER persisted in a document path or field.
 * Pepper is passed explicitly so the helper is unit-testable without Secret Manager.
 * @param {string} phoneNumber E.164 phone number.
 * @param {string} pepper Server-side HMAC key.
 * @return {string} 64-char hex digest.
 */
function hashPhone(phoneNumber, pepper) {
  return crypto.createHmac("sha256", String(pepper || ""))
      .update(String(phoneNumber)).digest("hex");
}

/**
 * GAP P0-2: redact a phone number for logs — last 4 digits only ("***2671").
 * Cloud Logging is broadly readable and retained, so full E.164 numbers must
 * never reach a console.* call.
 * @param {string} phoneNumber E.164 phone number.
 * @return {string} Redacted form safe for logs.
 */
function redactPhone(phoneNumber) {
  const s = String(phoneNumber || "");
  return s.length >= 4 ? `***${s.slice(-4)}` : "***";
}

exports.hashPhone = hashPhone;
exports.redactPhone = redactPhone;

/**
 * Check if phone verification request is allowed
 * Called before sending OTP from client
 *
 * @param {Object} data - Request data
 * @param {string} data.phoneNumber - E.164 formatted phone number
 * @param {string} data.action - 'send' or 'verify'
 * @return {Promise<Object>} - { allowed: boolean, reason?: string, retryAfter?: number }
 */
exports.checkPhoneVerificationRateLimit = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true, // Enable in production with App Check
      secrets: [PHONE_HASH_PEPPER],
    },
    async (request) => {
      const {phoneNumber, action = "send"} = request.data;
      const userId = request.auth?.uid;
      const ipAddress = request.rawRequest?.ip || "unknown";

      // Validate input
      if (!phoneNumber || typeof phoneNumber !== "string") {
        throw new Error("Invalid phone number");
      }

      // GAP P0-2: key + log by the peppered hash, never the raw E.164 number.
      const phoneHash = hashPhone(phoneNumber, PHONE_HASH_PEPPER.value());
      const phoneRedacted = redactPhone(phoneNumber);

      const now = Date.now();
      const fifteenMinutesAgo = now - (15 * 60 * 1000);

      try {
        // 1. Check per-phone-number rate limit
        const phoneRateLimitRef = admin.firestore()
            .collection("phoneAuthRateLimits")
            .doc(phoneHash);

        const phoneRateLimitDoc = await phoneRateLimitRef.get();
        const phoneRateLimitData = phoneRateLimitDoc.data() || {};

        // Clean up old attempts (older than 15 minutes)
        const recentAttempts = (phoneRateLimitData.attempts || [])
            .filter((attempt) => attempt.timestamp > fifteenMinutesAgo);

        // Check if phone number is blocked
        if (phoneRateLimitData.blockedUntil && phoneRateLimitData.blockedUntil > now) {
          const retryAfterSeconds = Math.ceil((phoneRateLimitData.blockedUntil - now) / 1000);
          console.warn(`🚫 Phone ${phoneRedacted} is blocked until ${new Date(phoneRateLimitData.blockedUntil)}`);

          return {
            allowed: false,
            reason: `Too many requests. Please try again in ${retryAfterSeconds} seconds.`,
            retryAfter: retryAfterSeconds,
          };
        }

        // Check recent attempts (max 3 per 15 minutes)
        if (recentAttempts.length >= 3) {
          // Block for exponential backoff: 5 minutes on 4th attempt, 15 on 5th, 30 on 6th
          const attemptCount = recentAttempts.length;
          const blockDuration = Math.min(attemptCount * 5 * 60 * 1000, 30 * 60 * 1000); // Max 30 mins
          const blockedUntil = now + blockDuration;

          await phoneRateLimitRef.set({
            phoneHash,
            attempts: recentAttempts,
            blockedUntil,
            lastBlockReason: `Exceeded rate limit (${attemptCount} attempts in 15 minutes)`,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});

          console.warn(`🚫 Blocking phone ${phoneRedacted} for ${blockDuration / 60000} minutes`);

          return {
            allowed: false,
            reason: "Too many verification attempts. Please try again later.",
            retryAfter: Math.ceil(blockDuration / 1000),
          };
        }

        // 2. Check per-IP rate limit (prevent same IP spamming different numbers)
        if (ipAddress !== "unknown") {
          const ipRateLimitRef = admin.firestore()
              .collection("phoneAuthIPRateLimits")
              .doc(ipAddress);

          const ipRateLimitDoc = await ipRateLimitRef.get();
          const ipRateLimitData = ipRateLimitDoc.data() || {};

          const recentIPAttempts = (ipRateLimitData.attempts || [])
              .filter((attempt) => attempt.timestamp > fifteenMinutesAgo);

          // Max 10 OTP sends from same IP in 15 minutes (across all phone numbers)
          if (recentIPAttempts.length >= 10) {
            console.warn(`🚫 IP ${ipAddress} exceeded rate limit`);

            return {
              allowed: false,
              reason: "Too many requests from your network. Please try again later.",
              retryAfter: 900, // 15 minutes
            };
          }
        }

        // 3. Log this attempt
        const newAttempt = {
          timestamp: now,
          action,
          userId: userId || "anonymous",
          ipAddress,
        };

        // Update phone rate limit
        await phoneRateLimitRef.set({
          phoneHash,
          attempts: [...recentAttempts, newAttempt],
          lastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

        // Update IP rate limit if available
        if (ipAddress !== "unknown") {
          const ipRateLimitRef = admin.firestore()
              .collection("phoneAuthIPRateLimits")
              .doc(ipAddress);

          const ipRateLimitDoc = await ipRateLimitRef.get();
          const ipRateLimitData = ipRateLimitDoc.data() || {};

          const recentIPAttempts = (ipRateLimitData.attempts || [])
              .filter((attempt) => attempt.timestamp > fifteenMinutesAgo);

          await ipRateLimitRef.set({
            ipAddress,
            attempts: [...recentIPAttempts, newAttempt],
            lastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
        }

        // 4. Security event logging (GAP P0-2: store hash, not raw number)
        await admin.firestore().collection("securityEvents").add({
          type: "phoneAuthRequest",
          phoneHash,
          userId: userId || null,
          ipAddress,
          action,
          allowed: true,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`✅ Phone auth request allowed for ${phoneRedacted} (${recentAttempts.length + 1}/3 attempts)`);

        return {
          allowed: true,
          remainingAttempts: 3 - (recentAttempts.length + 1),
        };
      } catch (error) {
        console.error("❌ Error checking phone verification rate limit:", error);

        // FAIL CLOSED (audit F-01): the server is the authoritative rate-limit
        // control. Returning allowed:true on error let an attacker who can
        // induce a transient failure bypass the 3-per-15-min / 10-per-IP caps
        // and drive SMS-pumping abuse. Deny on error; the client retries.
        return {
          allowed: false,
          reason: "Rate limit check unavailable, please try again.",
        };
      }
    }
);

/**
 * Track failed verification attempts
 * Called after OTP verification fails
 *
 * @param {Object} data - Request data
 * @param {string} data.phoneNumber - E.164 formatted phone number
 * @param {string} data.reason - Failure reason
 * @return {Promise<Object>} - Status
 */
exports.reportPhoneVerificationFailure = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true,
      secrets: [PHONE_HASH_PEPPER],
    },
    async (request) => {
      const {phoneNumber, reason = "invalid_code"} = request.data;
      const userId = request.auth?.uid;
      const ipAddress = request.rawRequest?.ip || "unknown";

      if (!phoneNumber) {
        throw new Error("Invalid phone number");
      }

      // GAP P0-2: key + log by the peppered hash, never the raw E.164 number.
      const phoneHash = hashPhone(phoneNumber, PHONE_HASH_PEPPER.value());
      const phoneRedacted = redactPhone(phoneNumber);

      try {
        const now = Date.now();

        // Track failure in security events (store hash, not raw number)
        await admin.firestore().collection("securityEvents").add({
          type: "phoneAuthFailure",
          phoneHash,
          userId: userId || null,
          ipAddress,
          reason,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Check for suspicious activity (e.g., > 10 failures in 1 hour)
        const oneHourAgo = now - (60 * 60 * 1000);
        const recentFailures = await admin.firestore()
            .collection("securityEvents")
            .where("type", "==", "phoneAuthFailure")
            .where("phoneHash", "==", phoneHash)
            .where("timestamp", ">", admin.firestore.Timestamp.fromMillis(oneHourAgo))
            .get();

        if (recentFailures.size >= 10) {
          console.warn(`⚠️ Suspicious activity detected for phone ${phoneRedacted}: ${recentFailures.size} failures in 1 hour`);

          // Block this phone number for 1 hour
          const phoneRateLimitRef = admin.firestore()
              .collection("phoneAuthRateLimits")
              .doc(phoneHash);

          await phoneRateLimitRef.set({
            phoneHash,
            blockedUntil: now + (60 * 60 * 1000), // 1 hour
            lastBlockReason: `Suspicious activity: ${recentFailures.size} failed verifications`,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});

          return {
            success: true,
            blocked: true,
            reason: "Phone number temporarily blocked due to suspicious activity",
          };
        }

        console.log(`📊 Recorded phone auth failure for ${phoneRedacted}: ${reason}`);

        return {
          success: true,
          blocked: false,
        };
      } catch (error) {
        console.error("❌ Error reporting phone verification failure:", error);
        throw new Error("Failed to report verification failure");
      }
    }
);

/**
 * Admin function to manually unblock a phone number
 *
 * @param {Object} data - Request data
 * @param {string} data.phoneNumber - Phone number to unblock
 * @return {Promise<Object>} - Status
 */
exports.unblockPhoneNumber = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true,
      secrets: [PHONE_HASH_PEPPER],
    },
    async (request) => {
      const {phoneNumber} = request.data;
      const userId = request.auth?.uid;

      // ADMIN GATE (audit F-05): unblocking clears rate-limit blocks and
      // attempt history, defeating the F-01 protection. Require the verified
      // admin custom claim, matching setAdminClaim / banUserPhone — not merely
      // an authenticated session.
      if (!userId) {
        throw new Error("Unauthorized: Authentication required");
      }
      if (request.auth?.token?.admin !== true) {
        throw new Error("Unauthorized: Admin access required");
      }

      // GAP P0-2: locate the doc by peppered hash, never the raw number.
      const phoneHash = hashPhone(phoneNumber, PHONE_HASH_PEPPER.value());
      const phoneRedacted = redactPhone(phoneNumber);

      try {
        const phoneRateLimitRef = admin.firestore()
            .collection("phoneAuthRateLimits")
            .doc(phoneHash);

        await phoneRateLimitRef.update({
          blockedUntil: null,
          attempts: [],
          unblocked: true,
          unblockedBy: userId,
          unblockedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`✅ Phone number ${phoneRedacted} unblocked by admin ${userId}`);

        return {
          success: true,
          phoneHash,
        };
      } catch (error) {
        console.error("❌ Error unblocking phone number:", error);
        throw new Error("Failed to unblock phone number");
      }
    }
);
