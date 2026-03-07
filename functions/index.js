/**
 * Firebase Cloud Functions for AMEN App
 * Compatible with Firebase Functions v7 (2nd generation)
 * Handles notifications, follows, and push notifications
 */

const admin = require("firebase-admin");
const {onValueCreated} = require("firebase-functions/v2/database");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");

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

// Shabbat Mode: server-side enforcement middleware
const {isSundayForUser} = require("./shabbatMiddleware");

// Server-side rate limiter (Firestore-backed, rolling window)
const {applyDefaultLimit} = require("./rateLimiter");

// Post + Comment pipeline (publish finalization, atomic counters, reactions, media)
const {
  finalizePostPublish,
  addComment,
  toggleReaction,
  onMediaFinalize,
  onPostCreateValidate,
} = require("./postAndCommentFunctions");

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

// Server-side post moderation (Firestore onWrite trigger)
const {serverSidePostModeration} = require("./contentModeration");
exports.serverSidePostModeration = serverSidePostModeration;

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

// Post + Comment pipeline
exports.finalizePostPublish  = finalizePostPublish;
exports.addComment           = addComment;
exports.toggleReaction       = toggleReaction;
exports.onMediaFinalize      = onMediaFinalize;
exports.onPostCreateValidate = onPostCreateValidate;

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
        // ── Shabbat guard ────────────────────────────────────────────────
        const commentAuthorId = commentData.userId;
        if (await isSundayForUser(commentAuthorId)) {
          console.log(`🕊️ Shabbat Mode active for ${commentAuthorId} — skipping comment notification`);
          return null;
        }
        // ────────────────────────────────────────────────────────────────

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
        // ── Shabbat guard ────────────────────────────────────────────────
        const replyAuthorId = commentData.userId;
        if (await isSundayForUser(replyAuthorId)) {
          console.log(`🕊️ Shabbat Mode active for ${replyAuthorId} — skipping reply notification`);
          return null;
        }
        // ────────────────────────────────────────────────────────────────

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

        // ── Shabbat guard ────────────────────────────────────────────────
        if (await isSundayForUser(senderId)) {
          console.log(`🕊️ Shabbat Mode active for ${senderId} — skipping message notification`);
          return null;
        }
        // ────────────────────────────────────────────────────────────────
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

// P0-2: Server-set ageTier — fires on user document creation, computes tier from birthYear.
exports.onUserDocCreated = authenticationHelpers.onUserDocCreated;

// P0: Account deletion pipeline (processes deletionRequests/{userId} — cascades
// Storage, RTDB, Firestore, and Auth deletion. Created when user taps Delete Account.)
const { processAccountDeletion } = require("./accountDeletion");
exports.processAccountDeletion = processAccountDeletion;

// ============================================================================
// BEREAN AI — All LLM calls go through these Cloud Functions.
// Credentials (OPENAI_API_KEY, GOOGLE_VISION_API_KEY) are stored in
// Firebase Secret Manager, never on device.
// Run: firebase functions:secrets:set OPENAI_API_KEY
//      firebase functions:secrets:set GOOGLE_VISION_API_KEY
// ============================================================================
const berean = require("./bereanFunctions");

exports.bereanBibleQA = berean.bereanBibleQA;
exports.bereanBibleQAFallback = berean.bereanBibleQAFallback;
exports.bereanMoralCounsel = berean.bereanMoralCounsel;
exports.bereanBusinessQA = berean.bereanBusinessQA;
exports.bereanNoteSummary = berean.bereanNoteSummary;
exports.bereanScriptureExtract = berean.bereanScriptureExtract;
exports.bereanPostAssist = berean.bereanPostAssist;
exports.bereanCommentAssist = berean.bereanCommentAssist;
exports.bereanDMSafety = berean.bereanDMSafety;
exports.bereanMediaSafety = berean.bereanMediaSafety;
exports.bereanFeedExplainer = berean.bereanFeedExplainer;
exports.bereanNotificationText = berean.bereanNotificationText;
exports.bereanReportTriage = berean.bereanReportTriage;
exports.bereanRankingLabels = berean.bereanRankingLabels;
exports.bereanGenericProxy = berean.bereanGenericProxy;

// ============================================================================
// GENKIT-STYLE AI FLOWS — daily verse, notification text, digest
// Replaces the external Genkit Cloud Run service (never deployed).
// DailyVerseGenkitService and NotificationGenkitService call these instead.
// ============================================================================
const genkit = require("./genkitFunctions");

exports.generateDailyVerse = genkit.generateDailyVerse;
exports.generateVerseReflection = genkit.generateVerseReflection;
exports.generateNotificationText = genkit.generateNotificationText;
exports.summarizeNotifications = genkit.summarizeNotifications;

// ============================================================================
// SCHEDULED: DAILY NOTIFICATION DIGEST PUSH
// Runs at 8:00 AM UTC daily.
// Finds users who have digest delivery enabled and undelivered digest docs,
// bundles their unread notifications, and sends a single FCM push.
//
// P1 FIX: Without this function the digest documents written by the iOS client
// would sit in Firestore indefinitely with no push ever sent.
// ============================================================================

exports.sendDailyNotificationDigest = onSchedule(
    {schedule: "0 8 * * *", timeZone: "UTC", region: "us-central1"},
    async () => {
      const db = admin.firestore();
      const today = new Date();
      today.setUTCHours(0, 0, 0, 0);

      console.log("⏰ Running daily notification digest delivery...");

      try {
        // Find all users who have digest mode enabled
        const usersSnap = await db.collection("users")
            .where("notificationSettings.digestMode", "==", true)
            .get();

        if (usersSnap.empty) {
          console.log("ℹ️ No users with digest mode enabled");
          return;
        }

        let deliveredCount = 0;

        for (const userDoc of usersSnap.docs) {
          const userId = userDoc.id;
          const userData = userDoc.data();

          // Skip users without a valid FCM token
          const deviceTokensSnap = await db.collection("users")
              .doc(userId)
              .collection("deviceTokens")
              .where("enabled", "==", true)
              .limit(1)
              .get();

          const hasToken = !deviceTokensSnap.empty || !!userData.fcmToken;
          if (!hasToken) continue;

          // Count unread notifications created since the start of today
          const unreadSnap = await db.collection("users")
              .doc(userId)
              .collection("notifications")
              .where("read", "==", false)
              .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(today))
              .get();

          if (unreadSnap.empty) continue;

          // Group by type for a friendly summary
          const typeCounts = {};
          for (const doc of unreadSnap.docs) {
            const t = doc.data().type || "activity";
            typeCounts[t] = (typeCounts[t] || 0) + 1;
          }

          const summaryParts = Object.entries(typeCounts).map(([type, count]) => {
            const label = {
              follow: "new follower",
              amen: "amen",
              comment: "comment",
              reply: "reply",
              mention: "mention",
              repost: "repost",
            }[type] || "notification";
            return `${count} ${label}${count === 1 ? "" : "s"}`;
          });

          const body = summaryParts.slice(0, 3).join(", ") +
              (summaryParts.length > 3 ? ` +${summaryParts.length - 3} more` : "");

          // Build the digest document ID for deep-linking
          const digestId = `${userId}_${today.getTime()}`;

          // Fan-out to all enabled device tokens
          const tokens = deviceTokensSnap.empty ?
              (userData.fcmToken ? [userData.fcmToken] : []) :
              deviceTokensSnap.docs.map((d) => d.data().token).filter(Boolean);

          const staleTokens = [];
          await Promise.all(tokens.map(async (token) => {
            try {
              await admin.messaging().send({
                notification: {
                  title: "Your Daily Summary",
                  body,
                },
                data: {
                  type: "digest",
                  digestId,
                  deepLink: `amen://notifications/digest/${digestId}`,
                  unreadCount: String(unreadSnap.size),
                },
                token,
              });
            } catch (err) {
              if (err.code === "messaging/registration-token-not-registered" ||
                  err.code === "messaging/invalid-registration-token") {
                staleTokens.push(token);
              }
            }
          }));

          // Clean stale tokens
          if (staleTokens.length > 0) {
            const batch = db.batch();
            deviceTokensSnap.docs.forEach((d) => {
              if (staleTokens.includes(d.data().token)) batch.delete(d.ref);
            });
            await batch.commit();
          }

          // Write/update the digest document so the iOS client can display history
          await db.collection("notificationDigests").doc(digestId).set({
            userId,
            period: "daily",
            itemCount: unreadSnap.size,
            typeCounts,
            delivered: true,
            deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
            opened: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});

          deliveredCount++;
        }

        console.log(`✅ Digest delivery complete — sent to ${deliveredCount} user(s)`);
      } catch (error) {
        console.error("❌ Error in sendDailyNotificationDigest:", error);
      }
    },
);
