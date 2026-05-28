import Foundation

enum AmenAIProvider: String, Codable, CaseIterable {
    case claude
    case openAI = "openai"
    case gemini
    case local
    case backend
}

enum AmenAIExecutionPath: String, Codable {
    case backendOnly = "backend_only"
    case directClient = "direct_client"
    case localOnly = "local_only"
}

enum AmenAIRiskTier: String, Codable, Comparable {
    case low
    case medium
    case high
    case restricted

    static func < (lhs: AmenAIRiskTier, rhs: AmenAIRiskTier) -> Bool {
        let order: [AmenAIRiskTier] = [.low, .medium, .high, .restricted]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

enum AmenAITaskType: String, Codable, CaseIterable {
    case dailyVerseQuickReflection = "daily_verse_quick_reflection"
    case churchNoteTitleSummary = "church_note_title_summary"
    case smartMessageSummary = "smart_message_summary"
    case postCaptionSuggestion = "post_caption_suggestion"
    case churchGroundedSearch = "church_grounded_search"
    case churchNotesFileSearch = "church_notes_file_search"
    case ttsNarration = "tts_narration"
    case imageGeneration = "image_generation"
    case videoGeneration = "video_generation"
    case bereanQuickAnswer = "berean_quick_answer"
    case bereanDeepStudy = "berean_deep_study"
    case pastoralCare = "pastoral_care"
    case moderation = "moderation"
    case crisis = "crisis"
    case paidEntitlement = "paid_entitlement"
    case feedRanking = "feed_ranking"
    case creatorMonetization = "creator_monetization"
    case finalPublishDecision = "final_publish_decision"

    var defaultRiskTier: AmenAIRiskTier {
        switch self {
        case .dailyVerseQuickReflection, .churchNoteTitleSummary, .postCaptionSuggestion:
            return .low
        case .smartMessageSummary, .churchGroundedSearch, .churchNotesFileSearch, .ttsNarration, .imageGeneration, .videoGeneration, .bereanQuickAnswer:
            return .medium
        case .bereanDeepStudy, .pastoralCare:
            return .high
        case .moderation, .crisis, .paidEntitlement, .feedRanking, .creatorMonetization, .finalPublishDecision:
            return .restricted
        }
    }

    var requiresBackendOnly: Bool {
        switch self {
        case .moderation, .crisis, .paidEntitlement, .feedRanking, .creatorMonetization, .finalPublishDecision,
             .bereanDeepStudy, .pastoralCare, .churchNotesFileSearch, .imageGeneration, .videoGeneration,
             .smartMessageSummary, .bereanQuickAnswer:
            // smartMessageSummary operates on private message threads.
            // bereanQuickAnswer may receive sensitive spiritual input; backend enforces audit trail.
            return true
        case .dailyVerseQuickReflection, .churchNoteTitleSummary, .postCaptionSuggestion,
             .churchGroundedSearch, .ttsNarration:
            return false
        }
    }
}

enum AmenAISensitiveCategory: String, Codable, CaseIterable {
    case prayer
    case confession
    case privateMessage = "private_message"
    case trauma
    case minors
    case crisis
    case sensitiveNote = "sensitive_note"
    case paidContent = "paid_content"
    case monetization
    case moderation

    var requiresBackendOnly: Bool {
        switch self {
        case .prayer, .confession, .privateMessage, .trauma, .minors, .crisis, .sensitiveNote,
             .paidContent, .monetization, .moderation:
            return true
        }
    }
}

struct AmenAIContentPolicyResult: Equatable {
    let categories: Set<AmenAISensitiveCategory>
    let requiresExplicitConsent: Bool
    let requiresBackendOnly: Bool
    let reason: String?

    static let clear = AmenAIContentPolicyResult(
        categories: [],
        requiresExplicitConsent: false,
        requiresBackendOnly: false,
        reason: nil
    )
}

enum AmenAIConsentState: String, Codable {
    case notRequired = "not_required"
    case missing
    case granted
}

struct AmenAIRequestPolicy {
    let taskType: AmenAITaskType
    let surface: String
    let preferredProvider: AmenAIProvider?
    let preferredExecutionPath: AmenAIExecutionPath?
    let userConsentedToSensitiveClientAI: Bool
    let timeoutBudgetMs: Int
    let costBudgetMicroUSD: Int
    let fallbackProviders: [AmenAIProvider]
    let modelOverride: String?

    init(
        taskType: AmenAITaskType,
        surface: String,
        preferredProvider: AmenAIProvider? = nil,
        preferredExecutionPath: AmenAIExecutionPath? = nil,
        userConsentedToSensitiveClientAI: Bool = false,
        timeoutBudgetMs: Int = 5_000,
        costBudgetMicroUSD: Int = 1_000,
        fallbackProviders: [AmenAIProvider] = [.claude, .openAI, .local],
        modelOverride: String? = nil
    ) {
        self.taskType = taskType
        self.surface = surface
        self.preferredProvider = preferredProvider
        self.preferredExecutionPath = preferredExecutionPath
        self.userConsentedToSensitiveClientAI = userConsentedToSensitiveClientAI
        self.timeoutBudgetMs = timeoutBudgetMs
        self.costBudgetMicroUSD = costBudgetMicroUSD
        self.fallbackProviders = fallbackProviders
        self.modelOverride = modelOverride
    }
}

struct AmenAIRouteDecision: Equatable {
    let taskType: AmenAITaskType
    let provider: AmenAIProvider
    let model: String
    let executionPath: AmenAIExecutionPath
    let riskTier: AmenAIRiskTier
    let timeoutBudgetMs: Int
    let costBudgetMicroUSD: Int
    let fallbackProviders: [AmenAIProvider]
    let featureFlag: String?
    let blockedReason: String?
    let requiresConsent: Bool
    let evalLoggingEnabled: Bool

    var isBlocked: Bool { blockedReason != nil }
}

enum AmenAITaskPolicy {
    static func evaluateContent(_ text: String, surface: String = "unknown") -> AmenAIContentPolicyResult {
        let lower = text.lowercased()
        var categories = Set<AmenAISensitiveCategory>()

        if containsAny(lower, ["pray for me", "prayer request", "please pray", "intercede", "my prayer"]) {
            categories.insert(.prayer)
        }
        if containsAny(lower, ["confess", "confession", "i sinned", "i relapsed", "i am ashamed"]) {
            categories.insert(.confession)
        }
        if containsAny(lower, ["dm", "private message", "conversation", "texted me", "message thread"]) || surface.contains("message") {
            categories.insert(.privateMessage)
        }
        if containsAny(lower, ["trauma", "abuse", "assault", "self harm", "suicide", "kill myself", "hopeless"]) {
            categories.insert(.trauma)
        }
        if containsAny(lower, ["minor", "child", "teen", "underage", "13", "14", "15", "16", "17"]) {
            categories.insert(.minors)
        }
        if containsAny(lower, ["suicide", "self-harm", "hurt myself", "end my life", "crisis"]) {
            categories.insert(.crisis)
        }
        if containsAny(lower, ["church note", "sermon note", "journal", "private note", "counseling note"]) || surface.contains("note") {
            categories.insert(.sensitiveNote)
        }
        if surface.contains("moderation") { categories.insert(.moderation) }
        if surface.contains("monetization") || surface.contains("payout") { categories.insert(.monetization) }

        guard !categories.isEmpty else { return .clear }
        return AmenAIContentPolicyResult(
            categories: categories,
            requiresExplicitConsent: true,
            requiresBackendOnly: categories.contains(where: { $0.requiresBackendOnly }),
            reason: categories.map(\.rawValue).sorted().joined(separator: ",")
        )
    }

    static func minimumRisk(for taskType: AmenAITaskType, contentPolicy: AmenAIContentPolicyResult) -> AmenAIRiskTier {
        if contentPolicy.categories.contains(.crisis) || contentPolicy.categories.contains(.minors) {
            return .restricted
        }
        if contentPolicy.requiresBackendOnly {
            return max(taskType.defaultRiskTier, .high)
        }
        return taskType.defaultRiskTier
    }

    /// Minimum subscription tier required to invoke a task type client-side.
    /// Backend-only system tasks (moderation, crisis, feed ranking) are enforced
    /// via `requiresBackendOnly` and are not user-initiable regardless of tier.
    static func requiredTier(for taskType: AmenAITaskType) -> AmenSubscriptionTier {
        switch taskType {
        case .dailyVerseQuickReflection:
            return .free
        case .bereanQuickAnswer:
            return .free  // free tier gets 3/day; enforced in AIUsageService
        case .churchGroundedSearch, .bereanDeepStudy, .ttsNarration:
            return .berean
        case .postCaptionSuggestion, .smartMessageSummary, .imageGeneration, .pastoralCare:
            return .creator
        case .churchNoteTitleSummary, .churchNotesFileSearch, .videoGeneration:
            return .ministryPro
        case .moderation, .crisis, .paidEntitlement, .feedRanking, .creatorMonetization, .finalPublishDecision:
            return .free  // system tasks — access controlled by requiresBackendOnly, not tier
        }
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
