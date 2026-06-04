// BereanSourceExplorerService.swift
// AMENAPP
//
// Fetches and conflict-detects sources attached to Berean AI result IDs.
// Tries Firestore first; falls back to calling the bereanFetchSources CF.
// Caches results for 15 minutes to reduce redundant round-trips.

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class BereanSourceExplorerService: ObservableObject {

    static let shared = BereanSourceExplorerService()

    @Published private(set) var sources: [BereanSourceEntry] = []

    // MARK: - Cache

    private struct CacheEntry {
        let sources: [BereanSourceEntry]
        let fetchedAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 15 * 60  // 15 minutes

    // MARK: - Dependencies

    private let db = Firestore.firestore()
    private lazy var functions = Functions.functions()

    // MARK: - Private init (singleton)

    private init() {}

    // MARK: - Public API

    /// Fetches sources for a given Berean result.
    /// Tries Firestore first; falls back to CF `bereanFetchSources`.
    /// - Parameters:
    ///   - resultId: The Berean context action result ID.
    ///   - projectId: Optional Berean project scope.
    /// - Returns: Array of `BereanSourceEntry` values, or empty if the flag is off.
    func fetchSources(for resultId: String, projectId: String?) async throws -> [BereanSourceEntry] {
        guard AMENFeatureFlags.shared.bereanOSSourceExplorerEnabled else { return [] }

        let cacheKey = "\(resultId)_\(projectId ?? "nil")"

        // Return cached result if still fresh
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            sources = cached.sources
            return cached.sources
        }

        var fetched: [BereanSourceEntry] = []

        // 1. Try Firestore if projectId is known
        if let projectId, let uid = Auth.auth().currentUser?.uid {
            fetched = try await fetchFromFirestore(uid: uid, projectId: projectId, resultId: resultId)
        }

        // 2. Fall back to Cloud Function if Firestore returned nothing
        if fetched.isEmpty {
            fetched = try await fetchFromCF(resultId: resultId, projectId: projectId)
        }

        // Store in cache and publish
        cache[cacheKey] = CacheEntry(sources: fetched, fetchedAt: Date())
        sources = fetched
        return fetched
    }

    /// Returns all (sourceA, sourceB) pairs where either source lists the other in `conflictsWithSourceIds`.
    func detectConflicts(_ sources: [BereanSourceEntry]) -> [(BereanSourceEntry, BereanSourceEntry)] {
        var pairs: [(BereanSourceEntry, BereanSourceEntry)] = []
        let index = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })

        for source in sources where !source.conflictsWithSourceIds.isEmpty {
            for conflictId in source.conflictsWithSourceIds {
                guard let conflictSource = index[conflictId] else { continue }
                // Avoid duplicate reversed pairs
                let alreadyRecorded = pairs.contains { $0.0.id == conflictId && $0.1.id == source.id }
                if !alreadyRecorded {
                    pairs.append((source, conflictSource))
                }
            }
        }
        return pairs
    }

    // MARK: - Private helpers

    private func fetchFromFirestore(uid: String, projectId: String, resultId: String) async throws -> [BereanSourceEntry] {
        let snapshot = try await db
            .collection("users")
            .document(uid)
            .collection("bereanProjects")
            .document(projectId)
            .collection("sources")
            .whereField("resultId", isEqualTo: resultId)
            .limit(to: 20)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> BereanSourceEntry? in
            try? doc.data(as: BereanSourceEntry.self)
        }
    }

    private func fetchFromCF(resultId: String, projectId: String?) async throws -> [BereanSourceEntry] {
        var payload: [String: Any] = ["resultId": resultId]
        if let projectId { payload["projectId"] = projectId }

        let result = try await functions
            .httpsCallable("bereanFetchSources")
            .call(payload)

        guard let data = result.data as? [String: Any],
              let rawSources = data["sources"] as? [[String: Any]] else {
            return []
        }

        let jsonData = try JSONSerialization.data(withJSONObject: rawSources)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([BereanSourceEntry].self, from: jsonData)) ?? []
    }
}
