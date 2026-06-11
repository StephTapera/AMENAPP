// AMENFeatureFlags.swift
// AMEN App — Unified Feature Flag System
//
// Single source of truth for all feature flags across the platform.
// Backed by Firebase Remote Config with safe local defaults.
// Major rollout surfaces default OFF until a human flips Remote Config after verification.
//
// Rollout philosophy:
//   - Every unapproved rollout feature starts OFF in production
//   - Flags are additive — never remove a flag without a deprecation cycle
//   - Flags can be targeted per-user via Remote Config audiences

import Foundation
import Combine
import FirebaseRemoteConfig

@MainActor
final class AMENFeatureFlags: ObservableObject {

    static let shared = AMENFeatureFlags()

    // MARK: - System 1: Advanced Moderation
    @Published private(set) var moderationV2Enabled: Bool = true
    @Published private(set) var imageModerationEnabled: Bool = true
    @Published private(set) var dmEnhancedScanningEnabled: Bool = true
    @Published private(set) var moderationAppealsEnabled: Bool = true
    @Published private(set) var trustScoringEnabled: Bool = true

    // MARK: - System 2: Berean RAG
    @Published private(set) var bereanRAGEnabled: Bool = true
    @Published private(set) var bereanConversationMemoryEnabled: Bool = true
    @Published private(set) var bereanSourceAttributionEnabled: Bool = true
    @Published private(set) var bereanStreamingResponseEnabled: Bool = true
    @Published private(set) var bereanVoiceEnabled: Bool = true
    @Published private(set) var bereanAdaptiveModeEnabled: Bool = true
    /// Kill switch: false disables Deep mode for all users instantly via Remote Config.
    @Published private(set) var bereanDeepEnabled: Bool = true
    /// Kill switch: false bypasses server entitlement enforcement for emergency rollback.
    @Published private(set) var bereanEntitlementEnforcementEnabled: Bool = true

    // MARK: - System 3: Spiritual Check-In
    @Published private(set) var spiritualCheckInEnabled: Bool = true
    @Published private(set) var checkInBehavioralSignalsEnabled: Bool = true
    @Published private(set) var checkInCrisisEscalationEnabled: Bool = true

    // MARK: - System 4: Feed Intelligence
    @Published private(set) var feedRankingV2Enabled: Bool = true
    @Published private(set) var antiDoomscrollEnabled: Bool = true
    @Published private(set) var feedSessionPacingEnabled: Bool = true
    @Published private(set) var feedReflectionPromptsEnabled: Bool = true
    @Published private(set) var feedQualityMetricsEnabled: Bool = true

    // MARK: - System 5: Church Discovery
    @Published private(set) var churchDiscoverySmartRankingEnabled: Bool = true
    @Published private(set) var churchFirstVisitCompanionEnabled: Bool = true
    @Published private(set) var churchServiceRemindersEnabled: Bool = true
    @Published private(set) var churchReviewsEnabled: Bool = true
    @Published private(set) var churchInteractionTrackingEnabled: Bool = true
    @Published private(set) var churchJourneyTimelineEnabled: Bool = true
    @Published private(set) var churchPostCardDraftsEnabled: Bool = true
    @Published private(set) var churchExplainableRecommendationsEnabled: Bool = true

    // MARK: - System 6: Studio / Creator Marketplace
    @Published private(set) var studioEnabled: Bool = true
    @Published private(set) var studioMonetizationEnabled: Bool = true
    @Published private(set) var studioJobBoardEnabled: Bool = true
    @Published private(set) var studioAITaggingEnabled: Bool = true

    // MARK: - System 7: Knowledge Graph
    @Published private(set) var knowledgeGraphEnabled: Bool = true
    @Published private(set) var knowledgeGraphRelatedContentEnabled: Bool = true
    @Published private(set) var knowledgeGraphSemanticSearchEnabled: Bool = true

    // MARK: - System 8: Action Threads (Care Workflows)
    @Published private(set) var actionThreadsEnabled: Bool = true
    @Published private(set) var actionSuggestionsEnabled: Bool = true
    @Published private(set) var careFollowupsEnabled: Bool = true
    @Published private(set) var mentorshipEnabled: Bool = true

    // MARK: - System 9: Compound Identity Graph
    @Published private(set) var compoundIdentityGraphEnabled: Bool = true
    @Published private(set) var agentRecommendationsEnabled: Bool = true

    // MARK: - System 10: Proof of Human + Proof of Care
    @Published private(set) var proofOfHumanEnabled: Bool = true
    @Published private(set) var proofOfCareEnabled: Bool = true
    @Published private(set) var trustSignalsEnabled: Bool = true

    // MARK: - System 11: Topic Drill-Down
    @Published private(set) var topicDrillDownEnabled: Bool = true
    @Published private(set) var topicEnrichmentEnabled: Bool = true

    // MARK: - System 12: Smart Media Continuity
    @Published private(set) var mediaResumeEnabled: Bool = true

    // MARK: - System 13: Suggested Follows
    @Published private(set) var suggestedFollowsEnabled: Bool = true
    @Published private(set) var suggestedRailPrayerEnabled: Bool = true
    @Published private(set) var suggestedRailTestimoniesEnabled: Bool = true
    @Published private(set) var suggestedRailPeekSheetEnabled: Bool = true
    @Published private(set) var suggestedRailServerRankingEnabled: Bool = true
    @Published private(set) var suggestedRailInsertionIndex: Int = 2
    @Published private(set) var suggestedRailCardLimit: Int = 12
    @Published private(set) var suggestedRailCooldownHours: Int = 24
    @Published private(set) var suggestedRailDismissCooldownDays: Int = 7

    // MARK: - System 14: Social Context & UX Enhancements
    @Published private(set) var mutualContextRowEnabled: Bool = true
    @Published private(set) var presenceIntelligenceEnabled: Bool = false
    @Published private(set) var messageRequestIntelligenceEnabled: Bool = true
    @Published private(set) var trustExplainerEnabled: Bool = true
    @Published private(set) var postDividerEnabled: Bool = true
    @Published private(set) var feedViewModeSwitcherEnabled: Bool = true
    @Published private(set) var mediaFilterPillsEnabled: Bool = true
    @Published private(set) var mediaDetailViewEnabled: Bool = true
    @Published private(set) var enhancedNotificationsEnabled: Bool = true
    @Published private(set) var serverNotificationsV2Enabled: Bool = true
    @Published private(set) var bereanChatRedesignEnabled: Bool = true
    @Published private(set) var inAppBrowserEnabled: Bool = true
    @Published private(set) var composerApprovedAudioEnabled: Bool = true
    @Published private(set) var smartAttachmentsEnabled: Bool = true
    @Published private(set) var smartAttachmentComposerPasteEnabled: Bool = true
    @Published private(set) var smartAttachmentMusicPickerEnabled: Bool = true
    @Published private(set) var smartAttachmentExpandedSheetEnabled: Bool = true
    @Published private(set) var smartAttachmentMediaGraphEnabled: Bool = true
    @Published private(set) var smartAttachmentSmartActionsEnabled: Bool = true

    // MARK: - System 15: Accessibility Intelligence Layer
    @Published private(set) var accessibilityIntelligenceEnabled: Bool = false
    @Published private(set) var meaningAwareTranslationEnabled: Bool = false
    @Published private(set) var naturalModeEnabled: Bool = false
    @Published private(set) var contextualModeEnabled: Bool = false
    @Published private(set) var readabilityLayerEnabled: Bool = false
    @Published private(set) var contentDifficultyScoring: Bool = false
    @Published private(set) var audioNarrationEnabled: Bool = false
    @Published private(set) var contextBridgeEnabled: Bool = false
    @Published private(set) var adaptiveAccessibilityEnabled: Bool = false
    @Published private(set) var conversationBridgeEnabled: Bool = false
    @Published private(set) var smartTranslationVisibilityEnabled: Bool = false
    @Published private(set) var sideBySideTranslationEnabled: Bool = false
    @Published private(set) var perLanguageAutoTranslateEnabled: Bool = false
    @Published private(set) var creationLanguageEnabled: Bool = false
    @Published private(set) var adaptiveTranslationEnabled: Bool = false

    // MARK: - System 16: Berean Spiritual Intelligence Layers
    @Published private(set) var bereanSpiritualLayersEnabled: Bool = true
    @Published private(set) var livingScriptureGraphEnabled: Bool = true
    @Published private(set) var spiritualStateLayerEnabled: Bool = true
    @Published private(set) var guidedDiscipleshipEnabled: Bool = true
    @Published private(set) var scriptureImmersionEnabled: Bool = true
    @Published private(set) var authorityAlignmentEnabled: Bool = true

    // MARK: - System 17: Resources Intelligence
    @Published private(set) var resourcesIntelligenceEnabled: Bool = true
    @Published private(set) var supportDraftDetectionEnabled: Bool = true
    @Published private(set) var churchNoteCareSummaryEnabled: Bool = true
    @Published private(set) var churchNotesServerSummaryEnabled: Bool = true
    // Church Notes Media Intelligence — keep unapproved processing surfaces OFF unless explicitly flipped.
    @Published private(set) var churchNotesAudioCaptureEnabled: Bool = false
    @Published private(set) var churchNotesPhotoOCREnabled: Bool = false
    @Published private(set) var churchNotesVideoCaptureEnabled: Bool = false
    @Published private(set) var churchNotesAIDraftReviewEnabled: Bool = true
    @Published private(set) var churchNotesStudyGuideEnabled: Bool = true
    @Published private(set) var churchNotesPrayerPromptsEnabled: Bool = true
    @Published private(set) var churchNotesIntelligenceEnabled: Bool = true
    @Published private(set) var sermonAudioCaptureEnabled: Bool = false
    @Published private(set) var sermonVideoCaptureEnabled: Bool = false
    @Published private(set) var churchPhotoOCRCaptureEnabled: Bool = false
    @Published private(set) var churchNotesTranslationEnabled: Bool = true
    @Published private(set) var churchNotesCollaborationEnabled: Bool = true
    @Published private(set) var sermonSummaryGenerationEnabled: Bool = true
    @Published private(set) var scriptureDetectionEnabled: Bool = true
    @Published private(set) var apiBibleScriptureProviderEnabled: Bool = false
    @Published private(set) var apiBibleLicensedDisplayTranslationsEnabled: Bool = false
    @Published private(set) var apiBibleCoreOfflineCacheEnabled: Bool = false
    @Published private(set) var sermonActionExtractionEnabled: Bool = true
    @Published private(set) var sermonClipSuggestionEnabled: Bool = true
    @Published private(set) var churchNotesStudyGuideGenerationEnabled: Bool = true
    /// Gates NOTE_SHARE_VIEWER. Default OFF until Wave 1 implements callables and UI.
    @Published private(set) var noteShareViewerEnabled: Bool = false
    /// Gates Church Notes Smart Objects and Liquid Glass post cards. Default OFF until Wave 1 is verified.
    @Published private(set) var churchNotesSmartObjectsEnabled: Bool = false
    // Kill switch: set true in Remote Config to block all new processing jobs instantly.
    @Published private(set) var churchNotesProcessingKillSwitch: Bool = false
    // Per-media-type kill switches — allow emergency rollback of one pipeline without
    // touching the others. Each defaults false (pipeline active) and is overridden by
    // Remote Config. A true value blocks only that media type; the master kill switch
    // above blocks all types simultaneously.
    @Published private(set) var churchNotesAudioProcessingKillSwitch: Bool = false
    @Published private(set) var churchNotesImageModerationKillSwitch: Bool = false
    @Published private(set) var churchNotesVideoProcessingKillSwitch: Bool = false
    @Published private(set) var trustedContactsEnabled: Bool = true
    @Published private(set) var helpingSomeoneElseEnabled: Bool = true
    @Published private(set) var supportFollowupsEnabled: Bool = true
    @Published private(set) var nonprofitRecommendationEnabled: Bool = true
    @Published private(set) var bereanResourceRoutingEnabled: Bool = true

    // MARK: - Selah Scripture Actions (command bar: Save/Reflect/Berean/Continue)
    @Published private(set) var selahScriptureActionsEnabled: Bool = true
    @Published private(set) var churchStudyCompanionEnabled: Bool = true
    @Published private(set) var churchNotesScriptureBridgeEnabled: Bool = true
    @Published private(set) var selahAddToChurchNotesEnabled: Bool = true
    @Published private(set) var findChurchStudyActionsEnabled: Bool = true
    @Published private(set) var afterServiceReflectionEnabled: Bool = true
    @Published private(set) var churchStudyGroupBridgeEnabled: Bool = true

    // MARK: - System 18: Selah Media OS
    @Published private(set) var selahMediaOSEnabled: Bool = true
    @Published private(set) var selahMediaOSMinAppVersion: String = "1.0.0"
    @Published private(set) var selahMediaOSRolloutPercent: Int = 100
    @Published private(set) var selahMediaOSKillReason: String = ""

    // MARK: - Onboarding & Auth Remediation (Wave 1)
    /// Master gate for the onboarding/auth remediation (see contracts/onboarding/).
    /// Default OFF in production until the new continuous flow, canonical GlassButton,
    /// Keychain identity hint, and E2EE recovery handoff are validated end-to-end.
    @Published private(set) var onboardingV2Enabled: Bool = false

    // MARK: - System 19: Berean Pulse
    @Published private(set) var bereanPulseEnabled: Bool = true

    // MARK: - Amen Pulse (Personalized Daily Surface)
    /// Master gate for the bounded App-Store-Today daily surface (Pulse/ module).
    /// Default OFF until the generation pipeline is deployed and the surface is verified.
    @Published private(set) var amenPulseEnabled: Bool = false

    // MARK: - Universal Migration & Context System
    /// Master gate for the Context System (ContextStore Passport, Migration Interview,
    /// Universal Import, matching, exports). Default OFF until each wave is validated.
    /// Nothing in the Context System is user-visible unless this is true.
    @Published private(set) var contextSystemEnabled: Bool = false
    /// Wave 1: manual facet entry + Identity Blueprint + Faith Journey Builder.
    @Published private(set) var contextManualEntryEnabled: Bool = false
    /// Wave 2: Berean Migration Interview (adaptive conversational onboarding).
    @Published private(set) var contextBereanInterviewEnabled: Bool = false
    /// Wave 3: Universal Extractor (paste/upload) + Approval UI.
    @Published private(set) var contextUniversalImportEnabled: Bool = false
    /// Wave 4: feed initialization + Community DNA matching + introduction generation.
    @Published private(set) var contextMatchingEnabled: Bool = false
    /// Wave 5: .amen export + Personal Operating Manual + Life Capsule projections.
    @Published private(set) var contextExportEnabled: Bool = false
    /// Wave 5: Context QR (public-visibility projection). Server-enforced OFF for minors (Aegis C60).
    @Published private(set) var contextQREnabled: Bool = false
    /// Wave 4: Commitment Bridge — turn a Tier-C goal facet into a real Commitment Object.
    @Published private(set) var contextCommitmentBridgeEnabled: Bool = false

    // MARK: - Amen Daily Digest
    @Published private(set) var amenDailyDigestEnabled: Bool = true
    @Published private(set) var amenDailyDigestWeatherEnabled: Bool = true
    @Published private(set) var amenDailyDigestHolidayEnabled: Bool = true
    @Published private(set) var amenDailyDigestChristianCalendarEnabled: Bool = true
    @Published private(set) var amenDailyDigestExpandedSheetEnabled: Bool = true
    @Published private(set) var amenDailyDigestBereanAIActionEnabled: Bool = true
    @Published private(set) var amenDailyDigestChurchNotesActionEnabled: Bool = true
    @Published private(set) var amenDailyDigestFindChurchActionEnabled: Bool = true
    @Published private(set) var amenDailyDigestSelahActionEnabled: Bool = true
    @Published private(set) var amenDailyDigestAIReflectionEnabled: Bool = true

    // MARK: - System 22: Community Hubs & Object Intelligence
    // Default OFF in all configurations until Remote Config activates a verified rollout.
    #if DEBUG
    @Published private(set) var communityHubsEnabled: Bool = false
    @Published private(set) var communityObjectMatchingEnabled: Bool = false
    @Published private(set) var lyricDetectionEnabled: Bool = false
    @Published private(set) var objectHubViewEnabled: Bool = false
    @Published private(set) var objectHubInlinePillEnabled: Bool = false
    @Published private(set) var objectHubInlineClusterEnabled: Bool = false
    #else
    @Published private(set) var communityHubsEnabled: Bool = false
    @Published private(set) var communityObjectMatchingEnabled: Bool = false
    @Published private(set) var lyricDetectionEnabled: Bool = false
    @Published private(set) var objectHubViewEnabled: Bool = false
    @Published private(set) var objectHubInlinePillEnabled: Bool = false
    @Published private(set) var objectHubInlineClusterEnabled: Bool = false
    #endif

    // MARK: - Communities / Threads-Style Feeds Gating
    // Ark legacy /communities path is unsafe at the rules layer until callable-protected.
    // Default OFF in production until the legacy code is fully retired or hardened.
    @Published private(set) var arkCommunitiesEnabled: Bool = false
    // Covenant is canonical for tiered creator communities.
    @Published private(set) var covenantCommunitiesEnabled: Bool = false
    // Unified Threads-style Feeds switcher (For You / Following / Quiet / Your / Saved / Popular).
    @Published private(set) var unifiedFeedsSwitcherEnabled: Bool = false
    // Community-level Saved / Bookmark.
    @Published private(set) var savedCommunitiesEnabled: Bool = false
    // "View in Feed" — scopes the home timeline to a covenant/hub/topic.
    @Published private(set) var viewInFeedEnabled: Bool = false

    // MARK: - System 22 continued: Smart Share Sheet
    @Published private(set) var smartShareSheetEnabled: Bool = true
    @Published private(set) var smartShareSmartSuggestionsEnabled: Bool = true
    @Published private(set) var smartShareRecipientRailEnabled: Bool = true
    @Published private(set) var smartShareContextEnabled: Bool = true
    @Published private(set) var smartSharePreviewModeEnabled: Bool = true

    // MARK: - System 22 continued: Translation Intelligence
    @Published private(set) var translationSmartPillEnabled: Bool = true
    @Published private(set) var translationRememberLanguagePreferenceEnabled: Bool = true

    // MARK: - System 23: Universal Content + Create
    @Published private(set) var universalContentModelEnabled: Bool = true
    @Published private(set) var universalCreateEnabled: Bool = true

    // MARK: - System 24: Media Creation System
    @Published private(set) var mediaCreationEnabled: Bool = true
    @Published private(set) var videoUploadEnabled: Bool = true
    @Published private(set) var voiceoverEnabled: Bool = true
    @Published private(set) var autoCaptionsEnabled: Bool = true
    @Published private(set) var immersiveMediaChromeEnabled: Bool = true
    @Published private(set) var immersiveFeedEnabled: Bool = true
    @Published private(set) var continuationFeedEnabled: Bool = true
    @Published private(set) var explainVideoEnabled: Bool = true
    @Published private(set) var explainVideoRolloutPercent: Int = 100
    @Published private(set) var explainVideoMinAppVersion: String = "1.0.0"
    @Published private(set) var explainVideoKillReason: String = ""    // non-empty = kill switch active

    // MARK: - System 24 (extension): Per-Media Captions
    /// Master switch: enables per-media caption composer and swipe-caption rendering.
    @Published private(set) var perMediaCaptionsEnabled: Bool = true
    /// Gates the one-time "A new caption with every swipe" education modal.
    @Published private(set) var perMediaCaptionEducationEnabled: Bool = true
    /// When true, each media caption is moderated before publish.
    @Published private(set) var perMediaCaptionModerationEnabled: Bool = true
    /// Gates the alt text field in the caption composer.
    @Published private(set) var perMediaCaptionAltTextEnabled: Bool = true
    /// Gates the scripture reference chips in the caption composer.
    @Published private(set) var perMediaCaptionScriptureRefsEnabled: Bool = true

    // MARK: - System 21: Berean Intelligence Layer v2
    /// Kill switch: false disables all three theological lens modes (Wisdom/Prayer/Discernment) instantly.
    @Published private(set) var bereanTheoLensEnabled: Bool = true
    /// Gates the Selah bridge (Save to Selah from Berean).
    @Published private(set) var bereanSelahBridgeEnabled: Bool = true
    /// Gates the Church Notes bridge (Save to Church Notes from Berean).
    @Published private(set) var bereanChurchNotesBridgeEnabled: Bool = true
    /// Gates mode-aware + safety-aware smart pills.
    @Published private(set) var bereanSmartPillsEnabled: Bool = true
    /// Gates the theology boundary / hard-block scrubber (always-on by default; kill only for debugging).
    @Published private(set) var bereanTheologyBoundaryEnabled: Bool = true
    /// Gates the persistent study memory UI and consent flow.
    @Published private(set) var bereanPersistentMemoryEnabled: Bool = true
    /// Gates study thread continuity (Create/Resume study threads).
    @Published private(set) var bereanStudyThreadsEnabled: Bool = true
    /// Gates translation comparison feature.
    @Published private(set) var bereanTranslationCompareEnabled: Bool = true
    /// Gates the research view (expandable source metadata panel).
    @Published private(set) var bereanResearchViewEnabled: Bool = true

    // MARK: - System 20: Messaging Micro Animations (Layer 1 + Layer 2)
    @Published private(set) var messagingLiquidGlassAnimationsEnabled: Bool = true
    @Published private(set) var messagingTypingIndicatorEnabled: Bool = true
    /// Floating header prototype: replaces system nav bar with detached capsule.
    /// Default OFF until nav replacement is fully validated on all device sizes.
    @Published private(set) var messagingFloatingHeaderPrototypeEnabled: Bool = false
    @Published private(set) var messagingLiquidGlassContextMenuEnabled: Bool = false
    @Published private(set) var messagingLiquidGlassAttachmentMenuEnabled: Bool = false
    @Published private(set) var messagingSmartComposerEnabled: Bool = false
    @Published private(set) var messagingAttachmentMenuSmartActionsEnabled: Bool = false

    // MARK: - System 20 continued: Messaging Intelligence (Phases 4-12)
    @Published private(set) var messagingSmartPillsEnabled: Bool = false
    @Published private(set) var messagingTranslationEnabled: Bool = false
    @Published private(set) var messagingCrossSurfaceActionsEnabled: Bool = false
    @Published private(set) var messagingSafetyNudgesEnabled: Bool = true
    @Published private(set) var messagingApprovalCardsEnabled: Bool = false
    @Published private(set) var messagingCatchUpEnabled: Bool = false
    @Published private(set) var messagingVoiceIntelligenceEnabled: Bool = false
    @Published private(set) var messagingMediaIntelligenceEnabled: Bool = false
    @Published private(set) var messagingPresencePolishEnabled: Bool = false
    @Published private(set) var actionIntelligenceEnabled: Bool = false
    /// Gates CameraOS Context Lens and the full-screen camera capture surface.
    /// Default OFF until CameraOS rules/index coverage and runtime privacy review are verified.
    @Published private(set) var cameraOSEnabled: Bool = false

    // MARK: - Communication OS (System 32: Next-Gen Messaging + Group Discussions)
    @Published private(set) var messagesSmartContextEnabled: Bool = false
    @Published private(set) var groupDiscussionPulseEnabled: Bool = false
    @Published private(set) var threadSummaryEnabled: Bool = false
    @Published private(set) var catchUpDigestEnabled: Bool = false
    @Published private(set) var threadDecisionExtractionEnabled: Bool = false
    @Published private(set) var threadActionExtractionEnabled: Bool = false
    @Published private(set) var threadQuestionDetectionEnabled: Bool = false
    @Published private(set) var smartPresenceEnabled: Bool = false
    @Published private(set) var smartReactionsEnabled: Bool = false
    @Published private(set) var mediaIntelligenceEnabled: Bool = false
    @Published private(set) var conversationMemorySearchEnabled: Bool = false
    @Published private(set) var commandPaletteEnabled: Bool = false
    @Published private(set) var smartRepliesEnabled: Bool = false
    @Published private(set) var multiPaneCommunicationEnabled: Bool = false
    @Published private(set) var liquidGlassCommunicationUIEnabled: Bool = false

    // MARK: - ContentOS (System 33: Content Discussion, Approval & Forwarding)
    @Published private(set) var contentOSEnabled: Bool = false
    @Published private(set) var contentApprovalWorkflowEnabled: Bool = false
    @Published private(set) var contentForwardingEnabled: Bool = false
    @Published private(set) var contentAIRouterEnabled: Bool = false
    @Published private(set) var contentAuditLogEnabled: Bool = false

    // MARK: - Social Safety OS (Phase 2–13)
    // DEFERRED-DESIGN: all flags in this block are declared, defaulted, and RC-applied
    // but have ZERO consumer call-sites in any view, service, or guard. They claim to
    // control wellbeing/safety surfaces but nothing checks them yet. Wire-up is pending
    // Safety OS v3 surface design. Do NOT flip OFF — keep true so consumers work when wired.
    // GAP A5-P1 DEFERRED-DESIGN documentation.
    @Published private(set) var socialSafetyOSEnabled: Bool = true
    @Published private(set) var wellbeingFeedRankingEnabled: Bool = true
    @Published private(set) var selahPauseEnabled: Bool = true
    @Published private(set) var emotionalCheckInEnabled: Bool = true
    @Published private(set) var privateReflectionEnabled: Bool = true
    @Published private(set) var healthyUseDashboardEnabled: Bool = true
    @Published private(set) var dmRiskFirewallEnabled: Bool = true
    @Published private(set) var minorSafetyModeEnabled: Bool = true
    @Published private(set) var sextortionPanicFlowEnabled: Bool = true
    @Published private(set) var suspiciousRelationshipDetectorEnabled: Bool = true
    @Published private(set) var trustedContactEscalationEnabled: Bool = true
    @Published private(set) var thinkFirstGuardEnabled: Bool = true
    @Published private(set) var dogpileDetectionEnabled: Bool = true
    @Published private(set) var mercyModeRepliesEnabled: Bool = true
    @Published private(set) var reputationModerationEnabled: Bool = true
    @Published private(set) var victimShieldEnabled: Bool = true
    @Published private(set) var truthContextLayerEnabled: Bool = true
    @Published private(set) var aiMediaDisclosureEnabled: Bool = true
    @Published private(set) var claimSourceRequirementEnabled: Bool = true
    @Published private(set) var communityCorrectionEnabled: Bool = true
    @Published private(set) var theologicalGuardrailsEnabled: Bool = true
    @Published private(set) var feedModeControlsEnabled: Bool = true
    @Published private(set) var feedBoundaryEnabled: Bool = true
    @Published private(set) var purposeOpenScreenEnabled: Bool = true
    @Published private(set) var engagementQualityRankingEnabled: Bool = true
    @Published private(set) var algorithmTransparencyEnabled: Bool = true

    // MARK: - Berean Extended Intelligence (Phases 2–8)
    @Published private(set) var bereanContextBridgeEnabled: Bool = false
    @Published private(set) var bereanSafetyClassifierEnabled: Bool = false
    @Published private(set) var bereanLiquidGlassContextActionsEnabled: Bool = false
    @Published private(set) var bereanSourceGroundingEnabled: Bool = false
    @Published private(set) var bereanFollowUpsEnabled: Bool = false
    @Published private(set) var bereanCommentaryCompareEnabled: Bool = false
    @Published private(set) var bereanTheologicalLensEnabled: Bool = false
    // Kill switches (override feature flags — fail closed)
    @Published private(set) var bereanMemoryKillSwitch: Bool = false
    @Published private(set) var bereanContextBridgeKillSwitch: Bool = false
    @Published private(set) var bereanSafetyClassifierKillSwitch: Bool = false
    @Published private(set) var bereanStudyThreadsKillSwitch: Bool = false
    @Published private(set) var bereanSourceGroundingKillSwitch: Bool = false

    // MARK: - System 25: Smart Account Resume
    /// Gates the full Smart Account Resume / one-tap login experience.
    @Published private(set) var smartAccountResumeEnabled: Bool = true
    /// When true, resumes automatically after token validation (skips the Continue button).
    @Published private(set) var smartAccountResumeAutoContinueEnabled: Bool = true
    /// When true, shows an offline-retry screen instead of routing to login on network failure.
    @Published private(set) var smartAccountResumeOfflineRetryEnabled: Bool = true

    // MARK: - System 26: AI Usage Labels
    /// Kill switch: false removes the AI label pill from all post cards instantly.
    @Published private(set) var aiUsageLabelPillEnabled: Bool = true

    // MARK: - System 27: Berean Grok Helper Pipeline
    /// Master kill switch: false disables the entire Grok/helper pipeline instantly.
    @Published private(set) var bereanHelperModelEnabled: Bool = false
    /// Gates prompt simplification (Flow 2).
    @Published private(set) var bereanHelperPromptSimplifyEnabled: Bool = false
    /// Gates link summarization (Flow 3).
    @Published private(set) var bereanHelperLinkSummaryEnabled: Bool = false
    /// Gates external/public context (Flow 4).
    @Published private(set) var bereanHelperExternalContextEnabled: Bool = false
    /// Gates study outline generation.
    @Published private(set) var bereanHelperStudyOutlineEnabled: Bool = false
    /// Gates extract-themes pill for links.
    @Published private(set) var bereanHelperExtractThemesEnabled: Bool = false
    /// Kill switch: false removes the "AI-assisted" provenance chip from all answers.
    @Published private(set) var bereanHelperProvenanceChipsEnabled: Bool = false

    // MARK: - Profile V2
    @Published private(set) var profileV2Enabled: Bool = true
    @Published private(set) var profileMediaGridEnabled: Bool = true
    @Published private(set) var pinnedContentEnabled: Bool = true
    @Published private(set) var creatorHighlightsEnabled: Bool = true

    // MARK: - System 28: Feed Intelligence OS
    /// Master kill switch for Guide My Feed and all feed personalization features.
    @Published private(set) var feedIntelligenceEnabled: Bool = false
    /// Gates the Guide My Feed composer chip and GuideMyFeedSheet.
    @Published private(set) var guideMyFeedEnabled: Bool = false
    /// When true, uses the backend-driven FeedIntelligenceWhyThisPostSheet.
    @Published private(set) var whyThisPostBackendEnabled: Bool = false
    /// When true, feed modes (Berean, Worship, etc.) appear in FeedIntelligenceSettingsView.
    @Published private(set) var feedModesEnabled: Bool = false

    // MARK: - System 29: Liquid Glass Intelligence Layer
    /// Master switch for all Liquid Glass intelligence features.
    @Published private(set) var liquidGlassSystemEnabled: Bool = false
    /// Enables AmenPresencePillStack — contextual AI action pills (max 3).
    @Published private(set) var liquidGlassPresencePillsEnabled: Bool = false
    /// Enables dotted underlines on high-confidence semantic terms in posts/notes.
    @Published private(set) var semanticUnderlineEnabled: Bool = false
    /// Enables the inline definition popover when a semantic term is tapped.
    @Published private(set) var inlineDefinitionPopoverEnabled: Bool = false
    /// Enables server-driven smart action detection via detectSmartActions CF.
    @Published private(set) var smartActionDetectionEnabled: Bool = false
    /// Enables Pulse awareness — UI adaptation based on interaction signals.
    @Published private(set) var pulseAwarenessEnabled: Bool = false
    /// Enables saving semantic insights as knowledge threads.
    @Published private(set) var knowledgeThreadsEnabled: Bool = false
    /// Enables "Save to Selah" from inline definition popover.
    @Published private(set) var selahSemanticSaveEnabled: Bool = false
    /// Enables AI semantic actions inside Church Notes toolbar.
    @Published private(set) var churchNotesSemanticActionsEnabled: Bool = false
    /// Enables Liquid Glass chrome for media player controls.
    @Published private(set) var mediaChromeLiquidGlassEnabled: Bool = false
    /// Enables Pulse-driven smart action pills inside the post composer.
    @Published private(set) var composerPresenceActionsEnabled: Bool = false
    /// Enables the Liquid Glass bottom bar (replaces solid bar when true).
    @Published private(set) var bottomBarLiquidGlassEnabled: Bool = false

    // MARK: - System 36: Context-First Discussion OS
    @Published private(set) var discussionModesEnabled: Bool = true
    @Published private(set) var contextParticipationEnabled: Bool = true
    @Published private(set) var discussionHealthEnabled: Bool = true
    @Published private(set) var draftIntelligenceEnabled: Bool = true
    @Published private(set) var discussionSummaryEnabled: Bool = true
    @Published private(set) var discussionMediatorEnabled: Bool = true
    @Published private(set) var communityMemoryEnabled: Bool = true
    @Published private(set) var discussionActionsEnabled: Bool = true
    @Published private(set) var participationTiersEnabled: Bool = true
    @Published private(set) var discussionCommandCenterEnabled: Bool = true

    // MARK: - System 37: Community OS Foundation
    /// Master switch for the Community OS Core Spine (Phase 1).
    /// Gates TransformEngine, EdgeService, RBACService, and AuditLogService.
    /// Default OFF until Phase 1 is validated and deployed.
    @Published private(set) var communityOSEnabled: Bool = false

    // MARK: - Ambient OS
    /// Master switch for Ambient OS surfaces and callable-backed context snapshots.
    /// Default OFF until privacy review, Aegis review, and fleet verification are complete.
    @Published private(set) var ambientOSEnabled: Bool = false
    /// Master switch for Community OS Discussion rooms (A6).
    /// Gates DiscussionRoomView, DiscussionProvenanceBanner, DiscussionFollowUpPrompt,
    /// and the provenance banner injection in DiscussionThreadView.
    /// Default OFF — enable via Remote Config only after Phase 1 Firestore paths are verified.
    @Published private(set) var communityOSDiscussionEnabled: Bool = false
    /// Master switch for Community OS Prayer OS (A7).
    /// Gates PrayerRoomView, PrayerPrivacySelector, PrayerPartnerRow, PrayerUpdateSheet.
    /// Default false — enable via Remote Config once prayer Firestore paths are deployed.
    @Published private(set) var communityOSPrayerOSEnabled: Bool = false

    // MARK: - System 38: Connect Hub
    @Published private(set) var connectHubEnabled: Bool = true
    @Published private(set) var connectYouMenuEnabled: Bool = true

    // MARK: - System 39: Connect UI Polish Waves (default OFF — flip in Remote Config after verification)
    @Published private(set) var connectLayoutV2Enabled: Bool = false
    @Published private(set) var connectPolishV2Enabled: Bool = false
    @Published private(set) var connectEmptyStatesEnabled: Bool = false
    @Published private(set) var connectSmartBereanEnabled: Bool = false
    @Published private(set) var connectOfflineQueueEnabled: Bool = false

    // MARK: - Cross-cutting
    @Published private(set) var analyticsEnabled: Bool = true
    @Published private(set) var performanceTelemetryEnabled: Bool = true
    
    // MARK: - Discover Surface (Amen Discover)
    @Published private(set) var amenDiscoverEnabled: Bool = true
    @Published private(set) var amenDiscoverLiquidGlassEnabled: Bool = true
    @Published private(set) var amenDiscoverRankingEnabled: Bool = true
    @Published private(set) var amenDiscoverWhyThisEnabled: Bool = true
    @Published private(set) var amenDiscoverLocalChurchesEnabled: Bool = true
    @Published private(set) var amenDiscoverSelahEnabled: Bool = true
    @Published private(set) var amenDiscoverSafetyFeedbackEnabled: Bool = true

    // MARK: - System 31: Voice Prayer & Testimony Comments
    /// Master kill switch: disables all voice comment UI instantly when false.
    @Published private(set) var voicePrayerCommentsEnabled: Bool = false
    /// Gates the "Share Testimony" voice button on testimony posts.
    @Published private(set) var voiceTestimonyCommentsEnabled: Bool = false
    /// When true, a transcript must exist before a voice comment can publish.
    @Published private(set) var voiceCommentTranscriptRequired: Bool = true
    /// Enables AI-generated safety summaries on published voice comments.
    @Published private(set) var voiceCommentSummaryEnabled: Bool = false
    /// Enables the held_for_review moderation queue for voice comments.
    @Published private(set) var voiceCommentReviewQueueEnabled: Bool = false
    /// Enables the Prayer Circle visibility option in the visibility picker.
    @Published private(set) var voiceCommentPrayerCircleVisibilityEnabled: Bool = false

    // MARK: - Amen AI Creative Intelligence Layer
    @Published private(set) var amenRealtimeVoiceEnabled: Bool = false
    @Published private(set) var amenLiveCaptionsEnabled: Bool = false
    @Published private(set) var amenTranslationEnabled: Bool = false
    @Published private(set) var amenGraphicStudioEnabled: Bool = false
    @Published private(set) var amenCreatorKitEnabled: Bool = false
    @Published private(set) var amenAgentWorkflowsEnabled: Bool = false
    @Published private(set) var amenExplainEnabled: Bool = false
    @Published private(set) var amenImproveEnabled: Bool = false
    @Published private(set) var amenSummarizeEnabled: Bool = false
    @Published private(set) var amenAIUsageLabelsRequired: Bool = true
    @Published private(set) var simpleModeFeatureEnabled: Bool = true
    @Published private(set) var replayEnabled: Bool = true

    @Published private(set) var bereanRealtimeEnabled: Bool = false
    @Published private(set) var bereanTranslationEnabled: Bool = false
    @Published private(set) var bereanPrayerRoomsEnabled: Bool = false
    @Published private(set) var bereanVoiceAssistantEnabled: Bool = false
    @Published private(set) var bereanSmartNotesEnabled: Bool = false
    @Published private(set) var bereanLiveCaptionsEnabled: Bool = false
    @Published private(set) var bereanRealtimeKillSwitch: Bool = false

    @Published private(set) var amenRealtimeVoiceKillSwitch: Bool = false
    @Published private(set) var amenLiveCaptionsKillSwitch: Bool = false
    @Published private(set) var amenTranslationKillSwitch: Bool = false
    @Published private(set) var amenGraphicGenerationKillSwitch: Bool = false
    @Published private(set) var amenAgentWorkflowKillSwitch: Bool = false
    @Published private(set) var amenExplainKillSwitch: Bool = false
    @Published private(set) var amenImproveKillSwitch: Bool = false
    @Published private(set) var amenSummarizeKillSwitch: Bool = false

    // MARK: - System 33: Spatial Social OS
    @Published private(set) var spatialHomeEnabled: Bool = false
    @Published private(set) var spatialContextRailEnabled: Bool = false
    @Published private(set) var provenanceTrustPanelEnabled: Bool = false
    @Published private(set) var creatorOSComposerEnabled: Bool = false
    @Published private(set) var truthfulAILabelsEnabled: Bool = false
    @Published private(set) var smartDiscoveryTransparencyEnabled: Bool = false
    @Published private(set) var discoveryWhyShownEnabled: Bool = false
    @Published private(set) var safetyOSEnabled: Bool = true

    // MARK: - System 34: Healthy Immersive Media Sessions
    @Published private(set) var healthyImmersiveMediaEnabled: Bool = false
    @Published private(set) var immersiveMediaSessionsEnabled: Bool = false
    @Published private(set) var mediaFiniteSessionsEnabled: Bool = true
    @Published private(set) var finiteMediaQueuesEnabled: Bool = true
    @Published private(set) var mediaCompletionReflectionEnabled: Bool = false
    @Published private(set) var mediaCompletionOverlayEnabled: Bool = false
    @Published private(set) var mediaDoomScrollGuardEnabled: Bool = true
    @Published private(set) var mediaNoDoomScrollGuardrailsEnabled: Bool = true
    @Published private(set) var mediaSessionCheckpointsEnabled: Bool = true
    @Published private(set) var healthyMediaCheckpointsEnabled: Bool = true
    @Published private(set) var mediaKeyMomentsEnabled: Bool = false
    @Published private(set) var mediaTranscriptEnabled: Bool = true
    @Published private(set) var mediaAIDraftMetadataEnabled: Bool = false
    @Published private(set) var mediaAIMetadataDraftsEnabled: Bool = false
    @Published private(set) var mediaApprovalFlowEnabled: Bool = false
    @Published private(set) var mediaGeneratedMetadataApprovalRequired: Bool = true
    @Published private(set) var mediaLowBandwidthModeEnabled: Bool = true
    @Published private(set) var mediaSelahAudioModeEnabled: Bool = true
    @Published private(set) var mediaSelahOverlayEnabled: Bool = true
    @Published private(set) var immersivePhotoSessionsEnabled: Bool = false
    @Published private(set) var immersiveVideoSessionsEnabled: Bool = false
    @Published private(set) var communityMediaLayersEnabled: Bool = false
    @Published private(set) var mediaCommunityLayerEnabled: Bool = false
    @Published private(set) var mediaReflectionSheetEnabled: Bool = false
    @Published private(set) var hideVanityMetricsDefault: Bool = true
    @Published private(set) var autoplayWithinSessionsEnabled: Bool = false
    @Published private(set) var lateNightPauseEnabled: Bool = true
    @Published private(set) var mediaWellbeingControlsEnabled: Bool = true
    @Published private(set) var mediaTimestampedCommentsEnabled: Bool = false
    @Published private(set) var mediaSearchEnabled: Bool = false
    @Published private(set) var mediaChurchNotesIntegrationEnabled: Bool = false
    @Published private(set) var mediaPrayerQueueEnabled: Bool = false
    @Published private(set) var mediaReflectionQueueEnabled: Bool = false
    @Published private(set) var mediaReportingEnabled: Bool = true
    @Published private(set) var mediaAccessibilityControlsEnabled: Bool = true
    @Published private(set) var mediaHideVanityMetricsEnabled: Bool = true
    @Published private(set) var mediaRankingV2Enabled: Bool = true
    @Published private(set) var mediaLiquidGlassChromeEnabled: Bool = false
    @Published private(set) var mediaProfileLiquidWhiteFlowEnabled: Bool = false

    // MARK: - System 35: Provenance & Authenticity OS
    @Published private(set) var mediaAuthenticityBadgesEnabled: Bool = false
    @Published private(set) var syntheticMediaDetectionEnabled: Bool = false
    @Published private(set) var mediaSyntheticDetectionEnabled: Bool = false
    @Published private(set) var contentCredentialsEnabled: Bool = false
    @Published private(set) var provenanceAuditChainEnabled: Bool = false

    // MARK: - Berean OS (Wisdom Operating System)
    /// Master switch: gates the Berean OS Hub entry point.
    @Published private(set) var bereanOSProjectsEnabled: Bool = false
    /// Research Engine: web + scripture research pipeline.
    @Published private(set) var bereanOSResearchEngineEnabled: Bool = false
    /// Wisdom Engine: structured wisdom analysis on any topic.
    @Published private(set) var bereanOSWisdomEngineEnabled: Bool = false
    /// Multi-Perspective: balanced multi-viewpoint theological analysis.
    @Published private(set) var bereanOSMultiPerspectiveEnabled: Bool = false
    /// Debate Engine: structured pro/con argument generation.
    @Published private(set) var bereanOSDebateEngineEnabled: Bool = false
    /// Social Knowledge Feed: community-curated knowledge items.
    @Published private(set) var bereanOSSocialKnowledgeFeedEnabled: Bool = false
    /// Advisory Boards: AI advisor board consultation.
    @Published private(set) var bereanOSAdvisoryBoardsEnabled: Bool = false
    /// Mentor OS: real + AI mentor relationship management.
    @Published private(set) var bereanOSMentorOSEnabled: Bool = false
    /// Knowledge Graph: personal concept-node knowledge graph.
    @Published private(set) var bereanOSKnowledgeGraphEnabled: Bool = false
    /// Onboarding: first-run onboarding flow for Berean OS.
    @Published private(set) var bereanOSOnboardingEnabled: Bool = false
    /// Memory Brain: project-scoped memory/insight extraction.
    @Published private(set) var bereanOSMemoryBrainEnabled: Bool = false
    /// Action Planner: AI-generated milestone-based action plans.
    @Published private(set) var bereanOSActionPlannerEnabled: Bool = false
    /// Truth Labels: epistemic status classification on claims.
    @Published private(set) var bereanOSTruthLabelsEnabled: Bool = false
    /// Source Explorer: deep source quality + citation explorer.
    @Published private(set) var bereanOSSourceExplorerEnabled: Bool = false
    /// Social Projects: publish + share projects with the community.
    @Published private(set) var bereanOSSocialProjectsEnabled: Bool = false
    /// Community Intelligence: collaborative knowledge actions.
    @Published private(set) var bereanOSCommunityIntelligenceEnabled: Bool = false
    /// Living Documents: AI-collaborative document writing.
    @Published private(set) var bereanOSLivingDocumentsEnabled: Bool = false

    // MARK: - Community OS (A18 Action Pill + A3 Universal Composer)
    /// Gates the universal AmenActionPill on all object views.
    @Published private(set) var communityOSActionPillEnabled: Bool = false
    /// Gates the AmenUniversalComposer bottom sheet creation surface.
    @Published private(set) var communityOSUniversalComposerEnabled: Bool = false

    // MARK: - Aegis OS — Pre-Post Content Safety Gate
    /// Gates `AmenPrePostReviewSheet` running before every post submission.
    /// Default true — this is a safety gate; disable only via Remote Config for emergency rollback.
    @Published private(set) var aegisPrePostReviewEnabled: Bool = true

    // MARK: - Community OS — Church OS / Org OS / Opportunity OS (A8–A10)
    /// Church OS: ChurchObjectHub + ChurchCapabilitySection.
    @Published private(set) var communityOSChurchOSEnabled: Bool = false
    /// Org OS: OrgProfileView + OrgAnnouncementBanner + OrgMemberCountBadge.
    @Published private(set) var communityOSOrgOSEnabled: Bool = false
    /// Opportunity OS: OpportunityCard + OpportunityHubView + SafeContactFlow.
    @Published private(set) var communityOSOpportunityEnabled: Bool = false

    // MARK: - Music Attachment
    /// Gates the music attachment picker in the post composer and the MusicCard renderer in post cards.
    @Published private(set) var musicAttachmentEnabled: Bool = true

    // MARK: - Live Activities — Prayer (Phases 2 & 3)
    /// Gates the push-driven Prayer Request Live Activity. Default false until APNs secrets are set and CFs deployed.
    @Published private(set) var liveActivityPrayerRequestEnabled: Bool = false
    /// Gates push-to-start for Prayer Request (iOS 17.2+).
    @Published private(set) var liveActivityPushToStartEnabled: Bool = false

    // MARK: - Conversation OS (Spaces Intelligence)
    /// Master switch for the Intelligent Conversation OS.
    @Published private(set) var conversationOSEnabled: Bool = false
    /// AI summary generation for spaces.
    @Published private(set) var conversationSummariesEnabled: Bool = false
    /// Catch-up recap banner and sheet.
    @Published private(set) var catchUpRecapsEnabled: Bool = false
    /// Semantic topic cluster extraction.
    @Published private(set) var topicClusteringEnabled: Bool = false
    /// Action item and decision extraction from threads.
    @Published private(set) var actionExtractionEnabled: Bool = false
    /// Org-level weekly memory persistence and query.
    @Published private(set) var organizationalMemoryEnabled: Bool = false
    /// Role-aware personalized summaries.
    @Published private(set) var personalizedInsightsEnabled: Bool = false
    /// Ambient top banner with catch-up / topic / action chips.
    @Published private(set) var ambientConversationIntelligenceEnabled: Bool = false
    /// Liquid Glass rendering for ConversationOS cards.
    @Published private(set) var conversationOSLiquidGlassEnabled: Bool = false
    /// Verbose debug telemetry for ConversationOS (staff/QA only).
    @Published private(set) var conversationOSDebugTelemetryEnabled: Bool = false
    /// Block AI access to sensitive spaces unless explicitly opted in.
    @Published private(set) var conversationOSSensitiveSpaceRestrictionsEnabled: Bool = false

    // MARK: - Find Church 2.0 (all default OFF — flip via Remote Config after verification)
    @Published private(set) var findChurch2OnboardingEnabled: Bool = false
    @Published private(set) var findChurch2MatchExplainEnabled: Bool = false
    @Published private(set) var findChurch2GatheringsEnabled: Bool = false
    @Published private(set) var findChurch2VisitPlannerEnabled: Bool = false
    @Published private(set) var findChurch2ClaimPortalEnabled: Bool = false
    @Published private(set) var findChurch2ConciergeEnabled: Bool = false
    @Published private(set) var findChurch2MapHybridEnabled: Bool = false
    @Published private(set) var findChurch2AvailabilityEnabled: Bool = false
    @Published private(set) var findChurch2TrustSignalsEnabled: Bool = false
    @Published private(set) var findChurch2DesignRefreshEnabled: Bool = false

    // MARK: - Master-Run Phase Gates
    /// Phase 1: Find a Church surface (MapKit map, clustering, filter chips, bottom sheet).
    @Published private(set) var findAChurchEnabled: Bool = true
    /// Phase 2: Posts Liquid Glass migration — AmenGlassKit post card surfaces.
    @Published private(set) var postsLiquidGlassEnabled: Bool = true
    /// Phase 3: "Why this is in your feed" provenance disclosure sheet.
    @Published private(set) var whySeeingThisEnabled: Bool = true
    /// Phase 5: Selah Stories free composer (ephemeral formation stories).
    @Published private(set) var selahStoriesEnabled: Bool = false
    /// Phase 5: Selah Stories premium AI features (subscription-gated).
    @Published private(set) var selahStoriesPremiumAIEnabled: Bool = false

    // MARK: - Selah Enhancement
    /// Enables SelahNote → Pinecone corpus indexing (indexSelahNote CF).
    @Published private(set) var selahPersonalCorpusEnabled: Bool = false
    /// Enables Berean Check against Scripture (runDiscernmentCheck CF).
    @Published private(set) var selahDiscernmentEnabled: Bool = false
    /// Enables sharing discernment checks to thread participants.
    @Published private(set) var selahDiscernmentSharingEnabled: Bool = false

    private init() {
        applyUITestOverrides()
        Task { await fetchRemoteConfig() }
    }

    // MARK: - Remote Config

    private func fetchRemoteConfig() async {
        let config = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600
        config.configSettings = settings

        config.setDefaults(buildDefaults())

        do {
            let status = try await config.fetch()
            if status == .success {
                try await config.activate()
                applyRemoteConfig(config)
            }
        } catch {
            // Non-fatal — local defaults above remain in effect
            dlog("[AMENFeatureFlags] Remote config fetch failed, using defaults: \(error)")
        }
    }

    private func buildDefaults() -> [String: NSObject] {
        [
            // Moderation
            "moderation_v2_enabled": true as NSObject,
            "image_moderation_enabled": true as NSObject,
            "imageModerationEnabled": true as NSObject,
            "textModerationEnabled": true as NSObject,
            "dm_enhanced_scanning_enabled": true as NSObject,
            "moderation_appeals_enabled": true as NSObject,
            "trust_scoring_enabled": true as NSObject,

            // Berean
            "berean_rag_enabled": true as NSObject,
            "berean_conversation_memory_enabled": true as NSObject,
            "berean_source_attribution_enabled": true as NSObject,
            "berean_streaming_response_enabled": true as NSObject,
            "berean_voice_enabled": true as NSObject,
            "berean_adaptive_mode_enabled": true as NSObject,
            "berean_deep_enabled": true as NSObject,
            "berean_entitlement_enforcement_enabled": true as NSObject,

            // Check-in
            "spiritual_check_in_enabled": true as NSObject,
            "check_in_behavioral_signals_enabled": true as NSObject,
            "check_in_crisis_escalation_enabled": true as NSObject,

            // Feed
            "feed_ranking_v2_enabled": true as NSObject,
            "anti_doomscroll_enabled": true as NSObject,
            "feed_session_pacing_enabled": true as NSObject,
            "feed_reflection_prompts_enabled": true as NSObject,
            "feed_quality_metrics_enabled": true as NSObject,

            // Church
            "church_smart_ranking_enabled": true as NSObject,
            "church_first_visit_companion_enabled": true as NSObject,
            "church_service_reminders_enabled": true as NSObject,
            "church_reviews_enabled": true as NSObject,
            "church_interaction_tracking_enabled": true as NSObject,
            "church_journey_timeline_enabled": true as NSObject,
            "church_post_card_drafts_enabled": true as NSObject,
            "church_explainable_recommendations_enabled": true as NSObject,

            // Studio
            "studio_enabled": true as NSObject,
            "studio_monetization_enabled": true as NSObject,
            "studio_job_board_enabled": true as NSObject,
            "studio_ai_tagging_enabled": true as NSObject,

            // Knowledge Graph
            "knowledge_graph_enabled": true as NSObject,
            "knowledge_graph_related_content_enabled": true as NSObject,
            "knowledge_graph_semantic_search_enabled": true as NSObject,
            "ragSearchEnabled": true as NSObject,

            // Action Threads
            "action_threads_enabled": true as NSObject,
            "action_suggestions_enabled": true as NSObject,
            "care_followups_enabled": true as NSObject,
            "smartMessageContextEnabled": true as NSObject,
            "conversationMemoryEnabled": true as NSObject,
            "privateContactNotesEnabled": true as NSObject,
            "smartReminderDetectionEnabled": true as NSObject,
            "smartMusicDetectionEnabled": true as NSObject,
            "smartLinkDetectionEnabled": true as NSObject,
            "smartAttachmentMenuEnabled": true as NSObject,
            "liquidGlassMessagingEnabled": true as NSObject,
            "smartPostContextEnabled": true as NSObject,

            // Compound Identity Graph
            "compound_identity_graph_enabled": true as NSObject,
            "agent_recommendations_enabled": true as NSObject,

            // Proof of Human + Proof of Care
            "proof_of_human_enabled": true as NSObject,
            "proof_of_care_enabled": true as NSObject,
            "trust_signals_enabled": true as NSObject,

            // Topic Drill-Down
            "topic_drill_down_enabled": true as NSObject,
            "topic_enrichment_enabled": true as NSObject,

            // Smart Media Continuity
            "media_resume_enabled": true as NSObject,

            // Suggested Follows
            "suggested_follows_enabled": true as NSObject,
            "suggested_rail_prayer_enabled": true as NSObject,
            "suggested_rail_testimonies_enabled": true as NSObject,
            "suggested_rail_peek_sheet_enabled": true as NSObject,
            "suggested_rail_server_ranking_enabled": true as NSObject,
            // GAP A5-P1 suggested-rail integer defaults
            "suggested_rail_insertion_index": 2 as NSObject,
            "suggested_rail_card_limit": 12 as NSObject,
            "suggested_rail_cooldown_hours": 24 as NSObject,
            "suggested_rail_dismiss_cooldown_days": 7 as NSObject,

            // Social Context & UX Enhancements
            "mutual_context_row_enabled": true as NSObject,
            "presence_intelligence_enabled": false as NSObject,
            "message_request_intelligence_enabled": true as NSObject,
            "trust_explainer_enabled": true as NSObject,
            "post_divider_enabled": true as NSObject,
            "feed_view_mode_switcher_enabled": true as NSObject,
            "media_filter_pills_enabled": true as NSObject,
            "media_detail_view_enabled": true as NSObject,
            "enhanced_notifications_enabled": true as NSObject,
            "server_notifications_v2_enabled": true as NSObject,
            "berean_chat_redesign_enabled": true as NSObject,
            "in_app_browser_enabled": true as NSObject,
            "composer_approved_audio_enabled": true as NSObject,
            "smart_attachments_enabled": true as NSObject,
            "smart_attachment_composer_paste_enabled": true as NSObject,
            "smart_attachment_music_picker_enabled": true as NSObject,
            "smart_attachment_expanded_sheet_enabled": true as NSObject,
            "smart_attachment_media_graph_enabled": true as NSObject,
            "smart_attachment_smart_actions_enabled": true as NSObject,

            // Accessibility Intelligence Layer
            "accessibility_intelligence_enabled": false as NSObject,
            "meaning_aware_translation_enabled": false as NSObject,
            "natural_mode_enabled": false as NSObject,
            "contextual_mode_enabled": false as NSObject,
            "readability_layer_enabled": false as NSObject,
            "content_difficulty_scoring": false as NSObject,
            "audio_narration_enabled": false as NSObject,
            "context_bridge_enabled": false as NSObject,
            "adaptive_accessibility_enabled": false as NSObject,
            "conversation_bridge_enabled": false as NSObject,
            "smart_translation_visibility_enabled": false as NSObject,
            "side_by_side_translation_enabled": false as NSObject,
            "per_language_auto_translate_enabled": false as NSObject,
            "creation_language_enabled": false as NSObject,
            "adaptive_translation_enabled": false as NSObject,

            // Berean Spiritual Intelligence Layers
            "berean_spiritual_layers_enabled": true as NSObject,
            "living_scripture_graph_enabled": true as NSObject,
            "spiritual_state_layer_enabled": true as NSObject,
            "guided_discipleship_enabled": true as NSObject,
            "scripture_immersion_enabled": true as NSObject,
            "authority_alignment_enabled": true as NSObject,

            // Resources Intelligence
            "resources_intelligence_enabled": true as NSObject,
            "support_draft_detection_enabled": true as NSObject,
            "church_note_care_summary_enabled": true as NSObject,
            "church_notes_server_summary_enabled": true as NSObject,
            "church_notes_audio_capture_enabled": false as NSObject,
            "church_notes_photo_ocr_enabled": false as NSObject,
            "church_notes_video_capture_enabled": false as NSObject,
            "church_notes_ai_draft_review_enabled": true as NSObject,
            "church_notes_study_guide_enabled": true as NSObject,
            "church_notes_prayer_prompts_enabled": true as NSObject,
            "church_notes_intelligence_enabled": true as NSObject,
            "sermon_audio_capture_enabled": false as NSObject,
            "sermon_video_capture_enabled": false as NSObject,
            "church_photo_ocr_capture_enabled": false as NSObject,
            "church_notes_translation_enabled": true as NSObject,
            "church_notes_collaboration_enabled": true as NSObject,
            "sermon_summary_generation_enabled": true as NSObject,
            "scripture_detection_enabled": true as NSObject,
            "api_bible_scripture_provider_enabled": false as NSObject,
            "api_bible_licensed_display_translations_enabled": false as NSObject,
            "api_bible_core_offline_cache_enabled": false as NSObject,
            "sermon_action_extraction_enabled": true as NSObject,
            "sermon_clip_suggestion_enabled": true as NSObject,
            "church_notes_study_guide_generation_enabled": true as NSObject,
            "feature_note_share_viewer": false as NSObject,
            "church_notes_smart_objects_enabled": false as NSObject,
            "church_notes_processing_kill_switch": false as NSObject,
            "church_notes_audio_processing_kill_switch": false as NSObject,
            "church_notes_image_moderation_kill_switch": false as NSObject,
            "church_notes_video_processing_kill_switch": false as NSObject,
            "trusted_contacts_enabled": true as NSObject,
            "helping_someone_else_enabled": true as NSObject,
            "support_followups_enabled": true as NSObject,
            "nonprofit_recommendation_enabled": true as NSObject,
            "berean_resource_routing_enabled": true as NSObject,

            // Amen Daily Digest
            "amen_daily_digest_enabled": true as NSObject,
            "amen_daily_digest_weather_enabled": true as NSObject,
            "amen_daily_digest_holiday_enabled": true as NSObject,
            "amen_daily_digest_christian_calendar_enabled": true as NSObject,
            "amen_daily_digest_expanded_sheet_enabled": true as NSObject,
            "amen_daily_digest_berean_ai_action_enabled": true as NSObject,
            "amen_daily_digest_church_notes_action_enabled": true as NSObject,
            "amen_daily_digest_find_church_action_enabled": true as NSObject,
            "amen_daily_digest_selah_action_enabled": true as NSObject,
            "amen_daily_digest_ai_reflection_enabled": true as NSObject,

            // Onboarding & Auth Remediation — default OFF
            "ff_onboarding_v2": false as NSObject,

            // Berean Pulse
            "berean_pulse_enabled": true as NSObject,

            // Amen Pulse (daily surface) — default OFF
            "amen_pulse_enabled": false as NSObject,

            // Spiritual OS — all default OFF until human flag flip
            "spiritualOS_enabled": false as NSObject,
            "spiritualOS_daily_enabled": false as NSObject,
            "spiritualOS_hub_enabled": false as NSObject,
            "spiritualOS_planner_enabled": false as NSObject,
            "spiritualOS_spaces_dashboard_enabled": false as NSObject,
            "spiritualOS_create_space_enhanced_enabled": false as NSObject,
            "spiritualOS_command_center_enabled": false as NSObject,
            "spiritualOS_assistant_bar_enabled": false as NSObject,
            "spiritualOS_context_engine_enabled": false as NSObject,
            "spiritualOS_community_os_enabled": false as NSObject,

            // Universal Migration & Context System — all default OFF
            "context_system_enabled": false as NSObject,
            "context_manual_entry_enabled": false as NSObject,
            "context_berean_interview_enabled": false as NSObject,
            "context_universal_import_enabled": false as NSObject,
            "context_matching_enabled": false as NSObject,
            "context_export_enabled": false as NSObject,
            "context_qr_enabled": false as NSObject,
            "context_commitment_bridge_enabled": false as NSObject,

            // Community Hubs & Object Intelligence
            "community_hubs_enabled": false as NSObject,
            "community_object_matching_enabled": false as NSObject,
            "lyric_detection_enabled": false as NSObject,
            "object_hub_view_enabled": false as NSObject,
            "object_hub_inline_pill_enabled": false as NSObject,
            "object_hub_inline_cluster_enabled": false as NSObject,

            // Communities / Threads-Style Feeds
            "ark_communities_enabled": false as NSObject,
            "covenant_communities_enabled": false as NSObject,
            "unified_feeds_switcher_enabled": false as NSObject,
            "saved_communities_enabled": false as NSObject,
            "view_in_feed_enabled": false as NSObject,

            // Smart Share Sheet
            "smart_share_sheet_enabled": true as NSObject,
            "smart_share_smart_suggestions_enabled": true as NSObject,
            "smart_share_recipient_rail_enabled": true as NSObject,
            "smart_share_context_enabled": true as NSObject,
            "smart_share_preview_mode_enabled": true as NSObject,

            // Translation Intelligence
            "translation_smart_pill_enabled": true as NSObject,
            "translation_remember_language_preference_enabled": true as NSObject,

            // Universal Content + Create
            "universal_content_model_enabled": true as NSObject,
            "universal_create_enabled": true as NSObject,

            // Media Creation System
            "media_creation_enabled": true as NSObject,
            "video_upload_enabled": true as NSObject,
            "voiceover_enabled": true as NSObject,
            "auto_captions_enabled": true as NSObject,
            "immersive_media_chrome_enabled": true as NSObject,
            "immersive_feed_enabled": true as NSObject,
            "continuation_feed_enabled": true as NSObject,
            "explain_video_enabled": true as NSObject,
            "explain_video_rollout_percent": 100 as NSObject,
            "explain_video_min_app_version": "1.0.0" as NSObject,
            "explain_video_kill_reason": "" as NSObject,

            // Per-Media Captions
            "per_media_captions_enabled": true as NSObject,
            "per_media_caption_education_enabled": true as NSObject,
            "per_media_caption_moderation_enabled": true as NSObject,
            "per_media_caption_alt_text_enabled": true as NSObject,
            "per_media_caption_scripture_refs_enabled": true as NSObject,

            // Selah Scripture Actions
            "selah_scripture_actions_enabled": true as NSObject,
            "church_study_companion_enabled": true as NSObject,
            "church_notes_scripture_bridge_enabled": true as NSObject,
            "selah_add_to_church_notes_enabled": true as NSObject,
            "find_church_study_actions_enabled": true as NSObject,
            "after_service_reflection_enabled": true as NSObject,
            "church_study_group_bridge_enabled": true as NSObject,

            // Selah Media OS
            "selah_media_os_enabled": true as NSObject,
            "selah_media_os_min_app_version": "1.0.0" as NSObject,
            "selah_media_os_rollout_percent": 100 as NSObject,
            "selah_media_os_kill_reason": "" as NSObject,

            // Messaging Micro Animations
            "messaging_liquid_glass_animations_enabled": true as NSObject,
            "messaging_typing_indicator_enabled": true as NSObject,
            "messaging_floating_header_prototype_enabled": false as NSObject,
            "messaging_liquid_glass_context_menu_enabled": false as NSObject,
            "messaging_liquid_glass_attachment_menu_enabled": false as NSObject,
            "messaging_smart_composer_enabled": false as NSObject,
            "messaging_attachment_menu_smart_actions_enabled": false as NSObject,
            "messaging_smart_pills_enabled": false as NSObject,
            "messaging_translation_enabled": false as NSObject,
            "messaging_cross_surface_actions_enabled": false as NSObject,
            "messaging_safety_nudges_enabled": true as NSObject,
            "messaging_approval_cards_enabled": false as NSObject,
            "messaging_catch_up_enabled": false as NSObject,
            "messaging_voice_intelligence_enabled": false as NSObject,
            "messaging_media_intelligence_enabled": false as NSObject,
            "messaging_presence_polish_enabled": false as NSObject,
            "camera_os_enabled": false as NSObject,

            // Smart Account Resume
            "smart_account_resume_enabled": true as NSObject,
            "smart_account_resume_auto_continue_enabled": true as NSObject,
            "smart_account_resume_offline_retry_enabled": true as NSObject,

            // AI Usage Labels
            "ai_usage_label_pill_enabled": true as NSObject,

            // System 27: Berean Grok Helper Pipeline
            "berean_helper_model_enabled": false as NSObject,
            "berean_helper_prompt_simplify_enabled": false as NSObject,
            "berean_helper_link_summary_enabled": false as NSObject,
            "berean_helper_external_context_enabled": false as NSObject,
            "berean_helper_study_outline_enabled": false as NSObject,
            "berean_helper_extract_themes_enabled": false as NSObject,
            "berean_helper_provenance_chips_enabled": false as NSObject,

            // System 28: Feed Intelligence OS
            "feed_intelligence_enabled": false as NSObject,
            "guide_my_feed_enabled": false as NSObject,
            "why_this_post_backend_enabled": false as NSObject,
            "feed_modes_enabled": false as NSObject,

            // System 29: Liquid Glass Intelligence Layer
            "liquid_glass_system_enabled": false as NSObject,
            "liquid_glass_presence_pills_enabled": false as NSObject,
            "semantic_underline_enabled": false as NSObject,
            "inline_definition_popover_enabled": false as NSObject,
            "smart_action_detection_enabled": false as NSObject,
            "pulse_awareness_enabled": false as NSObject,
            "knowledge_threads_enabled": false as NSObject,
            "selah_semantic_save_enabled": false as NSObject,
            "church_notes_semantic_actions_enabled": false as NSObject,
            "media_chrome_liquid_glass_enabled": false as NSObject,
            "composer_presence_actions_enabled": false as NSObject,
            "bottom_bar_liquid_glass_enabled": false as NSObject,
            "amen_discover_enabled": true as NSObject,
            "amen_discover_liquid_glass_enabled": true as NSObject,
            "amen_discover_ranking_enabled": true as NSObject,
            "amen_discover_why_this_enabled": true as NSObject,
            "amen_discover_local_churches_enabled": true as NSObject,
            "amen_discover_selah_enabled": true as NSObject,
            "amen_discover_safety_feedback_enabled": true as NSObject,

            // Analytics
            "analytics_enabled": true as NSObject,
            "performance_telemetry_enabled": true as NSObject,

            // Berean Intelligence Layer v2
            "berean_theo_lens_enabled": true as NSObject,
            "berean_selah_bridge_enabled": true as NSObject,
            "berean_church_notes_bridge_enabled": true as NSObject,
            "berean_smart_pills_enabled": true as NSObject,
            "berean_theology_boundary_enabled": true as NSObject,
            "berean_persistent_memory_enabled": true as NSObject,
            "berean_study_threads_enabled": true as NSObject,
            "berean_translation_compare_enabled": true as NSObject,
            "berean_research_view_enabled": true as NSObject,

            // System 31: Voice Prayer & Testimony Comments — default OFF until enforcement tests pass
            "voice_prayer_comments_enabled": false as NSObject,
            "voice_testimony_comments_enabled": false as NSObject,
            "voice_comment_transcript_required": true as NSObject,
            "voice_comment_summary_enabled": false as NSObject,
            "voice_comment_review_queue_enabled": false as NSObject,
            "voice_comment_prayer_circle_visibility_enabled": false as NSObject,

            // Amen AI Creative Intelligence Layer — default OFF until verified
            "amen_realtime_voice_enabled": false as NSObject,
            "amen_live_captions_enabled": false as NSObject,
            "amen_translation_enabled": false as NSObject,
            "amen_graphic_studio_enabled": false as NSObject,
            "amen_creator_kit_enabled": false as NSObject,
            "amen_agent_workflows_enabled": false as NSObject,
            "amen_explain_enabled": false as NSObject,
            "amen_improve_enabled": false as NSObject,
            "amen_summarize_enabled": false as NSObject,
            "amen_ai_usage_labels_required": true as NSObject,
            "berean_realtime_enabled": false as NSObject,
            "berean_translation_enabled": false as NSObject,
            "berean_prayer_rooms_enabled": false as NSObject,
            "berean_voice_assistant_enabled": false as NSObject,
            "berean_smart_notes_enabled": false as NSObject,
            "berean_live_captions_enabled": false as NSObject,
            "berean_realtime_kill_switch": false as NSObject,
            "amen_realtime_voice_kill_switch": false as NSObject,
            "amen_live_captions_kill_switch": false as NSObject,
            "amen_translation_kill_switch": false as NSObject,
            "amen_graphic_generation_kill_switch": false as NSObject,
            "amen_agent_workflow_kill_switch": false as NSObject,
            "amen_explain_kill_switch": false as NSObject,
            "amen_improve_kill_switch": false as NSObject,
            "amen_summarize_kill_switch": false as NSObject,

            // System 33: Spatial Social OS
            "spatial_home_enabled": false as NSObject,
            "spatial_context_rail_enabled": false as NSObject,
            "provenance_trust_panel_enabled": false as NSObject,
            "creator_os_composer_enabled": false as NSObject,
            "truthful_ai_labels_enabled": false as NSObject,
            "smart_discovery_transparency_enabled": false as NSObject,
            "discovery_why_shown_enabled": false as NSObject,
            "safety_os_enabled": true as NSObject,

            // System 34: Healthy Immersive Media Sessions
            "healthy_immersive_media_enabled": false as NSObject,
            "media_finite_sessions_enabled": true as NSObject,
            "media_completion_reflection_enabled": false as NSObject,
            "media_doom_scroll_guard_enabled": true as NSObject,
            "media_session_checkpoints_enabled": true as NSObject,
            "media_key_moments_enabled": false as NSObject,
            "media_transcript_enabled": true as NSObject,
            "media_ai_draft_metadata_enabled": false as NSObject,
            "media_approval_flow_enabled": false as NSObject,
            "media_selah_audio_mode_enabled": true as NSObject,
            "media_timestamped_comments_enabled": false as NSObject,
            "media_search_enabled": false as NSObject,
            "media_church_notes_integration_enabled": false as NSObject,
            "media_prayer_queue_enabled": false as NSObject,
            "media_reflection_queue_enabled": false as NSObject,
            "media_low_bandwidth_mode_enabled": true as NSObject,
            "media_reporting_enabled": true as NSObject,
            "media_accessibility_controls_enabled": true as NSObject,
            "media_ranking_v2_enabled": true as NSObject,
            "media_hide_vanity_metrics_enabled": true as NSObject,

            // System 35: Provenance & Authenticity OS
            "media_authenticity_badges_enabled": false as NSObject,
            "synthetic_media_detection_enabled": false as NSObject,
            "content_credentials_enabled": false as NSObject,
            "provenance_audit_chain_enabled": false as NSObject,

            // Aegis OS — Pre-Post Content Safety Gate
            "aegis_pre_post_review_enabled": true as NSObject,

            // Music Attachment
            "music_attachment_enabled": true as NSObject,

            // Berean OS — default matches Remote Config template (all true)
            "berean_os_projects_enabled": false as NSObject,
            "berean_os_research_engine_enabled": false as NSObject,
            "berean_os_wisdom_engine_enabled": false as NSObject,
            "berean_os_multi_perspective_enabled": false as NSObject,
            "berean_os_debate_engine_enabled": false as NSObject,
            "berean_os_social_knowledge_feed_enabled": false as NSObject,
            "berean_os_advisory_boards_enabled": false as NSObject,
            "berean_os_mentor_os_enabled": false as NSObject,
            "berean_os_knowledge_graph_enabled": false as NSObject,
            "berean_os_onboarding_enabled": false as NSObject,
            "berean_os_memory_brain_enabled": false as NSObject,
            "berean_os_action_planner_enabled": false as NSObject,
            "berean_os_truth_labels_enabled": false as NSObject,
            "berean_os_source_explorer_enabled": false as NSObject,
            "berean_os_social_projects_enabled": false as NSObject,
            "berean_os_community_intelligence_enabled": false as NSObject,
            "berean_os_living_documents_enabled": false as NSObject,

            // Profile V2
            "profile_v2_enabled": true as NSObject,
            "profile_media_grid_enabled": true as NSObject,
            "pinned_content_enabled": true as NSObject,
            "creator_highlights_enabled": true as NSObject,

            // Social Safety OS
            "social_safety_os_enabled": true as NSObject,
            "wellbeing_feed_ranking_enabled": true as NSObject,
            "selah_pause_enabled": true as NSObject,
            "emotional_check_in_enabled": true as NSObject,
            "private_reflection_enabled": true as NSObject,
            "healthy_use_dashboard_enabled": true as NSObject,
            "dm_risk_firewall_enabled": true as NSObject,
            "minor_safety_mode_enabled": true as NSObject,
            "sextortion_panic_flow_enabled": true as NSObject,
            "suspicious_relationship_detector_enabled": true as NSObject,
            "trusted_contact_escalation_enabled": true as NSObject,
            "think_first_guard_enabled": true as NSObject,
            "dogpile_detection_enabled": true as NSObject,
            "mercy_mode_replies_enabled": true as NSObject,
            "reputation_moderation_enabled": true as NSObject,
            "victim_shield_enabled": true as NSObject,
            "truth_context_layer_enabled": true as NSObject,
            "ai_media_disclosure_enabled": true as NSObject,
            "claim_source_requirement_enabled": true as NSObject,
            "community_correction_enabled": true as NSObject,
            "theological_guardrails_enabled": true as NSObject,
            "feed_mode_controls_enabled": true as NSObject,
            "feed_boundary_enabled": true as NSObject,
            "purpose_open_screen_enabled": true as NSObject,
            "engagement_quality_ranking_enabled": true as NSObject,
            "algorithm_transparency_enabled": true as NSObject,

            // Berean Extended Intelligence
            "berean_context_bridge_enabled": false as NSObject,
            "berean_safety_classifier_enabled": false as NSObject,
            "berean_liquid_glass_context_actions_enabled": false as NSObject,
            "berean_source_grounding_enabled": false as NSObject,
            "berean_follow_ups_enabled": false as NSObject,
            "berean_commentary_compare_enabled": false as NSObject,
            "berean_theological_lens_enabled": false as NSObject,

            // System 32: Communication OS
            "messages_smart_context_enabled": false as NSObject,
            "group_discussion_pulse_enabled": false as NSObject,
            "thread_summary_enabled": false as NSObject,
            "catch_up_digest_enabled": false as NSObject,
            "thread_decision_extraction_enabled": false as NSObject,
            "thread_action_extraction_enabled": false as NSObject,
            "thread_question_detection_enabled": false as NSObject,
            "smart_presence_enabled": false as NSObject,
            "smart_reactions_enabled": false as NSObject,
            "media_intelligence_enabled": false as NSObject,
            "conversation_memory_search_enabled": false as NSObject,
            "command_palette_enabled": false as NSObject,
            "smart_replies_enabled": false as NSObject,
            "multi_pane_communication_enabled": false as NSObject,
            "liquid_glass_communication_ui_enabled": false as NSObject,

            // System 33: ContentOS
            "content_os_enabled": false as NSObject,
            "content_approval_workflow_enabled": false as NSObject,
            "content_forwarding_enabled": false as NSObject,
            "content_ai_router_enabled": false as NSObject,
            "content_audit_log_enabled": false as NSObject,

            // System 36: Context-First Discussion OS
            "discussion_modes_enabled": true as NSObject,
            "context_participation_enabled": true as NSObject,
            "discussion_health_enabled": true as NSObject,
            "draft_intelligence_enabled": true as NSObject,
            "discussion_summary_enabled": true as NSObject,
            "discussion_mediator_enabled": true as NSObject,
            "community_memory_enabled": true as NSObject,
            "discussion_actions_enabled": true as NSObject,
            "participation_tiers_enabled": true as NSObject,
            "discussion_command_center_enabled": true as NSObject,

            // System 37: Community OS
            "community_os_enabled": false as NSObject,
            "community_os_discussion_enabled": false as NSObject,
            "community_os_prayer_os_enabled": false as NSObject,
            "community_os_action_pill_enabled": false as NSObject,
            "community_os_universal_composer_enabled": false as NSObject,
            "community_os_church_os_enabled": false as NSObject,
            "community_os_org_os_enabled": false as NSObject,
            "community_os_opportunity_enabled": false as NSObject,

            // System 38: Connect Hub
            "connect_hub_enabled": true as NSObject,
            "connect_you_menu_enabled": true as NSObject,

            // System 39: Connect UI Polish Waves (default OFF)
            "connect_layout_v2_enabled": false as NSObject,
            "connect_polish_v2_enabled": false as NSObject,
            "connect_empty_states_enabled": false as NSObject,
            "connect_smart_berean_enabled": false as NSObject,
            "connect_offline_queue_enabled": false as NSObject,

            // System 34: Healthy Media — extended flags
            "immersive_media_sessions_enabled": false as NSObject,
            "finite_media_queues_enabled": true as NSObject,
            "media_completion_overlay_enabled": false as NSObject,
            "media_no_doom_scroll_guardrails_enabled": true as NSObject,
            "healthy_media_checkpoints_enabled": true as NSObject,
            "media_ai_metadata_drafts_enabled": false as NSObject,
            "media_generated_metadata_approval_required": true as NSObject,
            "media_selah_overlay_enabled": true as NSObject,
            "community_media_layers_enabled": false as NSObject,
            "media_community_layer_enabled": false as NSObject,
            "media_reflection_sheet_enabled": false as NSObject,
            "hide_vanity_metrics_default": true as NSObject,
            "autoplay_within_sessions_enabled": false as NSObject,
            "late_night_pause_enabled": true as NSObject,
            "media_wellbeing_controls_enabled": true as NSObject,
            "media_liquid_glass_chrome_enabled": false as NSObject,
            "media_profile_liquid_white_flow_enabled": false as NSObject,
            "media_synthetic_detection_enabled": false as NSObject,
            "immersive_photo_sessions_enabled": false as NSObject,
            "immersive_video_sessions_enabled": false as NSObject,
            "live_activity_prayer_request_enabled": false as NSObject,
            "live_activity_push_to_start_enabled": false as NSObject,

            // Ambient OS
            "ambient_os_enabled": false as NSObject,

            // Accessibility + Simple Mode
            "simple_mode_feature_enabled": true as NSObject,
            "replay_enabled": true as NSObject,

            // Mentorship
            "mentorship_enabled": true as NSObject,

            // Conversation OS (Spaces Intelligence)
            "conversation_os_enabled": false as NSObject,
            "conversation_summaries_enabled": false as NSObject,
            "catch_up_recaps_enabled": false as NSObject,
            "topic_clustering_enabled": false as NSObject,
            "action_extraction_enabled": false as NSObject,
            "organizational_memory_enabled": false as NSObject,
            "personalized_insights_enabled": false as NSObject,
            "ambient_conversation_intelligence_enabled": false as NSObject,
            "conversation_os_liquid_glass_enabled": false as NSObject,
            "conversation_os_debug_telemetry_enabled": false as NSObject,
            "conversation_os_sensitive_space_restrictions_enabled": false as NSObject,

            // Master-Run Phase Gates
            "find_a_church_enabled": true as NSObject,
            "posts_liquid_glass_enabled": true as NSObject,
            "why_seeing_this_enabled": true as NSObject,
            "selah_stories_enabled": false as NSObject,
            "selah_stories_premium_ai_enabled": false as NSObject,

            // Selah Enhancement
            "selah_personal_corpus_enabled": false as NSObject,
            "selah_discernment_enabled": false as NSObject,
            "selah_discernment_sharing_enabled": false as NSObject,

            // Find Church 2.0 — all default OFF until RC flip after verification
            "findChurch2_onboarding": false as NSObject,
            "findChurch2_matchExplain": false as NSObject,
            "findChurch2_gatherings": false as NSObject,
            "findChurch2_visitPlanner": false as NSObject,
            "findChurch2_claimPortal": false as NSObject,
            "findChurch2_concierge": false as NSObject,
            "findChurch2_mapHybrid": false as NSObject,
            "findChurch2_availability": false as NSObject,
            "findChurch2_trustSignals": false as NSObject,
            "findChurch2_designRefresh": false as NSObject,
        ]
    }

    private func applyRemoteConfig(_ config: RemoteConfig) {
        moderationV2Enabled = config["moderation_v2_enabled"].boolValue
        imageModerationEnabled = config["image_moderation_enabled"].boolValue
        dmEnhancedScanningEnabled = config["dm_enhanced_scanning_enabled"].boolValue
        moderationAppealsEnabled = config["moderation_appeals_enabled"].boolValue
        trustScoringEnabled = config["trust_scoring_enabled"].boolValue

        bereanRAGEnabled = config["berean_rag_enabled"].boolValue
        bereanConversationMemoryEnabled = config["berean_conversation_memory_enabled"].boolValue
        bereanSourceAttributionEnabled = config["berean_source_attribution_enabled"].boolValue
        bereanStreamingResponseEnabled = config["berean_streaming_response_enabled"].boolValue
        bereanVoiceEnabled = config["berean_voice_enabled"].boolValue
        bereanAdaptiveModeEnabled = config["berean_adaptive_mode_enabled"].boolValue
        bereanDeepEnabled = config["berean_deep_enabled"].boolValue
        bereanEntitlementEnforcementEnabled = config["berean_entitlement_enforcement_enabled"].boolValue

        spiritualCheckInEnabled = config["spiritual_check_in_enabled"].boolValue
        checkInBehavioralSignalsEnabled = config["check_in_behavioral_signals_enabled"].boolValue
        checkInCrisisEscalationEnabled = config["check_in_crisis_escalation_enabled"].boolValue

        feedRankingV2Enabled = config["feed_ranking_v2_enabled"].boolValue
        antiDoomscrollEnabled = config["anti_doomscroll_enabled"].boolValue
        feedSessionPacingEnabled = config["feed_session_pacing_enabled"].boolValue
        feedReflectionPromptsEnabled = config["feed_reflection_prompts_enabled"].boolValue
        feedQualityMetricsEnabled = config["feed_quality_metrics_enabled"].boolValue

        churchDiscoverySmartRankingEnabled = config["church_smart_ranking_enabled"].boolValue
        churchFirstVisitCompanionEnabled = config["church_first_visit_companion_enabled"].boolValue
        churchServiceRemindersEnabled = config["church_service_reminders_enabled"].boolValue
        churchReviewsEnabled = config["church_reviews_enabled"].boolValue
        churchInteractionTrackingEnabled = config["church_interaction_tracking_enabled"].boolValue
        churchJourneyTimelineEnabled = config["church_journey_timeline_enabled"].boolValue
        churchPostCardDraftsEnabled = config["church_post_card_drafts_enabled"].boolValue
        churchExplainableRecommendationsEnabled = config["church_explainable_recommendations_enabled"].boolValue

        studioEnabled = config["studio_enabled"].boolValue
        studioMonetizationEnabled = config["studio_monetization_enabled"].boolValue
        studioJobBoardEnabled = config["studio_job_board_enabled"].boolValue
        studioAITaggingEnabled = config["studio_ai_tagging_enabled"].boolValue

        knowledgeGraphEnabled = config["knowledge_graph_enabled"].boolValue
        knowledgeGraphRelatedContentEnabled = config["knowledge_graph_related_content_enabled"].boolValue
        knowledgeGraphSemanticSearchEnabled = config["knowledge_graph_semantic_search_enabled"].boolValue

        actionThreadsEnabled = config["action_threads_enabled"].boolValue
        actionSuggestionsEnabled = config["action_suggestions_enabled"].boolValue
        careFollowupsEnabled = config["care_followups_enabled"].boolValue
        mentorshipEnabled = config["mentorship_enabled"].source == .static ? true : config["mentorship_enabled"].boolValue

        compoundIdentityGraphEnabled = config["compound_identity_graph_enabled"].boolValue
        agentRecommendationsEnabled = config["agent_recommendations_enabled"].boolValue

        proofOfHumanEnabled = config["proof_of_human_enabled"].boolValue
        proofOfCareEnabled = config["proof_of_care_enabled"].boolValue
        trustSignalsEnabled = config["trust_signals_enabled"].boolValue

        topicDrillDownEnabled = config["topic_drill_down_enabled"].boolValue
        topicEnrichmentEnabled = config["topic_enrichment_enabled"].boolValue

        mediaResumeEnabled = config["media_resume_enabled"].boolValue

        suggestedFollowsEnabled = config["suggested_follows_enabled"].boolValue
        suggestedRailPrayerEnabled = config["suggested_rail_prayer_enabled"].boolValue
        suggestedRailTestimoniesEnabled = config["suggested_rail_testimonies_enabled"].boolValue
        suggestedRailPeekSheetEnabled = config["suggested_rail_peek_sheet_enabled"].boolValue
        suggestedRailServerRankingEnabled = config["suggested_rail_server_ranking_enabled"].boolValue
        suggestedRailInsertionIndex = config["suggested_rail_insertion_index"].numberValue.intValue
        suggestedRailCardLimit = config["suggested_rail_card_limit"].numberValue.intValue
        suggestedRailCooldownHours = config["suggested_rail_cooldown_hours"].numberValue.intValue
        suggestedRailDismissCooldownDays = config["suggested_rail_dismiss_cooldown_days"].numberValue.intValue

        mutualContextRowEnabled = config["mutual_context_row_enabled"].boolValue
        presenceIntelligenceEnabled = config["presence_intelligence_enabled"].boolValue
        messageRequestIntelligenceEnabled = config["message_request_intelligence_enabled"].boolValue
        trustExplainerEnabled = config["trust_explainer_enabled"].boolValue
        postDividerEnabled = config["post_divider_enabled"].boolValue
        feedViewModeSwitcherEnabled = config["feed_view_mode_switcher_enabled"].boolValue
        mediaFilterPillsEnabled = config["media_filter_pills_enabled"].boolValue
        mediaDetailViewEnabled = config["media_detail_view_enabled"].boolValue
        enhancedNotificationsEnabled = config["enhanced_notifications_enabled"].boolValue
        serverNotificationsV2Enabled = config["server_notifications_v2_enabled"].boolValue
        bereanChatRedesignEnabled = config["berean_chat_redesign_enabled"].boolValue
        inAppBrowserEnabled = config["in_app_browser_enabled"].boolValue
        composerApprovedAudioEnabled = config["composer_approved_audio_enabled"].boolValue
        smartAttachmentsEnabled = config["smart_attachments_enabled"].boolValue
        smartAttachmentComposerPasteEnabled = config["smart_attachment_composer_paste_enabled"].boolValue
        smartAttachmentMusicPickerEnabled = config["smart_attachment_music_picker_enabled"].boolValue
        smartAttachmentExpandedSheetEnabled = config["smart_attachment_expanded_sheet_enabled"].boolValue
        smartAttachmentMediaGraphEnabled = config["smart_attachment_media_graph_enabled"].boolValue
        smartAttachmentSmartActionsEnabled = config["smart_attachment_smart_actions_enabled"].boolValue

        accessibilityIntelligenceEnabled = config["accessibility_intelligence_enabled"].boolValue
        meaningAwareTranslationEnabled = config["meaning_aware_translation_enabled"].boolValue
        naturalModeEnabled = config["natural_mode_enabled"].boolValue
        contextualModeEnabled = config["contextual_mode_enabled"].boolValue
        readabilityLayerEnabled = config["readability_layer_enabled"].boolValue
        contentDifficultyScoring = config["content_difficulty_scoring"].boolValue
        audioNarrationEnabled = config["audio_narration_enabled"].boolValue
        contextBridgeEnabled = config["context_bridge_enabled"].boolValue
        adaptiveAccessibilityEnabled = config["adaptive_accessibility_enabled"].boolValue
        conversationBridgeEnabled = config["conversation_bridge_enabled"].boolValue
        smartTranslationVisibilityEnabled = config["smart_translation_visibility_enabled"].boolValue
        sideBySideTranslationEnabled = config["side_by_side_translation_enabled"].boolValue
        perLanguageAutoTranslateEnabled = config["per_language_auto_translate_enabled"].boolValue
        creationLanguageEnabled = config["creation_language_enabled"].boolValue
        adaptiveTranslationEnabled = config["adaptive_translation_enabled"].boolValue

        bereanSpiritualLayersEnabled = config["berean_spiritual_layers_enabled"].boolValue
        livingScriptureGraphEnabled = config["living_scripture_graph_enabled"].boolValue
        spiritualStateLayerEnabled = config["spiritual_state_layer_enabled"].boolValue
        guidedDiscipleshipEnabled = config["guided_discipleship_enabled"].source == .static ? true : config["guided_discipleship_enabled"].boolValue
        scriptureImmersionEnabled = config["scripture_immersion_enabled"].boolValue
        authorityAlignmentEnabled = config["authority_alignment_enabled"].boolValue

        resourcesIntelligenceEnabled = config["resources_intelligence_enabled"].boolValue
        supportDraftDetectionEnabled = config["support_draft_detection_enabled"].boolValue
        churchNoteCareSummaryEnabled = config["church_note_care_summary_enabled"].boolValue
        churchNotesServerSummaryEnabled = config["church_notes_server_summary_enabled"].boolValue
        let churchNotesAudioCaptureRemote = config["church_notes_audio_capture_enabled"].boolValue
        let churchNotesPhotoOCRRemote = config["church_notes_photo_ocr_enabled"].boolValue
        let churchNotesVideoCaptureRemote = config["church_notes_video_capture_enabled"].boolValue
        churchNotesAudioCaptureEnabled = churchNotesAudioCaptureRemote
        churchNotesPhotoOCREnabled = churchNotesPhotoOCRRemote
        churchNotesVideoCaptureEnabled = churchNotesVideoCaptureRemote
        churchNotesAIDraftReviewEnabled = config["church_notes_ai_draft_review_enabled"].boolValue
        churchNotesStudyGuideEnabled = config["church_notes_study_guide_enabled"].boolValue
        churchNotesPrayerPromptsEnabled = config["church_notes_prayer_prompts_enabled"].boolValue
        churchNotesIntelligenceEnabled = config["church_notes_intelligence_enabled"].boolValue
        sermonAudioCaptureEnabled = churchNotesAudioCaptureRemote && config["sermon_audio_capture_enabled"].boolValue
        sermonVideoCaptureEnabled = churchNotesVideoCaptureRemote && config["sermon_video_capture_enabled"].boolValue
        churchPhotoOCRCaptureEnabled = churchNotesPhotoOCRRemote && config["church_photo_ocr_capture_enabled"].boolValue
        churchNotesTranslationEnabled = config["church_notes_translation_enabled"].boolValue
        churchNotesCollaborationEnabled = config["church_notes_collaboration_enabled"].boolValue
        sermonSummaryGenerationEnabled = config["sermon_summary_generation_enabled"].boolValue
        scriptureDetectionEnabled = config["scripture_detection_enabled"].boolValue
        apiBibleScriptureProviderEnabled = config["api_bible_scripture_provider_enabled"].boolValue
        apiBibleLicensedDisplayTranslationsEnabled = config["api_bible_licensed_display_translations_enabled"].boolValue
        apiBibleCoreOfflineCacheEnabled = config["api_bible_core_offline_cache_enabled"].boolValue
        sermonActionExtractionEnabled = config["sermon_action_extraction_enabled"].boolValue
        sermonClipSuggestionEnabled = config["sermon_clip_suggestion_enabled"].boolValue
        churchNotesStudyGuideGenerationEnabled = config["church_notes_study_guide_generation_enabled"].boolValue
        noteShareViewerEnabled = config["feature_note_share_viewer"].boolValue
        churchNotesSmartObjectsEnabled = config["church_notes_smart_objects_enabled"].boolValue
        churchNotesProcessingKillSwitch = config["church_notes_processing_kill_switch"].boolValue
        churchNotesAudioProcessingKillSwitch = config["church_notes_audio_processing_kill_switch"].boolValue
        churchNotesImageModerationKillSwitch = config["church_notes_image_moderation_kill_switch"].boolValue
        churchNotesVideoProcessingKillSwitch = config["church_notes_video_processing_kill_switch"].boolValue

        churchNotesStudyGuideEnabled = churchNotesStudyGuideEnabled || churchNotesStudyGuideGenerationEnabled
        trustedContactsEnabled = config["trusted_contacts_enabled"].boolValue
        helpingSomeoneElseEnabled = config["helping_someone_else_enabled"].boolValue
        supportFollowupsEnabled = config["support_followups_enabled"].boolValue
        nonprofitRecommendationEnabled = config["nonprofit_recommendation_enabled"].boolValue
        bereanResourceRoutingEnabled = config["berean_resource_routing_enabled"].boolValue

        amenDailyDigestEnabled = config["amen_daily_digest_enabled"].boolValue
        amenDailyDigestWeatherEnabled = config["amen_daily_digest_weather_enabled"].boolValue
        amenDailyDigestHolidayEnabled = config["amen_daily_digest_holiday_enabled"].boolValue
        amenDailyDigestChristianCalendarEnabled = config["amen_daily_digest_christian_calendar_enabled"].boolValue
        amenDailyDigestExpandedSheetEnabled = config["amen_daily_digest_expanded_sheet_enabled"].boolValue
        amenDailyDigestBereanAIActionEnabled = config["amen_daily_digest_berean_ai_action_enabled"].boolValue
        amenDailyDigestChurchNotesActionEnabled = config["amen_daily_digest_church_notes_action_enabled"].boolValue
        amenDailyDigestFindChurchActionEnabled = config["amen_daily_digest_find_church_action_enabled"].boolValue
        amenDailyDigestSelahActionEnabled = config["amen_daily_digest_selah_action_enabled"].boolValue
        amenDailyDigestAIReflectionEnabled = config["amen_daily_digest_ai_reflection_enabled"].boolValue

        onboardingV2Enabled = config["ff_onboarding_v2"].boolValue

        bereanPulseEnabled = config["berean_pulse_enabled"].boolValue
        amenPulseEnabled = config["amen_pulse_enabled"].boolValue

        syncSpiritualOSAppStorageFlags(config)

        contextSystemEnabled = config["context_system_enabled"].boolValue
        contextManualEntryEnabled = config["context_manual_entry_enabled"].boolValue
        contextBereanInterviewEnabled = config["context_berean_interview_enabled"].boolValue
        contextUniversalImportEnabled = config["context_universal_import_enabled"].boolValue
        contextMatchingEnabled = config["context_matching_enabled"].boolValue
        contextExportEnabled = config["context_export_enabled"].boolValue
        contextQREnabled = config["context_qr_enabled"].boolValue
        contextCommitmentBridgeEnabled = config["context_commitment_bridge_enabled"].boolValue

        communityHubsEnabled = config["community_hubs_enabled"].boolValue
        communityObjectMatchingEnabled = config["community_object_matching_enabled"].boolValue
        lyricDetectionEnabled = config["lyric_detection_enabled"].boolValue
        objectHubViewEnabled = config["object_hub_view_enabled"].boolValue
        objectHubInlinePillEnabled = config["object_hub_inline_pill_enabled"].boolValue
        objectHubInlineClusterEnabled = config["object_hub_inline_cluster_enabled"].boolValue

        // Communities / Threads-Style Feeds gating
        arkCommunitiesEnabled = config["ark_communities_enabled"].boolValue
        covenantCommunitiesEnabled = config["covenant_communities_enabled"].boolValue
        unifiedFeedsSwitcherEnabled = config["unified_feeds_switcher_enabled"].boolValue
        savedCommunitiesEnabled = config["saved_communities_enabled"].boolValue
        viewInFeedEnabled = config["view_in_feed_enabled"].boolValue

        // System 33: Spatial Social OS
        spatialHomeEnabled = config["spatial_home_enabled"].boolValue
        spatialContextRailEnabled = config["spatial_context_rail_enabled"].boolValue
        provenanceTrustPanelEnabled = config["provenance_trust_panel_enabled"].boolValue
        creatorOSComposerEnabled = config["creator_os_composer_enabled"].boolValue
        truthfulAILabelsEnabled = config["truthful_ai_labels_enabled"].boolValue
        smartDiscoveryTransparencyEnabled = config["smart_discovery_transparency_enabled"].boolValue
        discoveryWhyShownEnabled = config["discovery_why_shown_enabled"].boolValue
        safetyOSEnabled = config["safety_os_enabled"].boolValue

        // System 34: Healthy Immersive Media Sessions
        healthyImmersiveMediaEnabled = config["healthy_immersive_media_enabled"].boolValue
        immersiveMediaSessionsEnabled = config["immersive_media_sessions_enabled"].boolValue
        mediaFiniteSessionsEnabled = config["media_finite_sessions_enabled"].boolValue
        finiteMediaQueuesEnabled = config["finite_media_queues_enabled"].boolValue
        mediaCompletionReflectionEnabled = config["media_completion_reflection_enabled"].boolValue
        mediaCompletionOverlayEnabled = config["media_completion_overlay_enabled"].boolValue
        mediaDoomScrollGuardEnabled = config["media_doom_scroll_guard_enabled"].boolValue
        mediaNoDoomScrollGuardrailsEnabled = config["media_no_doom_scroll_guardrails_enabled"].boolValue
        mediaSessionCheckpointsEnabled = config["media_session_checkpoints_enabled"].boolValue
        healthyMediaCheckpointsEnabled = config["healthy_media_checkpoints_enabled"].boolValue
        mediaKeyMomentsEnabled = config["media_key_moments_enabled"].boolValue
        mediaTranscriptEnabled = config["media_transcript_enabled"].boolValue
        mediaAIDraftMetadataEnabled = config["media_ai_draft_metadata_enabled"].boolValue
        mediaAIMetadataDraftsEnabled = config["media_ai_metadata_drafts_enabled"].boolValue
        mediaApprovalFlowEnabled = config["media_approval_flow_enabled"].boolValue
        mediaGeneratedMetadataApprovalRequired = config["media_generated_metadata_approval_required"].source == .static ? true : config["media_generated_metadata_approval_required"].boolValue
        mediaSelahAudioModeEnabled = config["media_selah_audio_mode_enabled"].boolValue
        mediaSelahOverlayEnabled = config["media_selah_overlay_enabled"].boolValue
        immersivePhotoSessionsEnabled = config["immersive_photo_sessions_enabled"].boolValue
        immersiveVideoSessionsEnabled = config["immersive_video_sessions_enabled"].boolValue
        communityMediaLayersEnabled = config["community_media_layers_enabled"].boolValue
        mediaCommunityLayerEnabled = config["media_community_layer_enabled"].boolValue
        mediaReflectionSheetEnabled = config["media_reflection_sheet_enabled"].boolValue
        hideVanityMetricsDefault = config["hide_vanity_metrics_default"].boolValue
        autoplayWithinSessionsEnabled = config["autoplay_within_sessions_enabled"].boolValue
        lateNightPauseEnabled = config["late_night_pause_enabled"].boolValue
        mediaWellbeingControlsEnabled = config["media_wellbeing_controls_enabled"].boolValue
        mediaTimestampedCommentsEnabled = config["media_timestamped_comments_enabled"].boolValue
        mediaSearchEnabled = config["media_search_enabled"].boolValue
        mediaChurchNotesIntegrationEnabled = config["media_church_notes_integration_enabled"].boolValue
        mediaPrayerQueueEnabled = config["media_prayer_queue_enabled"].boolValue
        mediaReflectionQueueEnabled = config["media_reflection_queue_enabled"].boolValue
        mediaLowBandwidthModeEnabled = config["media_low_bandwidth_mode_enabled"].boolValue
        mediaReportingEnabled = config["media_reporting_enabled"].boolValue
        mediaAccessibilityControlsEnabled = config["media_accessibility_controls_enabled"].boolValue
        mediaRankingV2Enabled = config["media_ranking_v2_enabled"].boolValue
        mediaLiquidGlassChromeEnabled = config["media_liquid_glass_chrome_enabled"].boolValue
        mediaProfileLiquidWhiteFlowEnabled = config["media_profile_liquid_white_flow_enabled"].boolValue
        mediaHideVanityMetricsEnabled = config["media_hide_vanity_metrics_enabled"].boolValue

        // System 35: Provenance & Authenticity OS
        mediaAuthenticityBadgesEnabled = config["media_authenticity_badges_enabled"].boolValue
        syntheticMediaDetectionEnabled = config["synthetic_media_detection_enabled"].boolValue
        mediaSyntheticDetectionEnabled = config["media_synthetic_detection_enabled"].boolValue
        contentCredentialsEnabled = config["content_credentials_enabled"].boolValue
        provenanceAuditChainEnabled = config["provenance_audit_chain_enabled"].boolValue

        smartShareSheetEnabled = config["smart_share_sheet_enabled"].boolValue
        smartShareSmartSuggestionsEnabled = config["smart_share_smart_suggestions_enabled"].boolValue
        smartShareRecipientRailEnabled = config["smart_share_recipient_rail_enabled"].boolValue
        smartShareContextEnabled = config["smart_share_context_enabled"].boolValue
        smartSharePreviewModeEnabled = config["smart_share_preview_mode_enabled"].boolValue

        translationSmartPillEnabled = config["translation_smart_pill_enabled"].boolValue
        translationRememberLanguagePreferenceEnabled = config["translation_remember_language_preference_enabled"].boolValue

        universalContentModelEnabled = config["universal_content_model_enabled"].boolValue
        universalCreateEnabled = config["universal_create_enabled"].boolValue
        mediaCreationEnabled = config["media_creation_enabled"].boolValue
        videoUploadEnabled = config["video_upload_enabled"].boolValue
        voiceoverEnabled = config["voiceover_enabled"].boolValue
        autoCaptionsEnabled = config["auto_captions_enabled"].boolValue
        immersiveMediaChromeEnabled = config["immersive_media_chrome_enabled"].boolValue
        immersiveFeedEnabled = config["immersive_feed_enabled"].boolValue
        continuationFeedEnabled = config["continuation_feed_enabled"].boolValue
        explainVideoEnabled = config["explain_video_enabled"].boolValue
        explainVideoRolloutPercent = config["explain_video_rollout_percent"].numberValue.intValue
        explainVideoMinAppVersion = config["explain_video_min_app_version"].stringValue
        explainVideoKillReason = config["explain_video_kill_reason"].stringValue

        // Per-Media Captions
        perMediaCaptionsEnabled = config["per_media_captions_enabled"].boolValue
        perMediaCaptionEducationEnabled = config["per_media_caption_education_enabled"].boolValue
        perMediaCaptionModerationEnabled = config["per_media_caption_moderation_enabled"].boolValue
        perMediaCaptionAltTextEnabled = config["per_media_caption_alt_text_enabled"].boolValue
        perMediaCaptionScriptureRefsEnabled = config["per_media_caption_scripture_refs_enabled"].boolValue

        // System 21: Berean Intelligence Layer v2
        bereanTheoLensEnabled = config["berean_theo_lens_enabled"].boolValue
        bereanSelahBridgeEnabled = config["berean_selah_bridge_enabled"].boolValue
        bereanChurchNotesBridgeEnabled = config["berean_church_notes_bridge_enabled"].boolValue
        bereanSmartPillsEnabled = config["berean_smart_pills_enabled"].boolValue
        bereanTheologyBoundaryEnabled = config["berean_theology_boundary_enabled"].boolValue
        bereanPersistentMemoryEnabled = config["berean_persistent_memory_enabled"].boolValue
        bereanStudyThreadsEnabled = config["berean_study_threads_enabled"].boolValue
        bereanTranslationCompareEnabled = config["berean_translation_compare_enabled"].boolValue
        bereanResearchViewEnabled = config["berean_research_view_enabled"].boolValue

        selahScriptureActionsEnabled = config["selah_scripture_actions_enabled"].boolValue
        churchStudyCompanionEnabled = config["church_study_companion_enabled"].boolValue
        churchNotesScriptureBridgeEnabled = config["church_notes_scripture_bridge_enabled"].boolValue
        selahAddToChurchNotesEnabled = config["selah_add_to_church_notes_enabled"].boolValue
        findChurchStudyActionsEnabled = config["find_church_study_actions_enabled"].boolValue
        afterServiceReflectionEnabled = config["after_service_reflection_enabled"].boolValue
        churchStudyGroupBridgeEnabled = config["church_study_group_bridge_enabled"].boolValue
        selahMediaOSEnabled = config["selah_media_os_enabled"].boolValue
        selahMediaOSMinAppVersion = config["selah_media_os_min_app_version"].stringValue
        selahMediaOSRolloutPercent = config["selah_media_os_rollout_percent"].numberValue.intValue
        selahMediaOSKillReason = config["selah_media_os_kill_reason"].stringValue

        messagingLiquidGlassAnimationsEnabled = config["messaging_liquid_glass_animations_enabled"].boolValue
        messagingTypingIndicatorEnabled = config["messaging_typing_indicator_enabled"].boolValue
        messagingFloatingHeaderPrototypeEnabled = config["messaging_floating_header_prototype_enabled"].boolValue
        messagingLiquidGlassContextMenuEnabled = config["messaging_liquid_glass_context_menu_enabled"].boolValue
        messagingLiquidGlassAttachmentMenuEnabled = config["messaging_liquid_glass_attachment_menu_enabled"].boolValue
        messagingSmartComposerEnabled = config["messaging_smart_composer_enabled"].boolValue
        messagingAttachmentMenuSmartActionsEnabled = config["messaging_attachment_menu_smart_actions_enabled"].boolValue
        messagingSmartPillsEnabled = config["messaging_smart_pills_enabled"].boolValue
        messagingTranslationEnabled = config["messaging_translation_enabled"].boolValue
        messagingCrossSurfaceActionsEnabled = config["messaging_cross_surface_actions_enabled"].boolValue
        messagingSafetyNudgesEnabled = config["messaging_safety_nudges_enabled"].boolValue
        messagingApprovalCardsEnabled = config["messaging_approval_cards_enabled"].boolValue
        messagingCatchUpEnabled = config["messaging_catch_up_enabled"].boolValue
        messagingVoiceIntelligenceEnabled = config["messaging_voice_intelligence_enabled"].boolValue
        messagingMediaIntelligenceEnabled = config["messaging_media_intelligence_enabled"].boolValue
        messagingPresencePolishEnabled = config["messaging_presence_polish_enabled"].boolValue
        actionIntelligenceEnabled = config["ff_action_intelligence"].boolValue
        cameraOSEnabled = config["camera_os_enabled"].boolValue

        // Social Safety OS
        socialSafetyOSEnabled = config["social_safety_os_enabled"].boolValue
        wellbeingFeedRankingEnabled = config["wellbeing_feed_ranking_enabled"].boolValue
        selahPauseEnabled = config["selah_pause_enabled"].boolValue
        emotionalCheckInEnabled = config["emotional_check_in_enabled"].boolValue
        privateReflectionEnabled = config["private_reflection_enabled"].boolValue
        healthyUseDashboardEnabled = config["healthy_use_dashboard_enabled"].boolValue
        dmRiskFirewallEnabled = config["dm_risk_firewall_enabled"].boolValue
        minorSafetyModeEnabled = config["minor_safety_mode_enabled"].boolValue
        sextortionPanicFlowEnabled = config["sextortion_panic_flow_enabled"].boolValue
        suspiciousRelationshipDetectorEnabled = config["suspicious_relationship_detector_enabled"].boolValue
        trustedContactEscalationEnabled = config["trusted_contact_escalation_enabled"].boolValue
        thinkFirstGuardEnabled = config["think_first_guard_enabled"].boolValue
        dogpileDetectionEnabled = config["dogpile_detection_enabled"].boolValue
        mercyModeRepliesEnabled = config["mercy_mode_replies_enabled"].boolValue
        reputationModerationEnabled = config["reputation_moderation_enabled"].boolValue
        victimShieldEnabled = config["victim_shield_enabled"].boolValue
        truthContextLayerEnabled = config["truth_context_layer_enabled"].boolValue
        aiMediaDisclosureEnabled = config["ai_media_disclosure_enabled"].boolValue
        claimSourceRequirementEnabled = config["claim_source_requirement_enabled"].boolValue
        communityCorrectionEnabled = config["community_correction_enabled"].boolValue
        theologicalGuardrailsEnabled = config["theological_guardrails_enabled"].boolValue
        feedModeControlsEnabled = config["feed_mode_controls_enabled"].boolValue
        feedBoundaryEnabled = config["feed_boundary_enabled"].boolValue
        purposeOpenScreenEnabled = config["purpose_open_screen_enabled"].boolValue
        engagementQualityRankingEnabled = config["engagement_quality_ranking_enabled"].boolValue
        algorithmTransparencyEnabled = config["algorithm_transparency_enabled"].boolValue

        // Berean Extended Intelligence
        bereanContextBridgeEnabled = config["berean_context_bridge_enabled"].boolValue
        bereanSafetyClassifierEnabled = config["berean_safety_classifier_enabled"].boolValue
        bereanLiquidGlassContextActionsEnabled = config["berean_liquid_glass_context_actions_enabled"].boolValue
        bereanSourceGroundingEnabled = config["berean_source_grounding_enabled"].boolValue
        bereanFollowUpsEnabled = config["berean_follow_ups_enabled"].boolValue
        bereanCommentaryCompareEnabled = config["berean_commentary_compare_enabled"].boolValue
        bereanTheologicalLensEnabled = config["berean_theological_lens_enabled"].boolValue
        bereanMemoryKillSwitch = config["berean_memory_kill_switch"].boolValue
        bereanContextBridgeKillSwitch = config["berean_context_bridge_kill_switch"].boolValue
        bereanSafetyClassifierKillSwitch = config["berean_safety_classifier_kill_switch"].boolValue
        bereanStudyThreadsKillSwitch = config["berean_study_threads_kill_switch"].boolValue
        bereanSourceGroundingKillSwitch = config["berean_source_grounding_kill_switch"].boolValue

        // Profile V2
        profileV2Enabled = config["profile_v2_enabled"].boolValue
        profileMediaGridEnabled = config["profile_media_grid_enabled"].boolValue
        pinnedContentEnabled = config["pinned_content_enabled"].boolValue
        creatorHighlightsEnabled = config["creator_highlights_enabled"].boolValue

        analyticsEnabled = config["analytics_enabled"].boolValue
        performanceTelemetryEnabled = config["performance_telemetry_enabled"].boolValue

        // Smart Account Resume
        smartAccountResumeEnabled = config["smart_account_resume_enabled"].boolValue
        smartAccountResumeAutoContinueEnabled = config["smart_account_resume_auto_continue_enabled"].boolValue
        smartAccountResumeOfflineRetryEnabled = config["smart_account_resume_offline_retry_enabled"].boolValue

        // AI Usage Labels
        aiUsageLabelPillEnabled = config["ai_usage_label_pill_enabled"].boolValue

        // System 27: Berean Grok Helper Pipeline
        bereanHelperModelEnabled            = config["berean_helper_model_enabled"].boolValue
        bereanHelperPromptSimplifyEnabled   = config["berean_helper_prompt_simplify_enabled"].boolValue
        bereanHelperLinkSummaryEnabled      = config["berean_helper_link_summary_enabled"].boolValue
        bereanHelperExternalContextEnabled  = config["berean_helper_external_context_enabled"].boolValue
        bereanHelperStudyOutlineEnabled     = config["berean_helper_study_outline_enabled"].boolValue
        bereanHelperExtractThemesEnabled    = config["berean_helper_extract_themes_enabled"].boolValue
        bereanHelperProvenanceChipsEnabled  = config["berean_helper_provenance_chips_enabled"].boolValue

        // System 28: Feed Intelligence OS
        feedIntelligenceEnabled        = config["feed_intelligence_enabled"].boolValue
        guideMyFeedEnabled             = config["guide_my_feed_enabled"].boolValue
        whyThisPostBackendEnabled      = config["why_this_post_backend_enabled"].boolValue
        feedModesEnabled               = config["feed_modes_enabled"].boolValue

        // System 29: Liquid Glass Intelligence Layer
        liquidGlassSystemEnabled              = config["liquid_glass_system_enabled"].boolValue
        liquidGlassPresencePillsEnabled       = config["liquid_glass_presence_pills_enabled"].boolValue
        semanticUnderlineEnabled              = config["semantic_underline_enabled"].boolValue
        inlineDefinitionPopoverEnabled        = config["inline_definition_popover_enabled"].boolValue
        smartActionDetectionEnabled           = config["smart_action_detection_enabled"].boolValue
        pulseAwarenessEnabled                 = config["pulse_awareness_enabled"].boolValue
        knowledgeThreadsEnabled               = config["knowledge_threads_enabled"].boolValue
        selahSemanticSaveEnabled              = config["selah_semantic_save_enabled"].boolValue
        churchNotesSemanticActionsEnabled     = config["church_notes_semantic_actions_enabled"].boolValue
        mediaChromeLiquidGlassEnabled         = config["media_chrome_liquid_glass_enabled"].boolValue
        composerPresenceActionsEnabled        = config["composer_presence_actions_enabled"].boolValue
        bottomBarLiquidGlassEnabled           = config["bottom_bar_liquid_glass_enabled"].boolValue
        amenDiscoverEnabled                   = config["amen_discover_enabled"].boolValue
        amenDiscoverLiquidGlassEnabled        = config["amen_discover_liquid_glass_enabled"].boolValue
        amenDiscoverRankingEnabled            = config["amen_discover_ranking_enabled"].boolValue
        amenDiscoverWhyThisEnabled            = config["amen_discover_why_this_enabled"].boolValue
        amenDiscoverLocalChurchesEnabled      = config["amen_discover_local_churches_enabled"].boolValue
        amenDiscoverSelahEnabled              = config["amen_discover_selah_enabled"].boolValue
        amenDiscoverSafetyFeedbackEnabled     = config["amen_discover_safety_feedback_enabled"].boolValue

        // System 31: Voice Prayer & Testimony Comments
        voicePrayerCommentsEnabled                    = config["voice_prayer_comments_enabled"].boolValue
        voiceTestimonyCommentsEnabled                 = config["voice_testimony_comments_enabled"].boolValue
        voiceCommentTranscriptRequired                = config["voice_comment_transcript_required"].boolValue
        voiceCommentSummaryEnabled                    = config["voice_comment_summary_enabled"].boolValue
        voiceCommentReviewQueueEnabled                = config["voice_comment_review_queue_enabled"].boolValue
        voiceCommentPrayerCircleVisibilityEnabled     = config["voice_comment_prayer_circle_visibility_enabled"].boolValue

        amenRealtimeVoiceEnabled                      = config["amen_realtime_voice_enabled"].boolValue
        amenLiveCaptionsEnabled                       = config["amen_live_captions_enabled"].boolValue
        amenTranslationEnabled                        = config["amen_translation_enabled"].boolValue
        amenGraphicStudioEnabled                      = config["amen_graphic_studio_enabled"].boolValue
        amenCreatorKitEnabled                         = config["amen_creator_kit_enabled"].boolValue
        amenAgentWorkflowsEnabled                     = config["amen_agent_workflows_enabled"].boolValue
        amenExplainEnabled                            = config["amen_explain_enabled"].boolValue
        amenImproveEnabled                            = config["amen_improve_enabled"].boolValue
        amenSummarizeEnabled                          = config["amen_summarize_enabled"].boolValue
        amenAIUsageLabelsRequired                     = config["amen_ai_usage_labels_required"].boolValue
        bereanRealtimeEnabled                         = config["berean_realtime_enabled"].boolValue
        bereanTranslationEnabled                      = config["berean_translation_enabled"].boolValue
        bereanPrayerRoomsEnabled                      = config["berean_prayer_rooms_enabled"].boolValue
        bereanVoiceAssistantEnabled                   = config["berean_voice_assistant_enabled"].boolValue
        bereanSmartNotesEnabled                       = config["berean_smart_notes_enabled"].boolValue
        bereanLiveCaptionsEnabled                     = config["berean_live_captions_enabled"].boolValue
        bereanRealtimeKillSwitch                      = config["berean_realtime_kill_switch"].boolValue
        amenRealtimeVoiceKillSwitch                   = config["amen_realtime_voice_kill_switch"].boolValue
        amenLiveCaptionsKillSwitch                    = config["amen_live_captions_kill_switch"].boolValue
        amenTranslationKillSwitch                     = config["amen_translation_kill_switch"].boolValue
        amenGraphicGenerationKillSwitch               = config["amen_graphic_generation_kill_switch"].boolValue
        amenAgentWorkflowKillSwitch                   = config["amen_agent_workflow_kill_switch"].boolValue
        amenExplainKillSwitch                         = config["amen_explain_kill_switch"].boolValue
        amenImproveKillSwitch                         = config["amen_improve_kill_switch"].boolValue
        amenSummarizeKillSwitch                       = config["amen_summarize_kill_switch"].boolValue

        // System 32: Communication OS
        messagesSmartContextEnabled         = config["messages_smart_context_enabled"].boolValue
        groupDiscussionPulseEnabled         = config["group_discussion_pulse_enabled"].boolValue
        threadSummaryEnabled                = config["thread_summary_enabled"].boolValue
        catchUpDigestEnabled                = config["catch_up_digest_enabled"].boolValue
        threadDecisionExtractionEnabled     = config["thread_decision_extraction_enabled"].boolValue
        threadActionExtractionEnabled       = config["thread_action_extraction_enabled"].boolValue
        threadQuestionDetectionEnabled      = config["thread_question_detection_enabled"].boolValue
        smartPresenceEnabled                = config["smart_presence_enabled"].boolValue
        smartReactionsEnabled               = config["smart_reactions_enabled"].boolValue
        mediaIntelligenceEnabled            = config["media_intelligence_enabled"].boolValue
        conversationMemorySearchEnabled     = config["conversation_memory_search_enabled"].boolValue
        commandPaletteEnabled               = config["command_palette_enabled"].boolValue
        smartRepliesEnabled                 = config["smart_replies_enabled"].boolValue
        multiPaneCommunicationEnabled       = config["multi_pane_communication_enabled"].boolValue
        liquidGlassCommunicationUIEnabled   = config["liquid_glass_communication_ui_enabled"].boolValue

        // System 33: ContentOS
        contentOSEnabled                    = config["content_os_enabled"].boolValue
        contentApprovalWorkflowEnabled      = config["content_approval_workflow_enabled"].boolValue
        contentForwardingEnabled            = config["content_forwarding_enabled"].boolValue
        contentAIRouterEnabled              = config["content_ai_router_enabled"].boolValue
        contentAuditLogEnabled              = config["content_audit_log_enabled"].boolValue

        // Aegis OS — Pre-Post Content Safety Gate
        aegisPrePostReviewEnabled            = config["aegis_pre_post_review_enabled"].boolValue

        // Berean OS — Wisdom Operating System
        bereanOSProjectsEnabled              = config["berean_os_projects_enabled"].boolValue
        bereanOSResearchEngineEnabled        = config["berean_os_research_engine_enabled"].boolValue
        bereanOSWisdomEngineEnabled          = config["berean_os_wisdom_engine_enabled"].boolValue
        bereanOSMultiPerspectiveEnabled      = config["berean_os_multi_perspective_enabled"].boolValue
        bereanOSDebateEngineEnabled          = config["berean_os_debate_engine_enabled"].boolValue
        bereanOSSocialKnowledgeFeedEnabled   = config["berean_os_social_knowledge_feed_enabled"].boolValue
        bereanOSAdvisoryBoardsEnabled        = config["berean_os_advisory_boards_enabled"].boolValue
        bereanOSMentorOSEnabled              = config["berean_os_mentor_os_enabled"].boolValue
        bereanOSKnowledgeGraphEnabled        = config["berean_os_knowledge_graph_enabled"].boolValue
        bereanOSOnboardingEnabled            = config["berean_os_onboarding_enabled"].boolValue
        bereanOSMemoryBrainEnabled           = config["berean_os_memory_brain_enabled"].boolValue
        bereanOSActionPlannerEnabled         = config["berean_os_action_planner_enabled"].boolValue
        bereanOSTruthLabelsEnabled           = config["berean_os_truth_labels_enabled"].boolValue
        bereanOSSourceExplorerEnabled        = config["berean_os_source_explorer_enabled"].boolValue
        bereanOSSocialProjectsEnabled        = config["berean_os_social_projects_enabled"].boolValue
        bereanOSCommunityIntelligenceEnabled = config["berean_os_community_intelligence_enabled"].boolValue
        bereanOSLivingDocumentsEnabled       = config["berean_os_living_documents_enabled"].boolValue

        // System 36: Context-First Discussion OS
        discussionModesEnabled          = config["discussion_modes_enabled"].boolValue
        contextParticipationEnabled     = config["context_participation_enabled"].boolValue
        discussionHealthEnabled         = config["discussion_health_enabled"].boolValue
        draftIntelligenceEnabled        = config["draft_intelligence_enabled"].boolValue
        discussionSummaryEnabled        = config["discussion_summary_enabled"].boolValue
        discussionMediatorEnabled       = config["discussion_mediator_enabled"].boolValue
        communityMemoryEnabled          = config["community_memory_enabled"].boolValue
        discussionActionsEnabled        = config["discussion_actions_enabled"].boolValue
        participationTiersEnabled       = config["participation_tiers_enabled"].boolValue
        discussionCommandCenterEnabled  = config["discussion_command_center_enabled"].boolValue

        // System 37: Community OS Foundation
        communityOSEnabled = config["community_os_enabled"].boolValue

        // Ambient OS
        ambientOSEnabled = config["ambient_os_enabled"].boolValue

        // System 38: Connect Hub
        connectHubEnabled    = config["connect_hub_enabled"].boolValue
        connectYouMenuEnabled = config["connect_you_menu_enabled"].boolValue

        // System 39: Connect UI Polish Waves
        connectLayoutV2Enabled     = config["connect_layout_v2_enabled"].boolValue
        connectPolishV2Enabled     = config["connect_polish_v2_enabled"].boolValue
        connectEmptyStatesEnabled  = config["connect_empty_states_enabled"].boolValue
        connectSmartBereanEnabled  = config["connect_smart_berean_enabled"].boolValue
        connectOfflineQueueEnabled = config["connect_offline_queue_enabled"].boolValue

        // Music Attachment
        musicAttachmentEnabled = config.configValue(forKey: "music_attachment_enabled").boolValue

        // Live Activities
        liveActivityPrayerRequestEnabled = config["live_activity_prayer_request_enabled"].boolValue
        liveActivityPushToStartEnabled   = config["live_activity_push_to_start_enabled"].boolValue

        // Accessibility + Replay
        simpleModeFeatureEnabled = config["simple_mode_feature_enabled"].boolValue
        replayEnabled            = config["replay_enabled"].boolValue

        // Community OS sub-flags
        communityOSDiscussionEnabled         = config["community_os_discussion_enabled"].boolValue
        communityOSPrayerOSEnabled           = config["community_os_prayer_os_enabled"].boolValue
        communityOSActionPillEnabled         = config["community_os_action_pill_enabled"].boolValue
        communityOSUniversalComposerEnabled  = config["community_os_universal_composer_enabled"].boolValue
        communityOSChurchOSEnabled           = config["community_os_church_os_enabled"].boolValue
        communityOSOrgOSEnabled              = config["community_os_org_os_enabled"].boolValue
        communityOSOpportunityEnabled        = config["community_os_opportunity_enabled"].boolValue

        // Conversation OS (Spaces Intelligence)
        conversationOSEnabled                              = config["conversation_os_enabled"].boolValue
        conversationSummariesEnabled                       = config["conversation_summaries_enabled"].boolValue
        catchUpRecapsEnabled                               = config["catch_up_recaps_enabled"].boolValue
        topicClusteringEnabled                             = config["topic_clustering_enabled"].boolValue
        actionExtractionEnabled                            = config["action_extraction_enabled"].boolValue
        organizationalMemoryEnabled                        = config["organizational_memory_enabled"].boolValue
        personalizedInsightsEnabled                        = config["personalized_insights_enabled"].boolValue
        ambientConversationIntelligenceEnabled             = config["ambient_conversation_intelligence_enabled"].boolValue
        conversationOSLiquidGlassEnabled                   = config["conversation_os_liquid_glass_enabled"].boolValue
        conversationOSDebugTelemetryEnabled                = config["conversation_os_debug_telemetry_enabled"].boolValue
        conversationOSSensitiveSpaceRestrictionsEnabled    = config["conversation_os_sensitive_space_restrictions_enabled"].boolValue

        // Find Church 2.0
        findChurch2OnboardingEnabled     = config["findChurch2_onboarding"].boolValue
        findChurch2MatchExplainEnabled   = config["findChurch2_matchExplain"].boolValue
        findChurch2GatheringsEnabled     = config["findChurch2_gatherings"].boolValue
        findChurch2VisitPlannerEnabled   = config["findChurch2_visitPlanner"].boolValue
        findChurch2ClaimPortalEnabled    = config["findChurch2_claimPortal"].boolValue
        findChurch2ConciergeEnabled      = config["findChurch2_concierge"].boolValue
        findChurch2MapHybridEnabled      = config["findChurch2_mapHybrid"].boolValue
        findChurch2AvailabilityEnabled   = config["findChurch2_availability"].boolValue
        findChurch2TrustSignalsEnabled   = config["findChurch2_trustSignals"].boolValue
        findChurch2DesignRefreshEnabled  = config["findChurch2_designRefresh"].boolValue

        // Master-Run Phase Gates
        findAChurchEnabled             = config["find_a_church_enabled"].boolValue
        postsLiquidGlassEnabled        = config["posts_liquid_glass_enabled"].boolValue
        whySeeingThisEnabled           = config["why_seeing_this_enabled"].boolValue
        selahStoriesEnabled            = config["selah_stories_enabled"].boolValue
        selahStoriesPremiumAIEnabled   = config["selah_stories_premium_ai_enabled"].boolValue

        // Selah Enhancement
        selahPersonalCorpusEnabled      = config["selah_personal_corpus_enabled"].boolValue
        selahDiscernmentEnabled         = config["selah_discernment_enabled"].boolValue
        selahDiscernmentSharingEnabled  = config["selah_discernment_sharing_enabled"].boolValue

        // GAP A5-P1 bridge call
        let communicationOSValues = CommunicationOSRemoteConfigBridge.allFlagKeys.reduce(into: [String: Bool]()) { values, key in
            values[key] = config.configValue(forKey: key).boolValue
        }
        CommunicationOSRemoteConfigBridge.applyRemoteConfig(communicationOSValues)
    }

    private func syncSpiritualOSAppStorageFlags(_ config: RemoteConfig) {
        let keys = [
            "spiritualOS_enabled",
            "spiritualOS_daily_enabled",
            "spiritualOS_hub_enabled",
            "spiritualOS_planner_enabled",
            "spiritualOS_spaces_dashboard_enabled",
            "spiritualOS_create_space_enhanced_enabled",
            "spiritualOS_command_center_enabled",
            "spiritualOS_assistant_bar_enabled",
            "spiritualOS_context_engine_enabled",
            "spiritualOS_community_os_enabled"
        ]

        for key in keys {
            UserDefaults.standard.set(config[key].boolValue, forKey: key)
        }
    }

    private func applyUITestOverrides() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-test-enable-composer-audio") {
            composerApprovedAudioEnabled = true
        }
        if args.contains("--ui-test-disable-composer-audio") {
            composerApprovedAudioEnabled = false
        }
        if args.contains("--ui-test-enable-note-share-viewer") {
            noteShareViewerEnabled = true
        }
        if args.contains("--ui-test-enable-church-notes-smart-objects") {
            churchNotesSmartObjectsEnabled = true
        }
        if args.contains("--ui-test-enable-camera-os") {
            cameraOSEnabled = true
        }
    }

    // MARK: - Explain Video Rollout Gate

    /// Returns true only when:
    ///  1. The feature flag is ON.
    ///  2. The kill switch is not active (killReason is empty).
    ///  3. The running app version meets the minimum version requirement.
    ///  4. The user UID falls inside the rollout bucket (deterministic, hash-stable).
    func isExplainVideoActive(uid: String) -> Bool {
        guard explainVideoEnabled else { return false }
        guard explainVideoKillReason.isEmpty else { return false }
        guard AppVersion.meetsMinimum(explainVideoMinAppVersion) else { return false }
        // djb2 hash for deterministic, stable bucketing across app launches.
        let hash = uid.utf8.reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) }
        let bucket = Int(hash % 100)
        return bucket < explainVideoRolloutPercent
    }
}

// MARK: - App Version Helper

private enum AppVersion {
    static func meetsMinimum(_ minimum: String) -> Bool {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return current.compare(minimum, options: .numeric) != .orderedAscending
    }
}
