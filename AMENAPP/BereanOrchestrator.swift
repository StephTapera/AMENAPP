
//
//  BereanOrchestrator.swift
//  AMENAPP
//
//  Provider-agnostic AI orchestration layer.
//  Routes tasks across Vertex AI, OpenAI, and Claude based on:
//    - Task type (sensitivity, context length, output format)
//    - Cost target (embeddings → Vertex, structured JSON → OpenAI, moral reasoning → Claude)
//    - Latency budget (fast path: cached/heuristic; standard: full RAG; background: prefetch)
//    - Availability (circuit breaker + fallback chain)
//
//  NON-NEGOTIABLES:
//    - Safety-sensitive tasks (DM_SAFETY_SCAN, MEDIA_SAFETY_SCAN) always use the most
//      conservative available provider, never fail-open.
//    - No raw provider credentials on-device. All LLM calls go through Cloud Functions
//      or Cloud Run, which hold credentials server-side.
//    - All provider calls are logged with provider + modelVersion for audit.
//

import Foundation
import FirebaseFunctions

// MARK: - Task Type

/// Every AI request in AMEN is classified into a TaskType before routing.
enum BereanTaskType: String, CaseIterable {
    // Biblical reasoning
    case bibleQA              = "BIBLE_QA"
    case moralCounsel         = "MORAL_COUNSEL"
    case businessTechQA       = "BUSINESS_TECH_QA"
    case scriptureExtraction  = "SCRIPTURE_EXTRACTION"

    // Content features
    case noteSummary          = "NOTE_SUMMARY"
    case postAssist           = "POST_ASSIST"
    case commentAssist        = "COMMENT_ASSIST"
    case feedExplainer        = "FEED_EXPLAINER"
    case notificationText     = "NOTIFICATION_TEXT"

    // Safety-critical (never fail-open)
    case dmSafetyScan         = "DM_SAFETY_SCAN"
    case mediaSafetyScan      = "MEDIA_SAFETY_SCAN"
    case reportTriage         = "REPORT_TRIAGE"
    case rankingLabels        = "RANKING_LABELS"

    var isSafetyCritical: Bool {
        switch self {
        case .dmSafetyScan, .mediaSafetyScan, .reportTriage: return true
        default: return false
        }
    }

    var maxLatencyMs: Int {
        switch self {
        case .dmSafetyScan:          return 300   // must be fast — blocks message send
        case .mediaSafetyScan:       return 2000
        case .commentAssist:         return 800
        case .postAssist:            return 1200
        case .noteSummary:           return 3000
        case .bibleQA:               return 4000
        case .moralCounsel:          return 5000
        default:                     return 3000
        }
    }
}

// MARK: - AI Provider Protocol

/// All provider implementations must conform to this protocol.
protocol AIProvider {
    var name: String { get }
    var modelVersion: String { get }
    var isAvailable: Bool { get }

    func generate(prompt: String, systemPrompt: String?, maxTokens: Int) async throws -> String
    func classify(text: String, categories: [String]) async throws -> [String: Double]
    func embed(text: String) async throws -> [Float]
    func moderateText(_ text: String, context: [String: String]) async throws -> ProviderModerationResult
    func structuredOutput<T: Decodable>(prompt: String, schema: String) async throws -> T
}

struct ProviderModerationResult {
    let isSafe: Bool
    let categories: [String: Double]
    let severity: Double
    let provider: String
    let modelVersion: String
}

// MARK: - Routing Table

/// Static routing rules. One row per TaskType.
/// Primary → Fallback → Emergency (local heuristic).
struct RoutingRule {
    let primary: ProviderKind
    let fallback: ProviderKind
    let emergency: ProviderKind   // always local heuristics — never fails
    let preferStructuredOutput: Bool
    let requiresRAG: Bool
    let note: String

    enum ProviderKind: Equatable {
        case vertex       // Vertex AI (embeddings, multimodal safety, scalable throughput)
        case openAI       // OpenAI (structured JSON, function calling, precise classifiers)
        case claude       // Claude (long-context moral/biblical reasoning, empathetic tone)
        case local        // Local heuristics (never network-dependent)
        case cloudFn(name: String)  // Firebase Cloud Function proxy
    }
}

// MARK: - Routing Table Definition

let bereanRoutingTable: [BereanTaskType: RoutingRule] = [
    // Biblical Q&A: Vertex retrieval + Claude synthesis
    .bibleQA: RoutingRule(
        primary: .cloudFn(name: "bereanBibleQA"),
        fallback: .cloudFn(name: "bereanBibleQAFallback"),
        emergency: .local,
        preferStructuredOutput: false,
        requiresRAG: true,
        note: "Vertex embedding retrieval + Claude for nuanced synthesis. Requires citations."
    ),

    // Moral counsel: Claude for empathetic, long-context moral framing
    .moralCounsel: RoutingRule(
        primary: .cloudFn(name: "bereanMoralCounsel"),
        fallback: .cloudFn(name: "bereanBibleQA"),
        emergency: .local,
        preferStructuredOutput: false,
        requiresRAG: true,
        note: "Claude preferred — best for pastoral empathy and nuanced moral reasoning."
    ),

    // Business/Tech: Claude moral framing + OpenAI structured action plan
    .businessTechQA: RoutingRule(
        primary: .cloudFn(name: "bereanBusinessQA"),
        fallback: .cloudFn(name: "bereanBibleQA"),
        emergency: .local,
        preferStructuredOutput: true,
        requiresRAG: false,
        note: "Claude moral frame + OpenAI structured step plan."
    ),

    // Note summary: OpenAI structured JSON summary + Claude for reflection prompt
    .noteSummary: RoutingRule(
        primary: .cloudFn(name: "bereanNoteSummary"),
        fallback: .cloudFn(name: "bereanBibleQA"),
        emergency: .local,
        preferStructuredOutput: true,
        requiresRAG: false,
        note: "OpenAI for structured JSON extraction, Claude for reflection prompt."
    ),

    // Scripture extraction: Vertex text classifier, fast
    .scriptureExtraction: RoutingRule(
        primary: .cloudFn(name: "bereanScriptureExtract"),
        fallback: .local,
        emergency: .local,
        preferStructuredOutput: true,
        requiresRAG: false,
        note: "Pattern extraction + Vertex classifier. Falls back to regex locally."
    ),

    // Post assist (tone/intent): OpenAI structured suggestions, must be fast
    .postAssist: RoutingRule(
        primary: .cloudFn(name: "bereanPostAssist"),
        fallback: .local,
        emergency: .local,
        preferStructuredOutput: true,
        requiresRAG: false,
        note: "OpenAI for deterministic JSON rewrite suggestions."
    ),

    // Comment assist: OpenAI structured anti-harassment suggestions
    .commentAssist: RoutingRule(
        primary: .cloudFn(name: "bereanCommentAssist"),
        fallback: .local,
        emergency: .local,
        preferStructuredOutput: true,
        requiresRAG: false,
        note: "OpenAI structured rewrite. Must be <800ms to not block UX."
    ),

    // DM safety: Vertex safety + OpenAI structured classifier fallback. NEVER fail-open.
    .dmSafetyScan: RoutingRule(
        primary: .cloudFn(name: "bereanDMSafety"),
        fallback: .local,      // local heuristics (MessageSafetyGateway) — still blocks
        emergency: .local,
        preferStructuredOutput: true,
        requiresRAG: false,
        note: "Safety-critical. Vertex safety API + pattern engine. Never fail-open."
    ),

    // Media safety: Vertex Vision SafeSearch
    .mediaSafetyScan: RoutingRule(
        primary: .cloudFn(name: "bereanMediaSafety"),
        fallback: .local,
        emergency: .local,
        preferStructuredOutput: true,
        requiresRAG: false,
        note: "Vertex Vision multimodal safety. Async deep scan post-allow."
    ),

    // Feed explainer: fast, no RAG needed
    .feedExplainer: RoutingRule(
        primary: .cloudFn(name: "bereanFeedExplainer"),
        fallback: .local,
        emergency: .local,
        preferStructuredOutput: true,
        requiresRAG: false,
        note: "Short 1-sentence explanation of why a post was shown."
    ),

    // Notification text: OpenAI — must produce clean, non-bait language
    .notificationText: RoutingRule(
        primary: .cloudFn(name: "bereanNotificationText"),
        fallback: .local,
        emergency: .local,
        preferStructuredOutput: true,
        requiresRAG: false,
        note: "No engagement-bait, no scarcity hooks, no trending pulls."
    ),

    // Report triage: Claude for nuanced safety review
    .reportTriage: RoutingRule(
        primary: .cloudFn(name: "bereanReportTriage"),
        fallback: .local,
        emergency: .local,
        preferStructuredOutput: true,
        requiresRAG: false,
        note: "Claude for nuanced harm assessment. Safety-critical."
    ),

    // Ranking labels: OpenAI structured labels (addiction-risk, diversity, goal-match)
    .rankingLabels: RoutingRule(
        primary: .cloudFn(name: "bereanRankingLabels"),
        fallback: .local,
        emergency: .local,
        preferStructuredOutput: true,
        requiresRAG: false,
        note: "Addiction-risk downranking if signals detected. Do not optimize for session length."
    ),
]

// MARK: - Circuit Breaker

/// Per-provider failure tracker. After `failureThreshold` consecutive failures,
/// the provider is marked unavailable for `cooldownSeconds`.
actor CircuitBreaker {
    private var failureCounts: [String: Int] = [:]
    private var openUntil: [String: Date] = [:]
    private let failureThreshold = 3
    private let cooldownSeconds: TimeInterval = 60

    func isOpen(for provider: String) -> Bool {
        if let until = openUntil[provider], Date() < until { return true }
        return false
    }

    func recordSuccess(for provider: String) {
        failureCounts[provider] = 0
        openUntil.removeValue(forKey: provider)
    }

    func recordFailure(for provider: String) {
        let count = (failureCounts[provider] ?? 0) + 1
        failureCounts[provider] = count
        if count >= failureThreshold {
            openUntil[provider] = Date().addingTimeInterval(cooldownSeconds)
            dlog("⚡️ [CircuitBreaker] Provider '\(provider)' OPEN for \(cooldownSeconds)s after \(count) failures")
        }
    }
}

// MARK: - Orchestrator Request / Response

struct OrchestratorRequest {
    let taskType: BereanTaskType
    let userPrompt: String
    let systemContext: String?
    let retrievedContext: [String]     // RAG-retrieved passages (pre-fetched by caller)
    let maxTokens: Int
    let userId: String?
    let idempotencyKey: String?

    init(
        taskType: BereanTaskType,
        userPrompt: String,
        systemContext: String? = nil,
        retrievedContext: [String] = [],
        maxTokens: Int = 512,
        userId: String? = nil,
        idempotencyKey: String? = nil
    ) {
        self.taskType = taskType
        self.userPrompt = userPrompt
        self.systemContext = systemContext
        self.retrievedContext = retrievedContext
        self.maxTokens = maxTokens
        self.userId = userId
        self.idempotencyKey = idempotencyKey
    }
}

struct OrchestratorResponse {
    let content: String
    let provider: String
    let modelVersion: String
    let latencyMs: Int
    let fromCache: Bool
    let citations: [String]
    let taskType: BereanTaskType
}

// MARK: - BereanOrchestrator

/// Central AI routing singleton.
/// All AI requests in the app must go through here — not directly to providers.
@MainActor
final class BereanOrchestrator {
    static let shared = BereanOrchestrator()

    private let functions = Functions.functions()
    private let circuitBreaker = CircuitBreaker()
    private var responseCache: [String: (response: OrchestratorResponse, expiry: Date)] = [:]
    private let cacheExpirySeconds: TimeInterval = 300  // 5 min

    private init() {}

    // MARK: - Primary Route

    /// Route a request to the appropriate AI provider.
    /// Returns a response or throws — never returns silently incorrect content.
    ///
    /// For safety-critical tasks (isSafetyCritical == true), throwing is the correct
    /// behavior on failure — the caller must handle it as a block, not a pass-through.
    func route(_ request: OrchestratorRequest) async throws -> OrchestratorResponse {
        let start = Date()

        // Check cache for non-safety tasks
        if !request.taskType.isSafetyCritical {
            let cacheKey = "\(request.taskType.rawValue):\(request.userPrompt.hashValue)"
            if let cached = responseCache[cacheKey], cached.expiry > Date() {
                return cached.response
            }
        }

        guard let rule = bereanRoutingTable[request.taskType] else {
            throw OrchestratorError.noRoutingRule(request.taskType)
        }

        // Assemble prompt with RAG context
        let assembledPrompt = assemblePrompt(request: request, rule: rule)

        // Try primary → fallback → emergency
        var lastError: Error?
        for providerKind in [rule.primary, rule.fallback, rule.emergency] {
            let providerKey = providerKeyString(providerKind)
            let isCircuitOpen = await circuitBreaker.isOpen(for: providerKey)
            if isCircuitOpen && providerKind != rule.emergency {
                dlog("⚡️ [Orchestrator] Circuit open for \(providerKey) — trying next")
                continue
            }

            do {
                let result = try await callProvider(
                    kind: providerKind,
                    prompt: assembledPrompt,
                    request: request
                )
                await circuitBreaker.recordSuccess(for: providerKey)

                let latency = Int(Date().timeIntervalSince(start) * 1000)
                let response = OrchestratorResponse(
                    content: result.text,
                    provider: result.provider,
                    modelVersion: result.modelVersion,
                    latencyMs: latency,
                    fromCache: false,
                    citations: result.citations,
                    taskType: request.taskType
                )

                // Cache non-safety responses
                if !request.taskType.isSafetyCritical {
                    let key = "\(request.taskType.rawValue):\(request.userPrompt.hashValue)"
                    responseCache[key] = (response, Date().addingTimeInterval(cacheExpirySeconds))
                }

                return response
            } catch {
                await circuitBreaker.recordFailure(for: providerKey)
                lastError = error
                dlog("⚠️ [Orchestrator] Provider \(providerKey) failed: \(error.localizedDescription)")

                // Safety-critical: never fall through to emergency pass — emergency must still block
                if request.taskType.isSafetyCritical && providerKind == rule.emergency {
                    throw OrchestratorError.safetyProviderUnavailable(request.taskType)
                }
            }
        }

        throw lastError ?? OrchestratorError.allProvidersFailed(request.taskType)
    }

    // MARK: - Provider Call

    private struct ProviderResult {
        let text: String
        let provider: String
        let modelVersion: String
        let citations: [String]
    }

    private func callProvider(
        kind: RoutingRule.ProviderKind,
        prompt: String,
        request: OrchestratorRequest
    ) async throws -> ProviderResult {
        switch kind {
        case .cloudFn(let fnName):
            return try await callCloudFunction(
                name: fnName,
                prompt: prompt,
                request: request
            )
        case .local:
            return localHeuristicFallback(request: request)
        default:
            // vertex / openAI / claude are proxied through Cloud Functions for security
            // (no credentials on device). Use a generic proxy function name.
            return try await callCloudFunction(
                name: "bereanGenericProxy",
                prompt: prompt,
                request: request
            )
        }
    }

    private func callCloudFunction(
        name: String,
        prompt: String,
        request: OrchestratorRequest
    ) async throws -> ProviderResult {
        let data: [String: Any] = [
            "taskType": request.taskType.rawValue,
            "prompt": prompt,
            "maxTokens": request.maxTokens,
            "userId": request.userId as Any,
            "idempotencyKey": request.idempotencyKey as Any
        ]

        let result = try await functions.httpsCallable(name).call(data)
        guard let response = result.data as? [String: Any] else {
            throw OrchestratorError.invalidResponse(name)
        }

        return ProviderResult(
            text: response["content"] as? String ?? "",
            provider: response["provider"] as? String ?? name,
            modelVersion: response["modelVersion"] as? String ?? "unknown",
            citations: response["citations"] as? [String] ?? []
        )
    }

    private func localHeuristicFallback(request: OrchestratorRequest) -> ProviderResult {
        // For safety tasks: return an explicit block signal (conservative)
        // For content tasks: return a graceful degradation message
        let text: String
        if request.taskType.isSafetyCritical {
            text = "__SAFETY_BLOCK__"  // Caller must interpret this as block/hold
        } else {
            text = "Berean AI is temporarily unavailable. Please try again in a moment."
        }
        return ProviderResult(
            text: text,
            provider: "local_heuristic",
            modelVersion: "berean-heuristic-v1",
            citations: []
        )
    }

    // MARK: - Prompt Assembly

    /// Assembles the full prompt including:
    /// - Task-specific system context
    /// - RAG-retrieved passages (labeled as [RETRIEVED CONTEXT])
    /// - The user's actual query
    /// - Citation requirement reminder for biblical tasks
    private func assemblePrompt(request: OrchestratorRequest, rule: RoutingRule) -> String {
        var parts: [String] = []

        if let sys = request.systemContext {
            parts.append("[SYSTEM]\n\(sys)")
        }

        if !request.retrievedContext.isEmpty {
            let ctx = request.retrievedContext.enumerated().map { i, passage in
                "[\(i + 1)] \(passage)"
            }.joined(separator: "\n")
            parts.append("[RETRIEVED CONTEXT — use these as citations, do not fabricate]\n\(ctx)")
        }

        if rule.requiresRAG {
            parts.append("[CITATION REQUIREMENT] Every factual or biblical claim MUST include an inline citation from the retrieved context. If no relevant context was retrieved, say \"I'm not certain\" and ask a clarifying question rather than guessing.")
        }

        parts.append("[USER QUERY]\n\(request.userPrompt)")

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Helpers

    private func providerKeyString(_ kind: RoutingRule.ProviderKind) -> String {
        switch kind {
        case .vertex:              return "vertex"
        case .openAI:              return "openai"
        case .claude:              return "claude"
        case .local:               return "local"
        case .cloudFn(let name):   return "cloudFn:\(name)"
        }
    }
}

// MARK: - Errors

enum OrchestratorError: LocalizedError {
    case noRoutingRule(BereanTaskType)
    case allProvidersFailed(BereanTaskType)
    case safetyProviderUnavailable(BereanTaskType)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .noRoutingRule(let t):            return "No routing rule for task: \(t.rawValue)"
        case .allProvidersFailed(let t):       return "All providers failed for task: \(t.rawValue)"
        case .safetyProviderUnavailable(let t): return "Safety provider unavailable for: \(t.rawValue). Content blocked."
        case .invalidResponse(let fn):         return "Invalid response from function: \(fn)"
        }
    }
}

// MARK: - Convenience Extensions

extension BereanOrchestrator {

    // MARK: Church Notes

    /// Summarize church note content into structured output
    func summarizeChurchNote(content: String, userId: String) async throws -> String {
        let request = OrchestratorRequest(
            taskType: .noteSummary,
            userPrompt: content,
            systemContext: "Summarize this church sermon note. Output JSON with keys: summary (string, max 3 sentences), keyScriptures ([string] verse references), reflectionPrompt (string, 1 personal application question).",
            maxTokens: 400,
            userId: userId
        )
        let response = try await route(request)
        return response.content
    }

    // MARK: Post Assist

    /// Get tone rewrite suggestions for a post draft
    func getPostToneSuggestions(draft: String, userId: String) async throws -> String {
        let request = OrchestratorRequest(
            taskType: .postAssist,
            userPrompt: draft,
            systemContext: "You are a thoughtful faith-community writing assistant. Review this post draft for tone. Output JSON: { toneScore: 0-1, issues: [string], suggestedRewrite: string or null }. Be encouraging, not harsh.",
            maxTokens: 300,
            userId: userId
        )
        let response = try await route(request)
        return response.content
    }

    // MARK: Comment Assist

    /// Get anti-harassment rewrite suggestion for a comment
    func getCommentRewriteSuggestion(draft: String, context: String, userId: String) async throws -> String {
        let request = OrchestratorRequest(
            taskType: .commentAssist,
            userPrompt: "Post context: \(context)\n\nComment draft: \(draft)",
            systemContext: "Review this comment for harassment, rudeness, or divisiveness. Output JSON: { isHarassing: bool, suggestedRewrite: string or null, reason: string }.",
            maxTokens: 200,
            userId: userId
        )
        let response = try await route(request)
        return response.content
    }

    // MARK: Feed Explainer

    /// Explain why a post was shown to the user (one sentence)
    func explainFeedPost(postSummary: String, userGoals: [String], userId: String) async throws -> String {
        let request = OrchestratorRequest(
            taskType: .feedExplainer,
            userPrompt: "Post: \(postSummary)\nUser goals: \(userGoals.joined(separator: ", "))",
            systemContext: "Explain in one sentence why this post was shown. Be honest. Do not use engagement-bait language. Output: { explanation: string }",
            maxTokens: 80,
            userId: userId
        )
        let response = try await route(request)
        return response.content
    }
}
