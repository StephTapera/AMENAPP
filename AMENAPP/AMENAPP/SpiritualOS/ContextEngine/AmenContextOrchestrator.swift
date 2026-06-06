import Foundation
import CoreLocation
import CoreMotion
import FirebaseAuth
import FirebaseFirestore
import UIKit

// MARK: - AmenContextOrchestrator
//
// @Observable singleton that drives the 5-mode context system:
//   standard | driving | church | travel | event
//
// All sensor work starts only after start() is called (called from scenePhase .active
// in AMENAPPApp so nothing runs before the user is settled in).
//
// Privacy contract:
//   - Location is only started when CLAuthorizationStatus is .authorizedWhenInUse
//     or .authorizedAlways.
//   - Motion activity is started optimistically; if CMMotionActivityManager is
//     unavailable (hardware, permissions) the update closure simply never fires.
//   - No location or motion data is stored persistently; it is used only to
//     compute the current mode and is discarded.

@Observable
final class AmenContextOrchestrator: NSObject {

    // MARK: - Shared instance

    static let shared = AmenContextOrchestrator()

    // MARK: - Public state

    /// The currently detected context mode. Starts as `.standard`.
    var currentMode: AmenContextMode = .standard

    /// Set while `.event` mode is active. nil in all other modes.
    var eventCheckInSpace: (name: String, spaceId: String)? = nil

    // MARK: - Private infrastructure

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()

    /// Fires every 5 minutes for church-mode checks.
    private var churchCheckTimer: Timer?
    /// Fires every 2 minutes for event-mode checks.
    private var eventCheckTimer: Timer?

    /// Cached current CLLocation for speed / proximity use.
    private var latestLocation: CLLocation?

    /// Home region loaded once from Firestore at start().
    private var homeAdministrativeArea: String?
    private var homeCoordinate: CLLocation?

    /// Guard against multiple start() calls.
    private var isStarted = false

    // MARK: - Init (private — use .shared)

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Lifecycle

    /// Start all detectors. Safe to call multiple times (idempotent after first call).
    func start() {
        guard !isStarted else { return }
        isStarted = true
        loadHomeRegion()
        startLocationIfPermitted()
        startMotionDetection()
        startChurchCheckTimer()
        startEventCheckTimer()
    }

    /// Stop all detectors and invalidate timers.
    func stop() {
        isStarted = false
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        motionManager.stopActivityUpdates()
        churchCheckTimer?.invalidate()
        churchCheckTimer = nil
        eventCheckTimer?.invalidate()
        eventCheckTimer = nil
    }

    // MARK: - Mode Setter (centralised)

    @MainActor
    private func applyMode(_ mode: AmenContextMode) {
        guard mode != currentMode else { return }
        currentMode = mode
        if mode != .event { eventCheckInSpace = nil }
        NotificationCenter.default.post(name: .amenContextModeChanged, object: mode)
    }

    // MARK: - Location Permission

    private func startLocationIfPermitted() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            // Don't prompt before the user has authenticated — would show on landing screen.
            guard Auth.auth().currentUser != nil else { return }
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            locationManager.startMonitoringSignificantLocationChanges()
        default:
            break
        }
    }

    // MARK: - Motion / Driving Detection

    private func startMotionDetection() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            self.handleMotionActivity(activity)
        }
    }

    private func handleMotionActivity(_ activity: CMMotionActivity) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if activity.automotive {
                // Confirm with speed if location is available
                let speedConfirmed: Bool
                if let loc = latestLocation, loc.speed > 0 {
                    speedConfirmed = loc.speed > 6.7  // ~15 mph
                } else {
                    // No recent location — trust CMMotion alone
                    speedConfirmed = true
                }
                if speedConfirmed {
                    applyMode(.driving)
                }
            } else if activity.stationary || activity.walking || activity.running || activity.cycling {
                if currentMode == .driving {
                    applyMode(.standard)
                }
            }
        }
    }

    // MARK: - Church Mode (5-minute timer)

    private func startChurchCheckTimer() {
        churchCheckTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.evaluateChurchMode() }
        }
        RunLoop.main.add(t, forMode: .common)
        churchCheckTimer = t
        // Run once immediately
        Task { await evaluateChurchMode() }
    }

    private func evaluateChurchMode() async {
        // Condition 1: Sunday morning + near primaryChurchLocation
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)  // 1 == Sunday
        let hour = calendar.component(.hour, from: now)

        if weekday == 1 && hour >= 8 && hour <= 13 {
            if await isNearPrimaryChurch() {
                await applyMode(.church)
                return
            }
        }

        // Condition 2: Upcoming church event in next 30 minutes
        if await hasUpcomingChurchEvent() {
            await applyMode(.church)
        }
    }

    private func isNearPrimaryChurch() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid,
              let loc = latestLocation else { return false }
        do {
            let snap = try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("churchProfile").document("primary")
                .getDocument()
            guard let data = snap.data(),
                  let lat = data["latitude"] as? Double,
                  let lon = data["longitude"] as? Double else { return false }
            let churchLoc = CLLocation(latitude: lat, longitude: lon)
            return loc.distance(from: churchLoc) < 500
        } catch {
            return false
        }
    }

    private func hasUpcomingChurchEvent() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        let now = Date()
        let windowStart = now.addingTimeInterval(-900)   // 15 min ago
        let windowEnd   = now.addingTimeInterval(1800)   // +30 min

        do {
            let spacesSnap = try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("spaces")
                .getDocuments()
            for doc in spacesSnap.documents {
                let spaceId = doc.documentID
                let eventsSnap = try await Firestore.firestore()
                    .collection("spaces").document(spaceId)
                    .collection("events")
                    .whereField("eventType", isEqualTo: "church")
                    .whereField("attendees", arrayContains: uid)
                    .whereField("startTime", isGreaterThanOrEqualTo: windowStart)
                    .whereField("startTime", isLessThanOrEqualTo: windowEnd)
                    .getDocuments()
                if !eventsSnap.documents.isEmpty { return true }
            }
        } catch {
            // Silently degrade
        }
        return false
    }

    // MARK: - Travel Mode (significant location change)

    private func evaluateTravelMode(location: CLLocation) {
        guard let home = homeCoordinate else { return }
        let distanceFromHome = location.distance(from: home)
        guard distanceFromHome > 80_000 else {
            // Within 80 km of home — not traveling
            Task { @MainActor [weak self] in
                guard let self else { return }
                if currentMode == .travel { applyMode(.standard) }
            }
            return
        }

        // Reverse-geocode and compare administrative area
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }
            guard let area = placemarks?.first?.administrativeArea else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let homeArea = self.homeAdministrativeArea, area != homeArea {
                    self.applyMode(.travel)
                } else if self.homeAdministrativeArea == nil {
                    // No home region configured — use distance alone
                    self.applyMode(.travel)
                }
            }
        }
    }

    // MARK: - Event Mode (2-minute timer)

    private func startEventCheckTimer() {
        eventCheckTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.evaluateEventMode() }
        }
        RunLoop.main.add(t, forMode: .common)
        eventCheckTimer = t
        Task { await evaluateEventMode() }
    }

    private func evaluateEventMode() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let now = Date()
        let windowStart = now.addingTimeInterval(-900)   // -15 min
        let windowEnd   = now.addingTimeInterval(900)    // +15 min

        do {
            let spacesSnap = try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("spaces")
                .getDocuments()
            for doc in spacesSnap.documents {
                let spaceId = doc.documentID
                let spaceName = doc.data()["name"] as? String ?? spaceId
                let eventsSnap = try await Firestore.firestore()
                    .collection("spaces").document(spaceId)
                    .collection("events")
                    .whereField("attendees", arrayContains: uid)
                    .whereField("startTime", isGreaterThanOrEqualTo: windowStart)
                    .whereField("startTime", isLessThanOrEqualTo: windowEnd)
                    .getDocuments()
                if let eventDoc = eventsSnap.documents.first {
                    let eventName = eventDoc.data()["name"] as? String ?? spaceName
                    await MainActor.run {
                        self.eventCheckInSpace = (name: eventName, spaceId: spaceId)
                    }
                    await applyMode(.event)
                    return
                }
            }
        } catch {
            // Silently degrade
        }

        // No active event found — revert if we were in event mode
        await MainActor.run {
            if self.currentMode == .event {
                self.eventCheckInSpace = nil
                Task { await self.applyMode(.standard) }
            }
        }
    }

    // MARK: - Home Region Loading

    private func loadHomeRegion() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            do {
                // Try dedicated profile/home doc first
                let topSnap = try await Firestore.firestore()
                    .collection("users").document(uid)
                    .getDocument()
                let topData = topSnap.data() ?? [:]
                let resolvedArea = topData["homeRegion"] as? String
                let resolvedLat  = topData["homeLatitude"]  as? Double
                let resolvedLon  = topData["homeLongitude"] as? Double

                await MainActor.run {
                    self.homeAdministrativeArea = resolvedArea
                    if let la = resolvedLat, let lo = resolvedLon {
                        self.homeCoordinate = CLLocation(latitude: la, longitude: lo)
                    }
                }
            } catch {
                // Home region not critical — travel detection simply uses distance fallback.
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension AmenContextOrchestrator: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            manager.startMonitoringSignificantLocationChanges()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            manager.stopMonitoringSignificantLocationChanges()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        latestLocation = location
        // Travel mode evaluation on every significant location change
        evaluateTravelMode(location: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Non-fatal — graceful degradation; context engine continues with cached state.
    }
}
