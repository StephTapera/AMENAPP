//
//  ChurchSearchService.swift
//  AMENAPP
//

import Foundation
import MapKit
import CoreLocation

enum ChurchSearchError: LocalizedError {
    case noInternetConnection
    case noResultsFound
    case tooManyRequests
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .noInternetConnection:
            return String(localized: "church.search.error.offline", defaultValue: "No internet connection available")
        case .noResultsFound:
            return String(localized: "church.search.error.no_results", defaultValue: "No churches found in this area")
        case .tooManyRequests:
            return String(localized: "church.search.error.throttled", defaultValue: "Too many search requests. Please try again later")
        case .locationUnavailable:
            return String(localized: "church.search.error.location_unavailable", defaultValue: "Location services are unavailable")
        }
    }
}

@MainActor
final class ChurchSearchService: ObservableObject {
    static let shared = ChurchSearchService()

    @Published var isSearching = false
    @Published var searchResults: [Church] = []

    private let dataService = ChurchDataService.shared

    private init() {}

    func searchChurches(
        query: String = "",
        near location: CLLocationCoordinate2D?,
        radius: Double = 8000
    ) async throws -> [Church] {
        isSearching = true
        defer { isSearching = false }

        let queryLocation = location.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let radiusMiles = max(5, radius / 1609.34)

        let results = try await dataService.searchChurches(
            query: query,
            near: queryLocation,
            radius: radiusMiles
        )

        guard !results.isEmpty else {
            throw ChurchSearchError.noResultsFound
        }

        let churches = results.compactMap { result -> Church? in
            guard let entity = result.church else { return nil }
            let serviceTime = entity.serviceTimes.first.map { "\($0.time)" } ?? ""
            let distanceMiles = result.distance ?? 0
            let distanceStr = distanceMiles < 1
                ? String(format: "%.0f ft", distanceMiles * 5280)
                : String(format: "%.1f mi", distanceMiles)
            return Church(
                name: entity.name,
                denomination: entity.denomination ?? "",
                address: entity.address,
                distance: distanceStr,
                distanceValue: distanceMiles,
                serviceTime: serviceTime,
                phone: entity.phoneNumber ?? "",
                coordinate: CLLocationCoordinate2D(
                    latitude: entity.coordinate.latitude,
                    longitude: entity.coordinate.longitude
                ),
                website: entity.website
            )
        }
        .sorted { $0.distanceValue < $1.distanceValue }

        guard !churches.isEmpty else {
            throw ChurchSearchError.noResultsFound
        }

        searchResults = churches
        return churches
    }
}
