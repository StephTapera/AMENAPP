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
// exports.bereanChatProxy = berean.bereanChatProxy; // DISABLED: Using TypeScript version from Backend/functions
exports.deleteAccount = berean.deleteAccount;
// Study Assistant — routes all BereanContextActionEngine.swift calls
exports.routeBereanContextualAction = berean.routeBereanContextualAction;
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
exports.createRealtimeSession = bereanRealtime.createRealtimeSession;
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
//                           multilingual TODO; rate limit 30/hour
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
