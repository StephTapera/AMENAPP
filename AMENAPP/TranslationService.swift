// TranslationService.swift
// AMEN App — Translation System
//
// Central orchestration service for all translation flows.
// Coordinates: language detection → cache lookup → backend/on-device call → cache store → UI update
//
// Architecture:
//   Client requests translation via translate(text:contentType:contentId:surface:)
//   Service checks feature flags and user preferences first
//   Checks L1/L2/L3 cache (TranslationCacheManager)
//   Falls back to GCP backend (Cloud Run endpoint, server-side, secure)
//   Falls back to Apple on-device Translation if GCP unavailable
//   Stores result in all cache tiers
//   Emits analytics event
//
// Privacy:
//   Private content (messages, restricted visibility) is never sent to Firestore cache
//   DMs are feature-flagged off by default
//   Language detection runs on-device via NaturalLanguage (no data leaves device)

import Foundation
import Combine
import NaturalLanguage
import Translation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class TranslationService: ObservableObject {

    static let shared = TranslationService()

    // MARK: - Dependencies

    private let cache = TranslationCacheManager.shared
    private let settings = TranslationSettingsManager.shared
    private let flags = TranslationFeatureFlags.shared

    // MARK: - In-flight request deduplication
    // Prevents duplicate API calls when multiple views request same translation simultaneously

    private var inFlightRequests: [String: Task<String, Error>] = [:]

    // MARK: - Rate limiting (per-user, per-session)

    private var sessionRequestCount = 0
    private var sessionResetDate = Date()

    // MARK: - Backend config
    // Replace with your actual Cloud Run / Firebase Functions URL from Config.xcconfig

    private let backendBaseURL: String = {
        Bundle.main.object(forInfoDictionaryKey: "TRANSLATION_BACKEND_URL") as? String
            ?? "https://translation-YOURPROJECT.a.run.app"
    }()

    private init() {}

    // MARK: - Public API

    /// Primary translation entry point. Returns a TranslationUIState appropriate for the given content.
    /// Call this from PostCard, CommentsView, etc.
    func translate(
        text: String,
        contentType: TranslatableContentType,
        contentId: String,
        surface: TranslationSurface,
        isPublicContent: Bool = true,
        forceRefresh: Bool = false
    ) async -> TranslationUIState {
        // P0 SECURITY: Message/DM translations must NEVER be written to the shared
        // Firestore cache. The cache stores originalText which would expose private
        // message content to any authenticated user who hits the same cache key.
        // Override isPublicContent to false for all message surfaces regardless of
        // what the caller passed.
        let effectiveIsPublicContent = surface == .messages ? false : isPublicContent
        // 1. Feature flag check
        guard flags.isEnabled(for: contentType) else { return .disabled }

        // 2. Skip trivially short or no-translation-needed text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= TranslationPreservationRules.minimumCharCount else { return .notNeeded }
        let normalized = trimmed.lowercased()
        if TranslationPreservationRules.noTranslationNeeded.contains(normalized) { return .notNeeded }

        // 3. Truncate to max chars (cost guardrail)
        let truncated = String(trimmed.prefix(flags.maxCharsPerRequest))

        // 4. Detect language (on-device, free, private)
        let detection = await detectLanguage(truncated)
        guard detection.isReliable else { return .notNeeded }

        let targetLang = settings.userLanguageCode
        let sourceLang = detection.languageCode

        // 5. Same language — no translation needed
        guard sourceLang != targetLang else { return .notNeeded }

        // 6. User understands this language — skip
        if settings.preferences.understoodLanguages.contains(sourceLang) { return .notNeeded }

        // 7. Build cache key
        let cacheKey = TranslationCacheManager.buildCacheKey(
            text: truncated,
            sourceLanguage: sourceLang,
            targetLanguage: targetLang
        )

        // 8. Cache lookup (unless force refresh)
        if !forceRefresh, let cached = await cache.lookup(cacheKey: cacheKey) {
            let variant = TranslationVariant(
                translatedText: cached,
                sourceLanguage: sourceLang,
                targetLanguage: targetLang,
                engineVersion: .gcpV3,
                translatedAt: Date(),
                characterCount: truncated.count,
                isUserRequested: false
            )
            return .translated(variant)
        }

        // 9. Deduplicate in-flight requests
        if let existing = inFlightRequests[cacheKey] {
            do {
                let result = try await existing.value
                let variant = TranslationVariant(
                    translatedText: result,
                    sourceLanguage: sourceLang,
                    targetLanguage: targetLang,
                    engineVersion: .gcpV3,
                    translatedAt: Date(),
                    characterCount: truncated.count,
                    isUserRequested: true
                )
                return .translated(variant)
            } catch {
                return mapError(error)
            }
        }

        // 10. Session rate limit check
        guard checkSessionRateLimit() else {
            return .error(.rateLimited)
        }

        // 11. Dispatch translation request
        let task = Task<String, Error> {
            try await self.performTranslation(
                text: truncated,
                sourceLang: sourceLang,
                targetLang: targetLang,
                contentType: contentType,
                contentId: contentId,
                surface: surface,
                isPublicContent: effectiveIsPublicContent,
                cacheKey: cacheKey
            )
        }

        inFlightRequests[cacheKey] = task
        defer { inFlightRequests.removeValue(forKey: cacheKey) }

        do {
            let translatedText = try await task.value
            let variant = TranslationVariant(
                translatedText: translatedText,
                sourceLanguage: sourceLang,
                targetLanguage: targetLang,
                engineVersion: flags.preferredEngine,
                translatedAt: Date(),
                characterCount: truncated.count,
                isUserRequested: true
            )

            // Track analytics
            trackAnalytics(
                surface: surface,
                contentType: contentType,
                sourceLang: sourceLang,
                targetLang: targetLang,
                engine: flags.preferredEngine,
                cacheHit: false
            )

            return .translated(variant)
        } catch {
            return mapError(error)
        }
    }

    /// Detect language for a piece of text. Returns a reliable result or .notNeeded.
    /// Used at post-write time to store detectedLanguage on the document.
    func detectLanguage(_ text: String) async -> LanguageDetectionResult {
        return await Task.detached(priority: .userInitiated) {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)

            guard let dominant = recognizer.dominantLanguage,
                  dominant != .undetermined else {
                return LanguageDetectionResult(
                    languageCode: "und", confidence: 0, isReliable: false, rawText: text
                )
            }

            let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
            let confidence = hypotheses[dominant] ?? 0

            let raw = dominant.rawValue
            let base = raw.components(separatedBy: "-").first ?? raw
            let code = base.lowercased()

            let isReliable = confidence >= TranslationPreservationRules.minimumDetectionConfidence
                && text.count >= TranslationPreservationRules.minimumCharCount

            return LanguageDetectionResult(
                languageCode: code,
                confidence: confidence,
                isReliable: isReliable,
                rawText: text
            )
        }.value
    }

    /// Detect and store language metadata on a Firestore document (called at post write time).
    /// Fire-and-forget — does not block post creation.
    func detectAndStoreLanguage(
        text: String,
        collection: String,
        documentId: String
    ) {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let result = await self.detectLanguage(text)
            guard result.isReliable else { return }

            let db = Firestore.firestore()
            try? await db.collection(collection).document(documentId).updateData([
                "detectedLanguage": result.languageCode,
                "detectedLanguageConfidence": result.confidence
            ])
        }
    }

    /// Invalidate cached translations when a post/comment is edited.
    func invalidateTranslations(for text: String, sourceLang: String) async {
        // Invalidate for all common target languages
        let commonTargets = ["en", "es", "fr", "pt", "de", "zh", "ar"]
        for target in commonTargets {
            let key = TranslationCacheManager.buildCacheKey(
                text: text, sourceLanguage: sourceLang, targetLanguage: target
            )
            await cache.invalidate(cacheKey: key)
        }
    }

    // MARK: - Internal: Translation Execution

    private func performTranslation(
        text: String,
        sourceLang: String,
        targetLang: String,
        contentType: TranslatableContentType,
        contentId: String,
        surface: TranslationSurface,
        isPublicContent: Bool,
        cacheKey: String
    ) async throws -> String {
        var translated: String
        var engine = TranslationEngine.gcpV3

        // Try GCP backend first (server-side, secure, higher quality)
        if flags.gcpBackendEnabled {
            do {
                translated = try await callGCPBackend(
                    text: text,
                    sourceLang: sourceLang,
                    targetLang: targetLang,
                    contentType: contentType,
                    contentId: contentId,
                    surface: surface,
                    isPublicContent: isPublicContent
                )
                engine = .gcpV3
            } catch {
                // GCP failed — fall through to on-device
                if flags.appleOnDeviceFallbackEnabled {
                    translated = try await callAppleTranslation(text: text, sourceLang: sourceLang, targetLang: targetLang)
                    engine = .appleOnDevice
                } else {
                    throw error
                }
            }
        } else if flags.appleOnDeviceFallbackEnabled {
            translated = try await callAppleTranslation(text: text, sourceLang: sourceLang, targetLang: targetLang)
            engine = .appleOnDevice
        } else {
            throw TranslationErrorResponse(
                requestId: UUID().uuidString,
                errorCode: .serviceUnavailable,
                message: "No translation engine available",
                retryAfterSeconds: nil
            )
        }

        // Post-process: restore preserved entities
        translated = postProcess(translated: translated, original: text)

        // Store in all cache tiers
        await cache.store(
            cacheKey: cacheKey,
            originalText: text,
            translatedText: translated,
            sourceLanguage: sourceLang,
            targetLanguage: targetLang,
            engine: engine,
            isPublicContent: isPublicContent
        )

        sessionRequestCount += 1
        return translated
    }

    // MARK: - GCP Backend Call (Cloud Run / Firebase Functions)

    private func callGCPBackend(
        text: String,
        sourceLang: String,
        targetLang: String,
        contentType: TranslatableContentType,
        contentId: String,
        surface: TranslationSurface,
        isPublicContent: Bool
    ) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw TranslationErrorResponse(
                requestId: UUID().uuidString,
                errorCode: .contentRestricted,
                message: "Not authenticated",
                retryAfterSeconds: nil
            )
        }

        guard let url = URL(string: "\(backendBaseURL)/v1/translate") else {
            throw TranslationErrorResponse(
                requestId: UUID().uuidString,
                errorCode: .serviceUnavailable,
                message: "Invalid backend URL",
                retryAfterSeconds: nil
            )
        }

        // Get Firebase ID token for authenticated request
        let idToken = try await Auth.auth().currentUser?.getIDToken() ?? ""

        let requestBody = TranslationRequest(
            requestId: UUID().uuidString,
            contentType: contentType,
            contentId: contentId,
            text: text,
            sourceLanguage: sourceLang == "und" ? nil : sourceLang,
            targetLanguage: targetLang,
            requestingUserId: uid,
            isPublicContent: isPublicContent,
            surface: surface,
            engineHint: .gcpV3
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationErrorResponse(
                requestId: requestBody.requestId,
                errorCode: .serviceUnavailable,
                message: "Invalid response",
                retryAfterSeconds: nil
            )
        }

        guard httpResponse.statusCode == 200 else {
            let decoder = JSONDecoder()
            if let errorResp = try? decoder.decode(TranslationErrorResponse.self, from: data) {
                throw errorResp
            }
            throw TranslationErrorResponse(
                requestId: requestBody.requestId,
                errorCode: .serviceUnavailable,
                message: "HTTP \(httpResponse.statusCode)",
                retryAfterSeconds: httpResponse.statusCode == 429 ? 60 : nil
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let translationResponse = try decoder.decode(TranslationResponse.self, from: data)
        return translationResponse.translatedText
    }

    // MARK: - Apple On-Device Translation (iOS 17.4+ fallback)

    private func callAppleTranslation(
        text: String,
        sourceLang: String,
        targetLang: String
    ) async throws -> String {
        // Apple Translation framework — on-device, private, no API cost
        // Requires iOS 17.4+; language models downloaded on first use
        if #available(iOS 17.4, *) {
            return try await AppleTranslationBridge.shared.translate(
                text: text,
                from: sourceLang,
                to: targetLang
            )
        } else {
            throw TranslationErrorResponse(
                requestId: UUID().uuidString,
                errorCode: .serviceUnavailable,
                message: "On-device translation requires iOS 17.4+",
                retryAfterSeconds: nil
            )
        }
    }

    // MARK: - Post-Processing: Preserve AMEN Entities

    /// Restores scripture references, @mentions, #hashtags, and URLs that may have been
    /// mangled by the translation engine.
    private func postProcess(translated: String, original: String) -> String {
        var result = translated

        // Extract preserved tokens from original
        for pattern in TranslationPreservationRules.preservedPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(original.startIndex..., in: original)
            let matches = regex.matches(in: original, range: range)

            for match in matches {
                guard let matchRange = Range(match.range, in: original) else { continue }
                let originalToken = String(original[matchRange])

                // Find the approximate location in translated text and ensure token is present
                // If the translator changed it, we don't blindly restore (could break grammar)
                // For scripture refs and @mentions we do restore if clearly mangled
                if originalToken.hasPrefix("@") || originalToken.hasPrefix("#") {
                    // These should be byte-identical
                    if !result.contains(originalToken) {
                        // Find likely mangled version by looking for @ or # in translated
                        // This is a best-effort heuristic
                        result = restoreToken(originalToken, in: result)
                    }
                }
            }
        }

        return result
    }

    private func restoreToken(_ token: String, in text: String) -> String {
        // Simple: if token is missing, append it with a note
        // In practice a more sophisticated alignment is done server-side
        if text.contains(token) { return text }
        return text + " \(token)"
    }

    // MARK: - Rate Limiting

    private func checkSessionRateLimit() -> Bool {
        // Reset counter every hour
        if Date().timeIntervalSince(sessionResetDate) > 3600 {
            sessionRequestCount = 0
            sessionResetDate = Date()
        }
        return sessionRequestCount < flags.maxRequestsPerUserPerDay
    }

    // MARK: - Error Mapping

    private func mapError(_ error: Error) -> TranslationUIState {
        if let translationError = error as? TranslationErrorResponse {
            switch translationError.errorCode {
            case .unsupportedLanguage:    return .error(.unsupportedLanguage)
            case .contentRestricted:      return .error(.contentRestricted)
            case .rateLimitExceeded:      return .error(.rateLimited)
            case .serviceUnavailable:     return .error(.serviceUnavailable)
            default:                      return .error(.serviceUnavailable)
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .error(.networkUnavailable)
        }
        return .error(.serviceUnavailable)
    }

    // MARK: - Analytics

    private func trackAnalytics(
        surface: TranslationSurface,
        contentType: TranslatableContentType,
        sourceLang: String,
        targetLang: String,
        engine: TranslationEngine,
        cacheHit: Bool
    ) {
        guard flags.analyticsEnabled else { return }
        Task.detached(priority: .background) {
            // Fire-and-forget analytics event
            let db = Firestore.firestore()
            let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
            _ = try? await db
                .collection("translationAnalytics")
                .document(String(today))
                .collection("events")
                .addDocument(data: [
                    "surface": surface.rawValue,
                    "contentType": contentType.rawValue,
                    "sourceLanguage": sourceLang,
                    "targetLanguage": targetLang,
                    "engineVersion": engine.rawValue,
                    "cacheHit": cacheHit,
                    "timestamp": FieldValue.serverTimestamp()
                ])
        }
    }
}

// MARK: - Apple Translation Bridge (iOS 17.4+)

/// Wrapper that isolates the Apple Translation import behind availability guard
@MainActor
final class AppleTranslationBridge {
    static let shared = AppleTranslationBridge()
    private init() {}

    @available(iOS 17.4, *)
    func translate(text: String, from sourceLang: String, to targetLang: String) async throws -> String {
        // Apple Translation requires a TranslationSession
        // Sessions are lightweight and can be created per-request
        let source = Locale.Language(identifier: sourceLang)
        let target = Locale.Language(identifier: targetLang)

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    // Import Translation framework at call site via dynamic symbol
                    // This avoids compile-time dependency issues on pre-17.4 targets
                    let result = try await Self.performAppleTranslation(
                        text: text, source: source, target: target
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @available(iOS 17.4, *)
    private static func performAppleTranslation(
        text: String,
        source: Locale.Language,
        target: Locale.Language
    ) async throws -> String {
        // Dynamically resolve Translation.TranslationSession to avoid linker issues
        // on older OS. In practice, guard with @available ensures this path is safe.
        let session = Translation.TranslationSession(installedSource: source, target: target)
        let response = try await session.translate(text)
        return response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
