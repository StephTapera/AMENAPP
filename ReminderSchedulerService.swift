// ReminderSchedulerService.swift
// AMEN Calendar — Local Notification Reminder Engine
// Smart reminders for church events, prayer, Bible study, job interviews, and more

import SwiftUI
import Combine
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ReminderSchedulerService: ObservableObject {
    static let shared = ReminderSchedulerService()

    // MARK: - Published State

    @Published var notificationPermissionGranted = false
    @Published var scheduledReminders: [String: [String]] = [:]  // eventId -> [notificationIds]

    private let db = Firestore.firestore()

    private init() {
        checkNotificationPermission()
    }

    // MARK: - Permission

    func checkNotificationPermission() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationPermissionGranted = settings.authorizationStatus == .authorized
        }
    }

    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            notificationPermissionGranted = granted
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Schedule Reminders for AMEN Event

    /// Schedule one or more local notifications for an event.
    /// Returns array of notification identifiers.
    func scheduleReminders(
        for event: AMENEvent,
        offsets: [ReminderOffset],
        followUpAfterEvent: Bool = false
    ) async -> [String] {
        guard notificationPermissionGranted else { return [] }

        var notificationIds: [String] = []
        let center = UNUserNotificationCenter.current()

        for offset in offsets {
            let fireDate = event.startDate.addingTimeInterval(-TimeInterval(offset.minutesBefore * 60))
            guard fireDate > Date() else { continue }  // Skip past dates

            let id = "amen_event_\(event.id ?? UUID().uuidString)_\(offset.rawValue)"

            let content = makeContent(
                for: event,
                offset: offset,
                isFollowUp: false
            )

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fireDate
                ),
                repeats: false
            )

            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            do {
                try await center.add(request)
                notificationIds.append(id)
            } catch {
                // Silently skip failed notifications
            }
        }

        // Follow-up reminder (e.g., "How did the interview go?")
        if followUpAfterEvent {
            let followUpDate = event.endDate.addingTimeInterval(60 * 60)  // 1 hour after end
            if followUpDate > Date() {
                let followUpId = "amen_followup_\(event.id ?? UUID().uuidString)"
                let followUpContent = makeFollowUpContent(for: event)
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: followUpDate
                    ),
                    repeats: false
                )
                let request = UNNotificationRequest(identifier: followUpId, content: followUpContent, trigger: trigger)
                try? await center.add(request)
                notificationIds.append(followUpId)
            }
        }

        // Persist to Firestore
        if let eventId = event.id, !notificationIds.isEmpty {
            scheduledReminders[eventId] = notificationIds
            await saveReminderRecord(eventId: eventId, notificationIds: notificationIds)
        }

        return notificationIds
    }

    // MARK: - Schedule Prayer / Bible Study Recurring Reminder

    /// Schedule a recurring weekly reminder (e.g., weekly small group)
    func scheduleRecurringReminder(
        title: String,
        body: String,
        weekday: Int,                       // 1 = Sunday, 7 = Saturday
        hour: Int,
        minute: Int,
        identifier: String
    ) async -> Bool {
        guard notificationPermissionGranted else { return false }

        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["type": "recurring_reminder", "identifier": identifier]

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: "amen_recurring_\(identifier)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Schedule Spiritual Check-In Reminder

    func scheduleSpiritualCheckIn(hour: Int, minute: Int, daysOfWeek: [Int]) async {
        let center = UNUserNotificationCenter.current()
        let spiritualMessages = [
            "Take a moment to reflect. How is your spirit today?",
            "A quiet moment with God can change everything.",
            "How are you doing, really? Take a breath.",
            "Checking in — are you carrying anything that needs prayer?",
            "A still moment can anchor your whole day."
        ]

        for day in daysOfWeek {
            var components = DateComponents()
            components.weekday = day
            components.hour = hour
            components.minute = minute

            let content = UNMutableNotificationContent()
            content.title = "Spiritual Check-In"
            content.body = spiritualMessages.randomElement() ?? spiritualMessages[0]
            content.sound = .default
            content.userInfo = ["type": "spiritual_checkin"]

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let id = "amen_spiritual_checkin_day\(day)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    // MARK: - Cancel Reminders

    func cancelReminders(for eventId: String) {
        let ids = scheduledReminders[eventId] ?? []
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        scheduledReminders.removeValue(forKey: eventId)
    }

    func cancelRemindersByIds(_ identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelAllReminders() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        scheduledReminders = [:]
    }

    // MARK: - Notification Content Builders

    private func makeContent(for event: AMENEvent, offset: ReminderOffset, isFollowUp: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch event.eventType {
        case .jobInterview:
            switch offset {
            case .oneDayBefore:
                content.title = "Interview Tomorrow: \(event.title)"
                content.body = "Prepare your materials tonight. You've done the work — trust it."
            case .oneHourBefore:
                content.title = "Interview in 1 hour"
                content.body = "Take a breath. Be yourself. You're ready."
            default:
                content.title = event.title
                content.body = "\(offset.label.capitalized) — you've got this."
            }

        case .prayerMeeting:
            content.title = "Prayer Time — \(event.title)"
            content.body = offset == .atTime ? "It's time to pray." : "Prayer meeting \(offset.label)."

        case .bibleStudy:
            content.title = "Bible Study: \(event.title)"
            content.body = "Bring your Bible and an open heart."

        case .smallGroup:
            content.title = "Small Group Tonight"
            content.body = "\(event.title) starts \(offset.label)."

        case .volunteer:
            content.title = "You're Serving Today"
            content.body = "\(event.title) — thank you for showing up."

        case .churchService:
            content.title = "Church Service \(offset == .oneDayBefore ? "Tomorrow" : offset.label)"
            content.body = event.title

        default:
            content.title = event.title
            content.body = offset == .atTime ? "Starting now" : "Starting \(offset.label)"
        }

        var userInfo: [String: Any] = [
            "type": "event_reminder",
            "eventId": event.id ?? "",
            "eventType": event.eventType.rawValue
        ]
        if let deepLink = event.deepLinkURL { userInfo["deepLink"] = deepLink }
        content.userInfo = userInfo

        return content
    }

    private func makeFollowUpContent(for event: AMENEvent) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch event.eventType {
        case .jobInterview:
            content.title = "How did the interview go?"
            content.body = "Take a moment to journal or pray about how it went."
        case .bibleStudy:
            content.title = "Reflecting on today's study?"
            content.body = "What's one thing that stood out from your Bible study?"
        case .prayerMeeting:
            content.title = "Prayer time complete"
            content.body = "What are you carrying forward from today's prayer?"
        case .volunteer:
            content.title = "Thank you for serving!"
            content.body = "You made a difference today. How are you feeling?"
        case .smallGroup:
            content.title = "Small group wrap-up"
            content.body = "Any follow-ups or prayers from tonight's gathering?"
        default:
            content.title = "\(event.title) — Follow Up"
            content.body = "How did it go? Take a moment to reflect."
        }

        content.userInfo = [
            "type": "follow_up_reminder",
            "eventId": event.id ?? "",
            "eventType": event.eventType.rawValue
        ]
        return content
    }

    // MARK: - Firestore Persistence

    private func saveReminderRecord(eventId: String, notificationIds: [String]) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "userId": userId,
            "eventId": eventId,
            "notificationIds": notificationIds,
            "createdAt": FieldValue.serverTimestamp()
        ]
        let docId = "reminder_\(userId)_\(eventId)"
        try? await db.collection(CalendarCollections.reminderSchedules).document(docId).setData(data, merge: true)
    }

    // MARK: - Smart Reminder Suggestions

    /// Suggest reminder offsets based on event type
    func suggestedReminders(for eventType: AMENEventType) -> [ReminderOffset] {
        return eventType.defaultReminderOffsets
    }

    // MARK: - Pending Notifications Audit (dedup)

    func fetchPendingNotifications() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    func removeDuplicatePendingNotifications() async {
        let pending = await fetchPendingNotifications()
        var seen = Set<String>()
        var toRemove: [String] = []
        for request in pending {
            let key = "\(request.content.title)_\(request.trigger.debugDescription)"
            if seen.contains(key) {
                toRemove.append(request.identifier)
            } else {
                seen.insert(key)
            }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: toRemove)
    }
}
