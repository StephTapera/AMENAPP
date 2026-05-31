// FindChurchLocationManager.swift
// AMENAPP
//
// CLLocationManager wrapper for the Find a Church feature.
// Handles: permission request, one-shot location fetch, error states.
// Distinct from ChurchLocationManager (geofencing/dwell) — this is
// a lightweight, single-purpose wrapper for the map view.

import Foundation
import CoreLocation

// MARK: - FindChurchLocationManager

/// A lightweight CLLocationManager wrapper for the church finder map.
/// Handles: requestWhenInUseAuthorization, one-shot requestLocation(), error states.
/// This is separate from ChurchLocationManager (which handles geofencing/dwell detection).
@MainActor
final class FindChurchLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published State

    /// Most recently received user coordinate. Nil until a successful fix.
    @Published var userLocation: CLLocationCoordinate2D?

    /// Current CLLocationManager authorization status.
    @Published var authorizationStatus: CLAuthorizationStatus

    /// Set on permission denial or a failed location request.
    @Published var error: Error?

    // MARK: - Private

    private let manager = CLLocationManager()

    /// True while we're waiting for a one-shot location response.
    private var pendingLocationRequest = false

    // MARK: - Init

    override init() {
        authorizationStatus = CLLocationManager.authorizationStatus()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Public API

    /// Requests location permission if needed, then performs a one-shot `requestLocation()`.
    /// Safe to call multiple times — skips the request if already authorized and a fix is pending.
    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // Will re-enter via locationManagerDidChangeAuthorization
        case .authorizedWhenInUse, .authorizedAlways:
            fetchOneShotLocation()
        case .denied, .restricted:
            error = LocationError.permissionDenied
        @unknown default:
            break
        }
    }

    /// Stops any ongoing location updates (call on view disappear).
    func stopUpdating() {
        manager.stopUpdatingLocation()
        pendingLocationRequest = false
    }

    // MARK: - Helpers

    private func fetchOneShotLocation() {
        guard !pendingLocationRequest else { return }
        pendingLocationRequest = true
        error = nil
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                self.fetchOneShotLocation()
            } else if manager.authorizationStatus == .denied ||
                      manager.authorizationStatus == .restricted {
                self.error = LocationError.permissionDenied
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.userLocation = coordinate
            self.pendingLocationRequest = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.error = error
            self.pendingLocationRequest = false
        }
    }
}

// MARK: - LocationError

enum LocationError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission is required to find churches near you. Please enable it in Settings."
        }
    }
}
