import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - Covenant Search Service
// Abstraction layer over Algolia/Typesense. Never uses raw Firestore full-text search.
// All results respect access permissions — paid/private content is filtered server-side.

@MainActor
final class AmenCovenantSearchService: ObservableObject {
    static let shared = AmenCovenantSearchService()

    @Published var results: [CovenantSearchResult] = []
    @Published var isSearching = false
    @Published var recentQueries: [String] = []

    private let functions = Functions.functions()
    private var currentTask: Task<Void, Never>?

    private init() {
        loadRecentQueries()
    }

    // MARK: - Search

    func search(query: String, scope: CovenantSearchScope, covenantId: String?) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            return
        }

        isSearching = true
        currentTask?.cancel()

        currentTask = Task {
            // Debounce — 300ms after last keystroke
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            do {
                var params: [String: Any] = [
                    "query": query,
                    "scope": scope.rawValue
                ]
                if let cid = covenantId { params["covenantId"] = cid }

                let result = try await functions.httpsCallable("searchCovenantDocuments").call(params)
                guard !Task.isCancelled,
                      let data = result.data as? [String: Any],
                      let hits  = data["hits"] as? [[String: Any]] else { return }

                results = hits.compactMap { decodeSearchResult(from: $0) }
                saveRecentQuery(query)
            } catch {
                results = []
            }
            isSearching = false
        }
    }

    func clearResults() {
        currentTask?.cancel()
        results = []
        isSearching = false
    }

    // MARK: - Recent Queries

    private let recentKey = "covenantSearchRecentQueries"

    private func saveRecentQuery(_ query: String) {
        var recent = recentQueries
        recent.removeAll { $0.lowercased() == query.lowercased() }
        recent.insert(query, at: 0)
        recentQueries = Array(recent.prefix(8))
        UserDefaults.standard.set(recentQueries, forKey: recentKey)
    }

    private func loadRecentQueries() {
        recentQueries = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    func removeRecentQuery(_ query: String) {
        recentQueries.removeAll { $0 == query }
        UserDefaults.standard.set(recentQueries, forKey: recentKey)
    }

    // MARK: - Decode

    private func decodeSearchResult(from dict: [String: Any]) -> CovenantSearchResult? {
        guard let id    = dict["id"] as? String,
              let type  = dict["type"] as? String,
              let title = dict["title"] as? String,
              let scope = CovenantSearchScope(rawValue: type)
        else { return nil }

        return CovenantSearchResult(
            id: id,
            scope: scope,
            title: title,
            subtitle: dict["subtitle"] as? String,
            imageURL: dict["imageURL"] as? String,
            deepLink: nil,
            isLocked: dict["isLocked"] as? Bool ?? false
        )
    }
}
