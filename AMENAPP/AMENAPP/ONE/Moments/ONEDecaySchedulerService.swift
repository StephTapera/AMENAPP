// ONEDecaySchedulerService.swift
// ONE — Client-side decay scheduling (notification reminder + CF call at expiry).
// P2-F | Server-side CF scheduled trigger is primary; this is a client-side backup.
// "Remember" cancels both the notification and the server-side decay via one_expireMoment.

import Foundation
import UserNotifications

actor ONEDecaySchedulerService {

    private var scheduled: Set<String> = []     // momentIDs with active client schedules

    // MARK: - Schedule decay

    func schedule(momentID: String, policy: ONELifetimePolicy, createdAt: Date) async {
        guard let expiry = expiry(for: policy, from: createdAt) else { return }
        guard scheduled.insert(momentID).inserted else { return }   // idempotent

        let reminderDate = expiry.addingTimeInterval(-3_600)        // 1 h before expiry
        guard reminderDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Moment expiring soon"
        content.body  = "This moment fades in about an hour. Tap to remember it."
        content.userInfo = ["momentID": momentID, "action": "one_decay_reminder"]
        content.interruptionLevel = .passive

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: reminderDate
            ),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: notificationID(for: momentID),
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Non-critical: notification scheduling failure doesn't block send
        }
    }

    // MARK: - Cancel (earned permanence)

    /// Cancels decay for a moment. Called when the user taps "Remember".
    func cancel(momentID: String) async {
        scheduled.remove(momentID)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID(for: momentID)])
        // one_expireMoment with cancel=true extends lifetime on server
        // (CF stub — full implementation at P2-I deploy step)
        _ = try? await ONECallableService.shared.expireMoment(momentID: momentID)
    }

    // MARK: - Expiry calculation
    // Avoids calling ONELifetimePolicy.expiryDate which has a known Swift bug
    // (switch uses .hours(let h) pattern on non-associated-value enum).

    func expiry(for policy: ONELifetimePolicy, from creation: Date) -> Date? {
        switch policy.kind {
        case .permanent:             return nil
        case .afterView:             return creation.addingTimeInterval(3_600)
        case .hours:                 return creation.addingTimeInterval(Double(policy.hours ?? 24) * 3_600)
        case .days:                  return creation.addingTimeInterval(Double(policy.days  ?? 7)  * 86_400)
        case .decayUnlessRemembered: return creation.addingTimeInterval(Double(policy.days  ?? 30) * 86_400)
        }
    }

    private func notificationID(for momentID: String) -> String { "one_decay_\(momentID)" }
}
