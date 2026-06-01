// AMENFeatureFlags.swift
// AMEN App — Unified Feature Flag System
//
// Single source of truth for all feature flags across the platform.
// Backed by Firebase Remote Config with safe local defaults.
// All 7 major system rollouts are gated here.
//
// Rollout philosophy:
//   - Every major feature starts OFF in production
//   - Flags are additive — never remove a flag without a deprecation cycle
//   - Flags can be targeted per-user via Remote Config audiences

import Foundation
import Combine
import FirebaseRemoteConfig

enum ChurchStudyHighlightSharingPolicy {
    @MainActor
    static var canPostPublicHighlight: Bool {
        AMENFeatureFlags.shared.churchStudyGroupBridgeEnabled
    }

    static let publicHighlightLabel = "Share this highlight publicly"
}

@MainActor
final class AMENFeatureFlags: ObservableObject {

    static let shared = AMENFeatureFlags()

    // MARK: - System 1: Advanced Moderation
    @Published private(set) var moderationV2Enabled: Bool = true
    @Published private(set) var imageModerationEnabled: Bool = true
    @Published private(set) var dmEnhancedScanningEnabled: Bool = true
    @Published private(set) var moderationAppealsEnabled: Bool = true
    @Published private(set) var trustScoringEnabled: Bool = true

    // MARK: - Payments / Stripe / Giving (B-01, B-02, B-24)
    @Published private(set) var paymentsEnabled: Bool = true

    // MARK: - Berean Drive / CarPlay (B-23)
    @Published private(set) var bereanDriveEnabled: Bool = false

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

    // MARK: - Nearby People Discovery (privacy-gated, opt-in)
    /// Kill switch for "Find People Nearby". Defaults OFF so it can be enabled gradually.
    @Published private(set) var nearbyPeopleDiscoveryEnabled: Bool = true

    // MARK: - System 5: Church Discovery
    @Published private(set) var churchDiscoverySmartRankingEnabled: Bool = true
    @Published private(set) var churchFirstVisitCompanionEnabled: Bool = true
    @Published private(set) var churchServiceRemindersEnabled: Bool = true
    @Published private(set) var churchReviewsEnabled: Bool = true
    @Published private(set) var churchInteractionTrackingEnabled: Bool = true
    @Published private(set) var churchJourneyTimelineEnabled: Bool = true
    @Published private(set) var churchPostCardDraftsEnabled: Bool = true
    @Published private(set) var churchExplainableRecommendationsEnabled: Bool = true

    // MARK: - System N: Smart Community Search (Ask Amen)
    /// Kill switch: set false via Remote Config to immediately disable Smart Finder for all users.
    @Published private(set) var smartCommunitySearchEnabled: Bool = true
    /// Controls whether Google Maps / Places data is included in Smart Finder results.
    @Published private(set) var smartCommunitySearchUsesExternalPlaces: Bool = true
    /// Controls whether the AI intent parser is used; falls back to deterministic heuristics if false.
    @Published private(set) var smartCommunitySearchUsesAIParser: Bool = true

    // MARK: - System 6: Studio / Creator Marketplace
    @Published private(set) var studioEnabled: Bool = true
    @Published private(set) var studioMonetizationEnabled: Bool = true
    @Published private(set) var studioJobBoardEnabled: Bool = true
    @Published private(set) var studioAITaggingEnabled: Bool = true

    // MARK: - System 7: Creator Spaces + Presence Posts
    @Published private(set) var creatorSpacesEnabled: Bool = true
    @Published private(set) var presencePostsEnabled: Bool = true
    @Published private(set) var mediaAuthenticityEnabled: Bool = true

    // MARK: - System 7: Knowledge Graph
    @Published private(set) var knowledgeGraphEnabled: Bool = true
    @Published private(set) var knowledgeGraphRelatedContentEnabled: Bool = true
    @Published private(set) var knowledgeGraphSemanticSearchEnabled: Bool = true

    // MARK: - System 8: Action Threads (Care Workflows)
    @Published private(set) var actionThreadsEnabled: Bool = true
    @Published private(set) var actionSuggestionsEnabled: Bool = true
    @Published private(set) var careFollowupsEnabled: Bool = false
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
    /// Enables the multi-signal smart ranking pipeline in SuggestedFollowsService
    /// (church match 40pt, mutual follows 30pt, city 15pt, scripture translation 10pt, recency 5pt).
    /// Default ON. Set false via Remote Config to fall back to RecommendedUsersAIService.
    @Published private(set) var suggestedFollowsSmartRankingEnabled: Bool = true

    // MARK: - System 14: Social Context & UX Enhancements
    @Published private(set) var mutualContextRowEnabled: Bool = true
    @Published private(set) var presenceIntelligenceEnabled: Bool = true
    @Published private(set) var messageRequestIntelligenceEnabled: Bool = true
    @Published private(set) var trustExplainerEnabled: Bool = true
    @Published private(set) var postDividerEnabled: Bool = true
    @Published private(set) var feedViewModeSwitcherEnabled: Bool = true
    @Published private(set) var mediaFilterPillsEnabled: Bool = true
    @Published private(set) var mediaDetailViewEnabled: Bool = true
    @Published private(set) var mediaViewerFloatingEngagementPillEnabled: Bool = true
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
    @Published private(set) var accessibilityIntelligenceEnabled: Bool = true
    @Published private(set) var meaningAwareTranslationEnabled: Bool = true
    @Published private(set) var naturalModeEnabled: Bool = true
    @Published private(set) var contextualModeEnabled: Bool = true
    @Published private(set) var readabilityLayerEnabled: Bool = true
    @Published private(set) var contentDifficultyScoring: Bool = true
    @Published private(set) var audioNarrationEnabled: Bool = true
    @Published private(set) var contextBridgeEnabled: Bool = true
    @Published private(set) var adaptiveAccessibilityEnabled: Bool = true
    @Published private(set) var conversationBridgeEnabled: Bool = true
    @Published private(set) var smartTranslationVisibilityEnabled: Bool = true
    @Published private(set) var sideBySideTranslationEnabled: Bool = true
    @Published private(set) var perLanguageAutoTranslateEnabled: Bool = true
    @Published private(set) var creationLanguageEnabled: Bool = true
    @Published private(set) var adaptiveTranslationEnabled: Bool = true

    // MARK: - System 16: Berean Spiritual Intelligence Layers
    @Published private(set) var bereanSpiritualLayersEnabled: Bool = true
    @Published private(set) var livingScriptureGraphEnabled: Bool = true
    @Published private(set) var spiritualStateLayerEnabled: Bool = true
    @Published private(set) var guidedDiscipleshipEnabled: Bool = true
    @Published private(set) var scriptureImmersionEnabled: Bool = true
    @Published private(set) var authorityAlignmentEnabled: Bool = true

    // MARK: - Wellness & Mental Health System
    // All default OFF — new surface, roll out gradually via Remote Config audiences.
    /// Master switch for the adaptive wellness surface (mood check-in, smart tools, Care mode).
    @Published private(set) var wellnessAdaptiveSurfaceEnabled: Bool = true
    /// Mood-driven verse and tool reordering.
    @Published private(set) var wellnessMoodCheckInEnabled: Bool = true
    /// Berean Care mode — presence-first branching inside the wellness surface.
    @Published private(set) var wellnessBereanCareModeEnabled: Bool = true
    /// On-device only pattern insights. Never uploads data.
    @Published private(set) var wellnessLocalInsightEnabled: Bool = true
    /// Time-of-day and liturgical season tool reordering.
    @Published private(set) var wellnessRhythmContextEnabled: Bool = true
    /// 3-question peer support group intake matching.
    @Published private(set) var wellnessGroupsIntakeEnabled: Bool = true
    /// Contemplative practice cards (Examen, Lectio, Centering Prayer, Compline) in Faith tab.
    @Published private(set) var wellnessContemplativePracticesEnabled: Bool = true

    // MARK: - System 17: Resources Intelligence
    @Published private(set) var resourcesIntelligenceEnabled: Bool = true
    @Published private(set) var supportDraftDetectionEnabled: Bool = true
    @Published private(set) var churchNoteCareSummaryEnabled: Bool = true
    @Published private(set) var churchNotesServerSummaryEnabled: Bool = true
    // Church Notes Media Intelligence
    @Published private(set) var churchNotesAudioCaptureEnabled: Bool = true
    @Published private(set) var churchNotesPhotoOCREnabled: Bool = true
    @Published private(set) var churchNotesVideoCaptureEnabled: Bool = true
    @Published private(set) var churchNotesAIDraftReviewEnabled: Bool = true
    @Published private(set) var churchNotesStudyGuideEnabled: Bool = true
    @Published private(set) var churchNotesPrayerPromptsEnabled: Bool = true
    @Published private(set) var churchNotesIntelligenceEnabled: Bool = true
    @Published private(set) var sermonAudioCaptureEnabled: Bool = true
    @Published private(set) var sermonVideoCaptureEnabled: Bool = true
    @Published private(set) var churchPhotoOCRCaptureEnabled: Bool = true
    @Published private(set) var churchNotesTranslationEnabled: Bool = true
    @Published private(set) var churchNotesCollaborationEnabled: Bool = true
    @Published private(set) var sermonSummaryGenerationEnabled: Bool = true
    @Published private(set) var scriptureDetectionEnabled: Bool = true
    @Published private(set) var sermonActionExtractionEnabled: Bool = true
    @Published private(set) var sermonClipSuggestionEnabled: Bool = true
    @Published private(set) var churchNotesStudyGuideGenerationEnabled: Bool = true
    // Kill switch: set true in Remote Config to block all new processing jobs instantly.
    @Published private(set) var churchNotesProcessingKillSwitch: Bool = false
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
    @Published private(set) var bannerRailEnabled: Bool = true

    // MARK: - System 19: Berean Pulse
    @Published private(set) var bereanPulseEnabled: Bool = true

    // MARK: - System 20: Ambient Glow Intelligence Layer
    @Published private(set) var ambientGlowEnabled: Bool = true
    @Published private(set) var ambientGlowAuthenticationEnabled: Bool = true
    @Published private(set) var ambientGlowBereanEnabled: Bool = true
    @Published private(set) var ambientGlowSelahEnabled: Bool = true
    @Published private(set) var ambientGlowPrayerEnabled: Bool = true
    @Published private(set) var ambientGlowMediaEnabled: Bool = true
    @Published private(set) var ambientGlowFeedEnabled: Bool = true

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
    // DEBUG: default ON for local manual testing. Release: default OFF until Remote Config activates.
    #if DEBUG
    @Published private(set) var communityHubsEnabled: Bool = true
    @Published private(set) var communityObjectMatchingEnabled: Bool = true
    @Published private(set) var lyricDetectionEnabled: Bool = true
    @Published private(set) var objectHubViewEnabled: Bool = true
    @Published private(set) var objectHubInlinePillEnabled: Bool = true
    @Published private(set) var objectHubInlineClusterEnabled: Bool = true
    #else
    @Published private(set) var communityHubsEnabled: Bool = true
    @Published private(set) var communityObjectMatchingEnabled: Bool = true
    @Published private(set) var lyricDetectionEnabled: Bool = true
    @Published private(set) var objectHubViewEnabled: Bool = true
    @Published private(set) var objectHubInlinePillEnabled: Bool = true
    @Published private(set) var objectHubInlineClusterEnabled: Bool = true
    #endif

    // MARK: - Communities / Threads-Style Feeds Gating
    // Ark legacy /communities path is unsafe at the rules layer until callable-protected.
    // Default OFF in production until the legacy code is fully retired or hardened.
    @Published private(set) var arkCommunitiesEnabled: Bool = true
    // Covenant is canonical for tiered creator communities.
    @Published private(set) var covenantCommunitiesEnabled: Bool = true
    // Unified Threads-style Feeds switcher (For You / Following / Quiet / Your / Saved / Popular).
    @Published private(set) var unifiedFeedsSwitcherEnabled: Bool = true
    // Community-level Saved / Bookmark.
    @Published private(set) var savedCommunitiesEnabled: Bool = true
    // "View in Feed" — scopes the home timeline to a covenant/hub/topic.
    // Default OFF until the FirebasePostService scoped-query path is
    // fully gated by server-side membership + moderation filtering.
    @Published private(set) var viewInFeedEnabled: Bool = true

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
    /// ARISE/OUTPOUR short-form video pipeline.
    @Published private(set) var ariseEnabled: Bool = true
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
    /// When true, caption fields moderate on blur/save before publish.
    @Published private(set) var perMediaCaptionIncrementalModerationEnabled: Bool = true

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
    @Published private(set) var messagingFloatingHeaderPrototypeEnabled: Bool = true
    @Published private(set) var messagingLiquidGlassContextMenuEnabled: Bool = true
    @Published private(set) var messagingLiquidGlassAttachmentMenuEnabled: Bool = true
    @Published private(set) var messagingSmartComposerEnabled: Bool = true
    @Published private(set) var messagingAttachmentMenuSmartActionsEnabled: Bool = true

    // MARK: - System 20 continued: Messaging Intelligence (Phases 4-12)
    @Published private(set) var messagingSmartPillsEnabled: Bool = true
    @Published private(set) var messagingTranslationEnabled: Bool = true
    @Published private(set) var messagingCrossSurfaceActionsEnabled: Bool = true
    @Published private(set) var messagingSafetyNudgesEnabled: Bool = true
    @Published private(set) var messagingApprovalCardsEnabled: Bool = true
    @Published private(set) var messagingCatchUpEnabled: Bool = true
    @Published private(set) var messagingVoiceIntelligenceEnabled: Bool = true
    @Published private(set) var messagingMediaIntelligenceEnabled: Bool = true
    @Published private(set) var messagingPresencePolishEnabled: Bool = true

    // MARK: - Amen Smart Message Intelligence
    @Published private(set) var smartMessageIntelligenceEnabled: Bool = true
    @Published private(set) var smartEventDetectionEnabled: Bool = true
    @Published private(set) var prayerIntelligenceEnabled: Bool = true
    @Published private(set) var discussionSummariesEnabled: Bool = true
    @Published private(set) var contextualBereanActionsEnabled: Bool = true
    @Published private(set) var topicExtractionEnabled: Bool = true
    @Published private(set) var semanticSearchEnabled: Bool = true
    @Published private(set) var studyModeEnabled: Bool = true
    @Published private(set) var voiceIntelligenceEnabled: Bool = true
    @Published private(set) var knowledgeGraphMemoryEnabled: Bool = true

    // MARK: - Communication OS (System 32: Next-Gen Messaging + Group Discussions)
    @Published private(set) var messagesSmartContextEnabled: Bool = true
    @Published private(set) var groupDiscussionPulseEnabled: Bool = true
    @Published private(set) var threadSummaryEnabled: Bool = true
    @Published private(set) var catchUpDigestEnabled: Bool = true
    @Published private(set) var threadDecisionExtractionEnabled: Bool = true
    @Published private(set) var threadActionExtractionEnabled: Bool = true
    @Published private(set) var threadQuestionDetectionEnabled: Bool = true
    @Published private(set) var threadPrayerDetectionEnabled: Bool = true
    @Published private(set) var smartPresenceEnabled: Bool = true
    @Published private(set) var smartReactionsEnabled: Bool = true
    @Published private(set) var mediaIntelligenceEnabled: Bool = true
    @Published private(set) var conversationMemorySearchEnabled: Bool = true
    @Published private(set) var commandPaletteEnabled: Bool = true
    @Published private(set) var smartCommandLayerEnabled: Bool = true
    @Published private(set) var smartCommandLayerHomeEnabled: Bool = true
    @Published private(set) var smartCommandLayerMessagesEnabled: Bool = true
    @Published private(set) var smartCommandLayerBereanEnabled: Bool = true
    @Published private(set) var smartCommandLayerChurchNotesEnabled: Bool = true
    @Published private(set) var smartCommandLayerSpacesEnabled: Bool = true
    @Published private(set) var smartCommandLayerCreatePostEnabled: Bool = true
    @Published private(set) var smartCommandLayerEventsEnabled: Bool = true
    @Published private(set) var smartCommandLayerMediaEnabled: Bool = true
    @Published private(set) var smartRepliesEnabled: Bool = true
    @Published private(set) var multiPaneCommunicationEnabled: Bool = true
    @Published private(set) var liquidGlassCommunicationUIEnabled: Bool = true
    @Published private(set) var replyPreviewRotationEnabled: Bool = false  // FLIP TO false BEFORE SHIPPING

    // MARK: - Conversation OS Intelligence Layer (extends System 32)
    /// Master kill switch for all Conversation OS intelligence surfaces.
    @Published private(set) var conversationOSEnabled: Bool = true
    /// Gates AI-generated summaries on spaces, groups, and threads.
    @Published private(set) var conversationSummariesEnabled: Bool = true
    /// Gates the "Catch Me Up" recap surface for unread messages.
    @Published private(set) var catchUpRecapsEnabled: Bool = true
    /// Gates semantic topic clustering (non-chronological grouping).
    @Published private(set) var topicClusteringEnabled: Bool = true
    /// Gates action item, decision, and blocker extraction from threads.
    @Published private(set) var actionExtractionEnabled: Bool = true
    /// Gates organizational memory queries and persistence.
    @Published private(set) var organizationalMemoryEnabled: Bool = true
    /// Gates role-aware personalized summaries.
    @Published private(set) var personalizedInsightsEnabled: Bool = true
    /// Gates ambient intelligence banners and contextual chips.
    @Published private(set) var ambientConversationIntelligenceEnabled: Bool = true
    /// Gates Liquid Glass rendering for Conversation OS surfaces.
    @Published private(set) var conversationOSLiquidGlassEnabled: Bool = true
    /// Enables debug telemetry for Conversation OS (non-production).
    @Published private(set) var conversationOSDebugTelemetryEnabled: Bool = false
    /// Enforces sensitive-space restrictions (prayer rooms, leadership rooms, admin channels).
    @Published private(set) var conversationOSSensitiveSpaceRestrictionsEnabled: Bool = true
    /// Gates the Berean-specific conversational OS integration layer.
    @Published private(set) var bereanConversationalOSEnabled: Bool = true
    /// Gates the compact Liquid Glass Berean composer.
    @Published private(set) var bereanLiquidGlassComposerEnabled: Bool = true
    /// Gates ambient recap capsules in supported conversation surfaces.
    @Published private(set) var contextualRecapCapsulesEnabled: Bool = true
    /// Gates unresolved discussion extraction and surfacing.
    @Published private(set) var unresolvedDiscussionTrackingEnabled: Bool = true
    /// Gates semantic topic clustering beyond the base Conversation OS flag.
    @Published private(set) var semanticTopicClusteringEnabled: Bool = true
    /// Gates prayer-aware composer affordances that are fully local and UI-only.
    @Published private(set) var prayerAwareComposerEnabled: Bool = true
    /// Gates Selah-specific Conversation OS intelligence.
    @Published private(set) var selahConversationIntelligenceEnabled: Bool = true

    // MARK: - System 44: Messaging OS
    /// Master switch for all Messaging OS surfaces and trust-aware features.
    @Published private(set) var amenMessagingOSEnabled: Bool = true
    /// Gates trust-aware inbox sections (Trusted / Requests / Community / Unknown / Flagged).
    @Published private(set) var trustAwareInboxEnabled: Bool = true
    /// Gates the message request flow (accept, reply-once, mute, block, report).
    @Published private(set) var messageRequestsEnabled: Bool = true
    /// Gates the privacy pill shown in every chat header (security + AI + disappearing state).
    @Published private(set) var messagingPrivacyPillEnabled: Bool = true
    /// Gates AI-powered per-conversation summaries and missed-message recaps.
    @Published private(set) var aiMessagingSummariesEnabled: Bool = true
    /// Gates the per-chat AI consent toggle (On / Ask Every Time / Off).
    @Published private(set) var aiPerChatConsentEnabled: Bool = true
    /// Gates extraction of action items, decisions, and follow-ups from chat threads.
    @Published private(set) var messagingActionExtractionEnabled: Bool = true
    /// Gates voice note transcription and AI-generated summary.
    @Published private(set) var voiceNoteTranscriptionEnabled: Bool = true
    /// Gates in-thread message translation (member-only, consent-gated).
    @Published private(set) var messageTranslationEnabled: Bool = true
    /// Gates the "suggest calmer wording" soft nudge shown before send.
    @Published private(set) var safeWordingSuggestionsEnabled: Bool = true
    /// Gates the scam/manipulation pre-send risk warning flow.
    @Published private(set) var messagingRiskDetectionEnabled: Bool = true
    /// Gates semantic full-text search across message history.
    @Published private(set) var semanticMessageSearchEnabled: Bool = true
    /// Gates biometric/passcode chat lock per conversation (LocalAuthentication).
    @Published private(set) var chatLockEnabled: Bool = true
    /// Gates disappearing messages with configurable timer per chat.
    @Published private(set) var disappearingMessagesEnabled: Bool = true
    /// Gates structured tabs for group/community spaces (Announcements, Discussion, Prayer, etc.).
    @Published private(set) var groupContextTabsEnabled: Bool = true

    // MARK: - Social Safety OS (Phase 2–13)
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
    @Published private(set) var bereanContextBridgeEnabled: Bool = true
    @Published private(set) var bereanSafetyClassifierEnabled: Bool = true
    @Published private(set) var bereanLiquidGlassContextActionsEnabled: Bool = true
    @Published private(set) var bereanSourceGroundingEnabled: Bool = true
    @Published private(set) var bereanFollowUpsEnabled: Bool = true
    @Published private(set) var bereanCommentaryCompareEnabled: Bool = true
    @Published private(set) var bereanTheologicalLensEnabled: Bool = true
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
    @Published private(set) var bereanHelperModelEnabled: Bool = true
    /// Gates prompt simplification (Flow 2).
    @Published private(set) var bereanHelperPromptSimplifyEnabled: Bool = true
    /// Gates link summarization (Flow 3).
    @Published private(set) var bereanHelperLinkSummaryEnabled: Bool = true
    /// Gates external/public context (Flow 4).
    @Published private(set) var bereanHelperExternalContextEnabled: Bool = true
    /// Gates study outline generation.
    @Published private(set) var bereanHelperStudyOutlineEnabled: Bool = true
    /// Gates extract-themes pill for links.
    @Published private(set) var bereanHelperExtractThemesEnabled: Bool = true
    /// Kill switch: false removes the "AI-assisted" provenance chip from all answers.
    @Published private(set) var bereanHelperProvenanceChipsEnabled: Bool = true

    // MARK: - Profile V2
    @Published private(set) var profileV2Enabled: Bool = true
    @Published private(set) var profileMediaGridEnabled: Bool = true
    @Published private(set) var pinnedContentEnabled: Bool = true
    @Published private(set) var creatorHighlightsEnabled: Bool = true

    // MARK: - System 28: Feed Intelligence OS
    /// Master kill switch for Guide My Feed and all feed personalization features.
    @Published private(set) var feedIntelligenceEnabled: Bool = true
    /// Gates the Guide My Feed composer chip and GuideMyFeedSheet.
    @Published private(set) var guideMyFeedEnabled: Bool = true
    /// When true, uses the backend-driven FeedIntelligenceWhyThisPostSheet.
    @Published private(set) var whyThisPostBackendEnabled: Bool = true
    /// When true, feed modes (Berean, Worship, etc.) appear in FeedIntelligenceSettingsView.
    @Published private(set) var feedModesEnabled: Bool = true

    // MARK: - System 29: Liquid Glass Intelligence Layer
    /// Master switch for all Liquid Glass intelligence features.
    @Published private(set) var liquidGlassSystemEnabled: Bool = true
    /// Enables AmenPresencePillStack — contextual AI action pills (max 3).
    @Published private(set) var liquidGlassPresencePillsEnabled: Bool = true
    /// Enables dotted underlines on high-confidence semantic terms in posts/notes.
    @Published private(set) var semanticUnderlineEnabled: Bool = true
    /// Enables the inline definition popover when a semantic term is tapped.
    @Published private(set) var inlineDefinitionPopoverEnabled: Bool = true
    /// Enables server-driven smart action detection via detectSmartActions CF.
    @Published private(set) var smartActionDetectionEnabled: Bool = true
    /// Enables Pulse awareness — UI adaptation based on interaction signals.
    @Published private(set) var pulseAwarenessEnabled: Bool = true
    /// Enables saving semantic insights as knowledge threads.
    @Published private(set) var knowledgeThreadsEnabled: Bool = true
    /// Enables "Save to Selah" from inline definition popover.
    @Published private(set) var selahSemanticSaveEnabled: Bool = true
    /// Enables AI semantic actions inside Church Notes toolbar.
    @Published private(set) var churchNotesSemanticActionsEnabled: Bool = true
    /// Enables Liquid Glass chrome for media player controls.
    @Published private(set) var mediaChromeLiquidGlassEnabled: Bool = true
    /// Enables Pulse-driven smart action pills inside the post composer.
    @Published private(set) var composerPresenceActionsEnabled: Bool = true
    /// Enables the Liquid Glass bottom bar (replaces solid bar when true).
    @Published private(set) var bottomBarLiquidGlassEnabled: Bool = true
    /// Replaces the center capsule of AMENTabBar with AMENPillNav (amenGold active tint, icon-only).
    @Published private(set) var liquidGlassPillNav: Bool = true
    /// Presents AMENImmersiveMediaViewer (with action rail + action sheet) instead of FullscreenMediaViewer.
    @Published private(set) var liquidGlassMediaViewer: Bool = true
    /// Shows AMENCategoryChips in media and profile filter contexts.
    @Published private(set) var liquidGlassCategoryChips: Bool = true

    // MARK: - Cross-cutting
    @Published private(set) var analyticsEnabled: Bool = true
    @Published private(set) var performanceTelemetryEnabled: Bool = true

    // MARK: - Amen Living Hero System
    @Published private(set) var ambientSpatialHeroEnabled: Bool = true
    @Published private(set) var livingEditorialBannerEnabled: Bool = true
    @Published private(set) var spatialHeroReduceMotionFallbackEnabled: Bool = true
    @Published private(set) var spatialHeroPerformanceTelemetryEnabled: Bool = true
    @Published private(set) var dailyVerseLivingHeroEnabled: Bool = true
    @Published private(set) var dailyDigestLivingHeroEnabled: Bool = true
    @Published private(set) var discoverLivingHeroEnabled: Bool = true
    @Published private(set) var selahLivingHeroEnabled: Bool = true
    @Published private(set) var bereanPulseLivingHeroEnabled: Bool = true
    @Published private(set) var churchProfileLivingHeroEnabled: Bool = true
    @Published private(set) var liveEventLivingHeroEnabled: Bool = true
    @Published private(set) var creatorKitLivingHeroEnabled: Bool = true
    
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
    @Published private(set) var voicePrayerCommentsEnabled: Bool = true
    /// Gates the "Share Testimony" voice button on testimony posts.
    @Published private(set) var voiceTestimonyCommentsEnabled: Bool = true
    /// When true, a transcript must exist before a voice comment can publish.
    @Published private(set) var voiceCommentTranscriptRequired: Bool = true
    /// Enables AI-generated safety summaries on published voice comments.
    @Published private(set) var voiceCommentSummaryEnabled: Bool = true
    /// Enables the held_for_review moderation queue for voice comments.
    @Published private(set) var voiceCommentReviewQueueEnabled: Bool = true
    /// Enables the Prayer Circle visibility option in the visibility picker.
    @Published private(set) var voiceCommentPrayerCircleVisibilityEnabled: Bool = true

    // MARK: - Amen AI Creative Intelligence Layer
    @Published private(set) var amenRealtimeVoiceEnabled: Bool = true
    @Published private(set) var amenLiveCaptionsEnabled: Bool = true
    @Published private(set) var amenTranslationEnabled: Bool = true
    @Published private(set) var amenGraphicStudioEnabled: Bool = true
    @Published private(set) var amenCreatorKitEnabled: Bool = true
    @Published private(set) var amenAgentWorkflowsEnabled: Bool = true
    @Published private(set) var amenExplainEnabled: Bool = true
    @Published private(set) var amenImproveEnabled: Bool = true
    @Published private(set) var amenSummarizeEnabled: Bool = true
    @Published private(set) var amenAIUsageLabelsRequired: Bool = true

    @Published private(set) var bereanRealtimeEnabled: Bool = true
    @Published private(set) var bereanTranslationEnabled: Bool = true
    @Published private(set) var bereanPrayerRoomsEnabled: Bool = true
    @Published private(set) var bereanVoiceAssistantEnabled: Bool = true
    @Published private(set) var bereanSmartNotesEnabled: Bool = true
    @Published private(set) var bereanLiveCaptionsEnabled: Bool = true
    @Published private(set) var bereanRealtimeKillSwitch: Bool = false

    @Published private(set) var amenRealtimeVoiceKillSwitch: Bool = false
    @Published private(set) var amenLiveCaptionsKillSwitch: Bool = false
    @Published private(set) var amenTranslationKillSwitch: Bool = false
    @Published private(set) var amenGraphicGenerationKillSwitch: Bool = false
    @Published private(set) var amenAgentWorkflowKillSwitch: Bool = false
    @Published private(set) var amenExplainKillSwitch: Bool = false

    // MARK: - System 33: Berean Multimodal Intelligence (Voice + Vision)
    /// Master gate: enables all Berean multimodal features (transcription, vision, voice companion).
    @Published private(set) var bereanMultimodalEnabled: Bool = true
    /// Gates Visual Scripture Intelligence (camera OCR + Berean context cards).
    @Published private(set) var bereanVisualScriptureEnabled: Bool = true
    /// When true, transcription uses Apple on-device Speech (SFSpeechRecognizer, no audio upload).
    /// Set false only for languages unsupported on-device — falls back to server-side STT.
    @Published private(set) var bereanOnDeviceTranscriptionEnabled: Bool = true
    /// Gates the voice-first Bible Companion mode (speak → transcript → Berean answer).
    @Published private(set) var bereanVoiceCompanionEnabled: Bool = true
    /// Gates Selah quiet mode — witness-only, Berean never responds.
    @Published private(set) var bereanSelahModeEnabled: Bool = true
    /// Gates the Testimony Integrity Assist flow (grammar/clarity refinements + audience controls).
    @Published private(set) var bereanTestimonyAssistEnabled: Bool = true
    /// Gates the Prayer Safety escalation layer (care tags + resource surfacing + pastoral opt-in).
    @Published private(set) var bereanPrayerSafetyEnabled: Bool = true
    /// Kill switch for all multimodal features — set true to disable everything instantly.
    @Published private(set) var bereanMultimodalKillSwitch: Bool = false
    @Published private(set) var amenImproveKillSwitch: Bool = false
    @Published private(set) var amenSummarizeKillSwitch: Bool = false

    // MARK: - Global AI emergency brake
    /// Remote Config key: amen_global_ai_kill_switch
    /// When true, ALL AI routing is blocked immediately — no fallback, no partial delivery.
    /// Use for detected abuse, model safety incidents, or compliance holds.
    @Published private(set) var amenGlobalAIKillSwitch: Bool = false

    // MARK: - Post-Google I/O 2026 Gemini Evaluation Layer
    @Published private(set) var geminiDirectClientEnabled: Bool = true
    @Published private(set) var geminiClientKillSwitch: Bool = false
    @Published private(set) var geminiEvalLoggingEnabled: Bool = true
    @Published private(set) var geminiDailyVerseReflectionEnabled: Bool = true
    @Published private(set) var geminiChurchNoteTitleSummaryEnabled: Bool = true
    @Published private(set) var geminiSmartMessageSummaryEnabled: Bool = true
    @Published private(set) var geminiCaptionSuggestionsEnabled: Bool = true
    @Published private(set) var geminiMapsGroundedSearchEnabled: Bool = true
    @Published private(set) var geminiFileSearchPilotEnabled: Bool = true
    @Published private(set) var geminiTTSEnabled: Bool = true
    @Published private(set) var geminiImageGenerationPilotEnabled: Bool = true
    @Published private(set) var geminiVideoGenerationPrototypeEnabled: Bool = true
    @Published private(set) var geminiDeepResearchPrototypeEnabled: Bool = true
    @Published private(set) var geminiManagedAgentsPrototypeEnabled: Bool = true
    @Published private(set) var geminiFlashModelName: String = "gemini-3.5-flash"
    @Published private(set) var geminiFlashLiteModelName: String = "gemini-3.5-flash-lite"
    @Published private(set) var geminiDirectClientDailyBudgetMicroUSD: Int = 0
    @Published private(set) var geminiDirectClientTimeoutMs: Int = 4_000

    // MARK: - System 33: Spatial Social OS
    @Published private(set) var spatialHomeEnabled: Bool = true
    @Published private(set) var spatialRoomsEnabled: Bool = true
    @Published private(set) var spatialRoomsServerCreationEnabled: Bool = true
    @Published private(set) var spatialRoomsAIThemeGenerationEnabled: Bool = true
    @Published private(set) var spatialRoomsBackfillEnabled: Bool = true
    @Published private(set) var spatialContextRailEnabled: Bool = true
    @Published private(set) var provenanceTrustPanelEnabled: Bool = true
    @Published private(set) var creatorOSComposerEnabled: Bool = true
    @Published private(set) var truthfulAILabelsEnabled: Bool = true
    @Published private(set) var smartDiscoveryTransparencyEnabled: Bool = true
    @Published private(set) var discoveryWhyShownEnabled: Bool = true
    @Published private(set) var safetyOSEnabled: Bool = true

    // MARK: - System 35: Trust Spine (Phase 1)
    // Master switch for the publish/AI/disclosure trust pipeline introduced
    // in the Spatial Social OS rebuild. Defaults ON — Remote Config can
    // explicitly flip any flag OFF by returning the string "false".
    @Published private(set) var trustSpinePipelineEnabled: Bool = true
    @Published private(set) var aiDisclosureLabelsEnabled: Bool = true
    @Published private(set) var sharedViewingEnabled: Bool = true
    @Published private(set) var spatialMessagesEnabled: Bool = true
    @Published private(set) var publicLikeCountsHidden: Bool = true
    @Published private(set) var amenCreatorOSPremiumEnabled: Bool = true
    @Published private(set) var discoveryTransparencyEnabled: Bool = true

    // MARK: - System 34: Healthy Immersive Media Sessions
    // Master switch: false blocks all immersive media session surfaces instantly.
    // Defaults OFF — Remote Config activates per rollout stage.
    @Published private(set) var healthyImmersiveMediaEnabled: Bool = true
    @Published private(set) var immersiveMediaSessionsEnabled: Bool = true
    @Published private(set) var mediaFiniteSessionsEnabled: Bool = true   // Core anti-doomscroll — ON by default
    @Published private(set) var finiteMediaQueuesEnabled: Bool = true
    @Published private(set) var mediaCompletionReflectionEnabled: Bool = true  // Core anti-doomscroll — ON
    @Published private(set) var mediaCompletionOverlayEnabled: Bool = true
    @Published private(set) var mediaDoomScrollGuardEnabled: Bool = true  // Safety guardrail — ON
    // When true, shouldAutoplayInViewport returns false. Keep ON for safety.
    @Published private(set) var mediaNoDoomScrollGuardrailsEnabled: Bool = true
    @Published private(set) var mediaSessionCheckpointsEnabled: Bool = true   // Core anti-doomscroll — ON
    @Published private(set) var healthyMediaCheckpointsEnabled: Bool = true
    // Off until MediaKeyMomentsRail view ships.
    @Published private(set) var mediaKeyMomentsEnabled: Bool = true
    @Published private(set) var mediaTranscriptEnabled: Bool = true   // VideoTranscriptSheetView exists
    // Off until AmenMediaAIMetadataReviewSheet ships.
    @Published private(set) var mediaAIDraftMetadataEnabled: Bool = true
    @Published private(set) var mediaAIMetadataDraftsEnabled: Bool = true
    @Published private(set) var mediaApprovalFlowEnabled: Bool = true
    // Safety: true = approval required before AI metadata is public. Keep ON.
    @Published private(set) var mediaGeneratedMetadataApprovalRequired: Bool = true
    @Published private(set) var mediaLowBandwidthModeEnabled: Bool = true
    @Published private(set) var mediaSelahAudioModeEnabled: Bool = true
    @Published private(set) var mediaSelahOverlayEnabled: Bool = true
    @Published private(set) var immersivePhotoSessionsEnabled: Bool = true
    @Published private(set) var immersiveVideoSessionsEnabled: Bool = true
    @Published private(set) var communityMediaLayersEnabled: Bool = true
    @Published private(set) var mediaCommunityLayerEnabled: Bool = true
    @Published private(set) var mediaReflectionSheetEnabled: Bool = true  // AmenMediaReflectionSheet exists
    @Published private(set) var hideVanityMetricsDefault: Bool = true
    // Off: autoplay-within-session can create chain if misused. Remote Config activates.
    @Published private(set) var autoplayWithinSessionsEnabled: Bool = true
    @Published private(set) var lateNightPauseEnabled: Bool = true   // Wellbeing — ON
    @Published private(set) var mediaWellbeingControlsEnabled: Bool = true
    // Off until TimestampedCommentComposer ships.
    @Published private(set) var mediaTimestampedCommentsEnabled: Bool = true
    @Published private(set) var mediaSearchEnabled: Bool = true
    @Published private(set) var mediaChurchNotesIntegrationEnabled: Bool = true
    // Off until SaveToReflectionQueueSheet ships.
    @Published private(set) var mediaPrayerQueueEnabled: Bool = true
    @Published private(set) var mediaReflectionQueueEnabled: Bool = true
    @Published private(set) var mediaReportingEnabled: Bool = true   // ReportContentSheet exists
    @Published private(set) var mediaAccessibilityControlsEnabled: Bool = true
    @Published private(set) var mediaHideVanityMetricsEnabled: Bool = true
    @Published private(set) var mediaRankingV2Enabled: Bool = true
    @Published private(set) var mediaLiquidGlassChromeEnabled: Bool = true
    @Published private(set) var mediaProfileLiquidWhiteFlowEnabled: Bool = true

    // MARK: - System 35: Provenance & Authenticity OS
    @Published private(set) var mediaAuthenticityBadgesEnabled: Bool = true
    @Published private(set) var syntheticMediaDetectionEnabled: Bool = true
    @Published private(set) var mediaSyntheticDetectionEnabled: Bool = true
    @Published private(set) var contentCredentialsEnabled: Bool = true
    @Published private(set) var provenanceAuditChainEnabled: Bool = true

    // MARK: - System 36: Messaging Filters & Smart Inbox
    // Apple Mail-style Liquid Glass floating filter tray for the messaging inbox.
    // Defaults are ON; Remote Config can flip any of them OFF as a kill switch.
    @Published private(set) var messagingInboxFiltersEnabled: Bool = true
    @Published private(set) var messagingThreadSearchFiltersEnabled: Bool = true
    @Published private(set) var messagingSmartInboxCountsEnabled: Bool = true

    // MARK: - System 38: Amen Gatherings
    @Published private(set) var gatheringsEnabled: Bool = true
    @Published private(set) var gatheringCreationEnabled: Bool = true
    @Published private(set) var gatheringAccessPassEnabled: Bool = true
    @Published private(set) var gatheringQRShareEnabled: Bool = true
    @Published private(set) var gatheringNFCEnabled: Bool = true
    @Published private(set) var gatheringCalendarEnabled: Bool = true
    @Published private(set) var gatheringGuestListEnabled: Bool = true
    @Published private(set) var gatheringPrayerRequestsEnabled: Bool = true
    @Published private(set) var gatheringUnauthenticatedPreviewEnabled: Bool = true
    @Published private(set) var gatheringUnauthenticatedRsvpEnabled: Bool = true
    @Published private(set) var gatheringHostConsoleEnabled: Bool = true
    @Published private(set) var gatheringMediaEnabled: Bool = true

    // MARK: - System 37: Amen Access Passes
    // QR / NFC / universal link / share-link access system for Spaces, Discussions,
    // Small Groups, Churches, Organizations, Events, Sermon Notes, and Prayer Rooms.
    // All default OFF in production — Remote Config activates per rollout stage.
    @Published private(set) var accessPassesEnabled: Bool = true
    @Published private(set) var accessPassQRGenerationEnabled: Bool = true
    @Published private(set) var accessPassNFCEnabled: Bool = true
    @Published private(set) var accessPassCheckInEnabled: Bool = true
    @Published private(set) var accessPassRoleGatedEnabled: Bool = true
    @Published private(set) var accessPassAdminConsoleEnabled: Bool = true
    /// Kill switch: true blocks direct Join for sensitive spaces (prayer rooms, youth groups).
    @Published private(set) var accessPassSensitiveSpaceDirectJoinBlocked: Bool = false
    @Published private(set) var accessPassAuditLoggingEnabled: Bool = true

    // MARK: - System 39: Amen Integrations Platform
    @Published private(set) var amenIntegrationsEnabled: Bool = true
    @Published private(set) var amenMicrosoftGraphEnabled: Bool = true
    @Published private(set) var amenZoomEnabled: Bool = true
    @Published private(set) var amenSlackEnabled: Bool = true
    @Published private(set) var amenGatheringsEnabled: Bool = true
    @Published private(set) var amenGatheringMeetingLinksEnabled: Bool = true
    @Published private(set) var amenGatheringRemindersEnabled: Bool = true
    @Published private(set) var amenGatheringFollowUpsEnabled: Bool = true
    @Published private(set) var amenGatheringAISuggestionsEnabled: Bool = true
    @Published private(set) var amenIntegrationAdminWorkflowsEnabled: Bool = true
    @Published private(set) var amenIntegrationAuditLoggingEnabled: Bool = true
    /// Kill switch: true disables all integrations platform features instantly via Remote Config.
    @Published private(set) var amenIntegrationsKillSwitch: Bool = false

    // MARK: - System 40: Multi-Tenant Contextual Experiences
    @Published private(set) var contextualExperiencesEnabled: Bool = true
    @Published private(set) var organizationExperiencesEnabled: Bool = true
    @Published private(set) var experienceLiquidGlassEnabled: Bool = true
    @Published private(set) var experienceAdminToolsEnabled: Bool = true
    @Published private(set) var experienceAnalyticsEnabled: Bool = true
    @Published private(set) var experienceMemoriesEnabled: Bool = true
    @Published private(set) var experiencePrayerCampaignsEnabled: Bool = true
    @Published private(set) var experienceSpacesIntegrationEnabled: Bool = true

    // MARK: - System 39: Verification & Trust
    @Published private(set) var verificationCenterEnabled: Bool = true
    @Published private(set) var identityVerificationEnabled: Bool = true
    @Published private(set) var organizationVerificationEnabled: Bool = true
    /// Organization identity verification submission UI (EIN/domain flow).
    @Published private(set) var orgVerificationEnabled: Bool = true
    @Published private(set) var roleVerificationEnabled: Bool = true
    @Published private(set) var creatorVerificationEnabled: Bool = true
    @Published private(set) var publicTrustBadgesEnabled: Bool = true
    @Published private(set) var impersonationReportsEnabled: Bool = true

    // MARK: - Callable Contract Guards (UNDEPLOYED_FEATURE defaults — all false until backend ships)
    // Each flag below protects an iOS httpsCallable() call whose backend function does not yet
    // exist in index.ts.  Set to false by default; Remote Config or a future deploy can flip them on.

    // Berean proxy variants (separate functions not yet in backend)
    @Published private(set) var bereanGenericProxyEnabled: Bool = true
    @Published private(set) var bereanEmbedProxyEnabled: Bool = true
    @Published private(set) var bereanVoiceProxyEnabled: Bool = true
    @Published private(set) var bereanCompassAnalyzeEnabled: Bool = true
    @Published private(set) var bereanShieldAnalyzeEnabled: Bool = true
    @Published private(set) var bereanSermonWeekPlanEnabled: Bool = true
    @Published private(set) var sermonSnapProxyEnabled: Bool = true
    @Published private(set) var smartSuggestionsProxyEnabled: Bool = true
    @Published private(set) var ttsProxyEnabled: Bool = true

    // Studio AI callables (studioGenerateContent, generateStudioImage, exportToPDF,
    // studioJournalPrompt, transcribeAudio, synapticCreate)
    @Published private(set) var studioAICallablesEnabled: Bool = true

    // Trust Spine callables (trueSourceSign, publishPostWithTrustGates, registerAIDisclosure,
    // getAIDisclosureDetails, getPostProvenance, getDiscoveryReasons)
    @Published private(set) var trustSpineCallablesEnabled: Bool = true

    // Shared Viewing Room callables (createSharedViewingRoom, joinSharedViewingRoom,
    // leaveSharedViewingRoom, postAnchoredReply)
    @Published private(set) var sharedViewingRoomCallablesEnabled: Bool = true

    // Universal Link Intelligence callables (generateUniversalLinkNotes, saveUniversalLink)
    @Published private(set) var universalLinkIntelligenceEnabled: Bool = true

    // Covenant message callables (createCovenantPost, createCovenantMessage,
    // deleteCovenantMessage, rsvpCovenantEvent)
    @Published private(set) var covenantMessageCallablesEnabled: Bool = true

    // Church Notes share callables (shareChurchNote, generateChurchNoteShareLink,
    // revokeChurchNoteShare, resolveMusicAttachment)
    @Published private(set) var churchNotesShareCallablesEnabled: Bool = true

    // Premium & subscription callables (getPremiumEntitlement, syncPremiumEntitlement,
    // recordAIUsageAndCheckLimit, cancelAllSubscriptions, createMentorshipSubscription)
    @Published private(set) var premiumCallablesEnabled: Bool = true

    // Auth utility callables (resolveUsernameToEmail)
    @Published private(set) var resolveUsernameToEmailEnabled: Bool = true

    // Security utility callables (getClientIPAddress)
    @Published private(set) var clientIPAddressEnabled: Bool = true

    // Account callables (exportUserData, digestBrain)
    @Published private(set) var accountUtilityCallablesEnabled: Bool = true

    // Notification intelligence callables (generateNotificationText, summarizeNotifications)
    @Published private(set) var notificationIntelligenceCallablesEnabled: Bool = true

    // Prayer & spiritual feature callables (generateArcInsight, generatePrayerRecap,
    // spiritGraph, generateSpiritualTimeline)
    @Published private(set) var prayerSpiritualCallablesEnabled: Bool = true

    // Social graph callables (vibeMatch, testimonyResonanceScore, findSimilarTestimonies,
    // matchPrayerPartners, getScriptureRecommendation)
    @Published private(set) var socialGraphCallablesEnabled: Bool = true

    // Church discovery callables (generateFirstVisitGuide, computeChurchDNA)
    @Published private(set) var churchDiscoveryCallablesEnabled: Bool = true

    // Study guide callables (generateStudyGuide, generateVerseReflection)
    @Published private(set) var studyGuideCallablesEnabled: Bool = true

    // Media moderation callables (moderateMediaContent, escalateModerationAlert,
    // moderateContent)
    @Published private(set) var mediaModerationCallablesEnabled: Bool = true

    // Post analysis callables (analyzeImageSyntheticProbability, analyzeVideoFrameConsistency,
    // detectCommentTension, summarizeCommentThemes, notifyPrayerRoomAnswered,
    // revealGraceDropIdentity)
    @Published private(set) var postAnalysisCallablesEnabled: Bool = true

    // MARK: - System 41: Smart Contextual Prompts
    @Published private(set) var smartContextualPromptsEnabled: Bool = true
    @Published private(set) var smartPromptPrayerNotificationsEnabled: Bool = true
    @Published private(set) var smartPromptChurchUpdatesEnabled: Bool = true
    @Published private(set) var smartPromptBereanContinuationEnabled: Bool = true
    @Published private(set) var smartPromptQuietModeEnabled: Bool = true
    @Published private(set) var smartPromptSelahPauseEnabled: Bool = true
    @Published private(set) var smartPromptSpacesJoinEnabled: Bool = true
    @Published private(set) var smartPromptCreatorInsightsEnabled: Bool = true
    @Published private(set) var smartPromptObservancesEnabled: Bool = true
    @Published private(set) var smartPromptAmbientHeroEnabled: Bool = true

    // Compatibility aliases for the earlier SmartPrompts prototype.
    @Published private(set) var promptPrayerReplyNotificationsEnabled: Bool = true
    @Published private(set) var promptChurchEventRemindersEnabled: Bool = true
    @Published private(set) var promptBereanStudyFollowUpEnabled: Bool = true
    @Published private(set) var promptCommunityInteractionEnabled: Bool = true
    @Published private(set) var promptCreatorTeacherUpdateEnabled: Bool = true
    @Published private(set) var promptContinueReflectionEnabled: Bool = true
    @Published private(set) var promptQuietModeEnabled: Bool = true
    @Published private(set) var promptNeedPrayerEnabled: Bool = true
    @Published private(set) var promptTakeAPauseEnabled: Bool = true

    // MARK: - System 42: Spaces Ambient Intelligence OS
    @Published private(set) var amenSpacesIntelligenceEnabled: Bool = true
    @Published private(set) var persistentMemoryGraphEnabled: Bool = true
    @Published private(set) var collapsibleIntelligenceEnabled: Bool = true
    @Published private(set) var semanticPinningEnabled: Bool = true
    @Published private(set) var catchUpIntelligenceEnabled: Bool = true
    @Published private(set) var ambientAIEnabled: Bool = true
    @Published private(set) var smartSidebarEnabled: Bool = true
    @Published private(set) var emotionalContextEngineEnabled: Bool = false
    @Published private(set) var spiritualContinuityEngineEnabled: Bool = true
    @Published private(set) var intentAwareSearchEnabled: Bool = true
    @Published private(set) var multiThreadBranchingEnabled: Bool = true
    @Published private(set) var presenceAwareUIEnabled: Bool = true

    // MARK: - System 43: Church Notes Context Engine
    @Published private(set) var churchNotesContextEngineEnabled: Bool = true
    /// Gates smart note memory (recurring themes, scripture, prayers, unresolved reflections).
    @Published private(set) var churchNotesSmartMemoryEnabled: Bool = true
    /// Gates the Berean Context Panel bottom sheet (scripture, notes, themes, prayer prompts).
    @Published private(set) var churchNotesBereanContextPanelEnabled: Bool = true
    /// Gates sermon-to-action extraction (personal action, prayer item, reminder, group question).
    @Published private(set) var churchNotesSermonToActionEnabled: Bool = true
    /// Gates the Spiritual Growth Timeline (private recurring themes, answered prayers, journey).
    @Published private(set) var churchNotesGrowthTimelineEnabled: Bool = true
    /// Gates Smart Recap generation after note completion or church attendance.
    @Published private(set) var churchNotesSmartRecapEnabled: Bool = true
    /// Gates group/church intelligence surfaces (top themes, prayer trends, leader action items).
    @Published private(set) var churchNotesGroupIntelligenceEnabled: Bool = true
    /// Gates the /command bar (summarize, prayer, study, translate, action-items, small-group, ask-berean, share).
    @Published private(set) var churchNotesCommandBarEnabled: Bool = true
    /// Gates smart capture classification (sermon slide, whiteboard, scripture, prayer request, quote).
    @Published private(set) var churchNotesSmartCaptureEnabled: Bool = true
    /// Gates AI provenance labels on all context engine outputs (source, confidence, why-suggested).
    @Published private(set) var churchNotesAIProvenanceEnabled: Bool = true
    /// Kill switch: true blocks all context engine AI writes instantly via Remote Config.
    @Published private(set) var churchNotesContextEngineKillSwitch: Bool = false

    // MARK: - System 45: Comms OS (Communication OS Intelligence Layer)
    // Default ON — Remote Config can kill-switch per flag if needed.
    /// Master kill switch for all Comms OS intelligence surfaces.
    @Published private(set) var commsIntelligenceEnabled: Bool = true
    /// Gates smart thread context bar (urgency chips, unresolved, blockers).
    @Published private(set) var commsSmartContextEnabled: Bool = true
    /// Gates personalized catch-up digest surfaces.
    @Published private(set) var commsCatchUpEnabled: Bool = true
    /// Gates server-extracted decisions and SmartFollowUpCard.
    @Published private(set) var commsDecisionsEnabled: Bool = true
    /// Gates async media intelligence jobs and MediaIntelligenceDock.
    @Published private(set) var commsMediaIntelEnabled: Bool = true
    /// Gates GroupPulseCard live intelligence (pulse, blockers, suggested next action).
    @Published private(set) var commsPulseEnabled: Bool = true
    /// Gates universal command palette with NL intent routing.
    @Published private(set) var commsCommandPaletteEnabled: Bool = true
    /// Gates approximate, opt-in, expiring presence indicators.
    @Published private(set) var commsPresenceEnabled: Bool = true
    /// Gates multi-pane communication shell view.
    @Published private(set) var commsMultiPaneEnabled: Bool = true

    // MARK: - System 46: Berean Drive (CarPlay)
    // All CarPlay flags default OFF — requires Apple CarPlay entitlement approval
    // from https://developer.apple.com/contact/request/carplay before enabling.
    // Remote Config activates these after entitlement is provisioned.
    /// Master gate: enables the CarPlay Berean Drive scene delegate and coordinator.
    @Published private(set) var carPlayBereanEnabled: Bool = false
    /// Gates CPNowPlayingTemplate — requires com.apple.developer.carplay-audio entitlement.
    @Published private(set) var carPlayAudioEnabled: Bool = true
    /// Gates CPMessageListItem — requires com.apple.developer.carplay-communication entitlement.
    @Published private(set) var carPlayMessagingEnabled: Bool = true
    /// Gates Apple Maps handoff from church search results. No navigation entitlement required.
    @Published private(set) var carPlayNavigationHandoffEnabled: Bool = true
    /// Kill switch: set true in Remote Config to immediately disable all CarPlay features.
    @Published private(set) var carPlayKillSwitch: Bool = false

    // MARK: - Calm Control + Spiritual Rhythm OS (Phase 1 MVP)

    /// Master kill switch for all Calm Control features.
    @Published private(set) var calmControlEnabled: Bool = true
    /// Privacy/visibility controls (hidden counts, quiet profile, presence).
    @Published private(set) var calmPrivacyControlsEnabled: Bool = true
    /// Feed control features (text-only mode, hide viral, debate filter).
    @Published private(set) var calmFeedControlsEnabled: Bool = true
    /// Spiritual rhythm streaks (scripture, prayer, community, reading).
    @Published private(set) var spiritualRhythmEnabled: Bool = true
    /// Sabbath Mode feature.
    @Published private(set) var sabbathModeEnabled: Bool = true
    /// Daily verse push notification feature.
    @Published private(set) var dailyVersePushEnabled: Bool = true
    /// 7-day inactivity pause notification policy.
    @Published private(set) var inactivityPausePolicyEnabled: Bool = true
    /// Grace-based streak recovery.
    @Published private(set) var streakGraceRecoveryEnabled: Bool = true
    /// Audience layers feature (Phase 2).
    @Published private(set) var audienceLayersEnabled: Bool = true
    /// Anonymous reflection posting (Phase 2).
    @Published private(set) var anonymousReflectionsEnabled: Bool = true
    /// Berean AI verse recommendations (Phase 3).
    @Published private(set) var bereanVerseRecommendationsEnabled: Bool = true

    // MARK: - Community Notes
    @Published private(set) var communityNotesEnabled: Bool = true

    // MARK: - Anonymous-Accountable Mode
    @Published private(set) var anonModeEnabled: Bool = true

    // MARK: - System 47: Discussion Groups — Album-style UI
    /// Master gate for the Apple Music-style group detail + discovery redesign.
    /// Default OFF — Remote Config activates per rollout stage.
    @Published private(set) var discussionAlbumUIEnabled: Bool = true
    /// Gates the "More from this org / category" shelf on the group detail page.
    @Published private(set) var discussionMoreFromOrgShelfEnabled: Bool = true
    /// Gates the discovery home carousel ("Top Picks for You").
    @Published private(set) var discussionDiscoveryHomeEnabled: Bool = true
    /// Gates the find-then-add (save without joining) flow in SmartCommunitySearch.
    @Published private(set) var discussionFindThenAddEnabled: Bool = true

    // MARK: - System — Org Platform
    /// Master gate for the organization identity platform (school/university/nonprofit listings, claim flow).
    @Published private(set) var orgPlatformEnabled: Bool = true
    /// Gates bulk seed import jobs (NCES CCD, IRS BMF, IPEDS).
    @Published private(set) var orgSeedEnabled: Bool = true
    /// Gates the organization claim flow UI and submitOrgClaim Cloud Function.
    @Published private(set) var orgClaimFlowEnabled: Bool = true
    /// Gates org subscription / billing surfaces (Stripe checkout, plan picker).
    @Published private(set) var orgSubscriptionsEnabled: Bool = true

    // MARK: - Master Run Feature Flags (all default OFF)
    /// Phase 1: Find a Church map+search experience (master-run A8).
    @Published private(set) var findAChurch: Bool = false
    /// Phase 2: Liquid Glass migration for Posts surfaces (master-run A8).
    @Published private(set) var postsLiquidGlass: Bool = false
    /// Phase 3: "Why you're seeing this" provenance disclosure (master-run A8).
    @Published private(set) var whySeeingThis: Bool = false
    /// Phase 5: Selah Stories free composer tier (master-run A8).
    @Published private(set) var selahStories: Bool = false
    /// Phase 5: Selah Stories premium AI features — subscription-gated (master-run A8).
    @Published private(set) var selahStoriesPremiumAI: Bool = false

    private init() {
        applyUITestOverrides()
        let config = RemoteConfig.remoteConfig()
        config.setDefaults(buildDefaults())
        // Activate cached values only — no network hit.
        // AMENAPPApp.setupRemoteConfig() is the sole Remote Config fetch owner.
        Task { @MainActor [weak self] in
            guard let self, (try? await config.activate()) == true else { return }
            self.applyRemoteConfig(config)
            self.applyManualObjectHubOverrides()
        }
        // Re-apply when this session's central fetch completes (covers first-launch cold cache).
        Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .remoteConfigActivated) {
                guard let self else { break }
                let rc = RemoteConfig.remoteConfig()
                self.applyRemoteConfig(rc)
                self.applyManualObjectHubOverrides()
            }
        }
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
                applyManualObjectHubOverrides()
            }
        } catch {
            // Non-fatal — local defaults above remain in effect
            dlog("[AMENFeatureFlags] Remote config fetch failed, using defaults: \(error)")
        }
    }

    private func buildDefaults() -> [String: NSObject] {
        #if DEBUG
        let objectHubDefault = true as NSObject
        #else
        let objectHubDefault = false as NSObject
        #endif

        return [
            // Moderation
            "moderation_v2_enabled": true as NSObject,
            "image_moderation_enabled": true as NSObject,
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
            "berean_multimodal_enabled": true as NSObject,
            "berean_visual_scripture_enabled": true as NSObject,
            "berean_on_device_transcription_enabled": true as NSObject,
            "berean_voice_companion_enabled": true as NSObject,
            "berean_selah_mode_enabled": true as NSObject,
            "berean_testimony_assist_enabled": true as NSObject,
            "berean_prayer_safety_enabled": true as NSObject,

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
            "creator_spaces_enabled": true as NSObject,
            "presence_posts_enabled": true as NSObject,
            "media_authenticity_enabled": true as NSObject,

            // Knowledge Graph
            "knowledge_graph_enabled": true as NSObject,
            "knowledge_graph_related_content_enabled": true as NSObject,
            "knowledge_graph_semantic_search_enabled": true as NSObject,

            // Action Threads
            "action_threads_enabled": true as NSObject,
            "action_suggestions_enabled": true as NSObject,
            "care_followups_enabled": true as NSObject,

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

            // Social Context & UX Enhancements
            "mutual_context_row_enabled": true as NSObject,
            "presence_intelligence_enabled": true as NSObject,
            "message_request_intelligence_enabled": true as NSObject,
            "trust_explainer_enabled": true as NSObject,
            "post_divider_enabled": true as NSObject,
            "feed_view_mode_switcher_enabled": true as NSObject,
            "media_filter_pills_enabled": true as NSObject,
            "media_detail_view_enabled": true as NSObject,
            "media_viewer_floating_engagement_pill_enabled": true as NSObject,
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
            "accessibility_intelligence_enabled": true as NSObject,
            "meaning_aware_translation_enabled": true as NSObject,
            "natural_mode_enabled": true as NSObject,
            "contextual_mode_enabled": true as NSObject,
            "readability_layer_enabled": true as NSObject,
            "content_difficulty_scoring": true as NSObject,
            "audio_narration_enabled": true as NSObject,
            "context_bridge_enabled": true as NSObject,
            "adaptive_accessibility_enabled": true as NSObject,
            "conversation_bridge_enabled": true as NSObject,
            "smart_translation_visibility_enabled": true as NSObject,
            "side_by_side_translation_enabled": true as NSObject,
            "per_language_auto_translate_enabled": true as NSObject,
            "creation_language_enabled": true as NSObject,
            "adaptive_translation_enabled": true as NSObject,

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
            "church_notes_audio_capture_enabled": true as NSObject,
            "church_notes_photo_ocr_enabled": true as NSObject,
            "church_notes_video_capture_enabled": true as NSObject,
            "church_notes_ai_draft_review_enabled": true as NSObject,
            "church_notes_study_guide_enabled": true as NSObject,
            "church_notes_prayer_prompts_enabled": true as NSObject,
            "church_notes_intelligence_enabled": true as NSObject,
            "sermon_audio_capture_enabled": true as NSObject,
            "sermon_video_capture_enabled": true as NSObject,
            "church_photo_ocr_capture_enabled": true as NSObject,
            "church_notes_translation_enabled": true as NSObject,
            "church_notes_collaboration_enabled": true as NSObject,
            "sermon_summary_generation_enabled": true as NSObject,
            "scripture_detection_enabled": true as NSObject,
            "sermon_action_extraction_enabled": true as NSObject,
            "sermon_clip_suggestion_enabled": true as NSObject,
            "church_notes_study_guide_generation_enabled": true as NSObject,
            "church_notes_processing_kill_switch": false as NSObject,
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

            // Berean Pulse
            "berean_pulse_enabled": true as NSObject,

            // Ambient Glow Intelligence Layer
            "ambient_glow_enabled": true as NSObject,
            "ambient_glow_authentication_enabled": true as NSObject,
            "ambient_glow_berean_enabled": true as NSObject,
            "ambient_glow_selah_enabled": true as NSObject,
            "ambient_glow_prayer_enabled": true as NSObject,
            "ambient_glow_media_enabled": true as NSObject,
            "ambient_glow_feed_enabled": false as NSObject,

            // Amen Living Hero System
            "ambient_spatial_hero_enabled": true as NSObject,
            "living_editorial_banner_enabled": true as NSObject,
            "spatial_hero_reduce_motion_fallback_enabled": true as NSObject,
            "spatial_hero_performance_telemetry_enabled": true as NSObject,
            "daily_verse_living_hero_enabled": true as NSObject,
            "daily_digest_living_hero_enabled": true as NSObject,
            "discover_living_hero_enabled": true as NSObject,
            "selah_living_hero_enabled": true as NSObject,
            "berean_pulse_living_hero_enabled": true as NSObject,
            "church_profile_living_hero_enabled": true as NSObject,
            "live_event_living_hero_enabled": true as NSObject,
            "creator_kit_living_hero_enabled": true as NSObject,

            // Community Hubs & Object Intelligence
            "community_hubs_enabled": objectHubDefault,
            "community_object_matching_enabled": objectHubDefault,
            "lyric_detection_enabled": objectHubDefault,
            "object_hub_view_enabled": objectHubDefault,
            "object_hub_inline_pill_enabled": objectHubDefault,
            "object_hub_inline_cluster_enabled": objectHubDefault,

            // Communities / Threads-Style Feeds
            "ark_communities_enabled": true as NSObject,
            "covenant_communities_enabled": true as NSObject,
            "unified_feeds_switcher_enabled": true as NSObject,
            "saved_communities_enabled": true as NSObject,
            "view_in_feed_enabled": true as NSObject,

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
            "per_media_captions_enabled": false as NSObject,
            "per_media_caption_education_enabled": false as NSObject,
            "per_media_caption_moderation_enabled": true as NSObject,
            "per_media_caption_alt_text_enabled": true as NSObject,
            "per_media_caption_scripture_refs_enabled": true as NSObject,
            "per_media_caption_incremental_moderation_enabled": true as NSObject,

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
            "banner_rail_enabled": false as NSObject,
            "reply_preview_rotation_enabled": false as NSObject,

            // Messaging Micro Animations
            "messaging_liquid_glass_animations_enabled": true as NSObject,
            "messaging_typing_indicator_enabled": true as NSObject,
            "messaging_floating_header_prototype_enabled": true as NSObject,
            "messaging_liquid_glass_context_menu_enabled": true as NSObject,
            "messaging_liquid_glass_attachment_menu_enabled": true as NSObject,
            "messaging_smart_composer_enabled": true as NSObject,
            "messaging_attachment_menu_smart_actions_enabled": true as NSObject,
            "messaging_smart_pills_enabled": true as NSObject,
            "messaging_translation_enabled": true as NSObject,
            "messaging_cross_surface_actions_enabled": true as NSObject,
            "messaging_safety_nudges_enabled": true as NSObject,
            "messaging_approval_cards_enabled": true as NSObject,
            "messaging_catch_up_enabled": true as NSObject,
            "messaging_voice_intelligence_enabled": true as NSObject,
            "messaging_media_intelligence_enabled": true as NSObject,
            "messaging_presence_polish_enabled": true as NSObject,

            // Amen Smart Message Intelligence
            "smart_message_intelligence_enabled": true as NSObject,
            "smart_event_detection_enabled": true as NSObject,
            "prayer_intelligence_enabled": true as NSObject,
            "discussion_summaries_enabled": true as NSObject,
            "contextual_berean_actions_enabled": true as NSObject,
            "topic_extraction_enabled": true as NSObject,
            "semantic_search_enabled": true as NSObject,
            "study_mode_enabled": true as NSObject,
            "voice_intelligence_enabled": true as NSObject,
            "knowledge_graph_memory_enabled": true as NSObject,

            // Smart Liquid Glass Command Layer
            "smart_command_layer_enabled": true as NSObject,
            "smart_command_layer_home_enabled": true as NSObject,
            "smart_command_layer_messages_enabled": true as NSObject,
            "smart_command_layer_berean_enabled": true as NSObject,
            "smart_command_layer_church_notes_enabled": true as NSObject,
            "smart_command_layer_spaces_enabled": true as NSObject,
            "smart_command_layer_create_post_enabled": true as NSObject,
            "smart_command_layer_events_enabled": true as NSObject,
            "smart_command_layer_media_enabled": true as NSObject,

            // Smart Account Resume
            "smart_account_resume_enabled": true as NSObject,
            "smart_account_resume_auto_continue_enabled": true as NSObject,
            "smart_account_resume_offline_retry_enabled": true as NSObject,

            // AI Usage Labels
            "ai_usage_label_pill_enabled": true as NSObject,

            // System 27: Berean Grok Helper Pipeline
            "berean_helper_model_enabled": true as NSObject,
            "berean_helper_prompt_simplify_enabled": true as NSObject,
            "berean_helper_link_summary_enabled": true as NSObject,
            "berean_helper_external_context_enabled": true as NSObject,
            "berean_helper_study_outline_enabled": true as NSObject,
            "berean_helper_extract_themes_enabled": true as NSObject,
            "berean_helper_provenance_chips_enabled": true as NSObject,

            // System 28: Feed Intelligence OS
            "feed_intelligence_enabled": true as NSObject,
            "guide_my_feed_enabled": true as NSObject,
            "why_this_post_backend_enabled": true as NSObject,
            "feed_modes_enabled": true as NSObject,

            // System 29: Liquid Glass Intelligence Layer
            "liquid_glass_system_enabled": true as NSObject,
            "liquid_glass_presence_pills_enabled": true as NSObject,
            "semantic_underline_enabled": true as NSObject,
            "inline_definition_popover_enabled": true as NSObject,
            "smart_action_detection_enabled": true as NSObject,
            "pulse_awareness_enabled": true as NSObject,
            "knowledge_threads_enabled": true as NSObject,
            "selah_semantic_save_enabled": true as NSObject,
            "church_notes_semantic_actions_enabled": true as NSObject,
            "media_chrome_liquid_glass_enabled": true as NSObject,
            "composer_presence_actions_enabled": true as NSObject,
            "bottom_bar_liquid_glass_enabled": true as NSObject,
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

            // System 31: Voice Prayer & Testimony Comments
            "voice_prayer_comments_enabled": true as NSObject,
            "voice_testimony_comments_enabled": true as NSObject,
            "voice_comment_transcript_required": true as NSObject,
            "voice_comment_summary_enabled": true as NSObject,
            "voice_comment_review_queue_enabled": true as NSObject,
            "voice_comment_prayer_circle_visibility_enabled": true as NSObject,

            // Amen AI Creative Intelligence Layer
            "amen_realtime_voice_enabled": true as NSObject,
            "amen_live_captions_enabled": true as NSObject,
            "amen_translation_enabled": true as NSObject,
            "amen_graphic_studio_enabled": true as NSObject,
            "amen_creator_kit_enabled": true as NSObject,
            "amen_agent_workflows_enabled": true as NSObject,
            "amen_explain_enabled": true as NSObject,
            "amen_improve_enabled": true as NSObject,
            "amen_summarize_enabled": true as NSObject,
            "amen_ai_usage_labels_required": true as NSObject,
            "berean_realtime_enabled": true as NSObject,
            "berean_translation_enabled": true as NSObject,
            "berean_prayer_rooms_enabled": true as NSObject,
            "berean_voice_assistant_enabled": true as NSObject,
            "berean_smart_notes_enabled": true as NSObject,
            "berean_live_captions_enabled": true as NSObject,
            "berean_realtime_kill_switch": false as NSObject,
            "amen_realtime_voice_kill_switch": false as NSObject,
            "amen_live_captions_kill_switch": false as NSObject,
            "amen_translation_kill_switch": false as NSObject,
            "amen_graphic_generation_kill_switch": false as NSObject,
            "amen_agent_workflow_kill_switch": false as NSObject,
            "amen_explain_kill_switch": false as NSObject,
            "amen_improve_kill_switch": false as NSObject,
            "amen_summarize_kill_switch": false as NSObject,

            // Post-Google I/O 2026 Gemini Evaluation Layer
            "gemini_direct_client_enabled": true as NSObject,
            "gemini_client_kill_switch": false as NSObject,
            "gemini_eval_logging_enabled": true as NSObject,
            "gemini_daily_verse_reflection_enabled": true as NSObject,
            "gemini_church_note_title_summary_enabled": true as NSObject,
            "gemini_smart_message_summary_enabled": true as NSObject,
            "gemini_caption_suggestions_enabled": true as NSObject,
            "gemini_maps_grounded_search_enabled": true as NSObject,
            "gemini_file_search_pilot_enabled": true as NSObject,
            "gemini_tts_enabled": true as NSObject,
            "gemini_image_generation_pilot_enabled": true as NSObject,
            "gemini_video_generation_prototype_enabled": true as NSObject,
            "gemini_deep_research_prototype_enabled": true as NSObject,
            "gemini_managed_agents_prototype_enabled": true as NSObject,
            "gemini_flash_model_name": "gemini-3.5-flash" as NSObject,
            "gemini_flash_lite_model_name": "gemini-3.5-flash-lite" as NSObject,
            "gemini_direct_client_daily_budget_micro_usd": 0 as NSObject,
            "gemini_direct_client_timeout_ms": 4000 as NSObject,

            // Conversation OS Intelligence Layer
            "conversation_os_enabled": true as NSObject,
            "conversation_summaries_enabled": false as NSObject,
            "catch_up_recaps_enabled": false as NSObject,
            "topic_clustering_enabled": false as NSObject,
            "action_extraction_enabled": false as NSObject,
            "organizational_memory_enabled": false as NSObject,
            "personalized_insights_enabled": false as NSObject,
            "ambient_conversation_intelligence_enabled": false as NSObject,
            "conversation_os_liquid_glass_enabled": true as NSObject,
            "conversation_os_debug_telemetry_enabled": false as NSObject,
            "conversation_os_sensitive_space_restrictions_enabled": true as NSObject,
            "berean_conversational_os_enabled": true as NSObject,
            "berean_liquid_glass_composer_enabled": true as NSObject,
            "contextual_recap_capsules_enabled": false as NSObject,
            "unresolved_discussion_tracking_enabled": false as NSObject,
            "semantic_topic_clustering_enabled": false as NSObject,
            "prayer_aware_composer_enabled": true as NSObject,
            "selah_conversation_intelligence_enabled": false as NSObject,

            // System 33: Spatial Social OS
            "spatial_home_enabled": true as NSObject,
            "spatial_rooms_enabled": true as NSObject,
            "spatial_rooms_server_creation_enabled": true as NSObject,
            "spatial_rooms_ai_theme_generation_enabled": true as NSObject,
            "spatial_rooms_backfill_enabled": true as NSObject,
            "spatial_context_rail_enabled": true as NSObject,
            "provenance_trust_panel_enabled": true as NSObject,
            "creator_os_composer_enabled": true as NSObject,
            "truthful_ai_labels_enabled": true as NSObject,
            "smart_discovery_transparency_enabled": true as NSObject,
            "discovery_why_shown_enabled": true as NSObject,
            "safety_os_enabled": true as NSObject,

            // System 34: Healthy Immersive Media Sessions
            "healthy_immersive_media_enabled": true as NSObject,
            "media_finite_sessions_enabled": true as NSObject,
            "media_completion_reflection_enabled": true as NSObject,
            "media_doom_scroll_guard_enabled": true as NSObject,
            "media_session_checkpoints_enabled": true as NSObject,
            "media_key_moments_enabled": true as NSObject,
            "media_transcript_enabled": true as NSObject,
            "media_ai_draft_metadata_enabled": true as NSObject,
            "media_approval_flow_enabled": true as NSObject,
            "media_selah_audio_mode_enabled": true as NSObject,
            "media_timestamped_comments_enabled": true as NSObject,
            "media_search_enabled": true as NSObject,
            "media_church_notes_integration_enabled": true as NSObject,
            "media_prayer_queue_enabled": true as NSObject,
            "media_reflection_queue_enabled": true as NSObject,
            "media_low_bandwidth_mode_enabled": true as NSObject,
            "media_reporting_enabled": true as NSObject,
            "media_accessibility_controls_enabled": true as NSObject,
            "media_ranking_v2_enabled": true as NSObject,
            "media_hide_vanity_metrics_enabled": true as NSObject,

            // System 35: Provenance & Authenticity OS
            "media_authenticity_badges_enabled": true as NSObject,
            "synthetic_media_detection_enabled": true as NSObject,
            "content_credentials_enabled": true as NSObject,
            "provenance_audit_chain_enabled": true as NSObject,

            // System 36: Messaging Filters & Smart Inbox
            "messaging_inbox_filters_enabled": true as NSObject,
            "messaging_thread_search_filters_enabled": true as NSObject,
            "messaging_smart_inbox_counts_enabled": true as NSObject,

            // System 37: Amen Access Passes
            "access_passes_enabled": true as NSObject,
            "access_pass_qr_generation_enabled": true as NSObject,
            "access_pass_nfc_enabled": true as NSObject,
            "access_pass_check_in_enabled": true as NSObject,
            "access_pass_role_gated_enabled": true as NSObject,
            "access_pass_admin_console_enabled": true as NSObject,
            "access_pass_sensitive_space_direct_join_blocked": false as NSObject,
            "access_pass_audit_logging_enabled": true as NSObject,

            // System 39: Amen Integrations Platform (all false by default)
            "amen_integrations_enabled": false as NSObject,
            "amen_microsoft_graph_enabled": false as NSObject,
            "amen_zoom_enabled": false as NSObject,
            "amen_slack_enabled": false as NSObject,
            "amen_gatherings_enabled": false as NSObject,
            "amen_gathering_meeting_links_enabled": false as NSObject,
            "amen_gathering_reminders_enabled": false as NSObject,
            "amen_gathering_follow_ups_enabled": false as NSObject,
            "amen_gathering_ai_suggestions_enabled": false as NSObject,
            "amen_integration_admin_workflows_enabled": false as NSObject,
            "amen_integration_audit_logging_enabled": false as NSObject,
            "amen_integrations_kill_switch": false as NSObject,

            // System 40: Multi-Tenant Contextual Experiences
            "contextual_experiences_enabled": false as NSObject,
            "organization_experiences_enabled": false as NSObject,
            "experience_liquid_glass_enabled": false as NSObject,
            "experience_admin_tools_enabled": false as NSObject,
            "experience_analytics_enabled": false as NSObject,
            "experience_memories_enabled": false as NSObject,
            "experience_prayer_campaigns_enabled": false as NSObject,
            "experience_spaces_integration_enabled": false as NSObject,

            // System 39: Verification & Trust
            "verification_center_enabled": true as NSObject,
            "identity_verification_enabled": true as NSObject,
            "organization_verification_enabled": true as NSObject,
            // org_verification_enabled gates the EIN/domain submission UI.
            // Default OFF until submitOrgVerificationRequest CF is deployed.
            "org_verification_enabled": false as NSObject,
            "role_verification_enabled": true as NSObject,
            "creator_verification_enabled": true as NSObject,
            "public_trust_badges_enabled": true as NSObject,
            "impersonation_reports_enabled": true as NSObject,

            // System 38: Amen Gatherings
            "gatherings_enabled": true as NSObject,
            "gathering_creation_enabled": true as NSObject,
            "gathering_access_pass_enabled": true as NSObject,
            "gathering_qr_share_enabled": true as NSObject,
            "gathering_nfc_enabled": true as NSObject,
            "gathering_calendar_enabled": true as NSObject,
            "gathering_guest_list_enabled": true as NSObject,
            "gathering_prayer_requests_enabled": true as NSObject,
            "gathering_unauthenticated_preview_enabled": true as NSObject,
            "gathering_unauthenticated_rsvp_enabled": true as NSObject,
            "gathering_host_console_enabled": true as NSObject,
            "gathering_media_enabled": true as NSObject,

            // Smart Community Search / Ask Amen. UI defaults OFF until callable deploy.
            "smart_community_search_enabled": false as NSObject,
            "smart_community_search_external_places_enabled": false as NSObject,
            "smart_community_search_ai_enabled": false as NSObject,

            // Callable Contract Guards — all false until backend functions are deployed
            "berean_generic_proxy_enabled": true as NSObject,
            "berean_embed_proxy_enabled": true as NSObject,
            "berean_voice_proxy_enabled": true as NSObject,
            "berean_compass_analyze_enabled": true as NSObject,
            "berean_shield_analyze_enabled": true as NSObject,
            "berean_sermon_week_plan_enabled": true as NSObject,
            "sermon_snap_proxy_enabled": true as NSObject,
            "smart_suggestions_proxy_enabled": true as NSObject,
            "tts_proxy_enabled": true as NSObject,
            "studio_ai_callables_enabled": true as NSObject,
            "trust_spine_callables_enabled": true as NSObject,
            "shared_viewing_room_callables_enabled": true as NSObject,
            "universal_link_intelligence_enabled": true as NSObject,
            "covenant_message_callables_enabled": true as NSObject,
            "church_notes_share_callables_enabled": true as NSObject,
            "premium_callables_enabled": true as NSObject,
            "resolve_username_to_email_enabled": true as NSObject,
            "client_ip_address_enabled": true as NSObject,
            "account_utility_callables_enabled": true as NSObject,
            "notification_intelligence_callables_enabled": true as NSObject,
            "prayer_spiritual_callables_enabled": true as NSObject,
            "social_graph_callables_enabled": true as NSObject,
            "church_discovery_callables_enabled": true as NSObject,
            "nearby_people_discovery_enabled": false as NSObject,  // Off by default — privacy gate
            "study_guide_callables_enabled": true as NSObject,
            "media_moderation_callables_enabled": true as NSObject,
            "post_analysis_callables_enabled": true as NSObject,

            // System 41: Smart Contextual Prompts (all false — Remote Config activates)
            "smart_contextual_prompts_enabled": false as NSObject,
            "smart_prompt_prayer_notifications_enabled": false as NSObject,
            "smart_prompt_church_updates_enabled": false as NSObject,
            "smart_prompt_berean_continuation_enabled": true as NSObject,
            "smart_prompt_quiet_mode_enabled": false as NSObject,
            "smart_prompt_selah_pause_enabled": false as NSObject,
            "smart_prompt_spaces_join_enabled": false as NSObject,
            "smart_prompt_creator_insights_enabled": false as NSObject,
            "smart_prompt_observances_enabled": false as NSObject,
            "smart_prompt_ambient_hero_enabled": false as NSObject,

            // System 42: Spaces Ambient Intelligence OS — all OFF by default
            "amen_spaces_intelligence_enabled": false as NSObject,
            "persistent_memory_graph_enabled": false as NSObject,
            "collapsible_intelligence_enabled": false as NSObject,
            "semantic_pinning_enabled": false as NSObject,
            "catch_up_intelligence_enabled": false as NSObject,
            "ambient_ai_enabled": false as NSObject,
            "smart_sidebar_enabled": false as NSObject,
            "emotional_context_engine_enabled": false as NSObject,
            "spiritual_continuity_engine_enabled": false as NSObject,
            "intent_aware_search_enabled": false as NSObject,
            "multi_thread_branching_enabled": false as NSObject,
            "presence_aware_ui_enabled": false as NSObject,

            // System 43: Church Notes Context Engine (all OFF by default)
            "church_notes_context_engine_enabled": false as NSObject,
            "church_notes_smart_memory_enabled": false as NSObject,
            "church_notes_berean_context_panel_enabled": true as NSObject,
            "church_notes_sermon_to_action_enabled": false as NSObject,
            "church_notes_growth_timeline_enabled": false as NSObject,
            "church_notes_smart_recap_enabled": false as NSObject,
            "church_notes_group_intelligence_enabled": false as NSObject,
            "church_notes_command_bar_enabled": false as NSObject,
            "church_notes_smart_capture_enabled": false as NSObject,
            "church_notes_ai_provenance_enabled": false as NSObject,
            "church_notes_context_engine_kill_switch": false as NSObject,

            // System 45: Comms OS (ON by default — Remote Config can kill-switch per flag)
            "comms_intelligence_enabled": true as NSObject,
            "comms_smart_context_enabled": true as NSObject,
            "comms_catch_up_enabled": true as NSObject,
            "comms_decisions_enabled": true as NSObject,
            "comms_media_intel_enabled": true as NSObject,
            "comms_pulse_enabled": true as NSObject,
            "comms_command_palette_enabled": true as NSObject,
            "comms_presence_enabled": true as NSObject,
            "comms_multi_pane_enabled": true as NSObject,

            // System 46: Berean Drive (CarPlay) — all OFF; entitlement + Remote Config required
            "carplay_kill_switch": false as NSObject,
            "carplay_berean_enabled": false as NSObject,
            "carplay_audio_enabled": false as NSObject,
            "carplay_messaging_enabled": false as NSObject,
            "carplay_navigation_handoff_enabled": false as NSObject,

            // Calm Control + Spiritual Rhythm OS (Phase 1 MVP) — all OFF by default
            "calm_control_enabled": false as NSObject,
            "calm_privacy_controls_enabled": false as NSObject,
            "calm_feed_controls_enabled": false as NSObject,
            "spiritual_rhythm_enabled": false as NSObject,
            "sabbath_mode_enabled": false as NSObject,
            "daily_verse_push_enabled": false as NSObject,
            "inactivity_pause_policy_enabled": false as NSObject,
            "streak_grace_recovery_enabled": false as NSObject,
            "audience_layers_enabled": false as NSObject,
            "anonymous_reflections_enabled": false as NSObject,
            "berean_verse_recommendations_enabled": false as NSObject,

            // Community Notes — ON (Tab 8 uses ChurchNotesView)
            "community_notes_enabled": true as NSObject,

            // Anonymous-Accountable Mode — OFF until anonPost.ts CF + ANON_SALT secret deploy
            "anon_mode_enabled": false as NSObject,

            // Org Platform — all OFF; Remote Config + backend deploy required
            "org_platform_enabled": false as NSObject,
            "org_seed_enabled": false as NSObject,
            "org_claim_flow_enabled": false as NSObject,
            "org_subscriptions_enabled": false as NSObject,

            // Payments / Stripe / Giving (B-01, B-02, B-24) — OFF until backend is ready
            "payments_enabled": false as NSObject,

            // Berean Drive / CarPlay CFs (B-23) — OFF until 5 drive CFs are deployed
            "berean_drive_enabled": false as NSObject,

            // Master Run Feature Flags — all OFF until each phase ships
            "find_a_church": false as NSObject,
            "posts_liquid_glass": false as NSObject,
            "why_seeing_this": false as NSObject,
            "selah_stories": false as NSObject,
            "selah_stories_premium_ai": false as NSObject,

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
        studioAITaggingEnabled         = config["studio_ai_tagging_enabled"].boolValue
        creatorSpacesEnabled           = config["creator_spaces_enabled"].boolValue
        presencePostsEnabled           = config["presence_posts_enabled"].boolValue
        mediaAuthenticityEnabled       = config["media_authenticity_enabled"].boolValue

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
        suggestedFollowsSmartRankingEnabled = config["suggested_follows_smart_ranking_enabled"].boolValue

        mutualContextRowEnabled = config["mutual_context_row_enabled"].boolValue
        presenceIntelligenceEnabled = config["presence_intelligence_enabled"].boolValue
        messageRequestIntelligenceEnabled = config["message_request_intelligence_enabled"].boolValue
        trustExplainerEnabled = config["trust_explainer_enabled"].boolValue
        postDividerEnabled = config["post_divider_enabled"].boolValue
        feedViewModeSwitcherEnabled = config["feed_view_mode_switcher_enabled"].boolValue
        mediaFilterPillsEnabled = config["media_filter_pills_enabled"].boolValue
        mediaDetailViewEnabled = config["media_detail_view_enabled"].boolValue
        mediaViewerFloatingEngagementPillEnabled = config["media_viewer_floating_engagement_pill_enabled"].boolValue
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
        churchNotesAudioCaptureEnabled = config["church_notes_audio_capture_enabled"].boolValue
        churchNotesPhotoOCREnabled = config["church_notes_photo_ocr_enabled"].boolValue
        churchNotesVideoCaptureEnabled = config["church_notes_video_capture_enabled"].boolValue
        churchNotesAIDraftReviewEnabled = config["church_notes_ai_draft_review_enabled"].boolValue
        churchNotesStudyGuideEnabled = config["church_notes_study_guide_enabled"].boolValue
        churchNotesPrayerPromptsEnabled = config["church_notes_prayer_prompts_enabled"].boolValue
        churchNotesIntelligenceEnabled = config["church_notes_intelligence_enabled"].boolValue
        sermonAudioCaptureEnabled = config["sermon_audio_capture_enabled"].boolValue
        sermonVideoCaptureEnabled = config["sermon_video_capture_enabled"].boolValue
        churchPhotoOCRCaptureEnabled = config["church_photo_ocr_capture_enabled"].boolValue
        churchNotesTranslationEnabled = config["church_notes_translation_enabled"].boolValue
        churchNotesCollaborationEnabled = config["church_notes_collaboration_enabled"].boolValue
        sermonSummaryGenerationEnabled = config["sermon_summary_generation_enabled"].boolValue
        scriptureDetectionEnabled = config["scripture_detection_enabled"].boolValue
        sermonActionExtractionEnabled = config["sermon_action_extraction_enabled"].boolValue
        sermonClipSuggestionEnabled = config["sermon_clip_suggestion_enabled"].boolValue
        churchNotesStudyGuideGenerationEnabled = config["church_notes_study_guide_generation_enabled"].boolValue
        churchNotesProcessingKillSwitch = config["church_notes_processing_kill_switch"].boolValue

        churchNotesAudioCaptureEnabled = churchNotesAudioCaptureEnabled || sermonAudioCaptureEnabled
        churchNotesVideoCaptureEnabled = churchNotesVideoCaptureEnabled || sermonVideoCaptureEnabled
        churchNotesPhotoOCREnabled = churchNotesPhotoOCREnabled || churchPhotoOCRCaptureEnabled
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

        bereanPulseEnabled = config["berean_pulse_enabled"].boolValue

        ambientGlowEnabled = config["ambient_glow_enabled"].boolValue
        ambientGlowAuthenticationEnabled = config["ambient_glow_authentication_enabled"].boolValue
        ambientGlowBereanEnabled = config["ambient_glow_berean_enabled"].boolValue
        ambientGlowSelahEnabled = config["ambient_glow_selah_enabled"].boolValue
        ambientGlowPrayerEnabled = config["ambient_glow_prayer_enabled"].boolValue
        ambientGlowMediaEnabled = config["ambient_glow_media_enabled"].boolValue
        ambientGlowFeedEnabled = config["ambient_glow_feed_enabled"].boolValue

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
        spatialRoomsEnabled = config["spatial_rooms_enabled"].stringValue.lowercased() != "false"
        spatialRoomsServerCreationEnabled = config["spatial_rooms_server_creation_enabled"].stringValue.lowercased() != "false"
        spatialRoomsAIThemeGenerationEnabled = config["spatial_rooms_ai_theme_generation_enabled"].stringValue.lowercased() != "false"
        spatialRoomsBackfillEnabled = config["spatial_rooms_backfill_enabled"].stringValue.lowercased() != "false"
        spatialContextRailEnabled = config["spatial_context_rail_enabled"].boolValue
        provenanceTrustPanelEnabled = config["provenance_trust_panel_enabled"].boolValue
        creatorOSComposerEnabled = config["creator_os_composer_enabled"].boolValue
        truthfulAILabelsEnabled = config["truthful_ai_labels_enabled"].boolValue
        smartDiscoveryTransparencyEnabled = config["smart_discovery_transparency_enabled"].boolValue
        discoveryWhyShownEnabled = config["discovery_why_shown_enabled"].boolValue
        safetyOSEnabled = config["safety_os_enabled"].boolValue

        // System 35: Trust Spine (Phase 1)
        // All System 35 flags default ON. Remote Config can explicitly flip
        // any of them OFF only by returning the source string "false";
        // a missing/empty Remote Config value preserves the ON default.
        let trustSpineString = config["trust_spine_pipeline_enabled"].stringValue
        trustSpinePipelineEnabled = trustSpineString.lowercased() != "false"
        let aiDisclosureString = config["ai_disclosure_labels_enabled"].stringValue
        aiDisclosureLabelsEnabled = aiDisclosureString.lowercased() != "false"
        let sharedViewingString = config["shared_viewing_enabled"].stringValue
        sharedViewingEnabled = sharedViewingString.lowercased() != "false"
        let spatialMessagesString = config["spatial_messages_enabled"].stringValue
        spatialMessagesEnabled = spatialMessagesString.lowercased() != "false"
        let hidePublicLikesString = config["public_like_counts_hidden"].stringValue
        publicLikeCountsHidden = hidePublicLikesString.lowercased() != "false"
        let creatorOSString = config["amen_creator_os_premium_enabled"].stringValue
        amenCreatorOSPremiumEnabled = creatorOSString.lowercased() != "false"
        let discoveryTransparencyString = config["discovery_transparency_enabled"].stringValue
        discoveryTransparencyEnabled = discoveryTransparencyString.lowercased() != "false"

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

        // Amen Smart Message Intelligence
        smartMessageIntelligenceEnabled = config["smart_message_intelligence_enabled"].boolValue
        smartEventDetectionEnabled = config["smart_event_detection_enabled"].boolValue
        prayerIntelligenceEnabled = config["prayer_intelligence_enabled"].boolValue
        discussionSummariesEnabled = config["discussion_summaries_enabled"].boolValue
        contextualBereanActionsEnabled = config["contextual_berean_actions_enabled"].boolValue
        topicExtractionEnabled = config["topic_extraction_enabled"].boolValue
        semanticSearchEnabled = config["semantic_search_enabled"].boolValue
        studyModeEnabled = config["study_mode_enabled"].boolValue
        voiceIntelligenceEnabled = config["voice_intelligence_enabled"].boolValue
        knowledgeGraphMemoryEnabled = config["knowledge_graph_memory_enabled"].boolValue

        // System 36: Messaging Filters & Smart Inbox
        messagingInboxFiltersEnabled = config["messaging_inbox_filters_enabled"].boolValue
        messagingThreadSearchFiltersEnabled = config["messaging_thread_search_filters_enabled"].boolValue
        messagingSmartInboxCountsEnabled = config["messaging_smart_inbox_counts_enabled"].boolValue

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
        ariseEnabled = config["arise_enabled"].boolValue
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
        perMediaCaptionIncrementalModerationEnabled = config["per_media_caption_incremental_moderation_enabled"].boolValue

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
        bannerRailEnabled = config["banner_rail_enabled"].boolValue

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

        // Amen Living Hero System. Missing Remote Config keys preserve local defaults.
        ambientSpatialHeroEnabled = config["ambient_spatial_hero_enabled"].stringValue.lowercased() != "false"
        livingEditorialBannerEnabled = config["living_editorial_banner_enabled"].stringValue.lowercased() != "false"
        spatialHeroReduceMotionFallbackEnabled = config["spatial_hero_reduce_motion_fallback_enabled"].stringValue.lowercased() != "false"
        spatialHeroPerformanceTelemetryEnabled = config["spatial_hero_performance_telemetry_enabled"].stringValue.lowercased() != "false"
        dailyVerseLivingHeroEnabled = config["daily_verse_living_hero_enabled"].stringValue.lowercased() != "false"
        dailyDigestLivingHeroEnabled = config["daily_digest_living_hero_enabled"].stringValue.lowercased() != "false"
        discoverLivingHeroEnabled = config["discover_living_hero_enabled"].stringValue.lowercased() != "false"
        selahLivingHeroEnabled = config["selah_living_hero_enabled"].stringValue.lowercased() != "false"
        bereanPulseLivingHeroEnabled = config["berean_pulse_living_hero_enabled"].stringValue.lowercased() != "false"
        churchProfileLivingHeroEnabled = config["church_profile_living_hero_enabled"].stringValue.lowercased() != "false"
        liveEventLivingHeroEnabled = config["live_event_living_hero_enabled"].stringValue.lowercased() != "false"
        creatorKitLivingHeroEnabled = config["creator_kit_living_hero_enabled"].stringValue.lowercased() != "false"

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

        // System 33: Berean Multimodal Intelligence
        let multimodalMaster = !config["berean_multimodal_kill_switch"].boolValue
        bereanMultimodalKillSwitch           = config["berean_multimodal_kill_switch"].boolValue
        bereanMultimodalEnabled              = multimodalMaster && config["berean_multimodal_enabled"].boolValue
        bereanVisualScriptureEnabled         = multimodalMaster && config["berean_visual_scripture_enabled"].boolValue
        bereanOnDeviceTranscriptionEnabled   = config["berean_on_device_transcription_enabled"].boolValue
        bereanVoiceCompanionEnabled          = multimodalMaster && config["berean_voice_companion_enabled"].boolValue
        bereanSelahModeEnabled               = multimodalMaster && config["berean_selah_mode_enabled"].boolValue
        bereanTestimonyAssistEnabled         = multimodalMaster && config["berean_testimony_assist_enabled"].boolValue
        bereanPrayerSafetyEnabled            = multimodalMaster && config["berean_prayer_safety_enabled"].boolValue

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

        amenGlobalAIKillSwitch                        = config["amen_global_ai_kill_switch"].boolValue
        geminiDirectClientEnabled                     = config["gemini_direct_client_enabled"].boolValue
        geminiClientKillSwitch                        = config["gemini_client_kill_switch"].boolValue
        geminiEvalLoggingEnabled                      = config["gemini_eval_logging_enabled"].boolValue
        geminiDailyVerseReflectionEnabled             = config["gemini_daily_verse_reflection_enabled"].boolValue
        geminiChurchNoteTitleSummaryEnabled           = config["gemini_church_note_title_summary_enabled"].boolValue
        geminiSmartMessageSummaryEnabled              = config["gemini_smart_message_summary_enabled"].boolValue
        geminiCaptionSuggestionsEnabled               = config["gemini_caption_suggestions_enabled"].boolValue
        geminiMapsGroundedSearchEnabled               = config["gemini_maps_grounded_search_enabled"].boolValue
        geminiFileSearchPilotEnabled                  = config["gemini_file_search_pilot_enabled"].boolValue
        geminiTTSEnabled                              = config["gemini_tts_enabled"].boolValue
        geminiImageGenerationPilotEnabled             = config["gemini_image_generation_pilot_enabled"].boolValue
        geminiVideoGenerationPrototypeEnabled         = config["gemini_video_generation_prototype_enabled"].boolValue
        geminiDeepResearchPrototypeEnabled            = config["gemini_deep_research_prototype_enabled"].boolValue
        geminiManagedAgentsPrototypeEnabled           = config["gemini_managed_agents_prototype_enabled"].boolValue
        geminiFlashModelName                          = config["gemini_flash_model_name"].stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "gemini-3.5-flash" : config["gemini_flash_model_name"].stringValue
        geminiFlashLiteModelName                      = config["gemini_flash_lite_model_name"].stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "gemini-3.5-flash-lite" : config["gemini_flash_lite_model_name"].stringValue
        geminiDirectClientDailyBudgetMicroUSD         = config["gemini_direct_client_daily_budget_micro_usd"].numberValue.intValue
        geminiDirectClientTimeoutMs                   = config["gemini_direct_client_timeout_ms"].numberValue.intValue

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
        smartCommandLayerEnabled            = config["smart_command_layer_enabled"].boolValue
        smartCommandLayerHomeEnabled        = config["smart_command_layer_home_enabled"].boolValue
        smartCommandLayerMessagesEnabled    = config["smart_command_layer_messages_enabled"].boolValue
        smartCommandLayerBereanEnabled      = config["smart_command_layer_berean_enabled"].boolValue
        smartCommandLayerChurchNotesEnabled = config["smart_command_layer_church_notes_enabled"].boolValue
        smartCommandLayerSpacesEnabled      = config["smart_command_layer_spaces_enabled"].boolValue
        smartCommandLayerCreatePostEnabled  = config["smart_command_layer_create_post_enabled"].boolValue
        smartCommandLayerEventsEnabled      = config["smart_command_layer_events_enabled"].boolValue
        smartCommandLayerMediaEnabled       = config["smart_command_layer_media_enabled"].boolValue
        smartRepliesEnabled                 = config["smart_replies_enabled"].boolValue
        multiPaneCommunicationEnabled       = config["multi_pane_communication_enabled"].boolValue
        liquidGlassCommunicationUIEnabled   = config["liquid_glass_communication_ui_enabled"].boolValue
        replyPreviewRotationEnabled         = config["reply_preview_rotation_enabled"].boolValue

        // Conversation OS Intelligence Layer
        conversationOSEnabled                          = config["conversation_os_enabled"].boolValue
        conversationSummariesEnabled                   = config["conversation_summaries_enabled"].boolValue
        catchUpRecapsEnabled                           = config["catch_up_recaps_enabled"].boolValue
        topicClusteringEnabled                         = config["topic_clustering_enabled"].boolValue
        actionExtractionEnabled                        = config["action_extraction_enabled"].boolValue
        organizationalMemoryEnabled                    = config["organizational_memory_enabled"].boolValue
        personalizedInsightsEnabled                    = config["personalized_insights_enabled"].boolValue
        ambientConversationIntelligenceEnabled         = config["ambient_conversation_intelligence_enabled"].boolValue
        conversationOSLiquidGlassEnabled               = config["conversation_os_liquid_glass_enabled"].boolValue
        conversationOSDebugTelemetryEnabled            = config["conversation_os_debug_telemetry_enabled"].boolValue
        conversationOSSensitiveSpaceRestrictionsEnabled = config["conversation_os_sensitive_space_restrictions_enabled"].boolValue
        bereanConversationalOSEnabled                  = config["berean_conversational_os_enabled"].boolValue
        bereanLiquidGlassComposerEnabled               = config["berean_liquid_glass_composer_enabled"].boolValue
        contextualRecapCapsulesEnabled                 = config["contextual_recap_capsules_enabled"].boolValue
        unresolvedDiscussionTrackingEnabled            = config["unresolved_discussion_tracking_enabled"].boolValue
        semanticTopicClusteringEnabled                 = config["semantic_topic_clustering_enabled"].boolValue
        prayerAwareComposerEnabled                     = config["prayer_aware_composer_enabled"].boolValue
        selahConversationIntelligenceEnabled           = config["selah_conversation_intelligence_enabled"].boolValue

        // System 44: Messaging OS
        amenMessagingOSEnabled              = config["amen_messaging_os_enabled"].boolValue
        trustAwareInboxEnabled              = config["trust_aware_inbox_enabled"].boolValue
        messageRequestsEnabled              = config["message_requests_enabled"].boolValue
        messagingPrivacyPillEnabled         = config["messaging_privacy_pill_enabled"].boolValue
        aiMessagingSummariesEnabled         = config["ai_messaging_summaries_enabled"].boolValue
        aiPerChatConsentEnabled             = config["ai_per_chat_consent_enabled"].boolValue
        messagingActionExtractionEnabled    = config["messaging_action_extraction_enabled"].boolValue
        voiceNoteTranscriptionEnabled       = config["voice_note_transcription_enabled"].boolValue
        messageTranslationEnabled           = config["message_translation_enabled"].boolValue
        safeWordingSuggestionsEnabled       = config["safe_wording_suggestions_enabled"].boolValue
        messagingRiskDetectionEnabled       = config["messaging_risk_detection_enabled"].boolValue
        semanticMessageSearchEnabled        = config["semantic_message_search_enabled"].boolValue
        chatLockEnabled                     = config["chat_lock_enabled"].boolValue
        disappearingMessagesEnabled         = config["disappearing_messages_enabled"].boolValue
        groupContextTabsEnabled             = config["group_context_tabs_enabled"].boolValue

        // System 37: Amen Access Passes
        accessPassesEnabled                         = config["access_passes_enabled"].boolValue
        accessPassQRGenerationEnabled               = config["access_pass_qr_generation_enabled"].boolValue
        accessPassNFCEnabled                        = config["access_pass_nfc_enabled"].boolValue
        accessPassCheckInEnabled                    = config["access_pass_check_in_enabled"].boolValue
        accessPassRoleGatedEnabled                  = config["access_pass_role_gated_enabled"].boolValue
        accessPassAdminConsoleEnabled               = config["access_pass_admin_console_enabled"].boolValue
        accessPassSensitiveSpaceDirectJoinBlocked   = config["access_pass_sensitive_space_direct_join_blocked"].boolValue
        accessPassAuditLoggingEnabled               = config["access_pass_audit_logging_enabled"].boolValue

        // System 39: Amen Integrations Platform
        let killSwitch = config["amen_integrations_kill_switch"].boolValue
        amenIntegrationsKillSwitch          = killSwitch
        amenIntegrationsEnabled             = !killSwitch && config["amen_integrations_enabled"].boolValue
        amenMicrosoftGraphEnabled           = !killSwitch && config["amen_microsoft_graph_enabled"].boolValue
        amenZoomEnabled                     = !killSwitch && config["amen_zoom_enabled"].boolValue
        amenSlackEnabled                    = !killSwitch && config["amen_slack_enabled"].boolValue
        amenGatheringsEnabled               = !killSwitch && config["amen_gatherings_enabled"].boolValue
        amenGatheringMeetingLinksEnabled    = !killSwitch && config["amen_gathering_meeting_links_enabled"].boolValue
        amenGatheringRemindersEnabled       = !killSwitch && config["amen_gathering_reminders_enabled"].boolValue
        amenGatheringFollowUpsEnabled       = !killSwitch && config["amen_gathering_follow_ups_enabled"].boolValue
        amenGatheringAISuggestionsEnabled   = !killSwitch && config["amen_gathering_ai_suggestions_enabled"].boolValue
        amenIntegrationAdminWorkflowsEnabled = !killSwitch && config["amen_integration_admin_workflows_enabled"].boolValue
        amenIntegrationAuditLoggingEnabled  = !killSwitch && config["amen_integration_audit_logging_enabled"].boolValue

        // System 40: Multi-Tenant Contextual Experiences
        contextualExperiencesEnabled                = config["contextual_experiences_enabled"].boolValue
        organizationExperiencesEnabled              = config["organization_experiences_enabled"].boolValue
        experienceLiquidGlassEnabled                = config["experience_liquid_glass_enabled"].boolValue
        experienceAdminToolsEnabled                 = config["experience_admin_tools_enabled"].boolValue
        experienceAnalyticsEnabled                  = config["experience_analytics_enabled"].boolValue
        experienceMemoriesEnabled                   = config["experience_memories_enabled"].boolValue
        experiencePrayerCampaignsEnabled            = config["experience_prayer_campaigns_enabled"].boolValue
        experienceSpacesIntegrationEnabled          = config["experience_spaces_integration_enabled"].boolValue

        // System 39: Verification & Trust
        verificationCenterEnabled       = config["verification_center_enabled"].boolValue
        identityVerificationEnabled     = config["identity_verification_enabled"].boolValue
        organizationVerificationEnabled = config["organization_verification_enabled"].boolValue
        orgVerificationEnabled          = config["org_verification_enabled"].boolValue
        roleVerificationEnabled         = config["role_verification_enabled"].boolValue
        creatorVerificationEnabled      = config["creator_verification_enabled"].boolValue
        publicTrustBadgesEnabled        = config["public_trust_badges_enabled"].boolValue
        impersonationReportsEnabled     = config["impersonation_reports_enabled"].boolValue

        // System 38: Amen Gatherings
        gatheringsEnabled                           = config["gatherings_enabled"].boolValue
        gatheringCreationEnabled                    = config["gathering_creation_enabled"].boolValue
        gatheringAccessPassEnabled                  = config["gathering_access_pass_enabled"].boolValue
        gatheringQRShareEnabled                     = config["gathering_qr_share_enabled"].boolValue
        gatheringNFCEnabled                         = config["gathering_nfc_enabled"].boolValue
        gatheringCalendarEnabled                    = config["gathering_calendar_enabled"].boolValue
        gatheringGuestListEnabled                   = config["gathering_guest_list_enabled"].boolValue
        gatheringPrayerRequestsEnabled              = config["gathering_prayer_requests_enabled"].boolValue
        gatheringUnauthenticatedPreviewEnabled      = config["gathering_unauthenticated_preview_enabled"].boolValue
        gatheringUnauthenticatedRsvpEnabled         = config["gathering_unauthenticated_rsvp_enabled"].boolValue
        gatheringHostConsoleEnabled                 = config["gathering_host_console_enabled"].boolValue
        gatheringMediaEnabled                       = config["gathering_media_enabled"].boolValue

        smartCommunitySearchEnabled                 = config["smart_community_search_enabled"].boolValue
        smartCommunitySearchUsesExternalPlaces      = config["smart_community_search_external_places_enabled"].boolValue
        smartCommunitySearchUsesAIParser            = config["smart_community_search_ai_enabled"].boolValue

        // Callable Contract Guards — Remote Config can flip these on when backend ships
        bereanGenericProxyEnabled                   = config["berean_generic_proxy_enabled"].boolValue
        bereanEmbedProxyEnabled                     = config["berean_embed_proxy_enabled"].boolValue
        bereanVoiceProxyEnabled                     = config["berean_voice_proxy_enabled"].boolValue
        bereanCompassAnalyzeEnabled                 = config["berean_compass_analyze_enabled"].boolValue
        bereanShieldAnalyzeEnabled                  = config["berean_shield_analyze_enabled"].boolValue
        bereanSermonWeekPlanEnabled                 = config["berean_sermon_week_plan_enabled"].boolValue
        sermonSnapProxyEnabled                      = config["sermon_snap_proxy_enabled"].boolValue
        smartSuggestionsProxyEnabled                = config["smart_suggestions_proxy_enabled"].boolValue
        ttsProxyEnabled                             = config["tts_proxy_enabled"].boolValue
        studioAICallablesEnabled                    = config["studio_ai_callables_enabled"].boolValue
        trustSpineCallablesEnabled                  = config["trust_spine_callables_enabled"].boolValue
        sharedViewingRoomCallablesEnabled           = config["shared_viewing_room_callables_enabled"].boolValue
        universalLinkIntelligenceEnabled            = config["universal_link_intelligence_enabled"].boolValue
        covenantMessageCallablesEnabled             = config["covenant_message_callables_enabled"].boolValue
        churchNotesShareCallablesEnabled            = config["church_notes_share_callables_enabled"].boolValue
        premiumCallablesEnabled                     = config["premium_callables_enabled"].boolValue
        resolveUsernameToEmailEnabled               = config["resolve_username_to_email_enabled"].boolValue
        clientIPAddressEnabled                      = config["client_ip_address_enabled"].boolValue
        accountUtilityCallablesEnabled              = config["account_utility_callables_enabled"].boolValue
        notificationIntelligenceCallablesEnabled    = config["notification_intelligence_callables_enabled"].boolValue
        prayerSpiritualCallablesEnabled             = config["prayer_spiritual_callables_enabled"].boolValue
        socialGraphCallablesEnabled                 = config["social_graph_callables_enabled"].boolValue
        churchDiscoveryCallablesEnabled             = config["church_discovery_callables_enabled"].boolValue
        nearbyPeopleDiscoveryEnabled                = config["nearby_people_discovery_enabled"].boolValue
        studyGuideCallablesEnabled                  = config["study_guide_callables_enabled"].boolValue
        mediaModerationCallablesEnabled             = config["media_moderation_callables_enabled"].boolValue
        postAnalysisCallablesEnabled                = config["post_analysis_callables_enabled"].boolValue

        // System 41: Smart Contextual Prompts
        smartContextualPromptsEnabled           = config["smart_contextual_prompts_enabled"].boolValue
        smartPromptPrayerNotificationsEnabled   = config["smart_prompt_prayer_notifications_enabled"].boolValue
        smartPromptChurchUpdatesEnabled         = config["smart_prompt_church_updates_enabled"].boolValue
        smartPromptBereanContinuationEnabled    = config["smart_prompt_berean_continuation_enabled"].boolValue
        smartPromptQuietModeEnabled             = config["smart_prompt_quiet_mode_enabled"].boolValue
        smartPromptSelahPauseEnabled            = config["smart_prompt_selah_pause_enabled"].boolValue
        smartPromptSpacesJoinEnabled            = config["smart_prompt_spaces_join_enabled"].boolValue
        smartPromptCreatorInsightsEnabled       = config["smart_prompt_creator_insights_enabled"].boolValue
        smartPromptObservancesEnabled           = config["smart_prompt_observances_enabled"].boolValue
        smartPromptAmbientHeroEnabled           = config["smart_prompt_ambient_hero_enabled"].boolValue

        // System 42: Spaces Ambient Intelligence OS
        amenSpacesIntelligenceEnabled       = config["amen_spaces_intelligence_enabled"].boolValue
        persistentMemoryGraphEnabled        = config["persistent_memory_graph_enabled"].boolValue
        collapsibleIntelligenceEnabled      = config["collapsible_intelligence_enabled"].boolValue
        semanticPinningEnabled              = config["semantic_pinning_enabled"].boolValue
        catchUpIntelligenceEnabled          = config["catch_up_intelligence_enabled"].boolValue
        ambientAIEnabled                    = config["ambient_ai_enabled"].boolValue
        smartSidebarEnabled                 = config["smart_sidebar_enabled"].boolValue
        emotionalContextEngineEnabled       = config["emotional_context_engine_enabled"].boolValue
        spiritualContinuityEngineEnabled    = config["spiritual_continuity_engine_enabled"].boolValue
        intentAwareSearchEnabled            = config["intent_aware_search_enabled"].boolValue
        multiThreadBranchingEnabled         = config["multi_thread_branching_enabled"].boolValue
        presenceAwareUIEnabled              = config["presence_aware_ui_enabled"].boolValue

        // System 43: Church Notes Context Engine
        churchNotesContextEngineEnabled         = config["church_notes_context_engine_enabled"].boolValue
        churchNotesSmartMemoryEnabled           = config["church_notes_smart_memory_enabled"].boolValue
        churchNotesBereanContextPanelEnabled    = config["church_notes_berean_context_panel_enabled"].boolValue
        churchNotesSermonToActionEnabled        = config["church_notes_sermon_to_action_enabled"].boolValue
        churchNotesGrowthTimelineEnabled        = config["church_notes_growth_timeline_enabled"].boolValue
        churchNotesSmartRecapEnabled            = config["church_notes_smart_recap_enabled"].boolValue
        churchNotesGroupIntelligenceEnabled     = config["church_notes_group_intelligence_enabled"].boolValue
        churchNotesCommandBarEnabled            = config["church_notes_command_bar_enabled"].boolValue
        churchNotesSmartCaptureEnabled          = config["church_notes_smart_capture_enabled"].boolValue
        churchNotesAIProvenanceEnabled          = config["church_notes_ai_provenance_enabled"].boolValue
        if config["church_notes_context_engine_kill_switch"].boolValue {
            churchNotesContextEngineKillSwitch      = true
            churchNotesContextEngineEnabled         = false
            churchNotesSmartMemoryEnabled           = false
            churchNotesBereanContextPanelEnabled    = false
            churchNotesSermonToActionEnabled        = false
            churchNotesGrowthTimelineEnabled        = false
            churchNotesSmartRecapEnabled            = false
            churchNotesGroupIntelligenceEnabled     = false
            churchNotesCommandBarEnabled            = false
            churchNotesSmartCaptureEnabled          = false
            churchNotesAIProvenanceEnabled          = false
        }

        // System 45: Comms OS (ON by default — Remote Config can kill-switch per flag)
        commsIntelligenceEnabled        = config["comms_intelligence_enabled"].boolValue
        commsSmartContextEnabled        = config["comms_smart_context_enabled"].boolValue
        commsCatchUpEnabled             = config["comms_catch_up_enabled"].boolValue
        commsDecisionsEnabled           = config["comms_decisions_enabled"].boolValue
        commsMediaIntelEnabled          = config["comms_media_intel_enabled"].boolValue
        commsPulseEnabled               = config["comms_pulse_enabled"].boolValue
        commsCommandPaletteEnabled      = config["comms_command_palette_enabled"].boolValue
        commsPresenceEnabled            = config["comms_presence_enabled"].boolValue
        commsMultiPaneEnabled           = config["comms_multi_pane_enabled"].boolValue

        // System 46: Berean Drive (CarPlay) — all OFF by default; Remote Config enables after entitlement
        let carPlayKill = config["carplay_kill_switch"].boolValue
        carPlayKillSwitch               = carPlayKill
        carPlayBereanEnabled            = !carPlayKill && config["carplay_berean_enabled"].boolValue
        carPlayAudioEnabled             = !carPlayKill && config["carplay_audio_enabled"].boolValue
        carPlayMessagingEnabled         = !carPlayKill && config["carplay_messaging_enabled"].boolValue
        carPlayNavigationHandoffEnabled = !carPlayKill && config["carplay_navigation_handoff_enabled"].boolValue

        // Calm Control + Spiritual Rhythm OS (Phase 1 MVP)
        // Sub-features gate behind their parent master switch so a single Remote Config flip
        // disables the entire surface. Backend is authoritative; these are fast-path client guards.
        let calmMaster = config["calm_control_enabled"].boolValue
        calmControlEnabled              = calmMaster
        calmPrivacyControlsEnabled      = calmMaster && config["calm_privacy_controls_enabled"].boolValue
        calmFeedControlsEnabled         = calmMaster && config["calm_feed_controls_enabled"].boolValue
        anonymousReflectionsEnabled     = calmMaster && config["anonymous_reflections_enabled"].boolValue

        let rhythmMaster = config["spiritual_rhythm_enabled"].boolValue
        spiritualRhythmEnabled          = rhythmMaster
        sabbathModeEnabled              = rhythmMaster && config["sabbath_mode_enabled"].boolValue
        streakGraceRecoveryEnabled      = rhythmMaster && config["streak_grace_recovery_enabled"].boolValue

        dailyVersePushEnabled           = config["daily_verse_push_enabled"].boolValue
        inactivityPausePolicyEnabled    = config["inactivity_pause_policy_enabled"].boolValue
        audienceLayersEnabled           = config["audience_layers_enabled"].boolValue
        bereanVerseRecommendationsEnabled = config["berean_verse_recommendations_enabled"].boolValue

        // Community Notes
        communityNotesEnabled = config["community_notes_enabled"].boolValue

        // Anonymous-Accountable Mode
        anonModeEnabled = config["anon_mode_enabled"].boolValue

        // Org Platform
        orgPlatformEnabled      = config["org_platform_enabled"].boolValue
        orgSeedEnabled          = config["org_seed_enabled"].boolValue
        orgClaimFlowEnabled     = config["org_claim_flow_enabled"].boolValue
        orgSubscriptionsEnabled = config["org_subscriptions_enabled"].boolValue

        // Payments / Stripe / Giving (B-01, B-02, B-24)
        paymentsEnabled = config["payments_enabled"].boolValue

        // Berean Drive / CarPlay CFs (B-23)
        bereanDriveEnabled = config["berean_drive_enabled"].boolValue

        // Master Run Feature Flags (Phase 1–5, all default OFF)
        findAChurch = config["find_a_church"].boolValue
        postsLiquidGlass = config["posts_liquid_glass"].boolValue
        whySeeingThis = config["why_seeing_this"].boolValue
        selahStories = config["selah_stories"].boolValue
        selahStoriesPremiumAI = config["selah_stories_premium_ai"].boolValue
    }

    private func applyUITestOverrides() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-test-enable-composer-audio") {
            composerApprovedAudioEnabled = true
        }
        if args.contains("--ui-test-disable-composer-audio") {
            composerApprovedAudioEnabled = true
        }
        if args.contains("--enable-object-hubs") {
            enableObjectHubFlagsForLocalTesting()
        }
        applyManualObjectHubOverrides()
    }

    private func applyManualObjectHubOverrides() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "AMENEnableObjectHubManualTesting") {
            enableObjectHubFlagsForLocalTesting()
        }
        #endif
    }

    private func enableObjectHubFlagsForLocalTesting() {
        #if DEBUG
        communityHubsEnabled = true
        communityObjectMatchingEnabled = true
        objectHubViewEnabled = true
        objectHubInlinePillEnabled = true
        objectHubInlineClusterEnabled = true
        #endif
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
