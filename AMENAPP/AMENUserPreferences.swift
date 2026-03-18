//
//  AMENUserPreferences.swift
//  AMENAPP
//
//  Single source of truth for all user-controlled iOS integration preferences.
//  Stored in Firestore under users/{uid}/preferences/integrations.
//
//  Changes are applied optimistically (local first) then synced async.
//  The UI never blocks on a Firestore write.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Preferences Model

struct AMENUserPreferences: Codable, Equatable {

    // MARK: Push Notifications
    var notificationsEnabled: Bool = true
    var prayerRequestAlerts: Bool = true
    var testimonyAlerts: Bool = true
    var eventReminders: Bool = true
    var morningDevotionalEnabled: Bool = false
    var morningDevotionalHour: Int = 8      // stored as hour (0-23) for Codable simplicity
    var morningDevotionalMinute: Int = 0
    var followActivityAlerts: Bool = true
    var firstAmenAlert: Bool = true         // notified when prayer gets its first Amen
    var geofenceReminders: Bool = false
    var maxDailyNotifications: Int = 2      // default: 2, user range: 0-10

    // MARK: Widgets
    var widgetsEnabled: Bool = true
    var dailyVerseWidgetEnabled: Bool = true
    var communityPulseWidgetEnabled: Bool = true
    var upcomingEventWidgetEnabled: Bool = true

    // MARK: Dynamic Island / Live Activities
    var liveActivitiesEnabled: Bool = true
    var prayerChainLiveActivityEnabled: Bool = true
    var liveEventActivityEnabled: Bool = true

    // MARK: Siri & Shortcuts
    var siriIntegrationEnabled: Bool = true
    var siriSuggestionsEnabled: Bool = true
    var siriTipsEnabled: Bool = true        // controls SiriTipView appearances in-app

    static let `default` = AMENUserPreferences()
}

// MARK: - Preferences Service

/// @MainActor singleton that owns AMENUserPreferences state.
/// • Listens to Firestore for real-time cross-device sync.
/// • Optimistically applies local changes; debounces Firestore writes by 500 ms.
/// • Never blocks the UI.
@MainActor
final class AMENUserPreferencesService: ObservableObject {

    static let shared = AMENUserPreferencesService()

    @Published private(set) var preferences: AMENUserPreferences = .default
    @Published private(set) var isLoaded = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var saveDebounceTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = db
            .collection("users").document(uid)
            .collection("preferences").document("integrations")
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let data = snapshot?.data(),
                       let decoded = try? Firestore.Decoder().decode(AMENUserPreferences.self, from: data) {
                        self.preferences = decoded
                    } else {
                        // No document yet — use defaults and write them
                        self.preferences = .default
                    }
                    self.isLoaded = true
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        isLoaded = false
        preferences = .default
    }

    // MARK: - Update (optimistic + debounced sync)

    /// Apply a mutation immediately and schedule a debounced Firestore write.
    func update(_ transform: (inout AMENUserPreferences) -> Void) {
        transform(&preferences)
        scheduleSave()
    }

    private func scheduleSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s debounce
            guard !Task.isCancelled else { return }
            await self?.persistToFirestore()
        }
    }

    private func persistToFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let encoded = try Firestore.Encoder().encode(preferences)
            try await db
                .collection("users").document(uid)
                .collection("preferences").document("integrations")
                .setData(encoded, merge: true)
            dlog("✅ AMENUserPreferences saved to Firestore")
        } catch {
            dlog("❌ AMENUserPreferences save failed: \(error)")
        }
    }

    // MARK: - Reset

    func resetToDefaults() {
        preferences = .default
        scheduleSave()
        dlog("🔄 AMENUserPreferences reset to defaults")
    }
}
