import Foundation
import UserNotifications

final class ChurchNotesReminderService {
    static let shared = ChurchNotesReminderService()

    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    init(center: UNUserNotificationCenter = .current(), calendar: Calendar = .current) {
        self.center = center
        self.calendar = calendar
    }

    func scheduleMidweekReminder(noteTitle: String, serviceDate: Date, draftKey: String) async throws {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { throw ChurchNotesReminderError.authorizationDenied }
        } else if settings.authorizationStatus == .denied {
            throw ChurchNotesReminderError.authorizationDenied
        }

        let reminderDate = nextMidweekDate(after: serviceDate)
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        components.second = 0

        let content = UNMutableNotificationContent()
        content.title = "Revisit your Church Note"
        content.body = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Return to your prayer, action step, and what stood out."
            : "Return to \(noteTitle) and follow through on your prayer or action step."
        content.sound = .default
        content.userInfo = [
            "destination": "churchNotes",
            "draftKey": draftKey
        ]

        let identifier = "churchNotes.midweek.\(draftKey)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try await center.add(request)
    }

    private func nextMidweekDate(after serviceDate: Date) -> Date {
        let baseline = calendar.date(byAdding: .day, value: 3, to: serviceDate) ?? Date().addingTimeInterval(60 * 60 * 24 * 3)
        var components = calendar.dateComponents([.year, .month, .day], from: baseline)
        components.hour = 10
        components.minute = 0
        return calendar.date(from: components) ?? baseline
    }
}

enum ChurchNotesReminderError: LocalizedError {
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Notifications are turned off. Enable notifications to use midweek Church Note reminders."
        }
    }
}
