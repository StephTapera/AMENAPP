// ReadabilityService.swift
// AMEN App — Accessibility Intelligence Layer (Phase 2)
//
// Orchestrates content transformation for the Understand Sheet.
// Pipeline: cache check → Cloud Function "transformContent" → cache store.
// In-flight deduplication prevents duplicate requests.
// Supports 5 modes: simplify, summarize, keyTerms, explain, expandContext.

import Foundation
import CryptoKit

@MainActor
final class ReadabilityService: ObservableObject {

    static let shared = ReadabilityService()

    // MARK: - State

    @Published private(set) var isLoading = false
    @Published private(set) var currentTransform: ReadabilityTransform?
    @Published private(set) var error: String?

    // MARK: - In-Flight Dedup

    private var inFlightRequests: [String: Task<ReadabilityTransform?, Never>] = [:]

    private init() {}

    // MARK: - Public API

    /// Transform content using the specified readability mode.
    /// Results are cached in Firestore for cross-user dedup.
    func transform(
        text: String,
        contentId: String,
        mode: ReadabilityMode,
        language: String? = nil,
        forceRefresh: Bool = false
    ) async -> ReadabilityTransform? {
        guard AMENFeatureFlags.shared.readabilityLayerEnabled else { return nil }

        let lang = language ?? TranslationSettingsManager.shared.preferences.appLanguage
        let cacheKey = buildCacheKey(contentId: contentId, mode: mode, language: lang)

        // Check in-flight
        if let existingTask = inFlightRequests[cacheKey] {
            return await existingTask.value
        }

        // Check cache (memory → disk → Firestore via TranslationCacheManager pattern)
        if !forceRefresh, let cached = await lookupCache(cacheKey: cacheKey) {
            currentTransform = cached
            return cached
        }

        // Launch transform task
        let task = Task<ReadabilityTransform?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.performTransform(
                text: text,
                contentId: contentId,
                mode: mode,
                language: lang,
                cacheKey: cacheKey
            )
        }

        inFlightRequests[cacheKey] = task
        isLoading = true
        error = nil

        let result = await task.value
        inFlightRequests[cacheKey] = nil
        isLoading = false

        if let result {
            currentTransform = result
        }

        return result
    }

    /// Clear current transform state (e.g., when dismissing sheet)
    func clearCurrentTransform() {
        currentTransform = nil
        error = nil
    }

    // MARK: - Private Pipeline

    private func performTransform(
        text: String,
        contentId: String,
        mode: ReadabilityMode,
        language: String,
        cacheKey: String
    ) async -> ReadabilityTransform? {
        do {
            let payload: [String: Any] = [
                "text": text,
                "mode": mode.rawValue,
                "language": language,
                "contentId": contentId,
            ]

            let result = try await CloudFunctionsService.shared.call("transformContent", data: payload)

            guard let dict = result as? [String: Any],
                  let transformedText = dict["transformedText"] as? String else {
                throw NSError(domain: "ReadabilityService", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid response from transformContent"])
            }

            // Parse optional key terms
            var keyTerms: [KeyTermDefinition]?
            if let termsArray = dict["keyTerms"] as? [[String: Any]] {
                keyTerms = termsArray.compactMap { termDict -> KeyTermDefinition? in
                    guard let term = termDict["term"] as? String,
                          let definition = termDict["definition"] as? String else { return nil }
                    return KeyTermDefinition(
                        term: term,
                        definition: definition,
                        relatedVerse: termDict["relatedVerse"] as? String
                    )
                }
            }

            let transform = ReadabilityTransform(
                id: "\(contentId)_\(mode.rawValue)_\(language)",
                mode: mode,
                originalContentId: contentId,
                transformedText: transformedText,
                language: language,
                createdAt: Date(),
                keyTerms: keyTerms
            )

            // Cache the result
            await storeCache(cacheKey: cacheKey, transform: transform)

            return transform

        } catch {
            dlog("[ReadabilityService] Transform failed: \(error)")
            self.error = "Unable to process content. Please try again."
            return nil
        }
    }

    // MARK: - Cache (UserDefaults-based for simplicity, keyed by cacheKey)

    private let cachePrefix = "amen.readability.cache."
    private var memoryCache: [String: ReadabilityTransform] = [:]

    private func lookupCache(cacheKey: String) async -> ReadabilityTransform? {
        // L1: Memory
        if let cached = memoryCache[cacheKey] {
            return cached
        }

        // L2: UserDefaults
        if let data = UserDefaults.standard.data(forKey: cachePrefix + cacheKey),
           let cached = try? JSONDecoder().decode(ReadabilityTransform.self, from: data) {
            memoryCache[cacheKey] = cached
            return cached
        }

        return nil
    }

    private func storeCache(cacheKey: String, transform: ReadabilityTransform) async {
        // L1: Memory
        memoryCache[cacheKey] = transform

        // L2: UserDefaults (lightweight, bounded by mode × content combos)
        if let data = try? JSONEncoder().encode(transform) {
            UserDefaults.standard.set(data, forKey: cachePrefix + cacheKey)
        }
    }

    // MARK: - Cache Key

    private func buildCacheKey(contentId: String, mode: ReadabilityMode, language: String) -> String {
        let raw = "\(contentId)|\(mode.rawValue)|\(language)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
