import Foundation
import CoreLocation
import FirebaseFunctions

struct SmartChurchSummary: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var address: String
    var city: String
    var state: String
    var zip: String
    var latitude: Double
    var longitude: Double
    var denomination: String
    var denominationFamily: String
    var worshipStyles: [String]
    var ministries: [String]
    var size: String
    var serviceTimes: [SmartChurchServiceTime]
    var languages: [String]
    var statementOfFaith: String
    var doctrinalTags: [String]
    var description: String
    var website: String?
    var phone: String?
    var email: String?
    var photos: [String]
    var claimed: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var shortLocation: String {
        [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var legacyChurch: Church {
        Church(
            name: name,
            denomination: denomination.isEmpty ? "Christian Church" : denomination,
            address: address,
            distance: "",
            serviceTime: serviceTimes.first?.displayText ?? "Service times not verified yet",
            phone: phone ?? "No phone available",
            coordinate: coordinate,
            website: website
        )
    }
}

struct SmartChurchSearchItem: Identifiable, Hashable {
    let church: SmartChurchSummary
    let distanceMiles: Double
    let matchReason: String
    let score: Double

    var id: String { church.id }
}

struct BereanChurchChatEvent {
    let kind: String          // "status" | "results" | "message" | "error"
    let message: String?
    let results: [SmartChurchSearchItem]
}

final class SmartChurchSearchService {
    static let shared = SmartChurchSearchService()

    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    func search(query: String, userLocation: CLLocationCoordinate2D, radiusMiles: Double?) async throws -> [SmartChurchSearchItem] {
        var payload: [String: Any] = [
            "query": query,
            "userLat": userLocation.latitude,
            "userLng": userLocation.longitude,
        ]
        if let radiusMiles {
            payload["radiusMiles"] = radiusMiles
        }
        let result = try await functions.callWithTimeout("smartChurchSearch", data: payload, timeout: 15)
        return try decodeSearchItems(from: result.data)
    }

    func keywordSearch(query: String) async throws -> [SmartChurchSearchItem] {
        let result = try await functions.callWithTimeout("searchChurchesByKeyword", data: ["query": query], timeout: 15)
        return try decodeSearchItems(from: result.data)
    }

    func visitReadiness(churchId: String) async throws -> SmartChurchVisitReadiness {
        let result = try await functions.httpsCallable("getChurchVisitReadiness").call(["churchId": churchId])
        guard let data = result.data as? [String: Any] else { return .fallback }
        return SmartChurchVisitReadiness(
            dress: data["dress"] as? String ?? "Come as you are.",
            serviceLength: data["serviceLength"] as? String ?? "Confirm service length with the church.",
            parking: data["parking"] as? String ?? "Check the address before leaving.",
            kidsCheckIn: data["kidsCheckIn"] as? String ?? "Kids check-in details are not verified yet.",
            whatToBring: data["whatToBring"] as? String ?? "Bring anything you normally need for church."
        )
    }

    /// Streaming Berean church chat: calls the `bereanChurchChat` Cloud Function and
    /// yields typed events so callers can display status, results, and messages progressively.
    func bereanChurchChat(
        query: String,
        userLocation: CLLocationCoordinate2D,
        radiusMiles: Double
    ) -> AsyncThrowingStream<BereanChurchChatEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let payload: [String: Any] = [
                        "query": query,
                        "userLat": userLocation.latitude,
                        "userLng": userLocation.longitude,
                        "radiusMiles": radiusMiles
                    ]
                    let result = try await functions.httpsCallable("bereanChurchChat").call(payload)
                    guard let envelope = result.data as? [String: Any] else {
                        continuation.yield(BereanChurchChatEvent(kind: "error", message: "Unexpected response format.", results: []))
                        continuation.finish()
                        return
                    }
                    // Emit a status event if provided
                    if let status = envelope["status"] as? String {
                        continuation.yield(BereanChurchChatEvent(kind: "status", message: status, results: []))
                    }
                    // Emit results if provided
                    if let rows = envelope["results"] as? [[String: Any]] {
                        let items = rows.compactMap { row -> SmartChurchSearchItem? in
                            guard let churchData = row["church"] as? [String: Any],
                                  let church = SmartChurchSummary(data: churchData) else { return nil }
                            return SmartChurchSearchItem(
                                church: church,
                                distanceMiles: Self.double(row["distanceMiles"]) ?? 0,
                                matchReason: row["matchReason"] as? String ?? "Matches stored church profile signals.",
                                score: Self.double(row["score"]) ?? 0
                            )
                        }
                        continuation.yield(BereanChurchChatEvent(kind: "results", message: nil, results: items))
                    }
                    // Emit a narrative message if provided
                    if let message = envelope["message"] as? String, !message.isEmpty {
                        continuation.yield(BereanChurchChatEvent(kind: "message", message: message, results: []))
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(BereanChurchChatEvent(kind: "error", message: error.localizedDescription, results: []))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func decodeSearchItems(from value: Any) throws -> [SmartChurchSearchItem] {
        guard let envelope = value as? [String: Any], let rows = envelope["results"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let churchData = row["church"] as? [String: Any], let church = SmartChurchSummary(data: churchData) else { return nil }
            return SmartChurchSearchItem(
                church: church,
                distanceMiles: Self.double(row["distanceMiles"]) ?? 0,
                matchReason: row["matchReason"] as? String ?? "Matches stored church profile signals.",
                score: Self.double(row["score"]) ?? 0
            )
        }
    }

    static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

struct SmartChurchVisitReadiness: Hashable {
    var dress: String
    var serviceLength: String
    var parking: String
    var kidsCheckIn: String
    var whatToBring: String

    static let fallback = SmartChurchVisitReadiness(
        dress: "Come as you are.",
        serviceLength: "Confirm service length with the church.",
        parking: "Check the address before leaving.",
        kidsCheckIn: "Kids check-in details are not verified yet.",
        whatToBring: "Bring anything you normally need for church."
    )
}

private extension SmartChurchSummary {
    init?(data: [String: Any]) {
        let id = data["id"] as? String ?? data["objectID"] as? String ?? ""
        let location = data["location"] as? [String: Any]
        let lat = SmartChurchSearchService.double(location?["lat"] ?? location?["latitude"] ?? data["lat"] ?? data["latitude"]) ?? 0
        let lng = SmartChurchSearchService.double(location?["lng"] ?? location?["longitude"] ?? data["lng"] ?? data["longitude"]) ?? 0
        guard !id.isEmpty, lat != 0 || lng != 0 else { return nil }
        self.id = id
        self.name = data["name"] as? String ?? "Church"
        self.address = data["address"] as? String ?? ""
        self.city = data["city"] as? String ?? ""
        self.state = data["state"] as? String ?? ""
        self.zip = data["zip"] as? String ?? ""
        self.latitude = lat
        self.longitude = lng
        self.denomination = data["denomination"] as? String ?? ""
        self.denominationFamily = data["denominationFamily"] as? String ?? ""
        self.worshipStyles = Self.stringArray(data["worshipStyles"])
        self.ministries = Self.stringArray(data["ministries"])
        self.size = data["size"] as? String ?? ""
        self.serviceTimes = Self.serviceTimes(data["serviceTimes"])
        self.languages = Self.stringArray(data["languages"])
        self.statementOfFaith = data["statementOfFaith"] as? String ?? ""
        self.doctrinalTags = Self.stringArray(data["doctrinalTags"])
        self.description = data["description"] as? String ?? ""
        self.website = data["website"] as? String
        self.phone = data["phone"] as? String
        self.email = data["email"] as? String
        self.photos = Self.stringArray(data["photos"])
        self.claimed = data["claimed"] as? Bool ?? false
    }

    static func stringArray(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { element in
            let text = String(describing: element).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } ?? []
    }

    static func serviceTimes(_ value: Any?) -> [SmartChurchServiceTime] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.map { row in
            SmartChurchServiceTime(
                day: row["day"] as? String ?? "Sunday",
                time: row["time"] as? String ?? "",
                language: row["language"] as? String ?? "English",
                type: row["type"] as? String ?? "main"
            )
        }
    }
}
