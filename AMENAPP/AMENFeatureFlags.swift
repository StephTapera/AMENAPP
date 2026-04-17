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

@MainActor
final class AMENFeatureFlags: ObservableObject {

    static let shared = AMENFeatureFlags()

    // MARK: - System 1: Advanced Moderation
    @Published private(set) var moderationV2Enabled: Bool = true
    @Published private(set) var imageModerationEnabled: Bool = false       // Requires Hive AI key
    @Published private(set) var dmEnhancedScanningEnabled: Bool = true
    @Published private(set) var moderationAppealsEnabled: Bool = true
    @Published private(set) var trustScoringEnabled: Bool = false          // Phase 2

    // MARK: - System 2: Berean RAG
    @Published private(set) var bereanRAGEnabled: Bool = false             // Requires vector backend
    @Published private(set) var bereanConversationMemoryEnabled: Bool = true
    @Published private(set) var bereanSourceAttributionEnabled: Bool = true
    @Published private(set) var bereanStreamingResponseEnabled: Bool = false
    @Published private(set) var bereanVoiceEnabled: Bool = false

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
    @Published private(set) var churchReviewsEnabled: Bool = false         // Phase 2
    @Published private(set) var churchInteractionTrackingEnabled: Bool = true
    @Published private(set) var churchJourneyTimelineEnabled: Bool = false
    @Published private(set) var churchPostCardDraftsEnabled: Bool = false
    @Published private(set) var churchExplainableRecommendationsEnabled: Bool = true

    // MARK: - System 6: Studio / Creator Marketplace
    @Published private(set) var studioEnabled: Bool = true
    @Published private(set) var studioMonetizationEnabled: Bool = false    // Requires Stripe
    @Published private(set) var studioJobBoardEnabled: Bool = true
    @Published private(set) var studioAITaggingEnabled: Bool = false       // Phase 2

    // MARK: - System 7: Knowledge Graph
    @Published private(set) var knowledgeGraphEnabled: Bool = true
    @Published private(set) var knowledgeGraphRelatedContentEnabled: Bool = true
    @Published private(set) var knowledgeGraphSemanticSearchEnabled: Bool = false // Requires embeddings

    // MARK: - System 8: Action Threads (Care Workflows)
    @Published private(set) var actionThreadsEnabled: Bool = false
    @Published private(set) var actionSuggestionsEnabled: Bool = false
    @Published private(set) var careFollowupsEnabled: Bool = false

    // MARK: - System 9: Compound Identity Graph
    @Published private(set) var compoundIdentityGraphEnabled: Bool = false
    @Published private(set) var agentRecommendationsEnabled: Bool = false

    // MARK: - System 10: Proof of Human + Proof of Care
    @Published private(set) var proofOfHumanEnabled: Bool = false
    @Published private(set) var proofOfCareEnabled: Bool = false
    @Published private(set) var trustSignalsEnabled: Bool = false

    // MARK: - System 11: Topic Drill-Down
    @Published private(set) var topicDrillDownEnabled: Bool = false
    @Published private(set) var topicEnrichmentEnabled: Bool = false

    // MARK: - System 12: Smart Media Continuity
    @Published private(set) var mediaResumeEnabled: Bool = false

    // MARK: - System 13: Suggested Follows
    @Published private(set) var suggestedFollowsEnabled: Bool = false
    @Published private(set) var suggestedRailPrayerEnabled: Bool = true
    @Published private(set) var suggestedRailTestimoniesEnabled: Bool = true
    @Published private(set) var suggestedRailPeekSheetEnabled: Bool = true
    @Published private(set) var suggestedRailServerRankingEnabled: Bool = false
    @Published private(set) var suggestedRailInsertionIndex: Int = 2
    @Published private(set) var suggestedRailCardLimit: Int = 12
    @Published private(set) var suggestedRailCooldownHours: Int = 24
    @Published private(set) var suggestedRailDismissCooldownDays: Int = 7

    // MARK: - System 14: Social Context & UX Enhancements
    @Published private(set) var mutualContextRowEnabled: Bool = true
    @Published private(set) var presenceIntelligenceEnabled: Bool = true
    @Published private(set) var messageRequestIntelligenceEnabled: Bool = true
    @Published private(set) var trustExplainerEnabled: Bool = true
    @Published private(set) var postDividerEnabled: Bool = true
    @Published private(set) var feedViewModeSwitcherEnabled: Bool = true
    @Published private(set) var mediaFilterPillsEnabled: Bool = false        // Secondary filter pills in media mode
    @Published private(set) var mediaDetailViewEnabled: Bool = true          // Media-first detail view
    @Published private(set) var enhancedNotificationsEnabled: Bool = false
    @Published private(set) var serverNotificationsV2Enabled: Bool = false  // Server-side notification pipeline
    @Published private(set) var bereanChatRedesignEnabled: Bool = true
    @Published private(set) var inAppBrowserEnabled: Bool = false

    // MARK: - System 15: Accessibility Intelligence Layer
    @Published private(set) var accessibilityIntelligenceEnabled: Bool = true
    @Published private(set) var meaningAwareTranslationEnabled: Bool = true
    @Published private(set) var naturalModeEnabled: Bool = true
    @Published private(set) var contextualModeEnabled: Bool = true
    @Published private(set) var readabilityLayerEnabled: Bool = true
    @Published private(set) var contentDifficultyScoring: Bool = true
    @Published private(set) var audioNarrationEnabled: Bool = false
    @Published private(set) var contextBridgeEnabled: Bool = true
    @Published private(set) var adaptiveAccessibilityEnabled: Bool = true
    @Published private(set) var conversationBridgeEnabled: Bool = true
    @Published private(set) var smartTranslationVisibilityEnabled: Bool = true
    @Published private(set) var sideBySideTranslationEnabled: Bool = true
    @Published private(set) var perLanguageAutoTranslateEnabled: Bool = true
    @Published private(set) var creationLanguageEnabled: Bool = true
    @Published private(set) var adaptiveTranslationEnabled: Bool = true

    // MARK: - System 16: Berean Spiritual Intelligence Layers
    @Published private(set) var bereanSpiritualLayersEnabled: Bool = false
    @Published private(set) var livingScriptureGraphEnabled: Bool = false    // Semantic/theological graph
    @Published private(set) var spiritualStateLayerEnabled: Bool = false     // Posture detection & response mode
    @Published private(set) var guidedDiscipleshipEnabled: Bool = false      // Longitudinal formation tracking
    @Published private(set) var scriptureImmersionEnabled: Bool = false      // Cultural/historical context
    @Published private(set) var authorityAlignmentEnabled: Bool = false      // Escalation guardrails

    // MARK: - System 17: Resources Intelligence
    @Published private(set) var resourcesIntelligenceEnabled: Bool = false
    @Published private(set) var supportDraftDetectionEnabled: Bool = false
    @Published private(set) var churchNoteCareSummaryEnabled: Bool = false
    @Published private(set) var trustedContactsEnabled: Bool = false
    @Published private(set) var helpingSomeoneElseEnabled: Bool = false
    @Published private(set) var supportFollowupsEnabled: Bool = false
    @Published private(set) var nonprofitRecommendationEnabled: Bool = false
    @Published private(set) var bereanResourceRoutingEnabled: Bool = false

    // MARK: - Cross-cutting
    @Published private(set) var analyticsEnabled: Bool = true
    @Published private(set) var performanceTelemetryEnabled: Bool = true

    private init() {
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
            "image_moderation_enabled": false as NSObject,
            "dm_enhanced_scanning_enabled": true as NSObject,
            "moderation_appeals_enabled": true as NSObject,
            "trust_scoring_enabled": false as NSObject,

            // Berean
            "berean_rag_enabled": false as NSObject,
            "berean_conversation_memory_enabled": true as NSObject,
            "berean_source_attribution_enabled": true as NSObject,
            "berean_streaming_response_enabled": false as NSObject,
            "berean_voice_enabled": false as NSObject,

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
            "church_reviews_enabled": false as NSObject,
            "church_interaction_tracking_enabled": true as NSObject,
            "church_journey_timeline_enabled": false as NSObject,
            "church_post_card_drafts_enabled": false as NSObject,
            "church_explainable_recommendations_enabled": false as NSObject,

            // Studio
            "studio_enabled": true as NSObject,
            "studio_monetization_enabled": false as NSObject,
            "studio_job_board_enabled": true as NSObject,
            "studio_ai_tagging_enabled": false as NSObject,

            // Knowledge Graph
            "knowledge_graph_enabled": true as NSObject,
            "knowledge_graph_related_content_enabled": true as NSObject,
            "knowledge_graph_semantic_search_enabled": false as NSObject,

            // Action Threads
            "action_threads_enabled": false as NSObject,
            "action_suggestions_enabled": false as NSObject,
            "care_followups_enabled": false as NSObject,

            // Compound Identity Graph
            "compound_identity_graph_enabled": false as NSObject,
            "agent_recommendations_enabled": false as NSObject,

            // Proof of Human + Proof of Care
            "proof_of_human_enabled": false as NSObject,
            "proof_of_care_enabled": false as NSObject,
            "trust_signals_enabled": false as NSObject,

            // Topic Drill-Down
            "topic_drill_down_enabled": false as NSObject,
            "topic_enrichment_enabled": false as NSObject,

            // Smart Media Continuity
            "media_resume_enabled": false as NSObject,

            // Suggested Follows
            "suggested_follows_enabled": false as NSObject,
            "suggested_rail_prayer_enabled": false as NSObject,
            "suggested_rail_testimonies_enabled": false as NSObject,
            "suggested_rail_peek_sheet_enabled": false as NSObject,
            "suggested_rail_server_ranking_enabled": false as NSObject,

            // Social Context & UX Enhancements
            "mutual_context_row_enabled": true as NSObject,
            "presence_intelligence_enabled": true as NSObject,
            "message_request_intelligence_enabled": true as NSObject,
            "trust_explainer_enabled": true as NSObject,
            "post_divider_enabled": true as NSObject,
            "feed_view_mode_switcher_enabled": true as NSObject,
            "media_filter_pills_enabled": false as NSObject,
            "media_detail_view_enabled": true as NSObject,
            "enhanced_notifications_enabled": false as NSObject,
            "server_notifications_v2_enabled": false as NSObject,
            "berean_chat_redesign_enabled": true as NSObject,
            "in_app_browser_enabled": false as NSObject,

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
            "berean_spiritual_layers_enabled": false as NSObject,
            "living_scripture_graph_enabled": false as NSObject,
            "spiritual_state_layer_enabled": false as NSObject,
            "guided_discipleship_enabled": false as NSObject,
            "scripture_immersion_enabled": false as NSObject,
            "authority_alignment_enabled": false as NSObject,

            // Resources Intelligence
            "resources_intelligence_enabled": true as NSObject,
            "support_draft_detection_enabled": false as NSObject,
            "church_note_care_summary_enabled": false as NSObject,
            "trusted_contacts_enabled": false as NSObject,
            "helping_someone_else_enabled": false as NSObject,
            "support_followups_enabled": false as NSObject,
            "nonprofit_recommendation_enabled": false as NSObject,
            "berean_resource_routing_enabled": false as NSObject,

            // Analytics
            "analytics_enabled": true as NSObject,
            "performance_telemetry_enabled": true as NSObject,
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
        guidedDiscipleshipEnabled = config["guided_discipleship_enabled"].boolValue
        scriptureImmersionEnabled = config["scripture_immersion_enabled"].boolValue
        authorityAlignmentEnabled = config["authority_alignment_enabled"].boolValue

        resourcesIntelligenceEnabled = config["resources_intelligence_enabled"].boolValue
        supportDraftDetectionEnabled = config["support_draft_detection_enabled"].boolValue
        churchNoteCareSummaryEnabled = config["church_note_care_summary_enabled"].boolValue
        trustedContactsEnabled = config["trusted_contacts_enabled"].boolValue
        helpingSomeoneElseEnabled = config["helping_someone_else_enabled"].boolValue
        supportFollowupsEnabled = config["support_followups_enabled"].boolValue
        nonprofitRecommendationEnabled = config["nonprofit_recommendation_enabled"].boolValue
        bereanResourceRoutingEnabled = config["berean_resource_routing_enabled"].boolValue

        analyticsEnabled = config["analytics_enabled"].boolValue
        performanceTelemetryEnabled = config["performance_telemetry_enabled"].boolValue
    }
}
