// PostTranslationService.swift
// AMENAPP
//
// Wraps BereanContextualTranslationEngine for inline feed translation.
// Uses NaturalLanguage for on-device language detection and an in-memory
// cache to prevent redundant network calls on scroll.

import Foundation
import NaturalLanguage

// MARK: - TranslationLanguage

/// AMEN-side language enum that maps to BereanSupportedLanguage.
/// Includes Italian and Japanese even though BereanSupportedLanguage does not
/// yet support them — those cases produce a .unsupportedLanguagePair error.
enum TranslationLanguage: String, CaseIterable {
    case english    = "en"
    case spanish    = "es"
    case french     = "fr"
    case portuguese = "pt"
    case chinese    = "zh"
    case korean     = "ko"
    case arabic     = "ar"
    case german     = "de"
    case hindi      = "hi"
    case italian    = "it"
    case japanese   = "ja"

    var displayName: String {
        switch self {
        case .english:    return "English"
        case .spanish:    return "Spanish"
        case .french:     return "French"
        case .portuguese: return "Portuguese"
        case .chinese:    return "Chinese (Simplified)"
        case .korean:     return "Korean"
        case .arabic:     return "Arabic"
        case .german:     return "German"
        case .hindi:      return "Hindi"
        case .italian:    return "Italian"
        case .japanese:   return "Japanese"
        }
    }

    /// BCP-47 language code.
    var locale: String { rawValue }

    /// Corresponding BereanSupportedLanguage, or nil for engine-unsupported languages.
    var bereanLanguage: BereanSupportedLanguage? {
        switch self {
        case .english:    return .english
        case .spanish:    return .spanish
        case .french:     return .french
        case .portuguese: return .portuguese
        case .chinese:    return .mandarin
        case .korean:     return .korean
        case .arabic:     return .arabic
        case .german:     return .german
        case .hindi:      return .hindi
        case .italian:    return nil   // not yet supported by Berean engine
        case .japanese:   return .japanese
        }
    }

    /// Build a TranslationLanguage from a BCP-47 code.  Handles "zh-Hans" → .chinese.
    static func from(bcp47 code: String) -> TranslationLanguage? {
        let base = code.components(separatedBy: "-").first?.lowercased() ?? code.lowercased()
        return TranslationLanguage(rawValue: base)
    }
}

// MARK: - TranslatedPost

struct TranslatedPost: Codable {
    let postId: String
    let originalText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
    let timestamp: Date
}

// MARK: - PostTranslationError

enum PostTranslationError: LocalizedError {
    case unsupportedLanguagePair(String)
    case engineUnavailable
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguagePair(let lang):
            return "Translation to \(lang) is not yet supported."
        case .engineUnavailable:
            return "The translation service is currently unavailable."
        case .emptyResult:
            return "Translation returned an empty result."
        }
    }
}

// MARK: - PostTranslationService

@MainActor
final class PostTranslationService {

    static let shared = PostTranslationService()

    // In-memory cache keyed by "<postId>_<targetLang>"
    private var cache: [String: TranslatedPost] = [:]

    private let engine = BereanContextualTranslationEngine.shared

    private init() {
        dlog("PostTranslationService initialized")
    }

    // MARK: - Public API

    /// Translate post text to the given target language.
    /// Checks the in-memory cache first (1-hour TTL) before calling the engine.
    func translate(
        postId: String,
        text: String,
        to targetLang: TranslationLanguage
    ) async throws -> TranslatedPost {
        let cacheKey = "\(postId)_\(targetLang.rawValue)"

        // Cache hit
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < 3_600 {
            dlog("PostTranslationService: cache hit for \(cacheKey)")
            return cached
        }

        // Engine availability check
        guard let bereanTarget = targetLang.bereanLanguage else {
            throw PostTranslationError.unsupportedLanguagePair(targetLang.displayName)
        }

        // Detect source language (best-effort; fall back to .english)
        let detectedSource = detectLanguage(of: text)
        let bereanSource: BereanSupportedLanguage = detectedSource?.bereanLanguage ?? .english

        dlog("PostTranslationService: translating \(postId) \(bereanSource.rawValue) → \(bereanTarget.rawValue)")

        let result: BereanTranslationResult
        do {
            result = try await engine.translatePostOrComment(
                text,
                from: bereanSource,
                to: bereanTarget,
                contentKind: "post",
                contentId: postId,
                visibility: "private"
            )
        } catch {
            dlog("PostTranslationService: engine error \(error)")
            throw error
        }

        guard !result.translatedText.isEmpty else {
            throw PostTranslationError.emptyResult
        }

        let translated = TranslatedPost(
            postId: postId,
            originalText: text,
            translatedText: result.translatedText,
            sourceLanguage: result.sourceLanguage.rawValue,
            targetLanguage: result.targetLanguage.rawValue,
            timestamp: Date()
        )

        cache[cacheKey] = translated

        NotificationCenter.default.post(
            name: Notification.Name("AMENPostTranslated"),
            object: nil,
            userInfo: ["postId": postId]
        )

        return translated
    }

    /// Detect the dominant language of a text string using NLLanguageRecognizer.
    /// Returns nil if confidence is too low or language is unrecognised.
    func detectLanguage(of text: String) -> TranslationLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let dominant = recognizer.dominantLanguage,
              dominant != .undetermined else { return nil }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard (hypotheses[dominant] ?? 0) >= 0.5 else { return nil }

        // NLLanguage.rawValue is BCP-47 (e.g. "zh-Hans") — strip subtag
        let base = dominant.rawValue.components(separatedBy: "-").first ?? dominant.rawValue
        return TranslationLanguage(rawValue: base.lowercased())
    }

    /// Returns true if the text is likely NOT in the device's preferred language
    /// with confidence above 0.7.
    func shouldOfferTranslation(for text: String) -> Bool {
        guard text.count > 10 else { return false }   // too short to detect reliably

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let dominant = recognizer.dominantLanguage,
              dominant != .undetermined else { return false }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[dominant] ?? 0
        guard confidence > 0.7 else { return false }

        let detectedBase = dominant.rawValue.components(separatedBy: "-").first?.lowercased()
            ?? dominant.rawValue.lowercased()

        let deviceBase: String
        if #available(iOS 16, *) {
            deviceBase = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        } else {
            deviceBase = Locale.current.languageCode?.lowercased() ?? "en"
        }

        return detectedBase != deviceBase
    }

    /// The TranslationLanguage that best matches the device's current locale.
    var preferredLanguage: TranslationLanguage {
        let deviceCode: String
        if #available(iOS 16, *) {
            deviceCode = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        } else {
            deviceCode = Locale.current.languageCode?.lowercased() ?? "en"
        }
        return TranslationLanguage(rawValue: deviceCode) ?? .english
    }

    /// Clear the entire in-memory translation cache.
    func clearCache() {
        cache.removeAll()
        dlog("PostTranslationService: cache cleared")
    }

    // MARK: - Backward-compatibility shims
    //
    // PostCard.swift, PostCardViewModel.swift, and PostCardServices.swift call these
    // signatures from the previous Apple-Translation-based implementation.
    // They bridge to the new BereanContextualTranslationEngine path.

    /// Detect language and return a BCP-47 string (e.g. "es").
    /// Matches the old async-throws signature used by PostCardViewModel.
    func detectLanguage(_ text: String) async throws -> String {
        return detectLanguage(of: text)?.locale ?? "en"
    }

    /// Returns the device's preferred language as a BCP-47 string.
    func getDeviceLanguage() -> String {
        return preferredLanguage.locale
    }

    /// Translate arbitrary text from one BCP-47 code to another, returning the
    /// translated string.  Uses a synthetic postId derived from the text hash so
    /// the in-memory cache still prevents redundant calls.
    func translateText(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> String {
        let targetLang = TranslationLanguage.from(bcp47: targetLanguage) ?? .english
        let syntheticId = "text_\(text.hashValue)"
        let result = try await translate(postId: syntheticId, text: text, to: targetLang)
        return result.translatedText
    }
}
