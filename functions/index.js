/**
 * Firebase Cloud Functions for AMEN App
 * Compatible with Firebase Functions v7 (2nd generation)
 * Handles notifications, follows, and push notifications
 */

const admin = require("firebase-admin");
// v2 triggers (onRealtimeCommentCreate, onMessageSent, sendDailyNotificationDigest)
// are defined in v2functions.js — do NOT import v2 SDKs here, as the Firebase CLI
// applies v2 CPU/concurrency settings to every function in a file that imports them.

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
  spotifyTokenProxy,
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

// Shabbat Mode middleware is used within individual function modules (e.g. pushNotifications.js).
// v2functions.js imports it directly for the merged comment/reply trigger.

// Server-side rate limiter is used within individual function modules.
// Direct usage here was removed with the gen-1 duplicate triggers.

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

// Amen Action Intelligence: commitment economy callable workflows
const actionIntelligence = require("./actionIntelligenceFunctions");

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
exports.resolveMusicAttachment = resolveMusicAttachment;
exports.spotifyTokenProxy = spotifyTokenProxy;

// AI Personalization: Export ML-powered functions
exports.generatePersonalizedFeed = generatePersonalizedFeed;
exports.filterSmartNotifications = filterSmartNotifications;
exports.exportEngagementData = exportEngagementData;

// Content Moderation: Export organic content integrity system
exports.moderateContent = moderateContent;

// Server-side post moderation (Firestore onWrite trigger — v2, separate file to avoid gen1/gen2 conflict)
const {serverSidePostModeration} = require("./contentModerationTriggers");
exports.serverSidePostModeration = serverSidePostModeration;

// Image Moderation: Export Cloud Vision SafeSearch moderation
exports.moderateUploadedImage = moderateUploadedImage;

// P0: Phone Authentication Rate Limiting
exports.checkPhoneVerificationRateLimit = checkPhoneVerificationRateLimit;
exports.reportPhoneVerificationFailure = reportPhoneVerificationFailure;
exports.unblockPhoneNumber = unblockPhoneNumber;

// P0: Two-Factor Authentication
// exports.request2FAOTP = request2FAOTP; // DISABLED: TypeScript version in creator codebase
// exports.verify2FAOTP = verify2FAOTP;   // DISABLED: TypeScript version in creator codebase
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

// Comment Quality + Safety Gateway
const { checkCommentQuality, rewriteCommentTone } = require('./commentGateway');
exports.checkCommentQuality  = checkCommentQuality;
exports.rewriteCommentTone   = rewriteCommentTone;

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
// AMEN AI ROUTER — centralized callModel wrappers (gen2)
// All provider selection lives in functions/router/amenRouting.config.js.
// Feature code must NOT hardcode provider names or API URLs.
// ============================================================================
const {
  callModelTest,
  callModelBerean,
  callModelCommentCoach,
  callModelDailyBrief,
  callModelSearch,
} = require("./routerCallable");
exports.callModelTest         = callModelTest;
exports.callModelBerean       = callModelBerean;
exports.callModelCommentCoach = callModelCommentCoach;
exports.callModelDailyBrief   = callModelDailyBrief;
exports.callModelSearch       = callModelSearch;

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

// NOTE: onRealtimeCommentCreate, onRealtimeReplyCreate, onMessageSent, and
// sendDailyNotificationDigest are defined in v2functions.js (gen-2 triggers).
// They are intentionally NOT re-exported here to prevent double-invocation.

// ============================================================================
// AI MODERATION, CRISIS DETECTION & SMART NOTIFICATIONS — starts below.
// (MESSAGE NOTIFICATIONS block moved to v2functions.js)
// ============================================================================

// Temporary placeholder to mark removal boundary — see v2functions.js
// for all three removed gen-1 triggers.
const _v2TriggersMovedToV2Functions = true; // eslint-disable-line no-unused-vars

// ============================================================================
// REALTIME DATABASE: COMMENT NOTIFICATIONS (REMOVED — see v2functions.js)
// The following gen-1 triggers caused double notifications when deployed
// alongside the gen-2 merged handler in v2functions.js:
//   • onRealtimeCommentCreate (top-level only)
//   • onRealtimeReplyCreate   (replies only)
// Both are replaced by the unified gen-2 onRealtimeCommentCreate in v2functions.js
// which handles both comments and replies in a single trigger.
// ============================================================================

// ============================================================================
// AI MODERATION, CRISIS DETECTION & SMART NOTIFICATIONS
// ============================================================================
const aiModeration = require("./aiModeration");

// AI Moderation Firestore trigger (onDocumentCreated — NOT a callable).
// Renamed from moderateContent to avoid shadowing the https.onCall callable
// of the same name exported at line 167 from contentModeration.js.
// C3 fix: duplicate export removed; aiModeration trigger now has a unique name.
exports.moderateContentAI = aiModeration.moderateContent;

// Crisis Detection
// exports.detectCrisis = aiModeration.detectCrisis; // DISABLED: TypeScript version in creator codebase

// Smart Notifications
// exports.deliverBatchedNotifications = aiModeration.deliverBatchedNotifications; // DISABLED: TypeScript version in creator codebase

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
// H-03: Ban evasion prevention — admin-only callable that hashes + records a banned phone number.
// Deployed as v1 functions to work around Cloud Run quota exhaustion.
const authHelpersV1 = require("./authHelpersV1");
exports.updateBirthYear = authHelpersV1.updateBirthYear;
exports.banUserPhone    = authHelpersV1.banUserPhone;

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
exports.bereanChatProxy = berean.bereanChatProxy;
exports.routeBereanContextualAction = berean.routeBereanContextualAction;
exports.deleteAccount = berean.deleteAccount;
// Sermon & seasonal features
exports.bereanSmartReply              = berean.bereanSmartReply;
exports.sermonSnapProxy               = berean.sermonSnapProxy;
exports.bereanSermonWeekPlan          = berean.bereanSermonWeekPlan;
exports.bereanSpiritualGraphAnalysis  = berean.bereanSpiritualGraphAnalysis;
exports.bereanSeasonalPrompt          = berean.bereanSeasonalPrompt;

// ============================================================================
// BEREAN AUDIT LOG — H-13 FIX: server-authoritative audit trail
// writeBereanAuditEntry receives { event, metadata } from iOS client,
// appends userId from request.auth.uid server-side (tamper-proof).
// ============================================================================
const bereanAudit = require("./bereanAuditFunctions");
exports.writeBereanAuditEntry = bereanAudit.writeBereanAuditEntry;

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

// Hardened webhook handler: signature verification, idempotency, entitlement writes,
// audit log. See functions/stripe/stripeWebhook.js for full security posture.
const { stripeWebhook } = require("./stripe/stripeWebhook");
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
// TESTIMONY FEATURES — testimony strength scoring, witness cleanup, and
// SECURITY (H8): NeMo Guard moderation trigger on testimonies/{testimonyId}.
// ============================================================================
const {
  cleanStaleWitnesses,
  updateTestimonyStrength,
  onNeededThisWrite,
  moderateTestimony,
} = require("./testimonyFeatures");
exports.cleanStaleWitnesses      = cleanStaleWitnesses;
exports.updateTestimonyStrength  = updateTestimonyStrength;
exports.onNeededThisWrite        = onNeededThisWrite;
exports.moderateTestimony        = moderateTestimony;

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

exports.createAmenInitiative = actionIntelligence.createAmenInitiative;
exports.assignAmenVolunteer = actionIntelligence.assignAmenVolunteer;
exports.indexAmenMemoryGraph = actionIntelligence.indexAmenMemoryGraph;
exports.recordAmenRelationshipSignal = actionIntelligence.recordAmenRelationshipSignal;
exports.writeAmenKnowledgeGraph = actionIntelligence.writeAmenKnowledgeGraph;
exports.executeAmenAction = actionIntelligence.executeAmenAction;

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
// MODERATION GATEWAY — Unified pre-submit content safety callable
//   checkContentSafety — called from iOS before any content write
//     Covers: posts, comments, messages, DMs
//     Returns: { decision, reason?, crisisEscalated, crisisResources?, decisionId }
//     Self-harm: escalates to crisisEscalations/{uid}/{ts} + shows crisis resources
//     All decisions persisted to moderationDecisions/{decisionId}
//   Secret: NVIDIA_API_KEY (already set for other NeMo Guard CFs)
//   Deploy: firebase deploy --only functions:checkContentSafety --project amen-5e359
// ============================================================================
const { checkContentSafety } = require("./moderationGateway");
exports.checkContentSafety = checkContentSafety;

// ============================================================================
// AIL — Accessibility Intelligence Layer transform callable
//   ailTransform — routes 10 AIL tasks through callModel; fail-OPEN to original
//     (explain_scripture cite-or-refuse, never fabricates); App Check + Auth +
//     rate limit (crisis bypasses); transformCache (DM/crisis never cached).
//   Secrets: ANTHROPIC_API_KEY, NVIDIA_API_KEY, PINECONE_API_KEY, PINECONE_HOST
//   Deploy: Ship Order Stage 3 functions batch (NOT ad-hoc)
// ============================================================================
const { ailTransform } = require("./ail/ailTransform");
exports.ailTransform = ailTransform;

// ============================================================================
// CONTEXT SYSTEM — Universal Migration extractor (Wave 3)
//   extractContextFacets — onCall, enforceAppCheck: true, region us-central1.
//     Input  { text, sourceLabel, sanitizationPassId } → Output { candidates: FacetCandidate[] }.
//     Takes already-C59-sanitized, inert-wrapped import text (DATA, never instructions) and
//     returns structured FacetCandidate[] via the `context_extract` router task (fail_closed —
//     never fabricates, never echoes injection, never emits excluded content). Rejects an empty
//     sanitizationPassId. Writes NOTHING to Firestore — output is ephemeral candidates the user
//     approves client-side. Gen-2 onCall (imports firebase-functions/v2/https), same posture as
//     spiritualOSFunctions. Source: functions/context/extractContextFacets.ts (compiled to .js).
//   Secrets: ANTHROPIC_API_KEY, OPENAI_API_KEY, NVIDIA_API_KEY
//   Deploy: Ship Order Stage 3 functions batch (with the Context System CFs).
// ============================================================================
const { extractContextFacets } = require("./context/extractContextFacets");
exports.extractContextFacets = extractContextFacets;

// Context System — Wave 4 consumers (onCall, App Check, us-central1; Stage-3 deploy batch).
// All read ONLY tier-C facets server-side (CONTRACTS §3 server-read invariant); never tier-P.
const { initializeFeedFromContext } = require("./context/initializeFeedFromContext");
exports.initializeFeedFromContext = initializeFeedFromContext;
const { matchCommunitiesFromContext } = require("./context/matchCommunitiesFromContext");
exports.matchCommunitiesFromContext = matchCommunitiesFromContext;
const { generateIntroduction } = require("./context/generateIntroduction");
exports.generateIntroduction = generateIntroduction;

// Context System — Wave 5 exports (Stage-3 deploy batch, project amen-5e359, us-central1).
// exportAmenFile  : visibility-filtered .amen export; exclusion validator gates every payload.
// signAmenExport  : Ed25519 signature over canonical serialization; secret AMEN_EXPORT_ED25519_PRIVATE_KEY required.
// resolveContextQR: resolves a Context QR token to current public facets (live, never stale).
const { exportAmenFile } = require("./context/exportAmenFile");
exports.exportAmenFile = exportAmenFile;
const { signAmenExport } = require("./context/signAmenExport");
exports.signAmenExport = signAmenExport;
const { resolveContextQR } = require("./context/resolveContextQR");
exports.resolveContextQR = resolveContextQR;

// ============================================================================
// TTS — Text-to-Speech (Google Cloud TTS, no NVIDIA key needed)
// ============================================================================
const { generateSpeech, generatePrayerAudio } = require("./ttsService");
exports.generateSpeech      = generateSpeech;
exports.generatePrayerAudio = generatePrayerAudio;

// ============================================================================
// AI ACTIVITY LOGGING — Unified audit trail for all AI invocations
// ============================================================================
const { getAIUsageSummary } = require("./aiActivityLogger");
exports.getAIUsageSummary = getAIUsageSummary;

// ============================================================================
// FEATURE FLAGS — Server-side flag management (replaces iOS UserDefaults flags)
// ============================================================================
const { getFeatureFlags, updateFeatureFlag } = require("./featureFlagService");
exports.getFeatureFlags   = getFeatureFlags;
exports.updateFeatureFlag = updateFeatureFlag;

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
// exports.createCovenantCheckoutSession = covenantFunctions.createCovenantCheckoutSession; // DISABLED: TypeScript version in creator codebase
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

const connectHub = require("./connectHubFunctions");
exports.getConnectHubFeed = connectHub.getConnectHubFeed;

// ============================================================================
// CHURCH NOTES MEDIA PIPELINE
//   churchNotesMediaPipeline.js:
//     createChurchNoteProcessingJob, processChurchNoteAudio,
//     processChurchNoteImageOCR, processChurchNoteVideo,
//     processChurchNoteDocumentPDF
// ============================================================================

const churchNotesMedia = require("./churchNotesMediaPipeline");
// exports.createChurchNoteProcessingJob = churchNotesMedia.createChurchNoteProcessingJob; // DISABLED: TypeScript version in creator codebase
// exports.processChurchNoteAudio        = churchNotesMedia.processChurchNoteAudio;        // DISABLED: TypeScript version in creator codebase
// exports.processChurchNoteImageOCR     = churchNotesMedia.processChurchNoteImageOCR;     // DISABLED: TypeScript version in creator codebase
// exports.processChurchNoteVideo        = churchNotesMedia.processChurchNoteVideo;        // DISABLED: TypeScript version in creator codebase
exports.processChurchNoteDocumentPDF  = churchNotesMedia.processChurchNoteDocumentPDF;

// ============================================================================
// CHURCH NOTES AI CALLABLES
//   churchNotesAICallables.js:
//     generateChurchNoteDraft (full-pipeline: transcript → structured draft),
//     generateChurchNoteSummary, generateChurchNoteStudyGuide,
//     generateChurchNotePrayerPrompts, generateChurchNoteActionItems,
//     detectChurchNoteScriptures, translateChurchNoteContent,
//     regenerateChurchNoteSection, createChurchNoteClipSuggestions,
//     approveChurchNoteAIDraft, rejectChurchNoteAIDraft,
//     shareChurchNoteWithCollaborators, updateChurchNotePermissions
// ============================================================================

const churchNotesAI = require("./churchNotesAICallables");
exports.generateChurchNoteDraft           = churchNotesAI.generateChurchNoteDraft;
// exports.generateChurchNoteSummary         = churchNotesAI.generateChurchNoteSummary;        // DISABLED: TypeScript version in creator codebase
// exports.generateChurchNoteStudyGuide      = churchNotesAI.generateChurchNoteStudyGuide;     // DISABLED: TypeScript version in creator codebase
// exports.generateChurchNotePrayerPrompts   = churchNotesAI.generateChurchNotePrayerPrompts;  // DISABLED: TypeScript version in creator codebase
// exports.generateChurchNoteActionItems     = churchNotesAI.generateChurchNoteActionItems;    // DISABLED: TypeScript version in creator codebase
// exports.detectChurchNoteScriptures        = churchNotesAI.detectChurchNoteScriptures;       // DISABLED: TypeScript version in creator codebase
// exports.translateChurchNoteContent        = churchNotesAI.translateChurchNoteContent;       // DISABLED: TypeScript version in creator codebase
// exports.regenerateChurchNoteSection       = churchNotesAI.regenerateChurchNoteSection;      // DISABLED: TypeScript version in creator codebase
// exports.createChurchNoteClipSuggestions   = churchNotesAI.createChurchNoteClipSuggestions;  // DISABLED: TypeScript version in creator codebase
// exports.approveChurchNoteAIDraft          = churchNotesAI.approveChurchNoteAIDraft;         // DISABLED: TypeScript version in creator codebase
// exports.rejectChurchNoteAIDraft           = churchNotesAI.rejectChurchNoteAIDraft;          // DISABLED: TypeScript version in creator codebase
// exports.shareChurchNoteWithCollaborators  = churchNotesAI.shareChurchNoteWithCollaborators; // DISABLED: TypeScript version in creator codebase
// exports.updateChurchNotePermissions       = churchNotesAI.updateChurchNotePermissions;      // DISABLED: TypeScript version in creator codebase

// ============================================================================
// VOICE PRAYER & TESTIMONY COMMENTS
//   voicePrayer.js:
//     createVoicePrayerUploadSession, finalizeVoicePrayerComment,
//     reactToVoicePrayerComment, deleteVoicePrayerComment,
//     reportVoicePrayerComment, getVoicePrayerPlaybackURL
// ============================================================================

const voicePrayer = require("./voicePrayer");
// exports.createVoicePrayerUploadSession = voicePrayer.createVoicePrayerUploadSession; // DISABLED: TypeScript version in creator codebase
// exports.finalizeVoicePrayerComment     = voicePrayer.finalizeVoicePrayerComment;     // DISABLED: TypeScript version in creator codebase
// exports.reactToVoicePrayerComment      = voicePrayer.reactToVoicePrayerComment;      // DISABLED: TypeScript version in creator codebase
// exports.deleteVoicePrayerComment       = voicePrayer.deleteVoicePrayerComment;       // DISABLED: TypeScript version in creator codebase
// exports.reportVoicePrayerComment       = voicePrayer.reportVoicePrayerComment;       // DISABLED: TypeScript version in creator codebase
// exports.getVoicePrayerPlaybackURL      = voicePrayer.getVoicePrayerPlaybackURL;      // DISABLED: TypeScript version in creator codebase

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
// exports.generateThreadSummary            = messagingIntelligence.generateThreadSummary; // DISABLED: TypeScript version in creator codebase
exports.detectMessagingSmartPills        = messagingIntelligence.detectMessagingSmartPills;
// exports.translateMessage                 = messagingIntelligence.translateMessage; // DISABLED: TypeScript version in creator codebase
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
exports.askBerean              = discussion.askBerean;
exports.detectDuplicate        = discussion.detectDuplicate;
exports.computeReputation      = discussion.computeReputation;
exports.postComment            = discussion.postComment;
exports.markHelpful            = discussion.markHelpful;
exports.setAccepted            = discussion.setAccepted;
exports.updateWatchProgress    = discussion.updateWatchProgress;
exports.getWatchProgress       = discussion.getWatchProgress;
exports.processEmbeddingQueue  = discussion.processEmbeddingQueue;

// ============================================================================
// APPEALS SYSTEM — User-facing content appeal pipeline (C-04)
//   submitAppeal   — callable: user submits appeal for removed/held post or prayer
//   reviewAppeal   — callable (admin): approve or reject a pending appeal
// Writes to: appeals/{appealId}, moderationQueue (status:"appeal"), moderationAuditLog
// Deploy: firebase deploy --only functions:submitAppeal,reviewAppeal --project amen-5e359
// ============================================================================
const appeals = require("./appeals");
exports.submitAppeal = appeals.submitAppeal;
// reviewAppeal deployed as v1 to work around Cloud Run quota exhaustion.
const { reviewAppeal } = require("./reviewAppealV1");
exports.reviewAppeal = reviewAppeal;

// ============================================================================
// NCMEC CYBERTIPLINE — mandatory CSAM reporting pipeline (18 U.S.C. § 2258A)
//   onCSAMDetected: Firestore trigger on ncmecSubmissionQueue/{entryId}
//     -> FCM alert to all admin users + moderatorAlerts write
//   flagForNCMECReview: callable (trust_safety_admin/admin): manually flag content;
//     deletes Storage media + writes mandatory_reports + alerts trust_safety_admin users
//   onModerationRequiresMandatoryReport: Firestore trigger on moderationResults/{docId};
//     fires when requiresMandatoryReport transitions to true:
//     deletes Storage media + writes mandatory_reports + alerts trust_safety_admin users
//   fileNCMECReport: internal helper called by imageModeration.js on confirmed blocks
// Deploy: firebase deploy --only functions:onCSAMDetected,flagForNCMECReview,onModerationRequiresMandatoryReport --project amen-5e359
// ============================================================================
const ncmecReporter = require("./ncmecReporter");
exports.onCSAMDetected = ncmecReporter.onCSAMDetected;
exports.flagForNCMECReview = ncmecReporter.flagForNCMECReview;
exports.onModerationRequiresMandatoryReport = ncmecReporter.onModerationRequiresMandatoryReport;

// ============================================================================
// MODERATION SWEEP — scheduled every 4h: finds aged moderationQueue items and
// alerts admins. Items pending >24h are flagged; items with CSAM/grooming/
// trafficking categories pending >2h are escalated to criticalReviewQueue.
// M-06: SLA sweep to prevent items from stalling in the moderation queue.
// Deploy: firebase deploy --only functions:moderationSweep --project amen-5e359
// ============================================================================
const { moderationSweep } = require("./moderationSweep");
exports.moderationSweep = moderationSweep;

// ============================================================================
// ADMIN CLAIMS — grantAdminRole, revokeAdminRole, bootstrapFirstAdmin,
//               onUserAdminFlagChanged, auditAdminClaims (L-02)
// Deploy: firebase deploy --only functions:grantAdminRole,revokeAdminRole,
//         bootstrapFirstAdmin,onUserAdminFlagChanged,auditAdminClaims
//         --project amen-5e359
// ============================================================================
const adminClaims = require("./adminClaims");
exports.grantAdminRole         = adminClaims.grantAdminRole;
exports.revokeAdminRole        = adminClaims.revokeAdminRole;
exports.bootstrapFirstAdmin    = adminClaims.bootstrapFirstAdmin;
exports.onUserAdminFlagChanged = adminClaims.onUserAdminFlagChanged;
exports.auditAdminClaims       = adminClaims.auditAdminClaims;

// ============================================================================
// BEREAN REALTIME — H-22: Ephemeral OpenAI Realtime token broker
//                   H-33: SLO check scheduled function + kill switch
//
//   createRealtimeSession — callable: brokers short-lived ephemeral token;
//     iOS client (BereanRealtimeSessionManager.swift) calls this instead of
//     hitting api.openai.com directly. Returns sessionId + clientSecret.
//   bereanSLOCheck — scheduled every 5 minutes: reads bereanMetrics/hourly
//     and writes systemStatus/berean { status: "degraded" } on SLO breach,
//     which RemoteKillSwitch.swift picks up to disable Berean automatically.
//
// Secret required: OPENAI_API_KEY (already set for bereanFunctions.js)
// Deploy: firebase deploy --only functions:createRealtimeSession,bereanSLOCheck
//         --project amen-5e359
// ============================================================================
const bereanRealtime = require("./bereanRealtimeFunctions");
// exports.createRealtimeSession = bereanRealtime.createRealtimeSession; // DISABLED: TypeScript version in creator codebase
exports.bereanSLOCheck        = bereanRealtime.bereanSLOCheck;

// ============================================================================
// PINECONE CLEANUP — One-time cleanup of draft vectors + per-account cleanup
//   cleanupDraftVectors — admin-only callable: deletes vectors with
//     dominantType == "draft" from the user-interest-embeddings namespace.
//     Run once after deploy: firebase functions:call cleanupDraftVectors --data '{}'
//   deleteAccount (bereanFunctions.js) now calls deleteUserPineconeVectors
//     internally on every account deletion (H-18 fix).
//
// Secrets required: PINECONE_API_KEY, PINECONE_HOST
// Deploy: firebase deploy --only functions:cleanupDraftVectors --project amen-5e359
// ============================================================================
const pineconeCleanup = require("./pineconeCleanupFunctions");
exports.cleanupDraftVectors = pineconeCleanup.cleanupDraftVectors;

// ============================================================================
// AMEN AI FEATURES — Daily Digest, Creator Draft Assistant, RAG Search
//
//   getDailyDigest        — callable: 7-point morning card; cached in
//                           dailyDigests/{uid}/dates/{dateKey};
//                           rate limit 5/day per user
//   generateCreatorDraft  — callable: draft-only (never publishes) for
//                           mentors/churches; types: post|devotional|
//                           studyGuide|announcement; rate limit 20/hour
//   ragSearch             — callable: embed → Pinecone vector search across
//                           churchNotes|savedVerses|posts|sermons|all;
//                           multilingual TODO(gate: DECISION); rate limit 30/hour
//
// Secrets required: ANTHROPIC_API_KEY (getDailyDigest, generateCreatorDraft)
//                   OPENAI_API_KEY (ragSearch embedding via mlClients.openaiEmbed)
//                   PINECONE_API_KEY, PINECONE_HOST (ragSearch)
//
// Deploy:
//   firebase deploy --only functions:getDailyDigest,generateCreatorDraft,ragSearch \
//     --project amen-5e359
// ============================================================================
const amenAIFeatures = require("./amenAIFeatures");
exports.getDailyDigest       = amenAIFeatures.getDailyDigest;
exports.generateCreatorDraft = amenAIFeatures.generateCreatorDraft;
exports.ragSearch            = amenAIFeatures.ragSearch;

// ============================================================================
// ADMIN CRISIS ALERT QUEUE — H-23: surfaces crisisAlert items at top of queue
//   getCrisisAlertQueue — callable (moderator/admin): returns unresolved crisis
//     alerts from moderatorAlerts + pastoralAlerts, sorted by urgency then time.
//     Intended for 30s-polling from the admin panel (crisis-queue.html).
//   resolveAlert — callable (moderator/admin): marks an alert resolved with
//     one of: safe | contacted_user | escalated_to_counselor |
//             false_positive | referred_988
// Deploy: firebase deploy --only functions:getCrisisAlertQueue,resolveAlert
//         --project amen-5e359
// ============================================================================
const adminModeration = require("./adminModerationFunctions");
exports.getCrisisAlertQueue = adminModeration.getCrisisAlertQueue;
exports.resolveAlert        = adminModeration.resolveAlert;

// ============================================================================
// BEREAN SHIELD & COMPASS — Claim truth-check + DM manipulation detection
//   bereanShieldAnalyze  — callable: analyze claim across 5 truth dimensions
//   bereanCompassAnalyze — callable: detect manipulation arc in DM transcript
// Secret required: CLAUDE_API_KEY
// Deploy: firebase deploy --only functions:bereanShieldAnalyze,bereanCompassAnalyze
//         --project amen-5e359
// ============================================================================
const bereanShield = require("./bereanShield");
exports.bereanShieldAnalyze  = bereanShield.bereanShieldAnalyze;
exports.bereanCompassAnalyze = bereanShield.bereanCompassAnalyze;

// ============================================================================
// BEREAN AI FEATURES — Daily Verse Drop, Weekly Prayer Recap
//   dailyVerseDrop      — scheduled daily 7am CT: personalized verse push
//   weeklyPrayerRecap   — scheduled Sunday 8pm CT: AI prayer journal recap
//   generatePrayerRecap — callable: on-demand prayer recap for current user
// Secret required: CLAUDE_API_KEY
// Deploy: firebase deploy --only functions:dailyVerseDrop,weeklyPrayerRecap,generatePrayerRecap
//         --project amen-5e359
// ============================================================================
const bereanAIFeatures = require("./bereanFeaturesFunctions");
exports.dailyVerseDrop     = bereanAIFeatures.dailyVerseDrop;
exports.weeklyPrayerRecap  = bereanAIFeatures.weeklyPrayerRecap;
exports.generatePrayerRecap = bereanAIFeatures.generatePrayerRecap;

// ============================================================================
// COMMUNICATION OS — Context detection, conversation memory, contact notes,
//                    thread mini-summary, V1 text moderation
//
//   analyzeMessageContext    — callable: detect links/dates/music/tasks/memories
//                              in a thread message; verifies caller is a member
//   analyzePostContext       — callable: detect context signals in a draft post
//   saveConversationMemory   — callable: save link/date/music/note/task/event/
//                              memory item in threads/{id}/memories
//   savePrivateContactNote   — callable: save private note about a contact
//                              written to callerUid path only, never logged
//   generateThreadMiniSummary — callable: summarize saved memories for a thread
//                              (Remote Config gated: smartThreadMiniSummaryEnabled)
//   moderateTextContent      — callable: rule-based V1 text moderation for
//                              message|post|profile|comment; fails open
//
// No external secrets required (V1 is fully deterministic / rule-based).
// Deploy: firebase deploy --only \
//   functions:analyzeMessageContext,analyzePostContext,saveConversationMemory,\
//   savePrivateContactNote,generateThreadMiniSummary,moderateTextContent \
//   --project amen-5e359
// ============================================================================
const communicationOS = require("./communicationOS");
exports.analyzeMessageContext     = communicationOS.analyzeMessageContext;
exports.analyzePostContext        = communicationOS.analyzePostContext;
exports.saveConversationMemory    = communicationOS.saveConversationMemory;
exports.savePrivateContactNote    = communicationOS.savePrivateContactNote;
exports.generateThreadMiniSummary = communicationOS.generateThreadMiniSummary;
exports.moderateTextContent       = communicationOS.moderateTextContent;

// ============================================================================
// BEREAN OS — Wisdom Operating System Cloud Functions
// ============================================================================
const { bereanCreateProject } = require("./berean_os_projects");
exports.bereanCreateProject = bereanCreateProject;

const { bereanExtractProjectMemory } = require("./berean_os_memory");
exports.bereanExtractProjectMemory = bereanExtractProjectMemory;

const { bereanStartResearch } = require("./berean_os_research");
exports.bereanStartResearch = bereanStartResearch;

const { bereanClassifyStatement } = require("./berean_os_truth");
exports.bereanClassifyStatement = bereanClassifyStatement;

const { bereanFetchSources } = require("./berean_os_sources");
exports.bereanFetchSources = bereanFetchSources;

const { bereanWisdomAnalysis } = require("./berean_os_wisdom");
exports.bereanWisdomAnalysis = bereanWisdomAnalysis;

const { bereanGenerateDebate } = require("./berean_os_debate");
exports.bereanGenerateDebate = bereanGenerateDebate;

const { bereanAIMentorReview } = require("./berean_os_mentor");
exports.bereanAIMentorReview = bereanAIMentorReview;

const { bereanRefineDocument, bereanGenerateActionPlan } = require("./berean_os_documents");
exports.bereanRefineDocument = bereanRefineDocument;
exports.bereanGenerateActionPlan = bereanGenerateActionPlan;

const { bereanConsultAdvisoryBoard } = require("./berean_os_advisory");
exports.bereanConsultAdvisoryBoard = bereanConsultAdvisoryBoard;

const { bereanArchiveProject, bereanUpdateProject } = require("./berean_os_projects");
exports.bereanArchiveProject = bereanArchiveProject;
exports.bereanUpdateProject = bereanUpdateProject;

const { bereanDiscoverKnowledgeLinks } = require("./berean_os_graph");
exports.bereanDiscoverKnowledgeLinks = bereanDiscoverKnowledgeLinks;

const { bereanMultiPerspective } = require("./berean_os_perspectives");
exports.bereanMultiPerspective = bereanMultiPerspective;

// Discussion OS — Context Participation
const discussionContextFunctions = require("./discussionContextFunctions");
exports.updateReadProgress     = discussionContextFunctions.updateReadProgress;
exports.updateAudioProgress    = discussionContextFunctions.updateAudioProgress;
exports.updateCarouselProgress = discussionContextFunctions.updateCarouselProgress;
exports.getContextScore        = discussionContextFunctions.getContextScore;

// Discussion OS — Health Engine
const discussionHealthFunctions = require("./discussionHealthFunctions");
exports.analyzeDiscussionHealth = discussionHealthFunctions.analyzeDiscussionHealth;
exports.autoAnalyzeHealth       = discussionHealthFunctions.autoAnalyzeHealth;

// Discussion OS — Draft Intelligence
const discussionDraftFunctions = require("./discussionDraftFunctions");
exports.analyzeDraft = discussionDraftFunctions.analyzeDraft;

// Discussion OS — Mediator
const discussionMediatorFunctions = require("./discussionMediatorFunctions");
exports.mediateDiscussion = discussionMediatorFunctions.mediateDiscussion;

// Discussion OS — Community Memory
const discussionMemoryFunctions = require("./discussionMemoryFunctions");
exports.recordDiscussionOutcome = discussionMemoryFunctions.recordDiscussionOutcome;

// Discussion OS — Command Center
const discussionCommandFunctions = require("./discussionCommandFunctions");
exports.getDiscussionDashboard = discussionCommandFunctions.getDiscussionDashboard;

// ============================================================================
// BEREAN STUDY ASSISTANT — 6 draft-only study callables
//   bereanExplainVerse         — plain-language explanation + historical context
//   bereanStudyPlan            — 7-day study plan from a topic or verse
//   bereanCompareTranslations  — side-by-side KJV / NIV / ESV / NLT comparison
//   bereanDiscussionQuestions  — 5 discussion questions from a passage
//   bereanPrayerFromPassage    — personalised prayer draft from a passage
//   bereanConvertToChurchNotes — structure passage into a Church Notes entry
//
// ALL outputs are DRAFTS (approved:false). User approves before any save/share.
// Shared rate limit: 20 AI requests per user per hour (pooled across all 6).
// Secret required: NVIDIA_API_KEY
// Deploy:
//   firebase deploy --only functions:bereanExplainVerse,bereanStudyPlan,\
//     bereanCompareTranslations,bereanDiscussionQuestions,\
//     bereanPrayerFromPassage,bereanConvertToChurchNotes \
//     --project amen-5e359
// ============================================================================
const bereanStudy = require("./bereanStudyFunctions");
exports.bereanExplainVerse         = bereanStudy.bereanExplainVerse;
exports.bereanStudyPlan            = bereanStudy.bereanStudyPlan;
exports.bereanCompareTranslations  = bereanStudy.bereanCompareTranslations;
exports.bereanDiscussionQuestions  = bereanStudy.bereanDiscussionQuestions;
exports.bereanPrayerFromPassage    = bereanStudy.bereanPrayerFromPassage;
exports.bereanConvertToChurchNotes = bereanStudy.bereanConvertToChurchNotes;

// ============================================================================
// INTEGRATION OS — External provider orchestration (X1–X7 contracts)
//   matchHashedContacts          — privacy-safe contact matching (HMAC hashes)
//   getContactDiscoverySalt      — per-user HMAC salt for client-side hashing
//   orgKnowledgeSearch           — full-text search in org knowledge base
//   orgAssistant                 — AI assistant over org docs (Claude, draft-only)
//   sendEventFollowUpNotification — FCM follow-up for event attendees
//   sendBroadcast                — multi-channel broadcast (push / SMS / email)
//   checkBroadcastChannelStatus  — consent + auth state for a messaging channel
//   revokeMessagingConsent       — server-authoritative consent revocation
//   transcribeVoiceNote          — Whisper transcription of a Storage voice note
//   moderateMediaTransform       — NeMo Guard check on sermon/media text transforms
// Secrets: ANTHROPIC_API_KEY, NVIDIA_API_KEY, OPENAI_API_KEY,
//          TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER
// Deploy: firebase deploy --only functions:matchHashedContacts,...
// ============================================================================
const integrationOS = require("./integrationOSFunctions");
exports.matchHashedContacts           = integrationOS.matchHashedContacts;
exports.getContactDiscoverySalt       = integrationOS.getContactDiscoverySalt;
exports.orgKnowledgeSearch            = integrationOS.orgKnowledgeSearch;
exports.orgAssistant                  = integrationOS.orgAssistant;
exports.sendEventFollowUpNotification = integrationOS.sendEventFollowUpNotification;
exports.sendBroadcast                 = integrationOS.sendBroadcast;
exports.checkBroadcastChannelStatus   = integrationOS.checkBroadcastChannelStatus;
exports.revokeMessagingConsent        = integrationOS.revokeMessagingConsent;
exports.transcribeVoiceNote           = integrationOS.transcribeVoiceNote;
exports.moderateMediaTransform        = integrationOS.moderateMediaTransform;

// GAP A3-P1 Studio + Synaptic callables
const { studioGenerateContent, studioJournalPrompt } = require('./amenStudioAI');
exports.studioGenerateContent = studioGenerateContent;
exports.studioJournalPrompt = studioJournalPrompt;
const { generateStudioImage } = require('./studioImageGeneration');
exports.generateStudioImage = generateStudioImage;
const { exportToPDF } = require('./studioExport');
exports.exportToPDF = exportToPDF;
const { synapticCreate } = require('./synapticFunctions');
exports.synapticCreate = synapticCreate;

// ============================================================================
// ACCOUNT SUBSCRIPTION — StoreKit entitlement processing
//   processAccountSubscription — callable: records App Store subscription tier
//     after a successful StoreKit transaction; writes to
//     users/{uid}/entitlements/platform; rate-limited to 10/min per user.
// TODO(gate: DECISION) — wire full JWT-based App Store Server API verification before launch; requires Apple App Store Connect private key in Secret Manager
// Deploy: firebase deploy --only functions:processAccountSubscription --project amen-5e359
// ============================================================================
const { processAccountSubscription } = require("./accountSubscriptionFunctions");
exports.processAccountSubscription = processAccountSubscription;

// ============================================================================
// DISCOVERY BY GOALS — Personal Discovery Agent search
//   discoverByGoals — callable: accepts goals text; returns top-5 communities,
//     churches, and upcoming events from Firestore.
// TODO(gate: DECISION) — replace Firestore range queries with Algolia semantic search; requires ALGOLIA_APP_ID + ALGOLIA_API_KEY provisioning decision
// Deploy: firebase deploy --only functions:discoverByGoals --project amen-5e359
// ============================================================================
const { discoverByGoals } = require("./discoveryByGoalsFunctions");
exports.discoverByGoals = discoverByGoals;

// ============================================================================
// CAMERA OS — Vision AI, Berean scripture scan, media safety, CSAM reporting
//   interpretContextLens — callable: OCR text → structured content type
//   bereanVisionScan     — callable: text → Biblical scripture analysis
//   scanMediaForSafety   — callable: image base64 → safety classification
//   reportCSAMFlag       — callable: CSAM human-review queue (no auto-decisions)
// Deploy: firebase deploy --only functions:interpretContextLens,bereanVisionScan,scanMediaForSafety,reportCSAMFlag --project amen-5e359
// ============================================================================
const {
  interpretContextLens,
  bereanVisionScan,
  scanMediaForSafety,
  reportCSAMFlag,
} = require("./cameraOSFunctions");
exports.interpretContextLens = interpretContextLens;
exports.bereanVisionScan     = bereanVisionScan;
exports.scanMediaForSafety   = scanMediaForSafety;
exports.reportCSAMFlag       = reportCSAMFlag;

// ============================================================================
// CHURCH PULSE — Computed church-health view derived from real Firestore data
//   getChurchPulse — callable: returns a cached or freshly-computed ChurchPulse
//     for the given churchId.
//     - Verifies caller is authenticated and a church member
//     - Applies 6-hour server-side cache in church_pulse/{churchId}
//     - Score is always derived from real events/prayers/volunteer data
//     - Never fabricates pulse data; returns UNKNOWN/0 when no data exists
// Auth:   required (uid must be member of the church)
// Reads:  events, prayers, volunteerOpportunities, churches/{id}/members
// Writes: church_pulse/{churchId} (cache write, fails silently)
// Deploy: firebase deploy --only functions:getChurchPulse --project amen-5e359
// ============================================================================
const { getChurchPulse } = require("./intelligence/churchPulseCallable");
exports.getChurchPulse = getChurchPulse;

// ============================================================================
// AMEN LIVE — Real-time in-app live session banner (prayer events, sermon streams,
//   community moments, volunteer mobilizations, crisis responses)
//
//   startAmenLiveSession — callable: pastor/admin only; creates an active session
//     - Requires pastor or admin custom claim
//     - Verifies backingEntity exists before writing
//     - Writes to amen_live_sessions/{sessionId} via Admin SDK
//   endAmenLiveSession   — callable: pastor/admin only; marks session isActive=false
//     - Requires pastor or admin custom claim
//   recordLiveAction     — callable: any authenticated user
//     - Writes to intelligence_actions/{userId}/actions/{actionId}
//     - NO counts or metrics stored — action type + sessionId only
//
// Firestore rules needed (add to firestore.rules):
//   match /amen_live_sessions/{sessionId} {
//     allow read: if isSignedIn();
//     allow write: if false; // CF Admin SDK only
//   }
//
// Auth:   startAmenLiveSession/endAmenLiveSession require pastor or admin claim
//         recordLiveAction requires authenticated user (any)
// Writes: amen_live_sessions/{sessionId}, intelligence_actions/{uid}/actions/{id}
// Deploy: firebase deploy --only functions:startAmenLiveSession,endAmenLiveSession,recordLiveAction --project amen-5e359
// ============================================================================
const {
    startAmenLiveSession,
    endAmenLiveSession,
    recordLiveAction,
} = require("./intelligence/amenLiveCallable");
exports.startAmenLiveSession = startAmenLiveSession;
exports.endAmenLiveSession   = endAmenLiveSession;
exports.recordLiveAction     = recordLiveAction;

// ============================================================================
// AGENT 3 — Event Intelligence, Prayer Graph, Need Detection Callables
//
// Callable functions: getEventIntelligence, getPrayerMatchCards, getNeedDetectionCards
// Privacy: no counts, no PII, fail-closed
// Firestore indexes required (see composite index notes at bottom of this block):
//   events: (organizerChurchId ASC, startDate ASC, isDeleted ASC)
//   events: (location.lat ASC, startDate ASC, isDeleted ASC)
//   prayers: (authorUID ASC, isAnswered ASC, isPublic ASC, createdAt DESC)
//   prayers: (authorUID ASC, isAnswered ASC, expiresAt ASC)
//   posts:   (authorUID ASC, isPublic ASC, createdAt DESC, isDeleted ASC)
//
// Auth:   all three callables require Firebase Auth
// Deploy: firebase deploy --only functions:getEventIntelligence,getPrayerMatchCards,getNeedDetectionCards --project amen-5e359
// ============================================================================
const {
    getEventIntelligence,
    getPrayerMatchCards,
    getNeedDetectionCards,
} = require("./intelligence/eventPrayerNeedCallables");
exports.getEventIntelligence  = getEventIntelligence;
exports.getPrayerMatchCards   = getPrayerMatchCards;
exports.getNeedDetectionCards = getNeedDetectionCards;

// ============================================================================
// WORLD RESPONSE — GLOBAL tier intelligence cards (Agent 5)
//   getWorldResponseCards — callable: returns GLOBAL IntelligenceCard[] for
//     current events; fail-closed (returns [] on error); never fabricates.
// Auth:   requires Firebase Auth
// Reads:  world_response_queue/{eventId} (populated by scheduled CF or admin)
// Writes: intelligence_cards/{cardId} (cache, CF Admin SDK)
// Deploy: firebase deploy --only functions:getWorldResponseCards --project amen-5e359
// ============================================================================
const { getWorldResponseCards } = require("./intelligence/worldResponseCallable");
exports.getWorldResponseCards = getWorldResponseCards;

// ============================================================================
// WORLD RESPONSE ADMIN — Admin/pastor management of world_response_queue
//   addWorldResponseEvent   — callable (pastor/admin): add a new world event
//     to world_response_queue; feeds the GLOBAL intelligence pipeline.
//   closeWorldResponseEvent — callable (pastor/admin): mark an event inactive
//     so it no longer appears in intelligence card generation.
//   listWorldResponseEvents — callable (pastor/admin): list active events for
//     admin review UI; returns up to 20 events ordered by createdAt desc.
//
// Auth:   pastor or admin custom claim required for all three
// Reads:  world_response_queue (listWorldResponseEvents, closeWorldResponseEvent)
// Writes: world_response_queue/{eventId} (addWorldResponseEvent, closeWorldResponseEvent)
// Deploy: firebase deploy --only \
//   functions:addWorldResponseEvent,closeWorldResponseEvent,listWorldResponseEvents \
//   --project amen-5e359
// ============================================================================
const {
    addWorldResponseEvent,
    closeWorldResponseEvent,
    listWorldResponseEvents,
} = require("./intelligence/worldResponseAdmin");
exports.addWorldResponseEvent    = addWorldResponseEvent;
exports.closeWorldResponseEvent  = closeWorldResponseEvent;
exports.listWorldResponseEvents  = listWorldResponseEvents;

// ============================================================================
// WORLD RESPONSE SOURCES SEEDER — One-time seed of trusted news sources
//   seedWorldResponseSources — callable (admin only): populates
//     worldResponseSources/{id} with DEFAULT_SOURCES list (merge: true —
//     never overwrites existing entries).
//     Run once after first deploy:
//       firebase functions:call seedWorldResponseSources --data '{}' --project amen-5e359
//
// Auth:   admin custom claim required
// Writes: worldResponseSources/{source.id} (merge: true)
// Deploy: firebase deploy --only functions:seedWorldResponseSources --project amen-5e359
// ============================================================================
const { seedWorldResponseSources } = require("./intelligence/seedWorldResponseSources");
exports.seedWorldResponseSources = seedWorldResponseSources;

// ============================================================================
// LIVING INTELLIGENCE CALLABLES — getIntelligenceBrief, recordIntelligenceAction
//
// NOTE: These callables are defined in v2intelligenceFunctions.js alongside the
// buildDailyIntelligenceBriefs scheduled trigger. Because that file imports
// firebase-functions/v2/scheduler at the top level, requiring it here would
// cause the Firebase CLI to apply v2 CPU/concurrency settings to ALL Gen-1
// functions in this file — violating the Gen-1/Gen-2 separation constraint.
//
// THEREFORE: Both callables are deployed exclusively via the "v2triggers"
// Firebase codebase (functions/v2triggers/). iOS clients call them as normal
// Gen-2 callables — the codebase distinction is transparent to the iOS SDK.
//
// Deploy commands:
//   firebase deploy --only "functions:v2triggers:getIntelligenceBrief,functions:v2triggers:recordIntelligenceAction" --project amen-5e359
//   firebase deploy --only "functions:v2triggers:buildDailyIntelligenceBriefs" --project amen-5e359
//   firebase deploy --only functions:v2triggers --project amen-5e359  (deploys all v2 triggers)
// ============================================================================
// DO NOT require("./v2intelligenceFunctions") here — it imports v2/scheduler
// which would contaminate this Gen-1 file with v2 settings.
// See functions/v2triggers/ and functions/v2entry.js for the deployment path.

// ============================================================================
// MEDIA PROVENANCE — Content authenticity trail
//   registerMediaProvenance — callable: register provenance for uploaded media
//   getPostProvenance       — callable: fetch provenance chain for a post
// Deploy: firebase deploy --only functions:registerMediaProvenance,getPostProvenance --project amen-5e359
// ============================================================================
const provenanceFunctions = require("./provenanceFunctions");
// registerMediaProvenance owned by creator codebase
exports.getPostProvenance       = provenanceFunctions.getPostProvenance;

// ============================================================================
// AI DISCLOSURE — Transparency labels for AI-generated content
//   registerAIDisclosure   — callable: record AI disclosure for generated content
//   getAIDisclosureDetails — callable: fetch disclosure metadata for a post/comment
// Deploy: firebase deploy --only functions:registerAIDisclosure,getAIDisclosureDetails --project amen-5e359
// ============================================================================
const aiDisclosureFunctions = require("./aiDisclosureFunctions");
exports.registerAIDisclosure   = aiDisclosureFunctions.registerAIDisclosure;
exports.getAIDisclosureDetails = aiDisclosureFunctions.getAIDisclosureDetails;

// ============================================================================
// CONTENT REPORTING — User-initiated content reports
//   reportContent — callable: submit a report for a post, comment, or profile
// Deploy: firebase deploy --only functions:reportContent --project amen-5e359
// ============================================================================
const reportFunctions = require("./reportFunctions");
exports.reportContent = reportFunctions.reportContent;

// ============================================================================
// PUBLISH PIPELINE — Trust-gated post publishing
//   publishPostWithTrustGates — callable: run trust checks before finalizing publish
// Deploy: firebase deploy --only functions:publishPostWithTrustGates --project amen-5e359
// ============================================================================
const publishPipelineFunctions = require("./publishPipelineFunctions");
exports.publishPostWithTrustGates = publishPipelineFunctions.publishPostWithTrustGates;

// ============================================================================
// DISCOVERY TRANSPARENCY — Why Seeing This
//   getDiscoveryReasons — callable: returns ranked reasons a post appeared in feed
// Deploy: firebase deploy --only functions:getDiscoveryReasons --project amen-5e359
// ============================================================================
const discoveryTransparencyFunctions = require("./discoveryTransparencyFunctions");
exports.getDiscoveryReasons = discoveryTransparencyFunctions.getDiscoveryReasons;

// ============================================================================
// SPATIAL MESSAGES — Shared viewing rooms + anchored replies
//   createSharedViewingRoom — callable: create a co-viewing session for a media item
//   joinSharedViewingRoom   — callable: join an active shared viewing room
//   leaveSharedViewingRoom  — callable: leave / clean up a shared viewing room
//   postAnchoredReply       — callable: post a reply anchored to a media timestamp
// Deploy: firebase deploy --only functions:createSharedViewingRoom,joinSharedViewingRoom,leaveSharedViewingRoom,postAnchoredReply --project amen-5e359
// ============================================================================
const spatialMessagesFunctions = require("./spatialMessagesFunctions");
exports.createSharedViewingRoom = spatialMessagesFunctions.createSharedViewingRoom;
exports.joinSharedViewingRoom   = spatialMessagesFunctions.joinSharedViewingRoom;
exports.leaveSharedViewingRoom  = spatialMessagesFunctions.leaveSharedViewingRoom;
exports.postAnchoredReply       = spatialMessagesFunctions.postAnchoredReply;

// ============================================================================
// 242 HUB — Covenant application review + Kingdom Commerce matching
//   reviewCovenantApp  — callable (pastor/admin): review a covenant membership application
//   matchKingdomCommerce — callable: match user's spiritual gifts to commerce opportunities
// Deploy: firebase deploy --only functions:reviewCovenantApp,matchKingdomCommerce --project amen-5e359
// ============================================================================
const hub242 = require("./242hub");
exports.reviewCovenantApp    = hub242.reviewCovenantApp;
exports.matchKingdomCommerce = hub242.matchKingdomCommerce;

// ============================================================================
// CATALOG & KNOWLEDGE NETWORK — Creator catalog system
//   Ingestion Hub:    connectSource, disconnectSource, triggerManualSync,
//                     createCatalogWork, listConnectedSources, getIngestionStatus
//   Review Workflow:  advanceWorkReviewState, approveWork, publishWork (HUMAN GATE),
//                     unpublishWork, softDeleteWork, bulkAdvanceState
//   Ingestion Engine: startIngestion, syncApprovedSources
//   AI – Embed:       embedWork, onWorkApproved, removeWorkEmbedding
//   AI – Topics:      updateKnowledgeNodes, onWorkPublished
//   AI – Ask Creator: askCreatorQuery, getCatalogQueryStats (fail-closed RAG)
//   Billing:          checkCatalogEntitlement, getCreatorCatalogSettings,
//                     createCatalogCheckoutSession, createWorkPaymentIntent,
//                     enrichWorkLinks, trackAffiliateLinkClick
//   Verification:     submitVerificationClaim, checkDomainVerification,
//                     checkSocialOAuthVerification, checkEmailDomainVerification,
//                     confirmEmailCode, revokeBadge, getVerificationStatus
//   Anti-Impersonation: reportImpersonation, checkCreatorProtection,
//                       transferOrgAdmin (HUMAN GATE), getUnofficialCatalogLabel
//   Search:           searchCatalog, searchCreators, getTopicSuggestions
//   Follow-Knowledge: followTopic, unfollowTopic, getFollowedTopics, getTopicFeed
//
// Human gates: publishWork, transferOrgAdmin (require confirmed: true — never auto-execute)
// Secrets: PINECONE_API_KEY, PINECONE_HOST, ALGOLIA_APP_ID, ALGOLIA_ADMIN_API_KEY,
//          STRIPE_PRICE_CREATOR_PRO, STRIPE_PRICE_CREATOR_STUDIO,
//          AMAZON_AFFILIATE_TAG, BOOKSHOP_AFFILIATE_CODE
// Deploy: firebase deploy --only \
//   functions:connectSource,disconnectSource,triggerManualSync,createCatalogWork,\
//   listConnectedSources,getIngestionStatus,advanceWorkReviewState,approveWork,\
//   publishWork,unpublishWork,softDeleteWork,bulkAdvanceState,startIngestion,\
//   syncApprovedSources,embedWork,onWorkApproved,removeWorkEmbedding,\
//   updateKnowledgeNodes,onWorkPublished,askCreatorQuery,getCatalogQueryStats,\
//   checkCatalogEntitlement,getCreatorCatalogSettings,createCatalogCheckoutSession,\
//   createWorkPaymentIntent,enrichWorkLinks,trackAffiliateLinkClick,\
//   submitVerificationClaim,checkDomainVerification,checkSocialOAuthVerification,\
//   checkEmailDomainVerification,confirmEmailCode,revokeBadge,getVerificationStatus,\
//   reportImpersonation,checkCreatorProtection,transferOrgAdmin,\
//   getUnofficialCatalogLabel,searchCatalog,searchCreators,getTopicSuggestions,\
//   followTopic,unfollowTopic,getFollowedTopics,getTopicFeed \
//   --project amen-5e359
// ============================================================================

// Ingestion Hub (callable)
const importHub = require("./ingestion/importHub");
exports.connectSource        = importHub.connectSource;
exports.disconnectSource     = importHub.disconnectSource;
exports.triggerManualSync    = importHub.triggerManualSync;
exports.createCatalogWork    = importHub.createManualWork; // iOS clients call "createCatalogWork"
exports.listConnectedSources = importHub.listConnectedSources;
exports.getIngestionStatus   = importHub.getIngestionStatus;

// Ingestion Engine — internal pipeline module (called by triggerManualSync in importHub)
// startIngestion and syncApprovedSources are plain helpers, not Firebase handlers; not exported.
const ingestionEngine = require("./ingestion/ingestionEngine"); // loaded for side-effect dependency resolution

// Review Workflow (callable) — publishWork is a HUMAN GATE
const reviewWorkflow = require("./ingestion/reviewWorkflow");
exports.advanceWorkReviewState = reviewWorkflow.advanceWorkReviewState;
exports.approveWork            = reviewWorkflow.approveWork;
exports.publishWork            = reviewWorkflow.publishWork;
exports.unpublishWork          = reviewWorkflow.unpublishWork;
exports.softDeleteWork         = reviewWorkflow.softDeleteWork;
exports.bulkAdvanceState       = reviewWorkflow.bulkAdvanceState;

// AI: Embed + Knowledge Nodes (callable + Firestore triggers)
const embedCatalogWork = require("./ai-catalog/embedCatalogWork");
exports.embedWork      = embedCatalogWork.embedWork;
exports.onWorkApproved = embedCatalogWork.onWorkApproved;
// removeWorkEmbedding is an internal helper called by onWorkApproved — not a deployable CF

const topicClusterEngine = require("./ai-catalog/topicClusterEngine");
exports.updateKnowledgeNodes = topicClusterEngine.updateKnowledgeNodes;
exports.onWorkPublished      = topicClusterEngine.onWorkPublished;

// AI: Ask Creator (callable, fail-closed RAG)
const askCreatorQueryModule = require("./ai-catalog/askCreatorQuery");
exports.askCreatorQuery      = askCreatorQueryModule.askCreatorQuery;
exports.getCatalogQueryStats = askCreatorQueryModule.getCatalogQueryStats;

// Billing: Catalog entitlements (callable)
const catalogEntitlements = require("./billing/catalogEntitlements");
exports.checkCatalogEntitlement      = catalogEntitlements.checkCatalogEntitlement;
exports.getCreatorCatalogSettings    = catalogEntitlements.getCreatorCatalogSettings;
exports.createCatalogCheckoutSession = catalogEntitlements.createCatalogCheckoutSession;
exports.createWorkPaymentIntent      = catalogEntitlements.createWorkPaymentIntent;

// Billing: Affiliate link tracking (callable)
const affiliateLinkWrapper = require("./billing/affiliateLinkWrapper");
exports.enrichWorkLinks         = affiliateLinkWrapper.enrichWorkLinks;
exports.trackAffiliateLinkClick = affiliateLinkWrapper.trackAffiliateLinkClick;

// Verification engine (callable) — transferOrgAdmin is a HUMAN GATE
const verificationEngine = require("./verification/verificationEngine");
exports.submitVerificationClaim      = verificationEngine.submitVerificationClaim;
exports.checkDomainVerification      = verificationEngine.checkDomainVerification;
exports.checkSocialOAuthVerification = verificationEngine.checkSocialOAuthVerification;
exports.checkEmailDomainVerification = verificationEngine.checkEmailDomainVerification;
exports.confirmEmailCode             = verificationEngine.confirmEmailCode;
exports.revokeBadge                  = verificationEngine.revokeBadge;
exports.getVerificationStatus        = verificationEngine.getVerificationStatus;

const antiImpersonation = require("./verification/antiImpersonation");
exports.reportImpersonation    = antiImpersonation.reportImpersonation;
exports.checkCreatorProtection = antiImpersonation.checkCreatorProtection;
exports.transferOrgAdmin       = antiImpersonation.transferOrgAdmin;
// getUnofficialCatalogLabel is a pure utility called by iOS-side logic — not a deployable CF

// Search (callable)
const catalogSearchModule = require("./search/catalogSearch");
exports.searchCatalog       = catalogSearchModule.searchCatalog;
exports.searchCreators      = catalogSearchModule.searchCreators;
exports.getTopicSuggestions = catalogSearchModule.getTopicSuggestions;

// Follow-Knowledge (callable)
const followKnowledge = require("./search/followKnowledge");
exports.followTopic       = followKnowledge.followTopic;
exports.unfollowTopic     = followKnowledge.unfollowTopic;
exports.getFollowedTopics = followKnowledge.getFollowedTopics;
exports.getTopicFeed      = followKnowledge.getTopicFeed;

// ============================================================================
// FEED CONTEXT — Attach contextual signals to ranked feed posts
// ============================================================================
const feedContext = require("./feedContextFunctions");
exports.attachFeedContextToRankedPosts = feedContext.attachFeedContextToRankedPosts;

// ============================================================================
// BIBLICAL ALIGNMENT — Shared knowledge integrity
// ============================================================================
const biblicalAlignment = require("./biblicalAlignmentFunctions");
exports.attachSharedKnowledgeIntegrity = biblicalAlignment.attachSharedKnowledgeIntegrity;

// ============================================================================
// RESTORED FUNCTIONS (us-central1) — 15 previously active functions
// recreated from function contracts. Already deployed to us-central1.
// ============================================================================
const restoredFunctions = require("./restoredFunctions");
exports.acceptConnectInvite                = restoredFunctions.acceptConnectInvite;
exports.activateSextortionPanicFlow        = restoredFunctions.activateSextortionPanicFlow;
exports.activateSpaceMembership            = restoredFunctions.activateSpaceMembership;
exports.addInsightToWalkWithChrist         = restoredFunctions.addInsightToWalkWithChrist;
exports.analyzeAmenMediaWithBerean         = restoredFunctions.analyzeAmenMediaWithBerean;
exports.analyzeMessageSafety               = restoredFunctions.analyzeMessageSafety;
exports.analyzePostTrustLogoMatch          = restoredFunctions.analyzePostTrustLogoMatch;
exports.analyzeScriptureDrift              = restoredFunctions.analyzeScriptureDrift;
exports.analyzeTruthVsEmotion              = restoredFunctions.analyzeTruthVsEmotion;
exports.applyToMarketplaceListing          = restoredFunctions.applyToMarketplaceListing;
exports.approveGeneratedDraft              = restoredFunctions.approveGeneratedDraft;
exports.askStreamTranscript                = restoredFunctions.askStreamTranscript;
exports.auditChurchNotePrivacyChange       = restoredFunctions.auditChurchNotePrivacyChange;
exports.backfillHolidayCalendar            = restoredFunctions.backfillHolidayCalendar;
exports.bereanAsk                          = restoredFunctions.bereanAsk;

// ============================================================================
// RESTORED FUNCTIONS OVERFLOW (us-east1) — 11 functions that could not be
// deployed to us-central1 due to quota (1000-service limit).
// iOS clients calling these should use Functions.functions(region: "us-east1").
// ============================================================================
const overflowFunctions = require("./restoredFunctionsOverflow");
exports.askBereanAboutSelahMedia           = overflowFunctions.askBereanAboutSelahMedia;
exports.bereanAnalyzeMessage               = overflowFunctions.bereanAnalyzeMessage;
exports.bereanEvaluateAuthorityEscalation  = overflowFunctions.bereanEvaluateAuthorityEscalation;
exports.bereanGenerateChurchNotesSummary   = overflowFunctions.bereanGenerateChurchNotesSummary;
exports.bereanGenerateDiscipleshipNextStep = overflowFunctions.bereanGenerateDiscipleshipNextStep;
exports.bereanGetImmersionPayload          = overflowFunctions.bereanGetImmersionPayload;
exports.bereanGetJourneySnapshot           = overflowFunctions.bereanGetJourneySnapshot;
exports.bereanSaveReflectionEntry          = overflowFunctions.bereanSaveReflectionEntry;
exports.blockRelationshipCleanup           = overflowFunctions.blockRelationshipCleanup;
exports.broadcastSpaceAnnouncement         = overflowFunctions.broadcastSpaceAnnouncement;
exports.broadcastSpaceEvent                = overflowFunctions.broadcastSpaceEvent;

// ============================================================================
// LIVE ACTIVITIES — Prayer Request push counter + push-to-start (Phases 2 & 3)
// Deploy by name only:
//   firebase deploy --only functions:prayForRequest
//   firebase deploy --only functions:onPrayingUserWritten
//   firebase deploy --only functions:onPrayerRequestUpdated
//   firebase deploy --only functions:onPrayerRequestCreated
// ============================================================================
const liveActivity = require("./liveActivityFunctions");
exports.prayForRequest            = liveActivity.prayForRequest;
exports.onPrayingUserWritten      = liveActivity.onPrayingUserWritten;
exports.onPrayerRequestUpdated    = liveActivity.onPrayerRequestUpdated;
exports.onPrayerRequestCreated    = liveActivity.onPrayerRequestCreated;


// ============================================================================
// REPORT UNSAFE AI — user-facing pipeline for reporting unsafe AI responses (C-04)
// ============================================================================
const reportAI = require("./reportAIFunctions");
exports.reportUnsafeAIResponse = reportAI.reportUnsafeAIResponse;

// ============================================================================
// MODERATION APPEALS (v2) — moderation/appeals.js
//   submitAppeal — onCall (enforceAppCheck): authenticated user submits appeal
//   decideAppeal — onCall (enforceAppCheck): moderator approves or denies appeal
// Deploy: firebase deploy --only functions:submitAppeal,decideAppeal --project amen-5e359
// ============================================================================
const moderationAppeals = require("./moderation/appeals");
exports.submitAppeal = moderationAppeals.submitAppeal;
exports.decideAppeal = moderationAppeals.decideAppeal;

// ============================================================================
// SAFETY REPORT — iOS report button backend (auth + App Check + rate-limited)
//   submitSafetyReport — callable: writes to moderationQueue server-side;
//     critical categories (csam/child_safety/grooming) trigger escalation pipeline.
// Deploy: firebase deploy --only functions:submitSafetyReport --project amen-5e359
// ============================================================================
exports.submitSafetyReport = require("./safety/submitSafetyReport").submitSafetyReport;

// ============================================================================
// GUARDIAN LINK (finding #44) — email verification pipeline for minor guardian linking
//   onGuardianLinkCreated — onDocumentCreated: sends OTP email, stamps request doc
//   verifyGuardianLink    — onCall (enforceAppCheck): validates OTP, writes approval
// Gate: guardian_link_enabled Remote Config flag (default false).
// Deploy: firebase deploy --only functions:onGuardianLinkCreated,functions:verifyGuardianLink --project amen-5e359
// ============================================================================
const guardianLink = require("./guardianLink");
exports.onGuardianLinkCreated = guardianLink.onGuardianLinkCreated;
exports.verifyGuardianLink    = guardianLink.verifyGuardianLink;
