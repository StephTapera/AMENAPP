// BereanContextResultExtension.swift
// AMENAPP
//
// Additive bridge: attaches Source Explorer data to a Berean context result
// without modifying BereanContextPayload.swift or BereanContextActionResult.
//
// IMPORTANT: This file must not import or modify BereanContextPayload.swift.
// It is purely additive.

import Foundation

/// Carries the source-explorer state associated with one `BereanContextActionResult`.
/// Keyed by `BereanContextActionResult.id`.
struct BereanContextResultSources {
    let resultId: String
    var sources: [BereanSourceEntry]
    var conflictingViews: [String]
}

// MARK: - In-memory registry

/// Lightweight in-process store that maps result IDs to their source payloads.
/// Uses `BereanSourceExplorerService` for actual Firestore / CF fetching.
@MainActor
final class BereanContextResultSourcesRegistry {

    static let shared = BereanContextResultSourcesRegistry()

    private var registry: [String: BereanContextResultSources] = [:]

    private init() {}

    // MARK: - Access

    func sources(for resultId: String) -> BereanContextResultSources? {
        registry[resultId]
    }

    func allEntries() -> [BereanContextResultSources] {
        Array(registry.values)
    }

    // MARK: - Mutation

    func register(resultId: String, sources: [BereanSourceEntry]) {
        let conflictPairs = BereanSourceExplorerService.shared.detectConflicts(sources)
        let conflictingIds = conflictPairs.flatMap { [$0.0.id, $0.1.id] }
        let entry = BereanContextResultSources(
            resultId: resultId,
            sources: sources,
            conflictingViews: conflictingIds
        )
        registry[resultId] = entry
    }

    func removeEntry(for resultId: String) {
        registry.removeValue(forKey: resultId)
    }

    func clear() {
        registry.removeAll()
    }
}
