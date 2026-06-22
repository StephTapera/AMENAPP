// BereanTranslationComparisonService.swift
// AMENAPP
// Fetches multi-translation verse comparisons via the compareBibleTranslations callable.

import Foundation
import FirebaseFunctions
import Combine

struct TranslationComparison {
    let reference: String
    let translations: [String: String]
    let commentary: String
}

@MainActor
final class BereanTranslationComparisonService: ObservableObject {
    static let shared = BereanTranslationComparisonService()

    @Published private(set) var latestComparison: TranslationComparison?
    @Published private(set) var isLoading = false

    private let functions = Functions.functions()
    private var cache: [String: TranslationComparison] = [:]

    func compare(
        reference: String,
        // TODO(legal): ESV/NIV/NLT removed — copyrighted without license (AMEN-CONTENT-001).
        translations: [String] = ["KJV", "WEB", "BSB"]
    ) async throws -> TranslationComparison {
        let cacheKey = "\(reference):\(translations.joined())"
        if let cached = cache[cacheKey] { return cached }

        isLoading = true
        defer { isLoading = false }

        let result = try await functions.httpsCallable("compareBibleTranslations").call([
            "reference": reference,
            "translations": translations
        ])
        let data = result.data as? [String: Any] ?? [:]
        let txMap = data["translations"] as? [String: String] ?? [:]
        let commentary = data["commentary"] as? String ?? ""
        let comparison = TranslationComparison(
            reference: reference,
            translations: txMap,
            commentary: commentary
        )
        cache[cacheKey] = comparison
        latestComparison = comparison
        return comparison
    }
}
