import * as admin from "firebase-admin";
import { defineSecret } from "firebase-functions/params";

if (!admin.apps.length) {
    admin.initializeApp();
}

// Secrets — declared here so Functions v2 binds them at deploy time.
// Use: process.env.ANTHROPIC_API_KEY (populated automatically for functions that reference this)
export const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
export const perspectiveApiKey = defineSecret("PERSPECTIVE_API_KEY");


// AI Proxy Functions
export * from "./bereanChatProxy";
export * from "./bereanChatProxyStream"; // True SSE streaming proxy
export * from "./openAIProxy";
export * from "./whisperProxy";
export * from "./generateDailyVerse";
export * from "./amenDaily/getAmenDailyDigest";

// Phase P1-4: server-authoritative Think-First / Tone Checker.
// iOS ThinkFirstGuardrailsService is advisory only; the publish path
// (CreatePost / comments / replies) MUST call validateThinkFirstCheck
// before persisting user-authored content.
export * from "./thinkFirst/validateThinkFirstCheck";

// Phase H3 / App Review Guideline 1.2: user-facing "report this AI
// response" mechanism. Persists structured reports to aiUnsafeReports
// for human review without echoing the raw response text.
export * from "./aiSafety/reportUnsafeAIResponse";

// Berean Spiritual Intelligence Layers (System 16)
//   Feature 1: Living Scripture Graph
//   Feature 2: Spiritual State Discernment Layer
//   Feature 3: Guided Discipleship Engine
//   Feature 4: Scripture Immersion Mode
//   Feature 5: Authority Alignment System
export * from "./berean/controllers/generateStructuredResponse";
export * from "./berean/controllers/studyPassage";
export * from "./berean/controllers/analyzeMessage";
export * from "./berean/controllers/evaluateAuthorityEscalation";
export * from "./berean/controllers/getImmersionPayload";
export * from "./berean/controllers/getJourneySnapshot";
export * from "./berean/controllers/generateDiscipleshipNextStep";
export * from "./berean/controllers/saveReflectionEntry";
export * from "./berean/controllers/generateChurchNotesSummary";
export * from "./berean/controllers/premiumBereanCallables";
export * from "./contextual/contextualActionRouter";
export {
    analyzeSmartMessage,
    detectScriptureReferences,
    detectSmartDateEvents,
    detectPrayerRequest,
    summarizeDiscussion,
    getContextualBereanActions,
    extractDiscussionTopics,
    semanticSearchAmenSpace,
    startSmartStudyMode,
    transcribeVoiceMessage,
    buildKnowledgeGraphMemory,
    indexSmartPrayerRequest,
    backfillSmartMessageVectorIndex,
    getSmartMessageVectorIndexStatus,
    scheduledSmartMessageVectorBackfill,
} from "./smartMessageIntelligence/smartMessageRouter";

// Selah Media OS (System 18)
export * from "./selahMedia";

// Selah Bible Engine — Study sheet, verse theme classification, safety classification
export * from "./selah/index";

// Smart Media Attachments (System 22)
// resolveSmartAttachment, saveMediaGraphItem, getRecentMediaAttachments, getSavedMediaItems
export * from "./smartAttachments";

// Safety OS Reaction Engine
export * from "./safetyOSReactionEngine";

// Community Hubs & Object Intelligence
export {
    resolveCommunityObject,
    createOrJoinObjectHub,
    getObjectHub,
    getRelatedObjectHubs,
    recordObjectInteraction,
    muteObjectHub,
    reportHubContent,
    indexPostIntoHub,
} from "./communityHubs";

// Accessibility Intelligence Layer
export * from "./refineTranslation";
export * from "./transformContent";

// Group Link Functions
export * from "./groupLinks";
export * from "./resolveOrCreateConversation";

// Suggested Accounts Rail
export * from "./suggestedAccounts";

// Find People to Follow — getSuggestedFollows + registerDiscoveryLocation
export * from "./discovery";

// UserProfileMini context callable
export * from "./profileMini/getUserProfileMiniContext";

// Creator Spaces — trusted media, provenance, daily portion, and memory graph callables
export * from "./creatorSpaces";

// Amen Spatial Rooms OS — server-authoritative creation, theme generation, and backfill.
export * from "./spatialRooms";

// Trust + Intelligence (Berean infrastructure)
export * from "./trustIntelligence";
export * from "./profileBanners";
export * from "./amenConnect";
export * from "./spaces";
export * from "./amenSpacesDiscovery";
export * from "./amenSpaceBanners";
export * from "./amenNationalDirectory";
export * from "./legacyAiSafetyBridge";
export * from "./integrations";

// Action Threads — server-authoritative care workflow CRUD
// All state transitions and participant invitations are validated server-side.
export * from "./actionThreads";

// Private/Follower Feed Builder
export * from "./feedBuilder";
export * from "./postReactions";
export * from "./postCountTriggers";

// Smart Context Label scoring, ranking, feedback, and preference sync
export * from "./feedContext";
export * from "./bereanPulse";

// Dynamic Reply Preview system — server-ranked inline PostCard preview candidates
// onReplyCreate and rebuildReplyPreviews are intentionally omitted here; the
// CONTRACT.md-authoritative versions are exported from ./replyPreview below.
export {
    onCommentCreatedUpdatePreviews,
    onCommentDeletedUpdatePreviews,
    onUserProfileImageUpdatedRefreshPreviews,
    refreshDynamicReplyPreviews,
    scheduledReplyPreviewRefresh,
    detectCommunityPulse,
    selectFollowedReplyCandidate,
    countVisibleCommunityMatches,
    generateBereanInsightCandidate,
    passesPreviewModeration,
    denormalizePreviewCandidates,
    shouldRefreshPreviewAvatars,
} from "./generateDynamicReplyPreviews";

// CONTRACT.md §12 — authoritative onReplyCreate + rebuildReplyPreviews
// Implements resolver ladder (§13), scoring formula (§15), dirty thresholds (§16).
export { onReplyCreate, rebuildReplyPreviews, rebuildReplyPreviewsOnDirty } from "./replyPreview";
export * from "./churchDiscoveryPhase2";
export * from "./churchDiscoveryPhase3";
export * from "./churchDiscovery";

// Smart Community Search — Ask Amen (System: Smart Finder)
export * from "./smartCommunitySearch";
export * from "./smartChurchSearch";

// Church seed data (admin-only callable — run once per environment)
export { seedChurchData } from "./seedChurches";

// Server-authoritative feature flags (CRITICAL-3)
// Safety flags are read from Firestore by Cloud Functions — never trusted from the client.
// Must be exported before antiHarassmentEnforcement (which imports from it).
export * from "./serverFeatureFlags";

// Anti-Harassment Enforcement — server-side restriction checks on message sends
// CRITICAL-1: Enforces messaging/dm_freeze/no_contact restrictions and block checks
// unconditionally on the server, regardless of the client write path.
export * from "./antiHarassmentEnforcement";

// Account Suspension — Firebase Auth disablement for critical harassment tier
// HIGH-2: Auto-suspends accounts when critical/minor-safety queue items are created.
export * from "./accountSuspension";
export * from "./twoFactorAuth";
export * from "./accountLifecycle";

// Just-In-Time (JIT) Admin Access — Trust OS requirement.
// Moderator roles are time-limited, not permanent. Moderators request a
// short-lived elevation session (max 8 hours); the scheduled cleanup revokes
// claims automatically when the window closes.
// Callables: requestTemporaryElevation, revokeElevation
// Scheduled: cleanupExpiredJitSessions (every 30 minutes)
// Audit:     trustAuditLog (jit_session_created | jit_session_revoked | jit_session_expired)
export * from "./jitAccess";

// Safety Reporting — server-side report creation with validation
// HIGH-3: submitReport callable validates reason, verifies evidence, computes
// escalationTier and priority server-side. Direct client writes to userReports
// are now blocked in Firestore rules (allow create: if false).
export * from "./submitReport";

// Comment Moderation Enforcement — server-authoritative moderationStatus writes to RTDB
// Triggered on every new userReports document. For reports with contentType="comment",
// aggregates report history and writes moderationStatus ("pending" | "hidden") to
// /comments/{postId}/{commentId}/moderationStatus in RTDB based on tier/count thresholds.
// Closes the audit gap: moderationStatus was previously client-written with no server enforcement.
export * from "./commentModerationEnforcement";

// Media Scanning — Cloud Vision SafeSearch on every Storage upload
// HIGH-1: Scans images for CSAM/explicit/violence signals on onFinalize.
// VERY_LIKELY → delete file + suspend account
// LIKELY      → quarantine file + queue for human review
// POSSIBLE    → flag originating document, queue for human review
export * from "./mediaScanning";

// Account Deletion — Algolia record removal (App Store Guideline 5.1.1)
// Called by AccountDeletionService during full account deletion flow.
// Deletes the user record from "users" index and all posts from "posts" index.
export * from "./deleteAlgoliaUser";

// CRITICAL: Post deletion cascade — cleans up comments, reactions, reposts,
// savedPosts, feed items, Algolia record, and Storage media when a post is deleted.
export * from "./postDeletionCascade";

// CRITICAL: Full account deletion cascade — deletes all user content across
// every collection and subcollection (App Store Guideline 5.1.1 compliance).
export * from "./userAccountDeletionCascade";

// CRITICAL: Block relationship cleanup — removes follow edges, pending follow
// requests, and restricts shared conversations when a block is created.
export * from "./blockRelationshipCleanup";

// Atomic block/unblock — writes to BOTH blockedUsers top-level collection
// (used by antiHarassmentEnforcement) and users/{uid}/blockedUsers subcollection
// (used by Firestore rules) in a single batch. Prevents partial-block drift.
export * from "./createBlock";

// Atomic follow/unfollow — writes follows edge doc AND follows_index doc
// (used by callerFollows() in Firestore rules for follower-only content gating)
// in a single batch. Prevents follows_index missing entries that silently break
// follower-only post visibility.
export * from "./createFollow";

// Notification Functions — Server-side pipeline
//
// Firestore triggers use gen2 syntax (firebase-functions/v2/firestore) so they
// coexist with gen2 onCall functions in the same deployment.
export * from "./notifications/onSocialEvent";
export * from "./notifications/counts";
export * from "./notifications/maintenance";
export * from "./notifications/invalidation";

// 5.4 FIX — Prayer answered fan-out: processes ≤100 supporter batches per
// invocation, eliminating the timeout risk of sequential single-function fan-out.
export * from "./notifications/prayerAnsweredBatch";

// 5.6 FIX — Quiet hours digest: scheduled every 30 min to batch-deliver push
// notifications to users whose quiet window has ended.
export * from "./notifications/deliverQuietHoursDigest";

// Church Visit Lifecycle — phase-triggered follow-up scheduling and FCM nudges
// Triggered on attended/reflected phase transitions in users/{uid}/churchInteractions/{churchId}
export * from "./churchVisitLifecycle";

// Amen Intelligence Fabric — server-authoritative trust, safety, crisis,
// moderation, and reputation decisions derived from client/context snapshots.
export * from "./amenIntelligenceFabric";

// Church Journey System — full Find Church → Plan → Notes → Reflection orchestration
// createChurchJourney, updateChurchJourneyTiming, promoteJourneyToPrepActive,
// promoteJourneyToArrived, generateReflectionSeedFromNotes,
// scheduleMidweekReflectionReminder, learnChurchRoutine,
// cleanupStaleChurchJourneys, generatePrepSuggestions
export * from "./churchJourney";
export * from "./churchDiscovery";
export * from "./spiritualSystems";

// Post Creation Finalizer — text moderation, status transition (publishing→published),
// Algolia indexing. Feed fanout for followers-only posts is in feedBuilder.ts.
// Exported as finalizePostOnCreate to avoid conflict with the onPostCreated
// mention-handler in onSocialEvent.ts.
export * from "./onPostCreated";

// Media Post Index — maintains users/{authorId}/mediaPosts/{postId} denormalized
// index for profile "Photos & Videos" tab. Triggered on post create/update/delete.
// Handles moderation state changes, visibility changes, and media schema evolution.
export * from "./mediaPostIndex";

// Algolia sync — keeps "posts" index current on post edit and deletion
export * from "./algoliaSync";

// Scheduled maintenance — counter reconciliation, stale data pruning, token cleanup
export * from "./scheduledMaintenance";

// Age tier JWT claim sync — P1.1 FIX: sets ageTier custom claim on users/{uid}.ageTier
// changes so Firestore rules can read from request.auth.token.ageTier (zero get() reads).
export * from "./syncAgeTierClaim";

// Username change rate limiting — 30-day cooldown enforced server-side
// Section-13 FIX: trackUsernameChange trigger writes to userSafetyRecords on
// every username change; usernameChangeCooldownRelease (in scheduledMaintenance)
// re-enables canChangeUsername after 30 days.
export * from "./usernameChangeTracking";

// Smart Activity Layer — Followers/Following lists with precomputed activity state
// Triggers: posts/{postId}, prayers/{prayerId}, churchNotes/{noteId} writes
// Callable: markRelationshipSeen (batched seen-state flush from client)
// Scheduled: reconcileRelationshipStates (daily stale doc cleanup)
export * from "./socialGraph";

// Smart Share — ranked targets, payloads, deep links, moderation, analytics,
// notification fan-out, and queued render jobs for the AMEN custom share sheet.
export * from "./share/smartShare";

// Creator Functions
export * from "./creator/createProject";
export * from "./creator/updateProject";
export * from "./creator/deleteProject";
export * from "./creator/autosaveProject";
export * from "./creator/queueProcessingJob";
export * from "./creator/processVideoProxy";
export * from "./creator/generateThumbnail";
export * from "./creator/transcribeMedia";
export * from "./creator/generateSubtitleTrack";
export * from "./creator/translateSubtitleTrack";
export * from "./creator/buildOutputVariants";
export * from "./creator/renderExport";
export * from "./creator/publishProject";
export * from "./creator/moderateCreatorAsset";
export * from "./creator/verifyAuthenticitySignals";
export * from "./creator/saveBrandKit";
export * from "./creator/cloneTemplateToProject";
export * from "./creator/recordCreatorAnalytics";
export * from "./creator/enforceCreatorEntitlement";
export * from "./creator/cleanupOrphanedAssets";
export * from "./creator/retryFailedCreatorJob";

// Living Entries — unified notes, reminders, church follow-up, reflections
export * from "./livingEntries/livingEntryFunctions";

// Universal Content + Create foundations. Existing post/comment/note flows
// remain canonical until Remote Config enables the new surfaces.
export * from "./universalContent/contentNodeFunctions";
export * from "./universalContent/platformFunctions";

// Media Metadata Generation Pipeline — Phase 3
// Firestore trigger: onPostCreatedGenerateMediaMetadata (posts/{postId})
// Callable: retryMediaGeneration (retry failed generation for a media item)
// Provider: OpenAI Whisper (OPENAI_API_KEY) + Claude label refinement (ANTHROPIC_API_KEY)
export * from "./mediaGeneration/mediaMetadataPipeline";

// Berean AI Alignment + Spiritual Protection
// Rule-based pipeline classifies posts, comments, and Berean interactions for
// biblical alignment, spiritual-protection signals (grooming, trafficking,
// explicit content, coercion) and 7-deadly-sins pastoral framing.
// Callables: checkBiblicalAlignment, suggestBiblicalRewrite, saveAICorrection,
//   getDiscernmentPrompt, attachSharedKnowledgeIntegrity, voteKnowledgeIntegrity,
//   getWeeklyAlignmentSummary, updateAlignmentProfile.
export * from "./biblicalAlignmentFunctions";

// Holiday Calendar Generator — pre-generates annual observances in Firestore
// holiday_calendar/{year}/days/{yyyy-MM-dd}/observances/{holidayId}
// Scheduled: generateNextYearHolidayCalendar (Nov 1, 06:00 UTC)
// Callable:  backfillHolidayCalendar (admin-only), validateHolidayCalendarYear (admin-only)
export * from "./holidayCalendarGenerator";

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
export { setMode, initiateDM, requestGuardianConsent, confirmGuardianConsent, resolvePermissionsCallable, setDateOfBirth } from "./permissions/permissionsCallables";
export { onUserWrite, dailyAgeTierPromotion } from "./permissions/permissionsTriggers";

// Lord's Day Rest Mode — server-side policy evaluation + AI label resolution
// Callables: evaluateRestMode, setRestModePolicy, resolvePostAILabel
// Trigger:   onRestModePolicyWritten (restModePolicies/{userId})
export * from "./restModeEvaluator";

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
export * from "./covenant/createCovenantActivityEvent";
export * from "./covenant/saveCovenantTierStripePriceId";
export * from "./covenant/createCovenantCheckoutSession";
// P1-5: Server-authoritative tone/safety check for covenant composer.
export * from "./covenant/validateCovenantPostSafety";
// P1-Phase-F: Community-level Save/Unsave (server-authoritative).
export * from "./covenant/setCommunitySaved";
export * from "./covenant/createCovenantThreadReply";
export * from "./covenant/generateThreadSummary";
export * from "./covenant/createPrayerRequestFromMessage";
export * from "./covenant/generateCatchUpSummary";
export * from "./covenant/calculateCovenantChurnRisk";
export * from "./covenant/publishScheduledCovenantContent";
export * from "./covenant/submitCovenantReport";
export * from "./covenant/indexCovenantSearchDocument";
export * from "./covenant/stripeCovenantWebhook";

// Org Subscription OS — Stripe-based billing for organization Plus/Pro tiers
// Callables: createOrgSubscriptionCheckout (opens Stripe-hosted checkout for claimed org owners)
//            getOrgBillingPortalURL (opens Stripe Customer Portal for billing management)
// Webhook:   stripeOrgWebhook (HTTPS) — writes organizations/{orgId}/billing/subscription
//            and updates org.modules[] after Stripe confirms payment
// Idempotency: deduplicates by Stripe event ID in stripeEvents/{eventId}
export * from "./orgSubscription/createOrgSubscriptionCheckout";
export * from "./orgSubscription/getOrgBillingPortalURL";
export * from "./orgSubscription/stripeOrgWebhook";

// Berean Extended Intelligence — memory, threads, translation comparison, follow-ups,
//   context linking, safety classification, preference sync
// Callables: saveBereanInsight, updateBereanMemory, deleteBereanMemory,
//   createBereanStudyThread, summarizeBereanThread, compareBibleTranslations,
//   generateBereanFollowUps, linkBereanContext, unlinkBereanContext,
//   classifyBereanSafety, updateBereanPreferences
export * from "./bereanExtended";

// Social Safety OS — 5-harm-category safety platform
// Callables: evaluateContentSafety, publishWithSafetyDecision, evaluateMessageSafety,
//   createSafetyReport, activateSextortionPanicFlow, updateTrustedContacts,
//   updateFeedControls, recordSessionBoundarySignal, submitClaimContext,
//   getRecommendationContext, requestHumanReview, resolveSafetyReview,
//   getSafetyPolicySnapshot, resetRecommendationTraining
export * from "./safetyOS";

// Creation AI — AI-powered creation assistance
// Callables: suggestCreationVerses, improveCreationCaption,
//   suggestCreationHashtags, generateCreationOutline
export * from "./creationAI";

// Church Trust & Safety OS — verification pipeline, moderation, grounding, livestream
// Callables: submitChurchVerificationRequest, submitChurchProfileUpdate,
//   reviewChurchModerationItem, refreshChurchLivestreamState, generateGroundedChurchAnswer,
//   syncYouTubeChurchStreams, updateChurchLiveSignals, moderateChurchMediaUpload
// Trigger:   onChurchVerificationReviewed
export {
  submitChurchProfileUpdate,
  reviewChurchModerationItem,
  refreshChurchLivestreamState,
  generateGroundedChurchAnswer,
  syncYouTubeChurchStreams,
  updateChurchLiveSignals,
} from "./church/controllers/churchTrustCallables";

// Berean Operating Layer — integrated Berean AI response with full context pipeline
// Callable: generateBereanOperatingResponse
export * from "./berean/bereanOperatingLayer";

// Video Explain — AI-powered explanation of sermon/teaching video content
// Callable: explainVideoContent (Auth + App Check, transcript gate, Claude, safety filter)
// Security: server re-checks visibility, block status, flagged state before generation.
// No client writes to mediaMeta explanation fields — Firestore rules enforce this.
export * from "./explainVideoContent";

// Voice Prayer & Testimony Comments (System 32)
// Callables: createVoicePrayerUploadSession, finalizeVoicePrayerComment,
//   deleteVoicePrayerComment, reportVoicePrayerComment,
//   reactToVoicePrayerComment, getVoicePrayerPlaybackURL
// Trigger:   moderateVoicePrayerComment (Firestore onDocumentUpdated)
// Security:  Auth + App Check on all callables. Client cannot write transcript,
//   moderation, intent, spiritualContext, summary, or status.
//   All publish decisions are server-authoritative.
// Flags:     voicePrayerCommentsEnabled, voiceTestimonyCommentsEnabled (both off by default)
export * from "./voicePrayerComments";

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
export {
  detectUnsentThoughtRisk,
  saveUnsentThought,
  resolveUnsentThought,
  analyzeScriptureDrift,
  generateBalancingScripture,
  dismissDriftSignal,
  detectSilencePatterns,
  resurfaceAvoidedItem,
  markSilenceSignalResolved,
  updateRelationalGravity,
  classifyRelationshipState,
  generateReconciliationPrompt,
  evaluateMomentRisk,
  logMomentInterception,
  updateMomentLearning,
  createReflectionPrompt,
  savePostActionReflection,
  updateUserGrowthPattern,
  analyzeTruthVsEmotion,
  scoreWeightOfWords,
  generateGracefulRewrite,
  aggregateDiscernmentSignals,
  generateCommunityDiscernmentSummary,
  calculateEternalWeight,
  updateEternalWeightAfterReflection,
  generateMeaningPrompt,
  createWalkWithChristPathFromPattern
} from "./spiritualOS";

// AI Usage Labels — AI disclosure labeling, tone evaluation, and usage tracking
// Callables: recordPostAIUsage, getAILabelDetail, evaluateTone
// Privacy: raw text and prompts are never stored server-side.
// Disclosure enforcement: disclosureRequired labels cannot be downgraded once set.
export {
  recordPostAIUsage,
  getAILabelDetail,
  evaluateTone
} from "./aiUsageLabels";

// Media Moderation Pipeline — 6-layer AI safety pipeline for photos and videos
// Triggers: onPostCreatedRunMediaModeration, onPostMediaUpdatedRunModeration
// Callables: submitMediaReviewDecision, getPostModerationStatus,
//            getAccountMediaRiskScore, triggerMediaModeration
// Layers: hash check → image safety → OCR → text safety → fusion → action engine
// Raw text and media are never stored in moderation logs.
export {
  onPostCreatedRunMediaModeration,
  onPostMediaUpdatedRunModeration,
  submitMediaReviewDecision,
  getPostModerationStatus,
  getAccountMediaRiskScore,
  triggerMediaModeration
} from "./mediaModerationPipeline";

// System 27: Berean Grok Helper Pipeline
// Callables: bereanHelperSummarizePrompt, bereanHelperAnalyzeLink,
//            bereanHelperExternalContext, bereanHelperStudyOutline
export * from "./bereanHelperPipeline";

// System 28: Feed Intelligence
// Callables: submitFeedDirection, explainWhyThisPost, adjustPostRecommendationSignal,
//            getFeedIntelligenceSummary, resetFeedPreference
export * from "./feedIntelligence";

// Amen Discover
export * from "./discover";

// System 29: Liquid Glass Intelligence Layer
// Callables: defineSemanticTerm, detectSmartActions, createKnowledgeThread,
//            saveSemanticInsight, logPresenceSignal
// Auth + App Check enforced on all five. Trusted AI outputs written server-side only.
export * from "./semanticIntelligence";

// System 30: Per-Media Captions
// Callables: validateMediaCaptions, updatePostMediaCaptions
export {
  validateMediaCaptions,
} from "./validateMediaCaptions";

// System 32: Communication OS — Next-Gen Messaging + Group Discussions
// Callables: generateDMCatchUp/generateCatchUpDigest, extractThreadDecisions, detectOpenQuestions,
//            extractThreadActions, generateGroupPulse, generateMediaContext,
//            searchConversationMemory, generateSmartReplies
// All callables require Auth + App Check. Participant membership verified server-side.
// AI outputs marked as "suggested" — never fabricate owners, deadlines, or consensus.
export * from "./messaging/generateDMCatchUp";
export * from "./messaging/extractThreadDecisions";
export * from "./messaging/detectOpenQuestions";
export * from "./messaging/extractThreadActions";
export * from "./messaging/generateGroupPulse";
export * from "./messaging/generateMediaContext";
export * from "./messaging/privateMessageActions";
export * from "./messaging/productionIntelligenceActions";
export * from "./messaging/searchConversationMemory";
export * from "./messaging/generateSmartReplies";

// Amen Startup Drop Intelligence Layer
export * from "./realtime/createRealtimeSession";
export * from "./realtime/endRealtimeSession";
export * from "./realtime/logRealtimeVoiceEvent";
export * from "./realtime/moderateRealtimeTranscript";
export * from "./berean/translation/translateMultilingualContent";
export * from "./berean/scripture/resolveScriptureReferences";
export * from "./berean/transcripts/persistRealtimeTranscriptChunk";

export * from "./media/startRealtimeTranscription";
export * from "./media/finalizeTranscript";
export * from "./media/extractKeyMoments";
export * from "./media/moderateTranscript";

export * from "./translation/createTranslationSession";
export * from "./translation/saveTranslatedTranscript";
export * from "./translation/moderateTranslationOutput";

export * from "./graphics/generateAmenGraphic";
export * from "./graphics/editAmenGraphic";
export * from "./graphics/moderateGraphicPrompt";
export * from "./graphics/saveGeneratedGraphic";

export * from "./agents/runAmenAgentTask";
export * from "./agents/agentTaskRouter";
export * from "./agents/agentGuardrails";
export * from "./agents/agentObservability";
export * from "./agents/agentResultFormatter";

export * from "./amenAI/draftLifecycle";
export * from "./amenAI/modelRouter";
export * from "./churchNotes/createChurchNotesAIDraft";

// Church Notes Media Intelligence — processing jobs, OCR, audio, content generation, draft approval
export * from "./churchNotes/churchNotesProcessingJobs";
export * from "./churchNotes/churchNotesAudioProcessing";
export * from "./churchNotes/churchNotesImageOCR";
export * from "./churchNotes/churchNotesContentGeneration";
export * from "./churchNotes/churchNotesDraftApproval";
export * from "./churchNotes/churchNotesExtendedCallables";
export * from "./churchNotes/churchNotesPrivacyAudit";
export { analyzeChurchNoteMemory } from "./churchNotes/churchNotesMemory";

// Social OS — Healthy Media Sessions, Provenance and Authenticity
export * from "./media/createMediaSession";
export { registerMediaProvenance, getMediaTrustContext } from "./media/registerMediaProvenance";

// In-App Giving — server-side Stripe charge (Apple Pay + card tokenization)
export * from "./giving/processGivingCharge";

export * from "./giving/analyzePostTrustLogoMatch";

// Organization Identity Verification — Trust OS (C-04)
// submitOrgVerificationRequest: org owner/admin submits EIN/domain details for review
// approveOrgVerification:       platform admin sets identityVerified: true + audit log
// rejectOrgVerification:        platform admin rejects with reason + audit log
// Prerequisite: processGivingCharge.ts already enforces nonprofit.identityVerified before
// any donation transfer is processed; these callables complete that pipeline.
export * from "./orgVerification";

// Organization Claim System — search, submit, approve, reject, create stub
// Callables: requestOrgClaim, approveClaim, rejectClaim, createOrgStub
// Security: Auth + App Check. claimStatus / source / sourceId are server-only.
// Rate limit: 5 claim submissions per hour, max 3 simultaneous pending claims.
// Guardian check on every submission. Domain-match → auto-verify path.
// Google Places: placeId stored ONLY — no name/address/phone persisted from Places.
export * from "./orgClaim";

// Calm Control OS — privacy settings, feed controls, notification eligibility, inactivity management
// Callables: updatePrivacySettings, updateFeedControls, updateNotificationSettings,
//            evaluateNotificationEligibility, restoreUserAfterInactivity
// Scheduled: pauseInactiveUserNotifications (every 24 hours)
export * from "./calmControl";

// Unimplemented stubs — iOS-callable functions not yet fully built.
// All return HttpsError("failed-precondition") so callers receive a structured error.
// Replace each stub with a real implementation when the feature ships.
export * from "./stubs/missingFunctions";

// Spiritual Rhythm OS — streak tracking, verse candidates, spiritual digests
// Callables: recordSpiritualActivity, recoverStreak,
//            generateDailyVerseCandidate, generateSpiritualDigest
export * from "./spiritualRhythm";

// Amen Access Passes (System 37) — QR / NFC / universal link / share-link access
// Callables: createAccessPass, resolveAccessPass, acceptAccessPass, revokeAccessPass,
//   pauseAccessPass, resumeAccessPass, rotateAccessPassToken, approveAccessRequest,
//   denyAccessRequest, listAccessPassesForTarget, listAccessRequestsForTarget
// Auth + App Check enforced. tokenHash never leaves the server; rawToken in URLs only.
export * from "./accessPasses";

// Verification & Trust System — identity, organization, role, creator verification
// Callables: startIdentityVerification, requestOrganizationVerification,
//   verifyOrganizationDomain, requestRoleVerification, approveRoleVerification,
//   revokeRoleVerification, requestCreatorVerification, refreshVerificationSummary,
//   reportImpersonation
// Webhook: handleIdentityVerificationWebhook (HTTPS onRequest, HMAC-verified)
// Security: Auth + App Check on all callables. No raw ID data stored.
//   Verification truth fields are backend-only writes (Admin SDK).
export * from "./verification/index";

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

export { moderateTextCallable } from "./safety/TextModerationService";
export { moderateImageCallable } from "./safety/ImageModerationService";
export { moderateVideoCallable } from "./safety/VideoModerationService";
export { moderateAudioCallable } from "./safety/AudioModerationService";
export { checkLinkSafetyCallable } from "./safety/LinkSafetyService";
export {
  checkYouthSafetyCallable,
  updateYouthSettings,
  enforceYouthAccountDefaults,
} from "./safety/YouthSafetyService";
export {
  requestGuardianConnection,
  approveGuardianConnection,
  revokeGuardianConnection,
  approveContactForMinor,
  forwardYouthAlertToGuardians,
} from "./safety/GuardianConnectionService";
export {
  adminIssueStrike,
  adminGetTrustProfile,
  autoIssueStrikeOnBlock,
} from "./safety/TrustAndStrikeService";
export {
  claimReviewItem,
  resolveReviewItem,
  getReviewQueue,
  checkQueueSLABreaches,
} from "./safety/HumanReviewQueueService";
export {
  preserveEvidenceCallable,
  getEvidenceRecord,
  markEvidenceProvided,
  searchEvidenceByUser,
} from "./safety/EvidencePreservationService";
export {
  queryAuditLog,
  getAuditSummary,
} from "./safety/ModerationAuditLogService";
export {
  reportAbuse,
  getMyReports,
} from "./safety/ReportAbuseService";
// NOTE: TextRewriteService functions require ANTHROPIC_API_KEY secret.
// Run: firebase functions:secrets:set ANTHROPIC_API_KEY before deploying.
export * from "./safety/TextRewriteService";
export {
  getTrustProfile,
  adminGrantTrustEvent,
  initializeNewAccount,
} from "./safety/ProgressiveTrustService";
export {
  setInteractionMode,
  getInteractionMode,
  enforcePostModeConstraints,
  initializeModeForNewUser,
} from "./safety/InteractionModeService";
export {
  scanGroomingVelocity,
  scanCoordinatedHarassment,
} from "./safety/BehavioralPatternService";
export * from "./safety/AuditLogService";
export * from "./safety/BehavioralAlertConsumerService";
export {
  requestMentorship,
  approveMentorship,
  endMentorship,
  getMyMentorships,
  requestChurchVerification,
  issueChurchVerificationCode,
  getChurchVerificationStatus,
} from "./safety/MentorshipVerificationService";

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

export {
  runTextPreflight,
} from "./trustSafety/moderateText";

export {
  runImagePreflight,
} from "./trustSafety/moderateImage";

export {
  runVideoPreflight,
} from "./trustSafety/moderateVideo";

export {
  runAudioPreflight,
} from "./trustSafety/moderateAudio";

export {
  getMediaProvenance,
} from "./trustSafety/provenance";

export {
  evaluateBotScore,
  getBotProfile,
} from "./trustSafety/botDefense";

export {
  getIdentityTrustProfile,
  setChurchVerificationStatus,
  flagSuspectedImpersonation,
  updateCreatorTrustDeclaration,
} from "./trustSafety/identityTrust";

export {
  computeRankingScore,
  markContentTrendIneligible,
} from "./trustSafety/rankingSafety";

export {
  submitAbuseReport,
  getMyAbuseReports,
  resolveAbuseReport,
  escalateAbuseReport,
} from "./trustSafety/reportAbuse";

export {
  issueEnforcementStrike,
  getEnforcementProfile,
  submitAppeal,
  resolveAppeal,
} from "./trustSafety/enforcement";

export {
  queryAuditLog as queryTrustSafetyAuditLog,
} from "./trustSafety/safetyAuditLog";

export {
  moderateMediaCaption,
  publishPostWithMedia,
  generateAltText,
} from "./mediaCaptions";

// Anonymous-Accountable Mode — Trust OS requirement.
// createAnonymousPost:  authenticated user posts pseudonymously.
//   - stable anonId derived server-side via HMAC(uid, ANON_SALT)
//   - anonIdMappings/{anonId} mapping stored server-only (Firestore rules: allow read, write: if false)
//   - rate limited: 3 anon posts per 24-hour rolling window
// resolveAnonymousPost: admin-only de-anonymization. Every call is written to trustAuditLog.
// Prerequisites: deploy ANON_SALT secret before enabling the anonModeEnabled feature flag.
export { createAnonymousPost, resolveAnonymousPost } from "./anonPost";

// ─── Community Notes ──────────────────────────────────────────────────────────
// scriptureParser: parse + index Scripture refs from note text (server-side only)
// communityNotesWriter: Gen2 Firestore trigger — Algolia + Pinecone sync on write/delete
// engagement: counter triggers (likes, comments, amen, saves, follows) + hybrid search callable
export { onCommunityNoteWritten } from "./communityNotes/communityNotesWriter";
export {
  onLikeCreated, onLikeDeleted,
  onNoteCommentCreated, onNoteCommentDeleted,
  onNoteAmenCreated, onNoteAmenDeleted,
  onSaveCreated, onSaveDeleted,
  onFollowCreated, onFollowDeleted,
  searchCommunityNotes,
} from "./communityNotes/engagement";
// Multi-Tenant Contextual Experience System
export * from "./contextualExperiences";

// Organization Seed Pipeline — admin-only bulk import of NCES / IPEDS / IRS BMF data.
// All callables require admin custom claim (admin: true). Feature-flagged behind
// config/featureFlags.orgSeedEnabled. Never touches Google Places data (policy enforced
// inside batchUpsert). Dry-run support on all import functions.
//   importNcesCCD      — K-12 public schools (~100k records from NCES CCD CSV)
//   importNcesPSS      — K-12 private schools (~33k records from NCES PSS CSV)
//   importIPEDS        — postsecondary institutions (~6k from IPEDS CSV)
//   importIRSBMF       — exempt religious orgs/churches (~1.5M filtered to X-series NTEE)
//   deduplicateOrgs    — finds same-name/proximity pairs and merges by source priority
//   algolia_syncOrg    — single or bulk sync of org stubs to Algolia `organizations` index
export { importNcesCCD } from "./orgSeed/ncesCCDImport";
export { importNcesPSS } from "./orgSeed/ncesPSSImport";
export { importIPEDS } from "./orgSeed/ipedsImport";
export { importIRSBMF } from "./orgSeed/irsBMFImport";
export { deduplicateOrgs } from "./orgSeed/orgDeduplication";
export { algolia_syncOrg } from "./orgSeed/orgAlgoliaSync";

// ─── Security Hardening OS — Auth, Privacy, Anomaly Detection ────────────────
//
// Privacy / GDPR-CCPA:
//   deleteBereanHistory      — erases all Berean conversation data for a user (right to erasure)
//   requestUserDataExport    — packages all user data to a signed-URL JSON (right to portability)
//
// Auth & Account-Takeover Hardening:
//   revokeAllSessions        — revokes all refresh tokens for the calling user
//   reportAccountCompromise  — user-initiated compromise report → revoke + securityIncidents
//   requireRecentAuth        — issues single-use grant for sensitive actions (delete, email change…)
//
// Anomaly Monitoring (scheduled):
//   monitorInjectionSpikes   — alerts on >10 injection blocks per 15 min
//   monitorAISpend           — warns at 80% / critical at 100% of daily AI token cap
//   monitorFailedAuthSpike   — alerts on >20 failed auth attempts per uid per 30 min
//
// All callables: App Check + Auth enforced.
export { deleteBereanHistory } from "./privacy/deleteBereanHistory";
export { requestUserDataExport } from "./privacy/userDataExport";
export {
  revokeAllSessions,
  reportAccountCompromise,
} from "./auth/sessionRevocation";
export { requireRecentAuth } from "./auth/sensitiveActionGate";
export {
  monitorInjectionSpikes,
  monitorAISpend,
  monitorFailedAuthSpike,
} from "./monitoring/anomalyMonitor";
