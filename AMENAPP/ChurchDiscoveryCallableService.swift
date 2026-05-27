import Foundation
import CoreLocation
import FirebaseFunctions

@MainActor
final class ChurchDiscoveryCallableService: ObservableObject {
    static let shared = ChurchDiscoveryCallableService()

    @Published private(set) var lastIntent: ChurchSearchIntent?
    @Published private(set) var lastResults: [ChurchDiscoveryResult] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?

    private let functions = Functions.functions(region: "us-central1")
    private var activeSearchTask: Task<[ChurchDiscoveryResult], Error>?

    private init() {}

    func parseIntent(query: String, location: CLLocationCoordinate2D?) async throws -> ChurchSearchIntent {
        let payload = makePayload(query: query, location: location, filters: nil)
        let result = try await functions.httpsCallable("parseChurchSearchIntent").call(payload)
        let envelope = try decode(ParseIntentEnvelope.self, from: result.data)
        lastIntent = envelope.intent
        return envelope.intent
    }

    func search(query: String, location: CLLocationCoordinate2D?, filters: ChurchDiscoveryFilter? = nil) async throws -> [ChurchDiscoveryResult] {
        activeSearchTask?.cancel()
        let payload = makePayload(query: query, location: location, filters: filters)
        let task = Task<[ChurchDiscoveryResult], Error> {
            let result = try await functions.httpsCallable("searchChurchesAndCommunities").call(payload)
            try Task.checkCancellation()
            let response = try decode(ChurchDiscoveryResponse.self, from: result.data)
            await MainActor.run {
                self.lastIntent = response.intent
                self.lastResults = response.results
            }
            return response.results
        }

        activeSearchTask = task
        isSearching = true
        defer {
            if activeSearchTask === task { activeSearchTask = nil }
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

    func loadDetails(churchId: String) async throws -> [String: Any] {
        let result = try await functions.httpsCallable("getChurchDiscoveryDetails").call(["churchId": churchId])
        return result.data as? [String: Any] ?? [:]
    }

    func saveChurch(result: ChurchDiscoveryResult) async throws {
        _ = try await functions.httpsCallable("saveChurchCandidate").call([
            "churchId": result.churchId as Any,
            "googlePlaceId": result.googlePlaceId as Any,
            "name": result.name,
        ])
    }

    func savePreference(_ preference: ChurchSavedPreference) async throws {
        let data = try JSONEncoder().encode(preference)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        _ = try await functions.httpsCallable("saveChurchDiscoveryPreference").call(["preferences": object])
    }

    func logInteraction(event: String, result: ChurchDiscoveryResult?, metadata: [String: Any] = [:]) async {
        do {
            _ = try await functions.httpsCallable("logChurchDiscoveryInteraction").call([
                "event": event,
                "churchId": result?.churchId as Any,
                "googlePlaceId": result?.googlePlaceId as Any,
                "metadata": metadata,
            ])
        } catch {
            dlog("Church discovery interaction logging failed: \(error.localizedDescription)")
        }
    }

    func result(for church: Church) -> ChurchDiscoveryResult? {
        lastResults.first { result in
            result.churchId == church.canonicalChurchId || result.googlePlaceId == church.canonicalChurchId || result.id == church.canonicalChurchId
        }
    }

    private func makePayload(query: String, location: CLLocationCoordinate2D?, filters: ChurchDiscoveryFilter?) -> [String: Any] {
        var payload: [String: Any] = ["rawQuery": query]
        if let location {
            payload["approximateLocation"] = [
                "latitude": location.latitude,
                "longitude": location.longitude,
            ]
        }
        if let filters,
           let data = try? JSONEncoder().encode(filters),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload["filters"] = object
        }
        return payload
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
}

private struct ParseIntentEnvelope: Decodable {
    let intent: ChurchSearchIntent
}
