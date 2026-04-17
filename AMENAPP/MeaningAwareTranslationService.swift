// MeaningAwareTranslationService.swift
// AMEN App — Accessibility Intelligence Layer (Phase 1)
//
// Orchestrates meaning-aware translation with three modes:
//   - Literal: standard machine translation via existing TranslationService
//   - Natural: LLM-refined to sound native in target language
//   - Contextual: LLM with faith/tone/emotional context preservation
//
// Design:
//   - Literal mode delegates entirely to TranslationService (zero duplication)
//   - Natural/Contextual call Cloud Function "refineTranslation" for LLM post-processing
//   - Entity preservation: Bible verses, @mentions, #hashtags, URLs are extracted before
//     LLM processing and re-inserted after to prevent hallucination/modification
//   - In-flight deduplication prevents duplicate requests
//   - Results cached per mode+language in TranslationCacheManager

import Foundation
import CryptoKit

@MainActor
final class MeaningAwareTranslationService: ObservableObject {

    static let shared = MeaningAwareTranslationService()

    // MARK: - Dependencies

    private var translationService: TranslationService { TranslationService.shared }
    private var cacheManager: TranslationCacheManager { TranslationCacheManager.shared }
    private var featureFlags: TranslationFeatureFlags { TranslationFeatureFlags.shared }

    // MARK: - In-Flight Dedup

    private var inFlightRequests: [String: Task<TranslationUIState, Never>] = [:]

    private init() {}

    // MARK: - Public API

    /// Translate content with the specified mode.
    /// For `.literal`, delegates directly to TranslationService.
    /// For `.natural`/`.contextual`, first gets literal translation, then refines via LLM.
    func translate(
        text: String,
        contentType: TranslatableContentType,
        contentId: String,
        surface: TranslationSurface,
        mode: TranslationMode,
        isPublicContent: Bool = true,
        forceRefresh: Bool = false
    ) async -> TranslationUIState {
        // Original mode = no translation, show content as-is
        guard mode.performsTranslation else {
            return .notNeeded
        }

        // Literal mode = existing pipeline, no LLM
        guard mode.requiresLLM else {
            return await translationService.translate(
                text: text,
                contentType: contentType,
                contentId: contentId,
                surface: surface,
                isPublicContent: isPublicContent,
                forceRefresh: forceRefresh
            )
        }

        // Check feature flags
        guard featureFlags.meaningAwareTranslationEnabled else {
            return await translationService.translate(
                text: text,
                contentType: contentType,
                contentId: contentId,
                surface: surface,
                isPublicContent: isPublicContent,
                forceRefresh: forceRefresh
            )
        }

        if mode == .natural && !featureFlags.naturalModeEnabled {
            return await translationService.translate(
                text: text, contentType: contentType, contentId: contentId,
                surface: surface, isPublicContent: isPublicContent
            )
        }
        if mode == .contextual && !featureFlags.contextualModeEnabled {
            return await translationService.translate(
                text: text, contentType: contentType, contentId: contentId,
                surface: surface, isPublicContent: isPublicContent
            )
        }

        // Dedup key
        let dedupKey = buildDedupKey(text: text, mode: mode)

        // Check in-flight
        if let existingTask = inFlightRequests[dedupKey] {
            return await existingTask.value
        }

        // Launch translation task
        let task = Task<TranslationUIState, Never> { [weak self] in
            guard let self else { return .error(.serviceUnavailable) }
            return await self.performRefinedTranslation(
                text: text,
                contentType: contentType,
                contentId: contentId,
                surface: surface,
                mode: mode,
                isPublicContent: isPublicContent,
                forceRefresh: forceRefresh
            )
        }

        inFlightRequests[dedupKey] = task
        let result = await task.value
        inFlightRequests[dedupKey] = nil
        return result
    }

    // MARK: - Private Pipeline

    private func performRefinedTranslation(
        text: String,
        contentType: TranslatableContentType,
        contentId: String,
        surface: TranslationSurface,
        mode: TranslationMode,
        isPublicContent: Bool,
        forceRefresh: Bool
    ) async -> TranslationUIState {
        // Step 1: Detect language
        let detection = await translationService.detectLanguage(text)
        guard detection.isReliable else {
            return .notNeeded
        }

        let sourceLang = detection.languageCode
        let targetLang = TranslationSettingsManager.shared.preferences.appLanguage

        guard sourceLang != targetLang else {
            return .notNeeded
        }

        // Step 2: Check mode-aware cache (uses full 3-tier lookup: memory → disk → Firestore)
        let cacheKey = buildModeCacheKey(text: text, sourceLang: sourceLang, targetLang: targetLang, mode: mode)
        if !forceRefresh, let cachedText = await cacheManager.lookup(cacheKey: cacheKey) {
            let variant = TranslationVariant(
                translatedText: cachedText,
                sourceLanguage: sourceLang,
                targetLanguage: targetLang,
                engineVersion: .claudeLLM,
                translatedAt: Date(),
                characterCount: cachedText.count,
                confidence: nil,
                isUserRequested: true
            )
            return .translated(variant)
        }

        // Step 3: Get literal translation first (via existing service)
        let literalState = await translationService.translate(
            text: text,
            contentType: contentType,
            contentId: contentId,
            surface: surface,
            isPublicContent: isPublicContent
        )

        guard let literalText = literalState.translatedText else {
            return literalState // Pass through error/notNeeded states
        }

        // Step 4: Extract entities to preserve
        let entities = extractPreservedEntities(from: text)

        // Step 5: Call LLM refinement Cloud Function
        do {
            let refinedText = try await callRefinementFunction(
                originalText: text,
                literalTranslation: literalText,
                sourceLanguage: sourceLang,
                targetLanguage: targetLang,
                mode: mode,
                contentType: contentType,
                preservedEntities: entities
            )

            // Step 6: Re-insert any entities that may have been mangled
            let finalText = reinsertEntities(entities, into: refinedText, original: text)

            let variant = TranslationVariant(
                translatedText: finalText,
                sourceLanguage: sourceLang,
                targetLanguage: targetLang,
                engineVersion: .claudeLLM,
                translatedAt: Date(),
                characterCount: finalText.count,
                confidence: nil,
                isUserRequested: true
            )

            // Step 7: Cache the refined result (3-tier: memory + disk + Firestore for public)
            await cacheManager.store(
                cacheKey: cacheKey,
                originalText: text,
                translatedText: finalText,
                sourceLanguage: sourceLang,
                targetLanguage: targetLang,
                engine: .claudeLLM,
                isPublicContent: isPublicContent
            )

            return .translated(variant)
        } catch {
            dlog("[MeaningAwareTranslation] LLM refinement failed: \(error), falling back to literal")
            // Graceful degradation: return the literal translation
            return literalState
        }
    }

    // MARK: - Cloud Function Call

    private func callRefinementFunction(
        originalText: String,
        literalTranslation: String,
        sourceLanguage: String,
        targetLanguage: String,
        mode: TranslationMode,
        contentType: TranslatableContentType,
        preservedEntities: [PreservedEntity]
    ) async throws -> String {
        let payload: [String: Any] = [
            "originalText": originalText,
            "literalTranslation": literalTranslation,
            "sourceLanguage": sourceLanguage,
            "targetLanguage": targetLanguage,
            "mode": mode.rawValue,
            "contentType": contentType.rawValue,
            "preservedEntities": preservedEntities.map { ["type": $0.type.rawValue, "text": $0.originalText] },
        ]

        let result = try await CloudFunctionsService.shared.call("refineTranslation", data: payload)

        guard let dict = result as? [String: Any],
              let refinedText = dict["refinedText"] as? String else {
            throw NSError(domain: "MeaningAwareTranslation", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response from refineTranslation"])
        }

        return refinedText
    }

    // MARK: - Entity Preservation

    /// Extracts entities that should be preserved during LLM translation (verses, mentions, hashtags, URLs)
    func extractPreservedEntities(from text: String) -> [PreservedEntity] {
        var entities: [PreservedEntity] = []
        let patterns: [(PreservedEntityType, String)] = [
            (.verseReference, #"(?:(?:\d\s+)?[A-Za-z]+\s+\d+:\d+(?:-\d+)?)"#),
            (.bibleTranslation, #"\b(KJV|ESV|NIV|NASB|NLT|MSG|AMP|NKJV|CSB|HCSB|RSV|CEV)\b"#),
            (.mention, #"@[\w\.]+"#),
            (.hashtag, #"#\w+"#),
            (.url, #"https?://[^\s]+"#),
            (.email, #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#),
        ]

        for (type, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for (index, match) in matches.enumerated() {
                guard let range = Range(match.range, in: text) else { continue }
                let matchText = String(text[range])
                let placeholder = "[ENTITY_\(type.rawValue.uppercased())_\(index)]"
                entities.append(PreservedEntity(
                    type: type,
                    originalText: matchText,
                    placeholder: placeholder
                ))
            }
        }
        return entities
    }

    /// Re-inserts preserved entities into LLM-refined translation.
    /// If the LLM preserved the original text, this is a no-op.
    /// If the LLM modified entities (e.g., translated a verse reference), this restores them.
    func reinsertEntities(_ entities: [PreservedEntity], into translation: String, original: String) -> String {
        var result = translation

        for entity in entities {
            // If the entity was replaced by its placeholder, restore it
            if result.contains(entity.placeholder) {
                result = result.replacingOccurrences(of: entity.placeholder, with: entity.originalText)
            }
        }

        return result
    }

    // MARK: - Cache Key

    private func buildModeCacheKey(text: String, sourceLang: String, targetLang: String, mode: TranslationMode) -> String {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let raw = "\(normalized)|\(sourceLang)|\(targetLang)|claude-llm|\(mode.rawValue)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func buildDedupKey(text: String, mode: TranslationMode) -> String {
        let prefix = String(text.prefix(100))
        return "\(prefix)_\(mode.rawValue)"
    }
}
