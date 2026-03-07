//
//  OpenAIService.swift
//  AMENAPP
//
//  Direct OpenAI API integration for Berean AI
//  Production-hardened: cancellation, typed errors, retry, mode routing,
//  structured cache keys, preflight validation, ephemeral session.

import Foundation
import SwiftUI
import Combine

// MARK: - Supporting Enums

/// Berean personality modes. Maps to distinct system-prompt shaping.
enum BereanMode: String, CaseIterable {
    case shepherd   = "shepherd"
    case scholar    = "scholar"
    case builder    = "builder"
    case strategist = "strategist"
    case creator    = "creator"
    case coach      = "coach"
    case debater    = "debater"
}

/// Where a Berean request originates. Used for prompt shaping and audit context.
enum BereanSource {
    case chat
    case highlightedPost
    case highlightedComment
    case highlightedMessage
    case churchNote
    case prayerRequest
}

/// Actions a user can request on highlighted text.
enum BereanSelectionAction: String {
    case explain
    case summarize
    case rewrite
    case prayThrough
    case biblicalContext
    case practicalApplication
    case helpMeRespond
}

// MARK: - Supporting Types

struct OpenAIChatMessage {
    let content: String
    let isFromUser: Bool
}

struct CachedResponse {
    let response: String
    let timestamp: Date
}

/// Light metadata returned alongside a Berean response (for UI/analytics, no user content).
struct BereanResponseMetadata {
    let fromCache: Bool
    let model: String
    let startedAt: Date
    let completedAt: Date
    let mode: BereanMode
}

// MARK: - Error Types

/// Domain-specific error type for all Berean/OpenAI failures.
enum OpenAIServiceError: LocalizedError, Equatable {
    case missingAPIKey
    case networkUnavailable
    case timeout
    case rateLimited
    case unauthorized
    case serverError
    case invalidResponse
    case contentBlocked
    case cancelled
    case messageTooLong
    case emptyMessage
    case unknown

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:       return "Berean is not configured right now."
        case .networkUnavailable:  return "You're offline. Check your connection and try again."
        case .timeout:             return "Berean took too long to respond. Please try again."
        case .rateLimited:         return "Too many requests right now. Please wait a moment and try again."
        case .unauthorized:        return "Berean is temporarily unavailable."
        case .serverError:         return "Berean is having trouble right now. Please try again."
        case .invalidResponse:     return "Berean returned an unexpected response."
        case .contentBlocked:      return "That message contains content Berean can't process. Please remove any personal information or restricted content and try again."
        case .cancelled:           return nil
        case .messageTooLong:      return "Your message is too long. Please shorten it and try again."
        case .emptyMessage:        return "Please enter a message before sending."
        case .unknown:             return "Something went wrong. Please try again."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkUnavailable: return "Check your internet connection and try again."
        case .timeout:            return "Try again or send a shorter request."
        case .rateLimited:        return "Wait a few seconds and try again."
        case .messageTooLong:     return "Shorten your question and try again."
        case .serverError:        return "Please try again in a moment."
        default:                  return nil
        }
    }

    var isRetryable: Bool {
        switch self {
        case .timeout, .networkUnavailable, .rateLimited, .serverError:
            return true
        default:
            return false
        }
    }

    static func from(_ error: Error) -> OpenAIServiceError {
        if error is CancellationError { return .cancelled }

        if let svcError = error as? OpenAIServiceError { return svcError }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .cannotConnectToHost, .cannotFindHost:
                return .networkUnavailable
            case .timedOut:
                return .timeout
            default:
                return .unknown
            }
        }

        if let apiError = error as? OpenAIError {
            switch apiError {
            case .missingAPIKey:   return .missingAPIKey
            case .invalidResponse: return .invalidResponse
            case .httpError(let code):
                switch code {
                case 401:        return .unauthorized
                case 408:        return .timeout
                case 429:        return .rateLimited
                case 500...599:  return .serverError
                default:         return .unknown
                }
            }
        }

        return .unknown
    }
}

// Legacy error type kept for any existing call sites that check OpenAIError.
enum OpenAIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured."
        case .invalidResponse:
            return "Invalid response from OpenAI API."
        case .httpError(let statusCode):
            return "OpenAI API error (HTTP \(statusCode))"
        }
    }
}

// MARK: - Codable Request / Response Models

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let temperature: Double
    let max_tokens: Int
    let stream: Bool?
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - Service

/// Service for direct OpenAI API communication, used by Berean AI.
@MainActor
class OpenAIService: ObservableObject {
    static let shared = OpenAIService()

    @Published var isProcessing = false
    @Published var lastError: OpenAIServiceError?

    // MARK: - Configuration

    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"
    private let modelID = "gpt-4o"

    // One active stream at a time — cancel previous before starting new one.
    private var currentTask: Task<Void, Never>?

    // Ephemeral session so no accidental persistence of sensitive request data.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    // Response cache with 15-minute TTL (no conversation-history responses cached).
    private var responseCache: [String: CachedResponse] = [:]
    private let cacheTTL: TimeInterval = 900
    private let maxCacheEntries = 50
    private let maxHistoryMessages = 12
    private let maxMessageLength = 12_000

    init() {
        self.apiKey = BundleConfig.string(forKey: "OPENAI_API_KEY") ?? ""
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
        let cacheKey = makeCacheKey(message: message, mode: mode, suffix: systemPromptSuffix)
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

                    let messages = self.buildMessages(
                        userMessage: message,
                        history: self.trimmedHistory(conversationHistory),
                        mode: mode,
                        suffix: systemPromptSuffix
                    )

                    var fullResponse = ""

                    try await self.withRetry {
                        let stream = self.streamChatCompletion(
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
        let prompt = buildSelectionPrompt(
            selectedText: selectedText,
            source: source,
            action: action
        )
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

        let messages = buildMessages(
            userMessage: message,
            history: trimmedHistory(conversationHistory),
            mode: mode,
            suffix: nil
        )

        return try await withRetry {
            try await self.chatCompletion(messages: messages)
        }
    }

    // MARK: - Prompt Construction

    private func buildMessages(
        userMessage: String,
        history: [OpenAIChatMessage],
        mode: BereanMode,
        suffix: String?
    ) -> [ChatCompletionRequest.Message] {
        var messages: [ChatCompletionRequest.Message] = []
        messages.append(.init(role: "system", content: buildSystemPrompt(mode: mode, suffix: suffix)))
        for msg in history {
            messages.append(.init(role: msg.isFromUser ? "user" : "assistant", content: msg.content))
        }
        messages.append(.init(role: "user", content: userMessage))
        return messages
    }

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

        // ── Jailbreak detection (client-side, before any API call) ────────────
        let lower = trimmed.lowercased()
        for pattern in BereanSafetyPolicy.jailbreakPatterns {
            if lower.contains(pattern) {
                // Log to analytics but don't expose internal reason to caller
                print("🔒 [Berean] Jailbreak attempt blocked: \(pattern)")
                throw OpenAIServiceError.contentBlocked
            }
        }

        // ── PII detection: don't send personal data to the API ────────────────
        for (pattern, label) in BereanSafetyPolicy.piiPatterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if re.firstMatch(in: trimmed, range: range) != nil {
                print("🔒 [Berean] PII detected before API send: \(label)")
                // Throw a content-blocked error so the UI shows a helpful message
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

                // Exponential backoff: 500ms, 1s, 2s
                let delay = UInt64(pow(2.0, Double(attempt - 1)) * 500_000_000)
                try await Task.sleep(nanoseconds: delay)
            }
        }

        throw lastError ?? OpenAIServiceError.unknown
    }

    // MARK: - Low-Level Streaming Request

    // Maximum seconds allowed between consecutive SSE chunks before the stream
    // is treated as stalled and aborted with a timeout error.
    private let streamChunkTimeoutSeconds: TimeInterval = 20

    private func streamChatCompletion(
        messages: [ChatCompletionRequest.Message],
        maxTokens: Int,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: "\(baseURL)/chat/completions") else {
                        throw OpenAIServiceError.invalidResponse
                    }

                    let body = ChatCompletionRequest(
                        model: modelID,
                        messages: messages,
                        temperature: temperature,
                        max_tokens: maxTokens,
                        stream: true
                    )

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OpenAIServiceError.invalidResponse
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw OpenAIError.httpError(statusCode: httpResponse.statusCode)
                    }

                    // Inactivity watchdog: fires if no chunk arrives within the window.
                    // Replaced on every received chunk to reset the deadline.
                    var watchdog: Task<Void, Never>? = nil

                    func resetWatchdog() {
                        watchdog?.cancel()
                        watchdog = Task {
                            try? await Task.sleep(nanoseconds: UInt64(streamChunkTimeoutSeconds * 1_000_000_000))
                            guard !Task.isCancelled else { return }
                            continuation.finish(throwing: OpenAIServiceError.timeout)
                        }
                    }

                    resetWatchdog()

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard !line.isEmpty, !line.hasPrefix(":") else { continue }

                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))
                            if data == "[DONE]" { break }

                            guard let jsonData = data.data(using: .utf8) else { continue }

                            // Decode streaming delta
                            struct StreamChunk: Decodable {
                                struct Choice: Decodable {
                                    struct Delta: Decodable {
                                        let content: String?
                                    }
                                    let delta: Delta
                                }
                                let choices: [Choice]
                            }

                            guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: jsonData),
                                  let content = chunk.choices.first?.delta.content else {
                                continue
                            }

                            resetWatchdog()
                            continuation.yield(content)
                        }
                    }

                    watchdog?.cancel()
                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Low-Level Non-Streaming Request

    private func chatCompletion(messages: [ChatCompletionRequest.Message]) async throws -> String {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw OpenAIServiceError.invalidResponse
        }

        let body = ChatCompletionRequest(
            model: modelID,
            messages: messages,
            temperature: 0.7,
            max_tokens: 2000,
            stream: nil
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw OpenAIError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw OpenAIServiceError.invalidResponse
        }

        return content
    }

    // MARK: - Cache Management

    private func makeCacheKey(message: String, mode: BereanMode, suffix: String?) -> String {
        "\(modelID)|\(mode.rawValue)|\(suffix ?? "")|\(message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
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
