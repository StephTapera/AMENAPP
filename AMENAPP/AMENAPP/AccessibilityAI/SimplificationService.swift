// SimplificationService.swift
// AMENAPP
//
// A8 — Content readability transformation via `a11ySimplifyProxy` Cloud Function.
// Results are cached in memory by `contentId_mode_language`.

import Foundation
import FirebaseFunctions

@MainActor
final class SimplificationService {

    static let shared = SimplificationService()

    private var cache: [String: ReadabilityTransform] = [:]

    private init() {}

    func transform(
        contentId: String,
        text: String,
        mode: ReadabilityMode,
        language: String = "en"
    ) async -> ReadabilityTransform? {
        guard AMENFeatureFlags.shared.readabilityLayerEnabled else {
            dlog("[SimplificationService] feature flag off — skipping transform for \(contentId)")
            return nil
        }

        let cacheKey = "\(contentId)_\(mode.rawValue)_\(language)"

        if let cached = cache[cacheKey] {
            dlog("[SimplificationService] cache hit for \(cacheKey)")
            return cached
        }

        let payload: [String: Any] = [
            "text": text,
            "mode": mode.rawValue,
            "language": language
        ]

        do {
            let callable = Functions.functions().httpsCallable("a11ySimplifyProxy")
            callable.timeoutInterval = 20
            let result = try await callable.safeCall(payload)

            guard let data = result.data as? [String: Any] else {
                dlog("[SimplificationService] unexpected response shape for \(cacheKey)")
                return nil
            }

            let transformedText = (data["result"] as? String) ?? ""

            var keyTerms: [KeyTermDefinition]?
            if mode == .keyTerms, let rawTerms = data["keyTerms"] as? [[String: Any]] {
                keyTerms = rawTerms.compactMap { dict in
                    guard
                        let term = dict["term"] as? String,
                        let definition = dict["definition"] as? String
                    else { return nil }
                    let relatedVerse = dict["relatedVerse"] as? String
                    return KeyTermDefinition(term: term, definition: definition, relatedVerse: relatedVerse)
                }
            }

            var transform_ = ReadabilityTransform(
                id: cacheKey,
                mode: mode,
                originalContentId: contentId,
                transformedText: transformedText,
                language: language,
                createdAt: Date()
            )
            transform_.keyTerms = keyTerms

            cache[cacheKey] = transform_
            dlog("[SimplificationService] transformed \(cacheKey) — keyTerms: \(keyTerms?.count ?? 0)")
            return transform_

        } catch {
            dlog("[SimplificationService] error transforming \(cacheKey): \(error.localizedDescription)")
            return nil
        }
    }
}
