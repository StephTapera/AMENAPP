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
  expire2FASessions,
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
exports.expire2FASessions = expire2FASessions;

// P0: Scheduled cleanup for expired 2FA sessions (hourly, guaranteed TTL enforcement)
const { cleanupExpired2FASessions } = require("./cleanupExpired2FASessions");
exports.cleanupExpired2FASessions = cleanupExpired2FASessions;

// Post + Comment pipeline
exports.finalizePostPublish  = finalizePostPublish;
exports.addComment           = addComment;
exports.toggleReaction       = toggleReaction;
exports.onMediaFinalize      = onMediaFinalize;
exports.onPostCreateValidate = onPostCreateValidate;

// ============================================================================
// TRUST SCORE — E2EE messaging safety layer
// ============================================================================
const {
  onTrustScoreRequested,
  onMessageSafetyEvent,
  scheduledTrustScoreRefresh,
} = require("./trustScore");
exports.onTrustScoreRequested      = onTrustScoreRequested;
exports.onMessageSafetyEvent       = onMessageSafetyEvent;
exports.scheduledTrustScoreRefresh = scheduledTrustScoreRefresh;

// ============================================================================
// PHASE 2: SAFE MESSAGING — Pre-send safety gateway, trust scores, notification grouping
// ============================================================================

// Safe Messaging Gateway: Pre-send content moderation
const { safeMessageGateway } = require("./safeMessagingGateway");
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

// Username → email resolver (used by SignInView for username-based login)
// Secure: email never stored in public Firestore; Admin SDK resolves uid → email server-side.
// Falls back to users collection query if usernameLookup doc is missing, and backfills it.
exports.resolveUsernameToEmail = authenticationHelpers.resolveUsernameToEmail;

// One-time backfill: populates usernameLookup for accounts pre-dating the index.
exports.backfillUsernameLookup = authenticationHelpers.backfillUsernameLookup;

// P0-3: Account Deletion Cascade
exports.onUserDeleted = authenticationHelpers.onUserDeleted;
exports.manualCascadeDelete = authenticationHelpers.manualCascadeDelete;

// P0-2: Server-set ageTier — fires on user document creation, computes tier from birthYear.
exports.onUserDocCreated = authenticationHelpers.onUserDocCreated;

// M-02: Update birthYear with server-side age-downgrade protection (adults cannot re-declare as minors).
exports.updateBirthYear = authenticationHelpers.updateBirthYear;

// H-03: Ban evasion prevention — admin-only callable that hashes + records a banned phone number.
// Wire into the accountSuspension flow to auto-ban phone on user ban.
exports.banUserPhone = authenticationHelpers.banUserPhone;

// P0: Account deletion pipeline (processes deletionRequests/{userId} — cascades
// Storage, RTDB, Firestore, and Auth deletion. Created when user taps Delete Account.)
const { processAccountDeletion } = require("./accountDeletion");
exports.processAccountDeletion = processAccountDeletion;

// ============================================================================
// USER ACTIVITY & FCM TOKEN LIFECYCLE
// onUserActivity     — callable: rate-limited lastActiveAt stamp (skip if <5 min)
// onFcmTokenRefresh  — callable: saves token + timezoneOffset, keeps 5 most recent
// onPostActivity     — trigger: stamp lastActiveAt on post creation
// onPrayerActivity   — trigger: stamp lastActiveAt on prayer creation
// onTestimonyActivity— trigger: stamp lastActiveAt + prayer arc hook on testimony link
// ============================================================================
const userActivity = require("./userActivityFunctions");
exports.onUserActivity      = userActivity.onUserActivity;
exports.onFcmTokenRefresh   = userActivity.onFcmTokenRefresh;
exports.onPostActivity      = userActivity.onPostActivity;
exports.onPrayerActivity    = userActivity.onPrayerActivity;
exports.onTestimonyActivity = userActivity.onTestimonyActivity;

// ============================================================================
// PRAYER ARC — testimony ↔ prayer link notifications + Berean insight pill
// onTestimonyLinked: FCM to intercessors when testimony links a prayer (once, idempotent)
// generateArcInsight: Claude haiku phrase cached in posts/{id}.bereanArcInsight
// ============================================================================
const prayerArc = require("./prayerArcFunctions");
exports.onTestimonyLinked  = prayerArc.onTestimonyLinked;
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
exports.bereanGenericProxy = berean.bereanGenericProxy;
// exports.bereanChatProxy = berean.bereanChatProxy; // DISABLED: Using TypeScript version from Backend/functions
exports.deleteAccount = berean.deleteAccount;

// ============================================================================
// GENKIT-STYLE AI FLOWS — daily verse, notification text, digest
// Replaces the external Genkit Cloud Run service (never deployed).
// DailyVerseGenkitService and NotificationGenkitService call these instead.
// ============================================================================
const genkit = require("./genkitFunctions");

// generateDailyVerse is now owned by the Backend/functions (creator codebase) — removed to prevent duplicate function conflict
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
exports.onJobListingCreated     = onJobListingCreated;
exports.reportJobListing        = reportJobListing;

// ============================================================================
// CREATOR STUDIO
// ============================================================================
exports.onCommissionRequestCreated = onCommissionRequestCreated;
exports.onCommissionStatusUpdated  = onCommissionStatusUpdated;
exports.onBookingRequestCreated    = onBookingRequestCreated;
exports.onBookingStatusUpdated     = onBookingStatusUpdated;
exports.onInquiryCreated           = onInquiryCreated;
exports.reportStudioContent        = reportStudioContent;
exports.monthlyEarningsRollup      = monthlyEarningsRollup;

// ============================================================================
// CALENDAR & EVENTS
// ============================================================================
exports.onEventRSVPCreated  = onEventRSVPCreated;
exports.onEventRSVPUpdated  = onEventRSVPUpdated;
exports.sendEventReminders  = sendEventReminders;
exports.sendPostEventFollowUp = sendPostEventFollowUp;

// ============================================================================
// TRANSLATION — Google Cloud Translation API v3
// ============================================================================
const {translateText} = require("./translationFunctions");
exports.translateText = translateText;

// ============================================================================
// SCHEDULED POSTS — publishes pending posts every 5 minutes
// ============================================================================
const {executeScheduledPosts} = require("./scheduledPostsFunctions");
exports.executeScheduledPosts = executeScheduledPosts;

// ============================================================================
// GDPR DATA EXPORT — "Download My Data" callable
// ============================================================================
const {exportUserData} = require("./dataExport");
exports.exportUserData = exportUserData;

// ============================================================================
// STRIPE CONNECT — Creator Studio payments
// ============================================================================
const stripe = require("./stripeFunctions");
exports.stripeCreateConnectedAccount = stripe.stripeCreateConnectedAccount;
exports.stripeGetAccountStatus       = stripe.stripeGetAccountStatus;
exports.stripeCreatePaymentIntent    = stripe.stripeCreatePaymentIntent;
exports.stripeRequestPayout          = stripe.stripeRequestPayout;

const { stripeWebhook } = require("./stripeWebhook");
exports.stripeWebhook = stripeWebhook;

// ============================================================================
// ML CONTENT PIPELINE — Post ML analysis, virality, deletion cleanup
// ============================================================================
const mlContent = require("./mlContentPipeline");
exports.onPostCreatedML          = mlContent.onPostCreatedML;
exports.onPostDeletedML          = mlContent.onPostDeletedML;
exports.computeViralityScore     = mlContent.computeViralityScore;

// ============================================================================
// ML USER INTELLIGENCE — Interest graph, fatigue, creation nudge, session intent
// ============================================================================
const mlUser = require("./mlUserIntelligence");
exports.buildPassiveInterestGraph   = mlUser.buildPassiveInterestGraph;
exports.detectSocialFatigue         = mlUser.detectSocialFatigue;
exports.predictCreationPropensity   = mlUser.predictCreationPropensity;
exports.computeSessionIntent        = mlUser.computeSessionIntent;
exports.updateSpiritualHealthScore  = mlUser.updateSpiritualHealthScore;

// ============================================================================
// ML PRAYER INTELLIGENCE — Intercessor matching, testimony linking, gifts, verse
// ============================================================================
const mlPrayer = require("./mlPrayerIntelligence");
exports.matchIntercessors               = mlPrayer.matchIntercessors;
exports.detectTestimonyOutcome           = mlPrayer.detectTestimonyOutcome;
exports.detectSpiritualGift              = mlPrayer.detectSpiritualGift;
exports.computeScriptureSentimentMatch   = mlPrayer.computeScriptureSentimentMatch;
exports.generatePersonalVerseEngine      = mlPrayer.generatePersonalVerseEngine;

// ============================================================================
// ML COMMUNITY INTELLIGENCE — Health reports, coordinated behavior, safety
// ============================================================================
const mlCommunity = require("./mlCommunityIntelligence");
exports.generateCongregationHealthReport = mlCommunity.generateCongregationHealthReport;
exports.detectCoordinatedBehavior        = mlCommunity.detectCoordinatedBehavior;
exports.runLinguisticFingerprint         = mlCommunity.runLinguisticFingerprint;
exports.detectGriefCrisisPreIncident     = mlCommunity.detectGriefCrisisPreIncident;
exports.runZeroHarassmentDetection       = mlCommunity.runZeroHarassmentDetection;
exports.scoreTheologicalDrift            = mlCommunity.scoreTheologicalDrift;

// ============================================================================
// ML NOTIFICATION & INFRASTRUCTURE — Feed re-rank, SLO, cost audit, churn
// ============================================================================
const mlNotif = require("./mlNotificationIntelligence");
exports.predictNotificationChurn  = mlNotif.predictNotificationChurn;
exports.reRankFeedRealTime        = mlNotif.reRankFeedRealTime;
exports.runSLOAnomalyDetection    = mlNotif.runSLOAnomalyDetection;
exports.costOptimizationAudit     = mlNotif.costOptimizationAudit;
exports.runAgeSignalDetection     = mlNotif.runAgeSignalDetection;

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
exports.onPrayerAmen       = onPrayerAmen;
exports.onPrayerComment    = onPrayerComment;
exports.onPostMention      = onPostMention;
exports.weeklyCheckin      = weeklyCheckin;
exports.communityDigest    = communityDigest;
exports.bereanDailyInsight = bereanDailyInsight;

// ============================================================================
// MESSAGES FEATURES — Prayer Chain, Time Capsule, Accountability, Grace Drop,
//                     Cold Thread Revival, Prayer Room
// ============================================================================
const msgFeatures = require('./messages_features');
exports.onPrayerChainUpdated              = msgFeatures.onPrayerChainUpdated;
exports.processTimeCapsules               = msgFeatures.processTimeCapsules;
exports.sendWeeklyAccountabilityCheckIn   = msgFeatures.sendWeeklyAccountabilityCheckIn;
exports.revealGraceDropIdentity           = msgFeatures.revealGraceDropIdentity;
exports.analyzeThreadsForRevival          = msgFeatures.analyzeThreadsForRevival;
exports.notifyPrayerRoomAnswered          = msgFeatures.notifyPrayerRoomAnswered;

// Algolia sync handled by installed Firestore extension (ext-firestore-algolia-search)

// ============================================================================
// FELLOWSHIP MATCHER — Claude-powered spiritual theme matching
// ============================================================================
exports.fellowshipMatcher           = fellowshipMatcher;
exports.onNewPrayerFellowshipCheck  = onNewPrayerFellowshipCheck;

// ============================================================================
// OPENAI PROXIES — All OpenAI API calls go through these Cloud Functions.
// Client Swift code must NEVER call api.openai.com directly.
// The OPENAI_API_KEY lives only in Firebase Secret Manager (never on-device).
// Run: firebase functions:secrets:set OPENAI_API_KEY
// NOTE: openAIProxy and whisperProxy now use TypeScript versions from Backend/functions
// ============================================================================
const openAIFunctions = require("./openAIFunctions");
// exports.openAIProxy           = openAIFunctions.openAIProxy; // DISABLED: Using TypeScript version from Backend/functions
// exports.whisperProxy          = openAIFunctions.whisperProxy; // DISABLED: Using TypeScript version from Backend/functions
exports.transcribeAudio       = openAIFunctions.transcribeAudio;
exports.smartSuggestionsProxy = openAIFunctions.smartSuggestionsProxy;


// ============================================================================
// CHURCH ENHANCEMENTS — Sunday vibe, DNA scores, prayer momentum, visit guide
// ============================================================================
const churchEnhancements = require("./churchEnhancementFunctions");
exports.generateChurchVibe        = churchEnhancements.generateChurchVibe;
exports.computeChurchDNA          = churchEnhancements.computeChurchDNA;
exports.computePrayerMomentum     = churchEnhancements.computePrayerMomentum;
exports.generateFirstVisitGuide   = churchEnhancements.generateFirstVisitGuide;
exports.inferUserLearningStyle    = churchEnhancements.inferUserLearningStyle;
exports.inferPastorStyle          = churchEnhancements.inferPastorStyle;

// ============================================================================
// BEREAN FEATURE FUNCTIONS — semantic search, spiritual timeline, study guide
// ============================================================================
const bereanFeatures = require("./bereanFeatureFunctions");
exports.bereanEmbedProxy          = bereanFeatures.bereanEmbedProxy;
exports.generateSpiritualTimeline = bereanFeatures.generateSpiritualTimeline;
exports.generateStudyGuide        = bereanFeatures.generateStudyGuide;

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
exports.friendReturned       = engagementNotifs.friendReturned;
exports.gentleReengagement   = engagementNotifs.gentleReengagement;
exports.onNewChurchMember    = engagementNotifs.onNewChurchMember;
exports.prayerCheckin        = engagementNotifs.prayerCheckin;

// ============================================================================
// PROFILE PROPAGATION — syncs denormalized author fields on posts/comments
// when a user changes their displayName, username, or profileImageURL.
// ============================================================================
const {onUserProfileUpdated} = require("./profilePropagation");
exports.onUserProfileUpdated = onUserProfileUpdated;

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
exports.submitHeyFeedNLRequest    = submitHeyFeedNLRequest;
exports.removeHeyFeedNLPreference = removeHeyFeedNLPreference;
exports.resetHeyFeedNLPreferences = resetHeyFeedNLPreferences;
exports.parseHeyFeedIntent        = parseHeyFeedIntent;
exports.expireHeyFeedNLPreferences = expireHeyFeedNLPreferences;
exports.rebuildFeedControlState   = rebuildFeedControlState;

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

exports.generateScenePlan          = generateScenePlan;
exports.refineScenePlan            = refineScenePlan;
exports.runCreationSafetyCheck     = runCreationSafetyCheck;
exports.applyTemplateToAssets      = applyTemplateToAssets;
exports.generateCaptionSuggestions = generateCaptionSuggestions;
exports.saveCreationDraft          = saveCreationDraft;
exports.trackTemplateUsage         = trackTemplateUsage;

// Scheduled post publisher
const { publishScheduledPosts } = require('./scheduledPostPublisher');
exports.publishScheduledPosts = publishScheduledPosts;

// ============================================================================
// ACTION THREADS — Support workflows attached to posts (System 8)
//   onActionThreadCreated          — trigger: validate thread, record trust event
//   onActionStepCompleted          — trigger: notify participants on step completion
//   processActionThreadReminders   — scheduled hourly: send step reminders
//   cleanupExpiredActionThreads    — scheduled daily 4 AM: expire stale threads
// ============================================================================
const actionThreads = require("./actionThreadFunctions");
exports.onActionThreadCreated        = actionThreads.onActionThreadCreated;
exports.onActionStepCompleted        = actionThreads.onActionStepCompleted;
exports.processActionThreadReminders = actionThreads.processActionThreadReminders;
exports.cleanupExpiredActionThreads  = actionThreads.cleanupExpiredActionThreads;

// Topic Enrichment (System 11) — server-side fallback for post topic tagging
const topicEnrichment = require("./topicEnrichment");
exports.enrichPostTopics = topicEnrichment.enrichPostTopics;

// Media State Cleanup (System 12) — daily cleanup of expired resume positions
const mediaCleanup = require("./mediaStateCleanup");
exports.cleanupMediaResumeState = mediaCleanup.cleanupMediaResumeState;

// ============================================================================
// SPIRITUAL OS — 9 callable functions for all 8 surfaces
//   getSpiritualDigest       — AI-personalized daily digest
//   getHubItems              — paginated unified inbox stream
//   getPlannerEvents         — merged planner calendar + optional Berean suggestions
//   getPlannerSuggestions    — AI formation nudges (max 5/day CF-enforced)
//   getAssistantResponse     — Berean assistant bar Q&A (text/voice/vision)
//   updateContextState       — context engine server sync (privacy: CF-write-only)
//   dismissSuggestion        — user dismisses a planner/suggestion nudge
//   pinHubItem               — user pins/unpins a hub item
//   cleanupContextOnLogout   — wipe context doc on logout
// All: enforceAppCheck: true, Auth required, UID-scoped, rate-limited
// ============================================================================
const spiritualOS = require("./spiritualOSFunctions");
exports.getSpiritualDigest     = spiritualOS.getSpiritualDigest;
exports.getHubItems            = spiritualOS.getHubItems;
exports.getPlannerEvents       = spiritualOS.getPlannerEvents;
exports.getPlannerSuggestions  = spiritualOS.getPlannerSuggestions;
exports.getAssistantResponse   = spiritualOS.getAssistantResponse;
exports.updateContextState     = spiritualOS.updateContextState;
exports.dismissSuggestion      = spiritualOS.dismissSuggestion;
exports.pinHubItem             = spiritualOS.pinHubItem;
exports.cleanupContextOnLogout = spiritualOS.cleanupContextOnLogout;

// ============================================================================
// NVIDIA NEMOGUARD POST MODERATION — Firestore trigger on posts/{postId}
// Sets posts.visible + posts.moderation; queues non-approved to moderationQueue.
// Secret: firebase functions:secrets:set NVIDIA_API_KEY --project amen-5e359
// Deploy: firebase deploy --only functions:moderatePost --project amen-5e359
// ============================================================================
const { moderatePost, adminReviewPost } = require("./moderatePost");
exports.moderatePost   = moderatePost;
exports.adminReviewPost = adminReviewPost;

const { moderateSanctuaryMessage, moderatePrayerRequest, moderateDMMessage } = require("./moderateUGC");
exports.moderateSanctuaryMessage = moderateSanctuaryMessage;
exports.moderatePrayerRequest    = moderatePrayerRequest;
exports.moderateDMMessage        = moderateDMMessage;

// ============================================================================
// AMEN SPACES — Monetization, Events, Live, AI Catch-up, Safety, Stripe
//   Spaces Monetization (spacesFunctions.js):
//     createSpaceTier, getSpaceEntitlement, processSubscription,
//     processRefund, getPayoutSummary, hostKYCOnboarding
//   Spaces Events (spacesEventsFunctions.js):
//     createSpaceEvent, rsvpToEvent, sendEventBroadcast, listUpcomingEvents
//   Spaces Live (spacesLiveFunctions.js):
//     createLiveRoom, joinLiveRoom, endLiveRoom, raiseHand, muteParticipant
//   Spaces AI (spacesAIFunctions.js):
//     generateRecap, searchTranscripts, generateClip, studyCompanionQuery
//   Spaces Safety (spacesSafetyFunctions.js):
//     scanMessageForScam, verifyHost, submitModerationAction, reviewJoinRequest
//   Spaces Stripe (spacesStripeFunctions.js):
//     createStripeConnectAccount
// Deploy: firebase deploy --only functions:createSpaceTier,...
// ============================================================================

const spacesMonetization = require("./spacesFunctions");
exports.createSpaceTier        = spacesMonetization.createSpaceTier;
exports.getSpaceEntitlement    = spacesMonetization.getSpaceEntitlement;
exports.processSubscription    = spacesMonetization.processSubscription;
exports.processRefund          = spacesMonetization.processRefund;
exports.getPayoutSummary       = spacesMonetization.getPayoutSummary;
exports.hostKYCOnboarding      = spacesMonetization.hostKYCOnboarding;

const covenantFunctions = require("./covenantFunctions");
exports.createCovenantCheckoutSession = covenantFunctions.createCovenantCheckoutSession;
exports.verifyCovenantMembership      = covenantFunctions.verifyCovenantMembership;

const spacesEvents = require("./spacesEventsFunctions");
exports.createSpaceEvent       = spacesEvents.createSpaceEvent;
exports.rsvpToEvent            = spacesEvents.rsvpToEvent;
exports.sendEventBroadcast     = spacesEvents.sendEventBroadcast;
exports.listUpcomingEvents     = spacesEvents.listUpcomingEvents;

const spacesLive = require("./spacesLiveFunctions");
exports.createLiveRoom         = spacesLive.createLiveRoom;
exports.joinLiveRoom           = spacesLive.joinLiveRoom;
exports.endLiveRoom            = spacesLive.endLiveRoom;
exports.raiseHand              = spacesLive.raiseHand;
exports.muteParticipant        = spacesLive.muteParticipant;

const spacesAI = require("./spacesAIFunctions");
exports.generateRecap          = spacesAI.generateRecap;
exports.searchTranscripts      = spacesAI.searchTranscripts;
exports.generateClip           = spacesAI.generateClip;
exports.studyCompanionQuery    = spacesAI.studyCompanionQuery;

const spacesSafety = require("./spacesSafetyFunctions");
exports.scanMessageForScam         = spacesSafety.scanMessageForScam;
exports.verifyHost                 = spacesSafety.verifyHost;
exports.submitModerationAction     = spacesSafety.submitModerationAction;
exports.reviewJoinRequest          = spacesSafety.reviewJoinRequest;

const spacesStripe = require("./spacesStripeFunctions");
exports.createStripeConnectAccount = spacesStripe.createStripeConnectAccount;

const spacesLivekit = require("./spacesLivekitFunctions");
exports.getLivekitToken = spacesLivekit.getLivekitToken;

// ============================================================================
// CHURCH NOTES MEDIA PIPELINE
//   churchNotesMediaPipeline.js:
//     createChurchNoteProcessingJob, processChurchNoteAudio,
//     processChurchNoteImageOCR, processChurchNoteVideo,
//     processChurchNoteDocumentPDF
// ============================================================================

const churchNotesMedia = require("./churchNotesMediaPipeline");
exports.createChurchNoteProcessingJob = churchNotesMedia.createChurchNoteProcessingJob;
exports.processChurchNoteAudio        = churchNotesMedia.processChurchNoteAudio;
exports.processChurchNoteImageOCR     = churchNotesMedia.processChurchNoteImageOCR;
exports.processChurchNoteVideo        = churchNotesMedia.processChurchNoteVideo;
exports.processChurchNoteDocumentPDF  = churchNotesMedia.processChurchNoteDocumentPDF;

// ============================================================================
// CHURCH NOTES AI CALLABLES
//   churchNotesAICallables.js:
//     generateChurchNoteSummary, generateChurchNoteStudyGuide,
//     generateChurchNotePrayerPrompts, generateChurchNoteActionItems,
//     detectChurchNoteScriptures, translateChurchNoteContent,
//     regenerateChurchNoteSection, createChurchNoteClipSuggestions,
//     approveChurchNoteAIDraft, rejectChurchNoteAIDraft,
//     shareChurchNoteWithCollaborators, updateChurchNotePermissions
// ============================================================================

const churchNotesAI = require("./churchNotesAICallables");
exports.generateChurchNoteSummary         = churchNotesAI.generateChurchNoteSummary;
exports.generateChurchNoteStudyGuide      = churchNotesAI.generateChurchNoteStudyGuide;
exports.generateChurchNotePrayerPrompts   = churchNotesAI.generateChurchNotePrayerPrompts;
exports.generateChurchNoteActionItems     = churchNotesAI.generateChurchNoteActionItems;
exports.detectChurchNoteScriptures        = churchNotesAI.detectChurchNoteScriptures;
exports.translateChurchNoteContent        = churchNotesAI.translateChurchNoteContent;
exports.regenerateChurchNoteSection       = churchNotesAI.regenerateChurchNoteSection;
exports.createChurchNoteClipSuggestions   = churchNotesAI.createChurchNoteClipSuggestions;
exports.approveChurchNoteAIDraft          = churchNotesAI.approveChurchNoteAIDraft;
exports.rejectChurchNoteAIDraft           = churchNotesAI.rejectChurchNoteAIDraft;
exports.shareChurchNoteWithCollaborators  = churchNotesAI.shareChurchNoteWithCollaborators;
exports.updateChurchNotePermissions       = churchNotesAI.updateChurchNotePermissions;

// ============================================================================
// VOICE PRAYER & TESTIMONY COMMENTS
//   voicePrayer.js:
//     createVoicePrayerUploadSession, finalizeVoicePrayerComment,
//     reactToVoicePrayerComment, deleteVoicePrayerComment,
//     reportVoicePrayerComment, getVoicePrayerPlaybackURL
// ============================================================================

const voicePrayer = require("./voicePrayer");
exports.createVoicePrayerUploadSession = voicePrayer.createVoicePrayerUploadSession;
exports.finalizeVoicePrayerComment     = voicePrayer.finalizeVoicePrayerComment;
exports.reactToVoicePrayerComment      = voicePrayer.reactToVoicePrayerComment;
exports.deleteVoicePrayerComment       = voicePrayer.deleteVoicePrayerComment;
exports.reportVoicePrayerComment       = voicePrayer.reportVoicePrayerComment;
exports.getVoicePrayerPlaybackURL      = voicePrayer.getVoicePrayerPlaybackURL;

// ============================================================================
// CONTENT OS (System 33: Content Discussion, Approval & Forwarding)
//   contentOSFunctions.js:
//     routeContentAction
// ============================================================================

const { routeContentAction } = require("./contentOSFunctions");
exports.routeContentAction = routeContentAction;

// ============================================================================
// ONE — Private Social OS Callables
//   one_sendMoment         — send/relay moment with ConsentDNA enforcement
//   one_expireMoment       — decay moment (skips if evidenceLocked)
//   one_reportMoment       — evidence lock + moderation queue (invariant: lock first)
//   one_requestWitness     — request witness relationship with season label
//   one_relayMoment        — relay with reach budget + chain depth enforcement
//   one_activateRepairFlow — initiate repair flow between two participants
//   one_acceptRepairFlow   — accept repair flow; activates when both accepted
//   one_verifyEntitlement  — read StoreKit entitlement tier from Firestore
//   one_activateLegacy     — trustee-only: activate legacy directive + enqueue bequests
// All: enforceAppCheck: true, Auth required, UID-scoped
// Deploy: firebase deploy --only functions:one_sendMoment,one_expireMoment,
//           one_reportMoment,one_requestWitness,one_relayMoment,
//           one_activateRepairFlow,one_acceptRepairFlow,
//           one_verifyEntitlement,one_activateLegacy
// PREREQUISITE: Firebase console App Check "debug" → "enforce" before external users.
// ============================================================================

const oneFunctions = require("./oneFunctions");
exports.one_sendMoment           = oneFunctions.one_sendMoment;
exports.one_expireMoment         = oneFunctions.one_expireMoment;
exports.one_reportMoment         = oneFunctions.one_reportMoment;
exports.one_requestWitness       = oneFunctions.one_requestWitness;
exports.one_relayMoment          = oneFunctions.one_relayMoment;
exports.one_activateRepairFlow   = oneFunctions.one_activateRepairFlow;
exports.one_acceptRepairFlow     = oneFunctions.one_acceptRepairFlow;
exports.one_verifyEntitlement    = oneFunctions.one_verifyEntitlement;
exports.one_activateLegacy       = oneFunctions.one_activateLegacy;

// ============================================================================
// MESSAGING INTELLIGENCE — AI-powered in-conversation capabilities
//   generateMessageCatchUp          — summarise recent messages (up to 100)
//   generateThreadSummary           — thread summary with topics/prayers/questions
//   detectMessagingSmartPills       — contextual action pills from message text
//   translateMessage                — NIM translation preserving theological nuance
//   detectMessageSafetyNudge        — NeMo Guard safety check on message text
//   generateVoiceMessageSummary     — summarise a voice-message transcript
//   detectMessageCrossSurfaceActions — detect berean/church_notes/selah/etc. actions
// Secret: NVIDIA_API_KEY (already set for moderatePost)
// Deploy: firebase deploy --only functions:generateMessageCatchUp,
//           generateThreadSummary,detectMessagingSmartPills,translateMessage,
//           detectMessageSafetyNudge,generateVoiceMessageSummary,
//           detectMessageCrossSurfaceActions --project amen-5e359
// ============================================================================

const messagingIntelligence = require("./messagingIntelligenceFunctions");
exports.generateMessageCatchUp           = messagingIntelligence.generateMessageCatchUp;
exports.generateThreadSummary            = messagingIntelligence.generateThreadSummary;
exports.detectMessagingSmartPills        = messagingIntelligence.detectMessagingSmartPills;
exports.translateMessage                 = messagingIntelligence.translateMessage;
exports.detectMessageSafetyNudge         = messagingIntelligence.detectMessageSafetyNudge;
exports.generateVoiceMessageSummary      = messagingIntelligence.generateVoiceMessageSummary;
exports.detectMessageCrossSurfaceActions = messagingIntelligence.detectMessageCrossSurfaceActions;

// ============================================================================
// DISCUSSION SYSTEM V1 — Structured threads, Pre-Post Threshold, Ask Berean
//   askBerean            — AI thread summary (mock when BEREAN_LLM_KEY unset)
//   detectDuplicate      — cosine-similarity duplicate check (mock when EMBEDDING_KEY unset)
//   computeReputation    — points aggregation + badge tier
//   postComment          — write comment after threshold passes
//   markHelpful          — idempotent helpful-mark + reputation event
//   updateWatchProgress  — upsert watch-progress doc
//   getWatchProgress     — read watch-progress + shouldNudge flag
// Deploy: firebase deploy --only functions:askBerean,detectDuplicate,
//           computeReputation,postComment,markHelpful,
//           updateWatchProgress,getWatchProgress --project amen-5e359
// ============================================================================

const discussion = require("./discussionFunctions");
exports.askBerean           = discussion.askBerean;
exports.detectDuplicate     = discussion.detectDuplicate;
exports.computeReputation   = discussion.computeReputation;
exports.postComment         = discussion.postComment;
exports.markHelpful         = discussion.markHelpful;
exports.updateWatchProgress = discussion.updateWatchProgress;
exports.getWatchProgress    = discussion.getWatchProgress;

// ============================================================================
// APPEALS SYSTEM — User-facing content appeal pipeline (C-04)
//   submitAppeal   — callable: user submits appeal for removed/held post or prayer
//   reviewAppeal   — callable (admin): approve or reject a pending appeal
// Writes to: appeals/{appealId}, moderationQueue (status:"appeal"), moderationAuditLog
// Deploy: firebase deploy --only functions:submitAppeal,reviewAppeal --project amen-5e359
// ============================================================================
const appeals = require("./appeals");
exports.submitAppeal = appeals.submitAppeal;
exports.reviewAppeal = appeals.reviewAppeal;

// ============================================================================
// NCMEC CYBERTIPLINE — mandatory CSAM reporting pipeline (18 U.S.C. § 2258A)
//   onCSAMDetected: Firestore trigger on ncmecSubmissionQueue/{entryId}
//     -> FCM alert to all admin users + moderatorAlerts write
//   fileNCMECReport: internal helper called by imageModeration.js on confirmed blocks
// Deploy: firebase deploy --only functions:onCSAMDetected --project amen-5e359
// ============================================================================
const ncmecReporter = require("./ncmecReporter");
exports.onCSAMDetected = ncmecReporter.onCSAMDetected;

// ============================================================================
// AI SAFETY REPORTS — User-facing report pipeline for unsafe AI responses (C-04)
//   reportUnsafeAIResponse — callable: submit a report for a harmful AI response
// Writes to: aiReports/{reportId}
// Deploy: firebase deploy --only functions:reportUnsafeAIResponse --project amen-5e359
// ============================================================================
const { reportUnsafeAIResponse } = require('./reportAIFunctions');
exports.reportUnsafeAIResponse = reportUnsafeAIResponse;
