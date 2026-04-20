// ChurchProximityEngine.swift
// AMENAPP
//
// Signal-fusion engine that determines how confident the system is that a user
// is actively attending a church service, and drives Quiet Mode accordingly.
//
// Signals fused:
//   Geofence      (CLCircularRegion)         — max 30 pts
//   Time window   (service start/end)         — max 25 pts
//   Calendar      (EKEventStore correlation)  — max 15 pts
//   Motion        (CMMotionActivityManager)   — max 15 pts
//   Prior pattern (historical attendance)     — max 10 pts
//   Route         (navigation confirmation)   — max  5 pts
//                                               ————————
//                                         max = 100 pts
//
// Auto-enable threshold:  85
// Suggest threshold:      60
//
// Attendance states:
//   notAtChurch → possibleArrival → likelyInService → confirmedServiceWindow
//   confirmedServiceWindow → exitingChurch (on geofence exit)

import Foundation
import CoreLocation
import CoreMotion
import EventKit

// MARK: - Attendance State

enum ChurchAttendanceState: String, Equatable, Sendable {
    case notAtChurch
    case possibleArrival
    case likelyInService
    case confirmedServiceWindow
    case exitingChurch

    var displayName: String {
        switch self {
        case .notAtChurch:           return "Not at church"
        case .possibleArrival:       return "Possibly arriving"
        case .likelyInService:       return "Likely in service"
        case .confirmedServiceWindow: return "In service"
        case .exitingChurch:         return "Leaving church"
        }
    }

    var isAttending: Bool {
        self == .likelyInService || self == .confirmedServiceWindow
    }
}

// MARK: - Signal Contributions

struct ChurchProximitySignals: Equatable, Sendable {
    var geofenceScore: Double     = 0  // 0–30
    var timeWindowScore: Double   = 0  // 0–25
    var calendarScore: Double     = 0  // 0–15
    var motionScore: Double       = 0  // 0–15
    var priorPatternScore: Double = 0  // 0–10
    var routeScore: Double        = 0  // 0–5

    var total: Double {
        geofenceScore + timeWindowScore + calendarScore + motionScore + priorPatternScore + routeScore
    }

    var debugDescription: String {
        String(format: "geo=%.0f time=%.0f cal=%.0f motion=%.0f pattern=%.0f route=%.0f → total=%.0f",
               geofenceScore, timeWindowScore, calendarScore,
               motionScore, priorPatternScore, routeScore, total)
    }
}

// MARK: - Church Service Window

/// Describes one service slot at a specific church, including location, schedule, and weekday.
struct ChurchServiceWindow: Equatable, Sendable {
    let churchId: String
    let churchName: String
    let coordinate: CLLocationCoordinate2D
    /// Geofence radius — default 120 m, tunable per church.
    let radiusMeters: Double
    let serviceStart: Date
    let serviceEnd: Date
    /// 1 = Sunday in Foundation Calendar (Gregorian).
    let weekday: Int

    static func == (lhs: ChurchServiceWindow, rhs: ChurchServiceWindow) -> Bool {
        lhs.churchId == rhs.churchId &&
        lhs.serviceStart == rhs.serviceStart
    }
}

extension CLLocationCoordinate2D: @unchecked Sendable {}

// MARK: - Engine

@MainActor
final class ChurchProximityEngine: NSObject, ObservableObject {

    static let shared = ChurchProximityEngine()

    // Confidence thresholds
    static let autoEnableThreshold: Double = 85
    static let suggestThreshold: Double    = 60

    // MARK: Published State

    @Published private(set) var attendanceState: ChurchAttendanceState = .notAtChurch
    @Published private(set) var confidenceScore: Double = 0
    @Published private(set) var signals = ChurchProximitySignals()
    @Published private(set) var isMonitoring = false
    @Published private(set) var quietModeActive = false

    // MARK: Callbacks (set by Get Ready coordinator)

    /// Called when Auto mode silently enables Church Focus.
    var onQuietModeAutoEnable: (() -> Void)?
    /// Called when Ask mode prompts the user. Parameter = church name.
    var onQuietModeSuggest: ((String) -> Void)?
    /// Called when quiet mode is automatically ended.
    var onQuietModeDisable: (() -> Void)?

    // MARK: Private State

    private var locationManager: CLLocationManager?
    private let motionActivityManager = CMMotionActivityManager()
    private let eventStore = EKEventStore()

    private var activeWindow: ChurchServiceWindow?
    private var priorAttendanceCount: Int = 0

    private var isInsideGeofence = false
    private var wasAutomotiveBeforeArrival = false
    private var lastMotionActivity: CMMotionActivity?
    private var calendarEventMatched = false

    private var signalTimer: Timer?
    private var serviceEndTimer: Timer?

    // Prevent re-suggesting quiet mode on the same session
    private var hasAlreadySuggested = false

    private override init() { super.init() }

    // MARK: - Start / Stop Monitoring

    func startMonitoring(
        for serviceWindow: ChurchServiceWindow,
        priorAttendanceCount: Int = 0
    ) {
        stopMonitoring()

        activeWindow = serviceWindow
        self.priorAttendanceCount = priorAttendanceCount
        isInsideGeofence = false
        wasAutomotiveBeforeArrival = false
        calendarEventMatched = false
        hasAlreadySuggested = false
        isMonitoring = true

        setupLocationManager()
        startMotionUpdates()
        Task { await checkCalendarCorrelation(window: serviceWindow) }
        startSignalFusionTimer()
        scheduleServiceEndDisable(window: serviceWindow)
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        if let window = activeWindow {
            let region = CLCircularRegion(
                center: window.coordinate,
                radius: window.radiusMeters,
                identifier: window.churchId
            )
            locationManager?.stopMonitoring(for: region)
        }
        locationManager?.stopUpdatingLocation()
        locationManager?.delegate = nil

        motionActivityManager.stopActivityUpdates()
        signalTimer?.invalidate()
        signalTimer = nil
        serviceEndTimer?.invalidate()
        serviceEndTimer = nil

        activeWindow = nil
        signals = ChurchProximitySignals()
        confidenceScore = 0
        attendanceState = .notAtChurch
    }

    // MARK: - Route Completion

    /// Call this when Maps confirms the user has reached the church.
    /// Adds the route completion bonus to confidence.
    func notifyRouteCompleted() {
        var s = signals
        s.routeScore = 5
        signals = s
        recomputeSignals()
    }

    // MARK: - Manual Override

    func forceEnableQuietMode() {
        enableQuietMode()
    }

    func forceDisableQuietMode() {
        disableQuietMode()
    }

    // MARK: - Location Setup

    private func setupLocationManager() {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .other
        locationManager = manager

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            manager.startUpdatingLocation()
            if let window = activeWindow { registerGeofence(window) }
        default:
            break
        }
    }

    private func registerGeofence(_ window: ChurchServiceWindow) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let region = CLCircularRegion(
            center: window.coordinate,
            radius: window.radiusMeters,
            identifier: window.churchId
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager?.startMonitoring(for: region)
        // Request immediate state for the case the user is already inside.
        locationManager?.requestState(for: region)
    }

    // MARK: - Motion

    private func startMotionUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motionActivityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            Task { @MainActor [weak self] in
                self?.handleMotionActivity(activity)
            }
        }
    }

    private func handleMotionActivity(_ activity: CMMotionActivity) {
        if activity.automotive && !activity.stationary {
            wasAutomotiveBeforeArrival = true
        }
        lastMotionActivity = activity
        recomputeSignals()
    }

    // MARK: - Calendar Correlation

    private func checkCalendarCorrelation(window: ChurchServiceWindow) async {
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
        } else {
            granted = await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { ok, _ in
                    continuation.resume(returning: ok)
                }
            }
        }
        guard granted else { return }

        let bufferStart = window.serviceStart.addingTimeInterval(-30 * 60)
        let bufferEnd   = window.serviceEnd.addingTimeInterval(30 * 60)
        let predicate = eventStore.predicateForEvents(withStart: bufferStart, end: bufferEnd, calendars: nil)
        let events = eventStore.events(matching: predicate)

        let churchNameLower = window.churchName.lowercased()
        calendarEventMatched = events.contains { event in
            let title = (event.title ?? "").lowercased()
            return title.contains("church")
                || title.contains("service")
                || title.contains("worship")
                || title.contains(churchNameLower)
        }

        recomputeSignals()
    }

    // MARK: - Signal Fusion

    private func startSignalFusionTimer() {
        // Re-evaluate every 30 seconds to catch time-window changes.
        signalTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recomputeSignals() }
        }
        recomputeSignals()
    }

    private func recomputeSignals() {
        guard let window = activeWindow else { return }

        var s = signals // carry forward routeScore from prior call

        // ── 1. Geofence (max 30) ─────────────────────────────────────────
        s.geofenceScore = isInsideGeofence ? 30 : 0

        // ── 2. Time window (max 25) ──────────────────────────────────────
        let now = Date()
        let calendar = Calendar.current
        let todayWeekday = calendar.component(.weekday, from: now)
        let preBuffer  = window.serviceStart.addingTimeInterval(-15 * 60)
        let postBuffer = window.serviceEnd.addingTimeInterval(15 * 60)

        if todayWeekday == window.weekday {
            if now >= window.serviceStart && now <= window.serviceEnd {
                s.timeWindowScore = 25       // inside service
            } else if now >= preBuffer && now <= window.serviceStart {
                s.timeWindowScore = 12       // arrival window
            } else if now > window.serviceEnd && now <= postBuffer {
                s.timeWindowScore = 8        // post-service tail
            } else {
                s.timeWindowScore = 0
            }
        } else {
            s.timeWindowScore = 0
        }

        // ── 3. Calendar (max 15) ─────────────────────────────────────────
        s.calendarScore = calendarEventMatched ? 15 : 0

        // ── 4. Motion (max 15) ───────────────────────────────────────────
        if let motion = lastMotionActivity {
            if isInsideGeofence && wasAutomotiveBeforeArrival && motion.stationary {
                // Classic pattern: drove to church, parked, now stationary inside fence.
                s.motionScore = 15
            } else if isInsideGeofence && motion.walking {
                // Walking inside the geofence (heading to sanctuary).
                s.motionScore = 10
            } else if isInsideGeofence && motion.stationary {
                s.motionScore = 8
            } else {
                s.motionScore = 0
            }
        } else {
            s.motionScore = 0
        }

        // ── 5. Prior pattern (max 10) ────────────────────────────────────
        // Each prior confirmed attendance adds 2.5 pts, capped at 10.
        s.priorPatternScore = min(Double(priorAttendanceCount) * 2.5, 10)

        // routeScore is set externally via notifyRouteCompleted()

        signals = s
        confidenceScore = s.total
        updateAttendanceState()
        evaluateQuietMode()
    }

    private func updateAttendanceState() {
        let score = confidenceScore
        let newState: ChurchAttendanceState

        switch score {
        case 85...:
            newState = .confirmedServiceWindow

        case 60..<85:
            newState = .likelyInService

        case 35..<60 where isInsideGeofence:
            newState = .possibleArrival

        default:
            // If we were attending and dropped out of geofence, mark exiting.
            if attendanceState.isAttending && !isInsideGeofence {
                newState = .exitingChurch
            } else if attendanceState == .exitingChurch {
                // Stay in exitingChurch until we either re-enter or timer fires.
                newState = .exitingChurch
            } else {
                newState = .notAtChurch
            }
        }

        attendanceState = newState
    }

    // MARK: - Quiet Mode Evaluation

    private func evaluateQuietMode() {
        let preference = QuietModePreferenceService.shared.preference
        guard preference != .off else { return }

        // Enable path
        if !quietModeActive {
            if preference == .auto && confidenceScore >= Self.autoEnableThreshold {
                enableQuietMode()
            } else if preference == .ask && confidenceScore >= Self.suggestThreshold && !hasAlreadySuggested {
                hasAlreadySuggested = true
                onQuietModeSuggest?(activeWindow?.churchName ?? "your church")
            }
        }

        // Disable path — exit geofence or confidence collapses below 30
        if quietModeActive && (!isInsideGeofence || confidenceScore < 30) {
            disableQuietMode()
        }
    }

    private func enableQuietMode() {
        guard !quietModeActive else { return }
        quietModeActive = true
        onQuietModeAutoEnable?()
    }

    private func disableQuietMode() {
        guard quietModeActive else { return }
        quietModeActive = false
        onQuietModeDisable?()
    }

    // MARK: - Service End Auto-Disable

    private func scheduleServiceEndDisable(window: ChurchServiceWindow) {
        // Fire 15 min after service end to allow for post-service fellowship time.
        let fireAfter = window.serviceEnd.addingTimeInterval(15 * 60).timeIntervalSinceNow
        guard fireAfter > 0 else { return }
        serviceEndTimer = Timer.scheduledTimer(withTimeInterval: fireAfter, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.disableQuietMode()
                self?.stopMonitoring()
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension ChurchProximityEngine: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.startUpdatingLocation()
                if let window = self.activeWindow {
                    self.registerGeofence(window)
                }
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor [weak self] in
            guard let self, region.identifier == self.activeWindow?.churchId else { return }
            self.isInsideGeofence = true
            self.recomputeSignals()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor [weak self] in
            guard let self, region.identifier == self.activeWindow?.churchId else { return }
            self.isInsideGeofence = false
            self.recomputeSignals()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        Task { @MainActor [weak self] in
            guard let self, region.identifier == self.activeWindow?.churchId else { return }
            self.isInsideGeofence = (state == .inside)
            self.recomputeSignals()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // Geofence monitoring degraded — continue with remaining signals.
        // No crash path; score simply lacks geofence contribution.
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Graceful degradation — engine continues with available signals.
    }
}
