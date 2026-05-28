// MARK: - Notification Service Ownership
// This service owns: Reading and writing user notification settings from/to
//                    users/{uid}/settings/notifications in Firestore; providing a preference(for:)
//                    lookup used by other services (e.g. PrayerAnsweredNotificationService) to gate
//                    delivery; writing default NotificationSettings on first access;
//                    the settings keys: prayerIntercessors, prayerAnswered, prayerMilestone,
//                    prayerInsights, testimonyStrength, testimonyRipple, testimonyNeededThis,
//                    scriptureConfirmed, weeklyDigest.
// It does NOT own: Delivery of any notification type, priority scoring, batching, re-engagement copy,
//                  action-thread events, quiet-hours enforcement, or spiritual-rhythm gating.
// Canonical routing reference: See NotificationServiceMap.md

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class NotificationSettingsService: ObservableObject {
    static let shared = NotificationSettingsService()
    private init() {}

    @Published var settings = NotificationSettings()
    private lazy var db = Firestore.firestore()

    func fetchSettings() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let doc = try? await db
            .collection("users").document(uid)
            .collection("settings").document("notifications")
            .getDocument()
        if let data = doc?.data(), let decoded = try? Firestore.Decoder().decode(NotificationSettings.self, from: data) {
            await MainActor.run { settings = decoded }
        } else {
            // Write defaults
            await writeDefaults(uid: uid)
        }
    }

    func updateSetting(_ key: String, value: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db
            .collection("users").document(uid)
            .collection("settings").document("notifications")
            .setData([key: value], merge: true)
    }

    func preference(for key: String) async -> Bool {
        if !settings.asDict.keys.contains(key) { await fetchSettings() }
        return settings.asDict[key] ?? true
    }

    private func writeDefaults(uid: String) async {
        let defaults = NotificationSettings()
        let data = (try? Firestore.Encoder().encode(defaults)) ?? [:]
        try? await db
            .collection("users").document(uid)
            .collection("settings").document("notifications")
            .setData(data)
        await MainActor.run { settings = defaults }
    }
}

extension NotificationSettings {
    var asDict: [String: Bool] {
        [
            "prayerIntercessors":  prayerIntercessors,
            "prayerAnswered":      prayerAnswered,
            "prayerMilestone":     prayerMilestone,
            "prayerInsights":      prayerInsights,
            "testimonyStrength":   testimonyStrength,
            "testimonyRipple":     testimonyRipple,
            "testimonyNeededThis": testimonyNeededThis,
            "scriptureConfirmed":  scriptureConfirmed,
            "weeklyDigest":        weeklyDigest
        ]
    }
}
