//
//  PostTranslationService.swift
//  AMENAPP
//
//  On-device language detection (NaturalLanguage) + on-device translation
//  (Apple Translation framework, iOS 17.4+).
//
//  Pipeline:
//    1. detectLanguage() — NaturalLanguage.NLLanguageRecognizer (instant, free, private)
//    2. translateText()  — Apple Translation session (on-device model, no API cost)
//    3. In-memory cache (1 hour TTL) + Firestore cache (7 days TTL) for cross-device reuse
//
//  No OpenAI calls for language detection or translation.
//

import Foundation
import Combine
import NaturalLanguage
import Translation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class PostTranslationService: ObservableObject {
    static let shared = PostTranslationService()

    @Published var isTranslating = false
    @Published var translationCache: [String: CachedTranslation] = [:]

    private let db = Firestore.firestore()
    let deviceLanguage: String = Locale.current.language.languageCode?.identifier ?? "en"

    struct CachedTranslation: Codable {
        let originalText: String
        let translatedText: String
        let sourceLanguage: String
        let targetLanguage: String
        let timestamp: Date
    }

    private init() {
        dlog("✅ PostTranslationService initialized (device language: \(deviceLanguage))")
    }

    // MARK: - Language Detection (on-device, NaturalLanguage)

    /// Returns the ISO 639-1 language code for the given text using NLLanguageRecognizer.
    /// Falls back to "en" if confidence is below threshold or recognition fails.
    func detectLanguage(_ text: String) async throws -> String {
        // NLLanguageRecognizer is synchronous and fast — run off main thread to avoid any
        // momentary jank on long posts.
        return await Task.detached(priority: .userInitiated) {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)

            // Require at least 0.5 confidence to avoid misidentifying very short strings.
            guard let dominant = recognizer.dominantLanguage,
                  dominant != .undetermined else {
                return "en"
            }

            let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
            let confidence = hypotheses[dominant] ?? 0
            guard confidence >= 0.5 else { return "en" }

            // NLLanguage.rawValue is a BCP 47 tag like "en", "es", "zh-Hans".
            // Strip any region/script subtag to get the bare two-letter code.
            let raw = dominant.rawValue
            let base = raw.components(separatedBy: "-").first ?? raw
            return base.lowercased()
        }.value
    }

    // MARK: - Translation (on-device, Apple Translation framework)

    /// Translates text using Apple's on-device Translation framework.
    /// Falls back to the original text if the language pair is unsupported or the
    /// model download fails.
    func translateText(_ text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String {
        // 1. In-memory cache hit
        let cacheKey = "\(sourceLanguage)_\(targetLanguage)_\(text.hashValue)"
        if let cached = translationCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < 3600 {
            return cached.translatedText
        }

        // 2. Apple Translation session — headless (no SwiftUI view needed).
        // init(installedSource:target:) requires on-device language models; throws if not installed.
        let sourceLang = Locale.Language(identifier: sourceLanguage)
        let targetLang = Locale.Language(identifier: targetLanguage)

        let translated: String = try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    let session = TranslationSession(installedSource: sourceLang, target: targetLang)
                    let response = try await session.translate(text)
                    continuation.resume(returning: response.targetText)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        let result = translated.trimmingCharacters(in: .whitespacesAndNewlines)

        // 3. Store in memory cache
        let cached = CachedTranslation(
            originalText: text,
            translatedText: result,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            timestamp: Date()
        )
        translationCache[cacheKey] = cached

        // 4. Store in Firestore for cross-device reuse (fire-and-forget)
        Task.detached(priority: .background) {
            try? await self.storeTranslationInFirestore(cacheKey: cacheKey, translation: cached)
        }

        return result
    }

    // MARK: - Firestore cache

    private func storeTranslationInFirestore(cacheKey: String, translation: CachedTranslation) async throws {
        try await db.collection("translations").document(cacheKey).setData([
            "originalText": translation.originalText,
            "translatedText": translation.translatedText,
            "sourceLanguage": translation.sourceLanguage,
            "targetLanguage": translation.targetLanguage,
            "timestamp": Timestamp(date: translation.timestamp)
        ])
    }

    func fetchTranslationFromFirestore(text: String, sourceLanguage: String, targetLanguage: String) async throws -> String? {
        let cacheKey = "\(sourceLanguage)_\(targetLanguage)_\(text.hashValue)"
        let doc = try await db.collection("translations").document(cacheKey).getDocument()

        guard doc.exists,
              let data = doc.data(),
              let translatedText = data["translatedText"] as? String,
              let timestamp = data["timestamp"] as? Timestamp else { return nil }

        let age = Date().timeIntervalSince(timestamp.dateValue())
        guard age < 604_800 else { return nil } // 7-day TTL

        translationCache[cacheKey] = CachedTranslation(
            originalText: text,
            translatedText: translatedText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            timestamp: timestamp.dateValue()
        )
        return translatedText
    }

    // MARK: - Convenience

    /// Translate a full post, returning the original unchanged if the post is already
    /// in the device language or if translation fails.
    func translatePost(_ post: Post) async -> Post {
        do {
            let sourceLang = try await detectLanguage(post.content)
            guard sourceLang != deviceLanguage else { return post }

            // Firestore cache first
            if let cached = try await fetchTranslationFromFirestore(
                text: post.content, sourceLanguage: sourceLang, targetLanguage: deviceLanguage) {
                var p = post; p.content = cached; return p
            }

            isTranslating = true
            defer { isTranslating = false }

            let translated = try await translateText(post.content, from: sourceLang, to: deviceLanguage)
            var p = post; p.content = translated; return p
        } catch {
            isTranslating = false
            return post
        }
    }

    func getDeviceLanguage() -> String { deviceLanguage }
}
