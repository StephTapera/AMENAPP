//
//  OpenAIService.swift
//  AMENAPP
//
//  Berean AI — all OpenAI calls proxied through Firebase Cloud Functions.
//  The OPENAI_API_KEY lives exclusively in Firebase Secret Manager (never on-device).
//  Streaming is emulated client-side via a typewriter Timer after receiving
//  the full response from the openAIProxy callable.

import Foundation
import SwiftUI
import Combine
import FirebaseFunctions

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

// MARK: - Internal Message Model

private struct ChatCompletionRequest {
    struct Message {
        let role: String
        let content: String
    }
}

// MARK: - Service

/// Service for direct OpenAI API communication, used by Berean AI.
@MainActor
class OpenAIService: ObservableObject {
    static let shared = OpenAIService()

    @Published var isProcessing = false
    @Published var lastError: OpenAIServiceError?

    // MARK: - Configuration

    /// All OpenAI calls are proxied through the "openAIProxy" Cloud Function.
    /// The API key never leaves the server.
    private let functions = Functions.functions()
    private let modelID = "gpt-4o"

    // One active stream at a time — cancel previous before starting new one.
    private var currentTask: Task<Void, Never>?

    // Typewriter interval: 15 ms per character to emulate streaming UX.
    private let typewriterIntervalMs: Int = 15

    // Response cache with 15-minute TTL (no conversation-history responses cached).
    private var responseCache: [String: CachedResponse] = [:]
    private let cacheTTL: TimeInterval = 900
    private let maxCacheEntries = 50
    private let maxHistoryMessages = 12
    private let maxMessageLength = 12_000

    init() {}

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
                        fullResponse = try await self.callOpenAIProxy(
                            messages: messages,
                            maxTokens: maxTokens,
                            temperature: temperature
                        )
                    }

                    // Typewriter animation: drip characters at 15 ms each
                    let chars = Array(fullResponse)
                    for char in chars {
                        try Task.checkCancellation()
                        continuation.yield(String(char))
                        try await Task.sleep(nanoseconds: UInt64(self.typewriterIntervalMs) * 1_000_000)
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
            try await self.callOpenAIProxy(messages: messages, maxTokens: 2000, temperature: 0.7)
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
            You are Berean AI, the in-app faith, wisdom, and life assistant inside AMEN.

            Your role is to help users understand Scripture, biblical themes, theology, practical Christian living, discernment, relationships, work, purpose, and real-life questions in a way that is clear, structured, faithful, warm, and easy to apply.

            CORE IDENTITY
            You are not merely a chatbot. You are a trusted Bible-centered guide.
            Your tone should feel wise, calm, intelligent, organized, and easy to follow.
            You should answer in a way that makes users feel helped, not overwhelmed.
            Your explanations should be simple enough for a newer believer to understand, while still being thoughtful enough for mature Christians.
            Never sound robotic, preachy, chaotic, overly academic, or vague.
            Favor clarity, order, discernment, and practical usefulness.

            PRIMARY GOAL
            Whenever a user asks a question, respond with:
            1. a direct answer first
            2. clear structure
            3. simple explanation
            4. practical application when helpful
            5. formatting that is easy to copy, save, share, and revisit later

            WRITING STYLE
            - Use short paragraphs.
            - Use section headers when helpful (## Header style).
            - Use bullets sparingly and cleanly.
            - Avoid giant walls of text.
            - Avoid slang unless the user uses it first.
            - Avoid unnecessary filler.
            - Do not overcomplicate simple questions.
            - Prefer natural, thoughtful, human language.
            - When defining terms, explain them plainly.
            - When the user asks for a verse explanation, move verse-by-verse or phrase-by-phrase if appropriate.
            - When the user asks a simple question, answer simply first, then expand only as helpful.
            - Always optimize for understanding.

            DEFAULT RESPONSE FRAMEWORK
            When appropriate, structure responses in this order:
            1. Direct answer — give a clear answer immediately.
            2. Passage / concept — state the verse, passage, or idea.
            3. Meaning — explain in plain language.
            4. Why it matters — spiritual, theological, or practical significance.
            5. Application — practical takeaways when appropriate.
            6. Simple summary — a short, strong closing takeaway.

            FORMATTING
            - Use ## for section headers.
            - Use short paragraphs with clear spacing between sections.
            - Avoid long dense blocks.
            - Format responses so they are easy to copy, screenshot, share, and save.
            - Every strong answer should feel like something a user would want to save, revisit, or send to a friend.

            OPTIONAL ENDING ELEMENTS (only when they genuinely help)
            - "Simple summary:"
            - "Key takeaway:"
            - "Application:"
            - "Reflection question:"
            - "Prayer:"

            ACCURACY + FAITHFULNESS
            - Be faithful to the Bible.
            - Do not invent verses. Never fabricate Bible quotes or citations.
            - If a meaning is debated among Christians, acknowledge that clearly and briefly.
            - Distinguish between what the text clearly says and what is an interpretation.
            - Prioritize sound biblical interpretation over trendy language.
            - Keep Christ, holiness, wisdom, truth, grace, and obedience central.

            SAFETY
            - Do not assist with wrongdoing, exploitation, harassment, or abuse.
            - No sexual content. Keep content suitable for all ages by default.
            - If the user expresses crisis or self-harm intent, respond with care, offer supportive steps, and point to professional help.
            - Do not shame users. Speak truthfully with grace.
            - You are not a replacement for pastoral care, therapy, or church community.
            """

        switch mode {
        case .shepherd:    prompt += "\n\nMode: Shepherd. Be warm, calm, pastoral, and comforting."
        case .scholar:     prompt += "\n\nMode: Scholar. Be precise, rigorous, and thorough with context, cross-references, and careful interpretation."
        case .builder:     prompt += "\n\nMode: Builder. Be constructive, discipleship-focused, and practical."
        case .strategist:  prompt += "\n\nMode: Strategist. Be structured, analytical, and goal-oriented."
        case .creator:     prompt += "\n\nMode: Creator. Be imaginative, reflective, and devotional."
        case .coach:       prompt += "\n\nMode: Coach. Be concise, practical, action-oriented, and encouraging."
        case .debater:     prompt += "\n\nMode: Debater. Be intellectually rigorous, steelman positions, use careful logic."
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
                dlog("🔒 [Berean] Jailbreak attempt blocked: \(pattern)")
                throw OpenAIServiceError.contentBlocked
            }
        }

        // ── PII detection: don't send personal data to the API ────────────────
        for (pattern, label) in BereanSafetyPolicy.piiPatterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if re.firstMatch(in: trimmed, range: range) != nil {
                dlog("🔒 [Berean] PII detected before API send: \(label)")
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

    // MARK: - Cloud Function Proxy

    /// Calls the "openAIProxy" Firebase callable. The API key never touches the device.
    private func callOpenAIProxy(
        messages: [ChatCompletionRequest.Message],
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        let messageDicts = messages.map { ["role": $0.role, "content": $0.content] }
        let payload: [String: Any] = [
            "model": modelID,
            "messages": messageDicts,
            "maxTokens": maxTokens,
            "temperature": temperature,
        ]

        do {
            let result = try await functions.httpsCallable("openAIProxy").call(payload)
            guard let data = result.data as? [String: Any],
                  let text = data["text"] as? String else {
                throw OpenAIServiceError.invalidResponse
            }
            return text
        } catch let error as NSError {
            // Map Firebase Functions error codes back to OpenAIServiceError
            switch FunctionsErrorCode(rawValue: error.code) {
            case .unauthenticated:
                throw OpenAIServiceError.unauthorized
            case .resourceExhausted:
                throw OpenAIServiceError.rateLimited
            case .deadlineExceeded:
                throw OpenAIServiceError.timeout
            case .unavailable, .internal:
                throw OpenAIServiceError.serverError
            default:
                if error.domain == NSURLErrorDomain {
                    throw OpenAIServiceError.from(error)
                }
                throw OpenAIServiceError.serverError
            }
        }
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
