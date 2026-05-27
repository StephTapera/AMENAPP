import Foundation
import FirebaseAnalytics
import FirebaseAuth
import FirebaseFirestore

struct SpiritualRhythmPreferences: Codable, Equatable {
    var enabled: Bool = true
    var morningDevotionalEnabled: Bool = true
    var morningHour: Int = 8
    var morningMinute: Int = 0
    var masterPushEnabled: Bool = true
    var quietHoursEnabled: Bool = true
    var quietHoursStart: String = "22:00"
    var quietHoursEnd: String = "08:00"
    var sundayRestEnabled: Bool = true
    var preferCalmFeed: Bool = true
    var reduceOutrage: Bool = true
    var reduceRapidCuts: Bool = true
    var spiritualPromptsEnabled: Bool = true
    var promptCooldownMinutes: Int = 30
    var maxDailyNotifications: Int = 2
    var aiSummaryEnabled: Bool = false
    var aiSummaryFrequency: String = "smart"
    var updatedAt: Date?

    static let `default` = SpiritualRhythmPreferences()
}

@MainActor
final class SpiritualRhythmPreferencesService: ObservableObject {
    static let shared = SpiritualRhythmPreferencesService()

    @Published private(set) var preferences: SpiritualRhythmPreferences = .default
    @Published private(set) var isLoaded = false
    @Published var saveError: String?

    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var saveTask: Task<Void, Never>?

    private init() {}

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = settingsDocument(uid: uid).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.saveError = error.localizedDescription
                    return
                }
                if let data = snapshot?.data(),
                   let decoded = try? Firestore.Decoder().decode(SpiritualRhythmPreferences.self, from: data) {
                    self.preferences = decoded
                } else {
                    self.preferences = .default
                    self.scheduleSave()
                }
                self.applyToLocalPreferences()
                self.isLoaded = true
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        saveTask?.cancel()
        saveTask = nil
        preferences = .default
        isLoaded = false
    }

    func update(_ transform: (inout SpiritualRhythmPreferences) -> Void) {
        transform(&preferences)
        preferences.updatedAt = Date()
        applyToLocalPreferences()
        scheduleSave()
    }

    func resetToDefaults() {
        preferences = .default
        preferences.updatedAt = Date()
        applyToLocalPreferences()
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.persist()
        }
    }

    private func persist() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            var payload = try Firestore.Encoder().encode(preferences)
            payload["platform"] = "ios"
            try await settingsDocument(uid: uid).setData(payload, merge: true)
            try await syncSmartNotificationPreferences(uid: uid)
            try await syncFeedHealth(uid: uid)
            Analytics.logEvent("spiritual_rhythm_preferences_saved", parameters: [
                "morning_devotional_enabled": preferences.morningDevotionalEnabled,
                "sunday_rest_enabled": preferences.sundayRestEnabled,
                "prefer_calm_feed": preferences.preferCalmFeed
            ])
            saveError = nil
        } catch {
            saveError = error.localizedDescription
            dlog("❌ SpiritualRhythmPreferences save failed: \(error.localizedDescription)")
        }
    }

    private func settingsDocument(uid: String) -> DocumentReference {
        db.collection("users").document(uid)
            .collection("devotionalRhythm").document("main")
    }

    private func applyToLocalPreferences() {
        AMENUserPreferencesService.shared.update {
            $0.notificationsEnabled = preferences.masterPushEnabled
            $0.morningDevotionalEnabled = preferences.morningDevotionalEnabled
            $0.morningDevotionalHour = preferences.morningHour
            $0.morningDevotionalMinute = preferences.morningMinute
            $0.maxDailyNotifications = preferences.maxDailyNotifications
        }
    }

    private func syncSmartNotificationPreferences(uid: String) async throws {
        let quietHours: [String: Any] = [
            "enabled": preferences.quietHoursEnabled,
            "startTime": preferences.quietHoursStart,
            "endTime": preferences.quietHoursEnd
        ]
        try await db.collection("users").document(uid)
            .collection("notificationPreferences").document("smart")
            .setData([
                "masterPushEnabled": preferences.masterPushEnabled,
                "quietHours": quietHours,
                "sundayMode": preferences.sundayRestEnabled,
                "aiSummaryEnabled": preferences.aiSummaryEnabled,
                "aiSummaryFrequency": preferences.aiSummaryFrequency
            ], merge: true)
    }

    private func syncFeedHealth(uid: String) async throws {
        try await db.collection("users").document(uid)
            .collection("bereanPulse").document("main")
            .collection("preferences").document("main")
            .setData([
                "preferCalmContent": preferences.preferCalmFeed,
                "reduceOutrage": preferences.reduceOutrage,
                "reduceRapidCuts": preferences.reduceRapidCuts,
                "sundayRestEnabled": preferences.sundayRestEnabled,
                "spiritualPromptsEnabled": preferences.spiritualPromptsEnabled,
                "promptCooldownMinutes": preferences.promptCooldownMinutes,
                "updatedAt": Timestamp(date: preferences.updatedAt ?? Date())
            ], merge: true)
    }
}
