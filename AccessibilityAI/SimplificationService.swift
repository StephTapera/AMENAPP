// SimplificationService.swift
// AMEN Universal Accessibility Engine — A5 Comprehension & Simplification
// Preserves author meaning. Only adjusts reading level of expression.

import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - Models

struct GlossEntry: Codable {
    let term: String
    let simplifiedDefinition: String
}

struct SimplificationResult: Codable {
    let originalText: String
    let simplifiedText: String
    let targetLevel: ReadingLevel
    let glossary: [GlossEntry]       // struggle terms with inline definitions
    let aiContribution: AIContribution
}

// MARK: - Actor

actor SimplificationService {

    static let shared = SimplificationService()

    private let functions = Functions.functions()

    private init() {}

    // MARK: - Simplify

    /// Rewrites `text` to the target `ReadingLevel`.
    /// Author meaning is NEVER altered — only the reading level of expression changes.
    func simplify(
        text: String,
        to level: ReadingLevel,
        struggleTerms: [String] = []
    ) async throws -> SimplificationResult {

        let flags = await TrustAccessibilityFeatureFlags.shared.a11ySimplifyEnabled
        guard flags else {
            throw SimplificationError.featureDisabled
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SimplificationError.emptyInput
        }

        let params: [String: Any] = [
            "text": text,
            "targetLevel": level.rawValue,
            "struggleTerms": struggleTerms
        ]

        let result: HTTPSCallableResult
        do {
            result = try await functions
                .httpsCallable(TrustA11yCallable.a11ySimplifyProxy.rawValue)
                .call(params)
        } catch let error as NSError {
            throw SimplificationError.from(error)
        }

        guard let data = result.data as? [String: Any] else {
            throw SimplificationError.malformedResponse("Top-level data was not a dictionary")
        }

        let simplifiedText = data["simplifiedText"] as? String ?? text
        let jobId          = data["jobId"]           as? String ?? UUID().uuidString
        let model          = data["model"]           as? String ?? "unknown"

        // Parse glossary array: [{term, definition}]
        var glossary: [GlossEntry] = []
        if let rawGlossary = data["glossary"] as? [[String: String]] {
            glossary = rawGlossary.compactMap { entry in
                guard
                    let term = entry["term"],
                    let definition = entry["definition"]
                else { return nil }
                return GlossEntry(term: term, simplifiedDefinition: definition)
            }
        }

        let contribution = AIContribution(
            type: .simplification,
            model: model,
            jobId: jobId,
            timestamp: Date(),
            humanEdited: false
        )

        return SimplificationResult(
            originalText: text,
            simplifiedText: simplifiedText,
            targetLevel: level,
            glossary: glossary,
            aiContribution: contribution
        )
    }

    // MARK: - Summarize

    /// Returns a concise summary of `text` in at most `maxSentences` sentences.
    func summarize(text: String, maxSentences: Int = 3) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        let params: [String: Any] = [
            "text": text,
            "maxSentences": maxSentences
        ]

        let result: HTTPSCallableResult
        do {
            result = try await functions
                .httpsCallable(TrustA11yCallable.a11ySummarizeProxy.rawValue)
                .call(params)
        } catch let error as NSError {
            throw SimplificationError.from(error)
        }

        guard let data = result.data as? [String: Any] else {
            return ""
        }

        return data["summary"] as? String ?? ""
    }
}

// MARK: - Error

enum SimplificationError: LocalizedError {
    case featureDisabled
    case emptyInput
    case malformedResponse(String)
    case cloudFunctionError(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "Content simplification is not available right now."
        case .emptyInput:
            return "There is no text to simplify."
        case .malformedResponse(let detail):
            return "We received an unexpected response from the server. (\(detail))"
        case .cloudFunctionError(let message):
            return message
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }

    static func from(_ error: NSError) -> SimplificationError {
        // Firebase Functions error codes
        if error.domain == FunctionsErrorDomain {
            let code = FunctionsErrorCode(rawValue: error.code)
            switch code {
            case .resourceExhausted:
                return .cloudFunctionError("You have reached the simplification limit. Please try again later.")
            case .unauthenticated:
                return .cloudFunctionError("Please sign in to use content simplification.")
            case .permissionDenied:
                return .cloudFunctionError("You don't have permission to use this feature.")
            case .unavailable:
                return .cloudFunctionError("The simplification service is temporarily unavailable.")
            default:
                let message = error.localizedDescription
                return .cloudFunctionError(message.isEmpty ? "An error occurred." : message)
            }
        }
        return .unknown
    }
}
