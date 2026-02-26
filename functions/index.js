/**
 * Firebase Cloud Functions for AMEN App
 * Compatible with Firebase Functions v7 (2nd generation)
 * Handles notifications, follows, and push notifications
 */

const admin = require("firebase-admin");
const {onValueCreated} = require("firebase-functions/v2/database");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");

// Initialize Firebase Admin
// Storage bucket is auto-detected from Firebase project
admin.initializeApp();

// Import all notification functions
const {
  sendPushNotification,
  onUserFollow,
  onUserUnfollow,
  onFollowRequestAccepted,
  onMessageRequestAccepted,
  onCommentCreate,
  onCommentReply,
  onPostCreate,
  onAmenCreate,
  onAmenDelete,
  onRepostCreate,
  onMessageReaction,
} = require("./pushNotifications");

// P0-4: Import church notes sharing functions
const {
  shareChurchNote,
  revokeChurchNoteShare,
  generateChurchNoteShareLink,
} = require("./churchNotesShare");

// AI Personalization: Import ML-powered feed and notification functions
const {
  generatePersonalizedFeed,
  filterSmartNotifications,
  exportEngagementData,
} = require("./aiPersonalization");

// Content Moderation: Import organic content integrity system
const {
  moderateContent,
} = require("./contentModeration");

// Image Moderation: Import Cloud Vision SafeSearch moderation
const {
  moderateUploadedImage,
} = require("./imageModeration");

// P0: Phone Authentication Rate Limiting
const {
  checkPhoneVerificationRateLimit,
  reportPhoneVerificationFailure,
  unblockPhoneNumber,
} = require("./phoneAuthRateLimit");

// P0: Two-Factor Authentication
const {
  request2FAOTP,
  verify2FAOTP,
  send2FAEmail,
  send2FASMS,
  cleanupExpiredOTPs,
} = require("./twoFactorAuth");

// Export all functions
exports.sendPushNotification = sendPushNotification;
exports.onUserFollow = onUserFollow;
exports.onUserUnfollow = onUserUnfollow;
exports.onFollowRequestAccepted = onFollowRequestAccepted;
exports.onMessageRequestAccepted = onMessageRequestAccepted;
exports.onCommentCreate = onCommentCreate;
exports.onCommentReply = onCommentReply;
exports.onPostCreate = onPostCreate;
exports.onAmenCreate = onAmenCreate;
exports.onAmenDelete = onAmenDelete;
exports.onRepostCreate = onRepostCreate;
exports.onMessageReaction = onMessageReaction;

// P0-4: Export church notes sharing functions
exports.shareChurchNote = shareChurchNote;
exports.revokeChurchNoteShare = revokeChurchNoteShare;
exports.generateChurchNoteShareLink = generateChurchNoteShareLink;

// AI Personalization: Export ML-powered functions
exports.generatePersonalizedFeed = generatePersonalizedFeed;
exports.filterSmartNotifications = filterSmartNotifications;
exports.exportEngagementData = exportEngagementData;

// Content Moderation: Export organic content integrity system
exports.moderateContent = moderateContent;

// Image Moderation: Export Cloud Vision SafeSearch moderation
exports.moderateUploadedImage = moderateUploadedImage;

// P0: Phone Authentication Rate Limiting
exports.checkPhoneVerificationRateLimit = checkPhoneVerificationRateLimit;
exports.reportPhoneVerificationFailure = reportPhoneVerificationFailure;
exports.unblockPhoneNumber = unblockPhoneNumber;

// P0: Two-Factor Authentication
exports.request2FAOTP = request2FAOTP;
exports.verify2FAOTP = verify2FAOTP;
exports.send2FAEmail = send2FAEmail;
exports.send2FASMS = send2FASMS;
exports.cleanupExpiredOTPs = cleanupExpiredOTPs;

// ============================================================================
// REALTIME DATABASE: COMMENT NOTIFICATIONS
// ============================================================================

/**
 * Triggers when a new comment is created in Realtime Database
 * Path: postInteractions/{postId}/comments/{commentId}
 */
exports.onRealtimeCommentCreate = onValueCreated(
    {
      ref: "/postInteractions/{postId}/comments/{commentId}",
      region: "us-central1",
    },
    async (event) => {
      const postId = event.params.postId;
      const commentId = event.params.commentId;
      const commentData = event.data.val();

      console.log(`📝 New comment on post ${postId}: ${commentId}`);

      try {
        // Skip if this is a reply (has parentId)
        if (commentData.parentId) {
          console.log("⏭️ Skipping - this is a reply, not a top-level comment");
          return null;
        }

        // Get post to find the author
        const postDoc = await admin.firestore()
            .collection("posts")
            .doc(postId)
            .get();

        if (!postDoc.exists) {
          console.log("⚠️ Post not found");
          return null;
        }

        const postData = postDoc.data();
        const postAuthorId = postData.userId;
        const commentAuthorId = commentData.userId;

        // Don't notify if user comments on their own post
        if (postAuthorId === commentAuthorId) {
          console.log("⏭️ Skipping - user commented on their own post");
          return null;
        }

        // Get commenter's profile
        const commenterDoc = await admin.firestore()
            .collection("users")
            .doc(commentAuthorId)
            .get();

        const commenterData = commenterDoc.data();
        const commenterName = commenterData?.displayName || "Someone";

        // ✅ NEW: Include profile photo for Instagram-speed display
        const actorProfileImageURL = commenterData?.profileImageURL ||
                                     commenterData?.profilePictureURL ||
                                     "";

        // Create notification in Firestore
        const notification = {
          type: "comment",
          actorId: commentAuthorId,
          actorName: commenterName,
          actorUsername: commenterData?.username || "",
          actorProfileImageURL: actorProfileImageURL,  // ✅ NEW
          postId: postId,
          commentText: commentData.content || commentData.text || "",
          userId: postAuthorId,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        await admin.firestore()
            .collection("users")
            .doc(postAuthorId)
            .collection("notifications")
            .add(notification);

        console.log(`✅ Comment notification created for user ${postAuthorId}`);

        // Send push notification
        const userDoc = await admin.firestore()
            .collection("users")
            .doc(postAuthorId)
            .get();

        const fcmToken = userDoc.data()?.fcmToken;

        if (fcmToken) {
          await admin.messaging().send({
            notification: {
              title: "New Comment",
              body: `${commenterName} commented on your post`,
            },
            data: {
              type: "comment",
              actorId: commentAuthorId,
              postId: postId,
            },
            token: fcmToken,
          });
          console.log(`✅ Push notification sent to ${postAuthorId}`);
        }

        return {success: true};
      } catch (error) {
        console.error("❌ Error in onRealtimeCommentCreate:", error);
        return null;
      }
    },
);

/**
 * Triggers when a new reply is created in Realtime Database
 * Path: postInteractions/{postId}/comments/{commentId}
 */
exports.onRealtimeReplyCreate = onValueCreated(
    {
      ref: "/postInteractions/{postId}/comments/{commentId}",
      region: "us-central1",
    },
    async (event) => {
      const postId = event.params.postId;
      const commentId = event.params.commentId;
      const commentData = event.data.val();

      console.log(`💬 New reply on post ${postId}: ${commentId}`);

      try {
        // Only process if this is a reply (has parentId)
        if (!commentData.parentId) {
          console.log("⏭️ Skipping - this is a top-level comment, not a reply");
          return null;
        }

        // Get parent comment from RTDB
        const parentCommentSnapshot = await admin.database()
            .ref(`postInteractions/${postId}/comments/${commentData.parentId}`)
            .once("value");

        if (!parentCommentSnapshot.exists()) {
          console.log("⚠️ Parent comment not found");
          return null;
        }

        const parentCommentData = parentCommentSnapshot.val();
        const parentCommentAuthorId = parentCommentData.userId;
        const replyAuthorId = commentData.userId;

        // Don't notify if user replies to their own comment
        if (parentCommentAuthorId === replyAuthorId) {
          console.log("⏭️ Skipping - user replied to their own comment");
          return null;
        }

        // Get replier's profile
        const replierDoc = await admin.firestore()
            .collection("users")
            .doc(replyAuthorId)
            .get();

        const replierData = replierDoc.data();
        const replierName = replierData?.displayName || "Someone";

        // ✅ Include profile photo for Instagram-speed display
        const actorProfileImageURL = replierData?.profileImageURL ||
                                     replierData?.profilePictureURL ||
                                     "";

        // Create notification in Firestore
        const notification = {
          type: "reply",
          actorId: replyAuthorId,
          actorName: replierName,
          actorUsername: replierData?.username || "",
          actorProfileImageURL: actorProfileImageURL,  // ✅ NEW
          postId: postId,
          commentText: commentData.content || commentData.text || "",
          userId: parentCommentAuthorId,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        await admin.firestore()
            .collection("users")
            .doc(parentCommentAuthorId)
            .collection("notifications")
            .add(notification);

        console.log(`✅ Reply notification created for user ${parentCommentAuthorId}`);

        // Send push notification
        const userDoc = await admin.firestore()
            .collection("users")
            .doc(parentCommentAuthorId)
            .get();

        const fcmToken = userDoc.data()?.fcmToken;

        if (fcmToken) {
          await admin.messaging().send({
            notification: {
              title: "New Reply",
              body: `${replierName} replied to your comment`,
            },
            data: {
              type: "reply",
              actorId: replyAuthorId,
              postId: postId,
            },
            token: fcmToken,
          });
          console.log(`✅ Push notification sent to ${parentCommentAuthorId}`);
        }

        return {success: true};
      } catch (error) {
        console.error("❌ Error in onRealtimeReplyCreate:", error);
        return null;
      }
    },
);

// ============================================================================
// FIRESTORE: MESSAGE NOTIFICATIONS
// ============================================================================

/**
 * Triggers when a new message is sent in a conversation
 * Path: conversations/{conversationId}/messages/{messageId}
 */
exports.onMessageSent = onDocumentCreated(
    {
      document: "conversations/{conversationId}/messages/{messageId}",
      region: "us-central1",
    },
    async (event) => {
      const conversationId = event.params.conversationId;
      const messageId = event.params.messageId;
      const messageData = event.data.data();

      console.log(`💬 New message in conversation ${conversationId}: ${messageId}`);

      try {
        const senderId = messageData.senderId;
        const messageText = messageData.text || "";

        // Get conversation to find recipients
        const conversationDoc = await admin.firestore()
            .collection("conversations")
            .doc(conversationId)
            .get();

        if (!conversationDoc.exists) {
          console.log("⚠️ Conversation not found");
          return null;
        }

        const conversationData = conversationDoc.data();
        const participantIds = conversationData.participantIds || [];
        const conversationStatus = conversationData.conversationStatus || "accepted";
        const isGroup = conversationData.isGroup || false;
        const groupName = conversationData.groupName;

        // Get sender info
        const senderDoc = await admin.firestore()
            .collection("users")
            .doc(senderId)
            .get();

        const senderData = senderDoc.data();
        const senderName = senderData?.displayName || "Someone";
        const senderIsPrivate = senderData?.isPrivateAccount || false;

        // Send notification to all participants except sender
        const recipients = participantIds.filter((id) => id !== senderId);

        for (const recipientId of recipients) {
          // ✅ P0-7 FIX: Get recipient info for privacy checks
          const recipientDoc = await admin.firestore()
              .collection("users")
              .doc(recipientId)
              .get();

          const recipientData = recipientDoc.data();
          const recipientIsPrivate = recipientData?.isPrivateAccount || false;

          // ✅ P0-7 FIX: Check if users are blocked
          const senderBlockedUsers = senderData?.blockedUsers || [];
          const recipientBlockedUsers = recipientData?.blockedUsers || [];
          const isBlocked = senderBlockedUsers.includes(recipientId) ||
                          recipientBlockedUsers.includes(senderId);

          // ✅ P0-7 FIX: Determine if message preview should be hidden
          // Hide preview if: either user is private, OR users are blocked
          const shouldHidePreview = senderIsPrivate || recipientIsPrivate || isBlocked;

          // ✅ P0-7 FIX: Use generic message if privacy settings prevent preview
          const safeMessageText = shouldHidePreview ? "" : messageText.substring(0, 100);

          // Create notification
          const notification = {
            type: conversationStatus === "pending" ? "message_request" : "message",
            actorId: senderId,
            actorName: senderName,
            conversationId: conversationId,
            messageText: safeMessageText, // ✅ P0-7: Privacy-aware message text
            userId: recipientId,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          };

          await admin.firestore()
              .collection("users")
              .doc(recipientId)
              .collection("notifications")
              .add(notification);

          console.log(`✅ Message notification created for user ${recipientId}${shouldHidePreview ? " (preview hidden)" : ""}`);

          // Send push notification
          const fcmToken = recipientData?.fcmToken;

          if (fcmToken) {
            const notificationTitle = conversationStatus === "pending" ?
              "New Message Request" :
              isGroup ? groupName || "Group Message" : senderName;

            // ✅ P0-7 FIX: Use generic body if preview should be hidden
            const notificationBody = conversationStatus === "pending" ?
              `${senderName} wants to message you` :
              shouldHidePreview ? "New message" : messageText.substring(0, 100);

            await admin.messaging().send({
              notification: {
                title: notificationTitle,
                body: notificationBody,
              },
              data: {
                type: conversationStatus === "pending" ? "message_request" : "message",
                actorId: senderId,
                conversationId: conversationId,
              },
              token: fcmToken,
            });

            console.log(`✅ Push notification sent to ${recipientId}${shouldHidePreview ? " (generic message)" : ""}`);
          }
        }

        return {success: true};
      } catch (error) {
        console.error("❌ Error in onMessageSent:", error);
        return null;
      }
    },
);

// ============================================================================
// AI MODERATION, CRISIS DETECTION & SMART NOTIFICATIONS
// ============================================================================
const aiModeration = require("./aiModeration");

// Content Moderation
exports.moderateContent = aiModeration.moderateContent;

// Crisis Detection
exports.detectCrisis = aiModeration.detectCrisis;

// Smart Notifications
exports.deliverBatchedNotifications = aiModeration.deliverBatchedNotifications;

// ============================================================================
// AI CHURCH NOTES - SCRIPTURE REFERENCES & SUMMARIZATION
// ============================================================================
const aiChurchNotes = require("./aiChurchNotes");

// Scripture Cross-References
exports.findScriptureReferences = aiChurchNotes.findScriptureReferences;

// Note Summarization
exports.summarizeNote = aiChurchNotes.summarizeNote;

// ============================================================================
// AUTHENTICATION - USERNAME UNIQUENESS & ACCOUNT DELETION CASCADE
// ============================================================================
const authenticationHelpers = require("./authenticationHelpers");

// P0-2: Username Uniqueness Transaction
exports.reserveUsername = authenticationHelpers.reserveUsername;
exports.checkUsernameAvailability = authenticationHelpers.checkUsernameAvailability;

// P0-3: Account Deletion Cascade
exports.onUserDeleted = authenticationHelpers.onUserDeleted;
exports.manualCascadeDelete = authenticationHelpers.manualCascadeDelete;
