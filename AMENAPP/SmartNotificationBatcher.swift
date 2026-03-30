//
//  SmartNotificationBatcher.swift
//  AMENAPP
//
//  Intelligent notification batching with catch-up summaries
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import UserNotifications
import Combine

/// Batches low-priority notifications and delivers smart summaries
@MainActor
class SmartNotificationBatcher: ObservableObject {
    static let shared = SmartNotificationBatcher()

    private let db = Firestore.firestore()

    @Published var pendingBatch: [BatchedNotification] = []
    @Published var lastDeliveryTime: Date?

    // MARK: - Batching Queue

    struct BatchedNotification: Identifiable, Codable {
        let id: String
        let category: NotificationCategory
        let fromUserId: String
        let fromUsername: String
        let content: String
        let timestamp: Date
        let priority: Double
        let entityId: String?

        enum CodingKeys: String, CodingKey {
            case id, category, fromUserId, fromUsername, content, timestamp, priority, entityId
        }
    }

    /// Add notification to batch queue instead of delivering immediately
    func addToBatch(
        category: NotificationCategory,
        fromUserId: String,
        fromUsername: String,
        content: String,
        priority: Double,
        entityId: String? = nil
    ) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let notification = BatchedNotification(
            id: UUID().uuidString,
            category: category,
            fromUserId: fromUserId,
            fromUsername: fromUsername,
            content: content,
            timestamp: Date(),
            priority: priority,
            entityId: entityId
        )

        // Add to Firestore queue
        do {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(notification),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                try await db.collection("users").document(userId)
                    .collection("notificationQueue")
                    .document(notification.id)
                    .setData(dict)
            }

            // Add to local queue
            pendingBatch.append(notification)

        } catch {
            dlog("❌ Failed to add to batch: \(error.localizedDescription)")
        }
    }

    /// Deliver batch as a single summary notification
    func deliverBatchSummary(forUserId userId: String) async {
        // Fetch pending notifications
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("notificationQueue")
                .order(by: "timestamp", descending: false)
                .getDocuments()

            var notifications: [BatchedNotification] = []
            for doc in snapshot.documents {
                if let data = try? JSONSerialization.data(withJSONObject: doc.data()),
                   let notification = try? JSONDecoder().decode(BatchedNotification.self, from: data) {
                    notifications.append(notification)
                }
            }

            guard !notifications.isEmpty else {
                dlog("📬 No pending notifications to batch")
                return
            }

            // Generate smart summary
            let summary = generateSummary(from: notifications)

            // Deliver as single notification
            await deliverSummaryNotification(summary: summary, userId: userId)

            // Clear queue
            await clearBatchQueue(userId: userId)

            lastDeliveryTime = Date()
            dlog("✅ Delivered batch summary: \(notifications.count) notifications")

        } catch {
            dlog("❌ Failed to deliver batch: \(error.localizedDescription)")
        }
    }

    private func generateSummary(from notifications: [BatchedNotification]) -> BatchNotificationSummary {
        // Group by category
        let grouped = Dictionary(grouping: notifications, by: { $0.category })

        var summaryParts: [String] = []
        var totalCount = notifications.count

        // Format summary by category
        for (category, items) in grouped.sorted(by: { $0.value.count > $1.value.count }) {
            let count = items.count
            let categoryName = category.displayName.lowercased()

            if count == 1, let first = items.first {
                summaryParts.append("\(first.fromUsername): \(first.content.prefix(40))...")
            } else {
                summaryParts.append("\(count) \(categoryName)")
            }
        }

        let title: String
        if summaryParts.count == 1 {
            title = summaryParts[0]
        } else {
            title = "You have \(totalCount) new notifications"
        }

        let body = summaryParts.prefix(3).joined(separator: ", ")

        return BatchNotificationSummary(
            title: title,
            body: body,
            count: totalCount,
            categories: Array(grouped.keys),
            timestamp: Date()
        )
    }

    private func deliverSummaryNotification(summary: BatchNotificationSummary, userId: String) async {
        let content = UNMutableNotificationContent()
        content.title = summary.title
        content.body = summary.body
        content.badge = summary.count as NSNumber
        content.sound = .default
        content.categoryIdentifier = "BATCH_SUMMARY"
        content.threadIdentifier = "batch_summary"

        let request = UNNotificationRequest(
            identifier: "batch_summary_\(UUID().uuidString)",
            content: content,
            trigger: nil  // Deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            dlog("✅ Batch summary notification delivered")
        } catch {
            dlog("❌ Failed to deliver summary notification: \(error.localizedDescription)")
        }
    }

    private func clearBatchQueue(userId: String) async {
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("notificationQueue")
                .getDocuments()

            for doc in snapshot.documents {
                try await doc.reference.delete()
            }

            pendingBatch.removeAll()

        } catch {
            dlog("❌ Failed to clear batch queue: \(error.localizedDescription)")
        }
    }

    // MARK: - Catch-Up Summaries

    /// Generate catch-up summary when user opens app after quiet hours
    func generateCatchUpSummary(forUserId userId: String, since: Date) async -> CatchUpSummary? {
        do {
            // Fetch all notifications since the given time
            let snapshot = try await db.collection("users").document(userId)
                .collection("notificationQueue")
                .whereField("timestamp", isGreaterThan: Timestamp(date: since))
                .order(by: "timestamp", descending: false)
                .getDocuments()

            var notifications: [BatchedNotification] = []
            for doc in snapshot.documents {
                if let data = try? JSONSerialization.data(withJSONObject: doc.data()),
                   let notification = try? JSONDecoder().decode(BatchedNotification.self, from: data) {
                    notifications.append(notification)
                }
            }

            guard !notifications.isEmpty else { return nil }

            // Generate intelligent summary
            let grouped = Dictionary(grouping: notifications, by: { $0.category })

            var highlights: [CatchUpSummary.Highlight] = []

            // High-priority items first
            let highPriority = notifications.filter { $0.priority > 0.7 }
                .sorted { $0.priority > $1.priority }
                .prefix(3)

            for notification in highPriority {
                highlights.append(CatchUpSummary.Highlight(
                    type: .highPriority,
                    category: notification.category,
                    fromUsername: notification.fromUsername,
                    content: notification.content,
                    timestamp: notification.timestamp
                ))
            }

            // Add category summaries
            for (category, items) in grouped.sorted(by: { $0.value.count > $1.value.count }) {
                let summary = "\(items.count) \(category.displayName.lowercased())"
                highlights.append(CatchUpSummary.Highlight(
                    type: .categorySummary,
                    category: category,
                    fromUsername: summary,
                    content: "",
                    timestamp: items.first?.timestamp ?? Date()
                ))
            }

            return CatchUpSummary(
                totalCount: notifications.count,
                highlights: Array(highlights.prefix(5)),
                since: since,
                mostActiveUser: findMostActiveUser(in: notifications),
                totalTime: Date().timeIntervalSince(since)
            )

        } catch {
            dlog("❌ Failed to generate catch-up summary: \(error.localizedDescription)")
            return nil
        }
    }

    private func findMostActiveUser(in notifications: [BatchedNotification]) -> String? {
        let userCounts = Dictionary(grouping: notifications, by: { $0.fromUserId })
            .mapValues { $0.count }

        return userCounts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Scheduled Delivery

    /// Schedule batch delivery based on user preferences
    func scheduleNextBatchDelivery(cadence: SmartNotificationPreferences.DigestCadence) {
        let trigger: UNNotificationTrigger?

        switch cadence {
        case .realtime:
            return  // No batching

        case .twiceDaily:
            // Deliver at 9 AM and 6 PM
            let morningComponents = DateComponents(hour: 9, minute: 0)
            let eveningComponents = DateComponents(hour: 18, minute: 0)

            let now = Date()
            let calendar = Calendar.current
            let currentHour = calendar.component(.hour, from: now)

            if currentHour < 9 {
                trigger = UNCalendarNotificationTrigger(dateMatching: morningComponents, repeats: false)
            } else if currentHour < 18 {
                trigger = UNCalendarNotificationTrigger(dateMatching: eveningComponents, repeats: false)
            } else {
                // Next morning
                trigger = UNCalendarNotificationTrigger(dateMatching: morningComponents, repeats: false)
            }

        case .daily:
            // Deliver at 9 AM daily
            let components = DateComponents(hour: 9, minute: 0)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        case .weekly:
            // Deliver Sunday at 9 AM
            let components = DateComponents(hour: 9, minute: 0, weekday: 1)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }

        guard let trigger = trigger else { return }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = "BATCH_DELIVERY_TRIGGER"
        content.userInfo = ["action": "deliverBatch"]

        let request = UNNotificationRequest(
            identifier: "batch_delivery_scheduled",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                dlog("❌ Failed to schedule batch delivery: \(error.localizedDescription)")
            } else {
                dlog("✅ Batch delivery scheduled: \(cadence)")
            }
        }
    }
}

// MARK: - Models

struct BatchNotificationSummary {
    let title: String
    let body: String
    let count: Int
    let categories: [NotificationCategory]
    let timestamp: Date
}

struct CatchUpSummary {
    struct Highlight {
        enum HighlightType {
            case highPriority
            case categorySummary
            case trending
        }

        let type: HighlightType
        let category: NotificationCategory
        let fromUsername: String
        let content: String
        let timestamp: Date
    }

    let totalCount: Int
    let highlights: [Highlight]
    let since: Date
    let mostActiveUser: String?
    let totalTime: TimeInterval
}
