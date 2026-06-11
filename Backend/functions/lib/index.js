"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __exportStar = (this && this.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.onPostCreatedRunMediaModeration = exports.evaluateTone = exports.getAILabelDetail = exports.recordPostAIUsage = exports.createWalkWithChristPathFromPattern = exports.generateMeaningPrompt = exports.updateEternalWeightAfterReflection = exports.calculateEternalWeight = exports.generateCommunityDiscernmentSummary = exports.aggregateDiscernmentSignals = exports.generateGracefulRewrite = exports.scoreWeightOfWords = exports.analyzeTruthVsEmotion = exports.updateUserGrowthPattern = exports.savePostActionReflection = exports.createReflectionPrompt = exports.updateMomentLearning = exports.logMomentInterception = exports.evaluateMomentRisk = exports.generateReconciliationPrompt = exports.classifyRelationshipState = exports.updateRelationalGravity = exports.markSilenceSignalResolved = exports.resurfaceAvoidedItem = exports.detectSilencePatterns = exports.dismissDriftSignal = exports.generateBalancingScripture = exports.analyzeScriptureDrift = exports.resolveUnsentThought = exports.saveUnsentThought = exports.detectUnsentThoughtRisk = exports.updateChurchLiveSignals = exports.syncYouTubeChurchStreams = exports.generateGroundedChurchAnswer = exports.refreshChurchLivestreamState = exports.reviewChurchModerationItem = exports.submitChurchProfileUpdate = exports.updateAlignmentProfile = exports.getWeeklyAlignmentSummary = exports.voteKnowledgeIntegrity = exports.attachSharedKnowledgeIntegrity = exports.sendNotification = exports.indexPostIntoHub = exports.reportHubContent = exports.muteObjectHub = exports.recordObjectInteraction = exports.getRelatedObjectHubs = exports.getObjectHub = exports.createOrJoinObjectHub = exports.resolveCommunityObject = void 0;
exports.getLivekitToken = exports.generateLiveKitToken = exports.onSabbathNotificationWrite = exports.syncFamilySabbathPresence = exports.setSabbathPreference = exports.evaluateSabbathMode = exports.matchNeedsToVolunteers = exports.classifyPostNeed = exports.onPrayerCreated = exports.matchPrayerSupport = exports.matchEventsForUser = exports.triggerIntelligenceBriefForUser = exports.buildIntelligenceBriefs = exports.buildGlobalCard = exports.generateWorldResponse = exports.submitWorldEvent = exports.getGlobalIntelligenceCards = exports.triggerMediaModeration = exports.getAccountMediaRiskScore = exports.getPostModerationStatus = exports.submitMediaReviewDecision = exports.onPostMediaUpdatedRunModeration = void 0;
const admin = __importStar(require("firebase-admin"));
if (!admin.apps.length) {
    admin.initializeApp();
}
// AI Proxy Functions
__exportStar(require("./bereanChatProxy"), exports);
__exportStar(require("./bereanChatProxyStream"), exports); // True SSE streaming proxy
__exportStar(require("./openAIProxy"), exports);
__exportStar(require("./whisperProxy"), exports);
__exportStar(require("./generateDailyVerse"), exports);
__exportStar(require("./amenDaily/getAmenDailyDigest"), exports);
__exportStar(require("./cameraOS/contextLens"), exports);
__exportStar(require("./communityOS/core"), exports);
// Phase P1-4: server-authoritative Think-First / Tone Checker.
// iOS ThinkFirstGuardrailsService is advisory only; the publish path
// (CreatePost / comments / replies) MUST call validateThinkFirstCheck
// before persisting user-authored content.
__exportStar(require("./thinkFirst/validateThinkFirstCheck"), exports);
// Phase H3 / App Review Guideline 1.2: user-facing "report this AI
// response" mechanism. Persists structured reports to aiUnsafeReports
// for human review without echoing the raw response text.
__exportStar(require("./aiSafety/reportUnsafeAIResponse"), exports);
// Berean Spiritual Intelligence Layers (System 16)
//   Feature 1: Living Scripture Graph
//   Feature 2: Spiritual State Discernment Layer
//   Feature 3: Guided Discipleship Engine
//   Feature 4: Scripture Immersion Mode
//   Feature 5: Authority Alignment System
__exportStar(require("./berean/controllers/generateStructuredResponse"), exports);
__exportStar(require("./berean/controllers/studyPassage"), exports);
__exportStar(require("./berean/controllers/analyzeMessage"), exports);
__exportStar(require("./berean/controllers/evaluateAuthorityEscalation"), exports);
__exportStar(require("./berean/controllers/getImmersionPayload"), exports);
__exportStar(require("./berean/controllers/getJourneySnapshot"), exports);
__exportStar(require("./berean/controllers/generateDiscipleshipNextStep"), exports);
__exportStar(require("./berean/controllers/saveReflectionEntry"), exports);
__exportStar(require("./berean/controllers/generateChurchNotesSummary"), exports);
__exportStar(require("./berean/controllers/premiumBereanCallables"), exports);
// Selah Media OS (System 18)
__exportStar(require("./selahMedia"), exports);
// Smart Media Attachments (System 22)
// resolveSmartAttachment, saveMediaGraphItem, getRecentMediaAttachments, getSavedMediaItems
__exportStar(require("./smartAttachments"), exports);
__exportStar(require("./noteShare"), exports);
// Safety OS Reaction Engine
__exportStar(require("./safetyOSReactionEngine"), exports);
// Community Hubs & Object Intelligence
var communityHubs_1 = require("./communityHubs");
Object.defineProperty(exports, "resolveCommunityObject", { enumerable: true, get: function () { return communityHubs_1.resolveCommunityObject; } });
Object.defineProperty(exports, "createOrJoinObjectHub", { enumerable: true, get: function () { return communityHubs_1.createOrJoinObjectHub; } });
Object.defineProperty(exports, "getObjectHub", { enumerable: true, get: function () { return communityHubs_1.getObjectHub; } });
Object.defineProperty(exports, "getRelatedObjectHubs", { enumerable: true, get: function () { return communityHubs_1.getRelatedObjectHubs; } });
Object.defineProperty(exports, "recordObjectInteraction", { enumerable: true, get: function () { return communityHubs_1.recordObjectInteraction; } });
Object.defineProperty(exports, "muteObjectHub", { enumerable: true, get: function () { return communityHubs_1.muteObjectHub; } });
Object.defineProperty(exports, "reportHubContent", { enumerable: true, get: function () { return communityHubs_1.reportHubContent; } });
Object.defineProperty(exports, "indexPostIntoHub", { enumerable: true, get: function () { return communityHubs_1.indexPostIntoHub; } });
// Accessibility Intelligence Layer
__exportStar(require("./refineTranslation"), exports);
__exportStar(require("./transformContent"), exports);
// Group Link Functions
__exportStar(require("./groupLinks"), exports);
__exportStar(require("./resolveOrCreateConversation"), exports);
// Suggested Accounts Rail
__exportStar(require("./suggestedAccounts"), exports);
__exportStar(require("./userSettings"), exports);
// UserProfileMini context callable
__exportStar(require("./profileMini/getUserProfileMiniContext"), exports);
// Trust + Intelligence (Berean infrastructure)
__exportStar(require("./trustIntelligence"), exports);
__exportStar(require("./amenConnect"), exports);
__exportStar(require("./legacyAiSafetyBridge"), exports);
// Action Threads — server-authoritative care workflow CRUD
// All state transitions and participant invitations are validated server-side.
__exportStar(require("./actionThreads"), exports);
__exportStar(require("./actionIntelligence"), exports);
// Private/Follower Feed Builder
__exportStar(require("./feedBuilder"), exports);
__exportStar(require("./postReactions"), exports);
__exportStar(require("./postCountTriggers"), exports);
// Smart Context Label scoring, ranking, feedback, and preference sync
__exportStar(require("./feedContext"), exports);
__exportStar(require("./bereanPulse"), exports);
// Dynamic Reply Preview system — server-ranked inline PostCard preview candidates
__exportStar(require("./generateDynamicReplyPreviews"), exports);
__exportStar(require("./churchDiscoveryPhase2"), exports);
__exportStar(require("./churchDiscoveryPhase3"), exports);
// Server-authoritative feature flags (CRITICAL-3)
// Safety flags are read from Firestore by Cloud Functions — never trusted from the client.
// Must be exported before antiHarassmentEnforcement (which imports from it).
__exportStar(require("./serverFeatureFlags"), exports);
// Anti-Harassment Enforcement — server-side restriction checks on message sends
// CRITICAL-1: Enforces messaging/dm_freeze/no_contact restrictions and block checks
// unconditionally on the server, regardless of the client write path.
__exportStar(require("./antiHarassmentEnforcement"), exports);
// Account Suspension — Firebase Auth disablement for critical harassment tier
// HIGH-2: Auto-suspends accounts when critical/minor-safety queue items are created.
__exportStar(require("./accountSuspension"), exports);
__exportStar(require("./twoFactorAuth"), exports);
__exportStar(require("./accountLifecycle"), exports);
// Safety Reporting — server-side report creation with validation
// HIGH-3: submitReport callable validates reason, verifies evidence, computes
// escalationTier and priority server-side. Direct client writes to userReports
// are now blocked in Firestore rules (allow create: if false).
__exportStar(require("./submitReport"), exports);
// Comment Moderation Enforcement — server-authoritative moderationStatus writes to RTDB
// Triggered on every new userReports document. For reports with contentType="comment",
// aggregates report history and writes moderationStatus ("pending" | "hidden") to
// /comments/{postId}/{commentId}/moderationStatus in RTDB based on tier/count thresholds.
// Closes the audit gap: moderationStatus was previously client-written with no server enforcement.
__exportStar(require("./commentModerationEnforcement"), exports);
// Media Scanning — Cloud Vision SafeSearch on every Storage upload
// HIGH-1: Scans images for CSAM/explicit/violence signals on onFinalize.
// VERY_LIKELY → delete file + suspend account
// LIKELY      → quarantine file + queue for human review
// POSSIBLE    → flag originating document, queue for human review
__exportStar(require("./mediaScanning"), exports);
// Account Deletion — Algolia record removal (App Store Guideline 5.1.1)
// Called by AccountDeletionService during full account deletion flow.
// Deletes the user record from "users" index and all posts from "posts" index.
__exportStar(require("./deleteAlgoliaUser"), exports);
// CRITICAL: Post deletion cascade — cleans up comments, reactions, reposts,
// savedPosts, feed items, Algolia record, and Storage media when a post is deleted.
__exportStar(require("./postDeletionCascade"), exports);
// CRITICAL: Full account deletion cascade — deletes all user content across
// every collection and subcollection (App Store Guideline 5.1.1 compliance).
__exportStar(require("./userAccountDeletionCascade"), exports);
// CRITICAL: Block relationship cleanup — removes follow edges, pending follow
// requests, and restricts shared conversations when a block is created.
__exportStar(require("./blockRelationshipCleanup"), exports);
// Atomic block/unblock — writes to BOTH blockedUsers top-level collection
// (used by antiHarassmentEnforcement) and users/{uid}/blockedUsers subcollection
// (used by Firestore rules) in a single batch. Prevents partial-block drift.
__exportStar(require("./createBlock"), exports);
// Atomic follow/unfollow — writes follows edge doc AND follows_index doc
// (used by callerFollows() in Firestore rules for follower-only content gating)
// in a single batch. Prevents follows_index missing entries that silently break
// follower-only post visibility.
__exportStar(require("./createFollow"), exports);
// Notification Functions — Server-side pipeline
//
// Firestore triggers use gen2 syntax (firebase-functions/v2/firestore) so they
// coexist with gen2 onCall functions in the same deployment.
__exportStar(require("./notifications/onSocialEvent"), exports);
__exportStar(require("./notifications/counts"), exports);
__exportStar(require("./notifications/maintenance"), exports);
__exportStar(require("./notifications/invalidation"), exports);
// sendNotification callable — rate-limited (100/min per sender), auth-gated,
// block-checked direct push for 1:1 sends. Bulk fan-out uses the Firestore
// trigger pipeline in onSocialEvent.ts; this callable is for explicit
// client-initiated pushes (e.g. DM nudge, ministry alert to a single user).
// Rate-limit docs land in _rateLimits/{notif_{uid}_{minuteBucket}} with a
// `ttl` field. Configure a TTL policy on that collection group in the
// Firebase console (field: ttl) to auto-delete stale counter docs.
var sendNotificationCallable_1 = require("./notifications/sendNotificationCallable");
Object.defineProperty(exports, "sendNotification", { enumerable: true, get: function () { return sendNotificationCallable_1.sendNotification; } });
// 5.4 FIX — Prayer answered fan-out: processes ≤100 supporter batches per
// invocation, eliminating the timeout risk of sequential single-function fan-out.
__exportStar(require("./notifications/prayerAnsweredBatch"), exports);
// 5.6 FIX — Quiet hours digest: scheduled every 30 min to batch-deliver push
// notifications to users whose quiet window has ended.
__exportStar(require("./notifications/deliverQuietHoursDigest"), exports);
// Church Visit Lifecycle — phase-triggered follow-up scheduling and FCM nudges
// Triggered on attended/reflected phase transitions in users/{uid}/churchInteractions/{churchId}
__exportStar(require("./churchVisitLifecycle"), exports);
// Church Journey System — full Find Church → Plan → Notes → Reflection orchestration
// createChurchJourney, updateChurchJourneyTiming, promoteJourneyToPrepActive,
// promoteJourneyToArrived, generateReflectionSeedFromNotes,
// scheduleMidweekReflectionReminder, learnChurchRoutine,
// cleanupStaleChurchJourneys, generatePrepSuggestions
__exportStar(require("./churchJourney"), exports);
__exportStar(require("./churchDiscovery"), exports);
__exportStar(require("./spiritualSystems"), exports);
// Post Creation Finalizer — text moderation, status transition (publishing→published),
// Algolia indexing. Feed fanout for followers-only posts is in feedBuilder.ts.
// Exported as finalizePostOnCreate to avoid conflict with the onPostCreated
// mention-handler in onSocialEvent.ts.
__exportStar(require("./onPostCreated"), exports);
// Media Post Index — maintains users/{authorId}/mediaPosts/{postId} denormalized
// index for profile "Photos & Videos" tab. Triggered on post create/update/delete.
// Handles moderation state changes, visibility changes, and media schema evolution.
__exportStar(require("./mediaPostIndex"), exports);
// Algolia sync — keeps "posts" index current on post edit and deletion
__exportStar(require("./algoliaSync"), exports);
// Scheduled maintenance — counter reconciliation, stale data pruning, token cleanup
__exportStar(require("./scheduledMaintenance"), exports);
// Age tier JWT claim sync — P1.1 FIX: sets ageTier custom claim on users/{uid}.ageTier
// changes so Firestore rules can read from request.auth.token.ageTier (zero get() reads).
__exportStar(require("./syncAgeTierClaim"), exports);
// Username change rate limiting — 30-day cooldown enforced server-side
// Section-13 FIX: trackUsernameChange trigger writes to userSafetyRecords on
// every username change; usernameChangeCooldownRelease (in scheduledMaintenance)
// re-enables canChangeUsername after 30 days.
__exportStar(require("./usernameChangeTracking"), exports);
// Smart Activity Layer — Followers/Following lists with precomputed activity state
// Triggers: posts/{postId}, prayers/{prayerId}, churchNotes/{noteId} writes
// Callable: markRelationshipSeen (batched seen-state flush from client)
// Scheduled: reconcileRelationshipStates (daily stale doc cleanup)
__exportStar(require("./socialGraph"), exports);
// Smart Share — ranked targets, payloads, deep links, moderation, analytics,
// notification fan-out, and queued render jobs for the AMEN custom share sheet.
__exportStar(require("./share/smartShare"), exports);
// Creator Functions
__exportStar(require("./creator/createProject"), exports);
__exportStar(require("./creator/updateProject"), exports);
__exportStar(require("./creator/deleteProject"), exports);
__exportStar(require("./creator/autosaveProject"), exports);
__exportStar(require("./creator/queueProcessingJob"), exports);
__exportStar(require("./creator/processVideoProxy"), exports);
__exportStar(require("./creator/generateThumbnail"), exports);
__exportStar(require("./creator/transcribeMedia"), exports);
__exportStar(require("./creator/generateSubtitleTrack"), exports);
__exportStar(require("./creator/translateSubtitleTrack"), exports);
__exportStar(require("./creator/buildOutputVariants"), exports);
__exportStar(require("./creator/renderExport"), exports);
__exportStar(require("./creator/publishProject"), exports);
__exportStar(require("./creator/moderateCreatorAsset"), exports);
__exportStar(require("./creator/verifyAuthenticitySignals"), exports);
__exportStar(require("./creator/saveBrandKit"), exports);
__exportStar(require("./creator/cloneTemplateToProject"), exports);
__exportStar(require("./creator/recordCreatorAnalytics"), exports);
__exportStar(require("./creator/enforceCreatorEntitlement"), exports);
__exportStar(require("./creator/cleanupOrphanedAssets"), exports);
__exportStar(require("./creator/retryFailedCreatorJob"), exports);
// Living Entries — unified notes, reminders, church follow-up, reflections
__exportStar(require("./livingEntries/livingEntryFunctions"), exports);
// Media Metadata Generation Pipeline — Phase 3
// Firestore trigger: onPostCreatedGenerateMediaMetadata (posts/{postId})
// Callable: retryMediaGeneration (retry failed generation for a media item)
// Provider: OpenAI Whisper (OPENAI_API_KEY) + Claude label refinement (ANTHROPIC_API_KEY)
__exportStar(require("./mediaGeneration/mediaMetadataPipeline"), exports);
// Berean AI Alignment + Spiritual Protection
// Rule-based pipeline classifies posts, comments, and Berean interactions for
// biblical alignment, spiritual-protection signals (grooming, trafficking,
// explicit content, coercion) and 7-deadly-sins pastoral framing.
// Callables: checkBiblicalAlignment, suggestBiblicalRewrite, saveAICorrection,
//   getDiscernmentPrompt, attachSharedKnowledgeIntegrity, voteKnowledgeIntegrity,
//   getWeeklyAlignmentSummary, updateAlignmentProfile.
// checkBiblicalAlignment, suggestBiblicalRewrite, saveAICorrection, getDiscernmentPrompt
// are owned by the default codebase (functions/index.js). Export only creator-exclusive functions.
var biblicalAlignmentFunctions_1 = require("./biblicalAlignmentFunctions");
Object.defineProperty(exports, "attachSharedKnowledgeIntegrity", { enumerable: true, get: function () { return biblicalAlignmentFunctions_1.attachSharedKnowledgeIntegrity; } });
Object.defineProperty(exports, "voteKnowledgeIntegrity", { enumerable: true, get: function () { return biblicalAlignmentFunctions_1.voteKnowledgeIntegrity; } });
Object.defineProperty(exports, "getWeeklyAlignmentSummary", { enumerable: true, get: function () { return biblicalAlignmentFunctions_1.getWeeklyAlignmentSummary; } });
Object.defineProperty(exports, "updateAlignmentProfile", { enumerable: true, get: function () { return biblicalAlignmentFunctions_1.updateAlignmentProfile; } });
// Holiday Calendar Generator — pre-generates annual observances in Firestore
// holiday_calendar/{year}/days/{yyyy-MM-dd}/observances/{holidayId}
// Scheduled: generateNextYearHolidayCalendar (Nov 1, 06:00 UTC)
// Callable:  backfillHolidayCalendar (admin-only), validateHolidayCalendarYear (admin-only)
__exportStar(require("./holidayCalendarGenerator"), exports);
// Lord's Day Rest Mode — server-side policy evaluation + AI label resolution
// Callables: evaluateRestMode, setRestModePolicy, resolvePostAILabel
// Trigger:   onRestModePolicyWritten (restModePolicies/{userId})
__exportStar(require("./restModeEvaluator"), exports);
// Covenant OS — Paid Spiritual Community Operating System
// Activity: createCovenantActivityEvent (callable, admin/server-only creation)
// Threads:  createCovenantThreadReply, generateThreadSummary
// Prayer:   createPrayerRequestFromMessage
// CatchUp:  generateCatchUpSummary (AI-powered, Claude Haiku)
// Churn:    calculateCovenantChurnRisk (scheduled daily)
// Calendar: publishScheduledCovenantContent (scheduled every 5 min)
// Reports:  submitCovenantReport (server-authoritative, financial manipulation detection)
// Search:   searchCovenantDocuments, indexCovenantPost
// Payments: createCovenantCheckoutSession (callable) — opens Stripe-hosted checkout
//           saveCovenantTierStripePriceId (callable) — creator attaches Stripe Price ID to tier
//           stripeCovenantWebhook (HTTPS) — writes members/{uid} index on subscription activation
__exportStar(require("./covenant/createCovenantActivityEvent"), exports);
__exportStar(require("./covenant/saveCovenantTierStripePriceId"), exports);
__exportStar(require("./covenant/createCovenantCheckoutSession"), exports);
// P1-5: Server-authoritative tone/safety check for covenant composer.
__exportStar(require("./covenant/validateCovenantPostSafety"), exports);
// P1-Phase-F: Community-level Save/Unsave (server-authoritative).
__exportStar(require("./covenant/setCommunitySaved"), exports);
__exportStar(require("./covenant/createCovenantThreadReply"), exports);
__exportStar(require("./covenant/generateThreadSummary"), exports);
__exportStar(require("./covenant/createPrayerRequestFromMessage"), exports);
__exportStar(require("./prayer/createPrayerRequest"), exports);
__exportStar(require("./covenant/generateCatchUpSummary"), exports);
__exportStar(require("./covenant/calculateCovenantChurnRisk"), exports);
__exportStar(require("./covenant/publishScheduledCovenantContent"), exports);
__exportStar(require("./covenant/submitCovenantReport"), exports);
__exportStar(require("./covenant/indexCovenantSearchDocument"), exports);
__exportStar(require("./covenant/stripeCovenantWebhook"), exports);
// Berean Extended Intelligence — memory, threads, translation comparison, follow-ups,
//   context linking, safety classification, preference sync
// Callables: saveBereanInsight, updateBereanMemory, deleteBereanMemory,
//   createBereanStudyThread, summarizeBereanThread, compareBibleTranslations,
//   generateBereanFollowUps, linkBereanContext, unlinkBereanContext,
//   classifyBereanSafety, updateBereanPreferences
__exportStar(require("./bereanExtended"), exports);
// Social Safety OS — 5-harm-category safety platform
// Callables: evaluateContentSafety, publishWithSafetyDecision, evaluateMessageSafety,
//   createSafetyReport, activateSextortionPanicFlow, updateTrustedContacts,
//   updateFeedControls, recordSessionBoundarySignal, submitClaimContext,
//   getRecommendationContext, requestHumanReview, resolveSafetyReview,
//   getSafetyPolicySnapshot, resetRecommendationTraining
__exportStar(require("./safetyOS"), exports);
// Creation AI — AI-powered creation assistance
// Callables: suggestCreationVerses, improveCreationCaption,
//   suggestCreationHashtags, generateCreationOutline
__exportStar(require("./creationAI"), exports);
// Church Trust & Safety OS — verification pipeline, moderation, grounding, livestream
// Callables: submitChurchVerificationRequest, submitChurchProfileUpdate,
//   reviewChurchModerationItem, refreshChurchLivestreamState, generateGroundedChurchAnswer,
//   syncYouTubeChurchStreams, updateChurchLiveSignals, moderateChurchMediaUpload
// Trigger:   onChurchVerificationReviewed
var churchTrustCallables_1 = require("./church/controllers/churchTrustCallables");
Object.defineProperty(exports, "submitChurchProfileUpdate", { enumerable: true, get: function () { return churchTrustCallables_1.submitChurchProfileUpdate; } });
Object.defineProperty(exports, "reviewChurchModerationItem", { enumerable: true, get: function () { return churchTrustCallables_1.reviewChurchModerationItem; } });
Object.defineProperty(exports, "refreshChurchLivestreamState", { enumerable: true, get: function () { return churchTrustCallables_1.refreshChurchLivestreamState; } });
Object.defineProperty(exports, "generateGroundedChurchAnswer", { enumerable: true, get: function () { return churchTrustCallables_1.generateGroundedChurchAnswer; } });
Object.defineProperty(exports, "syncYouTubeChurchStreams", { enumerable: true, get: function () { return churchTrustCallables_1.syncYouTubeChurchStreams; } });
Object.defineProperty(exports, "updateChurchLiveSignals", { enumerable: true, get: function () { return churchTrustCallables_1.updateChurchLiveSignals; } });
// Berean Operating Layer — integrated Berean AI response with full context pipeline
// Callable: generateBereanOperatingResponse
__exportStar(require("./berean/bereanOperatingLayer"), exports);
// Video Explain — AI-powered explanation of sermon/teaching video content
// Callable: explainVideoContent (Auth + App Check, transcript gate, Claude, safety filter)
// Security: server re-checks visibility, block status, flagged state before generation.
// No client writes to mediaMeta explanation fields — Firestore rules enforce this.
__exportStar(require("./explainVideoContent"), exports);
// Voice Prayer & Testimony Comments (System 32)
// Callables: createVoicePrayerUploadSession, finalizeVoicePrayerComment,
//   deleteVoicePrayerComment, reportVoicePrayerComment,
//   reactToVoicePrayerComment, getVoicePrayerPlaybackURL
// Trigger:   moderateVoicePrayerComment (Firestore onDocumentUpdated)
// Security:  Auth + App Check on all callables. Client cannot write transcript,
//   moderation, intent, spiritualContext, summary, or status.
//   All publish decisions are server-authoritative.
// Flags:     voicePrayerCommentsEnabled, voiceTestimonyCommentsEnabled (both off by default)
__exportStar(require("./voicePrayerComments"), exports);
// Spiritual OS — 10-feature Spiritual Operating System
// Feature 1: Unsent Thoughts (detectUnsentThoughtRisk, saveUnsentThought, resolveUnsentThought)
// Feature 2: Scripture Drift (analyzeScriptureDrift, generateBalancingScripture, dismissDriftSignal)
// Feature 3: Silence Intelligence (detectSilencePatterns, resurfaceAvoidedItem, markSilenceSignalResolved)
// Feature 4: Relational Gravity (updateRelationalGravity, classifyRelationshipState, generateReconciliationPrompt)
// Feature 5: Moment Interception (evaluateMomentRisk, logMomentInterception, updateMomentLearning)
// Feature 6: Post-Action Reflection (createReflectionPrompt, savePostActionReflection, updateUserGrowthPattern)
// Feature 7: Truth vs Emotion (analyzeTruthVsEmotion)
// Feature 8: Weight of Words (scoreWeightOfWords, generateGracefulRewrite)
// Feature 9: Community Discernment (aggregateDiscernmentSignals, generateCommunityDiscernmentSummary)
// Feature 10: Eternal Weight (calculateEternalWeight, updateEternalWeightAfterReflection, generateMeaningPrompt, createWalkWithChristPathFromPattern)
var spiritualOS_1 = require("./spiritualOS");
Object.defineProperty(exports, "detectUnsentThoughtRisk", { enumerable: true, get: function () { return spiritualOS_1.detectUnsentThoughtRisk; } });
Object.defineProperty(exports, "saveUnsentThought", { enumerable: true, get: function () { return spiritualOS_1.saveUnsentThought; } });
Object.defineProperty(exports, "resolveUnsentThought", { enumerable: true, get: function () { return spiritualOS_1.resolveUnsentThought; } });
Object.defineProperty(exports, "analyzeScriptureDrift", { enumerable: true, get: function () { return spiritualOS_1.analyzeScriptureDrift; } });
Object.defineProperty(exports, "generateBalancingScripture", { enumerable: true, get: function () { return spiritualOS_1.generateBalancingScripture; } });
Object.defineProperty(exports, "dismissDriftSignal", { enumerable: true, get: function () { return spiritualOS_1.dismissDriftSignal; } });
Object.defineProperty(exports, "detectSilencePatterns", { enumerable: true, get: function () { return spiritualOS_1.detectSilencePatterns; } });
Object.defineProperty(exports, "resurfaceAvoidedItem", { enumerable: true, get: function () { return spiritualOS_1.resurfaceAvoidedItem; } });
Object.defineProperty(exports, "markSilenceSignalResolved", { enumerable: true, get: function () { return spiritualOS_1.markSilenceSignalResolved; } });
Object.defineProperty(exports, "updateRelationalGravity", { enumerable: true, get: function () { return spiritualOS_1.updateRelationalGravity; } });
Object.defineProperty(exports, "classifyRelationshipState", { enumerable: true, get: function () { return spiritualOS_1.classifyRelationshipState; } });
Object.defineProperty(exports, "generateReconciliationPrompt", { enumerable: true, get: function () { return spiritualOS_1.generateReconciliationPrompt; } });
Object.defineProperty(exports, "evaluateMomentRisk", { enumerable: true, get: function () { return spiritualOS_1.evaluateMomentRisk; } });
Object.defineProperty(exports, "logMomentInterception", { enumerable: true, get: function () { return spiritualOS_1.logMomentInterception; } });
Object.defineProperty(exports, "updateMomentLearning", { enumerable: true, get: function () { return spiritualOS_1.updateMomentLearning; } });
Object.defineProperty(exports, "createReflectionPrompt", { enumerable: true, get: function () { return spiritualOS_1.createReflectionPrompt; } });
Object.defineProperty(exports, "savePostActionReflection", { enumerable: true, get: function () { return spiritualOS_1.savePostActionReflection; } });
Object.defineProperty(exports, "updateUserGrowthPattern", { enumerable: true, get: function () { return spiritualOS_1.updateUserGrowthPattern; } });
Object.defineProperty(exports, "analyzeTruthVsEmotion", { enumerable: true, get: function () { return spiritualOS_1.analyzeTruthVsEmotion; } });
Object.defineProperty(exports, "scoreWeightOfWords", { enumerable: true, get: function () { return spiritualOS_1.scoreWeightOfWords; } });
Object.defineProperty(exports, "generateGracefulRewrite", { enumerable: true, get: function () { return spiritualOS_1.generateGracefulRewrite; } });
Object.defineProperty(exports, "aggregateDiscernmentSignals", { enumerable: true, get: function () { return spiritualOS_1.aggregateDiscernmentSignals; } });
Object.defineProperty(exports, "generateCommunityDiscernmentSummary", { enumerable: true, get: function () { return spiritualOS_1.generateCommunityDiscernmentSummary; } });
Object.defineProperty(exports, "calculateEternalWeight", { enumerable: true, get: function () { return spiritualOS_1.calculateEternalWeight; } });
Object.defineProperty(exports, "updateEternalWeightAfterReflection", { enumerable: true, get: function () { return spiritualOS_1.updateEternalWeightAfterReflection; } });
Object.defineProperty(exports, "generateMeaningPrompt", { enumerable: true, get: function () { return spiritualOS_1.generateMeaningPrompt; } });
Object.defineProperty(exports, "createWalkWithChristPathFromPattern", { enumerable: true, get: function () { return spiritualOS_1.createWalkWithChristPathFromPattern; } });
// AI Usage Labels — AI disclosure labeling, tone evaluation, and usage tracking
// Callables: recordPostAIUsage, getAILabelDetail, evaluateTone
// Privacy: raw text and prompts are never stored server-side.
// Disclosure enforcement: disclosureRequired labels cannot be downgraded once set.
var aiUsageLabels_1 = require("./aiUsageLabels");
Object.defineProperty(exports, "recordPostAIUsage", { enumerable: true, get: function () { return aiUsageLabels_1.recordPostAIUsage; } });
Object.defineProperty(exports, "getAILabelDetail", { enumerable: true, get: function () { return aiUsageLabels_1.getAILabelDetail; } });
Object.defineProperty(exports, "evaluateTone", { enumerable: true, get: function () { return aiUsageLabels_1.evaluateTone; } });
// Media Moderation Pipeline — 6-layer AI safety pipeline for photos and videos
// Triggers: onPostCreatedRunMediaModeration, onPostMediaUpdatedRunModeration
// Callables: submitMediaReviewDecision, getPostModerationStatus,
//            getAccountMediaRiskScore, triggerMediaModeration
// Layers: hash check → image safety → OCR → text safety → fusion → action engine
// Raw text and media are never stored in moderation logs.
var mediaModerationPipeline_1 = require("./mediaModerationPipeline");
Object.defineProperty(exports, "onPostCreatedRunMediaModeration", { enumerable: true, get: function () { return mediaModerationPipeline_1.onPostCreatedRunMediaModeration; } });
Object.defineProperty(exports, "onPostMediaUpdatedRunModeration", { enumerable: true, get: function () { return mediaModerationPipeline_1.onPostMediaUpdatedRunModeration; } });
Object.defineProperty(exports, "submitMediaReviewDecision", { enumerable: true, get: function () { return mediaModerationPipeline_1.submitMediaReviewDecision; } });
Object.defineProperty(exports, "getPostModerationStatus", { enumerable: true, get: function () { return mediaModerationPipeline_1.getPostModerationStatus; } });
Object.defineProperty(exports, "getAccountMediaRiskScore", { enumerable: true, get: function () { return mediaModerationPipeline_1.getAccountMediaRiskScore; } });
Object.defineProperty(exports, "triggerMediaModeration", { enumerable: true, get: function () { return mediaModerationPipeline_1.triggerMediaModeration; } });
// System 27: Berean Grok Helper Pipeline
// Callables: bereanHelperSummarizePrompt, bereanHelperAnalyzeLink,
//            bereanHelperExternalContext, bereanHelperStudyOutline
__exportStar(require("./bereanHelperPipeline"), exports);
// System 28: Feed Intelligence
// Callables: submitFeedDirection, explainWhyThisPost, adjustPostRecommendationSignal,
//            getFeedIntelligenceSummary, resetFeedPreference
__exportStar(require("./feedIntelligence"), exports);
// Amen Discover
__exportStar(require("./discover"), exports);
// System 29: Liquid Glass Intelligence Layer
// Callables: defineSemanticTerm, detectSmartActions, createKnowledgeThread,
//            saveSemanticInsight, logPresenceSignal
// Auth + App Check enforced on all five. Trusted AI outputs written server-side only.
__exportStar(require("./semanticIntelligence"), exports);
// System 30: Per-Media Captions
// Callables: validateMediaCaptions, updatePostMediaCaptions
__exportStar(require("./validateMediaCaptions"), exports);
// System 32: Communication OS — Next-Gen Messaging + Group Discussions
// Callables: generateDMCatchUp, extractThreadDecisions, detectOpenQuestions,
//            extractThreadActions, generateGroupPulse, generateMediaContext,
//            searchConversationMemory, generateSmartReplies
// All callables require Auth + App Check. Participant membership verified server-side.
// AI outputs marked as "suggested" — never fabricate owners, deadlines, or consensus.
__exportStar(require("./messaging/generateDMCatchUp"), exports);
__exportStar(require("./messaging/extractThreadDecisions"), exports);
__exportStar(require("./messaging/detectOpenQuestions"), exports);
__exportStar(require("./messaging/extractThreadActions"), exports);
__exportStar(require("./messaging/generateGroupPulse"), exports);
__exportStar(require("./messaging/generateMediaContext"), exports);
__exportStar(require("./messaging/privateMessageActions"), exports);
__exportStar(require("./messaging/productionIntelligenceActions"), exports);
__exportStar(require("./messaging/searchConversationMemory"), exports);
__exportStar(require("./messaging/generateSmartReplies"), exports);
// Amen Startup Drop Intelligence Layer
__exportStar(require("./realtime/createRealtimeSession"), exports);
__exportStar(require("./realtime/endRealtimeSession"), exports);
__exportStar(require("./realtime/logRealtimeVoiceEvent"), exports);
__exportStar(require("./realtime/moderateRealtimeTranscript"), exports);
__exportStar(require("./berean/translation/translateMultilingualContent"), exports);
__exportStar(require("./berean/scripture/resolveScriptureReferences"), exports);
__exportStar(require("./berean/transcripts/persistRealtimeTranscriptChunk"), exports);
__exportStar(require("./media/startRealtimeTranscription"), exports);
__exportStar(require("./media/finalizeTranscript"), exports);
__exportStar(require("./media/extractKeyMoments"), exports);
__exportStar(require("./media/moderateTranscript"), exports);
__exportStar(require("./translation/createTranslationSession"), exports);
__exportStar(require("./translation/saveTranslatedTranscript"), exports);
__exportStar(require("./translation/moderateTranslationOutput"), exports);
__exportStar(require("./graphics/generateAmenGraphic"), exports);
__exportStar(require("./graphics/editAmenGraphic"), exports);
__exportStar(require("./graphics/moderateGraphicPrompt"), exports);
__exportStar(require("./graphics/saveGeneratedGraphic"), exports);
__exportStar(require("./agents/runAmenAgentTask"), exports);
__exportStar(require("./agents/agentTaskRouter"), exports);
__exportStar(require("./agents/agentGuardrails"), exports);
__exportStar(require("./agents/agentObservability"), exports);
__exportStar(require("./agents/agentResultFormatter"), exports);
__exportStar(require("./amenAI/draftLifecycle"), exports);
__exportStar(require("./churchNotes/createChurchNotesAIDraft"), exports);
// Church Notes Media Intelligence — processing jobs, OCR, audio, content generation, draft approval
__exportStar(require("./churchNotes/churchNotesProcessingJobs"), exports);
__exportStar(require("./churchNotes/churchNotesAudioProcessing"), exports);
__exportStar(require("./churchNotes/churchNotesImageOCR"), exports);
__exportStar(require("./churchNotes/churchNotesContentGeneration"), exports);
__exportStar(require("./churchNotes/churchNotesDraftApproval"), exports);
__exportStar(require("./churchNotes/churchNotesExtendedCallables"), exports);
__exportStar(require("./churchNotes/churchNotesPrivacyAudit"), exports);
// Social OS — Media Provenance and Authenticity
// registerMediaProvenance, createMediaSession, completeMediaSession, saveToMediaQueue,
// updateMediaProgress, reportMedia, and getMediaTrustContext are all owned by the
// default codebase (functions/index.js). No re-exports here.
// In-App Giving — server-side Stripe charge (Apple Pay + card tokenization)
__exportStar(require("./giving/processGivingCharge"), exports);
__exportStar(require("./giving/analyzePostTrustLogoMatch"), exports);
// Creator Spaces OS — Community AI, Events, Livestream AI, Monetization, Discovery, Legal, Mentorship, Discussions
// Built: 2026-06-04
__exportStar(require("./spaces/communityAI"), exports);
__exportStar(require("./spaces/eventBroadcast"), exports);
__exportStar(require("./spaces/livestreamAI"), exports);
__exportStar(require("./spaces/monetizationExt"), exports);
__exportStar(require("./spaces/discoveryAndLegal"), exports);
__exportStar(require("./spaces/mentorship"), exports);
__exportStar(require("./spaces/discussionAI"), exports);
// Space lifecycle — deleteSpace callable (host-only hard delete + subcollection cascade)
// Cleans up spaces/{spaceId}/members, events, announcements on space deletion.
__exportStar(require("./spaces/spaceLifecycle"), exports);
// Living Intelligence — GLOBAL Tier (Agent 5: World Events as Christian Response)
// Callables: getGlobalIntelligenceCards, submitWorldEvent
// Utilities: generateWorldResponse (worldResponseEngine), buildGlobalCard (globalCardBuilder)
// Rules enforced: source required, DEVELOPING never top, lament frame for disaster/conflict/persecution,
//   actions restricted to PRAY | GIVE | SHOW_UP | DISCUSS, fail-closed on AI unavailability.
var worldEventsFunctions_1 = require("./intelligence/worldEventsFunctions");
Object.defineProperty(exports, "getGlobalIntelligenceCards", { enumerable: true, get: function () { return worldEventsFunctions_1.getGlobalIntelligenceCards; } });
Object.defineProperty(exports, "submitWorldEvent", { enumerable: true, get: function () { return worldEventsFunctions_1.submitWorldEvent; } });
var worldResponseEngine_1 = require("./intelligence/worldResponseEngine");
Object.defineProperty(exports, "generateWorldResponse", { enumerable: true, get: function () { return worldResponseEngine_1.generateWorldResponse; } });
var globalCardBuilder_1 = require("./intelligence/globalCardBuilder");
Object.defineProperty(exports, "buildGlobalCard", { enumerable: true, get: function () { return globalCardBuilder_1.buildGlobalCard; } });
// Living Intelligence — Church Pulse Subsystem
// Scheduled: refreshChurchPulses (every 6 hours, verified churches only)
// Callable: getChurchPulseForUser — auth required, returns ChurchPulseData
// Callable: buildChurchPulseCard — auth required, returns IntelligenceCard shape
// Writes: church_pulse/{churchId} — server-write-only, no fabricated scores
// Built: 2026-06-05
__exportStar(require("./intelligence/churchPulseFunctions"), exports);
// Living Intelligence — Core Engine (Agent 1)
// amenRouting.ts:       callModel abstraction + moderateContent (fail-closed)
// formationGovernor.ts: enforces all FORMATION_INVARIANTS synchronously
// rankingEngine.ts:     Ranking Brain — computes rankScore + rankReasons per card
// opportunityGraph.ts:  OpportunityNode store + supply↔demand matcher
// digestBuilder.ts:     Scheduled 2x/day digest builder + admin manual trigger
//
// Scheduled: buildIntelligenceBriefs (every 12 hours)
// Callable:  triggerIntelligenceBriefForUser (admin-only, testing/manual trigger)
// Writes:    intelligence_cards/{cardId}, users/{uid}/intelligence_brief/current
// Built: 2026-06-05
var digestBuilder_1 = require("./intelligence/digestBuilder");
Object.defineProperty(exports, "buildIntelligenceBriefs", { enumerable: true, get: function () { return digestBuilder_1.buildIntelligenceBriefs; } });
Object.defineProperty(exports, "triggerIntelligenceBriefForUser", { enumerable: true, get: function () { return digestBuilder_1.triggerIntelligenceBriefForUser; } });
// Living Intelligence — Agent 3: Event Matching + Prayer Graph + Need Detection
// Built: 2026-06-05
// Callables: matchEventsForUser, matchPrayerSupport, classifyPostNeed, matchNeedsToVolunteers
// Triggers: onPrayerCreated (classifies prayerNeedType on new prayers)
var eventMatcher_1 = require("./intelligence/eventMatcher");
Object.defineProperty(exports, "matchEventsForUser", { enumerable: true, get: function () { return eventMatcher_1.matchEventsForUser; } });
var prayerGraphService_1 = require("./intelligence/prayerGraphService");
Object.defineProperty(exports, "matchPrayerSupport", { enumerable: true, get: function () { return prayerGraphService_1.matchPrayerSupport; } });
Object.defineProperty(exports, "onPrayerCreated", { enumerable: true, get: function () { return prayerGraphService_1.onPrayerCreated; } });
var needDetector_1 = require("./intelligence/needDetector");
Object.defineProperty(exports, "classifyPostNeed", { enumerable: true, get: function () { return needDetector_1.classifyPostNeed; } });
Object.defineProperty(exports, "matchNeedsToVolunteers", { enumerable: true, get: function () { return needDetector_1.matchNeedsToVolunteers; } });
// Sabbath Mode — mandatory weekly rest; formation over engagement
// Callables: evaluateSabbathMode, setSabbathPreference, syncFamilySabbathPresence
// Trigger:   onSabbathNotificationWrite (holds non-essential pushes during active Sabbath)
// Collections: users/{uid}/sabbath/config, sabbathSessions/{date}, sabbathReflections/{id}
// Minor gate enforced: any minor account path returns MINOR_GATE_REQUIRED
// Built: 2026-06-07
var evaluateSabbathMode_1 = require("./sabbath/evaluateSabbathMode");
Object.defineProperty(exports, "evaluateSabbathMode", { enumerable: true, get: function () { return evaluateSabbathMode_1.evaluateSabbathMode; } });
var setSabbathPreference_1 = require("./sabbath/setSabbathPreference");
Object.defineProperty(exports, "setSabbathPreference", { enumerable: true, get: function () { return setSabbathPreference_1.setSabbathPreference; } });
var familySabbathSync_1 = require("./sabbath/familySabbathSync");
Object.defineProperty(exports, "syncFamilySabbathPresence", { enumerable: true, get: function () { return familySabbathSync_1.syncFamilySabbathPresence; } });
var notificationBatcher_1 = require("./sabbath/notificationBatcher");
Object.defineProperty(exports, "onSabbathNotificationWrite", { enumerable: true, get: function () { return notificationBatcher_1.onSabbathNotificationWrite; } });
// LiveKit Video — short-lived JWT token generator for live A/V rooms.
// Callables: generateLiveKitToken (primary), getLivekitToken (alias for iOS client)
// Secrets required: LIVEKIT_API_KEY, LIVEKIT_API_SECRET, LIVEKIT_SERVER_URL
// Built: 2026-06-07
var generateLiveKitToken_1 = require("./generateLiveKitToken");
Object.defineProperty(exports, "generateLiveKitToken", { enumerable: true, get: function () { return generateLiveKitToken_1.generateLiveKitToken; } });
Object.defineProperty(exports, "getLivekitToken", { enumerable: true, get: function () { return generateLiveKitToken_1.getLivekitToken; } });
// Space Events — RSVP callable for Spaces event attendance
__exportStar(require("./spaces/spaceEvents"), exports);
// Covenant Membership Verification — server-authoritative active-membership check
__exportStar(require("./covenant/verifyCovenantMembership"), exports);
// Prayer Recap — weekly prayer summary generation for the calling user
__exportStar(require("./prayer/generatePrayerRecap"), exports);
//# sourceMappingURL=index.js.map