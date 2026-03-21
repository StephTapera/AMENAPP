//
//  ClaudeService.swift
//  AMENAPP
//
//  Anthropic Claude client for Berean AI — routes through the bereanChatProxy
//  Cloud Function instead of calling api.anthropic.com directly.
//  The API key lives in Firebase Secret Manager; it is never stored on device.
//
//  Streaming UX is preserved via local typewriter animation (15 ms/character).
//
//  Public interface is identical to the previous direct-API version so all
//  callers compile without changes.

import Foundation
import SwiftUI
import Combine
import FirebaseFunctions

// MARK: - Service

/// Drop-in Berean AI client that routes all LLM calls through bereanChatProxy.
@MainActor
final class ClaudeService: ObservableObject {
    static let shared = ClaudeService()

    @Published var isProcessing = false
    @Published var lastError: OpenAIServiceError?

    // MARK: - Configuration

    private let functions = Functions.functions()
    private var currentTask: Task<Void, Never>?

    // 15-minute TTL, 50-entry LRU (history-free queries only).
    private var responseCache: [String: CachedResponse] = [:]
    private let cacheTTL: TimeInterval = 900
    private let maxCacheEntries = 50
    private let maxHistoryMessages = 12
    private let maxMessageLength = 12_000

    // Typewriter speed for local streaming simulation.
    private let typewriterDelayNs: UInt64 = 15_000_000 // 15 ms

    // MARK: - Public Control

    func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
    }

    func reset() {
        cancelCurrentRequest()
        responseCache.removeAll()
        lastError = nil
    }

    // MARK: - Chat Completion (Typewriter Streaming)

    /// Send a message to Berean and receive a streaming response via local
    /// typewriter animation on top of a full response from the Cloud Function.
    func sendMessage(
        _ message: String,
        conversationHistory: [OpenAIChatMessage] = [],
        maxTokens: Int = 2000,
        temperature: Double = 0.7,
        mode: BereanMode = .shepherd,
        systemPromptSuffix: String? = nil
    ) -> AsyncThrowingStream<String, Error> {

        cancelCurrentRequest()

        do {
            try validateOutgoingMessage(message)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        let cacheKey = makeCacheKey(message: message, mode: mode, suffix: systemPromptSuffix)
        if conversationHistory.isEmpty, let cached = getCachedResponse(for: cacheKey) {
            return typewriterStream(text: cached)
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
                    let userMessage = buildUserMessage(
                        userMessage: message,
                        history: trimmedHistory(conversationHistory)
                    )

                    let result = try await self.callProxy(
                        systemPrompt: systemPrompt,
                        userMessage: userMessage,
                        maxTokens: min(maxTokens, 2000)
                    )

                    if conversationHistory.isEmpty, !result.isEmpty {
                        self.cacheResponse(result, for: cacheKey)
                    }

                    for char in result {
                        try Task.checkCancellation()
                        continuation.yield(String(char))
                        try? await Task.sleep(nanoseconds: self.typewriterDelayNs)
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

    func sendMessageSync(
        _ message: String,
        conversationHistory: [OpenAIChatMessage] = [],
        mode: BereanMode = .shepherd
    ) async throws -> String {
        try validateOutgoingMessage(message)

        isProcessing = true
        defer { isProcessing = false }

        let systemPrompt = buildSystemPrompt(mode: mode, suffix: nil)
        let userMessage = buildUserMessage(
            userMessage: message,
            history: trimmedHistory(conversationHistory)
        )

        return try await withRetry {
            try await self.callProxy(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                maxTokens: 2000
            )
        }
    }

    // MARK: - Cloud Function Call

    private func callProxy(
        systemPrompt: String,
        userMessage: String,
        maxTokens: Int
    ) async throws -> String {
        let callable = functions.httpsCallable("bereanChatProxy")
        let params: [String: Any] = [
            "systemPrompt": systemPrompt,
            "userMessage": userMessage,
            "maxTokens": maxTokens,
        ]
        let result = try await callable.call(params)
        guard let data = result.data as? [String: Any],
              let text = data["text"] as? String else {
            throw OpenAIServiceError.invalidResponse
        }
        return text
    }

    // MARK: - Typewriter stream helper

    private func typewriterStream(text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for char in text {
                    if Task.isCancelled { break }
                    continuation.yield(String(char))
                    try? await Task.sleep(nanoseconds: self.typewriterDelayNs)
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Prompt Construction

    private func buildUserMessage(
        userMessage: String,
        history: [OpenAIChatMessage]
    ) -> String {
        guard !history.isEmpty else { return userMessage }
        let historyText = history.map { msg in
            "\(msg.isFromUser ? "User" : "Berean"): \(msg.content)"
        }.joined(separator: "\n")
        return "\(historyText)\nUser: \(userMessage)"
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

            SAFETY GUARDRAILS:
            - Do not assist with wrongdoing, exploitation, harassment, pornography, trafficking, or abuse.
            - No sexual content. Keep content suitable for teens by default.
            - If asked for harmful/illegal content, refuse and redirect.
            - If the user expresses self-harm intent or crisis, respond with care, encourage local emergency/help resources, then offer supportive steps.
            - Do not shame users. Speak truthfully with grace.

            ACCURACY:
            - If uncertain, say so and ask one clarifying question or state your safe assumptions.
            - Never fabricate Bible quotes or citations.

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

        let lower = trimmed.lowercased()
        for pattern in BereanSafetyPolicy.jailbreakPatterns {
            if lower.contains(pattern) {
                dlog("🔒 [Berean/Claude] Jailbreak attempt blocked: \(pattern)")
                throw OpenAIServiceError.contentBlocked
            }
        }

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
                guard attempt < maxAttempts else { throw error }
                let delay = UInt64(pow(2.0, Double(attempt - 1)) * 500_000_000)
                try await Task.sleep(nanoseconds: delay)
            }
        }

        throw lastError ?? OpenAIServiceError.unknown
    }

    // MARK: - Cache Management

    private func makeCacheKey(message: String, mode: BereanMode, suffix: String?) -> String {
        "\(mode.rawValue)|\(suffix ?? "")|\(message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
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
