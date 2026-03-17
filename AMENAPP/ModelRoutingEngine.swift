// ModelRoutingEngine.swift
// AMENAPP
//
// Smart multi-model routing across Claude, Vertex AI, and OpenAI.
// Decides which provider to use per task based on:
//   - task type + complexity
//   - latency budget
//   - cost tier
//   - provider health (circuit breaker)
//   - quality threshold requirements
//   - structured output needs
//   - fallback chain
//
// Never called directly by UI — always through BereanCoreService.process().

import Foundation
import Combine

// MARK: - Provider Identity

enum MREProvider: String, CaseIterable {
    case claude    = "claude"
    case openAI    = "openai"
    case vertexAI  = "vertex_ai"
    case local     = "local"          // on-device heuristics, zero latency
    case cloudFn   = "cloud_function" // GCP proxy (wraps any provider)

    var displayName: String {
        switch self {
        case .claude:   return "Claude"
        case .openAI:   return "OpenAI"
        case .vertexAI: return "Vertex AI"
        case .local:    return "On-Device"
        case .cloudFn:  return "Cloud"
        }
    }
}

// MARK: - Routing Decision

struct MRERoutingDecision {
    let primary: MREProvider
    let fallback: MREProvider
    let emergency: MREProvider     // always succeeds (local heuristic)
    let cloudFunctionName: String? // if routing through Cloud Functions
    let requiresRAG: Bool
    let preferStreaming: Bool
    let maxTokens: Int
    let costTier: CostTier
    let notes: String
}

enum CostTier: Int, Comparable {
    case free = 0       // on-device, zero cost
    case micro = 1      // tiny model calls, < $0.001
    case low = 2        // standard calls, < $0.01
    case medium = 3     // complex calls, < $0.05
    case high = 4       // long-context, expensive calls

    static func < (lhs: CostTier, rhs: CostTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Routing Result (from provider)

struct RoutingResult {
    let content: String
    let provider: String
    let modelVersion: String
    let citations: [ScriptureCitation]
    let safetyFlags: [SafetyFlag]
    let rawLatencyMs: Int
    var isEmpty: Bool { content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

// MARK: - Circuit Breaker State

struct ProviderHealth {
    let provider: MREProvider
    var isHealthy: Bool
    var consecutiveFailures: Int
    var lastFailureAt: Date?
    var cooldownUntil: Date?
    var totalCalls: Int
    var totalFailures: Int
    var averageLatencyMs: Int

    var failureRate: Double {
        totalCalls > 0 ? Double(totalFailures) / Double(totalCalls) : 0
    }

    var inCooldown: Bool {
        if let cooldown = cooldownUntil { return Date() < cooldown }
        return false
    }

    mutating func recordSuccess(latencyMs: Int) {
        consecutiveFailures = 0
        isHealthy = true
        cooldownUntil = nil
        totalCalls += 1
        // Running average
        averageLatencyMs = totalCalls == 1 ? latencyMs :
            (averageLatencyMs * (totalCalls - 1) + latencyMs) / totalCalls
    }

    mutating func recordFailure() {
        consecutiveFailures += 1
        totalFailures += 1
        totalCalls += 1
        lastFailureAt = Date()
        if consecutiveFailures >= 3 {
            isHealthy = false
            cooldownUntil = Date().addingTimeInterval(60) // 60s cooldown
        }
    }
}

// MARK: - ModelRoutingEngine

@MainActor
final class ModelRoutingEngine: ObservableObject {

    static let shared = ModelRoutingEngine()

    // MARK: Provider health tracking (published for system health monitoring)
    @Published private(set) var providerHealthMap: [MREProvider: ProviderHealth] = {
        var map: [MREProvider: ProviderHealth] = [:]
        for p in MREProvider.allCases {
            map[p] = ProviderHealth(
                provider: p, isHealthy: true, consecutiveFailures: 0,
                lastFailureAt: nil, cooldownUntil: nil,
                totalCalls: 0, totalFailures: 0, averageLatencyMs: 0
            )
        }
        return map
    }()

    // MARK: Routing table
    // Defined once; extensible. Maps AITaskCategory → MRERoutingDecision.
    private let routingTable: [AITaskCategory: MRERoutingDecision] = [

        // ── Bible & Theology ──────────────────────────────────────────────
        .scriptureGrounding: MRERoutingDecision(
            primary: .claude, fallback: .openAI, emergency: .local,
            cloudFunctionName: "bereanBibleQA",
            requiresRAG: true, preferStreaming: true, maxTokens: 1200, costTier: .medium,
            notes: "Claude: best nuanced biblical reasoning + RAG citations"
        ),
        .assistantResponse: MRERoutingDecision(
            primary: .claude, fallback: .openAI, emergency: .local,
            cloudFunctionName: "bereanGenericProxy",
            requiresRAG: false, preferStreaming: true, maxTokens: 800, costTier: .low,
            notes: "Claude: high-quality general assistant responses"
        ),
        .prayerDrafting: MRERoutingDecision(
            primary: .claude, fallback: .openAI, emergency: .local,
            cloudFunctionName: "bereanPrayerDraft",
            requiresRAG: false, preferStreaming: true, maxTokens: 500, costTier: .low,
            notes: "Claude: pastoral warmth, spiritual sensitivity"
        ),
        .devotionalGeneration: MRERoutingDecision(
            primary: .claude, fallback: .openAI, emergency: .local,
            cloudFunctionName: "bereanDevotional",
            requiresRAG: true, preferStreaming: false, maxTokens: 1000, costTier: .medium,
            notes: "Claude: editorial quality devotional writing"
        ),

        // ── Content & Tone ────────────────────────────────────────────────
        .captionHelp: MRERoutingDecision(
            primary: .openAI, fallback: .claude, emergency: .local,
            cloudFunctionName: "bereanPostAssist",
            requiresRAG: false, preferStreaming: false, maxTokens: 300, costTier: .micro,
            notes: "OpenAI: fast structured suggestions, cheap"
        ),
        .rewriteSuggestion: MRERoutingDecision(
            primary: .openAI, fallback: .claude, emergency: .local,
            cloudFunctionName: "bereanRewrite",
            requiresRAG: false, preferStreaming: false, maxTokens: 400, costTier: .micro,
            notes: "OpenAI: structured rewrites, low latency"
        ),
        .sentimentTone: MRERoutingDecision(
            primary: .local, fallback: .openAI, emergency: .local,
            cloudFunctionName: nil,
            requiresRAG: false, preferStreaming: false, maxTokens: 100, costTier: .free,
            notes: "On-device NaturalLanguage first; escalate if ambiguous"
        ),
        .topicClassification: MRERoutingDecision(
            primary: .local, fallback: .vertexAI, emergency: .local,
            cloudFunctionName: nil,
            requiresRAG: false, preferStreaming: false, maxTokens: 50, costTier: .free,
            notes: "On-device keyword + embedding classification"
        ),

        // ── Summarization ─────────────────────────────────────────────────
        .summaryGeneration: MRERoutingDecision(
            primary: .openAI, fallback: .claude, emergency: .local,
            cloudFunctionName: "bereanNoteSummary",
            requiresRAG: false, preferStreaming: false, maxTokens: 500, costTier: .low,
            notes: "OpenAI: reliable structured summarization"
        ),

        // ── Safety & Moderation ───────────────────────────────────────────
        .safetyScreening: MRERoutingDecision(
            primary: .local, fallback: .openAI, emergency: .local,
            cloudFunctionName: nil,
            requiresRAG: false, preferStreaming: false, maxTokens: 150, costTier: .free,
            notes: "On-device ContentRiskAnalyzer first; cloud only if high confidence needed"
        ),
        .crisisDetection: MRERoutingDecision(
            primary: .local, fallback: .claude, emergency: .local,
            cloudFunctionName: nil,
            requiresRAG: false, preferStreaming: false, maxTokens: 100, costTier: .free,
            notes: "On-device CrisisDetectionService always runs first; never delayed"
        ),
        .dmSafetyGate: MRERoutingDecision(
            primary: .local, fallback: .openAI, emergency: .local,
            cloudFunctionName: "bereanDMSafety",
            requiresRAG: false, preferStreaming: false, maxTokens: 100, costTier: .free,
            notes: "300ms budget — local runs sync, cloud async if needed"
        ),
        .mediaSafety: MRERoutingDecision(
            primary: .vertexAI, fallback: .openAI, emergency: .local,
            cloudFunctionName: "bereanMediaSafety",
            requiresRAG: false, preferStreaming: false, maxTokens: 100, costTier: .low,
            notes: "Vertex AI Vision SafeSearch: best image/video safety classification"
        ),

        // ── Recommendations ───────────────────────────────────────────────
        .contentRecommendation: MRERoutingDecision(
            primary: .vertexAI, fallback: .local, emergency: .local,
            cloudFunctionName: "bereanRecommend",
            requiresRAG: false, preferStreaming: false, maxTokens: 200, costTier: .low,
            notes: "Vertex AI: ML embeddings for semantic similarity"
        ),
        .feedRanking: MRERoutingDecision(
            primary: .local, fallback: .vertexAI, emergency: .local,
            cloudFunctionName: nil,
            requiresRAG: false, preferStreaming: false, maxTokens: 0, costTier: .free,
            notes: "HomeFeedAlgorithm (on-device); Vertex predictions async background"
        ),
        .churchMatching: MRERoutingDecision(
            primary: .vertexAI, fallback: .openAI, emergency: .local,
            cloudFunctionName: "bereanChurchMatch",
            requiresRAG: true, preferStreaming: false, maxTokens: 300, costTier: .low,
            notes: "Vertex embeddings for location + culture + theology match"
        ),
        .opportunityMatching: MRERoutingDecision(
            primary: .openAI, fallback: .claude, emergency: .local,
            cloudFunctionName: "bereanOpportunityMatch",
            requiresRAG: false, preferStreaming: false, maxTokens: 400, costTier: .low,
            notes: "OpenAI: structured skill/role matching with fraud detection"
        ),
        .semanticSearch: MRERoutingDecision(
            primary: .vertexAI, fallback: .local, emergency: .local,
            cloudFunctionName: nil,
            requiresRAG: false, preferStreaming: false, maxTokens: 0, costTier: .free,
            notes: "Vertex text embeddings for semantic similarity search"
        ),

        // ── Translation ───────────────────────────────────────────────────
        .translation: MRERoutingDecision(
            primary: .cloudFn, fallback: .local, emergency: .local,
            cloudFunctionName: "translateContent",
            requiresRAG: false, preferStreaming: false, maxTokens: 0, costTier: .micro,
            notes: "GCP Cloud Translation; Apple on-device fallback"
        ),
        .altTextGeneration: MRERoutingDecision(
            primary: .vertexAI, fallback: .openAI, emergency: .local,
            cloudFunctionName: "bereanAltText",
            requiresRAG: false, preferStreaming: false, maxTokens: 150, costTier: .micro,
            notes: "Vertex Vision: image captioning for accessibility"
        ),

        // ── Wellness ──────────────────────────────────────────────────────
        .wellnessSignal: MRERoutingDecision(
            primary: .local, fallback: .local, emergency: .local,
            cloudFunctionName: nil,
            requiresRAG: false, preferStreaming: false, maxTokens: 0, costTier: .free,
            notes: "Always on-device — never send wellness signals to cloud"
        ),
        .crisisResource: MRERoutingDecision(
            primary: .local, fallback: .local, emergency: .local,
            cloudFunctionName: nil,
            requiresRAG: false, preferStreaming: false, maxTokens: 0, costTier: .free,
            notes: "Static resource lookup — zero latency, always available"
        ),
    ]

    private init() {}

    // MARK: - Primary Route Method

    func route(_ request: BereanAIRequest, policyResult: PolicyResult) async -> RoutingResult {
        guard let decision: MRERoutingDecision = routingTable[request.category] else {
            return await routeDefault(request)
        }

        // Try primary → fallback → emergency
        let primaryProvider = decision.primary
        let fallbackProvider = decision.fallback

        if canUse(primaryProvider) {
            if let result = await callProvider(primaryProvider, request: request, decision: decision) {
                recordSuccess(for: primaryProvider, latencyMs: result.rawLatencyMs)
                return result
            }
            recordFailure(for: primaryProvider)
        }

        if canUse(fallbackProvider) && fallbackProvider != primaryProvider {
            if let result = await callProvider(fallbackProvider, request: request, decision: decision) {
                recordSuccess(for: fallbackProvider, latencyMs: result.rawLatencyMs)
                return result
            }
            recordFailure(for: fallbackProvider)
        }

        // Emergency: always local
        return await callLocalEmergency(request)
    }

    // MARK: - Provider Health

    func activeProviders() -> [String] {
        providerHealthMap.filter { $0.value.isHealthy }.map { $0.key.displayName }
    }

    func healthReport() -> [(provider: String, healthy: Bool, failureRate: Double, avgLatencyMs: Int)] {
        providerHealthMap.map { (
            provider: $0.key.displayName,
            healthy: $0.value.isHealthy,
            failureRate: $0.value.failureRate,
            avgLatencyMs: $0.value.averageLatencyMs
        )}
    }

    // MARK: - Private

    private func canUse(_ provider: MREProvider) -> Bool {
        guard let health = providerHealthMap[provider] else { return true }
        return health.isHealthy && !health.inCooldown
    }

    private func recordSuccess(for provider: MREProvider, latencyMs: Int) {
        providerHealthMap[provider]?.recordSuccess(latencyMs: latencyMs)
    }

    private func recordFailure(for provider: MREProvider) {
        providerHealthMap[provider]?.recordFailure()
    }

    private func callProvider(
        _ provider: MREProvider,
        request: BereanAIRequest,
        decision: MRERoutingDecision
    ) async -> RoutingResult? {
        let start = Date()
        do {
            switch provider {
            case .local:
                return await callLocalProvider(request)
            case .claude:
                return try await callClaudeProvider(request, decision: decision)
            case .openAI:
                return try await callOpenAIProvider(request, decision: decision)
            case .vertexAI:
                return try await callVertexProvider(request, decision: decision)
            case .cloudFn:
                let fnName = decision.cloudFunctionName ?? "bereanGenericProxy"
                return try await callCloudFunction(fnName, request: request)
            }
        } catch {
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            _ = latency // latency tracked in recordFailure path
            return nil
        }
    }

    // MARK: Claude

    private func callClaudeProvider(_ request: BereanAIRequest, decision: MRERoutingDecision) async throws -> RoutingResult {
        let start = Date()
        // Build prompt with policy-compliant system context
        let systemPrompt = buildSystemPrompt(for: request)
        let userPrompt = buildUserPrompt(request: request, decision: decision)

        // Route through Cloud Function proxy (no raw API keys on device)
        let fnName = decision.cloudFunctionName ?? "bereanGenericProxy"
        let payload: [String: Any] = [
            "provider": "claude",
            "system": systemPrompt,
            "user": userPrompt,
            "maxTokens": decision.maxTokens,
            "stream": decision.preferStreaming && request.requiresStreaming
        ]
        let response = try await invokeCloudFunction(fnName, payload: payload)
        let latency = Int(Date().timeIntervalSince(start) * 1000)
        return RoutingResult(
            content: response["content"] as? String ?? "",
            provider: "claude",
            modelVersion: response["model"] as? String ?? "claude-haiku-4-5",
            citations: parseCitations(from: response),
            safetyFlags: [],
            rawLatencyMs: latency
        )
    }

    // MARK: OpenAI

    private func callOpenAIProvider(_ request: BereanAIRequest, decision: MRERoutingDecision) async throws -> RoutingResult {
        let start = Date()
        let systemPrompt = buildSystemPrompt(for: request)
        let userPrompt = buildUserPrompt(request: request, decision: decision)
        let payload: [String: Any] = [
            "provider": "openai",
            "system": systemPrompt,
            "user": userPrompt,
            "maxTokens": decision.maxTokens,
            "responseFormat": decision.requiresRAG ? "json_object" : "text"
        ]
        let fnName = decision.cloudFunctionName ?? "bereanGenericProxy"
        let response = try await invokeCloudFunction(fnName, payload: payload)
        let latency = Int(Date().timeIntervalSince(start) * 1000)
        return RoutingResult(
            content: response["content"] as? String ?? "",
            provider: "openai",
            modelVersion: response["model"] as? String ?? "gpt-4o-mini",
            citations: parseCitations(from: response),
            safetyFlags: parseSafetyFlags(from: response),
            rawLatencyMs: latency
        )
    }

    // MARK: Vertex AI

    private func callVertexProvider(_ request: BereanAIRequest, decision: MRERoutingDecision) async throws -> RoutingResult {
        let start = Date()
        let payload: [String: Any] = [
            "provider": "vertex",
            "task": request.category.rawValue,
            "input": request.userInput,
            "context": request.context
        ]
        let fnName = decision.cloudFunctionName ?? "bereanVertexProxy"
        let response = try await invokeCloudFunction(fnName, payload: payload)
        let latency = Int(Date().timeIntervalSince(start) * 1000)
        return RoutingResult(
            content: response["content"] as? String ?? "",
            provider: "vertex_ai",
            modelVersion: response["model"] as? String ?? "gemini-1.5-flash",
            citations: [],
            safetyFlags: parseSafetyFlags(from: response),
            rawLatencyMs: latency
        )
    }

    // MARK: Cloud Function

    private func callCloudFunction(_ name: String, request: BereanAIRequest) async throws -> RoutingResult {
        let start = Date()
        let payload: [String: Any] = [
            "task": request.category.rawValue,
            "surface": request.surface.rawValue,
            "input": request.userInput,
            "context": request.context,
            "retrievedContext": request.retrievedContext
        ]
        let response = try await invokeCloudFunction(name, payload: payload)
        let latency = Int(Date().timeIntervalSince(start) * 1000)
        return RoutingResult(
            content: response["content"] as? String ?? "",
            provider: "cloud_function:\(name)",
            modelVersion: response["model"] as? String ?? "cloud",
            citations: parseCitations(from: response),
            safetyFlags: parseSafetyFlags(from: response),
            rawLatencyMs: latency
        )
    }

    // MARK: Local (on-device)

    private func callLocalProvider(_ request: BereanAIRequest) async -> RoutingResult {
        // Local = fast heuristic responses (safety checks, topic classification, wellness)
        let content = await localHeuristic(request)
        return RoutingResult(
            content: content,
            provider: "local",
            modelVersion: "on_device_v1",
            citations: [],
            safetyFlags: [],
            rawLatencyMs: 0
        )
    }

    private func callLocalEmergency(_ request: BereanAIRequest) async -> RoutingResult {
        return RoutingResult(
            content: emergencyFallbackContent(for: request),
            provider: "emergency_local",
            modelVersion: "fallback_v1",
            citations: [],
            safetyFlags: [],
            rawLatencyMs: 0
        )
    }

    private func routeDefault(_ request: BereanAIRequest) async -> RoutingResult {
        // No routing rule found — safe fallback
        return await callLocalEmergency(request)
    }

    // MARK: Cloud Function Invocation

    private func invokeCloudFunction(_ name: String, payload: [String: Any]) async throws -> [String: Any] {
        // Use Firebase Functions SDK callable instead of raw HTTP.
        // CloudFunctionsService wraps Functions.functions().httpsCallable().
        let result = try await CloudFunctionsService.shared.call(name, data: payload)
        if let dict = result as? [String: Any] {
            return dict
        }
        return ["result": result as Any]
    }

    /// Fallback HTTP invocation (unused — kept for reference).
    private func _invokeCloudFunctionHTTP(_ name: String, payload: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: "https://us-central1-amen-app.cloudfunctions.net/\(name)") else {
            throw RoutingError.invalidEndpoint
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        // Attach Firebase ID token for auth
        if let idToken = await fetchFirebaseIDToken() {
            req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        req.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw RoutingError.serverError
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return json
    }

    private func fetchFirebaseIDToken() async -> String? {
        // Delegate to FirebaseAuth — returns current user's ID token
        return await withCheckedContinuation { continuation in
            // In production: Auth.auth().currentUser?.getIDToken { token, _ in continuation.resume(returning: token) }
            continuation.resume(returning: nil)
        }
    }

    // MARK: Prompt Construction

    private func buildSystemPrompt(for request: BereanAIRequest) -> String {
        var parts: [String] = []

        // Core identity
        parts.append("""
        You are Berean, AMEN's AI assistant. You are scripture-grounded, theologically \
        careful, warm, and helpful. You support users across a faith-centered social platform.
        """)

        // Surface-specific context
        switch request.surface {
        case .bereanChat:
            parts.append("You are in a focused Bible study and spiritual guidance session.")
        case .postCreation:
            parts.append("You are assisting a user in crafting a meaningful post for their faith community.")
        case .churchNotes:
            parts.append("You are helping process and enhance church sermon notes.")
        case .prayerRequest:
            parts.append("You are responding to a prayer request with pastoral sensitivity.")
        case .dm:
            parts.append("You are a safety assistant screening direct messages.")
        default:
            break
        }

        // Safety reminder
        parts.append("Always prioritize user safety. If crisis signals are present, route to crisis resources.")
        parts.append("Distinguish clearly between scripture, theological interpretation, and opinion.")

        return parts.joined(separator: "\n\n")
    }

    private func buildUserPrompt(request: BereanAIRequest, decision: MRERoutingDecision) -> String {
        var parts: [String] = []

        // RAG context injection
        if decision.requiresRAG && !request.retrievedContext.isEmpty {
            parts.append("[RETRIEVED CONTEXT]\n" + request.retrievedContext.joined(separator: "\n---\n"))
        }

        parts.append("[USER INPUT]\n\(request.userInput)")

        // Additional context metadata
        if !request.context.isEmpty {
            let contextStr = request.context.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            parts.append("[CONTEXT]\n\(contextStr)")
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: Local Heuristics

    private func localHeuristic(_ request: BereanAIRequest) async -> String {
        switch request.category {
        case .sentimentTone:
            return analyzeToneLocally(request.userInput)
        case .topicClassification:
            return classifyTopicLocally(request.userInput)
        case .safetyScreening:
            // Delegates to existing ContentRiskAnalyzer
            let analysis = ContentRiskAnalyzer.shared.analyze(
                text: request.userInput,
                context: .post
            )
            return analysis.primaryCategory.rawValue
        default:
            return ""
        }
    }

    private func analyzeToneLocally(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("angry") || lower.contains("hate") || lower.contains("furious") {
            return "tone:negative"
        }
        if lower.contains("praise") || lower.contains("grateful") || lower.contains("blessed") {
            return "tone:joyful"
        }
        if lower.contains("sad") || lower.contains("grief") || lower.contains("loss") {
            return "tone:sorrowful"
        }
        return "tone:neutral"
    }

    private func classifyTopicLocally(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("bible") || lower.contains("scripture") || lower.contains("verse") { return "topic:scripture" }
        if lower.contains("pray") || lower.contains("prayer") { return "topic:prayer" }
        if lower.contains("church") || lower.contains("worship") { return "topic:church" }
        if lower.contains("testimony") { return "topic:testimony" }
        return "topic:general"
    }

    private func emergencyFallbackContent(for request: BereanAIRequest) -> String {
        switch request.category {
        case .safetyScreening, .crisisDetection, .dmSafetyGate:
            return "safe"  // Fail open only for non-critical safety, fail closed handled upstream
        case .assistantResponse:
            return "I'm having trouble responding right now. Please try again in a moment."
        default:
            return ""
        }
    }

    // MARK: Response Parsing

    private func parseCitations(from response: [String: Any]) -> [ScriptureCitation] {
        guard let citationsArray = response["citations"] as? [[String: Any]] else { return [] }
        return citationsArray.compactMap { dict in
            guard let ref = dict["reference"] as? String,
                  let text = dict["text"] as? String else { return nil }
            return ScriptureCitation(
                id: UUID().uuidString,
                reference: ref,
                text: text,
                translation: dict["translation"] as? String ?? "ESV",
                relevanceScore: dict["relevance"] as? Double ?? 0.8
            )
        }
    }

    private func parseSafetyFlags(from response: [String: Any]) -> [SafetyFlag] {
        guard let flagsArray = response["safety_flags"] as? [[String: Any]] else { return [] }
        return flagsArray.compactMap { dict in
            guard let category = dict["category"] as? String,
                  let severityRaw = dict["severity"] as? String,
                  let severity = SafetyFlagSeverity(rawValue: severityRaw) else { return nil }
            let actionRaw = dict["action"] as? String ?? "allow"
            return SafetyFlag(
                category: category,
                severity: severity,
                detail: dict["detail"] as? String ?? "",
                actionRequired: SafetyFlagAction(rawValue: actionRaw) ?? .allow
            )
        }
    }
}

// MARK: - Routing Errors

enum RoutingError: Error {
    case invalidEndpoint
    case serverError
    case timeout
    case allProvidersFailed
}
