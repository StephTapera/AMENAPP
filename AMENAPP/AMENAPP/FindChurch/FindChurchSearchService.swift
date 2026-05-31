//
//  FindChurchSearchService.swift
//  AMENAPP/FindChurch
//
//  Phase 1 / Master Run — Find a Church backend bridge.
//
//  Implements ChurchSearchServiceProtocol (Phase0Contracts.swift).
//  Calls the `churchSearchProxy` Firebase callable (emulator only until
//  [NEEDS HUMAN DEPLOY] is completed).
//
//  Security model:
//    - No API keys, Algolia keys, or geo credentials live on the device.
//    - App Check + Auth are enforced at the Cloud Function level.
//    - The CF is the sole search proxy; the iOS layer only submits structured
//      query parameters.
//
//  Fallback:
//    If the CF is unavailable (network error, emulator not running, CF throws
//    functions-unavailable / internal), the service falls back to
//    SmartChurchSearchService and adapts its results into [ChurchRecord].
//    Any other error (unauthenticated, invalid-argument, etc.) is re-thrown
//    so the caller can display an appropriate error state.
//
//  Feature flag:
//    Gated by `findAChurchEnabled`. When false the service returns [] immediately
//    without making any network call. A9 will replace the compile-time constant
//    with a read from MasterRunFeatureFlags.findAChurch (which A9 wires to
//    the app's Remote Config / local flags provider).
//

import Foundation
import CoreLocation
import FirebaseFunctions

// ─── Feature flag ─────────────────────────────────────────────────────────────

// A9 WIRE POINT: replace this constant with MasterRunFeatureFlags.findAChurch
// once A9 wires it to the flags provider.
private let findAChurchEnabled: Bool = false

// ─── Response shape ───────────────────────────────────────────────────────────

/// Internal Codable type that matches the JSON shape returned by the
/// `churchSearchProxy` Cloud Function:
///   { "churches": [ ChurchRecord, … ] }
private struct ChurchSearchProxyResponse: Decodable {
    let churches: [ChurchRecord]
}

/// ISO-8601 date string as sent by the CF mock data for `serviceTimes.start`.
/// The CF returns strings like "2000-01-02T10:00:00Z"; we parse them via
/// the ISO8601DateFormatter rather than JSONDecoder's standard date strategy
/// so the decoder remains self-contained.
private extension DateFormatter {
    static let iso8601Full: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let iso8601Basic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - FindChurchSearchService

@MainActor
final class FindChurchSearchService: ObservableObject {

    // MARK: Shared

    static let shared = FindChurchSearchService()

    // MARK: Private

    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    // MARK: ChurchSearchServiceProtocol

    /// Searches for churches matching the given query and filters.
    ///
    /// - When `findAChurchEnabled` is false, returns `[]` immediately.
    /// - When the CF is available, calls `churchSearchProxy` with a 15-second
    ///   timeout via the project's `callWithTimeout` pattern.
    /// - On CF availability errors, falls back to `SmartChurchSearchService`
    ///   and adapts results to `[ChurchRecord]`.
    /// - All other errors (auth, bad input, etc.) are re-thrown.
    func search(
        query: String,
        coordinate: CLLocationCoordinate2D?,
        filters: ChurchSearchFilters
    ) async throws -> [ChurchRecord] {

        // Feature flag guard — graceful no-op when flag is OFF.
        guard findAChurchEnabled else { return [] }

        // Build the payload that the CF expects.
        var payload: [String: Any] = [
            "query": query,
            "sortBy": filters.sortBy.rawValue,
        ]
        if let coord = coordinate {
            payload["lat"] = coord.latitude
            payload["lng"] = coord.longitude
        }
        if let openNow = filters.openNow {
            payload["openNow"] = openNow
        }
        if let denomination = filters.denomination {
            payload["denomination"] = denomination.rawValue
        }
        if let maxDistance = filters.maxDistanceMeters {
            payload["maxDistanceMeters"] = maxDistance
        }

        // Call the CF proxy (15-second timeout for data queries).
        do {
            let result = try await functions.callWithTimeout(
                "churchSearchProxy",
                data: payload,
                timeout: 15
            )
            return try decodeChurches(from: result.data)
        } catch let error as NSError
            where isCFAvailabilityError(error) {
            // CF unavailable (emulator not running, network issue, etc.).
            // Fall back to SmartChurchSearchService.
            return await fallbackSearch(query: query, coordinate: coordinate, filters: filters)
        }
    }
}

// MARK: - Decoding helpers

private extension FindChurchSearchService {

    /// Decodes the raw Any? value from HTTPSCallableResult into [ChurchRecord].
    ///
    /// The CF returns a JSON object `{ "churches": [...] }`. Firebase deserialises
    /// this as `[String: Any]` on iOS, so we round-trip through JSONSerialization
    /// to use Codable rather than manual dictionary casting.
    func decodeChurches(from value: Any?) throws -> [ChurchRecord] {
        guard let rawDict = value as? [String: Any] else {
            return []
        }
        let data = try JSONSerialization.data(withJSONObject: rawDict)
        let decoder = JSONDecoder()
        // The CF sends ISO-8601 date strings for serviceTimes.start.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = DateFormatter.iso8601Basic.date(from: string)
                ?? DateFormatter.iso8601Full.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string: \(string)"
            )
        }
        let response = try decoder.decode(ChurchSearchProxyResponse.self, from: data)
        return response.churches
    }

    /// Returns true for Firebase Functions errors that indicate the CF is
    /// simply unreachable, so we can fall back safely.
    func isCFAvailabilityError(_ error: NSError) -> Bool {
        // FunctionsErrorCode raw values: unavailable = 14, internal = 13, deadlineExceeded = 4
        let unavailableCodes: Set<Int> = [4, 13, 14]
        guard error.domain == FunctionsErrorDomain else { return false }
        return unavailableCodes.contains(error.code)
    }
}

// MARK: - Fallback: SmartChurchSearchService

private extension FindChurchSearchService {

    /// Falls back to SmartChurchSearchService and adapts results to [ChurchRecord].
    /// Returns [] on any error so callers always get a valid (possibly empty) result.
    func fallbackSearch(
        query: String,
        coordinate: CLLocationCoordinate2D?,
        filters: ChurchSearchFilters
    ) async -> [ChurchRecord] {
        guard let coord = coordinate else { return [] }
        do {
            let items = try await SmartChurchSearchService.shared.search(
                query: query,
                userLocation: coord,
                radiusMiles: filters.maxDistanceMeters.map { $0 / 1609.34 }
            )
            return items.compactMap { item in
                adaptSmartChurchItem(item, filters: filters)
            }
        } catch {
            return []
        }
    }

    /// Converts a SmartChurchSearchItem into a ChurchRecord.
    /// Fields not present in SmartChurchSummary are set to safe defaults.
    func adaptSmartChurchItem(
        _ item: SmartChurchSearchItem,
        filters: ChurchSearchFilters
    ) -> ChurchRecord? {
        let church = item.church

        // Map denomination string to enum (best-effort; unknown → .other).
        let denomination = ChurchSearchDenomination(rawValue: church.denomination.lowercased()) ?? .other

        // Apply denomination filter if requested.
        if let filterDenom = filters.denomination, denomination != filterDenom {
            return nil
        }

        let coordinate = ChurchGeoPoint(latitude: church.latitude, longitude: church.longitude)

        // Convert SmartChurchServiceTime → ChurchJourneyServiceTime (Int weekday + Date start).
        let serviceTimes: [ChurchJourneyServiceTime] = church.serviceTimes.compactMap { st in
            // SmartChurchServiceTime uses day: String + time: String (e.g. "Sunday", "10:00 AM").
            // Map day name to ISO weekday integer (1=Sunday … 7=Saturday).
            let weekday = weekdayNumber(from: st.day)
            guard let time = parseTimeString(st.time) else { return nil }
            return ChurchJourneyServiceTime(weekday: weekday, start: time, label: st.displayText)
        }

        return ChurchRecord(
            id: church.id,
            name: church.name,
            denomination: denomination,
            coordinate: coordinate,
            address: [church.address, church.city, church.state, church.zip]
                .filter { !$0.isEmpty }
                .joined(separator: ", "),
            serviceTimes: serviceTimes,
            distanceMeters: item.distanceMiles * 1609.34,
            rating: nil,           // SmartChurchSummary has no rating field
            isOpenNow: nil,        // SmartChurchSummary has no isOpenNow field
            verified: church.claimed
        )
    }

    // ── Day-name → ISO weekday ────────────────────────────────────────────────

    func weekdayNumber(from day: String) -> Int {
        switch day.lowercased().trimmingCharacters(in: .whitespaces) {
        case "sunday":    return 1
        case "monday":    return 2
        case "tuesday":   return 3
        case "wednesday": return 4
        case "thursday":  return 5
        case "friday":    return 6
        case "saturday":  return 7
        default:          return 1  // Default to Sunday
        }
    }

    // ── "10:00 AM" → Date (time components only) ─────────────────────────────

    func parseTimeString(_ timeString: String) -> Date? {
        let trimmed = timeString.trimmingCharacters(in: .whitespaces)
        // Try "h:mm a" (e.g. "10:00 AM") against a fixed reference date so the
        // time components are stable and the date component is ignored at display time.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["h:mm a", "H:mm", "hh:mm a"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}

// MARK: - ChurchSearchServiceProtocol conformance

extension FindChurchSearchService: ChurchSearchServiceProtocol {}
