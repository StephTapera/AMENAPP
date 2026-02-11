/**
 * Firebase Cloud Functions for AMEN App
 * Compatible with Firebase Functions v7 (2nd generation)
 * Handles notifications, follows, and push notifications
 */

const admin = require("firebase-admin");

// Initialize Firebase Admin
admin.initializeApp();

// Import all notification functions
const {
  sendPushNotification,
  onUserFollow,
  onUserUnfollow,
  onFollowRequestAccepted,
  onMessageRequestAccepted,
} = require("./pushNotifications");

// Export all functions
exports.sendPushNotification = sendPushNotification;
exports.onUserFollow = onUserFollow;
exports.onUserUnfollow = onUserUnfollow;
exports.onFollowRequestAccepted = onFollowRequestAccepted;
exports.onMessageRequestAccepted = onMessageRequestAccepted;
