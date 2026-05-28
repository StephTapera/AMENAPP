import Foundation
import CoreLocation

@MainActor
final class SmartCommunityLocationManager: NSObject, ObservableObject {
    static let shared = SmartCommunityLocationManager()

    @Published private(set) var locationState: SmartSearchLocationState = .notDetermined
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var manualLocationText: String = ""

    private let locationManager = CLLocationManager()
    private var locationCompletion: ((CLLocationCoordinate2D?) -> Void)?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = locationManager.authorizationStatus
        syncState()
    }

    func requestLocationIfNeeded() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            locationState = .denied
        @unknown default:
            locationState = .denied
        }
    }

    func applyManualLocation() {
        let trimmed = manualLocationText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        locationState = .manual(trimmed)
    }

    func clearManualLocation() {
        manualLocationText = ""
        syncState()
    }

    private func syncState() {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if let loc = locationManager.location {
                locationState = .available(loc.coordinate)
            }
        case .denied, .restricted:
            locationState = .denied
        default:
            locationState = .notDetermined
        }
    }
}

extension SmartCommunityLocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.locationState = .available(loc.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if self.locationState == .notDetermined {
                self.locationState = .denied
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            self.syncState()
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }
}
