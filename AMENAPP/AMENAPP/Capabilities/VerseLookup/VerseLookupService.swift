// VerseLookupService.swift
// AMEN Capabilities v1 — Thin async service for verse lookup callables (Wave 1: Lane E)
//
// Wraps `scripture_searchVerses` and `scripture_getVerses` callables.
// Uses the same JSONSerialization → JSONDecoder pipeline as CapabilityRegistryStore.
//
// All calls pass through without extra flag checks; callers are responsible for
// checking `AMENFeatureFlags.shared.verseLookupInlineEnabled` before presenting the UI.

import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - VerseLookupService

final class VerseLookupService {

    // MARK: Singleton

    static let shared = VerseLookupService()

    // MARK: Private

    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    // MARK: - Public API

    /// Full-text or reference search over the scripture corpus.
    /// - Parameters:
    ///   - query: A reference string (e.g. "John 3:16") or keyword phrase (e.g. "God is love").
    ///   - limit: Maximum results to return. Default 5, backend caps at 10.
    /// - Returns: Ordered list of `ScriptureSearchResult` values.
    func search(query: String, limit: Int = 5) async throws -> [ScriptureSearchResult] {
        let clampedLimit = min(max(limit, 1), 10)
        let params: [String: Any] = [
            "query": query,
            "limit": clampedLimit
        ]

        let result = try await functions
            .httpsCallable("scripture_searchVerses")
            .call(params)

        guard
            let data = result.data as? [String: Any],
            let resultsRaw = data["results"] as? [[String: Any]]
        else {
            throw VerseLookupError.unexpectedResponse
        }

        return resultsRaw.compactMap { dict in
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else {
                return nil
            }
            return try? JSONDecoder().decode(ScriptureSearchResult.self, from: jsonData)
        }
    }

    /// Fetches the full verse text for a given OSIS reference and translation.
    /// - Parameters:
    ///   - osisRef: OSIS reference string, e.g. `"John.3.16"`.
    ///   - translation: Which translation to fetch. Defaults to `.BSB`.
    /// - Returns: A `VerseCard` with the verse text, display label, and translation.
    func getVerse(osisRef: String, translation: BibleTranslation = .BSB) async throws -> VerseCard {
        let params: [String: Any] = [
            "osisRefs": [osisRef],
            "translation": translation.rawValue
        ]

        let result = try await functions
            .httpsCallable("scripture_getVerses")
            .call(params)

        guard
            let data = result.data as? [String: Any],
            let versesRaw = data["verses"] as? [[String: Any]],
            let firstRaw = versesRaw.first,
            let jsonData = try? JSONSerialization.data(withJSONObject: firstRaw)
        else {
            throw VerseLookupError.unexpectedResponse
        }

        return try JSONDecoder().decode(VerseCard.self, from: jsonData)
    }
}

// MARK: - VerseLookupError

enum VerseLookupError: LocalizedError {
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            return "Verse Lookup returned an unexpected response."
        }
    }
}
