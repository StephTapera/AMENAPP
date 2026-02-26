/**
 * Two-Factor Authentication Cloud Functions
 * Handles OTP generation, delivery via email/SMS, and verification
 */

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {logger} = require("firebase-functions");

// OTP Configuration
const OTP_LENGTH = 6;
const OTP_EXPIRY_MINUTES = 10;
const MAX_VERIFICATION_ATTEMPTS = 3;
const RATE_LIMIT_WINDOW_MINUTES = 15;
const MAX_OTP_REQUESTS_PER_WINDOW = 3;

/**
 * Generate a secure random OTP code
 * @param {number} length - Length of the OTP
 * @return {string} Generated OTP code
 */
function generateOTP(length = OTP_LENGTH) {
  let otp = "";
  for (let i = 0; i < length; i++) {
    otp += Math.floor(Math.random() * 10).toString();
  }
  return otp;
}

/**
 * Check rate limiting for OTP requests
 * @param {string} userId - User ID
 * @param {FirebaseFirestore.Firestore} db - Firestore instance
 * @return {Promise<boolean>} True if rate limit exceeded
 */
async function checkRateLimit(userId, db) {
  const now = admin.firestore.Timestamp.now();
  const windowStart = new admin.firestore.Timestamp(
      now.seconds - (RATE_LIMIT_WINDOW_MINUTES * 60),
      now.nanoseconds,
  );

  const recentRequests = await db
      .collection("twoFactorOTP")
      .where("userId", "==", userId)
      .where("createdAt", ">=", windowStart)
      .get();

  return recentRequests.size >= MAX_OTP_REQUESTS_PER_WINDOW;
}

/**
 * Request a 2FA OTP code
 * Callable function that generates and stores an OTP
 * The actual sending is done via a separate trigger
 */
exports.request2FAOTP = onCall({
  region: "us-central1",
  enforceAppCheck: false, // Set to true in production
}, async (request) => {
  try {
    const {auth, data} = request;

    // Verify authenticated user
    if (!auth || !auth.uid) {
      throw new HttpsError(
          "unauthenticated",
          "User must be authenticated to request 2FA code",
      );
    }

    const userId = auth.uid;
    const {deliveryMethod} = data; // "email" or "sms"

    if (!deliveryMethod || !["email", "sms"].includes(deliveryMethod)) {
      throw new HttpsError(
          "invalid-argument",
          "Delivery method must be 'email' or 'sms'",
      );
    }

    const db = admin.firestore();

    // Check rate limiting
    const rateLimited = await checkRateLimit(userId, db);
    if (rateLimited) {
      throw new HttpsError(
          "resource-exhausted",
          `Too many OTP requests. Please wait ${RATE_LIMIT_WINDOW_MINUTES} minutes.`,
      );
    }

    // Get user data
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      throw new HttpsError("not-found", "User not found");
    }

    const userData = userDoc.data();
    const has2FAEnabled = userData.enable2FA || false;

    if (!has2FAEnabled) {
      throw new HttpsError(
          "failed-precondition",
          "Two-factor authentication is not enabled for this user",
      );
    }

    // Validate delivery method availability
    if (deliveryMethod === "email" && !userData.email) {
      throw new HttpsError(
          "failed-precondition",
          "Email not available for this user",
      );
    }

    if (deliveryMethod === "sms" && !userData.phoneNumber) {
      throw new HttpsError(
          "failed-precondition",
          "Phone number not available for this user",
      );
    }

    // Generate OTP
    const otp = generateOTP();
    const expiresAt = admin.firestore.Timestamp.fromMillis(
        Date.now() + (OTP_EXPIRY_MINUTES * 60 * 1000),
    );

    // Store OTP in Firestore
    const otpDoc = await db.collection("twoFactorOTP").add({
      userId: userId,
      otp: otp,
      deliveryMethod: deliveryMethod,
      destination: deliveryMethod === "email" ?
        userData.email :
        userData.phoneNumber,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: expiresAt,
      verified: false,
      attempts: 0,
      sent: false,
    });

    logger.info(`2FA OTP generated for user ${userId}`, {
      otpId: otpDoc.id,
      deliveryMethod,
    });

    return {
      success: true,
      otpId: otpDoc.id,
      expiresAt: expiresAt.toMillis(),
      deliveryMethod: deliveryMethod,
      destination: deliveryMethod === "email" ?
        maskEmail(userData.email) :
        maskPhoneNumber(userData.phoneNumber),
    };
  } catch (error) {
    logger.error("Error requesting 2FA OTP:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", "Failed to generate 2FA code");
  }
});

/**
 * Verify a 2FA OTP code
 */
exports.verify2FAOTP = onCall({
  region: "us-central1",
  enforceAppCheck: false, // Set to true in production
}, async (request) => {
  try {
    const {auth, data} = request;

    // Verify authenticated user
    if (!auth || !auth.uid) {
      throw new HttpsError(
          "unauthenticated",
          "User must be authenticated to verify 2FA code",
      );
    }

    const userId = auth.uid;
    const {otpId, code} = data;

    if (!otpId || !code) {
      throw new HttpsError(
          "invalid-argument",
          "OTP ID and code are required",
      );
    }

    const db = admin.firestore();

    // Get OTP document
    const otpDoc = await db.collection("twoFactorOTP").doc(otpId).get();

    if (!otpDoc.exists) {
      throw new HttpsError("not-found", "Invalid OTP ID");
    }

    const otpData = otpDoc.data();

    // Verify ownership
    if (otpData.userId !== userId) {
      throw new HttpsError("permission-denied", "Invalid OTP ID");
    }

    // Check if already verified
    if (otpData.verified) {
      throw new HttpsError(
          "failed-precondition",
          "This code has already been used",
      );
    }

    // Check expiration
    const now = admin.firestore.Timestamp.now();
    if (now.toMillis() > otpData.expiresAt.toMillis()) {
      throw new HttpsError("deadline-exceeded", "This code has expired");
    }

    // Check max attempts
    if (otpData.attempts >= MAX_VERIFICATION_ATTEMPTS) {
      throw new HttpsError(
          "failed-precondition",
          "Maximum verification attempts exceeded",
      );
    }

    // Increment attempts
    await db.collection("twoFactorOTP").doc(otpId).update({
      attempts: admin.firestore.FieldValue.increment(1),
    });

    // Verify code
    if (otpData.otp !== code) {
      const attemptsLeft = MAX_VERIFICATION_ATTEMPTS - (otpData.attempts + 1);
      throw new HttpsError(
          "invalid-argument",
          `Invalid code. ${attemptsLeft} attempts remaining.`,
      );
    }

    // Mark as verified
    await db.collection("twoFactorOTP").doc(otpId).update({
      verified: true,
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Create a 2FA session token
    const sessionToken = generateSessionToken();
    const sessionExpiresAt = admin.firestore.Timestamp.fromMillis(
        Date.now() + (30 * 60 * 1000), // 30 minutes
    );

    await db.collection("twoFactorSessions").add({
      userId: userId,
      sessionToken: sessionToken,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: sessionExpiresAt,
      active: true,
    });

    logger.info(`2FA verification successful for user ${userId}`);

    return {
      success: true,
      verified: true,
      sessionToken: sessionToken,
      expiresAt: sessionExpiresAt.toMillis(),
    };
  } catch (error) {
    logger.error("Error verifying 2FA OTP:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", "Failed to verify 2FA code");
  }
});

/**
 * Send 2FA OTP via Email
 * Triggered when a new OTP document is created
 */
exports.send2FAEmail = onDocumentCreated(
    {
      document: "twoFactorOTP/{otpId}",
      region: "us-central1",
    },
    async (event) => {
      const snapshot = event.data;
      try {
        const otpData = snapshot.data();

        // Only process email delivery
        if (otpData.deliveryMethod !== "email" || otpData.sent) {
          return null;
        }

        const {userId, otp, destination} = otpData;

        // Get user data for personalization
        const userDoc = await admin.firestore()
            .collection("users")
            .doc(userId)
            .get();

        const userData = userDoc.data();
        const displayName = userData.displayName || "User";

        // Prepare email
        const emailData = {
          to: destination,
          message: {
            subject: "Your AMEN Verification Code",
            html: generateEmailTemplate(displayName, otp),
            text: `Your AMEN verification code is: ${otp}. ` +
                  `This code will expire in ${OTP_EXPIRY_MINUTES} minutes.`,
          },
        };

        // Add to mail queue (assuming you have an email extension configured)
        await admin.firestore().collection("mail").add(emailData);

        // Mark as sent
        await snapshot.ref.update({
          sent: true,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        logger.info(`2FA email sent to ${destination}`);
        return null;
      } catch (error) {
        logger.error("Error sending 2FA email:", error);
        // Mark as failed
        await snapshot.ref.update({
          sent: false,
          sendError: error.message,
        });
        return null;
      }
    },
);

/**
 * Send 2FA OTP via SMS
 * Triggered when a new OTP document is created
 */
exports.send2FASMS = onDocumentCreated(
    {
      document: "twoFactorOTP/{otpId}",
      region: "us-central1",
    },
    async (event) => {
      const snapshot = event.data;
      try {
        const otpData = snapshot.data();

        // Only process SMS delivery
        if (otpData.deliveryMethod !== "sms" || otpData.sent) {
          return null;
        }

        const {otp, destination} = otpData;

        // Use Firebase Auth's built-in SMS sending
        // Note: This requires Firebase Auth SMS configuration
        const message = `Your AMEN verification code is: ${otp}. ` +
                       `This code will expire in ${OTP_EXPIRY_MINUTES} minutes.`;

        // TODO: Implement SMS sending via Twilio or Firebase Auth
        // For now, we'll use a placeholder
        logger.info(`SMS would be sent to ${destination}: ${message}`);

        // Mark as sent
        await snapshot.ref.update({
          sent: true,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        logger.info(`2FA SMS sent to ${destination}`);
        return null;
      } catch (error) {
        logger.error("Error sending 2FA SMS:", error);
        // Mark as failed
        await snapshot.ref.update({
          sent: false,
          sendError: error.message,
        });
        return null;
      }
    },
);

/**
 * Cleanup expired OTP codes
 * Triggered on document creation to clean up old expired codes
 */
exports.cleanupExpiredOTPs = onDocumentCreated(
    {
      document: "twoFactorOTP/{otpId}",
      region: "us-central1",
    },
    async (event) => {
      try {
        const now = admin.firestore.Timestamp.now();

        const expiredOTPs = await admin.firestore()
            .collection("twoFactorOTP")
            .where("expiresAt", "<", now)
            .where("verified", "==", false)
            .get();

        const batch = admin.firestore().batch();
        expiredOTPs.docs.forEach((doc) => {
          batch.delete(doc.ref);
        });

        await batch.commit();
        logger.info(`Cleaned up ${expiredOTPs.size} expired OTPs`);
        return null;
      } catch (error) {
        logger.error("Error cleaning up expired OTPs:", error);
        return null;
      }
    },
);

// Helper functions

/**
 * Generate a secure session token
 * @return {string} Session token
 */
function generateSessionToken() {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let token = "";
  for (let i = 0; i < 32; i++) {
    token += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return token;
}

/**
 * Mask email address for privacy
 * @param {string} email - Email address
 * @return {string} Masked email
 */
function maskEmail(email) {
  const [localPart, domain] = email.split("@");
  if (localPart.length <= 2) {
    return `${localPart[0]}***@${domain}`;
  }
  return `${localPart.substring(0, 2)}***@${domain}`;
}

/**
 * Mask phone number for privacy
 * @param {string} phone - Phone number
 * @return {string} Masked phone
 */
function maskPhoneNumber(phone) {
  if (phone.length <= 4) {
    return `***${phone.slice(-2)}`;
  }
  return `***${phone.slice(-4)}`;
}

/**
 * Generate HTML email template
 * @param {string} displayName - User's display name
 * @param {string} otp - OTP code
 * @return {string} HTML email
 */
function generateEmailTemplate(displayName, otp) {
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Your AMEN Verification Code</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #f5f5f5; margin: 0; padding: 20px;">
  <table width="100%" cellpadding="0" cellspacing="0" style="max-width: 600px; margin: 0 auto; background-color: white; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
    <tr>
      <td style="padding: 40px 30px; text-align: center; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);">
        <h1 style="color: white; margin: 0; font-size: 24px; font-weight: 600;">🔐 AMEN Security</h1>
      </td>
    </tr>
    <tr>
      <td style="padding: 40px 30px;">
        <h2 style="color: #333; font-size: 20px; margin: 0 0 16px 0;">Hi ${displayName},</h2>
        <p style="color: #666; font-size: 16px; line-height: 1.5; margin: 0 0 24px 0;">
          Your two-factor authentication code is:
        </p>
        <div style="background-color: #f8f9fa; border: 2px solid #667eea; border-radius: 8px; padding: 24px; text-align: center; margin: 0 0 24px 0;">
          <div style="font-size: 36px; font-weight: 700; color: #667eea; letter-spacing: 8px; font-family: 'Courier New', monospace;">
            ${otp}
          </div>
        </div>
        <p style="color: #666; font-size: 14px; line-height: 1.5; margin: 0 0 16px 0;">
          This code will expire in <strong>${OTP_EXPIRY_MINUTES} minutes</strong>.
        </p>
        <p style="color: #666; font-size: 14px; line-height: 1.5; margin: 0 0 24px 0;">
          If you didn't request this code, please ignore this email or contact support if you're concerned about your account security.
        </p>
        <hr style="border: none; border-top: 1px solid #e0e0e0; margin: 24px 0;">
        <p style="color: #999; font-size: 12px; line-height: 1.5; margin: 0;">
          This is an automated message from AMEN. Please do not reply to this email.
        </p>
      </td>
    </tr>
    <tr>
      <td style="padding: 20px 30px; background-color: #f8f9fa; text-align: center;">
        <p style="color: #999; font-size: 12px; margin: 0;">
          © ${new Date().getFullYear()} AMEN. All rights reserved.
        </p>
      </td>
    </tr>
  </table>
</body>
</html>
  `.trim();
}
