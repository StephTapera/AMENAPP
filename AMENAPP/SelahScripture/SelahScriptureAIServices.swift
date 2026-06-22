//
//  SelahScriptureAIServices.swift
//  AMENAPP
//
//  Three Selah AI services backed by the same real `ClaudeService.shared`
//  pipeline that `SelahService.askSelah(...)` already uses. Nothing here
//  invents content — every response is a real backend call to the Berean
//  Chat proxy with grounded prompts and transparent labeling.
//
//   * `SelahBereanContextService` — optional deeper-study mode that
//     surfaces historical, theological, and original-language context for
//     a verse / passage.
//   * `SelahReflectionRewritingService` — user-initiated rewriting of a
//     user's own reflection or prayer in four modes.
//   * `SelahScriptureCompanionService` — short, grounded conversational
//     follow-ups while the user is reading.
//
//  All three are exposed behind a feature flag and label every output as
//  AI-generated. None are auto-invoked.
//

import Foundation

// MARK: - AI Transparency Result

/// Output from a Selah AI service. The model never speaks in its own voice
/// without this envelope so the UI can clearly label generated content.
struct SelahScriptureAIResult: Equatable {
    let content: String
    let isAIGenerated: Bool
    let citations: [String]
    let generatedAt: Date

    init(content: String,
         citations: [String] = [],
         isAIGenerated: Bool = true,
         generatedAt: Date = Date()) {
        self.content = content
        self.citations = citations
        self.isAIGenerated = isAIGenerated
        self.generatedAt = generatedAt
    }
}

enum SelahScriptureAIServiceError: LocalizedError {
    case featureDisabled
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .featureDisabled: return "This AI feature is not enabled in this build."
        case .emptyResponse:   return "The model returned no content."
        }
    }
}

// MARK: - Shared helper

@MainActor
private enum SelahScriptureAIRunner {

    /// Streams a Claude response and returns the full concatenated body.
    /// Uses the exact same `ClaudeService.shared.sendMessage` pipeline that
    /// `SelahService` already relies on, so behavior is consistent.
    static func runOnce(
        prompt: String,
        maxTokens: Int = 1500,
        temperature: Double = 0.55,
        systemSuffix: String? = nil
    ) async throws -> String {
        var accumulated = ""
        let stream = ClaudeService.shared.sendMessage(
            prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            mode: .shepherd,
            systemPromptSuffix: systemSuffix
        )
        for try await chunk in stream {
            accumulated += chunk
        }
        return accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Berean Context Mode

@MainActor
final class SelahBereanContextService {
    static let shared = SelahBereanContextService()
    private init() {}

    /// Compose a grounded deeper-study response for a passage.
    func deeperStudy(
        for reference: SelahScriptureReference,
        translationAbbreviation: String,
        verseText: String?
    ) async throws -> SelahScriptureAIResult {
        guard AMENFeatureFlags.shared.selahScriptureActionsEnabled else {
            throw SelahScriptureAIServiceError.featureDisabled
        }

        let systemSuffix = """
        You are Berean, a careful and theologically conservative Bible study
        companion. The user has opened a "deeper study" view on a passage.
        Produce a calm, structured response with these sections, each marked
        with a clear heading on its own line:

        Historical context.
        Literary context.
        Key terms (with brief original-language notes where well-attested).
        Cross references.
        Pastoral takeaway.

        Constraints:
        - Stay grounded in widely-accepted scholarship.
        - Never invent quotations from commentators.
        - Never make claims about words in Hebrew / Greek you are uncertain about.
        - When a section has nothing reliable to say, write "Nothing to add."
        - Keep total length under 350 words.
        """

        let body = verseText.map { "Verse text: \"\($0)\"" } ?? "Verse text not bundled in this build."
        let prompt = """
        Passage: \(reference.displayString) (\(translationAbbreviation))
        \(body)

        Produce the deeper study now.
        """

        let response = try await SelahScriptureAIRunner.runOnce(
            prompt: prompt,
            maxTokens: 1800,
            temperature: 0.4,
            systemSuffix: systemSuffix
        )
        guard !response.isEmpty else { throw SelahScriptureAIServiceError.emptyResponse }
        return SelahScriptureAIResult(content: response, citations: [reference.displayString])
    }
}

// MARK: - Reflection Rewriting

enum SelahReflectionRewriteMode: String, CaseIterable, Identifiable {
    case simplify
    case poetic
    case journal
    case prayer

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .simplify: return "Simplify"
        case .poetic:   return "Poetic"
        case .journal:  return "Journal"
        case .prayer:   return "Prayer"
        }
    }
    var systemSuffix: String {
        switch self {
        case .simplify:
            return "Rewrite the user's reflection in clearer, simpler language. Keep the meaning unchanged. Do not add new ideas or scripture references."
        case .poetic:
            return "Rewrite the user's reflection in a calm, poetic register. Keep the meaning unchanged. Do not embellish or invent."
        case .journal:
            return "Rewrite the user's reflection as a first-person journal entry, contemplative and honest. Keep the meaning unchanged."
        case .prayer:
            return "Rewrite the user's reflection as a heartfelt prayer addressed to God. Keep the meaning and emotional center unchanged."
        }
    }
}

@MainActor
final class SelahReflectionRewritingService {
    static let shared = SelahReflectionRewritingService()
    private init() {}

    func rewrite(
        _ text: String,
        mode: SelahReflectionRewriteMode
    ) async throws -> SelahScriptureAIResult {
        guard AMENFeatureFlags.shared.selahScriptureActionsEnabled else {
            throw SelahScriptureAIServiceError.featureDisabled
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SelahScriptureAIServiceError.emptyResponse }

        let systemSuffix = """
        \(mode.systemSuffix)

        Rules:
        - Never fabricate scripture references.
        - Never claim certainty the original text didn't claim.
        - Output ONLY the rewritten text. No preamble, no explanation.
        - Keep the rewritten text within 1.5× the length of the input.
        """

        let prompt = """
        Original reflection:
        \"\"\"
        \(trimmed)
        \"\"\"
        """

        let response = try await SelahScriptureAIRunner.runOnce(
            prompt: prompt,
            maxTokens: 800,
            temperature: 0.6,
            systemSuffix: systemSuffix
        )
        guard !response.isEmpty else { throw SelahScriptureAIServiceError.emptyResponse }
        return SelahScriptureAIResult(content: response)
    }
}

// MARK: - Scripture Companion

@MainActor
final class SelahScriptureCompanionService {
    static let shared = SelahScriptureCompanionService()
    private init() {}

    /// Ask a grounded follow-up while reading a chapter / verse.
    func ask(
        _ question: String,
        about reference: SelahScriptureReference,
        translationAbbreviation: String,
        visibleVerses: [String]
    ) async throws -> SelahScriptureAIResult {
        guard AMENFeatureFlags.shared.selahScriptureActionsEnabled else {
            throw SelahScriptureAIServiceError.featureDisabled
        }
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { throw SelahScriptureAIServiceError.emptyResponse }

        let scriptureContext = visibleVerses.isEmpty
            ? "(No verse text bundled — answer in general terms only.)"
            : visibleVerses.prefix(8).joined(separator: " ")

        let systemSuffix = """
        You are the Selah Scripture Companion. Answer the user's question briefly
        (under 180 words), grounded in the passage they are reading.

        Rules:
        - Cite the passage and any other reference in [square brackets].
        - Never fabricate citations from commentators or scholars.
        - Be calm, pastoral, doctrinally neutral where reasonable.
        - If the question is outside the passage, gently redirect or say
          "I don't have a confident answer for that."
        - End with a single short reflective question for the reader.
        """

        let prompt = """
        Passage: \(reference.displayString) (\(translationAbbreviation))
        Passage text: \(scriptureContext)

        User question: \(trimmedQuestion)
        """

        let response = try await SelahScriptureAIRunner.runOnce(
            prompt: prompt,
            maxTokens: 700,
            temperature: 0.55,
            systemSuffix: systemSuffix
        )
        guard !response.isEmpty else { throw SelahScriptureAIServiceError.emptyResponse }
        return SelahScriptureAIResult(content: response, citations: [reference.displayString])
    }
}
