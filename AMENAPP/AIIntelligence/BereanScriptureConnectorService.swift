// BereanScriptureConnectorService.swift
// AMENAPP — Berean Spiritual Intelligence Layer (Wave 1)
//
// Connector abstraction over Tier A scripture sources.
// All public methods guard on `bereanTierAConnectorsEnabled`.
// When the flag is OFF, every call returns nil immediately (fail-closed).
//
// Network path is documented via TODO(wave1-deploy) comments — the URLSession
// call body is intentionally deferred until the server proxy is deployed.

import Foundation

@MainActor
final class BereanScriptureConnectorService: ObservableObject {

    static let shared = BereanScriptureConnectorService()

    private let registry = BereanTierARegistry.shared

    // MARK: - Verse Fetch

    /// Fetches a verse for the given reference and translation.
    /// Returns `nil` when `bereanTierAConnectorsEnabled` is OFF (fail-closed).
    /// When the flag is ON, this will call the Free Use Bible API; the HTTP
    /// call body is stubbed pending server-proxy deployment.
    ///
    /// - Parameters:
    ///   - reference: A canonical scripture reference, e.g. "John 3:16".
    ///   - translation: Bible translation code (default: "BSB").
    /// - Returns: The `ScriptureSource` descriptor used, or `nil` if unavailable.
    func fetchVerse(reference: String, translation: String = "BSB") async -> ScriptureSource? {
        guard AMENFeatureFlags.shared.bereanTierAConnectorsEnabled else {
            // Fail-closed: connectors are OFF. No network call is attempted.
            dlog("[BereanScriptureConnectorService] Tier A connectors disabled — fetchVerse returning nil for \(reference)")
            return nil
        }

        guard let source = registry.activeSources.first(where: { $0.availableTranslations.contains(translation) })
                           ?? registry.activeSources.first else {
            dlog("[BereanScriptureConnectorService] No active source available for translation '\(translation)'")
            return nil
        }

        // TODO(wave1-deploy): wire URLSession call to the free-use-bible-api endpoint.
        // Endpoint pattern: https://bible.helloao.org/api/{translation}/{book}/{chapter}.json
        // Parse the `reference` string into (translation, book, chapter, verse) before calling.
        // Use `source.requiresProxiedKey` to route proxied sources through the AMEN server proxy
        // rather than calling the external API directly from the client.
        dlog("[BereanScriptureConnectorService] fetchVerse stub — source: \(source.id), ref: \(reference), translation: \(translation)")
        return source
    }

    // MARK: - Attribution

    /// Returns the correct attribution string for a given source.
    /// Uses `attributionText` when present; falls back to the license name.
    func attribution(for source: ScriptureSource) -> String {
        source.license.attributionText ?? source.license.name
    }
}
