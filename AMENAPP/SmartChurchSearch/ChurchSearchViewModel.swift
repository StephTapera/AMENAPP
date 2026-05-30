import Foundation
import CoreLocation
import MapKit
import SwiftUI

@MainActor
final class ChurchSearchViewModel: ObservableObject {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case list
        case map

        var id: String { rawValue }
    }

    @Published var query = ""
    @Published var radiusMiles = 15.0
    @Published var displayMode: DisplayMode = .list
    @Published private(set) var results: [SmartChurchSearchItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isNearbySearch = false
    @Published var errorMessage: String?
    @Published var selectedResult: SmartChurchSearchItem?
    @Published var mapCamera: MapCameraPosition = .automatic
    @Published var showLocationPrompt = false

    private let service: SmartChurchSearchService
    private let locationProvider: ChurchSearchLocationProviding
    private var searchTask: Task<Void, Never>?

    init(
        service: SmartChurchSearchService? = nil,
        locationProvider: ChurchSearchLocationProviding? = nil
    ) {
        self.service = service ?? SmartChurchSearchService.shared
        self.locationProvider = locationProvider ?? ChurchSearchLocationProvider.shared
    }

    func search() {
        isNearbySearch = false
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Describe the church you're looking for."
            return
        }

        searchTask?.cancel()
        isLoading = true
        errorMessage = nil

        searchTask = Task { [service, locationProvider, radiusMiles] in
            do {
                let location = try await locationProvider.currentCoordinate()
                let items = try await service.search(query: trimmed, userLocation: location, radiusMiles: radiusMiles)
                try Task.checkCancellation()
                await MainActor.run {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        self.results = items
                        self.selectedResult = items.first
                        self.updateMapCamera()
                    }
                    self.isLoading = false
                    if items.isEmpty {
                        self.errorMessage = "No churches matched that search nearby."
                    }
                }
            } catch is CancellationError {
                await MainActor.run { self.isLoading = false }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func loadNearby() {
        guard results.isEmpty, !isLoading else { return }
        isNearbySearch = true
        query = ""
        searchTask?.cancel()
        isLoading = true
        errorMessage = nil
        searchTask = Task { [service, locationProvider, radiusMiles] in
            do {
                let location = try await locationProvider.currentCoordinate()
                let items = try await service.search(query: "church near me", userLocation: location, radiusMiles: radiusMiles)
                try Task.checkCancellation()
                await MainActor.run {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        self.results = items
                        self.selectedResult = items.first
                        self.updateMapCamera()
                    }
                    self.isLoading = false
                }
            } catch is CancellationError {
                await MainActor.run { self.isLoading = false }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    if error is ChurchSearchLocationError {
                        self.showLocationPrompt = true
                    } else {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    func select(_ result: SmartChurchSearchItem) {
        selectedResult = result
        mapCamera = .region(MKCoordinateRegion(
            center: result.church.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        ))
    }

    func updateMapCamera() {
        guard !results.isEmpty else {
            mapCamera = .automatic
            return
        }
        let coordinates = results.map(\.church.coordinate)
        let minLat = coordinates.map(\.latitude).min() ?? coordinates.first?.latitude ?? 0
        let maxLat = coordinates.map(\.latitude).max() ?? coordinates.first?.latitude ?? 0
        let minLng = coordinates.map(\.longitude).min() ?? coordinates.first?.longitude ?? 0
        let maxLng = coordinates.map(\.longitude).max() ?? coordinates.first?.longitude ?? 0
        mapCamera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.04, (maxLat - minLat) * 1.6), longitudeDelta: max(0.04, (maxLng - minLng) * 1.6))
        ))
    }
}

extension ChurchSearchViewModel {
    static let quickIntents: [QuickChurchIntent] = [
        .init(label: "Young Adults",   icon: "person.2.fill",        query: "church with a strong young adults community near me"),
        .init(label: "Families",       icon: "house.fill",            query: "family-friendly church with kids ministry near me"),
        .init(label: "Bible Teaching", icon: "book.fill",             query: "church with strong expository Bible teaching near me"),
        .init(label: "Small Groups",   icon: "person.3.fill",         query: "church with active small groups and community near me"),
        .init(label: "Worship Night",  icon: "music.note",            query: "church with contemporary worship nights near me"),
        .init(label: "Recovery",       icon: "heart.fill",            query: "church with recovery ministry near me"),
        .init(label: "Traditional",    icon: "building.columns.fill", query: "traditional liturgical church near me"),
        .init(label: "New Believers",  icon: "sparkles",              query: "church welcoming for new Christians near me"),
        .init(label: "Prayer",         icon: "hands.sparkles.fill",   query: "church known for intercessory prayer near me"),
    ]
}

protocol ChurchSearchLocationProviding {
    func currentCoordinate() async throws -> CLLocationCoordinate2D
}

final class ChurchSearchLocationProvider: NSObject, ChurchSearchLocationProviding, CLLocationManagerDelegate {
    static let shared = ChurchSearchLocationProvider()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        if let coordinate = manager.location?.coordinate {
            return coordinate
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                continuation.resume(throwing: ChurchSearchLocationError.denied)
                self.continuation = nil
            @unknown default:
                continuation.resume(throwing: ChurchSearchLocationError.denied)
                self.continuation = nil
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            continuation?.resume(throwing: ChurchSearchLocationError.denied)
            continuation = nil
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

enum ChurchSearchLocationError: LocalizedError {
    case denied

    var errorDescription: String? {
        "Location permission is needed to rank churches by distance."
    }
}
