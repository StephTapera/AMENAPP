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
exports.shouldSkipPostPreviewUpdate = exports.shouldRefreshPreviewAvatars = exports.denormalizePreviewCandidates = exports.passesPreviewModeration = exports.generateBereanInsightCandidate = exports.countVisibleCommunityMatches = exports.selectFollowedReplyFromRelationships = exports.hasStrongRelationship = exports.selectFollowedReplyCandidate = exports.detectCommunityPulse = exports.scheduledReplyPreviewRefresh = exports.refreshDynamicReplyPreviews = exports.onUserProfileImageUpdatedRefreshPreviews = exports.onBlockRelationshipUpdatedRefreshPreviewsTrigger = exports.onBlockRelationshipUpdatedRefreshPreviews = exports.onPostDeletedClearPreviewsTrigger = exports.onPostDeletedClearPreviews = exports.onPostPreviewDirtyRebuild = exports.onPostUpdatedUpdatePreviewsTrigger = exports.onPostUpdatedUpdatePreviews = exports.onCommentUpdatedUpdatePreviewsTrigger = exports.onCommentUpdatedUpdatePreviews = exports.onCommentDeletedUpdatePreviews = exports.onCommentCreatedUpdatePreviews = exports.attachCommunityHubPreviewToPost = exports.indexPostIntoHub = exports.reportHubContent = exports.muteObjectHub = exports.recordObjectInteraction = exports.getRelatedObjectHubs = exports.getObjectHub = exports.createOrJoinObjectHub = exports.resolveCommunityObject = exports.scheduledSmartMessageVectorBackfill = exports.getSmartMessageVectorIndexStatus = exports.backfillSmartMessageVectorIndex = exports.indexSmartPrayerRequest = exports.buildKnowledgeGraphMemory = exports.transcribeVoiceMessage = exports.startSmartStudyMode = exports.semanticSearchAmenSpace = exports.extractDiscussionTopics = exports.getContextualBereanActions = exports.summarizeDiscussion = exports.detectPrayerRequest = exports.detectSmartDateEvents = exports.detectScriptureReferences = exports.analyzeSmartMessage = exports.perspectiveApiKey = exports.anthropicApiKey = void 0;
exports.onPostCreatedRunMediaModeration = exports.evaluateTone = exports.getAILabelDetail = exports.recordPostAIUsage = exports.createWalkWithChristPathFromPattern = exports.generateMeaningPrompt = exports.updateEternalWeightAfterReflection = exports.calculateEternalWeight = exports.generateCommunityDiscernmentSummary = exports.aggregateDiscernmentSignals = exports.generateGracefulRewrite = exports.scoreWeightOfWords = exports.analyzeTruthVsEmotion = exports.updateUserGrowthPattern = exports.savePostActionReflection = exports.createReflectionPrompt = exports.updateMomentLearning = exports.logMomentInterception = exports.evaluateMomentRisk = exports.generateReconciliationPrompt = exports.classifyRelationshipState = exports.updateRelationalGravity = exports.markSilenceSignalResolved = exports.resurfaceAvoidedItem = exports.detectSilencePatterns = exports.dismissDriftSignal = exports.generateBalancingScripture = exports.analyzeScriptureDrift = exports.resolveUnsentThought = exports.saveUnsentThought = exports.detectUnsentThoughtRisk = exports.updateChurchLiveSignals = exports.syncYouTubeChurchStreams = exports.generateGroundedChurchAnswer = exports.refreshChurchLivestreamState = exports.reviewChurchModerationItem = exports.submitChurchProfileUpdate = exports.dailyAgeTierPromotion = exports.onUserWrite = exports.setDateOfBirth = exports.resolvePermissionsCallable = exports.confirmGuardianConsent = exports.requestGuardianConsent = exports.initiateDM = exports.setMode = exports.seedChurchData = exports.rebuildReplyPreviewsOnDirty = exports.rebuildReplyPreviews = exports.onReplyCreate = exports.recordPreviewImpression = void 0;
exports.issueChurchVerificationCode = exports.requestChurchVerification = exports.getMyMentorships = exports.endMentorship = exports.approveMentorship = exports.requestMentorship = exports.scanCoordinatedHarassment = exports.scanGroomingVelocity = exports.initializeModeForNewUser = exports.enforcePostModeConstraints = exports.getInteractionMode = exports.setInteractionMode = exports.initializeNewAccount = exports.adminGrantTrustEvent = exports.getTrustProfile = exports.getMyReports = exports.reportAbuse = exports.getAuditSummary = exports.queryAuditLog = exports.searchEvidenceByUser = exports.markEvidenceProvided = exports.getEvidenceRecord = exports.preserveEvidenceCallable = exports.checkQueueSLABreaches = exports.getReviewQueue = exports.resolveReviewItem = exports.claimReviewItem = exports.autoIssueStrikeOnBlock = exports.adminGetTrustProfile = exports.adminIssueStrike = exports.forwardYouthAlertToGuardians = exports.approveContactForMinor = exports.revokeGuardianConnection = exports.approveGuardianConnection = exports.requestGuardianConnection = exports.enforceYouthAccountDefaults = exports.updateYouthSettings = exports.checkYouthSafetyCallable = exports.checkLinkSafetyCallable = exports.moderateAudioCallable = exports.moderateVideoCallable = exports.moderateImageCallable = exports.moderateTextCallable = exports.registerMediaProvenance = exports.validateMediaCaptions = exports.triggerMediaModeration = exports.getAccountMediaRiskScore = exports.getPostModerationStatus = exports.submitMediaReviewDecision = exports.onPostMediaUpdatedRunModeration = void 0;
exports.generateAltText = exports.publishPostWithMedia = exports.moderateMediaCaption = exports.queryTrustSafetyAuditLog = exports.resolveAppeal = exports.submitAppeal = exports.getEnforcementProfile = exports.issueEnforcementStrike = exports.escalateAbuseReport = exports.resolveAbuseReport = exports.getMyAbuseReports = exports.submitAbuseReport = exports.markContentTrendIneligible = exports.computeRankingScore = exports.updateCreatorTrustDeclaration = exports.flagSuspectedImpersonation = exports.setChurchVerificationStatus = exports.getIdentityTrustProfile = exports.getBotProfile = exports.evaluateBotScore = exports.getMediaProvenance = exports.runAudioPreflight = exports.runVideoPreflight = exports.runImagePreflight = exports.runTextPreflight = exports.getChurchVerificationStatus = void 0;
const admin = __importStar(require("firebase-admin"));
const params_1 = require("firebase-functions/params");
if (!admin.apps.length) {
    admin.initializeApp();
}
// Secrets — declared here so Functions v2 binds them at deploy time.
// Use: process.env.ANTHROPIC_API_KEY (populated automatically for functions that reference this)
exports.anthropicApiKey = (0, params_1.defineSecret)("ANTHROPIC_API_KEY");
exports.perspectiveApiKey = (0, params_1.defineSecret)("PERSPECTIVE_API_KEY");
// AI Proxy Functions
__exportStar(require("./bereanChatProxy"), exports);
__exportStar(require("./bereanChatProxyStream"), exports); // True SSE streaming proxy
__exportStar(require("./openAIProxy"), exports);
__exportStar(require("./whisperProxy"), exports);
__exportStar(require("./generateDailyVerse"), exports);
__exportStar(require("./amenDaily/getAmenDailyDigest"), exports);
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
__exportStar(require("./contextual/contextualActionRouter"), exports);
var smartMessageRouter_1 = require("./smartMessageIntelligence/smartMessageRouter");
Object.defineProperty(exports, "analyzeSmartMessage", { enumerable: true, get: function () { return smartMessageRouter_1.analyzeSmartMessage; } });
Object.defineProperty(exports, "detectScriptureReferences", { enumerable: true, get: function () { return smartMessageRouter_1.detectScriptureReferences; } });
Object.defineProperty(exports, "detectSmartDateEvents", { enumerable: true, get: function () { return smartMessageRouter_1.detectSmartDateEvents; } });
Object.defineProperty(exports, "detectPrayerRequest", { enumerable: true, get: function () { return smartMessageRouter_1.detectPrayerRequest; } });
Object.defineProperty(exports, "summarizeDiscussion", { enumerable: true, get: function () { return smartMessageRouter_1.summarizeDiscussion; } });
Object.defineProperty(exports, "getContextualBereanActions", { enumerable: true, get: function () { return smartMessageRouter_1.getContextualBereanActions; } });
Object.defineProperty(exports, "extractDiscussionTopics", { enumerable: true, get: function () { return smartMessageRouter_1.extractDiscussionTopics; } });
Object.defineProperty(exports, "semanticSearchAmenSpace", { enumerable: true, get: function () { return smartMessageRouter_1.semanticSearchAmenSpace; } });
Object.defineProperty(exports, "startSmartStudyMode", { enumerable: true, get: function () { return smartMessageRouter_1.startSmartStudyMode; } });
Object.defineProperty(exports, "transcribeVoiceMessage", { enumerable: true, get: function () { return smartMessageRouter_1.transcribeVoiceMessage; } });
Object.defineProperty(exports, "buildKnowledgeGraphMemory", { enumerable: true, get: function () { return smartMessageRouter_1.buildKnowledgeGraphMemory; } });
Object.defineProperty(exports, "indexSmartPrayerRequest", { enumerable: true, get: function () { return smartMessageRouter_1.indexSmartPrayerRequest; } });
Object.defineProperty(exports, "backfillSmartMessageVectorIndex", { enumerable: true, get: function () { return smartMessageRouter_1.backfillSmartMessageVectorIndex; } });
Object.defineProperty(exports, "getSmartMessageVectorIndexStatus", { enumerable: true, get: function () { return smartMessageRouter_1.getSmartMessageVectorIndexStatus; } });
Object.defineProperty(exports, "scheduledSmartMessageVectorBackfill", { enumerable: true, get: function () { return smartMessageRouter_1.scheduledSmartMessageVectorBackfill; } });
// Selah Media OS (System 18)
__exportStar(require("./selahMedia"), exports);
// Selah Bible Engine — Study sheet, verse theme classification, safety classification
__exportStar(require("./selah/index"), exports);
// Smart Media Attachments (System 22)
// resolveSmartAttachment, saveMediaGraphItem, getRecentMediaAttachments, getSavedMediaItems
__exportStar(require("./smartAttachments"), exports);
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
Object.defineProperty(exports, "attachCommunityHubPreviewToPost", { enumerable: true, get: function () { return communityHubs_1.attachCommunityHubPreviewToPost; } });
// Accessibility Intelligence Layer
__exportStar(require("./refineTranslation"), exports);
__exportStar(require("./transformContent"), exports);
// Group Link Functions
__exportStar(require("./groupLinks"), exports);
__exportStar(require("./resolveOrCreateConversation"), exports);
// Suggested Accounts Rail
__exportStar(require("./suggestedAccounts"), exports);
// UserProfileMini context callable
__exportStar(require("./profileMini/getUserProfileMiniContext"), exports);
// Creator Spaces — trusted media, provenance, daily portion, and memory graph callables
__exportStar(require("./creatorSpaces"), exports);
// Amen Spatial Rooms OS — server-authoritative creation, theme generation, and backfill.
__exportStar(require("./spatialRooms"), exports);
// Trust + Intelligence (Berean infrastructure)
__exportStar(require("./trustIntelligence"), exports);
__exportStar(require("./profileBanners"), exports);
__exportStar(require("./amenConnect"), exports);
__exportStar(require("./spaces"), exports);
__exportStar(require("./amenSpacesDiscovery"), exports);
__exportStar(require("./amenSpaceBanners"), exports);
__exportStar(require("./amenNationalDirectory"), exports);
__exportStar(require("./legacyAiSafetyBridge"), exports);
__exportStar(require("./integrations"), exports);
// Action Threads — server-authoritative care workflow CRUD
// All state transitions and participant invitations are validated server-side.
__exportStar(require("./actionThreads"), exports);
// Private/Follower Feed Builder
__exportStar(require("./feedBuilder"), exports);
__exportStar(require("./postReactions"), exports);
__exportStar(require("./postCountTriggers"), exports);
// Smart Context Label scoring, ranking, feedback, and preference sync
__exportStar(require("./feedContext"), exports);
__exportStar(require("./bereanPulse"), exports);
// Dynamic Reply Preview system — server-ranked inline PostCard preview candidates
// onReplyCreate and rebuildReplyPreviews are intentionally omitted here; the
// CONTRACT.md-authoritative versions are exported from ./replyPreview below.
var generateDynamicReplyPreviews_1 = require("./generateDynamicReplyPreviews");
Object.defineProperty(exports, "onCommentCreatedUpdatePreviews", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.onCommentCreatedUpdatePreviews; } });
Object.defineProperty(exports, "onCommentDeletedUpdatePreviews", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.onCommentDeletedUpdatePreviews; } });
Object.defineProperty(exports, "onCommentUpdatedUpdatePreviews", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.onCommentUpdatedUpdatePreviews; } });
Object.defineProperty(exports, "onCommentUpdatedUpdatePreviewsTrigger", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.onCommentUpdatedUpdatePreviewsTrigger; } });
Object.defineProperty(exports, "onPostUpdatedUpdatePreviews", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.onPostUpdatedUpdatePreviews; } });
Object.defineProperty(exports, "onPostUpdatedUpdatePreviewsTrigger", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.onPostUpdatedUpdatePreviewsTrigger; } });
Object.defineProperty(exports, "onPostPreviewDirtyRebuild", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.onPostPreviewDirtyRebuild; } });
Object.defineProperty(exports, "onPostDeletedClearPreviews", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.onPostDeletedClearPreviews; } });
Object.defineProperty(exports, "onPostDeletedClearPreviewsTrigger", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.onPostDeletedClearPreviewsTrigger; } });
Object.defineProperty(exports, "onBlockRelationshipUpdatedRefreshPreviews", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.onBlockRelationshipUpdatedRefreshPreviews; } });
Object.defineProperty(exports, "onBlockRelationshipUpdatedRefreshPreviewsTrigger", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.onBlockRelationshipUpdatedRefreshPreviewsTrigger; } });
Object.defineProperty(exports, "onUserProfileImageUpdatedRefreshPreviews", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.onUserProfileImageUpdatedRefreshPreviews; } });
Object.defineProperty(exports, "refreshDynamicReplyPreviews", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.refreshDynamicReplyPreviews; } });
Object.defineProperty(exports, "scheduledReplyPreviewRefresh", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.scheduledReplyPreviewRefresh; } });
Object.defineProperty(exports, "detectCommunityPulse", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.detectCommunityPulse; } });
Object.defineProperty(exports, "selectFollowedReplyCandidate", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.selectFollowedReplyCandidate; } });
Object.defineProperty(exports, "hasStrongRelationship", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.hasStrongRelationship; } });
Object.defineProperty(exports, "selectFollowedReplyFromRelationships", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.selectFollowedReplyFromRelationships; } });
Object.defineProperty(exports, "countVisibleCommunityMatches", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.countVisibleCommunityMatches; } });
Object.defineProperty(exports, "generateBereanInsightCandidate", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.generateBereanInsightCandidate; } });
Object.defineProperty(exports, "passesPreviewModeration", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.passesPreviewModeration; } });
Object.defineProperty(exports, "denormalizePreviewCandidates", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.denormalizePreviewCandidates; } });
Object.defineProperty(exports, "shouldRefreshPreviewAvatars", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.shouldRefreshPreviewAvatars; } });
Object.defineProperty(exports, "shouldSkipPostPreviewUpdate", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.shouldSkipPostPreviewUpdate; } });
Object.defineProperty(exports, "recordPreviewImpression", { enumerable: true, get: function () { return generateDynamicReplyPreviews_1.recordPreviewImpression; } });
// CONTRACT.md §12 — authoritative onReplyCreate + rebuildReplyPreviews
// Implements resolver ladder (§13), scoring formula (§15), dirty thresholds (§16).
var replyPreview_1 = require("./replyPreview");
Object.defineProperty(exports, "onReplyCreate", { enumerable: true, get: function () { return replyPreview_1.onReplyCreate; } });
Object.defineProperty(exports, "rebuildReplyPreviews", { enumerable: true, get: function () { return replyPreview_1.rebuildReplyPreviews; } });
Object.defineProperty(exports, "rebuildReplyPreviewsOnDirty", { enumerable: true, get: function () { return replyPreview_1.rebuildReplyPreviewsOnDirty; } });
__exportStar(require("./churchDiscoveryPhase2"), exports);
__exportStar(require("./churchDiscoveryPhase3"), exports);
__exportStar(require("./churchDiscovery"), exports);
// Smart Community Search — Ask Amen (System: Smart Finder)
__exportStar(require("./smartCommunitySearch"), exports);
__exportStar(require("./smartChurchSearch"), exports);
// Church seed data (admin-only callable — run once per environment)
var seedChurches_1 = require("./seedChurches");
Object.defineProperty(exports, "seedChurchData", { enumerable: true, get: function () { return seedChurches_1.seedChurchData; } });
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
// 5.4 FIX — Prayer answered fan-out: processes ≤100 supporter batches per
// invocation, eliminating the timeout risk of sequential single-function fan-out.
__exportStar(require("./notifications/prayerAnsweredBatch"), exports);
// 5.6 FIX — Quiet hours digest: scheduled every 30 min to batch-deliver push
// notifications to users whose quiet window has ended.
__exportStar(require("./notifications/deliverQuietHoursDigest"), exports);
// Church Visit Lifecycle — phase-triggered follow-up scheduling and FCM nudges
// Triggered on attended/reflected phase transitions in users/{uid}/churchInteractions/{churchId}
__exportStar(require("./churchVisitLifecycle"), exports);
// Amen Intelligence Fabric — server-authoritative trust, safety, crisis,
// moderation, and reputation decisions derived from client/context snapshots.
__exportStar(require("./amenIntelligenceFabric"), exports);
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
// Universal Content + Create foundations. Existing post/comment/note flows
// remain canonical until Remote Config enables the new surfaces.
__exportStar(require("./universalContent/contentNodeFunctions"), exports);
__exportStar(require("./universalContent/platformFunctions"), exports);
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
__exportStar(require("./biblicalAlignmentFunctions"), exports);
// Holiday Calendar Generator — pre-generates annual observances in Firestore
// holiday_calendar/{year}/days/{yyyy-MM-dd}/observances/{holidayId}
// Scheduled: generateNextYearHolidayCalendar (Nov 1, 06:00 UTC)
// Callable:  backfillHolidayCalendar (admin-only), validateHolidayCalendarYear (admin-only)
__exportStar(require("./holidayCalendarGenerator"), exports);
// Permissions Engine — single source of truth for what each account may do.
// Derives effective PermissionSet from ageTier × identityMode × trustLevel × accountState.
// Resolution: intersect(ceiling, modeGrant) → applyTrustModifiers → applyHardOverrides.
//
// Callables:
//   setDateOfBirth         — records DOB, derives ageTier (teen/adult), triggers recompute
//   setMode                — validate + update identityMode + recompute PermissionSet
//   initiateDM             — pairwise canMessage() check before opening a conversation
//   requestGuardianConsent  — initiates guardian consent flow (future under-13 support)
//   confirmGuardianConsent  — guardian confirms link (7-day TTL), child permissions recomputed
//   resolvePermissionsCallable — admin-only debug/remediation
//
// Triggers:
//   onUserWrite           — recomputes on any watched field change in users/{uid}
//   dailyAgeTierPromotion — promotes tier on birthday, forces token refresh
var permissionsCallables_1 = require("./permissions/permissionsCallables");
Object.defineProperty(exports, "setMode", { enumerable: true, get: function () { return permissionsCallables_1.setMode; } });
Object.defineProperty(exports, "initiateDM", { enumerable: true, get: function () { return permissionsCallables_1.initiateDM; } });
Object.defineProperty(exports, "requestGuardianConsent", { enumerable: true, get: function () { return permissionsCallables_1.requestGuardianConsent; } });
Object.defineProperty(exports, "confirmGuardianConsent", { enumerable: true, get: function () { return permissionsCallables_1.confirmGuardianConsent; } });
Object.defineProperty(exports, "resolvePermissionsCallable", { enumerable: true, get: function () { return permissionsCallables_1.resolvePermissionsCallable; } });
Object.defineProperty(exports, "setDateOfBirth", { enumerable: true, get: function () { return permissionsCallables_1.setDateOfBirth; } });
var permissionsTriggers_1 = require("./permissions/permissionsTriggers");
Object.defineProperty(exports, "onUserWrite", { enumerable: true, get: function () { return permissionsTriggers_1.onUserWrite; } });
Object.defineProperty(exports, "dailyAgeTierPromotion", { enumerable: true, get: function () { return permissionsTriggers_1.dailyAgeTierPromotion; } });
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
var validateMediaCaptions_1 = require("./validateMediaCaptions");
Object.defineProperty(exports, "validateMediaCaptions", { enumerable: true, get: function () { return validateMediaCaptions_1.validateMediaCaptions; } });
// System 32: Communication OS — Next-Gen Messaging + Group Discussions
// Callables: generateDMCatchUp/generateCatchUpDigest, extractThreadDecisions, detectOpenQuestions,
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
__exportStar(require("./amenAI/modelRouter"), exports);
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
// createMediaSession, completeMediaSession, saveToMediaQueue, updateMediaProgress,
// reportMedia, and getMediaTrustContext are owned by the default codebase (healthyImmersiveMedia.js).
var registerMediaProvenance_1 = require("./media/registerMediaProvenance");
Object.defineProperty(exports, "registerMediaProvenance", { enumerable: true, get: function () { return registerMediaProvenance_1.registerMediaProvenance; } });
// In-App Giving — server-side Stripe charge (Apple Pay + card tokenization)
__exportStar(require("./giving/processGivingCharge"), exports);
__exportStar(require("./giving/analyzePostTrustLogoMatch"), exports);
// Calm Control OS — privacy settings, feed controls, notification eligibility, inactivity management
// Callables: updatePrivacySettings, updateFeedControls, updateNotificationSettings,
//            evaluateNotificationEligibility, restoreUserAfterInactivity
// Scheduled: pauseInactiveUserNotifications (every 24 hours)
__exportStar(require("./calmControl"), exports);
// Unimplemented stubs — iOS-callable functions not yet fully built.
// All return HttpsError("failed-precondition") so callers receive a structured error.
// Replace each stub with a real implementation when the feature ships.
__exportStar(require("./stubs/missingFunctions"), exports);
// Spiritual Rhythm OS — streak tracking, verse candidates, spiritual digests
// Callables: recordSpiritualActivity, recoverStreak,
//            generateDailyVerseCandidate, generateSpiritualDigest
__exportStar(require("./spiritualRhythm"), exports);
// Amen Access Passes (System 37) — QR / NFC / universal link / share-link access
// Callables: createAccessPass, resolveAccessPass, acceptAccessPass, revokeAccessPass,
//   pauseAccessPass, resumeAccessPass, rotateAccessPassToken, approveAccessRequest,
//   denyAccessRequest, listAccessPassesForTarget, listAccessRequestsForTarget
// Auth + App Check enforced. tokenHash never leaves the server; rawToken in URLs only.
__exportStar(require("./accessPasses"), exports);
// Verification & Trust System — identity, organization, role, creator verification
// Callables: startIdentityVerification, requestOrganizationVerification,
//   verifyOrganizationDomain, requestRoleVerification, approveRoleVerification,
//   revokeRoleVerification, requestCreatorVerification, refreshVerificationSummary,
//   reportImpersonation
// Webhook: handleIdentityVerificationWebhook (HTTPS onRequest, HMAC-verified)
// Security: Auth + App Check on all callables. No raw ID data stored.
//   Verification truth fields are backend-only writes (Admin SDK).
__exportStar(require("./verification/index"), exports);
// ─── Amen Safety OS — Full Trust & Safety Stack ───────────────────────────────
//
// AmenSafetyPolicy   — canonical policy catalog (50+ harm categories → enforcement)
// TextModerationService — Perspective API + deterministic banned-term pipeline
// ImageModerationService — Cloud Vision SafeSearch + CSAM hash check
// VideoModerationService — frame sampling + SafeSearch moderation
// AudioModerationService — Whisper transcription + text moderation
// LinkSafetyService  — Safe Browsing API + domain blocklist + heuristics
// YouthSafetyService — minor account defaults, age-gating, DM restrictions
// GuardianConnectionService — parent/guardian connection and safety alerts
// TrustAndStrikeService — strike tracking, trust score, account threshold actions
// HumanReviewQueueService — claim/resolve workflow + SLA monitoring
// EvidencePreservationService — immutable evidence storage for severe cases
// ModerationAuditLogService — immutable audit log writes and moderator queries
//
// All callables: Auth + App Check enforced.
// All moderation decisions enforce moderationStatus lifecycle:
//   pending → approved | blocked | needs_human_review | escalated | removed_after_publish
// Feeds and search MUST only read content where moderationStatus == "approved".
var TextModerationService_1 = require("./safety/TextModerationService");
Object.defineProperty(exports, "moderateTextCallable", { enumerable: true, get: function () { return TextModerationService_1.moderateTextCallable; } });
var ImageModerationService_1 = require("./safety/ImageModerationService");
Object.defineProperty(exports, "moderateImageCallable", { enumerable: true, get: function () { return ImageModerationService_1.moderateImageCallable; } });
var VideoModerationService_1 = require("./safety/VideoModerationService");
Object.defineProperty(exports, "moderateVideoCallable", { enumerable: true, get: function () { return VideoModerationService_1.moderateVideoCallable; } });
var AudioModerationService_1 = require("./safety/AudioModerationService");
Object.defineProperty(exports, "moderateAudioCallable", { enumerable: true, get: function () { return AudioModerationService_1.moderateAudioCallable; } });
var LinkSafetyService_1 = require("./safety/LinkSafetyService");
Object.defineProperty(exports, "checkLinkSafetyCallable", { enumerable: true, get: function () { return LinkSafetyService_1.checkLinkSafetyCallable; } });
var YouthSafetyService_1 = require("./safety/YouthSafetyService");
Object.defineProperty(exports, "checkYouthSafetyCallable", { enumerable: true, get: function () { return YouthSafetyService_1.checkYouthSafetyCallable; } });
Object.defineProperty(exports, "updateYouthSettings", { enumerable: true, get: function () { return YouthSafetyService_1.updateYouthSettings; } });
Object.defineProperty(exports, "enforceYouthAccountDefaults", { enumerable: true, get: function () { return YouthSafetyService_1.enforceYouthAccountDefaults; } });
var GuardianConnectionService_1 = require("./safety/GuardianConnectionService");
Object.defineProperty(exports, "requestGuardianConnection", { enumerable: true, get: function () { return GuardianConnectionService_1.requestGuardianConnection; } });
Object.defineProperty(exports, "approveGuardianConnection", { enumerable: true, get: function () { return GuardianConnectionService_1.approveGuardianConnection; } });
Object.defineProperty(exports, "revokeGuardianConnection", { enumerable: true, get: function () { return GuardianConnectionService_1.revokeGuardianConnection; } });
Object.defineProperty(exports, "approveContactForMinor", { enumerable: true, get: function () { return GuardianConnectionService_1.approveContactForMinor; } });
Object.defineProperty(exports, "forwardYouthAlertToGuardians", { enumerable: true, get: function () { return GuardianConnectionService_1.forwardYouthAlertToGuardians; } });
var TrustAndStrikeService_1 = require("./safety/TrustAndStrikeService");
Object.defineProperty(exports, "adminIssueStrike", { enumerable: true, get: function () { return TrustAndStrikeService_1.adminIssueStrike; } });
Object.defineProperty(exports, "adminGetTrustProfile", { enumerable: true, get: function () { return TrustAndStrikeService_1.adminGetTrustProfile; } });
Object.defineProperty(exports, "autoIssueStrikeOnBlock", { enumerable: true, get: function () { return TrustAndStrikeService_1.autoIssueStrikeOnBlock; } });
var HumanReviewQueueService_1 = require("./safety/HumanReviewQueueService");
Object.defineProperty(exports, "claimReviewItem", { enumerable: true, get: function () { return HumanReviewQueueService_1.claimReviewItem; } });
Object.defineProperty(exports, "resolveReviewItem", { enumerable: true, get: function () { return HumanReviewQueueService_1.resolveReviewItem; } });
Object.defineProperty(exports, "getReviewQueue", { enumerable: true, get: function () { return HumanReviewQueueService_1.getReviewQueue; } });
Object.defineProperty(exports, "checkQueueSLABreaches", { enumerable: true, get: function () { return HumanReviewQueueService_1.checkQueueSLABreaches; } });
var EvidencePreservationService_1 = require("./safety/EvidencePreservationService");
Object.defineProperty(exports, "preserveEvidenceCallable", { enumerable: true, get: function () { return EvidencePreservationService_1.preserveEvidenceCallable; } });
Object.defineProperty(exports, "getEvidenceRecord", { enumerable: true, get: function () { return EvidencePreservationService_1.getEvidenceRecord; } });
Object.defineProperty(exports, "markEvidenceProvided", { enumerable: true, get: function () { return EvidencePreservationService_1.markEvidenceProvided; } });
Object.defineProperty(exports, "searchEvidenceByUser", { enumerable: true, get: function () { return EvidencePreservationService_1.searchEvidenceByUser; } });
var ModerationAuditLogService_1 = require("./safety/ModerationAuditLogService");
Object.defineProperty(exports, "queryAuditLog", { enumerable: true, get: function () { return ModerationAuditLogService_1.queryAuditLog; } });
Object.defineProperty(exports, "getAuditSummary", { enumerable: true, get: function () { return ModerationAuditLogService_1.getAuditSummary; } });
var ReportAbuseService_1 = require("./safety/ReportAbuseService");
Object.defineProperty(exports, "reportAbuse", { enumerable: true, get: function () { return ReportAbuseService_1.reportAbuse; } });
Object.defineProperty(exports, "getMyReports", { enumerable: true, get: function () { return ReportAbuseService_1.getMyReports; } });
// NOTE: TextRewriteService functions require ANTHROPIC_API_KEY secret.
// Run: firebase functions:secrets:set ANTHROPIC_API_KEY before deploying.
__exportStar(require("./safety/TextRewriteService"), exports);
var ProgressiveTrustService_1 = require("./safety/ProgressiveTrustService");
Object.defineProperty(exports, "getTrustProfile", { enumerable: true, get: function () { return ProgressiveTrustService_1.getTrustProfile; } });
Object.defineProperty(exports, "adminGrantTrustEvent", { enumerable: true, get: function () { return ProgressiveTrustService_1.adminGrantTrustEvent; } });
Object.defineProperty(exports, "initializeNewAccount", { enumerable: true, get: function () { return ProgressiveTrustService_1.initializeNewAccount; } });
var InteractionModeService_1 = require("./safety/InteractionModeService");
Object.defineProperty(exports, "setInteractionMode", { enumerable: true, get: function () { return InteractionModeService_1.setInteractionMode; } });
Object.defineProperty(exports, "getInteractionMode", { enumerable: true, get: function () { return InteractionModeService_1.getInteractionMode; } });
Object.defineProperty(exports, "enforcePostModeConstraints", { enumerable: true, get: function () { return InteractionModeService_1.enforcePostModeConstraints; } });
Object.defineProperty(exports, "initializeModeForNewUser", { enumerable: true, get: function () { return InteractionModeService_1.initializeModeForNewUser; } });
var BehavioralPatternService_1 = require("./safety/BehavioralPatternService");
Object.defineProperty(exports, "scanGroomingVelocity", { enumerable: true, get: function () { return BehavioralPatternService_1.scanGroomingVelocity; } });
Object.defineProperty(exports, "scanCoordinatedHarassment", { enumerable: true, get: function () { return BehavioralPatternService_1.scanCoordinatedHarassment; } });
__exportStar(require("./safety/AuditLogService"), exports);
__exportStar(require("./safety/BehavioralAlertConsumerService"), exports);
var MentorshipVerificationService_1 = require("./safety/MentorshipVerificationService");
Object.defineProperty(exports, "requestMentorship", { enumerable: true, get: function () { return MentorshipVerificationService_1.requestMentorship; } });
Object.defineProperty(exports, "approveMentorship", { enumerable: true, get: function () { return MentorshipVerificationService_1.approveMentorship; } });
Object.defineProperty(exports, "endMentorship", { enumerable: true, get: function () { return MentorshipVerificationService_1.endMentorship; } });
Object.defineProperty(exports, "getMyMentorships", { enumerable: true, get: function () { return MentorshipVerificationService_1.getMyMentorships; } });
Object.defineProperty(exports, "requestChurchVerification", { enumerable: true, get: function () { return MentorshipVerificationService_1.requestChurchVerification; } });
Object.defineProperty(exports, "issueChurchVerificationCode", { enumerable: true, get: function () { return MentorshipVerificationService_1.issueChurchVerificationCode; } });
Object.defineProperty(exports, "getChurchVerificationStatus", { enumerable: true, get: function () { return MentorshipVerificationService_1.getChurchVerificationStatus; } });
// ─── Amen Trust + Safety OS — Extended Modules ──────────────────────────────
//
// safetyTypes         — unified SafetyDecision model, all shared types
// moderateText        — layered text preflight (banned-terms + Perspective API)
// moderateImage       — Cloud Vision SafeSearch image preflight
// moderateVideo       — video preflight (transcript + thumbnail analysis)
// moderateAudio       — audio transcript preflight
// provenance          — Amen True Source: upload hash, AI detection, source chain
// botDefense          — BotScore evaluation: velocity + device + comment signals
// identityTrust       — identity trust levels, church verification, impersonation
// rankingSafety       — safety-first ranking (penalizes outrage/bots/fake virality)
// reportAbuse (ts)    — full report flow: quarantine, escalate, preserve evidence
// enforcement         — strike ladder, account status, appeals
// safetyAuditLog (ts) — immutable append-only audit event writer
//
// All callables: App Check + Auth enforced.
var moderateText_1 = require("./trustSafety/moderateText");
Object.defineProperty(exports, "runTextPreflight", { enumerable: true, get: function () { return moderateText_1.runTextPreflight; } });
var moderateImage_1 = require("./trustSafety/moderateImage");
Object.defineProperty(exports, "runImagePreflight", { enumerable: true, get: function () { return moderateImage_1.runImagePreflight; } });
var moderateVideo_1 = require("./trustSafety/moderateVideo");
Object.defineProperty(exports, "runVideoPreflight", { enumerable: true, get: function () { return moderateVideo_1.runVideoPreflight; } });
var moderateAudio_1 = require("./trustSafety/moderateAudio");
Object.defineProperty(exports, "runAudioPreflight", { enumerable: true, get: function () { return moderateAudio_1.runAudioPreflight; } });
var provenance_1 = require("./trustSafety/provenance");
Object.defineProperty(exports, "getMediaProvenance", { enumerable: true, get: function () { return provenance_1.getMediaProvenance; } });
var botDefense_1 = require("./trustSafety/botDefense");
Object.defineProperty(exports, "evaluateBotScore", { enumerable: true, get: function () { return botDefense_1.evaluateBotScore; } });
Object.defineProperty(exports, "getBotProfile", { enumerable: true, get: function () { return botDefense_1.getBotProfile; } });
var identityTrust_1 = require("./trustSafety/identityTrust");
Object.defineProperty(exports, "getIdentityTrustProfile", { enumerable: true, get: function () { return identityTrust_1.getIdentityTrustProfile; } });
Object.defineProperty(exports, "setChurchVerificationStatus", { enumerable: true, get: function () { return identityTrust_1.setChurchVerificationStatus; } });
Object.defineProperty(exports, "flagSuspectedImpersonation", { enumerable: true, get: function () { return identityTrust_1.flagSuspectedImpersonation; } });
Object.defineProperty(exports, "updateCreatorTrustDeclaration", { enumerable: true, get: function () { return identityTrust_1.updateCreatorTrustDeclaration; } });
var rankingSafety_1 = require("./trustSafety/rankingSafety");
Object.defineProperty(exports, "computeRankingScore", { enumerable: true, get: function () { return rankingSafety_1.computeRankingScore; } });
Object.defineProperty(exports, "markContentTrendIneligible", { enumerable: true, get: function () { return rankingSafety_1.markContentTrendIneligible; } });
var reportAbuse_1 = require("./trustSafety/reportAbuse");
Object.defineProperty(exports, "submitAbuseReport", { enumerable: true, get: function () { return reportAbuse_1.submitAbuseReport; } });
Object.defineProperty(exports, "getMyAbuseReports", { enumerable: true, get: function () { return reportAbuse_1.getMyAbuseReports; } });
Object.defineProperty(exports, "resolveAbuseReport", { enumerable: true, get: function () { return reportAbuse_1.resolveAbuseReport; } });
Object.defineProperty(exports, "escalateAbuseReport", { enumerable: true, get: function () { return reportAbuse_1.escalateAbuseReport; } });
var enforcement_1 = require("./trustSafety/enforcement");
Object.defineProperty(exports, "issueEnforcementStrike", { enumerable: true, get: function () { return enforcement_1.issueEnforcementStrike; } });
Object.defineProperty(exports, "getEnforcementProfile", { enumerable: true, get: function () { return enforcement_1.getEnforcementProfile; } });
Object.defineProperty(exports, "submitAppeal", { enumerable: true, get: function () { return enforcement_1.submitAppeal; } });
Object.defineProperty(exports, "resolveAppeal", { enumerable: true, get: function () { return enforcement_1.resolveAppeal; } });
var safetyAuditLog_1 = require("./trustSafety/safetyAuditLog");
Object.defineProperty(exports, "queryTrustSafetyAuditLog", { enumerable: true, get: function () { return safetyAuditLog_1.queryAuditLog; } });
var mediaCaptions_1 = require("./mediaCaptions");
Object.defineProperty(exports, "moderateMediaCaption", { enumerable: true, get: function () { return mediaCaptions_1.moderateMediaCaption; } });
Object.defineProperty(exports, "publishPostWithMedia", { enumerable: true, get: function () { return mediaCaptions_1.publishPostWithMedia; } });
Object.defineProperty(exports, "generateAltText", { enumerable: true, get: function () { return mediaCaptions_1.generateAltText; } });
//# sourceMappingURL=index.js.map