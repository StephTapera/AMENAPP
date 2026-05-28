import Foundation
import FirebaseFirestore

enum NotificationFrequency: String, Codable, CaseIterable {
    case realtime, batchedDaily, batchedWeekly, digest
    var displayName: String {
        switch self {
        case .realtime: return "Real-Time"
        case .batchedDaily: return "Daily Digest"
        case .batchedWeekly: return "Weekly Digest"
        case .digest: return "Smart Digest"
        }
    }
}

struct NotificationPreferences: Codable {
    var enabled: Bool
    var quietHoursEnabled: Bool
    var quietHoursStart: String
    var quietHoursEnd: String
    var timezone: String
    var frequency: NotificationFrequency
    var crisisEscalation: Bool
    var givingMilestone: Bool
    var wellnessReminder: Bool
    var supportGroupUpdate: Bool
    var friendActivity: Bool
    var churchNews: Bool
    var mutedUntil: Timestamp?

    static var defaults: NotificationPreferences {
        NotificationPreferences(
            enabled: true,
            quietHoursEnabled: true,
            quietHoursStart: "21:00",
            quietHoursEnd: "08:00",
            timezone: TimeZone.current.identifier,
            frequency: .realtime,
            crisisEscalation: true,
            givingMilestone: true,
            wellnessReminder: true,
            supportGroupUpdate: true,
            friendActivity: true,
            churchNews: true,
            mutedUntil: nil
        )
    }
}

struct QueuedNotification: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var type: String
    var title: String
    var body: String
    var deepLink: String
    var priority: String
    var scheduledFor: Timestamp?
    var sent: Bool
    var dedupeKey: String?
}
