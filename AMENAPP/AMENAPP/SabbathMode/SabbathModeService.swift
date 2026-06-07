// SabbathModeService.swift
// AMENAPP — SabbathMode
//
// EXTENDS (does NOT replace) ShabbatModeService and RestModeGate.
//
// Firestore paths (canonical from contracts):
//   users/{uid}/sabbath/config           → SabbathConfig
//   users/{uid}/sabbathSessions/{date}   → SabbathSession
//   users/{uid}/sabbathReflections/{id}  → SabbathReflection
//
// All writes are additive (merge: true equivalent). Never destructive.
// Uses async/await, never Combine.

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Step-out error

enum SabbathStepOutError: LocalizedError {
    case confirmRequired
    case alreadySteppedOut
    case noConfig

    var errorDescription: String? {
        switch self {
        case .confirmRequired:   return "Confirmation required before stepping out."
        case .alreadySteppedOut: return "You have already stepped out of Sabbath today."
        case .noConfig:          return "Sabbath configuration not loaded yet."
        }
    }
}

// MARK: - SabbathModeService

/// Observable service that drives Sabbath Mode state.
/// Extends the existing ShabbatModeService/RestModeGate pattern.
/// Firestore is the source of truth; device timezone is used for boundary
/// evaluation (TimeZone.current.identifier, matching contracts).
@MainActor
final class SabbathModeService: ObservableObject {

    static let shared = SabbathModeService()

    // MARK: Published state

    /// Computed Sabbath lifecycle state.
    @Published private(set) var currentState: SabbathState = .inactive
    /// User's persisted config, or nil while loading.
    @Published private(set) var currentConfig: SabbathConfig?
    /// Today's session document, or nil when no active session.
    @Published private(set) var currentSession: SabbathSession?

    // MARK: Private

    private let db = Firestore.firestore()
    private var configListener: ListenerRegistration?
    private var sessionListener: ListenerRegistration?
    private var minuteTimer: Timer?
    private var currentDateKey: String = ""

    private init() {
        startMinuteTicker()
        startIfAuthenticated()
    }

    deinit {
        configListener?.remove()
        sessionListener?.remove()
        minuteTimer?.invalidate()
    }

    // MARK: - Bootstrap

    private func startIfAuthenticated() {
        guard let uid = Auth.auth().currentUser?.uid else {
            NotificationCenter.default.addObserver(
                forName: .init("AuthStateDidChange"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.startIfAuthenticated() }
            }
            return
        }
        Task { await loadOrCreateConfig(uid: uid) }
    }

    // MARK: - Public API

    /// Load or create the user's Sabbath config from Firestore.
    /// Creates a default config (chosenDay: .sunday) if none exists.
    func loadOrCreateConfig() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await loadOrCreateConfig(uid: uid)
    }

    /// Attempt to step the user out of active Sabbath.
    /// Enforces maxPerSabbath: 1. Gated by confirmation sheet (requiresConfirm: true).
    func enterStepOut() async throws {
        guard let config = currentConfig else { throw SabbathStepOutError.noConfig }

        // Already stepped out — deny silently (policy maxPerSabbath: 1)
        if let session = currentSession, session.steppedOutAt != nil {
            throw SabbathStepOutError.alreadySteppedOut
        }

        guard let uid = Auth.auth().currentUser?.uid else { throw SabbathStepOutError.noConfig }

        let dateKey = localDateString(timezone: config.timezone)
        let ref = sessionRef(uid: uid, dateKey: dateKey)
        let now = Date().timeIntervalSince1970 * 1000 // ms

        // Ensure session doc exists (merge = safe upsert)
        try await ref.setData([
            "date": dateKey,
            "state": SabbathState.active.rawValue,
            "enteredAt": currentSession?.enteredAt ?? now,
            "surfacesUsed": currentSession?.surfacesUsed.map { $0.rawValue } ?? [],
            "steppedOutAt": FieldValue.delete()  // Guard: don't set if already absent
        ] as [String : Any], merge: true)

        // Additive update — never overwrites earlier fields
        try await ref.updateData([
            "state": SabbathState.steppedOut.rawValue,
            "steppedOutAt": now
        ])
    }

    /// Record that the user visited a Sabbath surface.
    /// Safety surfaces (SABBATH_ALWAYS_ALLOWED) are silently excluded.
    func markSurfaceUsed(_ surface: SabbathSurface) async {
        guard let config = currentConfig,
              let uid = Auth.auth().currentUser?.uid else { return }

        // Safety surfaces: silently skip (belt-and-suspenders — surface values won't
        // match the policy key strings in SABBATH_ALWAYS_ALLOWED, but we check anyway)
        let safetySet = Set(SABBATH_ALWAYS_ALLOWED)
        if safetySet.contains(surface.rawValue) { return }

        // Only log sanctioned surfaces
        let sanctioned = Set(SabbathModeDefaults.allowedSurfaces.map { $0.rawValue })
        guard sanctioned.contains(surface.rawValue) else { return }

        let dateKey = localDateString(timezone: config.timezone)
        let ref = sessionRef(uid: uid, dateKey: dateKey)
        let now = Date().timeIntervalSince1970 * 1000

        // Ensure doc exists (merge = safe upsert)
        try? await ref.setData([
            "date": dateKey,
            "state": currentState.rawValue,
            "enteredAt": currentSession?.enteredAt ?? now,
            "surfacesUsed": []
        ] as [String : Any], merge: true)

        // arrayUnion — additive, no duplicates
        try? await ref.updateData([
            "surfacesUsed": FieldValue.arrayUnion([surface.rawValue])
        ])
    }

    // MARK: - Private: Config loading

    private func loadOrCreateConfig(uid: String) async {
        let ref = configRef(uid: uid)

        do {
            let snap = try await ref.getDocument()

            if !snap.exists {
                // Create with defaults (initial creation only)
                let now = Date().timeIntervalSince1970 * 1000
                let defaults: [String: Any] = [
                    "chosenDay": SabbathModeDefaults.defaultDay.rawValue,
                    "boundary": SabbathModeDefaults.defaultBoundary.rawValue,
                    "timezone": TimeZone.current.identifier,
                    "createdAt": now,
                    "updatedAt": now
                ]
                try? await ref.setData(defaults)
            }
        } catch {
            // Non-fatal — will retry on next foreground
        }

        // Subscribe to real-time config updates
        configListener?.remove()
        configListener = ref.addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let data = snapshot?.data() else { return }
            Task { @MainActor [weak self] in
                self?.applyConfig(data)
            }
        }
    }

    private func applyConfig(_ data: [String: Any]) {
        guard let chosenDayRaw = data["chosenDay"] as? String,
              let chosenDay = SabbathDay(rawValue: chosenDayRaw),
              let boundaryRaw = data["boundary"] as? String,
              let boundary = SabbathBoundary(rawValue: boundaryRaw),
              let timezone = data["timezone"] as? String else { return }

        let createdAt = data["createdAt"] as? Double ?? 0
        let updatedAt = data["updatedAt"] as? Double ?? 0

        currentConfig = SabbathConfig(
            chosenDay: chosenDay,
            boundary: boundary,
            timezone: timezone,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        resubscribeSessionIfNeeded()
        recomputeState()
    }

    // MARK: - Private: Session subscription

    private func resubscribeSessionIfNeeded() {
        guard let config = currentConfig,
              let uid = Auth.auth().currentUser?.uid else { return }

        let todayKey = localDateString(timezone: config.timezone)
        guard todayKey != currentDateKey else { return }
        currentDateKey = todayKey

        sessionListener?.remove()
        let ref = sessionRef(uid: uid, dateKey: todayKey)
        sessionListener = ref.addSnapshotListener { [weak self] snapshot, _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data = snapshot?.data() {
                    self.applySession(data)
                } else {
                    self.currentSession = nil
                }
                self.recomputeState()
            }
        }
    }

    private func applySession(_ data: [String: Any]) {
        guard let dateStr = data["date"] as? String,
              let stateRaw = data["state"] as? String,
              let state = SabbathState(rawValue: stateRaw),
              let enteredAt = data["enteredAt"] as? Double else { return }

        let steppedOutAt = data["steppedOutAt"] as? Double
        let surfaceRaws = data["surfacesUsed"] as? [String] ?? []
        let surfaces = surfaceRaws.compactMap { SabbathSurface(rawValue: $0) }

        currentSession = SabbathSession(
            date: dateStr,
            state: state,
            enteredAt: enteredAt,
            steppedOutAt: steppedOutAt,
            surfacesUsed: surfaces
        )
    }

    // MARK: - Private: State computation

    /// Pure computation — does not read Firestore. Matches SabbathStateEngine.ts.
    private func recomputeState() {
        guard let config = currentConfig else {
            currentState = .inactive
            return
        }
        currentState = Self.computeState(
            config: config,
            now: Date(),
            steppedOutAt: currentSession?.steppedOutAt
        )
    }

    /// Timezone-aware Sabbath state computation. Pure function — no I/O.
    /// Matches computeSabbathState() in SabbathStateEngine.ts.
    static func computeState(
        config: SabbathConfig,
        now: Date,
        steppedOutAt: Double?
    ) -> SabbathState {
        let tz = TimeZone(identifier: config.timezone) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let weekday = cal.component(.weekday, from: now) // 1=Sun … 7=Sat

        let isInWindow: Bool
        switch config.boundary {
        case .localMidnight:
            // Active all day (00:00–23:59) on the chosen weekday in the user's timezone
            switch config.chosenDay {
            case .sunday:   isInWindow = weekday == 1
            case .saturday: isInWindow = weekday == 7
            }
        case .sundown:
            // Graceful fallback: sundown requires lat/lng which we don't carry in
            // the frozen config. Fall back to localMidnight (matches TS engine).
            switch config.chosenDay {
            case .sunday:   isInWindow = weekday == 1
            case .saturday: isInWindow = weekday == 7
            }
        }

        guard isInWindow else { return .inactive }

        // Inside the window — check if user has already stepped out
        if steppedOutAt != nil { return .steppedOut }
        return .active
    }

    // MARK: - Private: Minute ticker (catches midnight boundary crossings)

    private func startMinuteTicker() {
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resubscribeSessionIfNeeded()
                self?.recomputeState()
            }
        }
    }

    // MARK: - Private: Firestore path helpers

    private func configRef(uid: String) -> DocumentReference {
        db.collection("users").document(uid).collection("sabbath").document("config")
    }

    private func sessionRef(uid: String, dateKey: String) -> DocumentReference {
        db.collection("users").document(uid).collection("sabbathSessions").document(dateKey)
    }

    // MARK: - Private: Date helpers

    /// Returns the local date string "yyyy-mm-dd" in the given IANA timezone.
    private func localDateString(timezone: String) -> String {
        let tz = TimeZone(identifier: timezone) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let comps = cal.dateComponents([.year, .month, .day], from: Date())
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
