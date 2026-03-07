/**
 * Standalone Phone Auth Functions - No Storage Required
 */

const admin = require("firebase-admin");

// Initialize Firebase Admin WITHOUT storage bucket
admin.initializeApp();

// Import ONLY phone auth functions
const {
  checkPhoneVerificationRateLimit,
  reportPhoneVerificationFailure,
  unblockPhoneNumber,
} = require("./phoneAuthRateLimit");

// Export ONLY phone auth functions
exports.checkPhoneVerificationRateLimit = checkPhoneVerificationRateLimit;
exports.reportPhoneVerificationFailure = reportPhoneVerificationFailure;
exports.unblockPhoneNumber = unblockPhoneNumber;
