import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class LocationContextService: NSObject, ObservableObject {
    static let shared = LocationContextService()

    @Published private(set) var currentContext: LocationContext = .unknown
    @Published private(set) var isLocationAvailable = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()
    private var db = Firestore.firestore()

    private let lastCityKey = "amencompanion_last_city"
    private let lastStateKey = "amencompanion_last_state"
    private let lastCountryKey = "amencompanion_last_country"

    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    private override init() {
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.distanceFilter = 2000
        locationManager.delegate = self
    }

    func requestLocationIfNeeded() {
        let status = locationManager.authorizationStatus
        authorizationStatus = status
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }

    func stopTracking() {
        locationManager.stopUpdatingLocation()
    }

    // Resolves approximate location for companion features — never exact
    func resolveApproximateLocation() async -> LocationContext {
        guard locationManager.authorizationStatus == .authorizedWhenInUse ||
              locationManager.authorizationStatus == .authorizedAlways else {
            return .unknown
        }
        let clLocation = await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
        guard let clLocation else { return .unknown }
        return await buildContext(from: clLocation)
    }

    private func buildContext(from location: CLLocation) async -> LocationContext {
        let geocoder = CLGeocoder()
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return .unknown
        }

        let city = placemark.locality ?? ""
        let state = placemark.administrativeArea ?? ""
        let country = placemark.isoCountryCode ?? ""

        // Only compare and write location history when the user has granted personalization consent.
        // Without consent: isNewArea stays false so the new-city prompt is never triggered
        // and no city/state history is persisted. Basic location coordinates are still available.
        let isNewArea: Bool
        if AmenAIConsentStore.shared.hasFabricConsent(for: .personalization) {
            let lastCity = UserDefaults.standard.string(forKey: lastCityKey) ?? ""
            let lastState = UserDefaults.standard.string(forKey: lastStateKey) ?? ""
            isNewArea = !city.isEmpty && (city != lastCity || state != lastState)
            if isNewArea {
                UserDefaults.standard.set(city, forKey: lastCityKey)
                UserDefaults.standard.set(state, forKey: lastStateKey)
                UserDefaults.standard.set(country, forKey: lastCountryKey)
            }
        } else {
            isNewArea = false
        }

        let isInternational = country != "US" && !country.isEmpty
        let broadLabel = buildBroadLabel(city: city, state: state, country: country, isInternational: isInternational)

        let context = LocationContext(
            city: city,
            state: state,
            country: country,
            coordinate: location.coordinate,
            environment: isInternational ? .international : .unknown,
            isNewArea: isNewArea,
            broadAreaLabel: broadLabel
        )

        currentContext = context
        isLocationAvailable = true

        if isNewArea, let uid = Auth.auth().currentUser?.uid {
            try? await persistLocationContext(uid: uid, context: context)
        }

        return context
    }

    private func buildBroadLabel(city: String, state: String, country: String, isInternational: Bool) -> String {
        if isInternational {
            return [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
        }
        return [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func persistLocationContext(uid: String, context: LocationContext) async throws {
        let data: [String: Any] = [
            "broadArea": context.broadAreaLabel,
            "city": context.city,
            "state": context.state,
            "country": context.country,
            "isNewArea": context.isNewArea,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        try await db.collection("users").document(uid)
            .collection("location_context").document("current")
            .setData(data, merge: true)
    }
}

extension LocationContextService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }
}
