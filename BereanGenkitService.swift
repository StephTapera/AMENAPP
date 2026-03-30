//
//  BereanGenkitService.swift
//  AMENAPP
//
//  Service for AI-powered Bible study using Claude API.
//  Routes deep-work helpers (devotional, study plan, scripture analysis) to Sonnet
//  and real-time chat to Haiku via ClaudeService model tiering.
//
//  Architecture notes:
//  - The class name is kept for source compatibility; the underlying provider is ClaudeService.
//  - @Published properties are updated on the main actor only.
//  - All network work runs off the main actor inside ClaudeService.
//  - isProcessing uses a reference-counted approach so concurrent requests don't
//    prematurely clear the loading state.
//  - Every method validates inputs before hitting the network.
//  - lastError is always set on failure so observers can react.
//  - Parsing uses a normalised key-extraction helper rather than brittle
//    case-sensitive replacingOccurrences calls.
//  - Structured-output prompts ask the model for JSON so parsing is reliable.

import Foundation
import SwiftUI
import Combine

// MARK: - Error Types

enum BereanAIError: LocalizedError {
    case emptyInput
    case invalidDuration
    case responseParsingFailed
    case serviceDisabled
    case unsupportedFlow(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:             return "Input cannot be empty."
        case .invalidDuration:        return "Study duration must be between 1 and 365 days."
        case .responseParsingFailed:  return "The AI response could not be parsed. Please try again."
        case .serviceDisabled:        return "Berean AI is currently unavailable."
        case .unsupportedFlow(let n): return "Unsupported legacy flow: \(n)."
        }
    }
}

// MARK: - Service

/// AI-powered Bible study service backed by ClaudeService.
/// Source-compatible with the original BereanGenkitService name used across the project.
@MainActor
final class BereanGenkitService: ObservableObject {

    static let shared = BereanGenkitService()

    // UI-facing state — always mutated on the main actor (guaranteed by @MainActor class).
    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: Error?

    // The actual AI provider. Named clearly to avoid confusion with the class name.
    private let aiService = ClaudeService.shared

    // Reference count so concurrent requests don't prematurely clear the loading state.
    private var activeRequestCount = 0

    var isEnabled: Bool { true }

    private init() {}

    // MARK: - Request Lifecycle

    private func beginRequest() {
        activeRequestCount += 1
        isProcessing = true
        lastError = nil
    }

    private func endRequest(error: Error? = nil) {
        activeRequestCount = max(0, activeRequestCount - 1)
        isProcessing = activeRequestCount > 0
        if let error { lastError = error }
    }

    /// Wraps any async throwing operation with isProcessing + lastError management.
    private func perform<T>(_ operation: () async throws -> T) async throws -> T {
        beginRequest()
        do {
            let result = try await operation()
            endRequest()
            return result
        } catch {
            endRequest(error: error)
            throw error
        }
    }

    // MARK: - Input Validation

    private func requireNonEmpty(_ value: String, _ name: String = "Input") throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BereanAIError.emptyInput
        }
    }

    /// Caps a string at `maxLength` characters after trimming whitespace.
    private func trimmed(_ value: String, maxLength: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
    }

    // MARK: - Parsing Helpers

    /// Extracts the value after `key:` in a line, case-insensitively.
    /// Handles "Title:", "title:", "TITLE :", extra whitespace, etc.
    private func extractValue(forKey key: String, from line: String) -> String? {
        let lower = line.lowercased()
        let normalizedKey = key.lowercased() + ":"
        guard lower.contains(normalizedKey) else { return nil }
        guard let colonIdx = line.firstIndex(of: ":") else { return nil }
        let value = line[line.index(after: colonIdx)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - Core AI Chat

    /// Streaming response. Mode defaults to .shepherd (Haiku) for real-time chat.
    /// Tracks isProcessing and lastError for the full lifetime of the stream.
    func sendMessage(
        _ message: String,
        conversationHistory: [BereanMessage] = [],
        maxTokens: Int = 2000,
        temperature: Double = 0.7,
        systemPromptSuffix: String? = nil,
        mode: BereanMode = .shepherd
    ) -> AsyncThrowingStream<String, Error> {
        let safeMessage = trimmed(message, maxLength: 4000)
        let chatHistory = conversationHistory.map { msg in
            OpenAIChatMessage(content: msg.content, isFromUser: msg.isFromUser)
        }

        beginRequest()

        let baseStream = aiService.sendMessage(
            safeMessage,
            conversationHistory: chatHistory,
            maxTokens: maxTokens,
            temperature: temperature,
            mode: mode,
            systemPromptSuffix: systemPromptSuffix
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in baseStream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    await MainActor.run { self.lastError = error }
                    continuation.finish(throwing: error)
                }
                await MainActor.run { self.endRequest() }
            }
        }
    }

    /// Non-streaming response. Mode defaults to .shepherd (Haiku).
    func sendMessageSync(
        _ message: String,
        conversationHistory: [BereanMessage] = [],
        mode: BereanMode = .shepherd
    ) async throws -> String {
        let safeMessage = trimmed(message, maxLength: 4000)
        let chatHistory = conversationHistory.map { msg in
            OpenAIChatMessage(content: msg.content, isFromUser: msg.isFromUser)
        }
        return try await perform {
            try await self.aiService.sendMessageSync(safeMessage, conversationHistory: chatHistory, mode: mode)
        }
    }

    // MARK: - Devotional Generation

    /// Generates a structured devotional. Uses Sonnet (.scholar) for quality.
    /// Asks the model for JSON so parsing is reliable regardless of prose formatting.
    func generateDevotional(topic: String? = nil) async throws -> Devotional {
        let safeTopic = topic.map { trimmed($0, maxLength: 120) }

        let topicLine = safeTopic.map { "- topic: \($0)" } ?? "- topic: daily Christian reflection"

        let prompt = """
        Generate a Christian devotional as strict JSON only. No markdown, no commentary outside the JSON.
        Schema:
        {
          "title": "string (5–10 words)",
          "scripture": "string (e.g. John 3:16)",
          "content": "string (200–300 words of devotional reflection)",
          "prayer": "string (2–4 sentence closing prayer, first person)"
        }
        Requirements:
        \(topicLine)
        - content must be 200–300 words
        - scripture must be a real verse reference
        - prayer must be sincere and personal
        """

        return try await perform {
            // Devotional generation is quality-critical — use Sonnet via .scholar mode.
            let response = try await self.aiService.sendMessageSync(prompt, mode: .scholar)
            return try self.parseDevotionalJSON(response)
        }
    }

    private func parseDevotionalJSON(_ response: String) throws -> Devotional {
        // Strip possible markdown code fences the model may add despite instructions.
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw BereanAIError.responseParsingFailed
        }

        struct DevotionalDTO: Decodable {
            let title: String
            let scripture: String
            let content: String
            let prayer: String
        }

        do {
            let dto = try JSONDecoder().decode(DevotionalDTO.self, from: data)
            return Devotional(title: dto.title, scripture: dto.scripture, content: dto.content, prayer: dto.prayer)
        } catch {
            // Fall back to line-based parsing for models that ignore the JSON instruction.
            dlog("Devotional JSON parse failed (\(error)); falling back to line parser")
            return parseDevotionalLines(cleaned)
        }
    }

    private func parseDevotionalLines(_ response: String) -> Devotional {
        let lines = response.components(separatedBy: "\n").filter { !$0.isEmpty }
        var title = "Daily Devotional"
        var scripture = ""
        var prayer = ""

        for (index, line) in lines.enumerated() {
            if let v = extractValue(forKey: "title", from: line), !v.isEmpty { title = v }
            else if let v = extractValue(forKey: "scripture", from: line), !v.isEmpty { scripture = v }
            else if let v = extractValue(forKey: "prayer", from: line), !v.isEmpty {
                // Capture the prayer line and everything after it.
                prayer = lines[index...].joined(separator: "\n")
                if let afterColon = prayer.firstIndex(of: ":") {
                    prayer = String(prayer[prayer.index(after: afterColon)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                break
            }
        }

        return Devotional(
            title: title,
            scripture: scripture.isEmpty ? "Psalm 119:105" : scripture,
            content: response,
            prayer: prayer.isEmpty ? "Lord, guide us in Your truth. Amen." : prayer
        )
    }

    // MARK: - Study Plan Generation

    func generateStudyPlan(topic: String, duration: Int) async throws -> StudyPlan {
        try requireNonEmpty(topic, "Study topic")
        guard (1...365).contains(duration) else { throw BereanAIError.invalidDuration }

        let safeTopic = trimmed(topic, maxLength: 120)
        dlog("Generating \(duration)-day study plan for '\(safeTopic)'")

        let prompt = """
        Create a \(duration)-day Bible study plan on '\(safeTopic)'.
        Provide a clear title and a 2–3 sentence description of what the student will learn.
        Be specific and practical.
        """

        return try await perform {
            // Multi-day study plans are quality-critical — use Sonnet via .scholar mode.
            let response = try await self.aiService.sendMessageSync(prompt, mode: .scholar)
            return StudyPlan(
                id: UUID().uuidString,
                title: "\(duration)-Day Study: \(safeTopic)",
                duration: "\(duration) days",
                description: response,
                icon: "book.pages.fill",
                color: .blue,
                progress: 0
            )
        }
    }

    // MARK: - Scripture Analysis

    func analyzeScripture(reference: String, analysisType: ScriptureAnalysisType) async throws -> String {
        try requireNonEmpty(reference, "Scripture reference")
        let safeRef = trimmed(reference, maxLength: 200)
        dlog("Analyzing '\(safeRef)' — type: \(analysisType)")

        let prompt = """
        Provide a \(analysisType.rawValue) analysis of \(safeRef).
        Include historical context, meaning, and practical application.
        Be thorough but accessible.
        """

        return try await perform {
            // Scripture analysis requires precision — use Sonnet via .scholar mode.
            try await self.aiService.sendMessageSync(prompt, mode: .scholar)
        }
    }

    // MARK: - Memory Verse Helper

    func generateMemoryAid(verse: String, reference: String) async throws -> MemoryAid {
        try requireNonEmpty(verse, "Verse text")
        try requireNonEmpty(reference, "Verse reference")
        let safeVerse = trimmed(verse, maxLength: 2000)
        let safeRef = trimmed(reference, maxLength: 100)
        dlog("Generating memory aid for \(safeRef)")

        let prompt = """
        Provide practical memory techniques to memorize this verse:

        "\(safeVerse)" (\(safeRef))

        Include mnemonics, visualization tips, and key word associations.
        Format clearly with numbered steps.
        """

        return try await perform {
            let techniques = try await self.aiService.sendMessageSync(prompt)
            return MemoryAid(verse: safeVerse, reference: safeRef, techniques: techniques)
        }
    }

    // MARK: - AI Insights

    /// Returns up to 3 parsed insights. Uses JSON for reliable structure.
    func generateInsights(topic: String? = nil) async throws -> [AIInsight] {
        let safeTopic = topic.map { trimmed($0, maxLength: 120) }
        dlog("Generating AI insights" + (safeTopic.map { " for '\($0)'" } ?? ""))

        let topicClause = safeTopic.map { "about '\($0)'" } ?? "on a range of biblical themes"

        let prompt = """
        Generate exactly 3 biblical insights \(topicClause) as strict JSON only.
        Schema:
        {
          "insights": [
            { "title": "string", "verse": "string (e.g. Romans 8:28)", "content": "string (2–3 sentences)" },
            { "title": "string", "verse": "string", "content": "string" },
            { "title": "string", "verse": "string", "content": "string" }
          ]
        }
        No markdown, no commentary outside the JSON.
        """

        return try await perform {
            let response = try await self.aiService.sendMessageSync(prompt)
            return self.parseInsightsJSON(response)
        }
    }

    private func parseInsightsJSON(_ response: String) -> [AIInsight] {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        struct InsightDTO: Decodable {
            let title: String
            let verse: String
            let content: String
        }
        struct InsightsResponse: Decodable {
            let insights: [InsightDTO]
        }

        let icons  = ["lightbulb.fill", "star.fill", "book.fill"]
        let colors: [Color] = [.purple, .blue, .orange]

        if let data = cleaned.data(using: .utf8),
           let dto = try? JSONDecoder().decode(InsightsResponse.self, from: data) {
            return dto.insights.enumerated().map { idx, item in
                AIInsight(
                    title: item.title,
                    verse: item.verse,
                    content: item.content,
                    icon: icons[idx % icons.count],
                    color: colors[idx % colors.count]
                )
            }
        }

        // Fallback: return the blob as a single insight rather than silently returning nothing.
        dlog("Insights JSON parse failed — returning single fallback insight")
        return [AIInsight(title: "Biblical Insight", verse: "See response", content: cleaned,
                          icon: "lightbulb.fill", color: .purple)]
    }

    // MARK: - Fun Bible Fact

    func generateFunBibleFact(category: String? = nil) async throws -> String {
        let safeCategory = category.map { trimmed($0, maxLength: 80) }
        let prompt: String
        if let safeCategory {
            prompt = "Share an interesting and educational fact about \(safeCategory) from the Bible."
        } else {
            prompt = "Share an interesting and educational fact from the Bible."
        }
        return try await perform {
            try await self.aiService.sendMessageSync(prompt)
        }
    }

    // MARK: - AI-Powered Search

    func generateSearchSuggestions(query: String, context: String? = nil) async throws -> SearchSuggestions {
        try requireNonEmpty(query, "Search query")
        let safeQuery = trimmed(query, maxLength: 200)
        let safeContext = context.map { trimmed($0, maxLength: 80) } ?? "general biblical"
        dlog("Generating search suggestions for '\(safeQuery)'")

        let prompt = """
        Based on the search query '\(safeQuery)' in a \(safeContext) context, provide:
        - 5 related search terms (one per line, no bullets or numbering)
        - Then a blank line
        - 3 related biblical topics (one per line, no bullets or numbering)
        """

        return try await perform {
            let response = try await self.aiService.sendMessageSync(prompt)
            let parts = response.components(separatedBy: "\n\n")
            let suggestions = (parts.first ?? response)
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(5)
            let topics = (parts.dropFirst().first ?? "")
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(3)
            return SearchSuggestions(suggestions: Array(suggestions), relatedTopics: Array(topics))
        }
    }

    func enhanceBiblicalSearch(query: String, type: BiblicalSearchType) async throws -> BiblicalSearchResult {
        try requireNonEmpty(query, "Search query")
        let safeQuery = trimmed(query, maxLength: 200)
        dlog("Enhancing biblical search '\(safeQuery)' — type: \(type.rawValue)")

        let prompt = """
        Provide information about '\(safeQuery)' as a biblical \(type.rawValue) in strict JSON only.
        Schema:
        {
          "summary": "string (2–3 sentences)",
          "keyVerses": ["string", "string", "string"],
          "relatedPeople": ["string"],
          "funFacts": ["string", "string"]
        }
        No markdown, no commentary outside the JSON.
        """

        return try await perform {
            let response = try await self.aiService.sendMessageSync(prompt)
            let cleaned = response
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            struct ResultDTO: Decodable {
                let summary: String
                let keyVerses: [String]
                let relatedPeople: [String]
                let funFacts: [String]
            }

            if let data = cleaned.data(using: .utf8),
               let dto = try? JSONDecoder().decode(ResultDTO.self, from: data) {
                return BiblicalSearchResult(
                    query: safeQuery,
                    summary: dto.summary,
                    keyVerses: dto.keyVerses,
                    relatedPeople: dto.relatedPeople,
                    funFacts: dto.funFacts
                )
            }
            // Fallback to summary-only result.
            return BiblicalSearchResult(query: safeQuery, summary: cleaned, keyVerses: [], relatedPeople: [], funFacts: [])
        }
    }

    func suggestSearchFilters(query: String) async throws -> FilterSuggestion {
        try requireNonEmpty(query, "Search query")
        let safeQuery = trimmed(query, maxLength: 200)
        dlog("Suggesting filters for '\(safeQuery)'")

        let prompt = "Suggest relevant search filters for the biblical query: '\(safeQuery)'. Include categories like Testament, Book, Theme, etc."

        return try await perform {
            let response = try await self.aiService.sendMessageSync(prompt)
            return FilterSuggestion(filters: ["Testament", "Book", "Theme"], explanation: response)
        }
    }

    // MARK: - Legacy Compatibility (MessageAIService)

    /// Backward-compatible bridge for MessageAIService callers that still use
    /// the original Genkit flow-name pattern. [String: Any] is kept for source
    /// compatibility; new code should call typed methods directly.
    func callGenkitFlow(flowName: String, input: [String: Any]) async throws -> [String: Any] {
        dlog("Legacy flow: \(flowName)")

        let prompt = try legacyPrompt(flowName: flowName, input: input)
        let response = try await perform {
            try await self.aiService.sendMessageSync(prompt)
        }
        return ["response": response, "result": response]
    }

    private func legacyPrompt(flowName: String, input: [String: Any]) throws -> String {
        switch flowName {
        case "generateIceBreakers":
            let context = (input["context"] as? String).map { trimmed($0, maxLength: 80) } ?? "general"
            return "Generate 3 friendly, faith-forward ice breaker messages for starting a conversation in a \(context) context."

        case "generateSmartReplies":
            let message = (input["lastMessage"] as? String).map { trimmed($0, maxLength: 500) } ?? ""
            guard !message.isEmpty else { throw BereanAIError.emptyInput }
            return """
            Generate 3 short, kind smart reply suggestions to this message.
            Keep each under 60 characters.

            Message:
            \(message)
            """

        case "analyzeConversation":
            return "Analyze this conversation and provide constructive, faith-aligned insights."

        case "detectMessageTone":
            let message = (input["message"] as? String).map { trimmed($0, maxLength: 500) } ?? ""
            guard !message.isEmpty else { throw BereanAIError.emptyInput }
            return """
            Detect the tone of the message below.
            Reply with exactly one word from: positive, negative, neutral, encouraging, prayerful.

            Message:
            \(message)
            """

        case "suggestScriptureForMessage":
            let message = (input["message"] as? String).map { trimmed($0, maxLength: 500) } ?? ""
            guard !message.isEmpty else { throw BereanAIError.emptyInput }
            return """
            Suggest one relevant Bible verse for the message below.
            Provide only the reference and a one-sentence explanation.

            Message:
            \(message)
            """

        case "enhanceMessage":
            let message = (input["message"] as? String).map { trimmed($0, maxLength: 500) } ?? ""
            let style = (input["style"] as? String).map { trimmed($0, maxLength: 40) } ?? "friendly"
            guard !message.isEmpty else { throw BereanAIError.emptyInput }
            return """
            Rewrite the message below in a \(style) tone.
            Keep it concise and preserve the original intent.

            Message:
            \(message)
            """

        case "detectPrayerRequest":
            let message = (input["message"] as? String).map { trimmed($0, maxLength: 500) } ?? ""
            guard !message.isEmpty else { throw BereanAIError.emptyInput }
            return """
            Does the message below contain a prayer request?
            Reply with "yes" or "no". If yes, extract the request in one sentence.

            Message:
            \(message)
            """

        default:
            throw BereanAIError.unsupportedFlow(flowName)
        }
    }
}

// MARK: - Search Support Types

struct SearchSuggestions {
    let suggestions: [String]
    let relatedTopics: [String]
}

struct BiblicalSearchResult {
    let query: String
    let summary: String
    let keyVerses: [String]
    let relatedPeople: [String]
    let funFacts: [String]
}

enum BiblicalSearchType: String {
    case person
    case place
    case event
}

struct FilterSuggestion {
    let filters: [String]
    let explanation: String
}
