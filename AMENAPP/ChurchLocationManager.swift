// ChurchLocationManager.swift
// Geofencing, arrival detection, confidence scoring
// Battery-safe, foreground-first
// AMENAPP

import Foundation
import CoreLocation

// MARK: - ChurchLocationManager

@MainActor
@available(macOS, unavailable)
final class ChurchLocationManager: NSObject, ObservableObject {

    // MARK: - Shared Instance
    static let shared = ChurchLocationManager()

    // MARK: - Published Properties
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var nearestChurchContext: ChurchLocationContext?

    // MARK: - Private Properties
    private let locationManager = CLLocationManager()

    /// Maps churchId to its monitored circular geofence region
    private var monitoredChurches: [String: CLCircularRegion] = [:]

    /// Maps churchId to the time the user entered its geofence
    private var dwellTimers: [String: Date] = [:]

    /// Last known speed used for confidence scoring
    private var lastKnownSpeed: CLLocationSpeed = -1

    private let geofenceRadius: CLLocationDistance = 150          // 150 meters
    private let arrivedDwellThreshold: TimeInterval = 8 * 60       // 8 minutes
    private let inServiceDwellThreshold: TimeInterval = 30 * 60    // 30 minutes
    private let maxMonitoredRegions = 15                            // CLLocationManager OS limit

    // MARK: - Callbacks
    var onArrival: ((String, Double) -> Void)?   // (churchId, confidence)
    var onInService: ((String) -> Void)?
    var onExit: ((String, Int) -> Void)?          // (churchId, dwellSeconds)

    // MARK: - Init
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 30  // Update every 30m to conserve battery
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Permission

    /// Request when-in-use permission only. Never requests always-on upfront.
    func requestWhenInUsePermission() {
        guard authorizationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
        dlog("[ChurchLocation] Requested when-in-use location permission")
    }

    // MARK: - Monitoring Management

    /// Start monitoring a specific church's geofence.
    func startMonitoring(churchId: String, coordinate: CLLocationCoordinate2D) {
        guard monitoredChurches[churchId] == nil else { return }
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            dlog("[ChurchLocation] Cannot monitor \(churchId) — no location permission")
            return
        }
        let region = CLCircularRegion(
            center: coordinate,
            radius: geofenceRadius,
            identifier: churchId
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager.startMonitoring(for: region)
        monitoredChurches[churchId] = region
        dlog("[ChurchLocation] Started monitoring church \(churchId) at \(coordinate.latitude), \(coordinate.longitude)")
    }

    /// Stop monitoring a specific church.
    func stopMonitoring(churchId: String) {
        guard let region = monitoredChurches[churchId] else { return }
        locationManager.stopMonitoring(for: region)
        monitoredChurches.removeValue(forKey: churchId)
        dwellTimers.removeValue(forKey: churchId)
        dlog("[ChurchLocation] Stopped monitoring church \(churchId)")
    }

    /// Stop monitoring all churches.
    func stopAllMonitoring() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        monitoredChurches.removeAll()
        dwellTimers.removeAll()
        dlog("[ChurchLocation] Stopped all church monitoring")
    }

    /// Monitor a list of churches, rotating if over the OS limit of 15.
    /// Prioritizes upcoming (planning) and recently saved churches.
    func monitorSavedChurches(_ churches: [(id: String, coordinate: CLLocationCoordinate2D)]) {
        let limited = Array(churches.prefix(maxMonitoredRegions))
        // Stop monitoring churches no longer in the list
        let newIds = Set(limited.map { $0.id })
        for existingId in monitoredChurches.keys where !newIds.contains(existingId) {
            stopMonitoring(churchId: existingId)
        }
        // Start monitoring new ones
        for church in limited {
            if monitoredChurches[church.id] == nil {
                startMonitoring(churchId: church.id, coordinate: church.coordinate)
            }
        }
        dlog("[ChurchLocation] Now monitoring \(monitoredChurches.count) church(es)")
    }

    // MARK: - Confidence Scoring

    /// Calculates arrival confidence for a church based on available signals.
    func calculateArrivalConfidence(churchId: String) -> Double {
        var confidence: Double = 0.5 // Base from geofence entry

        // +0.2 if stationary (speed < 1 m/s)
        if lastKnownSpeed >= 0 && lastKnownSpeed < 1.0 {
            confidence += 0.2
        }

        // +0.2 if dwell > 3 minutes
        if let enteredAt = dwellTimers[churchId] {
            let dwellSeconds = Date().timeIntervalSince(enteredAt)
            if dwellSeconds > 180 {
                confidence += 0.2
            }
        }

        // +0.1 if during typical service hours
        if isDuringTypicalServiceHours() {
            confidence += 0.1
        }

        return min(confidence, 1.0)
    }

    // MARK: - Helpers

    private func isDuringTypicalServiceHours() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now) // 1 = Sun
        let hour = calendar.component(.hour, from: now)

        // Sunday morning (8am-1pm) or Sunday evening (5pm-9pm)
        if weekday == 1 {
            return (hour >= 8 && hour < 13) || (hour >= 17 && hour < 21)
        }
        // Midweek services (Wed 6pm-9pm)
        if weekday == 4 {
            return hour >= 18 && hour < 21
        }
        return false
    }
}

// MARK: - CLLocationManagerDelegate

extension ChurchLocationManager: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        let churchId = circularRegion.identifier
        Task { @MainActor in
            dwellTimers[churchId] = Date()
            let initialConfidence = 0.5
            dlog("[ChurchLocation] Entered region for church \(churchId), initial confidence: \(initialConfidence)")

            // Update nearest church context
            nearestChurchContext = ChurchLocationContext(
                churchId: churchId,
                state: .arrived,
                enteredAt: Date(),
                source: "geofence",
                arrivalConfidence: initialConfidence
            )

            // Schedule a dwell check after arrivedDwellThreshold
            DispatchQueue.main.asyncAfter(deadline: .now() + arrivedDwellThreshold) { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    let confidence = self.calculateArrivalConfidence(churchId: churchId)
                    if confidence > 0.6 {
                        self.onArrival?(churchId, confidence)
                        dlog("[ChurchLocation] Arrival confirmed for \(churchId), confidence: \(confidence)")
                    }
                }
            }

            // Schedule an in-service check after inServiceDwellThreshold
            DispatchQueue.main.asyncAfter(deadline: .now() + inServiceDwellThreshold) { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    guard self.dwellTimers[churchId] != nil else { return }
                    self.onInService?(churchId)
                    dlog("[ChurchLocation] In-service detected for \(churchId)")
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        let churchId = circularRegion.identifier
        Task { @MainActor in
            let dwellDuration: Int
            if let enteredAt = dwellTimers[churchId] {
                dwellDuration = Int(Date().timeIntervalSince(enteredAt))
            } else {
                dwellDuration = 0
            }
            dwellTimers.removeValue(forKey: churchId)
            dlog("[ChurchLocation] Exited region for church \(churchId), dwell: \(dwellDuration)s")
            if dwellDuration > Int(arrivedDwellThreshold) {
                onExit?(churchId, dwellDuration)
            }
            // Clear nearest context if it matches
            if nearestChurchContext?.churchId == churchId {
                nearestChurchContext = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            currentLocation = location
            // Cache speed for confidence scoring
            if location.speedAccuracy >= 0 {
                lastKnownSpeed = location.speed
            }
            dlog("[ChurchLocation] Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude), speed: \(location.speed)m/s")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            dlog("[ChurchLocation] Authorization changed to: \(manager.authorizationStatus.rawValue)")
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            } else {
                manager.stopUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        dlog("[ChurchLocation] Monitoring failed for region \(region?.identifier ?? "unknown"): \(error)")
    }
}
