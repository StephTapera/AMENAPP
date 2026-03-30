// BereanCoreService.swift
// AMENAPP
//
// The central AI operating layer for the AMEN app.
// Every AI capability — assistant, moderation, recommendation, safety,
// discovery, translation, wellness — routes through or coordinates with
// this singleton. It is the nervous system of the product.
//
// Architecture:
//   BereanCoreService
//   ├── ModelRoutingEngine          (provider selection, fallback, circuit breakers)
//   ├── PromptPolicyEngine          (guardrails, policy versioning, spiritual integrity)
//   ├── ConfidenceScoringService    (response quality evaluation)
//   ├── SemanticTopicService        (topic/scripture graph across surfaces)
//   ├── UserSignalsService          (unified behavioral signal aggregation)
//   └── RecommendationIntelligenceService (cross-surface semantic recommendations)
//
// All existing services (SafetyOrchestrator, HomeFeedAlgorithm,
// TranslationService, ContentRiskAnalyzer, BereanOrchestrator, etc.)
// remain unchanged — BereanCoreService coordinates them without replacing them.

import SwiftUI
import Combine
import Foundation

// MARK: - Surface Identifier
/// Every product surface that Berean AI can enhance.
enum AMENSurface: String, Codable, CaseIterable {
    case bereanChat       = "berean_chat"
    case postCreation     = "post_creation"
    case comment          = "comment"
    case dm               = "dm"
    case churchNotes      = "church_notes"
    case prayerRequest    = "prayer_request"
    case testimony        = "testimony"
    case feed             = "feed"
    case discovery        = "discovery"
    case wisdomLibrary    = "wisdom_library"
    case resources        = "resources"
    case opportunities    = "opportunities"
    case creatorPlatform  = "creator_platform"
    case churchDiscovery  = "church_discovery"
    case onboarding       = "onboarding"
    case notifications    = "notifications"
    case profile          = "profile"
    case wellnessCheckIn  = "wellness_check_in"
    case search           = "search"
}

// MARK: - AI Task Category
/// Broad classification used for routing, budgeting, and observability.
enum AITaskCategory: String, Codable {
    // Content understanding
    case contentAnalysis      = "content_analysis"
    case sentimentTone        = "sentiment_tone"
    case topicClassification  = "topic_classification"
    case scriptureGrounding   = "scripture_grounding"

    // Generation
    case assistantResponse    = "assistant_response"
    case captionHelp          = "caption_help"
    case rewriteSuggestion    = "rewrite_suggestion"
    case summaryGeneration    = "summary_generation"
    case prayerDrafting       = "prayer_drafting"
    case devotionalGeneration = "devotional_generation"

    // Safety & moderation
    case safetyScreening      = "safety_screening"
    case crisisDetection      = "crisis_detection"
    case dmSafetyGate         = "dm_safety_gate"
    case mediaSafety          = "media_safety"

    // Recommendation & discovery
    case feedRanking          = "feed_ranking"
    case contentRecommendation = "content_recommendation"
    case churchMatching       = "church_matching"
    case opportunityMatching  = "opportunity_matching"
    case semanticSearch       = "semantic_search"

    // Translation & accessibility
    case translation          = "translation"
    case altTextGeneration    = "alt_text_generation"

    // Well-being
    case wellnessSignal       = "wellness_signal"
    case crisisResource       = "crisis_resource"
}

// MARK: - AI Request
/// Unified request type for any AI operation in the app.
struct BereanAIRequest {
    let id: String                      // idempotency key
    let surface: AMENSurface
    let category: AITaskCategory
    let userInput: String               // primary text to process
    let context: [String: String]       // surface-specific metadata
    let retrievedContext: [String]      // pre-fetched RAG chunks
    let userId: String?
    let requiresStreaming: Bool
    let latencyBudgetMs: Int            // 0 = best-effort
    let allowCache: Bool
    let isPrivate: Bool                 // never cache or log raw content
    let createdAt: Date

    init(
        surface: AMENSurface,
        category: AITaskCategory,
        userInput: String,
        context: [String: String] = [:],
        retrievedContext: [String] = [],
        userId: String? = nil,
        requiresStreaming: Bool = false,
        latencyBudgetMs: Int = 3000,
        allowCache: Bool = true,
        isPrivate: Bool = false
    ) {
        self.id = UUID().uuidString
        self.surface = surface
        self.category = category
        self.userInput = userInput
        self.context = context
        self.retrievedContext = retrievedContext
        self.userId = userId
        self.requiresStreaming = requiresStreaming
        self.latencyBudgetMs = latencyBudgetMs
        self.allowCache = allowCache
        self.isPrivate = isPrivate
        self.createdAt = Date()
    }
}

// MARK: - AI Response
struct BereanAIResponse {
    let requestId: String
    let content: String
    let confidence: Double              // 0-1.0 from ConfidenceScoringService
    let provider: String
    let modelVersion: String
    let latencyMs: Int
    let fromCache: Bool
    let citations: [ScriptureCitation]
    let suggestedActions: [AIAction]
    let safetyFlags: [SafetyFlag]
    let topicTags: [String]
    let category: AITaskCategory
    let surface: AMENSurface
    let createdAt: Date

    var isHighConfidence: Bool  { confidence >= 0.75 }
    var isMediumConfidence: Bool { confidence >= 0.50 && confidence < 0.75 }
    var needsDisclaimer: Bool   { confidence < 0.50 || !citations.isEmpty }
}

struct ScriptureCitation: Identifiable, Codable {
    let id: String
    let reference: String       // e.g. "John 3:16"
    let text: String
    let translation: String
    let relevanceScore: Double
}

enum AIAction: Codable {
    case openVerse(reference: String)
    case openResource(id: String)
    case openChurch(id: String)
    case openPrayer
    case openBereanChat(prompt: String)
    case saveToLibrary
    case shareContent
    case reviseBeforeSending
    case seekPastoralSupport
    case viewCrisisResources
}

struct SafetyFlag: Codable {
    let category: String
    let severity: SafetyFlagSeverity
    let detail: String
    let actionRequired: SafetyFlagAction
}

enum SafetyFlagSeverity: String, Codable {
    case low, medium, high, critical
}

enum SafetyFlagAction: String, Codable {
    case allow, warn, suggestRevision, hold, block
}

// MARK: - BereanCoreService

@MainActor
final class BereanCoreService: ObservableObject {

    // MARK: Singleton
    static let shared = BereanCoreService()

    // MARK: Sub-services (all lazy, initialized on first use)
    let routing          = ModelRoutingEngine.shared
    let policy           = PromptPolicyEngine.shared
    let confidence       = ConfidenceScoringService.shared
    let topics           = SemanticTopicService.shared
    let signals          = UserSignalsService.shared
    let recommendations  = RecommendationIntelligenceService.shared

    // MARK: Published state
    @Published private(set) var activeRequests: Int = 0
    @Published private(set) var systemHealth: SystemHealth = .nominal
    @Published private(set) var lastObservabilitySnapshot: ObservabilitySnapshot?

    // MARK: Observability
    private var requestLog: [RequestLogEntry] = []
    private let maxLogEntries = 500
    private var cancellables = Set<AnyCancellable>()

    // MARK: Response cache
    private var responseCache: [String: BereanCachedResponse] = [:]
    private let cacheTTL: TimeInterval = 300  // 5 minutes
    private let maxCacheEntries = 200

    // MARK: Feature flags (mirrors RemoteConfig in production)
    @Published var featureFlags = AIFeatureFlags()

    private init() {
        setupObservabilityTimer()
        setupHealthMonitoring()
    }

    // MARK: - Primary Entry Point

    /// The single method every surface in the app calls for any AI operation.
    /// Routes to the appropriate provider, applies policy, scores confidence,
    /// and returns a unified BereanAIResponse.
    func process(_ request: BereanAIRequest) async -> BereanAIResponse {
        let startTime = Date()
        incrementActiveRequests()
        defer { Task { self.decrementActiveRequests() } }

        // 1. Feature flag gate
        guard featureFlags.isEnabled(for: request.surface, category: request.category) else {
            return makeDisabledResponse(for: request)
        }

        // 2. Policy check — reject or transform the prompt before sending to any model
        let policyResult = await policy.evaluate(request)
        if policyResult.shouldBlock {
            log(request: request, outcome: .blocked(reason: policyResult.blockReason ?? "policy"), latency: elapsed(from: startTime))
            return makeBlockedResponse(for: request, reason: policyResult.blockReason)
        }

        // 3. Cache lookup
        if request.allowCache && !request.isPrivate {
            let cacheKey = makeCacheKey(request)
            if let cached = responseCache[cacheKey], !cached.isExpired {
                log(request: request, outcome: .cacheHit, latency: elapsed(from: startTime))
                return cached.response
            }
        }

        // 4. Route to provider
        let routingResult = await routing.route(request, policyResult: policyResult)

        // 5. Confidence scoring
        let confidenceScore = await confidence.score(
            response: routingResult.content,
            request: request,
            citations: routingResult.citations
        )

        // 6. Topic tagging
        let tags = await topics.extractTags(from: routingResult.content, input: request.userInput)

        // 7. Assemble response
        let response = BereanAIResponse(
            requestId: request.id,
            content: routingResult.content,
            confidence: confidenceScore,
            provider: routingResult.provider,
            modelVersion: routingResult.modelVersion,
            latencyMs: elapsed(from: startTime),
            fromCache: false,
            citations: routingResult.citations,
            suggestedActions: buildSuggestedActions(request: request, tags: tags, confidence: confidenceScore),
            safetyFlags: routingResult.safetyFlags,
            topicTags: tags,
            category: request.category,
            surface: request.surface,
            createdAt: Date()
        )

        // 8. Cache (non-private, non-safety)
        if request.allowCache && !request.isPrivate && response.safetyFlags.isEmpty {
            let cacheKey = makeCacheKey(request)
            responseCache[cacheKey] = BereanCachedResponse(response: response, expiresAt: Date().addingTimeInterval(cacheTTL))
            trimCache()
        }

        // 9. Record signal
        signals.record(AISignalEvent(
            userId: request.userId,
            surface: request.surface,
            category: request.category,
            confidence: confidenceScore,
            hadSafetyFlags: !response.safetyFlags.isEmpty,
            latencyMs: elapsed(from: startTime)
        ))

        log(request: request, outcome: .success(provider: routingResult.provider), latency: elapsed(from: startTime))
        return response
    }

    // MARK: - Surface-Specific Convenience APIs

    /// Post creation: caption help, tone suggestions, verse suggestion, safety scan
    func assistPostCreation(
        text: String,
        userId: String?,
        needsSafetyCheck: Bool = true
    ) async -> PostCreationAssistance {
        var assistance = PostCreationAssistance()

        // Safety check first (non-blocking, async)
        if needsSafetyCheck {
            let safetyReq = BereanAIRequest(
                surface: .postCreation,
                category: .safetyScreening,
                userInput: text,
                userId: userId,
                latencyBudgetMs: 1500,
                allowCache: false,
                isPrivate: false
            )
            let safetyResult = await process(safetyReq)
            assistance.safetyFlags = safetyResult.safetyFlags
        }

        // Tone suggestion (parallel)
        async let toneTask = process(BereanAIRequest(
            surface: .postCreation,
            category: .sentimentTone,
            userInput: text,
            userId: userId,
            latencyBudgetMs: 800
        ))

        // Scripture suggestion if spiritually relevant
        async let scriptureTask: BereanAIResponse? = topics.looksSpiritual(text) ? process(BereanAIRequest(
            surface: .postCreation,
            category: .scriptureGrounding,
            userInput: text,
            userId: userId,
            latencyBudgetMs: 2000
        )) : nil

        let (toneResult, scriptureResult) = await (toneTask, scriptureTask)
        assistance.toneSuggestion = toneResult.content.isEmpty ? nil : toneResult.content
        assistance.suggestedVerses = scriptureResult?.citations ?? []
        assistance.topicTags = toneResult.topicTags
        return assistance
    }

    /// DM safety: pre-send gate with gentle UX framing
    func screenDM(
        text: String,
        senderId: String?,
        recipientId: String?
    ) async -> DMScreeningResult {
        let req = BereanAIRequest(
            surface: .dm,
            category: .dmSafetyGate,
            userInput: text,
            context: [
                "sender_id": senderId ?? "",
                "recipient_id": recipientId ?? ""
            ],
            userId: senderId,
            latencyBudgetMs: 300,   // blocks send button
            allowCache: false,
            isPrivate: true         // never cache DM content
        )
        let result = await process(req)
        return DMScreeningResult(
            canSend: result.safetyFlags.filter { $0.actionRequired == .block }.isEmpty,
            flags: result.safetyFlags,
            gentlePrompt: buildDMGentlePrompt(flags: result.safetyFlags),
            suggestedRevision: result.safetyFlags.contains(where: { $0.actionRequired == .suggestRevision })
                ? result.content : nil
        )
    }

    /// Church notes: summarize + extract action points + scripture refs
    func processChurchNote(
        noteText: String,
        userId: String?
    ) async -> ChurchNoteIntelligence {
        async let summaryTask = process(BereanAIRequest(
            surface: .churchNotes,
            category: .summaryGeneration,
            userInput: noteText,
            userId: userId,
            latencyBudgetMs: 4000
        ))
        async let scriptureTask = process(BereanAIRequest(
            surface: .churchNotes,
            category: .scriptureGrounding,
            userInput: noteText,
            userId: userId,
            latencyBudgetMs: 3000
        ))
        let (summary, scripture) = await (summaryTask, scriptureTask)
        return ChurchNoteIntelligence(
            summary: summary.content,
            extractedVerses: scripture.citations,
            actionPoints: extractActionPoints(from: summary.content),
            prayerPrompts: buildPrayerPrompts(from: scripture.citations),
            topicTags: summary.topicTags
        )
    }

    /// Feed ranking signal — lightweight, called per post scroll
    func feedSignal(
        postId: String,
        authorId: String,
        content: String,
        userId: String?
    ) async -> FeedSignal {
        // Quick local topic/quality check — never call a model for this
        let localScore = await topics.localQualityScore(text: content)
        let topicTags = await topics.extractTagsFast(from: content)
        return FeedSignal(
            postId: postId,
            qualityScore: localScore,
            topicTags: topicTags,
            addictionRiskFlag: await signals.addictionRisk(for: userId)
        )
    }

    /// Contextual "Ask Berean" entry — surfaces suggested prompts based on current screen
    func contextualPrompts(
        surface: AMENSurface,
        context: String,
        userId: String?
    ) async -> [String] {
        return await recommendations.suggestedPrompts(
            surface: surface,
            context: context,
            userId: userId
        )
    }

    /// Prayer request: supportive suggestions + crisis detection
    func processPrayerRequest(
        text: String,
        userId: String?
    ) async -> PrayerRequestIntelligence {
        async let safetyTask = process(BereanAIRequest(
            surface: .prayerRequest,
            category: .crisisDetection,
            userInput: text,
            userId: userId,
            latencyBudgetMs: 1500,
            allowCache: false,
            isPrivate: true
        ))
        async let supportTask = process(BereanAIRequest(
            surface: .prayerRequest,
            category: .prayerDrafting,
            userInput: text,
            userId: userId,
            latencyBudgetMs: 3000
        ))
        let (safety, support) = await (safetyTask, supportTask)
        let needsCrisisSupport = safety.safetyFlags.contains(where: {
            $0.category == "crisis" && ($0.severity == .high || $0.severity == .critical)
        })
        return PrayerRequestIntelligence(
            refinementSuggestion: support.content.isEmpty ? nil : support.content,
            crisisDetected: needsCrisisSupport,
            crisisResources: needsCrisisSupport ? CrisisResources.standard : nil,
            scriptureSuggestions: support.citations,
            categoryTags: support.topicTags
        )
    }

    // MARK: - Observability

    func currentMetrics() -> ObservabilitySnapshot {
        let successCount = requestLog.filter { if case .success = $0.outcome { return true }; return false }.count
        let totalCount = requestLog.count
        let avgLatency = requestLog.isEmpty ? 0 :
            requestLog.map(\.latencyMs).reduce(0, +) / requestLog.count
        return ObservabilitySnapshot(
            totalRequests: totalCount,
            successRate: totalCount > 0 ? Double(successCount) / Double(totalCount) : 1.0,
            averageLatencyMs: avgLatency,
            cacheHitRate: cacheHitRate(),
            activeProviders: routing.activeProviders(),
            systemHealth: systemHealth,
            timestamp: Date()
        )
    }

    // MARK: - Private Helpers

    private func setupObservabilityTimer() {
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.lastObservabilitySnapshot = self.currentMetrics()
                self.trimLog()
            }
            .store(in: &cancellables)
    }

    private func setupHealthMonitoring() {
        routing.$providerHealthMap
            .receive(on: DispatchQueue.main)
            .sink { [weak self] healthMap in
                let degraded = healthMap.values.filter { !$0.isHealthy }.count
                if degraded == 0       { self?.systemHealth = .nominal }
                else if degraded == 1  { self?.systemHealth = .degraded }
                else                   { self?.systemHealth = .critical }
            }
            .store(in: &cancellables)
    }

    private func incrementActiveRequests() {
        activeRequests += 1
    }

    private func decrementActiveRequests() {
        activeRequests = max(0, activeRequests - 1)
    }

    private func makeCacheKey(_ request: BereanAIRequest) -> String {
        let inputHash = request.userInput.hashValue
        return "\(request.surface.rawValue)_\(request.category.rawValue)_\(inputHash)"
    }

    private func trimCache() {
        guard responseCache.count > maxCacheEntries else { return }
        let sorted = responseCache.sorted { $0.value.expiresAt < $1.value.expiresAt }
        let toRemove = sorted.prefix(responseCache.count - maxCacheEntries)
        toRemove.forEach { responseCache.removeValue(forKey: $0.key) }
    }

    private func elapsed(from start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    private func buildSuggestedActions(
        request: BereanAIRequest,
        tags: [String],
        confidence: Double
    ) -> [AIAction] {
        var actions: [AIAction] = []
        if tags.contains(where: { $0.hasPrefix("verse:") }) {
            if let verseTag = tags.first(where: { $0.hasPrefix("verse:") }) {
                actions.append(.openVerse(reference: String(verseTag.dropFirst(6))))
            }
        }
        if request.surface == .dm && confidence < 0.3 {
            actions.append(.reviseBeforeSending)
        }
        if request.category == .crisisDetection {
            actions.append(.viewCrisisResources)
        }
        return actions
    }

    private func buildDMGentlePrompt(flags: [SafetyFlag]) -> String? {
        guard !flags.isEmpty else { return nil }
        let highest = flags.sorted { $0.severity.rawValue > $1.severity.rawValue }.first
        switch highest?.severity {
        case .critical: return "This message may cause harm. Please reconsider before sending."
        case .high:     return "We noticed something in this message. Take a moment to review it."
        case .medium:   return "Would you like to review your message before sending?"
        default:        return nil
        }
    }

    private func extractActionPoints(from summary: String) -> [String] {
        summary.components(separatedBy: "\n")
            .filter { $0.hasPrefix("•") || $0.hasPrefix("-") || $0.hasPrefix("*") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func buildPrayerPrompts(from citations: [ScriptureCitation]) -> [String] {
        citations.prefix(2).map { "Lord, as \($0.reference) reminds us — \($0.text.prefix(60))..." }
    }

    private func log(request: BereanAIRequest, outcome: RequestOutcome, latency: Int) {
        requestLog.append(RequestLogEntry(
            requestId: request.id,
            surface: request.surface,
            category: request.category,
            outcome: outcome,
            latencyMs: latency,
            timestamp: Date()
        ))
    }

    private func trimLog() {
        if requestLog.count > maxLogEntries {
            requestLog = Array(requestLog.suffix(maxLogEntries))
        }
    }

    private func cacheHitRate() -> Double {
        let hits = requestLog.filter { if case .cacheHit = $0.outcome { return true }; return false }.count
        return requestLog.isEmpty ? 0 : Double(hits) / Double(requestLog.count)
    }

    private func makeDisabledResponse(for request: BereanAIRequest) -> BereanAIResponse {
        BereanAIResponse(requestId: request.id, content: "", confidence: 0, provider: "disabled",
            modelVersion: "", latencyMs: 0, fromCache: false, citations: [], suggestedActions: [],
            safetyFlags: [], topicTags: [], category: request.category, surface: request.surface, createdAt: Date())
    }

    private func makeBlockedResponse(for request: BereanAIRequest, reason: String?) -> BereanAIResponse {
        BereanAIResponse(requestId: request.id, content: "", confidence: 0, provider: "policy",
            modelVersion: "policy", latencyMs: 0, fromCache: false, citations: [], suggestedActions: [],
            safetyFlags: [SafetyFlag(category: "policy", severity: .high,
                detail: reason ?? "Request blocked by policy", actionRequired: .block)],
            topicTags: [], category: request.category, surface: request.surface, createdAt: Date())
    }
}

// MARK: - Supporting Models

struct PostCreationAssistance {
    var toneSuggestion: String?
    var captionHelp: String?
    var suggestedVerses: [ScriptureCitation] = []
    var topicTags: [String] = []
    var safetyFlags: [SafetyFlag] = []
    var isClean: Bool { safetyFlags.filter { $0.actionRequired != .allow }.isEmpty }
}

struct DMScreeningResult {
    let canSend: Bool
    let flags: [SafetyFlag]
    let gentlePrompt: String?
    let suggestedRevision: String?
    var requiresUserReview: Bool { !flags.isEmpty }
}

struct ChurchNoteIntelligence {
    let summary: String
    let extractedVerses: [ScriptureCitation]
    let actionPoints: [String]
    let prayerPrompts: [String]
    let topicTags: [String]
}

struct FeedSignal {
    let postId: String
    let qualityScore: Double        // 0-1.0
    let topicTags: [String]
    let addictionRiskFlag: Bool     // true = deprioritize for this user
}

struct PrayerRequestIntelligence {
    let refinementSuggestion: String?
    let crisisDetected: Bool
    let crisisResources: CrisisResources?
    let scriptureSuggestions: [ScriptureCitation]
    let categoryTags: [String]
}

struct CrisisResources {
    let hotline: String
    let textLine: String
    let description: String

    static let standard = CrisisResources(
        hotline: "988",
        textLine: "Text HOME to 741741",
        description: "You are not alone. Help is available right now."
    )
}

struct AISignalEvent {
    let userId: String?
    let surface: AMENSurface
    let category: AITaskCategory
    let confidence: Double
    let hadSafetyFlags: Bool
    let latencyMs: Int
    let timestamp: Date = Date()
}

struct RequestLogEntry {
    let requestId: String
    let surface: AMENSurface
    let category: AITaskCategory
    let outcome: RequestOutcome
    let latencyMs: Int
    let timestamp: Date
}

enum RequestOutcome {
    case success(provider: String)
    case cacheHit
    case blocked(reason: String)
    case failed(error: String)
    case degraded(provider: String)
}

struct BereanCachedResponse {
    let response: BereanAIResponse
    let expiresAt: Date
    var isExpired: Bool { Date() > expiresAt }
}

enum SystemHealth: String {
    case nominal, degraded, critical
    var color: Color {
        switch self {
        case .nominal:  return .green
        case .degraded: return .orange
        case .critical: return .red
        }
    }
}

struct ObservabilitySnapshot {
    let totalRequests: Int
    let successRate: Double
    let averageLatencyMs: Int
    let cacheHitRate: Double
    let activeProviders: [String]
    let systemHealth: SystemHealth
    let timestamp: Date
}

// MARK: - AI Feature Flags
struct AIFeatureFlags {
    // Per-surface toggles (mirrors Firebase RemoteConfig in production)
    var bereanChatEnabled: Bool = true
    var postCreationAIEnabled: Bool = true
    var commentAIEnabled: Bool = true
    var dmSafetyEnabled: Bool = true
    var churchNotesAIEnabled: Bool = true
    var prayerRequestAIEnabled: Bool = true
    var feedIntelligenceEnabled: Bool = true
    var discoveryAIEnabled: Bool = true
    var translationEnabled: Bool = true
    var wellnessAIEnabled: Bool = true
    var wisdomLibraryAIEnabled: Bool = true
    var opportunitiesAIEnabled: Bool = true
    var onboardingAIEnabled: Bool = true
    var crisisDetectionEnabled: Bool = true

    func isEnabled(for surface: AMENSurface, category: AITaskCategory) -> Bool {
        // Safety-critical features always enabled
        if category == .crisisDetection || category == .dmSafetyGate { return true }

        switch surface {
        case .bereanChat:       return bereanChatEnabled
        case .postCreation:     return postCreationAIEnabled
        case .comment:          return commentAIEnabled
        case .dm:               return dmSafetyEnabled
        case .churchNotes:      return churchNotesAIEnabled
        case .prayerRequest:    return prayerRequestAIEnabled
        case .feed:             return feedIntelligenceEnabled
        case .discovery:        return discoveryAIEnabled
        case .wisdomLibrary:    return wisdomLibraryAIEnabled
        case .opportunities, .creatorPlatform: return opportunitiesAIEnabled
        case .onboarding:       return onboardingAIEnabled
        case .wellnessCheckIn:  return wellnessAIEnabled
        default:                return true
        }
    }
}
