//
//  ClaudeService.swift
//  AMENAPP
//
//  Anthropic Claude API client for Berean AI.
//  Drop-in replacement for OpenAIService: same public interface, same error types,
//  same streaming API, same cache structure — routes to Anthropic Messages API
//  with BereanMode-driven model tiering (Haiku for real-time, Sonnet for deep work).
//
//  Model tiering:
//    • Haiku  (claude-haiku-4-5)  — every real-time user interaction
//    • Sonnet (claude-sonnet-4-5) — multi-chapter study, devotional, enforcement drafts
//
//  BereanMode → tier:
//    scholar   → Sonnet  (precise theological analysis, cross-references, multi-step study)
//    debater   → Sonnet  (steelmanning arguments requires deeper reasoning)
//    strategist→ Haiku   (fast business/ops answers)
//    shepherd  → Haiku   (pastoral warmth, light-weight)
//    builder   → Haiku   (code/systems, concise)
//    creator   → Haiku   (generative, fast)
//    coach     → Haiku   (action-oriented, concise)
//
//  Async Genkit helpers (generateDevotional, generateStudyPlan, analyzeScripture):
//    These are called with mode: .scholar and will automatically route to Sonnet.

import Foundation
import SwiftUI
import Combine

// MARK: - Model Constants

private enum ClaudeModel {
    /// Fast, cost-efficient — used for all real-time Berean interactions.
    static let haiku  = "claude-haiku-4-5"
    /// Higher quality — used for scholar/debater modes and async deep-work helpers.
    static let sonnet = "claude-sonnet-4-5"

    /// Map a BereanMode to the appropriate Claude model.
    static func forMode(_ mode: BereanMode) -> String {
        switch mode {
        case .scholar, .debater:
            return sonnet
        case .shepherd, .builder, .strategist, .creator, .coach:
            return haiku
        }
    }
}

// MARK: - Codable Request / Response Models (Anthropic Messages API)

private struct AnthropicMessage: Encodable {
    let role: String    // "user" or "assistant"
    let content: String
}

private struct AnthropicRequest: Encodable {
    let model: String
    let max_tokens: Int
    let temperature: Double
    let system: String
    let messages: [AnthropicMessage]
    let stream: Bool
}

private struct AnthropicNonStreamResponse: Decodable {
    struct Content: Decodable {
        let type: String
        let text: String?
    }
    let content: [Content]
}

// MARK: - Service

/// Drop-in Claude replacement for OpenAIService, used by Berean AI and Church Notes.
/// Uses the same public interface (sendMessage/sendMessageSync/reset/cancelCurrentRequest)
/// and the same error types (OpenAIServiceError) so callers require no changes.
@MainActor
final class ClaudeService: ObservableObject {
    static let shared = ClaudeService()

    @Published var isProcessing = false
    @Published var lastError: OpenAIServiceError?

    // MARK: - Configuration

    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1"
    private let anthropicVersion = "2023-06-01"

    private var currentTask: Task<Void, Never>?

    // Ephemeral session: no accidental persistence of sensitive request data.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    // 15-minute TTL, 50-entry LRU (history-free queries only — same as OpenAIService).
    private var responseCache: [String: CachedResponse] = [:]
    private let cacheTTL: TimeInterval = 900
    private let maxCacheEntries = 50
    private let maxHistoryMessages = 12
    private let maxMessageLength = 12_000

    init() {
        self.apiKey = BundleConfig.string(forKey: "ANTHROPIC_API_KEY") ?? ""
    }

    // MARK: - Public Control

    /// Cancel any in-flight streaming request immediately.
    func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
    }

    /// Full reset — call on logout or auth switch.
    func reset() {
        cancelCurrentRequest()
        responseCache.removeAll()
        lastError = nil
    }

    // MARK: - Chat Completion (Streaming)

    /// Send a message to Berean and receive a streaming response.
    /// Automatically cancels any previously running request.
    func sendMessage(
        _ message: String,
        conversationHistory: [OpenAIChatMessage] = [],
        maxTokens: Int = 2000,
        temperature: Double = 0.7,
        mode: BereanMode = .shepherd,
        systemPromptSuffix: String? = nil
    ) -> AsyncThrowingStream<String, Error> {

        cancelCurrentRequest()

        guard !apiKey.isEmpty else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: OpenAIServiceError.missingAPIKey)
            }
        }

        // Preflight validation before touching the network.
        do {
            try validateOutgoingMessage(message)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        // Cache hit (history-free queries only).
        let modelID = ClaudeModel.forMode(mode)
        let cacheKey = makeCacheKey(message: message, model: modelID, mode: mode, suffix: systemPromptSuffix)
        if conversationHistory.isEmpty, let cached = getCachedResponse(for: cacheKey) {
            return AsyncThrowingStream { continuation in
                Task {
                    let words = cached.split(separator: " ")
                    for word in words {
                        if Task.isCancelled { break }
                        continuation.yield(String(word) + " ")
                        try? await Task.sleep(nanoseconds: 8_000_000)
                    }
                    continuation.finish()
                }
            }
        }

        return AsyncThrowingStream { continuation in
            self.currentTask = Task {
                do {
                    try Task.checkCancellation()

                    await MainActor.run {
                        self.isProcessing = true
                        self.lastError = nil
                    }

                    let systemPrompt = buildSystemPrompt(mode: mode, suffix: systemPromptSuffix)
                    let messages = buildMessages(
                        userMessage: message,
                        history: trimmedHistory(conversationHistory)
                    )

                    var fullResponse = ""

                    try await self.withRetry {
                        let stream = self.streamCompletion(
                            model: modelID,
                            systemPrompt: systemPrompt,
                            messages: messages,
                            maxTokens: maxTokens,
                            temperature: temperature
                        )
                        for try await chunk in stream {
                            try Task.checkCancellation()
                            continuation.yield(chunk)
                            fullResponse += chunk
                        }
                    }

                    if conversationHistory.isEmpty, !fullResponse.isEmpty {
                        self.cacheResponse(fullResponse, for: cacheKey)
                    }

                    continuation.finish()

                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    let mapped = OpenAIServiceError.from(error)
                    continuation.finish(throwing: mapped)
                    await MainActor.run { self.lastError = mapped }
                }

                await MainActor.run {
                    self.isProcessing = false
                    self.currentTask = nil
                }
            }
        }
    }

    // MARK: - Highlighted Text / Selection API

    /// Ask Berean about selected text from anywhere in the app.
    func askBereanAboutSelection(
        selectedText: String,
        source: BereanSource,
        action: BereanSelectionAction,
        mode: BereanMode = .scholar
    ) -> AsyncThrowingStream<String, Error> {
        let prompt = buildSelectionPrompt(selectedText: selectedText, source: source, action: action)
        return sendMessage(prompt, conversationHistory: [], mode: mode)
    }

    // MARK: - Sync Completion

    /// Non-streaming completion (for summarisation, moderation helpers, etc.).
    func sendMessageSync(
        _ message: String,
        conversationHistory: [OpenAIChatMessage] = [],
        mode: BereanMode = .shepherd
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw OpenAIServiceError.missingAPIKey }
        try validateOutgoingMessage(message)

        isProcessing = true
        defer { isProcessing = false }

        let modelID = ClaudeModel.forMode(mode)
        let systemPrompt = buildSystemPrompt(mode: mode, suffix: nil)
        let messages = buildMessages(
            userMessage: message,
            history: trimmedHistory(conversationHistory)
        )

        return try await withRetry {
            try await self.nonStreamingCompletion(
                model: modelID,
                systemPrompt: systemPrompt,
                messages: messages
            )
        }
    }

    // MARK: - Prompt Construction

    private func buildMessages(
        userMessage: String,
        history: [OpenAIChatMessage]
    ) -> [AnthropicMessage] {
        var messages: [AnthropicMessage] = []
        for msg in history {
            messages.append(.init(role: msg.isFromUser ? "user" : "assistant", content: msg.content))
        }
        messages.append(.init(role: "user", content: userMessage))
        return messages
    }

    /// Identical system prompt to OpenAIService — content, mode shaping, and safety guardrails preserved.
    private func buildSystemPrompt(mode: BereanMode, suffix: String?) -> String {
        var prompt = """
            You are Berean, the AI assistant inside the AMEN app. You are an elite, helpful assistant for Bible study, life decisions, tech, business, and creativity — while staying Christ-centered, safe, and wise. Be practical, intelligent, and calm.

            HARD FORMATTING RULES (strict):
            - Do NOT use Markdown headings or heading symbols (no #, ##, ###).
            - Do NOT write long walls of text. Use short paragraphs and simple bullets when helpful.
            - Prefer plain text with clean spacing.
            - If the user asks for a structured format, use short labels like "Summary:", "Steps:", "Options:", "Scripture:", "Next:" — no headings.
            - Keep lists tight and readable.

            CORE IDENTITY:
            - You are Bible-informed first, but not Bible-only.
            - You can help with: Bible study and discipleship, decision-making and life advice, tech (iOS, Firebase, architecture, security), business (strategy, PMF, product, ops, fundraising, marketing), creativity (writing, naming, branding, UX ideas).
            - Keep answers aligned with wisdom, truth, and love. Do not be preachy or manipulative.

            CHRIST-CENTERED RESPONSE SHAPE (always):
            Every answer includes these three elements:
            1. Direct value: answer the question clearly and practically.
            2. Scripture anchor: include 1–3 relevant references when appropriate. Never invent verses.
            3. Jesus-centered close: 1–2 sentences pointing toward Christ-like wisdom. No guilt, no manipulation.

            RESPONSE TEMPLATES:
            Template A (general): Summary: / Key points: / Steps: / Scripture: / Close:
            Template B (decision): Recommendation: / Why: / Risks: / Next actions: / Scripture: / Close:
            Template C (Bible study): Plain meaning: / Context: / Key themes: / Cross references: / Application: / Scripture: / Close:

            SAFETY GUARDRAILS:
            - Do not assist with wrongdoing, exploitation, harassment, pornography, trafficking, or abuse.
            - No sexual content. Keep content suitable for teens by default.
            - If asked for harmful/illegal content, refuse and redirect.
            - If the user expresses self-harm intent or crisis, respond with care, encourage local emergency/help resources, then offer supportive steps.
            - Do not shame users. Speak truthfully with grace.

            ACCURACY:
            - If uncertain, say so and ask one clarifying question or state your safe assumptions.
            - Never fabricate Bible quotes or citations.
            - For tech/business: be concrete, include tradeoffs, give next actions.

            PRIVACY:
            - Don't ask for sensitive personal data unless necessary.
            - You are not a replacement for pastoral care, therapy, or church community. For serious crises, point to professional help.
            """

        switch mode {
        case .shepherd:    prompt += "\n\nMode: Shepherd. Be warm, calm, pastoral, supportive."
        case .scholar:     prompt += "\n\nMode: Scholar. Use context, precision, cross-references, careful interpretation."
        case .builder:     prompt += "\n\nMode: Builder. Be technical, practical, systems-oriented, direct."
        case .strategist:  prompt += "\n\nMode: Strategist. Focus on business, leverage, sequencing, risk, metrics."
        case .creator:     prompt += "\n\nMode: Creator. Be imaginative, clear, useful, compelling."
        case .coach:       prompt += "\n\nMode: Coach. Be concise, motivating, practical, action-oriented."
        case .debater:     prompt += "\n\nMode: Debater. Steelman both sides, avoid hostility, use logic carefully."
        }

        if let suffix, !suffix.isEmpty {
            prompt += "\n\nAdditional style instruction: \(suffix)"
        }

        return prompt
    }

    private func buildSelectionPrompt(
        selectedText: String,
        source: BereanSource,
        action: BereanSelectionAction
    ) -> String {
        let sourceLabel: String
        switch source {
        case .chat:               sourceLabel = "a chat message"
        case .highlightedPost:    sourceLabel = "a post"
        case .highlightedComment: sourceLabel = "a comment"
        case .highlightedMessage: sourceLabel = "a message"
        case .churchNote:         sourceLabel = "a church note"
        case .prayerRequest:      sourceLabel = "a prayer request"
        }

        let actionInstruction: String
        switch action {
        case .explain:              actionInstruction = "Explain this clearly."
        case .summarize:            actionInstruction = "Summarize this concisely."
        case .rewrite:              actionInstruction = "Rewrite this more clearly and helpfully."
        case .prayThrough:          actionInstruction = "Pray through this with me."
        case .biblicalContext:      actionInstruction = "Provide biblical context and relevant Scripture."
        case .practicalApplication: actionInstruction = "Give practical steps to apply this."
        case .helpMeRespond:        actionInstruction = "Help me craft a wise, kind response to this."
        }

        return "The following text is from \(sourceLabel):\n\n\"\(selectedText)\"\n\n\(actionInstruction)"
    }

    // MARK: - Preflight Validation

    private func validateOutgoingMessage(_ message: String) throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OpenAIServiceError.emptyMessage }
        guard trimmed.count <= maxMessageLength else { throw OpenAIServiceError.messageTooLong }

        // Jailbreak detection (client-side, before any API call).
        let lower = trimmed.lowercased()
        for pattern in BereanSafetyPolicy.jailbreakPatterns {
            if lower.contains(pattern) {
                dlog("🔒 [Berean/Claude] Jailbreak attempt blocked: \(pattern)")
                throw OpenAIServiceError.contentBlocked
            }
        }

        // PII detection: don't send personal data to the API.
        for (pattern, label) in BereanSafetyPolicy.piiPatterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if re.firstMatch(in: trimmed, range: range) != nil {
                dlog("🔒 [Berean/Claude] PII detected before API send: \(label)")
                throw OpenAIServiceError.contentBlocked
            }
        }
    }

    // MARK: - History Trimming

    private func trimmedHistory(_ history: [OpenAIChatMessage]) -> [OpenAIChatMessage] {
        Array(history.suffix(maxHistoryMessages))
    }

    // MARK: - Retry Logic

    private func shouldRetry(for error: Error) -> Bool {
        OpenAIServiceError.from(error).isRetryable
    }

    @discardableResult
    private func withRetry<T>(
        maxAttempts: Int = 3,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?

        while attempt < maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                attempt += 1

                guard attempt < maxAttempts, shouldRetry(for: error) else {
                    throw error
                }

                // Exponential backoff: 500ms, 1s, 2s.
                let delay = UInt64(pow(2.0, Double(attempt - 1)) * 500_000_000)
                try await Task.sleep(nanoseconds: delay)
            }
        }

        throw lastError ?? OpenAIServiceError.unknown
    }

    // MARK: - Low-Level Streaming Request (Anthropic SSE)

    private func streamCompletion(
        model: String,
        systemPrompt: String,
        messages: [AnthropicMessage],
        maxTokens: Int,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: "\(baseURL)/messages") else {
                        throw OpenAIServiceError.invalidResponse
                    }

                    let body = AnthropicRequest(
                        model: model,
                        max_tokens: maxTokens,
                        temperature: temperature,
                        system: systemPrompt,
                        messages: messages,
                        stream: true
                    )

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OpenAIServiceError.invalidResponse
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw OpenAIError.httpError(statusCode: httpResponse.statusCode)
                    }

                    // Anthropic SSE format:
                    //   event: content_block_delta
                    //   data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"…"}}
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard !line.isEmpty, !line.hasPrefix(":") else { continue }

                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            guard jsonString != "[DONE]",
                                  let jsonData = jsonString.data(using: .utf8) else { continue }

                            struct StreamDelta: Decodable {
                                struct Delta: Decodable {
                                    let type: String?
                                    let text: String?
                                }
                                let type: String
                                let delta: Delta?
                            }

                            guard let event = try? JSONDecoder().decode(StreamDelta.self, from: jsonData),
                                  event.type == "content_block_delta",
                                  event.delta?.type == "text_delta",
                                  let text = event.delta?.text else {
                                continue
                            }

                            continuation.yield(text)
                        }
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Low-Level Non-Streaming Request (Anthropic Messages)

    private func nonStreamingCompletion(
        model: String,
        systemPrompt: String,
        messages: [AnthropicMessage]
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/messages") else {
            throw OpenAIServiceError.invalidResponse
        }

        let body = AnthropicRequest(
            model: model,
            max_tokens: 2000,
            temperature: 0.7,
            system: systemPrompt,
            messages: messages,
            stream: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw OpenAIError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(AnthropicNonStreamResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
            throw OpenAIServiceError.invalidResponse
        }

        return text
    }

    // MARK: - Cache Management

    private func makeCacheKey(message: String, model: String, mode: BereanMode, suffix: String?) -> String {
        "\(model)|\(mode.rawValue)|\(suffix ?? "")|\(message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func getCachedResponse(for key: String) -> String? {
        pruneExpiredCache()
        guard let cached = responseCache[key] else { return nil }
        guard Date().timeIntervalSince(cached.timestamp) <= cacheTTL else {
            responseCache.removeValue(forKey: key)
            return nil
        }
        return cached.response
    }

    private func cacheResponse(_ response: String, for key: String) {
        pruneExpiredCache()
        responseCache[key] = CachedResponse(response: response, timestamp: Date())

        // Evict oldest entry if over limit.
        if responseCache.count > maxCacheEntries {
            if let oldestKey = responseCache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                responseCache.removeValue(forKey: oldestKey)
            }
        }
    }

    private func pruneExpiredCache() {
        let now = Date()
        responseCache = responseCache.filter { now.timeIntervalSince($0.value.timestamp) <= cacheTTL }
    }
}
