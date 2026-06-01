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

const {
  resolveMusicAttachment,
} = require("./musicAttachmentResolver");

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
// checkPhoneVerificationRateLimit + reportPhoneVerificationFailure now owned by creator codebase (accountLifecycle.ts)
const {
  unblockPhoneNumber,
} = require("./phoneAuthRateLimit");

// P0: Two-Factor Authentication
// request2FAOTP + verify2FAOTP now owned by creator codebase (twoFactorAuth.ts)
const {
  send2FAEmail,
  send2FASMS,
  cleanupExpiredOTPs,
  expire2FASessions,
} = require("./twoFactorAuth");

// Shabbat Mode: server-side enforcement middleware
const {isSundayForUser} = require("./shabbatMiddleware");

// Post + Comment pipeline (publish finalization, atomic counters, reactions, media)
const {
  finalizePostPublish,
  addComment,
  toggleReaction,
  onMediaFinalize,
  onPostCreateValidate,
} = require("./postAndCommentFunctions");

const {
  onPostMediaMetadataCreate,
  onPostMediaMetadataUpdate,
  onPostMediaMetadataDelete,
} = require("./mediaMetadataPipeline");

const healthyImmersiveMedia = require("./healthyImmersiveMedia");

// Jobs Platform: notifications, alerts, moderation
const {
  onJobApplicationCreated,
  onJobApplicationUpdated,
  onJobListingCreated,
  reportJobListing,
} = require("./jobFunctions");

// Creator Studio: commissions, bookings, inquiries, earnings
const {
  onCommissionRequestCreated,
  onCommissionStatusUpdated,
  onBookingRequestCreated,
  onBookingStatusUpdated,
  onInquiryCreated,
  reportStudioContent,
  monthlyEarningsRollup,
} = require("./studioFunctions");

// Calendar & Events: RSVP counters, reminders, follow-ups
const {
  onEventRSVPCreated,
  onEventRSVPUpdated,
  sendEventReminders,
  sendPostEventFollowUp,
} = require("./eventFunctions");

// Fellowship Matcher: Claude-powered spiritual theme matching
const {
  fellowshipMatcher,
  onNewPrayerFellowshipCheck,
} = require("./fellowshipMatcher");

// Hey Feed: NL-driven feed control intelligence layer
const {
  submitHeyFeedNLRequest,
  removeHeyFeedNLPreference,
  resetHeyFeedNLPreferences,
  parseHeyFeedIntent,
  expireHeyFeedNLPreferences,
  rebuildFeedControlState,
} = require("./heyfeedFunctions");

// feedContextFunctions — now owned by creator codebase (Backend/functions)
// computeFeedContextLabels, attachFeedContextToRankedPosts, etc. removed from default

const {
  generateWeeklyAlignmentSummary,
} = require("./biblicalAlignmentFunctions");
// checkBiblicalAlignment and related callables now owned by creator codebase

const premiumEntitlements = require("./premiumEntitlements");

// Calm Control + Spiritual Rhythm OS
const calmControlFunctions = require("./calmControlFunctions");


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
exports.resolveMusicAttachment = resolveMusicAttachment;

// AI Personalization: Export ML-powered functions
exports.generatePersonalizedFeed = generatePersonalizedFeed;
exports.filterSmartNotifications = filterSmartNotifications;
exports.exportEngagementData = exportEngagementData;

// Content Moderation: Export organic content integrity system
// moderateContent temporarily skipped — deployed as GCFv2 on Firebase but defined as v1 here; needs gen2 conversion before redeploying
// exports.moderateContent = moderateContent;
exports.generateWeeklyAlignmentSummary = generateWeeklyAlignmentSummary;

exports.getPremiumEntitlement = premiumEntitlements.getPremiumEntitlement;
exports.syncPremiumEntitlement = premiumEntitlements.syncPremiumEntitlement;
exports.appStoreServerNotificationV2 = premiumEntitlements.appStoreServerNotificationV2;
exports.listCustomTopicTags = premiumEntitlements.listCustomTopicTags;
exports.createCustomTopicTag = premiumEntitlements.createCustomTopicTag;
exports.recordAIUsageAndCheckLimit = premiumEntitlements.recordAIUsageAndCheckLimit;
exports.requirePremiumFeature = premiumEntitlements.requirePremiumFeature;

// Server-side post moderation (Firestore onWrite trigger)
const {serverSidePostModeration} = require("./contentModeration");
exports.serverSidePostModeration = serverSidePostModeration;

// Image Moderation: Export Cloud Vision SafeSearch moderation
exports.moderateUploadedImage = moderateUploadedImage;

// P0: Phone Authentication Rate Limiting
// checkPhoneVerificationRateLimit + reportPhoneVerificationFailure moved to creator codebase
exports.unblockPhoneNumber = unblockPhoneNumber;

// P0: Two-Factor Authentication
// request2FAOTP + verify2FAOTP moved to creator codebase
exports.send2FAEmail = send2FAEmail;
exports.send2FASMS = send2FASMS;
exports.cleanupExpiredOTPs = cleanupExpiredOTPs;
exports.expire2FASessions = expire2FASessions;

// P0: Scheduled cleanup for expired 2FA sessions (hourly, guaranteed TTL enforcement)
const {cleanupExpired2FASessions} = require("./cleanupExpired2FASessions");
exports.cleanupExpired2FASessions = cleanupExpired2FASessions;

// Post + Comment pipeline
exports.finalizePostPublish = finalizePostPublish;
exports.addComment = addComment;
exports.toggleReaction = toggleReaction;
exports.onMediaFinalize = onMediaFinalize;
exports.onPostCreateValidate = onPostCreateValidate;
exports.onPostMediaMetadataCreate = onPostMediaMetadataCreate;
exports.onPostMediaMetadataUpdate = onPostMediaMetadataUpdate;
exports.onPostMediaMetadataDelete = onPostMediaMetadataDelete;

// createMediaUploadSession + finalizeMediaUpload moved to creator codebase (platformFunctions.ts)
exports.generateMediaDraftMetadata = healthyImmersiveMedia.generateMediaDraftMetadata;
// approveMediaMetadata — owned by Backend/functions (TS codebase); removed from default to resolve two-codebase conflict
exports.rejectMediaMetadata = healthyImmersiveMedia.rejectMediaMetadata;
exports.publishMediaPost = healthyImmersiveMedia.publishMediaPost;
exports.moderateMediaPost = healthyImmersiveMedia.moderateMediaPost;
// updateMediaProgress / createMediaSession / completeMediaSession / saveToMediaQueue / searchMedia / reportMedia
// — owned by Backend/functions TS codebase (selahMedia); removed from default to resolve conflict
exports.recordMediaEvent = healthyImmersiveMedia.recordMediaEvent;
exports.rankMedia = healthyImmersiveMedia.rankMedia;
exports.generateCaptionDraft = healthyImmersiveMedia.generateCaptionDraft;
exports.generateKeyMomentsDraft = healthyImmersiveMedia.generateKeyMomentsDraft;
exports.translateCaptions = healthyImmersiveMedia.translateCaptions;
exports.explainMediaMoment = healthyImmersiveMedia.explainMediaMoment;
exports.saveMediaAccessibilityPreferences = healthyImmersiveMedia.saveMediaAccessibilityPreferences;
exports.notInterestedMedia = healthyImmersiveMedia.notInterestedMedia;
exports.createMediaCompletionEvent = healthyImmersiveMedia.createMediaCompletionEvent;
exports.createTimestampedComment = healthyImmersiveMedia.createTimestampedComment;
exports.requestMediaUpload = healthyImmersiveMedia.requestMediaUpload;
exports.getNextSessionItems = healthyImmersiveMedia.getNextSessionItems;
exports.logMediaSessionEvent = healthyImmersiveMedia.logMediaSessionEvent;
exports.runMediaModeration = healthyImmersiveMedia.runMediaModeration;
exports.createMediaReflection = healthyImmersiveMedia.createMediaReflection;
exports.createMediaDiscussionReply = healthyImmersiveMedia.createMediaDiscussionReply;
exports.getCommunityMediaLayer = healthyImmersiveMedia.getCommunityMediaLayer;
exports.updateMediaPreferences = healthyImmersiveMedia.updateMediaPreferences;
exports.getMediaTrustContext = healthyImmersiveMedia.getMediaTrustContext;

// ============================================================================
// TRUST SCORE — E2EE messaging safety layer
// ============================================================================
const {
  onTrustScoreRequested,
  onMessageSafetyEvent,
  scheduledTrustScoreRefresh,
} = require("./trustScore");
exports.onTrustScoreRequested = onTrustScoreRequested;
exports.onMessageSafetyEvent = onMessageSafetyEvent;
exports.scheduledTrustScoreRefresh = scheduledTrustScoreRefresh;

// ============================================================================
// PHASE 2: SAFE MESSAGING — Pre-send safety gateway, trust scores, notification grouping
// ============================================================================

// Safe Messaging Gateway: Pre-send content moderation
const {safeMessageGateway} = require("./safeMessagingGateway");
exports.safeMessageGateway = safeMessageGateway;

// Trust Score System: User reputation tracking
const {
  onUserReported,
  onUserBlocked,
  onMessageRequestAccepted: onTrustRequestAccepted,
  onMessageRequestDeclined,
  recalculateTrustScores,
  initializeTrustScore,
} = require("./trustScoreSystem");
exports.onUserReported = onUserReported;
exports.onUserBlocked = onUserBlocked;
exports.onTrustRequestAccepted = onTrustRequestAccepted;
exports.onMessageRequestDeclined = onMessageRequestDeclined;
exports.recalculateTrustScores = recalculateTrustScores;
exports.initializeTrustScore = initializeTrustScore;

// Notification Grouping: Intelligent notification management
const {
  onMessageCreated,
  updateBadgeCount,
  getGroupedNotifications,
  markNotificationsRead,
} = require("./notificationGrouping");
exports.onMessageCreated = onMessageCreated;
exports.updateBadgeCount = updateBadgeCount;
exports.getGroupedNotifications = getGroupedNotifications;
exports.markNotificationsRead = markNotificationsRead;

// onChurchNoteCommentCreate — owned by Backend/functions TS codebase (churchNotes/churchNotesCommentModeration.ts);
// removed from default to resolve HTTPS↔trigger ghost conflict

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

        // ── #8 First Response Only ────────────────────────────────────────
        // Only fire this notification for the very first top-level comment so
        // the author gets a single "first response" moment, not a flood.
        // Count existing top-level comments (no parentId / parentCommentId) in RTDB.
        const allCommentsSnap = await admin.database()
            .ref(`postInteractions/${postId}/comments`)
            .once("value");
        let topLevelCount = 0;
        allCommentsSnap.forEach((child) => {
          const d = child.val();
          if (!d.parentId && !d.parentCommentId) topLevelCount++;
        });
        if (topLevelCount > 1) {
          console.log(`⏭️ Skipping first-response notification — ${topLevelCount} top-level comments already`);
          return null;
        }
        // ─────────────────────────────────────────────────────────────────

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
          actorProfileImageURL: actorProfileImageURL, // ✅ NEW
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
          actorProfileImageURL: actorProfileImageURL, // ✅ NEW
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

          console.log(
              `✅ Message notification created for user ${recipientId}` +
              `${shouldHidePreview ? " (preview hidden)" : ""}`,
          );

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

// Username → email resolver (used by SignInView for username-based login)
// Secure: email never stored in public Firestore; Admin SDK resolves uid → email server-side.
// Falls back to users collection query if usernameLookup doc is missing, and backfills it.
// Rate-limited: 10/hr per username hash, 30/hr per IP hash — protects against credential stuffing.
exports.resolveUsernameToEmail = authenticationHelpers.resolveUsernameToEmail;

// One-time backfill: populates usernameLookup for accounts pre-dating the index.
exports.backfillUsernameLookup = authenticationHelpers.backfillUsernameLookup;

// P0-3: Account Deletion Cascade
exports.onUserDeleted = authenticationHelpers.onUserDeleted;
exports.manualCascadeDelete = authenticationHelpers.manualCascadeDelete;

// P0-2: Server-set ageTier — fires on user document creation, computes tier from birthYear.
exports.onUserDocCreated = authenticationHelpers.onUserDocCreated;

// Sign-out current device: revoke refresh tokens (called during sign-out flow)
exports.revokeUserSessions = authenticationHelpers.revokeUserSessions;

// Session revocation (sign-out all other devices — requires recent auth ≤5 min)
exports.revokeOtherSessions = authenticationHelpers.revokeOtherSessions;

// Post-email-change: revoke other sessions + propagate new email to Firestore.
exports.onEmailChange = authenticationHelpers.onEmailChange;

// Post-password-change: revoke other sessions (requires recent auth ≤5 min).
exports.onPasswordChange = authenticationHelpers.onPasswordChange;

// P0: Account deletion pipeline (processes deletionRequests/{userId} — cascades
// Storage, RTDB, Firestore, and Auth deletion. Created when user taps Delete Account.)
const {processAccountDeletion} = require("./accountDeletion");
exports.processAccountDeletion = processAccountDeletion;

// ============================================================================
// AUTH ANOMALY DETECTION — sign-in event logging + rapid sign-in detection
// ============================================================================
const authAnomalyDetector = require("./authAnomalyDetector");

// Called by iOS client after every successful sign-in.
// Records device metadata (no IP/PII) and queues safety review on anomaly.
exports.logSignInEvent = authAnomalyDetector.logSignInEvent;

// ============================================================================
// USER ACTIVITY & FCM TOKEN LIFECYCLE
// onUserActivity     — callable: rate-limited lastActiveAt stamp (skip if <5 min)
// onFcmTokenRefresh  — callable: saves token + timezoneOffset, keeps 5 most recent
// onPostActivity     — trigger: stamp lastActiveAt on post creation
// onPrayerActivity   — trigger: stamp lastActiveAt on prayer creation
// onTestimonyActivity— trigger: stamp lastActiveAt + prayer arc hook on testimony link
// ============================================================================
const userActivity = require("./userActivityFunctions");
exports.onUserActivity = userActivity.onUserActivity;
exports.onFcmTokenRefresh = userActivity.onFcmTokenRefresh;
exports.onPostActivity = userActivity.onPostActivity;
exports.onPrayerActivity = userActivity.onPrayerActivity;
exports.onTestimonyActivity = userActivity.onTestimonyActivity;

// ============================================================================
// PRAYER ARC — testimony ↔ prayer link notifications + Berean insight pill
// onTestimonyLinked: FCM to intercessors when testimony links a prayer (once, idempotent)
// generateArcInsight: Claude haiku phrase cached in posts/{id}.bereanArcInsight
// ============================================================================
const prayerArc = require("./prayerArcFunctions");
exports.onTestimonyLinked = prayerArc.onTestimonyLinked;
exports.generateArcInsight = prayerArc.generateArcInsight;

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
// bereanGenericProxy + bereanChatProxy — owned by Backend/functions TS codebase (enforceAppCheck: true confirmed); removed from default codebase to resolve two-codebase conflict
exports.deleteAccount = berean.deleteAccount;
exports.bereanChatProxyStream = require("./bereanStreamProxy").bereanChatProxyStream;

// ============================================================================
// GENKIT-STYLE AI FLOWS — daily verse, notification text, digest
// Replaces the external Genkit Cloud Run service (never deployed).
// DailyVerseGenkitService and NotificationGenkitService call these instead.
// ============================================================================
const genkit = require("./genkitFunctions");

// generateDailyVerse is owned by Backend/functions; keep this off to avoid duplicate function names.
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

// ============================================================================
// JOBS PLATFORM
// ============================================================================
exports.onJobApplicationCreated = onJobApplicationCreated;
exports.onJobApplicationUpdated = onJobApplicationUpdated;
exports.onJobListingCreated = onJobListingCreated;
exports.reportJobListing = reportJobListing;

// ============================================================================
// CREATOR STUDIO
// ============================================================================
exports.onCommissionRequestCreated = onCommissionRequestCreated;
exports.onCommissionStatusUpdated = onCommissionStatusUpdated;
exports.onBookingRequestCreated = onBookingRequestCreated;
exports.onBookingStatusUpdated = onBookingStatusUpdated;
exports.onInquiryCreated = onInquiryCreated;
exports.reportStudioContent = reportStudioContent;
exports.monthlyEarningsRollup = monthlyEarningsRollup;

// ============================================================================
// CALENDAR & EVENTS
// ============================================================================
exports.onEventRSVPCreated = onEventRSVPCreated;
exports.onEventRSVPUpdated = onEventRSVPUpdated;
exports.sendEventReminders = sendEventReminders;
exports.sendPostEventFollowUp = sendPostEventFollowUp;

// ============================================================================
// TRANSLATION — Google Cloud Translation API v3
// ============================================================================
const {translateText} = require("./translationFunctions");
exports.translateText = translateText;

// ============================================================================
// SCHEDULED POSTS — publishes pending posts every 5 minutes
// Disabled: canonical scheduled post publisher is in mlContentPipeline.js (scheduledPostPublisherML)
// ============================================================================
const {executeScheduledPosts} = require("./scheduledPostsFunctions");
// exports.executeScheduledPosts = executeScheduledPosts;

// ============================================================================
// GDPR DATA EXPORT — "Download My Data" callable (legacy, kept for BC)
// ============================================================================
const {exportUserData: exportUserDataLegacy} = require("./dataExport");
exports.exportUserData = exportUserDataLegacy;

// ============================================================================
// USER DATA LIFECYCLE — GDPR/CCPA: export (rate-limited, recent-auth),
//   deleteBereanHistory (erase AI history + Pinecone vectors),
//   deleteAccountData (nuclear hard-delete, 5-min auth window)
// ============================================================================
const userDataLifecycle = require("./userDataLifecycle");
exports.exportUserDataV2        = userDataLifecycle.exportUserData;
// deleteBereanHistory — owned by Backend/functions TS codebase; removed from default to resolve conflict
exports.deleteAccountData       = userDataLifecycle.deleteAccountData;

// ============================================================================
// STRIPE CONNECT — Creator Studio payments
// ============================================================================
const stripe = require("./stripeFunctions");
exports.stripeCreateConnectedAccount = stripe.stripeCreateConnectedAccount;
exports.stripeGetAccountStatus = stripe.stripeGetAccountStatus;
exports.stripeCreatePaymentIntent = stripe.stripeCreatePaymentIntent;
exports.stripeRequestPayout = stripe.stripeRequestPayout;

// ============================================================================
// 242 HUB — Acts 2:42 Resource Hub (Flock Intelligence, Sermon Memory,
//            Prayer Wall Review, Values Verified, Kingdom Commerce)
// ============================================================================
const hub242 = require("./242hub");
exports.flockIntelligence = hub242.flockIntelligence;
exports.processSermonMemory = hub242.processSermonMemory;
exports.reviewPrayerSubmission = hub242.reviewPrayerSubmission;
exports.reviewCovenantApp = hub242.reviewCovenantApp;
exports.matchKingdomCommerce = hub242.matchKingdomCommerce;

// ============================================================================
// ML CONTENT PIPELINE — Post ML analysis, virality, deletion cleanup
// ============================================================================
const mlContent = require("./mlContentPipeline");
exports.onPostCreatedML = mlContent.onPostCreatedML;
exports.onPostDeletedML = mlContent.onPostDeletedML;
exports.computeViralityScore = mlContent.computeViralityScore;

// ============================================================================
// ML USER INTELLIGENCE — Interest graph, fatigue, creation nudge, session intent
// ============================================================================
const mlUser = require("./mlUserIntelligence");
exports.buildPassiveInterestGraph = mlUser.buildPassiveInterestGraph;
exports.detectSocialFatigue = mlUser.detectSocialFatigue;
exports.predictCreationPropensity = mlUser.predictCreationPropensity;
exports.computeSessionIntent = mlUser.computeSessionIntent;
exports.updateSpiritualHealthScore = mlUser.updateSpiritualHealthScore;

// ============================================================================
// ML PRAYER INTELLIGENCE — Intercessor matching, testimony linking, gifts, verse
// ============================================================================
const mlPrayer = require("./mlPrayerIntelligence");
exports.matchIntercessors = mlPrayer.matchIntercessors;
exports.detectTestimonyOutcome = mlPrayer.detectTestimonyOutcome;
exports.detectSpiritualGift = mlPrayer.detectSpiritualGift;
exports.computeScriptureSentimentMatch = mlPrayer.computeScriptureSentimentMatch;
exports.generatePersonalVerseEngine = mlPrayer.generatePersonalVerseEngine;

// ============================================================================
// ML COMMUNITY INTELLIGENCE — Health reports, coordinated behavior, safety
// ============================================================================
const mlCommunity = require("./mlCommunityIntelligence");
exports.generateCongregationHealthReport = mlCommunity.generateCongregationHealthReport;
exports.detectCoordinatedBehavior = mlCommunity.detectCoordinatedBehavior;
exports.runLinguisticFingerprint = mlCommunity.runLinguisticFingerprint;
exports.detectGriefCrisisPreIncident = mlCommunity.detectGriefCrisisPreIncident;
exports.runZeroHarassmentDetection = mlCommunity.runZeroHarassmentDetection;
exports.scoreTheologicalDrift = mlCommunity.scoreTheologicalDrift;

// ============================================================================
// ML NOTIFICATION & INFRASTRUCTURE — Feed re-rank, SLO, cost audit, churn
// ============================================================================
const mlNotif = require("./mlNotificationIntelligence");
exports.predictNotificationChurn = mlNotif.predictNotificationChurn;
exports.reRankFeedRealTime = mlNotif.reRankFeedRealTime;
exports.runSLOAnomalyDetection = mlNotif.runSLOAnomalyDetection;
exports.costOptimizationAudit = mlNotif.costOptimizationAudit;
exports.runAgeSignalDetection = mlNotif.runAgeSignalDetection;

// ============================================================================
// NOTIFICATIONS — Prayer amens/comments, mentions, scheduled campaigns
// ============================================================================
const {
  onPrayerAmen,
  onPrayerComment,
  onPostMention,
  weeklyCheckin,
  communityDigest,
  bereanDailyInsight,
} = require("./notifications");
exports.onPrayerAmen = onPrayerAmen;
exports.onPrayerComment = onPrayerComment;
exports.onPostMention = onPostMention;
exports.weeklyCheckin = weeklyCheckin;
exports.communityDigest = communityDigest;
exports.bereanDailyInsight = bereanDailyInsight;

// ============================================================================
// MESSAGES FEATURES — Prayer Chain, Time Capsule, Accountability, Grace Drop,
//                     Cold Thread Revival, Prayer Room
// ============================================================================
const msgFeatures = require("./messages_features");
exports.onPrayerChainUpdated = msgFeatures.onPrayerChainUpdated;
exports.processTimeCapsules = msgFeatures.processTimeCapsules;
exports.sendWeeklyAccountabilityCheckIn = msgFeatures.sendWeeklyAccountabilityCheckIn;
exports.revealGraceDropIdentity = msgFeatures.revealGraceDropIdentity;
exports.analyzeThreadsForRevival = msgFeatures.analyzeThreadsForRevival;
exports.notifyPrayerRoomAnswered = msgFeatures.notifyPrayerRoomAnswered;

// System 36: Smart Inbox Denormalization (forward-only, RC-gated)
const smartInbox = require("./smartInboxDenormalization");
exports.onMessageCreatedForSmartInbox = smartInbox.onMessageCreatedForSmartInbox;
exports.onMessageCreatedClearsNeedsReply = smartInbox.onMessageCreatedClearsNeedsReply;

// Algolia sync — Firestore triggers (post create/update) + server-side callable write wrappers
const algoliaSync = require("./algoliaSync");
// onPostCreatedSyncAlgolia / onPostUpdatedSyncAlgolia — persistent HTTPS ghost conflict;
// Backend/functions TS codebase owns algoliaPostUpdateSync + algoliaPostDeleteSync;
// create-sync TODO: add algoliaPostCreateSync to Backend TS to close the gap
exports.algolia_syncUser = algoliaSync.algolia_syncUser;
exports.algolia_deleteUser = algoliaSync.algolia_deleteUser;
exports.algolia_syncPost = algoliaSync.algolia_syncPost;
exports.algolia_deletePost = algoliaSync.algolia_deletePost;

// ============================================================================
// FELLOWSHIP MATCHER — Claude-powered spiritual theme matching
// ============================================================================
exports.fellowshipMatcher = fellowshipMatcher;
exports.onNewPrayerFellowshipCheck = onNewPrayerFellowshipCheck;

// ============================================================================
// OPENAI PROXIES — All OpenAI API calls go through these Cloud Functions.
// Client Swift code must NEVER call api.openai.com directly.
// The OPENAI_API_KEY lives only in Firebase Secret Manager (never on-device).
// Run: firebase functions:secrets:set OPENAI_API_KEY
// NOTE: openAIProxy and whisperProxy now use TypeScript versions from Backend/functions
// ============================================================================
const openAIFunctions = require("./openAIFunctions");
// exports.openAIProxy = openAIFunctions.openAIProxy;
// exports.whisperProxy = openAIFunctions.whisperProxy;
exports.transcribeAudio = openAIFunctions.transcribeAudio;
exports.smartSuggestionsProxy = openAIFunctions.smartSuggestionsProxy;

// ============================================================================
// H-05: AMEN STUDIO AI — content generation & journal reflection
// amenStudioAI.js was orphaned (never imported). iOS calls studioGenerateContent
// and studioJournalPrompt via httpsCallable() and received NOT_FOUND. Fixed here.
// ============================================================================
const amenStudioAI = require("./amenStudioAI");
exports.studioGenerateContent = amenStudioAI.studioGenerateContent;
exports.studioJournalPrompt = amenStudioAI.studioJournalPrompt;


// ============================================================================
// CHURCH ENHANCEMENTS — Sunday vibe, DNA scores, prayer momentum, visit guide
// ============================================================================
const churchEnhancements = require("./churchEnhancementFunctions");
exports.generateChurchVibe = churchEnhancements.generateChurchVibe;
exports.computeChurchDNA = churchEnhancements.computeChurchDNA;
exports.computePrayerMomentum = churchEnhancements.computePrayerMomentum;
exports.generateFirstVisitGuide = churchEnhancements.generateFirstVisitGuide;
exports.inferUserLearningStyle = churchEnhancements.inferUserLearningStyle;
exports.inferPastorStyle = churchEnhancements.inferPastorStyle;

// ============================================================================
// BEREAN FEATURE FUNCTIONS — semantic search, spiritual timeline, study guide
// ============================================================================
const bereanFeatures = require("./bereanFeatureFunctions");
exports.bereanEmbedProxy = bereanFeatures.bereanEmbedProxy;
exports.generateSpiritualTimeline = bereanFeatures.generateSpiritualTimeline;
exports.generateStudyGuide = bereanFeatures.generateStudyGuide;

// ============================================================================
// ENGAGEMENT NOTIFICATIONS
//   #3  Testimony Anniversary   — daily, 1-year anniversary
//   #4  Friend Returned         — daily, 14-day gap detection, 30-day cap
//   #6  Gentle Re-engagement    — Sunday-only, 7-day dormancy, 14-day cap
//   #7  New Church Member       — Firestore trigger on churchId transition
//   #10 Prayer Check-in         — Wednesday, 7-day-old prayers, 14-day cap
// ============================================================================
const engagementNotifs = require("./engagementNotifications");
exports.testimonyAnniversary = engagementNotifs.testimonyAnniversary;
exports.friendReturned = engagementNotifs.friendReturned;
exports.gentleReengagement = engagementNotifs.gentleReengagement;
exports.onNewChurchMember = engagementNotifs.onNewChurchMember;
exports.prayerCheckin = engagementNotifs.prayerCheckin;

// ============================================================================
// PROFILE PROPAGATION — syncs denormalized author fields on posts/comments
// when a user changes their displayName, username, or profileImageURL.
// ============================================================================
const {onUserProfileUpdated, normalizePostAuthorOnCreate} = require("./profilePropagation");
exports.onUserProfileUpdated = onUserProfileUpdated;
exports.normalizePostAuthorOnCreate = normalizePostAuthorOnCreate;

// ============================================================================
// NOTIFICATION CLEANUP — daily scheduled job (3 AM UTC).
// Deletes read notifications >90 days old, unread >180 days old,
// and caps each user's notification subcollection at 500 documents.
// ============================================================================
const {cleanupStaleNotifications} = require("./notificationCleanup");
exports.cleanupStaleNotifications = cleanupStaleNotifications;

// ============================================================================
// HEY FEED — NL-driven feed control intelligence layer
//   submitHeyFeedNLRequest    — callable: parse NL text, write preferences
//   removeHeyFeedNLPreference — callable: deactivate single preference
//   resetHeyFeedNLPreferences — callable: clear all active preferences
//   parseHeyFeedIntent        — callable: preview parse (no write)
//   expireHeyFeedNLPreferences — scheduled every 4h: expire stale prefs
//   rebuildFeedControlState    — scheduled every 1h: housekeeping
// ============================================================================
exports.submitHeyFeedNLRequest = submitHeyFeedNLRequest;
exports.removeHeyFeedNLPreference = removeHeyFeedNLPreference;
exports.resetHeyFeedNLPreferences = resetHeyFeedNLPreferences;
exports.parseHeyFeedIntent = parseHeyFeedIntent;
exports.expireHeyFeedNLPreferences = expireHeyFeedNLPreferences;
exports.rebuildFeedControlState = rebuildFeedControlState;

// ============================================================================
// CONVERSATION OS — Intelligent Conversation Intelligence Layer
//   generateCatchUpRecap          — callable: AI catch-up recap for unread messages
//   generateTopicClusters         — callable: semantic (non-chronological) topic clustering
//   extractConversationActions    — callable: extract actions, decisions, questions
//   getPersonalizedSummary        — callable: role-aware personalized summary
//   queryOrganizationalMemory     — callable: org-level memory query
//   updateConversationActionStatus — callable: mark action done/dismissed
//   updateConversationDecision    — callable: confirm/challenge a decision
//   dismissConversationSummary    — callable: user dismisses a summary
// All callables: App Check enforced, permissions validated, output moderated.
// ============================================================================
const conversationOSFns = require("./conversationOSFunctions");
exports.generateCatchUpRecap = conversationOSFns.generateCatchUpRecap;
exports.generateTopicClusters = conversationOSFns.generateTopicClusters;
exports.extractConversationActions = conversationOSFns.extractConversationActions;
exports.getPersonalizedSummary = conversationOSFns.getPersonalizedSummary;
exports.queryOrganizationalMemory = conversationOSFns.queryOrganizationalMemory;
exports.updateConversationActionStatus = conversationOSFns.updateConversationActionStatus;
exports.updateConversationDecision = conversationOSFns.updateConversationDecision;
exports.dismissConversationSummary = conversationOSFns.dismissConversationSummary;

// ============================================================================
// COMMS OS — Communication OS Intelligence Layer (all flags OFF by default)
//   comms_rankRelevance        — callable: score thread relevance to user
//   comms_routeIntent          — callable: route NL query to structured intent
//   comms_generateSmartContext — callable: decisions + actions + blockers for thread
//   comms_generateCatchUp      — callable: catch-up summary for unread messages
//   comms_submitFeedback       — callable: record user feedback (accept/dismiss/correct)
//   comms_processMediaJob      — callable: start media intelligence job
//   comms_getMediaJobStatus    — callable: poll media job status
//   comms_suggestAsyncReply    — callable: AI-suggested async reply
// All: App Check enforced, membership validated, output moderated, audit logged.
// ============================================================================
const commsOSFns = require("./commsOS");
exports.comms_rankRelevance = commsOSFns.comms_rankRelevance;
exports.comms_routeIntent = commsOSFns.comms_routeIntent;
exports.comms_generateSmartContext = commsOSFns.comms_generateSmartContext;
exports.comms_generateCatchUp = commsOSFns.comms_generateCatchUp;
exports.comms_submitFeedback = commsOSFns.comms_submitFeedback;
exports.comms_processMediaJob = commsOSFns.comms_processMediaJob;
exports.comms_getMediaJobStatus = commsOSFns.comms_getMediaJobStatus;
exports.comms_suggestAsyncReply = commsOSFns.comms_suggestAsyncReply;

// Smart Context Labels — now owned by creator codebase (Backend/functions)
// computeFeedContextLabels, attachFeedContextToRankedPosts, etc. removed from default

// ============================================================================
// AMEN CREATOR — AI Scene Builder + Living Templates
//   generateScenePlan          — callable: generate structured timeline from assets + intent
//   refineScenePlan            — callable: refine plan from NL prompt
//   runCreationSafetyCheck     — callable: safety check before publish
//   applyTemplateToAssets      — callable: map assets to template structure
//   generateCaptionSuggestions — callable: AI caption suggestions
//   saveCreationDraft          — callable: persist draft to Firestore
//   trackTemplateUsage         — callable: analytics for template affinity
// ============================================================================
const {
  generateScenePlan,
  refineScenePlan,
  runCreationSafetyCheck,
  applyTemplateToAssets,
  generateCaptionSuggestions,
  saveCreationDraft,
  trackTemplateUsage,
} = require("./creationFunctions");

exports.generateScenePlan = generateScenePlan;
exports.refineScenePlan = refineScenePlan;
exports.runCreationSafetyCheck = runCreationSafetyCheck;
exports.applyTemplateToAssets = applyTemplateToAssets;
exports.generateCaptionSuggestions = generateCaptionSuggestions;
exports.saveCreationDraft = saveCreationDraft;
exports.trackTemplateUsage = trackTemplateUsage;

// Scheduled post publisher — Disabled: canonical scheduled post publisher is in mlContentPipeline.js (scheduledPostPublisherML)
const {publishScheduledPosts} = require("./scheduledPostPublisher");
// exports.publishScheduledPosts = publishScheduledPosts;

// ============================================================================
// ACTION THREADS — Support workflows attached to posts (System 8)
//   onActionThreadCreated          — trigger: validate thread, record trust event
//   onActionStepCompleted          — trigger: notify participants on step completion
//   processActionThreadReminders   — scheduled hourly: send step reminders
//   cleanupExpiredActionThreads    — scheduled daily 4 AM: expire stale threads
// ============================================================================
const actionThreads = require("./actionThreadFunctions");
exports.onActionThreadCreated = actionThreads.onActionThreadCreated;
exports.onActionStepCompleted = actionThreads.onActionStepCompleted;
exports.processActionThreadReminders = actionThreads.processActionThreadReminders;
exports.cleanupExpiredActionThreads = actionThreads.cleanupExpiredActionThreads;

// Topic Enrichment (System 11) — server-side fallback for post topic tagging
const topicEnrichment = require("./topicEnrichment");
exports.enrichPostTopics = topicEnrichment.enrichPostTopics;

// Media State Cleanup (System 12) — daily cleanup of expired resume positions
const mediaCleanup = require("./mediaStateCleanup");
exports.cleanupMediaResumeState = mediaCleanup.cleanupMediaResumeState;

// Canonical notifications pipeline (compiled from TypeScript source under
// AMENAPP/AMENAPP/CloudFunction_NotificationRoutingPipeline.ts).
Object.assign(
    exports,
    require("./dist-notifications/functions/notificationRoutingPipeline.entry.js"),
);

// ============================================================================
// SYSTEM 35 — Trust Spine (Phase 1, Spatial Social OS)
//   registerMediaProvenance — record media origin + edit/AI chain
//   getPostProvenance       — fetch user-visible provenance for a media item
//   registerAIDisclosure    — record an AI action with trusted user-visible label
//   getAIDisclosureDetails  — fetch AI disclosure records for a media item
//   reportContent           — submit a content report (writes /reports + queue)
// ============================================================================
const provenanceFns = require("./provenanceFunctions");
// registerMediaProvenance moved to creator codebase (media/registerMediaProvenance.ts)
exports.getPostProvenance = provenanceFns.getPostProvenance;

const aiDisclosureFns = require("./aiDisclosureFunctions");
exports.registerAIDisclosure = aiDisclosureFns.registerAIDisclosure;
exports.getAIDisclosureDetails = aiDisclosureFns.getAIDisclosureDetails;

const reportFns = require("./reportFunctions");
exports.reportContent = reportFns.reportContent;

// Publish pipeline trust gate (Phase 2). Validates provenance + AI disclosures
// before allowing finalizePostPublish to run.
const publishPipelineFns = require("./publishPipelineFunctions");
exports.publishPostWithTrustGates = publishPipelineFns.publishPostWithTrustGates;

// Discovery transparency (Phase 4). "Why am I seeing this?" — returns the
// server-derived reasons a given post surfaced in the user's feed.
const discoveryTransparencyFns = require("./discoveryTransparencyFunctions");
exports.getDiscoveryReasons = discoveryTransparencyFns.getDiscoveryReasons;

// Spatial messages (Phase 5). Shared viewing rooms + anchored replies. The
// client never writes /sharedViewingRooms or /presenceSessions directly —
// all membership transitions flow through these callables.
const spatialMessagesFns = require("./spatialMessagesFunctions");
exports.createSharedViewingRoom = spatialMessagesFns.createSharedViewingRoom;
exports.joinSharedViewingRoom = spatialMessagesFns.joinSharedViewingRoom;
exports.leaveSharedViewingRoom = spatialMessagesFns.leaveSharedViewingRoom;
exports.postAnchoredReply = spatialMessagesFns.postAnchoredReply;

// Access Pass callables are owned by the creator codebase
// (Backend/functions/src/accessPasses). Keeping them out of the default
// codebase prevents duplicate Firebase function ownership during deploy.

// ============================================================================
// CONTEXTUAL EXPERIENCES — multi-tenant seasonal / organization / event layer
// All mutations are server-owned and guarded by membership role checks.
// ============================================================================
const contextualExperienceFns = require("./contextualExperiences");
// All contextual experience functions — owned by Backend/functions TS codebase (contextualExperiences);
// removed from default codebase to resolve two-codebase conflict

// (conversationOSFns exported at line ~1185 above — no duplicate needed here)

// ============================================================================
// SELAH BANNER RAIL — editorial banners for Spaces surfaces
// Server resolves eligibility, ranking, safety, and CTA validity.
// Client is dumb: renders a pre-sorted, pre-validated list only.
// ============================================================================
const bannerFns = require("./banners");
exports.resolveBannerRail                   = bannerFns.resolveBannerRail;
// logAmenSpaceBannerEvent / validateAmenSpaceBannerCTA / setAmenSpaceBannerDisplayPreference / setAmenSpaceDefaultBannerSize
// — owned by Backend/functions TS codebase (amenSpaceBanners); removed from default to resolve two-codebase conflict

// Anonymous Berean — single question, no userId, no session history
const anonymousBereanFns = require("./anonymousBerean");
exports.anonymousBereanQuery = anonymousBereanFns.anonymousBereanQuery;

// ============================================================================
// AI PROMPT FEATURES — UI-driven per-user AI callables
//   vibeMatch               — 1-sentence spiritual connection reason (Claude Haiku)
//   digestBrain             — spiritual journey digest paragraph (Claude Sonnet)
//   spiritGraph             — 1-sentence feed post explanation (Claude Haiku)
//   testimonyResonanceScore — affirming micro-copy after testimony action (Claude Haiku)
//   livingWordEngine        — 3 contextual scripture suggestions for post draft (Claude Sonnet)
// All: App Check enforced, auth required, shared 50/hr + 200/day per-user rate limit,
//      global Anthropic circuit-breaker.
// ============================================================================
const aiPromptFeaturesFns = require("./aiPromptFeatures");
exports.vibeMatch               = aiPromptFeaturesFns.vibeMatch;
exports.digestBrain             = aiPromptFeaturesFns.digestBrain;
exports.spiritGraph             = aiPromptFeaturesFns.spiritGraph;
exports.testimonyResonanceScore = aiPromptFeaturesFns.testimonyResonanceScore;
exports.livingWordEngine        = aiPromptFeaturesFns.livingWordEngine;

// ============================================================================
// SAFETY DETECTION — Abuse signals, minor protection, crisis hook, appeals
//   onNewDMMessage              — Firestore trigger: abuse/exploitation/fraud signal
//                                 extraction on new DM docs (metadata only, no content stored)
//   onNewDMForMinorProtection   — Firestore trigger: grooming pattern detection for
//                                 adult→minor DMs (feature-flag gated, fail-closed)
//   submitAppeal                — callable: user submits appeal for a moderation action
//   getAppealStatus             — callable: user checks status of their appeal
//   resolveAppeal               — callable: moderator resolves an appeal (HITL gate)
// crisisDetectionHook is imported internally by bereanFunctions — no direct export needed.
// All triggers: no content stored; metadata-only; all actions require human review.
// ============================================================================
const abuseDetectionFns = require('./abuseDetectionSignals');
exports.onNewDMMessage = onDocumentCreated(
  { document: 'conversations/{conversationId}/messages/{messageId}', region: 'us-central1' },
  abuseDetectionFns.handleNewDMMessage
);

const minorSafetyFns = require('./minorSafetyHook');
exports.onNewDMForMinorProtection = onDocumentCreated(
  { document: 'conversations/{conversationId}/messages/{messageId}', region: 'us-central1' },
  minorSafetyFns.handleNewDMForMinorProtection
);

const appealsFns = require('./appealsService');
// submitAppeal / getAppealStatus / resolveAppeal — owned by Backend/functions TS codebase; removed from default to resolve conflict

// ============================================================================
// CALM CONTROL + SPIRITUAL RHYTHM OS
// ============================================================================
// evaluateNotificationEligibility — owned by Backend/functions TS codebase; removed from default to resolve conflict
exports.updateCalmControlSettings        = calmControlFunctions.updateCalmControlSettings;
exports.updateRhythmSettings             = calmControlFunctions.updateRhythmSettings;
// recordSpiritualActivity — owned by Backend/functions TS codebase; removed from default to resolve conflict
exports.calculateStreakState             = calmControlFunctions.calculateStreakState;
// pauseInactiveUserNotifications / restoreUserAfterInactivity — owned by Backend/functions TS codebase; removed from default to resolve conflict
exports.checkSpiritualRhythmInactivity   = calmControlFunctions.checkSpiritualRhythmInactivity;
exports.updatePrivacySettings            = calmControlFunctions.updatePrivacySettings;
exports.updateFeedControls               = calmControlFunctions.updateFeedControls;
exports.updateNotificationSettings       = calmControlFunctions.updateNotificationSettings;
exports.createAudienceLayer              = calmControlFunctions.createAudienceLayer;
exports.deleteAudienceLayer              = calmControlFunctions.deleteAudienceLayer;
exports.expirePresenceStates             = calmControlFunctions.expirePresenceStates;

// ============================================================================
// SMART COLLABORATION LAYER — Phase 1 (all flags OFF by default)
//   generateThreadSummary         — callable: AI summary of last 50 messages, writes ThreadSummary + ThreadSmartContext
//   detectPrayerContextForThread  — callable: prayer request detection for a single message, stores theme category only
//   extractThreadActions          — callable: action items / decisions / commitments from last 30 messages
//   generateGroupPulse            — callable: urgency + topic momentum for channel threads
//   generateSmartReplies          — callable: 3 ephemeral faith-affirming reply suggestions
//   requestMediaTranscription     — callable: queue async audio/video transcription job
// All: App Check enforced, membership server-verified, feature-flagged, moderated.
// LLM: Anthropic claude-3-haiku via CLAUDE_API_KEY secret. No raw message text in logs.
// ============================================================================
const smartCollabFns = require("./src/smartCollaboration/dist");
// generateThreadSummary — owned by Backend/functions TS codebase; removed from default to resolve conflict
exports.detectPrayerContextForThread = smartCollabFns.detectPrayerContextForThread;
// extractThreadActions / generateGroupPulse / generateSmartReplies — owned by Backend/functions TS codebase; removed from default to resolve conflict
exports.requestMediaTranscription    = smartCollabFns.requestMediaTranscription;

// ============================================================================
// DISCOVER / FEATURED CAROUSEL
//   setFeatured             — admin-only callable: create/update a featured card (moderationCleared=false)
//   clearFeaturedModeration — admin-only callable: approve a card post-GUARDIAN review
//   markEngaged             — user callable: upsert users/{uid}/continue entry on content open/play
//   deleteContinueRow       — user callable: remove one Continue-in-AMEN entry
// ============================================================================
const discoverFns = require('./discoverFunctions');
// setFeatured / clearFeaturedModeration / markEngaged / deleteContinueRow — owned by Backend/functions TS codebase; removed from default to resolve conflict


// ============================================================================
// MEDIA INTERACTIONS — Agent 0 Stubs (Agents 1–7 implement the bodies)
//   addReaction       — callable: idempotent upsert of a MediaReaction
//   removeReaction    — callable: delete a reaction the caller owns
//   pinReply          — callable: creator pins one comment to top of media
//   saveToCollection  — callable: bookmark a media item into a named collection
//   translateText     — callable: Claude proxy translation for captions/comments
//   attachVerse       — callable: validate scripture ref and pin to reaction/comment/post
// All: Auth required, App Check enforced.
// ============================================================================
const mediaInteractionFns = require('./src/mediaInteractions');
exports.addReaction      = mediaInteractionFns.addReaction;
exports.removeReaction   = mediaInteractionFns.removeReaction;
exports.pinReply         = mediaInteractionFns.pinReply;
exports.saveToCollection = mediaInteractionFns.saveToCollection;
exports.translateText    = mediaInteractionFns.translateText;
exports.attachVerse      = mediaInteractionFns.attachVerse;
exports.expireViewOnceMedia    = mediaInteractionFns.expireViewOnceMedia;
exports.cleanupExpiredMutes    = mediaInteractionFns.cleanupExpiredMutes;
exports.sendScheduledMessages  = mediaInteractionFns.sendScheduledMessages;

// ============================================================================
// AMEN Spaces — Data Layer + Entitlement Cloud Functions (Agent A)
//   grantSpaceAccess           — callable: admin grants entitlement to a user
//   handleStripeSpaceWebhook   — HTTP endpoint: Stripe subscription lifecycle
//   revokeSpaceLinkAccess      — callable: revoke external member access on link revocation
// Agent F Cross-Community Links:
//   notifyCommunityLinkInvite  — Firestore onCreate trigger: push to target community admins
// Auth required; grantSpaceAccess and revokeSpaceLinkAccess enforce App Check.
// ============================================================================
const spacesFns = require('./src/spaces/dist');
exports.grantSpaceAccess             = spacesFns.grantSpaceAccess;
exports.handleStripeSpaceWebhook     = spacesFns.handleStripeSpaceWebhook;
exports.revokeSpaceLinkAccess        = spacesFns.revokeSpaceLinkAccess;
// notifyCommunityLinkInvite — persistent HTTPS ghost conflict; removed from default to resolve

// ============================================================================
// SECURITY MONITORING — Hourly spend + auth anomaly detection
//   hourlyAnomalyCheck — scheduled every 60 min: checks AI spend vs. caps,
//                        global sign-in rate, and per-user Berean call spikes.
//                        Writes alerts to meta/anomalyAlerts/alerts/{id}.
// ============================================================================
const anomalyMonitor = require('./anomalyMonitor');
exports.hourlyAnomalyCheck = anomalyMonitor.hourlyAnomalyCheck;

// ============================================================================
// DATA-EXPORT IMPORT PIPELINE — Berean conversion gate for user-owned archives
//   ingestImportArchive      — Storage trigger: fires on imports/{uid}/{jobId}/archive.zip
//                              Unzips archive, discovers structure, extracts posts + media,
//                              writes ImportCandidate docs, deletes raw archive, sets status=classifying
//   classifyImportCandidates — Firestore trigger: fires when job status → "classifying"
//                              Runs cheap pre-filter then Berean LLM gate on each candidate,
//                              writes bereanClassification, sets status=ready
//
// Deploy: firebase deploy --only functions:ingestImportArchive,functions:classifyImportCandidates
// ============================================================================
const importFns = require('./importFunctions');
exports.ingestImportArchive      = importFns.ingestImportArchive;
exports.classifyImportCandidates = importFns.classifyImportCandidates;

// ============================================================================
// FIND A CHURCH — churchSearchProxy (Phase 1 / Master Run A8)
//   churchSearchProxy — callable: searches active Firestore church records with
//                       server-side geo/text filtering. App Check + Auth enforced;
//                       no search credentials live on device.
// Deploy: firebase deploy --only functions:churchSearchProxy
// ============================================================================
const churchSearchProxyFns = require('./src/church/churchSearchProxy');
exports.churchSearchProxy = churchSearchProxyFns.churchSearchProxy;

// ============================================================================
// POST PROVENANCE — postProvenanceProxy (Phase 3 / Master Run A8)
//   postProvenanceProxy — callable: returns feed-ranking signals for a post
//                         ("Why you're seeing this" disclosure). App Check +
//                         Auth enforced; no raw ML signals on device.
// Deploy: firebase deploy --only functions:postProvenanceProxy
// ============================================================================
const postProvenanceProxyFns = require('./src/provenance/postProvenanceProxy');
exports.postProvenanceProxy = postProvenanceProxyFns.postProvenanceProxy;

// ============================================================================
// SELAH STORIES — selahStoryProxy (Phase 5 / Master Run A8)
//   selahStoryProxy — callable: handles all Selah Stories AI operations
//                     actions: recognizeVerse | generateReflectionPrompt |
//                              matchAudio | createStory | deleteStory
//                     App Check + Auth enforced; no AI credentials on device.
//
// Compatibility callables are also exported for the current iOS service:
//   createSelahStory, deleteSelahStory, selahRecognizeVerse,
//   selahGenerateReflectionPrompt, selahMatchAudio.
//
// Deploy: firebase deploy --only functions:selahStoryProxy,functions:createSelahStory,functions:deleteSelahStory,functions:selahRecognizeVerse,functions:selahGenerateReflectionPrompt,functions:selahMatchAudio
// ============================================================================
const selahStoryProxyFns = require('./src/selahStories/selahStoryProxy');
exports.selahStoryProxy = selahStoryProxyFns.selahStoryProxy;
exports.selahRecognizeVerse = selahStoryProxyFns.selahRecognizeVerse;
exports.selahGenerateReflectionPrompt = selahStoryProxyFns.selahGenerateReflectionPrompt;
exports.selahMatchAudio = selahStoryProxyFns.selahMatchAudio;
exports.createSelahStory = selahStoryProxyFns.createSelahStory;
exports.deleteSelahStory = selahStoryProxyFns.deleteSelahStory;
