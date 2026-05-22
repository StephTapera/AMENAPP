import Foundation

@MainActor
final class AmenAIModelRouter {
    static let shared = AmenAIModelRouter()

    private init() {}

    func route(inputText: String, policy: AmenAIRequestPolicy) -> AmenAIRouteDecision {
        let contentPolicy = AmenAITaskPolicy.evaluateContent(inputText, surface: policy.surface)
        let riskTier = AmenAITaskPolicy.minimumRisk(for: policy.taskType, contentPolicy: contentPolicy)
        let flags = AMENFeatureFlags.shared

        let directClientRequested = policy.preferredExecutionPath == .directClient
        let mustRemainBackendOnly = policy.taskType.requiresBackendOnly || contentPolicy.requiresBackendOnly || riskTier >= .high

        // Block personal sensitive content on ANY execution path without explicit consent.
        // Prayer, confession, trauma, crisis, and notes about minors are spiritually private —
        // sending them to AI (client or backend) requires the user to have opted in.
        // System-level categories (moderation, monetization, paidContent) are internal
        // pipeline tasks and do not require individual user consent.
        let personalSensitiveCategories: Set<AmenAISensitiveCategory> = [
            .prayer, .confession, .trauma, .minors, .crisis, .sensitiveNote, .privateMessage
        ]
        let hasPersonalSensitiveContent = !contentPolicy.categories.isDisjoint(with: personalSensitiveCategories)
        if hasPersonalSensitiveContent && !policy.userConsentedToSensitiveClientAI {
            return blockedDecision(
                policy: policy,
                riskTier: riskTier,
                reason: "sensitive_personal_content_requires_explicit_consent",
                contentPolicy: contentPolicy
            )
        }

        if directClientRequested && contentPolicy.requiresExplicitConsent && !policy.userConsentedToSensitiveClientAI {
            return blockedDecision(
                policy: policy,
                riskTier: riskTier,
                reason: "sensitive_content_requires_explicit_consent",
                contentPolicy: contentPolicy
            )
        }

        if directClientRequested && mustRemainBackendOnly {
            return blockedDecision(
                policy: policy,
                riskTier: riskTier,
                reason: "task_requires_backend_only",
                contentPolicy: contentPolicy
            )
        }

        if policy.preferredProvider == .gemini || directClientRequested {
            if let blockedReason = geminiBlockedReason(for: policy, directClientRequested: directClientRequested) {
                return blockedDecision(policy: policy, riskTier: riskTier, reason: blockedReason, contentPolicy: contentPolicy)
            }
        }

        let provider = resolvedProvider(for: policy, riskTier: riskTier, directClientRequested: directClientRequested)
        let executionPath = resolvedExecutionPath(for: policy, provider: provider, mustRemainBackendOnly: mustRemainBackendOnly)
        let decision = AmenAIRouteDecision(
            taskType: policy.taskType,
            provider: provider,
            model: resolvedModel(for: provider, policy: policy),
            executionPath: executionPath,
            riskTier: riskTier,
            timeoutBudgetMs: policy.timeoutBudgetMs,
            costBudgetMicroUSD: policy.costBudgetMicroUSD,
            fallbackProviders: sanitizedFallbacks(policy.fallbackProviders, riskTier: riskTier),
            featureFlag: featureFlagName(for: policy.taskType, provider: provider, executionPath: executionPath),
            blockedReason: nil,
            requiresConsent: contentPolicy.requiresExplicitConsent,
            evalLoggingEnabled: flags.geminiEvalLoggingEnabled || flags.performanceTelemetryEnabled
        )
        if decision.evalLoggingEnabled {
            AmenAIEvalLogger.shared.logRoute(decision, surface: policy.surface)
        }
        return decision
    }

    func assertAllowed(inputText: String, policy: AmenAIRequestPolicy) throws -> AmenAIRouteDecision {
        let decision = route(inputText: inputText, policy: policy)
        if let reason = decision.blockedReason {
            throw AmenAIModelRouterError.blocked(reason)
        }
        return decision
    }

    private func resolvedProvider(for policy: AmenAIRequestPolicy, riskTier: AmenAIRiskTier, directClientRequested: Bool) -> AmenAIProvider {
        if let preferred = policy.preferredProvider, preferred != .gemini || riskTier < .high {
            return preferred
        }
        switch policy.taskType {
        case .dailyVerseQuickReflection, .churchNoteTitleSummary, .postCaptionSuggestion, .churchGroundedSearch, .ttsNarration:
            return directClientRequested ? .gemini : .backend
        case .smartMessageSummary:
            return .backend
        case .bereanQuickAnswer:
            return .claude
        case .bereanDeepStudy, .pastoralCare:
            return .claude
        case .churchNotesFileSearch, .imageGeneration, .videoGeneration:
            return .backend
        case .moderation, .crisis, .paidEntitlement, .feedRanking, .creatorMonetization, .finalPublishDecision:
            return .backend
        }
    }

    private func resolvedExecutionPath(for policy: AmenAIRequestPolicy, provider: AmenAIProvider, mustRemainBackendOnly: Bool) -> AmenAIExecutionPath {
        if provider == .local { return .localOnly }
        if mustRemainBackendOnly { return .backendOnly }
        if provider == .gemini, policy.preferredExecutionPath == .directClient { return .directClient }
        return .backendOnly
    }

    private func resolvedModel(for provider: AmenAIProvider, policy: AmenAIRequestPolicy) -> String {
        if let modelOverride = policy.modelOverride, !modelOverride.isEmpty { return modelOverride }
        let flags = AMENFeatureFlags.shared
        switch provider {
        case .gemini:
            return flags.geminiFlashModelName
        case .claude:
            return "remote_config:claude"
        case .openAI:
            return "remote_config:openai"
        case .backend:
            return "server_selected"
        case .local:
            return "on_device_policy_v1"
        }
    }

    private func sanitizedFallbacks(_ providers: [AmenAIProvider], riskTier: AmenAIRiskTier) -> [AmenAIProvider] {
        if riskTier >= .high {
            return providers.filter { $0 != .gemini && $0 != .local }
        }
        return providers
    }

    private func featureFlagName(for taskType: AmenAITaskType, provider: AmenAIProvider, executionPath: AmenAIExecutionPath) -> String? {
        guard provider == .gemini || executionPath == .directClient else { return nil }
        switch taskType {
        case .dailyVerseQuickReflection: return "gemini_daily_verse_reflection_enabled"
        case .churchNoteTitleSummary: return "gemini_church_note_title_summary_enabled"
        case .smartMessageSummary: return "gemini_smart_message_summary_enabled"
        case .postCaptionSuggestion: return "gemini_caption_suggestions_enabled"
        case .churchGroundedSearch: return "gemini_maps_grounded_search_enabled"
        case .ttsNarration: return "gemini_tts_enabled"
        default: return "gemini_direct_client_enabled"
        }
    }

    private func geminiBlockedReason(for policy: AmenAIRequestPolicy, directClientRequested: Bool) -> String? {
        let flags = AMENFeatureFlags.shared
        if flags.geminiClientKillSwitch { return "gemini_client_kill_switch" }
        if directClientRequested && !flags.geminiDirectClientEnabled { return "gemini_direct_client_disabled" }

        switch policy.taskType {
        case .dailyVerseQuickReflection:
            return flags.geminiDailyVerseReflectionEnabled ? nil : "gemini_daily_verse_reflection_disabled"
        case .churchNoteTitleSummary:
            return flags.geminiChurchNoteTitleSummaryEnabled ? nil : "gemini_church_note_title_summary_disabled"
        case .smartMessageSummary:
            return flags.geminiSmartMessageSummaryEnabled ? nil : "gemini_smart_message_summary_disabled"
        case .postCaptionSuggestion:
            return flags.geminiCaptionSuggestionsEnabled ? nil : "gemini_caption_suggestions_disabled"
        case .churchGroundedSearch:
            return flags.geminiMapsGroundedSearchEnabled ? nil : "gemini_maps_grounded_search_disabled"
        case .churchNotesFileSearch:
            return flags.geminiFileSearchPilotEnabled ? nil : "gemini_file_search_pilot_disabled"
        case .ttsNarration:
            return flags.geminiTTSEnabled ? nil : "gemini_tts_disabled"
        case .imageGeneration:
            return flags.geminiImageGenerationPilotEnabled ? nil : "gemini_image_generation_pilot_disabled"
        case .videoGeneration:
            return flags.geminiVideoGenerationPrototypeEnabled ? nil : "gemini_video_generation_prototype_disabled"
        case .bereanDeepStudy:
            return flags.geminiDeepResearchPrototypeEnabled ? nil : "gemini_deep_research_prototype_disabled"
        default:
            return nil
        }
    }

    private func blockedDecision(
        policy: AmenAIRequestPolicy,
        riskTier: AmenAIRiskTier,
        reason: String,
        contentPolicy: AmenAIContentPolicyResult
    ) -> AmenAIRouteDecision {
        let provider = policy.preferredProvider ?? .backend
        let decision = AmenAIRouteDecision(
            taskType: policy.taskType,
            provider: provider,
            model: resolvedModel(for: provider, policy: policy),
            executionPath: .backendOnly,
            riskTier: riskTier,
            timeoutBudgetMs: policy.timeoutBudgetMs,
            costBudgetMicroUSD: policy.costBudgetMicroUSD,
            fallbackProviders: sanitizedFallbacks(policy.fallbackProviders, riskTier: riskTier),
            featureFlag: featureFlagName(for: policy.taskType, provider: provider, executionPath: policy.preferredExecutionPath ?? .backendOnly),
            blockedReason: contentPolicy.reason.map { "\(reason):\($0)" } ?? reason,
            requiresConsent: contentPolicy.requiresExplicitConsent,
            evalLoggingEnabled: AMENFeatureFlags.shared.geminiEvalLoggingEnabled || AMENFeatureFlags.shared.performanceTelemetryEnabled
        )
        if decision.evalLoggingEnabled {
            AmenAIEvalLogger.shared.logRoute(decision, surface: policy.surface)
        }
        return decision
    }
}

enum AmenAIModelRouterError: LocalizedError, Equatable {
    case blocked(String)

    var errorDescription: String? {
        switch self {
        case .blocked(let reason): return "AI route blocked: \(reason)"
        }
    }
}
