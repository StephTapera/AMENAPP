import Foundation
import CoreLocation
import FirebaseFunctions

@MainActor
final class SmartCommunitySearchService {
    static let shared = SmartCommunitySearchService()

    @Published private(set) var lastIntent: SmartCommunitySearchIntent?
    @Published private(set) var lastResults: [SmartCommunityRankedResult] = []
    @Published private(set) var lastRefinements: [String] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?

    private let functions = Functions.functions(region: "us-central1")
    private var activeSearchTask: Task<SmartCommunitySearchResponse, Error>?

    private init() {}

    func search(
        query: String,
        location: SmartSearchLocation?,
        manualLocationText: String? = nil,
        surface: SmartSearchSurface = .findChurch,
        previousSearchId: String? = nil
    ) async throws -> SmartCommunitySearchResponse {
        activeSearchTask?.cancel()

        let payload = makePayload(
            query: query,
            location: location,
            manualLocationText: manualLocationText,
            surface: surface,
            previousSearchId: previousSearchId
        )

        let task = Task<SmartCommunitySearchResponse, Error> {
            let result = try await functions.httpsCallable("smartCommunitySearch").call(payload)
            try Task.checkCancellation()
            let response = try decode(SmartCommunitySearchResponse.self, from: result.data)
            await MainActor.run {
                self.lastIntent = response.interpretedIntent
                self.lastResults = response.results
                self.lastRefinements = response.refinementSuggestions
            }
            return response
        }

        activeSearchTask = task
        isSearching = true
        defer {
            activeSearchTask = nil
            isSearching = false
        }

        do {
            return try await task.value
        } catch {
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    func cancelSearch() {
        activeSearchTask?.cancel()
        activeSearchTask = nil
        isSearching = false
    }

    func logInteraction(event: String, result: SmartCommunityRankedResult?) async {
        do {
            _ = try await functions.httpsCallable("logSmartSearchInteraction").call([
                "event": event,
                "resultId": result?.id as Any,
                "resultType": result?.type.rawValue as Any,
            ])
        } catch {
            // Analytics failures must never crash the app
        }
    }

    private func makePayload(
        query: String,
        location: SmartSearchLocation?,
        manualLocationText: String?,
        surface: SmartSearchSurface,
        previousSearchId: String?
    ) -> [String: Any] {
        var payload: [String: Any] = ["queryText": query]
        if let location {
            var locDict: [String: Any] = ["lat": location.lat, "lng": location.lng]
            if let accuracy = location.accuracyMeters { locDict["accuracyMeters"] = accuracy }
            payload["location"] = locDict
        }
        if location == nil,
           let manualLocationText = manualLocationText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !manualLocationText.isEmpty {
            payload["manualLocationText"] = manualLocationText
        }
        var ctx: [String: Any] = ["surface": surface.rawValue]
        if let prev = previousSearchId { ctx["previousSearchId"] = prev }
        payload["context"] = ctx
        return payload
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
}
