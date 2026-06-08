import Foundation
import SwiftUI
import CoreLocation
import FirebaseFunctions
import FirebaseAuth

// MARK: - SpiritualOSContextManager
// @MainActor ObservableObject that owns the Context Engine lifecycle.
// Injected via .environmentObject() at ContentView level by the Lead.
// DORMANT until spiritualOS_context_engine_enabled == true AND permissions granted.
// Privacy contract: no location/motion starts unless isEnabled AND user has opted in.

@MainActor
final class SpiritualOSContextManager: NSObject, ObservableObject {

    // MARK: Published state

    @Published var contextState: AmenContextState = AmenContextState()
    @Published var isActive: Bool = false

    // MARK: Private state

    private let userId: String
    private var locationManager: CLLocationManager?
    private var evaluationTimer: Timer?
    private let functions = Functions.functions()

    // MARK: Feature flag
    // Gated at AppStorage level — changes take effect on next launch/activate call.

    @AppStorage("spiritualOS_context_engine_enabled") private var isEnabled: Bool = true

    // MARK: Test church coordinate (placeholder until churchEnhancementFunctions CF is wired)
    // Real implementation will query the CF for church locations by user region.

    fileprivate let testChurchCoordinate = CLLocationCoordinate2D(
        latitude: 33.7490,  // Atlanta, GA — representative placeholder
        longitude: -84.3880
    )
    fileprivate let churchProximityThresholdMeters: CLLocationDistance = 500.0

    // MARK: - Init

    init(userId: String) {
        self.userId = userId
        super.init()
        contextState.timeOfDay = SOTimeOfDay.current()
        if isEnabled {
            activate()
        }
    }

    // MARK: - Lifecycle

    /// Activates the context engine. No-ops if already active.
    /// Starts time-of-day and Sunday detection. Location/motion only if user has opted in.
    func activate() {
        guard !isActive else { return }
        isActive = true
        evaluateTimeContext()
        startEvaluationTimer()

        // Restart location if permission was previously granted
        if contextState.userPermissions.geofenceOptIn &&
           contextState.userPermissions.locationEnabled {
            startLocationUpdatesIfPermitted()
        }
    }

    /// Stops all active monitoring and invalidates the timer.
    func deactivate() {
        isActive = false
        invalidateTimer()
        stopLocationMonitoring()
    }

    /// Full logout cleanup — deactivates, resets state, and fires server cleanup callable.
    func onLogout() async {
        deactivate()
        await cleanupContextOnLogout()
        contextState = AmenContextState()
    }

    // MARK: - Permission Request

    /// Entry point for the Privacy Consent Sheet. Call this when the user taps "Enable Selected"
    /// and has toggled geofence/location on. Sets the opt-in flag then requests system permission.
    func requestGeofenceOptIn() {
        contextState.userPermissions.geofenceOptIn = true

        let manager = CLLocationManager()
        manager.delegate = locationDelegate
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 200
        locationManager = manager

        switch manager.authorizationStatus {
        case .notDetermined:
            guard Auth.auth().currentUser != nil else { return }
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            contextState.userPermissions.locationEnabled = true
            startLocationUpdatesIfPermitted()
        case .denied, .restricted:
            contextState.userPermissions.locationEnabled = false
        @unknown default:
            contextState.userPermissions.locationEnabled = false
        }
    }

    // MARK: - Mode Evaluation

    /// Re-evaluates the context mode from current signals. Called by the timer and after
    /// any permission or location signal changes.
    func updateMode() {
        let tod = SOTimeOfDay.current()
        contextState.timeOfDay = tod
        contextState.isSundayChurchTime = isSundayMorning()

        let newMode = resolvedMode(tod: tod)
        guard newMode != contextState.mode else { return }

        contextState.mode = newMode
        contextState.lastUpdated = Date()

        Task {
            await syncToServer()
        }
    }

    // MARK: - Server Sync

    /// Syncs the current context state to Firebase. Fire-and-forget — errors are logged silently.
    func syncToServer() async {
        let payload: [String: Any] = [
            "userId": userId,
            "mode": contextState.mode.rawValue,
            "timeOfDay": contextState.timeOfDay.rawValue,
            "isSundayChurchTime": contextState.isSundayChurchTime,
            "isNearChurch": contextState.isNearChurch,
            "isDriving": contextState.isDriving,
            "isTraveling": contextState.isTraveling,
            "lastUpdated": ISO8601DateFormatter().string(from: contextState.lastUpdated)
        ]

        do {
            _ = try await functions.httpsCallable("updateContextState").call(payload)
        } catch {
            // Background operation — surface nothing to the user.
            print("[ContextEngine] syncToServer silently failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func evaluateTimeContext() {
        contextState.timeOfDay = SOTimeOfDay.current()
        contextState.isSundayChurchTime = isSundayMorning()
        contextState.mode = resolvedMode(tod: contextState.timeOfDay)
        contextState.lastUpdated = Date()
    }

    private func startEvaluationTimer() {
        invalidateTimer()
        let timer = Timer.scheduledTimer(
            withTimeInterval: 60,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMode()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        evaluationTimer = timer
    }

    private func invalidateTimer() {
        evaluationTimer?.invalidate()
        evaluationTimer = nil
    }

    private func isSundayMorning() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)  // 1 = Sunday
        let hour = calendar.component(.hour, from: now)
        return weekday == 1 && hour >= 7 && hour < 14
    }

    private func resolvedMode(tod: SOTimeOfDay) -> SOContextMode {
        if contextState.isDriving {
            return .driveMode
        }
        if contextState.isSundayChurchTime && contextState.isNearChurch {
            return .worshipMode
        }
        if contextState.isTraveling {
            return .travelMode
        }
        if tod == .evening || tod == .night {
            return .eveningReflection
        }
        return .default
    }

    private func startLocationUpdatesIfPermitted() {
        guard let manager = locationManager,
              manager.authorizationStatus == .authorizedWhenInUse ||
              manager.authorizationStatus == .authorizedAlways else {
            return
        }
        manager.startUpdatingLocation()
    }

    private func stopLocationMonitoring() {
        locationManager?.stopUpdatingLocation()
        locationManager?.delegate = nil
        locationManager = nil
    }

    // MARK: - Server Cleanup

    private func cleanupContextOnLogout() async {
        do {
            _ = try await functions.httpsCallable("cleanupContextOnLogout").call(["userId": userId])
        } catch {
            print("[ContextEngine] cleanupContextOnLogout silently failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Location Delegate

    // Stored as a strong reference because CLLocationManager holds a weak delegate.
    private lazy var locationDelegate: ContextLocationDelegate = {
        ContextLocationDelegate(manager: self)
    }()
}

// MARK: - ContextLocationDelegate
// Private nested delegate class for CLLocationManager.
// Keeps SpiritualOSContextManager free of Objective-C protocol conformance noise.

private final class ContextLocationDelegate: NSObject, CLLocationManagerDelegate {

    private weak var contextManager: SpiritualOSContextManager?

    init(manager: SpiritualOSContextManager) {
        self.contextManager = manager
    }

    // MARK: Auth changes

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, let ctx = self.contextManager else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                ctx.contextState.userPermissions.locationEnabled = true
                if ctx.contextState.userPermissions.geofenceOptIn {
                    manager.startUpdatingLocation()
                }
            case .denied, .restricted:
                ctx.contextState.userPermissions.locationEnabled = false
                ctx.contextState.isNearChurch = false
                ctx.updateMode()
            default:
                break
            }
        }
    }

    // MARK: Location updates

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor [weak self] in
            guard let self, let ctx = self.contextManager else { return }
            guard ctx.contextState.userPermissions.geofenceOptIn else { return }

            // Driving heuristic: speed > 15 m/s (~54 km/h)
            let speed = location.speed
            if speed > 0 {
                ctx.contextState.isDriving = speed > 15.0
            }

            // Church proximity check (simplified: compare to test coordinate)
            // Real implementation: query churchEnhancementFunctions CF for nearby churches
            let testChurch = CLLocation(
                latitude: ctx.testChurchCoordinate.latitude,
                longitude: ctx.testChurchCoordinate.longitude
            )
            let distance = location.distance(from: testChurch)
            ctx.contextState.isNearChurch = distance <= ctx.churchProximityThresholdMeters

            ctx.updateMode()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location failure is non-fatal — context engine degrades gracefully.
        print("[ContextEngine] Location update failed: \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            self?.contextManager?.contextState.isNearChurch = false
            self?.contextManager?.updateMode()
        }
    }
}
