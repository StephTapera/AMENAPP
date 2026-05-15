import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

@MainActor
final class AmbientPresenceIntelligence: ObservableObject {
    static let shared = AmbientPresenceIntelligence()

    @Published private(set) var preferences: PresencePreferences = .default
    @Published private(set) var activeSignals: [PresenceSignal] = []

    private lazy var db = Firestore.firestore()

    private init() {}

    func loadPreferences() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snapshot = try await db.collection("users")
            .document(uid)
            .collection("presence_preferences")
            .document("main")
            .getDocument()

        guard let data = snapshot.data() else {
            preferences = .default
            return
        }

        preferences = try Firestore.Decoder().decode(PresencePreferences.self, from: data)
    }

    func updatePreferences(_ updated: PresencePreferences) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data = try Firestore.Encoder().encode(updated)
        try await db.collection("users")
            .document(uid)
            .collection("presence_preferences")
            .document("main")
            .setData(data, merge: true)
        preferences = updated
    }

    func loadPresenceSignals(limit: Int = 10) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snapshot = try await db.collection("users")
            .document(uid)
            .collection("presence_signals")
            .limit(to: limit)
            .getDocuments()

        let decoder = Firestore.Decoder()
        activeSignals = snapshot.documents.compactMap { try? decoder.decode(PresenceSignal.self, from: $0.data()) }
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
    }

    func eligibleSignals(
        at date: Date = Date(),
        userLocation: CLLocation?,
        isTraveling: Bool,
        isQuietHours: Bool
    ) -> [PresenceSignal] {
        guard !preferences.quietModeEnabled else { return [] }
        guard !(isQuietHours && preferences.sensitivityLevel == .quiet) else { return [] }
        guard !(isTraveling && preferences.travelAwareSuppression) else { return [] }

        return activeSignals.filter { signal in
            preferences.enabledSignals.contains(signal.type) &&
            signal.confidence >= minimumConfidence(for: signal.type) &&
            isLocationCompatible(signal: signal, userLocation: userLocation)
        }
    }

    func buildNotificationRequests(from signals: [PresenceSignal]) -> [UNNotificationRequest] {
        signals.prefix(3).compactMap { signal in
            let content = UNMutableNotificationContent()
            content.title = signal.title
            content.body = signal.detail ?? defaultBody(for: signal.type)
            content.sound = nil
            content.userInfo = [
                "presenceSignalId": signal.id,
                "confidence": signal.confidence,
                "confidenceLevel": signal.confidenceLevel.rawValue,
            ]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            return UNNotificationRequest(identifier: "presence_\(signal.id)", content: content, trigger: trigger)
        }
    }

    private func minimumConfidence(for type: PresenceSignalType) -> Double {
        switch preferences.sensitivityLevel {
        case .minimal:
            return 0.82
        case .balanced:
            return type == .serviceStartingSoon ? 0.68 : 0.74
        case .quiet:
            return 0.88
        }
    }

    private func isLocationCompatible(signal: PresenceSignal, userLocation: CLLocation?) -> Bool {
        guard let userLocation, let point = signal.location else { return true }
        return userLocation.distance(from: point.clLocation) < 40_000
    }

    private func defaultBody(for type: PresenceSignalType) -> String {
        switch type {
        case .prayerGathering:
            return "A nearby prayer gathering is beginning soon."
        case .serviceStartingSoon:
            return "A saved church is approaching its next service window."
        case .quietPrayerSpace:
            return "A calm prayer space is available nearby."
        case .bibleStudyTonight:
            return "A Bible study aligned with your interests is happening tonight."
        case .volunteerOpportunity:
            return "A service opportunity matches your recent ministry interests."
        case .savedChurchReminder:
            return "A church you saved has a meaningful update."
        }
    }
}

private extension ChurchEntity.GeoPoint {
    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
