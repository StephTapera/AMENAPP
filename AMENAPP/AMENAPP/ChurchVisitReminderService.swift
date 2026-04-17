// ChurchVisitReminderService.swift
// AMENAPP
//
// Schedules and manages local UNUserNotificationCenter reminders tied to
// the church visit planning lifecycle. Uses the existing NotificationScheduler
// infrastructure for consistency.
//
// Reminder types:
//   - Pre-visit (leave-soon): fires N minutes before service based on travel estimate
//   - Post-visit reflect: fires 3 hours after expected service end
//   - Follow-up: fires next morning to prompt a return decision note
//
// Privacy: all state is user-initiated. No reminders are created without
// explicit user action (starting a visit plan or marking attended).

import Foundation
import UserNotifications
import CoreLocation
import FirebaseAuth

@MainActor
final class ChurchVisitReminderService {

    static let shared = ChurchVisitReminderService()

    // MARK: - Notification identifiers

    private enum Identifier {
        static func leaveSoon(churchId: String) -> String { "church_leave_soon_\(churchId)" }
        static func reflectToday(churchId: String) -> String { "church_reflect_today_\(churchId)" }
        static func followUpTomorrow(churchId: String) -> String { "church_follow_up_\(churchId)" }
    }

    private init() {}

    // MARK: - Schedule Pre-Visit Reminder

    /// Schedule a "leave soon" reminder for a planned visit.
    /// Safe to call multiple times — idempotent per churchId.
    func scheduleLeaveReminder(
        for church: Church,
        serviceDate: Date,
        travelMinutes: Double,
        prepMinutes: Int = 30
    ) {
        let leadTime = TimeInterval((travelMinutes + Double(prepMinutes)) * 60)
        let fireDate = serviceDate.addingTimeInterval(-leadTime)

        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to leave for \(church.name)"
        content.body = "Your service starts soon. Safe travels! 🙏"
        content.sound = .default
        content.categoryIdentifier = "CHURCH_VISIT"
        content.userInfo = [
            "churchId": church.id.uuidString,
            "churchName": church.name,
            "type": "leave_soon"
        ]

        schedule(
            content: content,
            at: fireDate,
            identifier: Identifier.leaveSoon(churchId: church.id.uuidString)
        )
    }

    // MARK: - Schedule Post-Visit Reflection Prompt

    /// Schedules a same-day reflection prompt 3 hours after the expected service end.
    func scheduleReflectPrompt(for church: Church, serviceDate: Date, durationMinutes: Int = 90) {
        let serviceEnd = serviceDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let fireDate = serviceEnd.addingTimeInterval(3 * 3600)

        guard fireDate > Date() else {
            // Service already ended — fire in 30 minutes if user just marked attended
            let soon = Date().addingTimeInterval(30 * 60)
            scheduleReflectContent(for: church, at: soon)
            return
        }

        scheduleReflectContent(for: church, at: fireDate)
    }

    private func scheduleReflectContent(for church: Church, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "How was \(church.name)?"
        content.body = "Take a moment to capture your thoughts from today's service."
        content.sound = .default
        content.categoryIdentifier = "CHURCH_REFLECT"
        content.userInfo = [
            "churchId": church.id.uuidString,
            "churchName": church.name,
            "type": "reflect_today"
        ]

        schedule(
            content: content,
            at: date,
            identifier: Identifier.reflectToday(churchId: church.id.uuidString)
        )
    }

    // MARK: - Schedule Follow-Up Tomorrow

    /// Schedules a next-morning follow-up to prompt a return decision note.
    func scheduleFollowUpReminder(for church: Church) {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) else { return }
        let fireDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow

        let content = UNMutableNotificationContent()
        content.title = "Still thinking about \(church.name)?"
        content.body = "Write a quick reflection — what stayed with you from Sunday?"
        content.sound = .default
        content.categoryIdentifier = "CHURCH_FOLLOW_UP"
        content.userInfo = [
            "churchId": church.id.uuidString,
            "churchName": church.name,
            "type": "follow_up_tomorrow"
        ]

        schedule(
            content: content,
            at: fireDate,
            identifier: Identifier.followUpTomorrow(churchId: church.id.uuidString)
        )
    }

    // MARK: - Cancel

    func cancelReminders(for church: Church) {
        let ids = [
            Identifier.leaveSoon(churchId: church.id.uuidString),
            Identifier.reflectToday(churchId: church.id.uuidString),
            Identifier.followUpTomorrow(churchId: church.id.uuidString),
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Cancels all church-related pending reminders (called on sign-out).
    func cancelAllReminders() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let churchIds = requests
                .filter { $0.identifier.hasPrefix("church_") }
                .map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: churchIds)
        }
    }

    // MARK: - Permission Check

    func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Private

    private func schedule(content: UNMutableNotificationContent, at date: Date, identifier: String) {
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        // Remove stale request first (idempotent)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                dlog("[ChurchReminder] Schedule error (\(identifier)): \(error)")
            }
        }
    }
}
