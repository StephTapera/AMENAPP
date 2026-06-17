
//  ChurchNotesNotificationGovernor.swift
//  AMENAPP
//
//  W3 — Template-based notification composer + grace-shaped governor.
//  No free text. No streaks. No shame. No standing-with-God framing.
//

import Foundation
import UserNotifications

// MARK: - Composer

/// Fills approved slots in a NotificationTemplate. LLM path is server-side only
/// and only for general notes; this client composer does template rendering.
final class ChurchNotesNotificationComposerImpl: NotificationComposer {

    func compose(_ template: NotificationTemplate, slots: NotificationSlots) -> String {
        switch template {
        case .continueReadingPlan:
            return "Would you like to continue your reading plan?"
        case .verseReview:
            let ref = slots.verseRef.map { " \($0)" } ?? ""
            return "Would you like to review\(ref) today?"
        case .prayerInvite:
            let topic = slots.topic ?? "what's on your heart"
            return "Take a few minutes to pray for \(topic)."
        case .eventUpcoming:
            let event = slots.eventTitle ?? "an upcoming gathering"
            return "\(event) is coming up."
        }
    }
}

// MARK: - Governor

/// Enforces per-day cap and ignore-decay back-off.
/// Shared singleton; state is persisted in UserDefaults (no sensitive data stored).
final class ChurchNotesNotificationGovernorImpl: NotificationGovernor {

    static let shared = ChurchNotesNotificationGovernorImpl()

    private let maxPerDay = 2
    private let consecutiveIgnoreBackOffThreshold = 3
    private let composer = ChurchNotesNotificationComposerImpl()

    // UserDefaults keys (no PII, template IDs only)
    private let historyKey = "cn_discipleship_delivery_history"

    private init() {}

    // MARK: Protocol

    func shouldDeliver(_ candidate: NotificationTemplate, history: DeliveryHistory) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())

        // 1. Per-day cap
        let todayCount = history.records.filter {
            Calendar.current.startOfDay(for: $0.deliveredAt) == today
        }.count
        if todayCount >= maxPerDay { return false }

        // 2. Ignore-decay: 3+ consecutive ignores → back off
        let recent = history.records.suffix(consecutiveIgnoreBackOffThreshold)
        if recent.count == consecutiveIgnoreBackOffThreshold && recent.allSatisfy(\.wasIgnored) {
            return false
        }

        return true
    }

    // MARK: - Schedule

    /// Called from ChurchNotesDiscipleshipService.handleRemindLater(_:).
    /// Schedules a local notification if the governor allows it.
    func scheduleIfAllowed(_ action: SpiritualAction) {
        guard ChurchNotesDiscipleshipFlags.masterEnabled,
              ChurchNotesDiscipleshipFlags.notificationsEnabled else { return }

        let history = loadHistory()
        let template = bestTemplate(for: action)
        guard shouldDeliver(template, history: history) else { return }

        let slots = slotsFor(action: action)
        let body = composer.compose(template, slots: slots)
        scheduleLocalNotification(body: body, action: action)
        appendDelivery(template: template, to: history)
    }

    // MARK: - Helpers

    private func bestTemplate(for action: SpiritualAction) -> NotificationTemplate {
        switch action.kind {
        case .pray:              return .prayerInvite
        case .read, .memorize:  return .continueReadingPlan
        case .attend:            return .eventUpcoming
        default:                 return .continueReadingPlan
        }
    }

    private func slotsFor(action: SpiritualAction) -> NotificationSlots {
        var slots = NotificationSlots()
        switch action.kind {
        case .pray:
            let topic = action.namedPeople.first ?? "what's on your heart"
            slots.topic = topic
        default:
            break
        }
        return slots
    }

    private func scheduleLocalNotification(body: String, action: SpiritualAction) {
        let content = UNMutableNotificationContent()
        content.title = "From your church notes"
        content.body = body
        content.sound = .default
        // No badge count — avoids numeric pressure. (S9)

        // Deliver ~1 hour from now, within a grace window
        var components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        components.hour = (components.hour ?? 0) + 1
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: "cn_discipleship_\(action.id.uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - History Persistence (template IDs only, no note content)

    private func loadHistory() -> DeliveryHistory {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode(DeliveryHistory.self, from: data) else {
            return DeliveryHistory(records: [])
        }
        // Prune records older than 7 days to keep storage bounded
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let pruned = history.records.filter { $0.deliveredAt > cutoff }
        return DeliveryHistory(records: pruned)
    }

    private func appendDelivery(template: NotificationTemplate, to history: DeliveryHistory) {
        let record = DeliveryRecord(template: template, deliveredAt: Date(), wasIgnored: false)
        let updated = DeliveryHistory(records: history.records + [record])
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    /// Call when a notification is interacted with (clears ignore status for the last record).
    func markInteracted(notificationID: String) {
        var history = loadHistory()
        // Mark last record as not ignored when the user taps
        if var last = history.records.last, !last.wasIgnored {
            last = DeliveryRecord(template: last.template, deliveredAt: last.deliveredAt, wasIgnored: false)
            let updated = history.records.dropLast() + [last]
            let newHistory = DeliveryHistory(records: Array(updated))
            if let data = try? JSONEncoder().encode(newHistory) {
                UserDefaults.standard.set(data, forKey: historyKey)
            }
        }
    }

    /// Call when a notification is dismissed without interaction (increments ignore counter).
    func markIgnored(notificationID: String) {
        var history = loadHistory()
        if let last = history.records.last {
            let marked = DeliveryRecord(template: last.template, deliveredAt: last.deliveredAt, wasIgnored: true)
            let updated = history.records.dropLast() + [marked]
            let newHistory = DeliveryHistory(records: Array(updated))
            if let data = try? JSONEncoder().encode(newHistory) {
                UserDefaults.standard.set(data, forKey: historyKey)
            }
        }
    }
}
