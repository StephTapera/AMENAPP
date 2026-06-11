import Foundation
import SwiftUI
import FirebaseFunctions

// MARK: - SpiritualOSContextManager
// @MainActor ObservableObject that owns the Spiritual OS context lifecycle.
// Context source of truth: server-assembled Ambient/ContextStore projection.
// This manager does not start location, motion, or background sensing pipelines.

@MainActor
final class SpiritualOSContextManager: ObservableObject {

    // MARK: Published state

    @Published var contextState: AmenContextState = AmenContextState()
    @Published var isActive: Bool = false

    // MARK: Private state

    private let userId: String
    private var evaluationTimer: Timer?
    private let functions = Functions.functions()

    // MARK: Feature flags

    @AppStorage("spiritualOS_enabled") private var masterEnabled: Bool = false
    @AppStorage("spiritualOS_context_engine_enabled") private var isEnabled: Bool = false

    private var featureEnabled: Bool {
        masterEnabled && isEnabled
    }

    // MARK: Init

    init(userId: String) {
        self.userId = userId
        contextState.timeOfDay = SOTimeOfDay.current()
        if featureEnabled {
            activate()
        }
    }

    // MARK: - Lifecycle

    /// Activates context mapping. It consumes the Ambient OS callable and keeps a local timer
    /// only for time-of-day labels; it never starts device sensing.
    func activate() {
        guard featureEnabled else {
            deactivate()
            return
        }
        guard !isActive else { return }
        isActive = true
        evaluateTimeContext()
        startEvaluationTimer()
        Task { await refreshFromAmbientContext() }
    }

    /// Stops local refresh timers. No sensor teardown is needed because this manager owns none.
    func deactivate() {
        isActive = false
        invalidateTimer()
    }

    /// Full logout cleanup. Server cleanup is best-effort and feature-gated.
    func onLogout() async {
        deactivate()
        if featureEnabled {
            await cleanupContextOnLogout()
        }
        contextState = AmenContextState()
    }

    // MARK: - User Consent

    /// Records the user's opt-in intent and refreshes the approved server projection.
    /// Device permission prompts belong to ContextStore/Ambient OS, not this consumer.
    func requestGeofenceOptIn() {
        contextState.userPermissions.geofenceOptIn = true
        Task { await refreshFromAmbientContext() }
    }

    // MARK: - Mode Evaluation

    /// Re-evaluates local time context and refreshes explicit server context.
    func updateMode() {
        guard featureEnabled else {
            deactivate()
            return
        }
        evaluateTimeContext()
        Task { await refreshFromAmbientContext() }
    }

    // MARK: - Ambient Context

    /// Pulls the single approved context projection. Ambient OS callables aggregate any
    /// ContextStore inputs server-side, so Spiritual OS does not read raw facets or sensors.
    func refreshFromAmbientContext() async {
        guard featureEnabled, !userId.isEmpty else { return }

        do {
            let payload: [String: Any] = [
                "userId": userId,
                "mode": contextState.mode.rawValue
            ]
            let result = try await functions.httpsCallable("getAmbientContext").call(payload)
            guard let data = result.data as? [String: Any] else { return }
            applyAmbientContextPayload(data)
            await syncToServer()
        } catch {
            print("[ContextEngine] refreshFromAmbientContext failed closed: \(error.localizedDescription)")
        }
    }

    private func applyAmbientContextPayload(_ data: [String: Any]) {
        if let mode = data["mode"] as? String {
            applyAmbientMode(mode)
        } else if let context = data["context"] as? [String: Any],
                  let mode = context["mode"] as? String {
            applyAmbientMode(mode)
        }

        contextState.timeOfDay = SOTimeOfDay.current()
        contextState.lastUpdated = Date()
        postLegacyModeNotification()
    }

    private func applyAmbientMode(_ mode: String) {
        switch mode {
        case AmbientMode.driving.rawValue:
            contextState.mode = .driveMode
            contextState.isDriving = true
            contextState.isNearChurch = false
            contextState.isTraveling = false
        case AmbientMode.atChurch.rawValue:
            contextState.mode = .worshipMode
            contextState.isDriving = false
            contextState.isNearChurch = true
            contextState.isTraveling = false
        default:
            contextState.mode = resolvedMode(tod: SOTimeOfDay.current())
            contextState.isDriving = false
            contextState.isNearChurch = false
            contextState.isTraveling = false
        }
    }

    private func postLegacyModeNotification() {
        let legacyMode: AmenContextMode
        switch contextState.mode {
        case .driveMode:
            legacyMode = .driving
        case .worshipMode:
            legacyMode = .church
        case .travelMode:
            legacyMode = .travel
        default:
            legacyMode = .standard
        }
        NotificationCenter.default.post(name: .amenContextModeChanged, object: legacyMode)
    }

    // MARK: - Server Sync

    /// Syncs derived, non-sensitive mode state. Failures remain silent in the UI.
    func syncToServer() async {
        guard featureEnabled, !userId.isEmpty else { return }

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
        let timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
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
        let weekday = calendar.component(.weekday, from: now)
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

    private func cleanupContextOnLogout() async {
        do {
            _ = try await functions.httpsCallable("cleanupContextOnLogout").call(["userId": userId])
        } catch {
            print("[ContextEngine] cleanupContextOnLogout silently failed: \(error.localizedDescription)")
        }
    }
}
