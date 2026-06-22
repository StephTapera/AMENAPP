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

        guard let coord = location else {
            throw ChurchSearchError.locationUnavailable
        }
        let queryLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
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
            let distanceMiles = result.distance ?? result.church?.distance(from: queryLocation) ?? 0.0
            let distanceStr = distanceMiles < 1 ? "< 1 mi" : String(format: "%.1f mi", distanceMiles)
            let lat = result.church?.coordinate.latitude ?? 0.0
            let lon = result.church?.coordinate.longitude ?? 0.0
            let serviceTime = result.church?.serviceTimes.first
                .map { "\($0.serviceType ?? "Service") \($0.time)" } ?? "Sunday Service"
            return Church(
                name: result.name,
                denomination: result.church?.denomination ?? "Non-Denominational",
                address: "\(result.address), \(result.city)",
                distance: distanceStr,
                distanceValue: distanceMiles,
                serviceTime: serviceTime,
                phone: result.church?.phoneNumber ?? "",
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                website: result.church?.website
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
