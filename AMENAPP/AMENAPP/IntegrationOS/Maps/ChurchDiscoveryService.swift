// ChurchDiscoveryService.swift — AMEN IntegrationOS
// Actor that uses MapKit local search to find nearby churches.

import Foundation
import MapKit
import CoreLocation
import FirebaseRemoteConfig

actor ChurchDiscoveryService {
    static let shared = ChurchDiscoveryService()
    private init() {}

    private let remoteConfig = RemoteConfig.remoteConfig()
    private var isEnabled: Bool { remoteConfig.configValue(forKey: "integration_maps_enabled").boolValue }

    struct ChurchResult: Identifiable {
        let id: String
        let name: String
        let address: String
        let coordinate: CLLocationCoordinate2D
        let phoneNumber: String?
        let url: URL?
        let mapItem: MKMapItem
    }

    func searchNearby(
        coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance = 8000
    ) async throws -> [ChurchResult] {
        guard isEnabled else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "church"
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radiusMeters,
            longitudinalMeters: radiusMeters
        )

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        return response.mapItems.map { item in
            ChurchResult(
                id: item.identifier?.rawValue ?? UUID().uuidString,
                name: item.name ?? "Church",
                address: formattedAddress(item.placemark),
                coordinate: item.placemark.coordinate,
                phoneNumber: item.phoneNumber,
                url: item.url,
                mapItem: item
            )
        }
    }

    func directions(to mapItem: MKMapItem) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = mapItem
        request.transportType = .automobile
        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        guard let route = response.routes.first else {
            throw IntegrationOSError.providerUnavailable("apple_maps")
        }
        return route
    }

    private func formattedAddress(_ placemark: CLPlacemark) -> String {
        [placemark.subThoroughfare, placemark.thoroughfare, placemark.locality, placemark.administrativeArea]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
