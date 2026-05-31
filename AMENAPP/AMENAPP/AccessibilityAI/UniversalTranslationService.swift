// UniversalTranslationService.swift
// AMEN Universal Accessibility Engine — A2 Translation
// Phase 2: Translation via Firebase callable proxy.
// Translation is additive only — original text is always preserved and accessible.

import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - UniversalTranslationService

actor UniversalTranslationService {
    static let shared = UniversalTranslationService()

    private let functions = Functions.functions()

    private init() {}

    // MARK: - Translate

    /// Translates `text` from `sourceLang` to `targetLang` via the `a11yTranslateProxy` callable.
    /// - Parameters:
    ///   - text: The original text. Always preserved — translation is additive.
    ///   - sourceLang: BCP-47 language code (e.g. "en", "es").
    ///   - targetLang: BCP-47 language code for the desired output.
    ///   - preserveMeaning: Instructs the backend to prioritise meaning fidelity.
    ///   - faithContext: Instructs the backend to respect theological/faith terminology.
    /// - Returns: A tuple of the translated string, a confidence score (0–1), and an AIContribution.
    func translate(
        text: String,
        from sourceLang: String,
        to targetLang: String,
        preserveMeaning: Bool = true,
        faithContext: Bool = true
    ) async throws -> (translated: String, confidence: Double, aiContribution: C2PAAIContribution) {
        guard await TrustAccessibilityFeatureFlags.shared.a11yTranslateEnabled else {
            throw TranslationError.featureDisabled
        }

        let callable = functions.httpsCallable(TrustA11yCallable.a11yTranslateProxy.rawValue)
        let params: [String: Any] = [
            "text": text,
            "sourceLang": sourceLang,
            "targetLang": targetLang,
            "preserveMeaning": preserveMeaning,
            "faithContext": faithContext
        ]

        let result: HTTPSCallableResult
        do {
            result = try await callable.call(params)
        } catch let error as NSError {
            throw TranslationError.callableFailed(underlyingMessage: error.localizedDescription)
        }

        guard let data = result.data as? [String: Any] else {
            throw TranslationError.malformedResponse("Root data is not a dictionary")
        }

        guard let translated = data["translated"] as? String else {
            throw TranslationError.malformedResponse("Missing 'translated' field")
        }

        let confidence = data["confidence"] as? Double ?? 0.9
        let model = data["model"] as? String ?? "gpt-4o-mini"
        let jobId = data["jobId"] as? String ?? UUID().uuidString

        let aiContribution = C2PAAIContribution(
            type: .translation,
            model: model,
            jobId: jobId,
            timestamp: Date(),
            humanEdited: false
        )

        return (translated: translated, confidence: confidence, aiContribution: aiContribution)
    }

    // MARK: - Auto-Detect Language

    /// Detects the language of `text` using the `a11yTranslateProxy` callable.
    /// Returns a BCP-47 language code string (e.g. "en", "es", "fr").
    func autoDetectLanguage(text: String) async throws -> String {
        let callable = functions.httpsCallable(TrustA11yCallable.a11yTranslateProxy.rawValue)
        let params: [String: Any] = [
            "detectOnly": true,
            "text": text
        ]

        let result: HTTPSCallableResult
        do {
            result = try await callable.call(params)
        } catch let error as NSError {
            throw TranslationError.callableFailed(underlyingMessage: error.localizedDescription)
        }

        guard let data = result.data as? [String: Any] else {
            return "en"
        }

        return data["detectedLanguage"] as? String ?? "en"
    }
}

// MARK: - Errors

enum TranslationError: LocalizedError {
    case featureDisabled
    case callableFailed(underlyingMessage: String)
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "Translation is not available right now."
        case .callableFailed(let msg):
            return "Translation request failed: \(msg)"
        case .malformedResponse(let detail):
            return "Unexpected translation response: \(detail)"
        }
    }
}
