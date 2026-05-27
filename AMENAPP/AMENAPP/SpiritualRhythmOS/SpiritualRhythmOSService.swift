import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - SpiritualRhythmOSService

@MainActor
final class SpiritualRhythmOSService: ObservableObject {

    // MARK: Shared Instance

    static let shared = SpiritualRhythmOSService()

    // MARK: Published State

    @Published var settings: SpiritualRhythmSettings = .defaults
    @Published var streaks: [SpiritualStreak] = []
    @Published var isLoading = false
    @Published var error: Error?

    // MARK: Private Dependencies

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var settingsListener: ListenerRegistration?
    private var streaksListener: ListenerRegistration?

    // MARK: Helpers

    private var uid: String? { Auth.auth().currentUser?.uid }

    private var settingsRef: DocumentReference? {
        guard let uid else { return nil }
        return db.collection("users").document(uid)
            .collection("spiritualRhythm").document("main")
    }

    private var streaksCollection: CollectionReference? {
        guard let uid else { return nil }
        return db.collection("users").document(uid).collection("streaks")
    }

    // MARK: Init

    private init() {}

    // MARK: - 1. Start Listening

    /// Attaches real-time listeners for rhythm settings and all streak documents.
    func startListening() {
        guard let uid else { return }
        isLoading = true

        // Settings listener
        settingsListener = db.collection("users").document(uid)
            .collection("spiritualRhythm").document("main")
            .addSnapshotListener { [weak self] snapshot, listenerError in
                guard let self else { return }
                if let listenerError {
                    self.error = listenerError
                    self.isLoading = false
                    return
                }
                if let snapshot, snapshot.exists,
                   let decoded = try? snapshot.data(as: SpiritualRhythmSettings.self) {
                    self.settings = decoded
                }
                self.isLoading = false
            }

        // Streaks listener
        streaksListener = db.collection("users").document(uid)
            .collection("streaks")
            .addSnapshotListener { [weak self] snapshot, listenerError in
                guard let self else { return }
                if let listenerError {
                    self.error = listenerError
                    return
                }
                self.streaks = (snapshot?.documents ?? [])
                    .compactMap { try? $0.data(as: SpiritualStreak.self) }
            }
    }

    // MARK: - 2. Stop Listening

    /// Detaches both Firestore listeners.
    func stopListening() {
        settingsListener?.remove()
        settingsListener = nil
        streaksListener?.remove()
        streaksListener = nil
    }

    // MARK: - 3. Record Activity

    /// Calls the `recordSpiritualActivity` Cloud Function and updates local
    /// settings to reflect the new last-active time, clearing any inactivity pause.
    func recordActivity(_ type: SpiritualStreakType) async {
        guard let uid else { return }

        let isoTimestamp = ISO8601DateFormatter().string(from: Date())

        do {
            _ = try await functions.httpsCallable("recordSpiritualActivity").call([
                "activityType": type.rawValue,
                "uid": uid,
                "timestamp": isoTimestamp
            ])

            // Persist the updated last-active time and clear any inactivity pause locally.
            let now = Timestamp(date: Date())
            var merge: [String: Any] = [
                "lastActiveAt": now,
                "updatedAt": now
            ]
            if settings.isInactivityPauseActive {
                merge["inactivityPauseActivatedAt"] = FieldValue.delete()
                merge["pauseNotificationSentAt"] = FieldValue.delete()
            }
            try await settingsRef?.setData(merge, merge: true)
        } catch {
            self.error = error
        }
    }

    // MARK: - 4. Enable Sabbath Mode

    /// Persists the provided Sabbath mode settings (with `enabled = true`) to Firestore.
    func enableSabbathMode(_ sabbathSettings: SabbathModeSettings) async {
        guard settingsRef != nil else { return }

        var updated = sabbathSettings
        updated.enabled = true

        do {
            let encoded = try Firestore.Encoder().encode(updated)
            let merge: [String: Any] = [
                "sabbathMode": encoded,
                "updatedAt": Timestamp(date: Date())
            ]
            try await settingsRef?.setData(merge, merge: true)
        } catch {
            self.error = error
        }
    }

    // MARK: - 5. Disable Sabbath Mode

    /// Sets `sabbathMode.enabled` to `false` without touching other Sabbath fields.
    func disableSabbathMode() async {
        guard settingsRef != nil else { return }

        let merge: [String: Any] = [
            "sabbathMode.enabled": false,
            "updatedAt": Timestamp(date: Date())
        ]
        do {
            try await settingsRef?.setData(merge, merge: true)
        } catch {
            self.error = error
        }
    }

    // MARK: - 6. Update Notification Preferences

    /// Calls the `updateNotificationSettings` Cloud Function then merges
    /// the preferences into the local Firestore settings document.
    func updateNotificationPreferences(_ prefs: NotificationPreferences) async {
        guard let uid else { return }

        do {
            // Notify the backend so it can update push-token subscriptions, etc.
            let encoded = try Firestore.Encoder().encode(prefs)
            _ = try await functions.httpsCallable("updateNotificationSettings").call([
                "uid": uid,
                "preferences": encoded
            ])

            // Merge into the settings document.
            let merge: [String: Any] = [
                "notificationPreferences": encoded,
                "updatedAt": Timestamp(date: Date())
            ]
            try await settingsRef?.setData(merge, merge: true)
        } catch {
            self.error = error
        }
    }

    // MARK: - 7. Request Grace Recovery

    /// Asks the backend to evaluate whether the streak for `type` can be
    /// recovered within its grace window.
    func requestGraceRecovery(for type: SpiritualStreakType) async {
        guard let uid else { return }

        do {
            _ = try await functions.httpsCallable("calculateStreakState").call([
                "uid": uid,
                "streakType": type.rawValue,
                "graceRecovery": true
            ])
        } catch {
            self.error = error
        }
    }

    // MARK: - 8. Check Inactivity Status

    /// Should be called periodically (e.g. on app foreground) to detect users
    /// who have been inactive for 7+ days.
    ///
    /// Behaviour:
    /// - First detection: sends one pause notice and records both timestamps.
    /// - Subsequent checks: already paused, nothing more is sent.
    func checkInactivityStatus() async {
        guard let uid else { return }

        let inactive = settings.daysSinceLastActive >= 7

        guard inactive else { return }
        // Already fully handled on a previous launch.
        guard !settings.isInactivityPauseActive || settings.pauseNotificationSentAt == nil else { return }

        do {
            // Send the single pause notification if not yet done.
            if settings.pauseNotificationSentAt == nil {
                _ = try await functions.httpsCallable("pauseInactiveUserNotifications").call([
                    "uid": uid,
                    "daysSinceLastActive": settings.daysSinceLastActive
                ])
            }

            // Persist pause activation and notification-sent timestamps.
            let now = Timestamp(date: Date())
            var merge: [String: Any] = ["updatedAt": now]
            if settings.inactivityPauseActivatedAt == nil {
                merge["inactivityPauseActivatedAt"] = now
            }
            if settings.pauseNotificationSentAt == nil {
                merge["pauseNotificationSentAt"] = now
            }
            try await settingsRef?.setData(merge, merge: true)
        } catch {
            self.error = error
        }
    }

    // MARK: - 9. Handle User Return

    /// Call when the user opens the app after a period of absence.
    /// If an inactivity pause was active, this lifts it and restores normal delivery.
    func handleUserReturn() async {
        guard let uid else { return }

        do {
            if settings.isInactivityPauseActive {
                _ = try await functions.httpsCallable("restoreUserAfterInactivity").call([
                    "uid": uid
                ])
            }

            let now = Timestamp(date: Date())
            let merge: [String: Any] = [
                "inactivityPauseActivatedAt": FieldValue.delete(),
                "pauseNotificationSentAt": FieldValue.delete(),
                "lastActiveAt": now,
                "updatedAt": now
            ]
            try await settingsRef?.setData(merge, merge: true)
        } catch {
            self.error = error
        }
    }

    // MARK: - 10. Compute Momentum State

    /// Pure function — derives a `SpiritualMomentumState` from current streaks
    /// and inactivity data. Does not write to Firestore.
    func computeMomentumState() -> SpiritualMomentumState {
        let activeStreaks = streaks.filter { $0.isActive }.count
        let totalDays = streaks.map(\.totalDays).reduce(0, +)
        let daysSince = settings.daysSinceLastActive

        switch (activeStreaks, totalDays, daysSince) {
        case let (active, total, days) where active >= 3 && total > 30 && days < 7:
            return .grounded
        case let (active, _, days) where active >= 1 && days < 3:
            return .growing
        case let (_, _, days) where days >= 3 && days <= 7:
            return .reflecting
        default:
            // daysSinceLastActive > 7 or no qualifying active streaks
            return .resting
        }
    }

    // MARK: - 11. Update Enabled Streak Types

    /// Persists the set of streak types the user wants to track.
    func updateEnabledStreakTypes(_ types: Set<SpiritualStreakType>) async {
        guard settingsRef != nil else { return }

        do {
            // Encode the Set as a sorted array for Firestore compatibility.
            let rawValues = types.map(\.rawValue).sorted()
            let merge: [String: Any] = [
                "enabledStreakTypes": rawValues,
                "updatedAt": Timestamp(date: Date())
            ]
            try await settingsRef?.setData(merge, merge: true)
        } catch {
            self.error = error
        }
    }

    // MARK: - Deinit

    deinit {
        settingsListener?.remove()
        streaksListener?.remove()
    }
}
