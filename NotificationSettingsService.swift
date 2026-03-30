import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

final class NotificationSettingsService: ObservableObject {
    static let shared = NotificationSettingsService()
    private init() {}

    @Published var settings = NotificationSettings()
    private let db = Firestore.firestore()

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
