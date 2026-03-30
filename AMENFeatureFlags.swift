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

    // MARK: - System 6: Studio / Creator Marketplace
    @Published private(set) var studioEnabled: Bool = true
    @Published private(set) var studioMonetizationEnabled: Bool = false    // Requires Stripe
    @Published private(set) var studioJobBoardEnabled: Bool = true
    @Published private(set) var studioAITaggingEnabled: Bool = false       // Phase 2

    // MARK: - System 7: Knowledge Graph
    @Published private(set) var knowledgeGraphEnabled: Bool = true
    @Published private(set) var knowledgeGraphRelatedContentEnabled: Bool = true
    @Published private(set) var knowledgeGraphSemanticSearchEnabled: Bool = false // Requires embeddings

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

            // Studio
            "studio_enabled": true as NSObject,
            "studio_monetization_enabled": false as NSObject,
            "studio_job_board_enabled": true as NSObject,
            "studio_ai_tagging_enabled": false as NSObject,

            // Knowledge Graph
            "knowledge_graph_enabled": true as NSObject,
            "knowledge_graph_related_content_enabled": true as NSObject,
            "knowledge_graph_semantic_search_enabled": false as NSObject,

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

        studioEnabled = config["studio_enabled"].boolValue
        studioMonetizationEnabled = config["studio_monetization_enabled"].boolValue
        studioJobBoardEnabled = config["studio_job_board_enabled"].boolValue
        studioAITaggingEnabled = config["studio_ai_tagging_enabled"].boolValue

        knowledgeGraphEnabled = config["knowledge_graph_enabled"].boolValue
        knowledgeGraphRelatedContentEnabled = config["knowledge_graph_related_content_enabled"].boolValue
        knowledgeGraphSemanticSearchEnabled = config["knowledge_graph_semantic_search_enabled"].boolValue

        analyticsEnabled = config["analytics_enabled"].boolValue
        performanceTelemetryEnabled = config["performance_telemetry_enabled"].boolValue
    }
}
