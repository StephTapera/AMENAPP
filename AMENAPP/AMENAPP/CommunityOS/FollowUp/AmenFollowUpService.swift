// AmenFollowUpService.swift
// AMEN App — CommunityOS / FollowUp
//
// Phase 2 — Agent A15 (Smart Follow-Up)
// Firestore-backed service for private per-user follow-up items.
//
// Storage: /users/{uid}/followUps/{itemId}
//   Private subcollection. Firestore security rules must restrict all
//   reads and writes to the document owner (request.auth.uid == userId).
//
// Anti-engagement rules enforced in this file:
//   ANTI-ENGAGEMENT: Never surface more than 3 follow-ups at once.
//   ANTI-ENGAGEMENT: Reminders are local-only, never push or badge-count increases.
//   ANTI-ENGAGEMENT: No streak tracking, no "you haven't checked in" guilt language.
//   ANTI-ENGAGEMENT: Opt-in only — user explicitly taps "Follow Up" to create an item.
//
// Requires: FirebaseFirestore, UserNotifications
// Concurrency: @MainActor on all public state. Private helpers may run on background executor.

import Foundation
import FirebaseFirestore
import UserNotifications

// MARK: - AmenFollowUpService

@MainActor
final class AmenFollowUpService: ObservableObject {

    // MARK: - Published State

    /// Active + snoozed follow-up items for the current user.
    /// Sorted by `lastSurfacedAt` ascending (oldest-surfaced first) then by `createdAt`.
    /// Resolved and dismissed items are excluded.
    @Published var activeItems: [AmenFollowUpItem] = []

    // MARK: - Private

    private let db = Firestore.firestore()

    /// Returns the `/users/{uid}/followUps` subcollection reference.
    private func followUpsCollection(userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("followUps")
    }

    // MARK: - CRUD

    // MARK: addFollowUp

    /// Creates a new follow-up item in `/users/{uid}/followUps`.
    ///
    /// ANTI-ENGAGEMENT: Opt-in only — this function must only be called when the
    /// user explicitly taps a "Follow Up" action. Never auto-enroll.
    ///
    /// - Parameters:
    ///   - type: The category of the followed-up object.
    ///   - objectRef: Firestore document path of the source object.
    ///   - objectTitle: Denormalised display title for the inbox row.
    ///   - preview: Optional brief preview text from the source object.
    ///   - notifyAfterDays: Days after creation before a local reminder fires.
    ///                      Pass `nil` to skip automatic local reminders.
    ///   - userId: Firebase Auth UID of the current user.
    func addFollowUp(
        type: FollowUpItemType,
        objectRef: String,
        objectTitle: String,
        preview: String?,
        notifyAfterDays: Int?,
        userId: String
    ) async throws {
        let collection = followUpsCollection(userId: userId)
        let docRef = collection.document()

        let item = AmenFollowUpItem(
            id: docRef.documentID,
            userId: userId,
            itemType: type,
            objectRef: objectRef,
            objectTitle: objectTitle,
            objectPreview: preview,
            status: .active,
            createdAt: Date(),
            lastSurfacedAt: nil,
            resolvedAt: nil,
            snoozedUntil: nil,
            notifyAfterDays: notifyAfterDays,
            userNote: nil,
            isPrivate: true         // always private; enforced at rules layer too
        )

        let payload = try encodeItem(item)
        try await docRef.setData(payload)

        // Schedule a gentle local reminder if the caller supplied a day offset.
        if let days = notifyAfterDays {
            let schedule = FollowUpReminderSchedule(
                itemId: item.id,
                triggerDate: Date().addingTimeInterval(Double(days) * 86_400),
                message: type.gentleReminderMessage
            )
            _ = try? scheduleReminder(for: item, schedule: schedule)
        }

        // Reload so activeItems reflects the new item immediately.
        try await loadFollowUps(userId: userId)
    }

    // MARK: loadFollowUps

    /// Loads active + snoozed items for `userId` from Firestore.
    ///
    /// Items are sorted: `lastSurfacedAt` ascending (nil first), then `createdAt` ascending.
    /// Resolved and dismissed items are excluded from `activeItems`.
    func loadFollowUps(userId: String) async throws {
        let snap = try await followUpsCollection(userId: userId)
            .whereField("isDeleted", isNotEqualTo: true)
            .order(by: "isDeleted")
            .order(by: "createdAt", descending: false)
            .getDocuments()

        let items = snap.documents.compactMap { doc -> AmenFollowUpItem? in
            try? decodeItem(from: doc)
        }
        .filter { $0.status == .active || $0.status == .snoozed }
        .sorted { lhs, rhs in
            // Nil lastSurfacedAt sorts before any date (surface oldest-unseen first).
            switch (lhs.lastSurfacedAt, rhs.lastSurfacedAt) {
            case (.none, .some): return true
            case (.some, .none): return false
            case (.some(let l), .some(let r)): return l < r
            case (.none, .none): return lhs.createdAt < rhs.createdAt
            }
        }

        activeItems = items
    }

    // MARK: resolveFollowUp

    /// Marks the follow-up as resolved. Optionally saves a private journal note.
    ///
    /// Resolved items are removed from `activeItems` and their local reminder is cancelled.
    ///
    /// - Parameters:
    ///   - id: The `AmenFollowUpItem.id`.
    ///   - userId: Firebase Auth UID of the current user.
    ///   - note: Optional private journal note to attach before resolving.
    func resolveFollowUp(id: String, userId: String, note: String?) async throws {
        var payload: [String: Any] = [
            "status":     FollowUpStatus.resolved.rawValue,
            "resolvedAt": FieldValue.serverTimestamp()
        ]
        if let note = note {
            payload["userNote"] = note
        }
        try await followUpsCollection(userId: userId).document(id).updateData(payload)
        cancelReminder(for: id)
        activeItems.removeAll { $0.id == id }
    }

    // MARK: snoozeFollowUp

    /// Snoozes the follow-up for `days` days.
    ///
    /// ANTI-ENGAGEMENT: Snooze is a user-directed defer, not a platform retry loop.
    /// The item will re-enter surface eligibility in `surfaceItems` once `snoozedUntil < now`.
    ///
    /// - Parameters:
    ///   - id: The `AmenFollowUpItem.id`.
    ///   - userId: Firebase Auth UID of the current user.
    ///   - days: Number of days to snooze. Minimum 1, maximum 90.
    func snoozeFollowUp(id: String, userId: String, days: Int) async throws {
        let clampedDays = min(max(days, 1), 90)
        let snoozedUntil = Date().addingTimeInterval(Double(clampedDays) * 86_400)
        try await followUpsCollection(userId: userId).document(id).updateData([
            "status":       FollowUpStatus.snoozed.rawValue,
            "snoozedUntil": Timestamp(date: snoozedUntil)
        ])
        // Reflect locally without a full reload.
        if let index = activeItems.firstIndex(where: { $0.id == id }) {
            activeItems[index].status = .snoozed
            activeItems[index].snoozedUntil = snoozedUntil
        }
    }

    // MARK: dismissFollowUp

    /// Soft-dismisses the follow-up (retained in Firestore, removed from inbox).
    ///
    /// Dismissed items are never hard-deleted per the app-wide soft-delete policy.
    func dismissFollowUp(id: String, userId: String) async throws {
        try await followUpsCollection(userId: userId).document(id).updateData([
            "status": FollowUpStatus.dismissed.rawValue
        ])
        cancelReminder(for: id)
        activeItems.removeAll { $0.id == id }
    }

    // MARK: updateNote

    /// Saves or replaces the private journal note on a follow-up item.
    ///
    /// Notes are purely private. They are never indexed, never visible to other users,
    /// and never used as training or feed signals.
    func updateNote(id: String, note: String, userId: String) async throws {
        try await followUpsCollection(userId: userId).document(id).updateData([
            "userNote": note
        ])
        if let index = activeItems.firstIndex(where: { $0.id == id }) {
            activeItems[index].userNote = note
        }
    }

    // MARK: surfaceItems

    /// Returns the items that are due to be shown to the user right now.
    ///
    /// Eligibility rules:
    ///   1. Status is `.active`, OR status is `.snoozed` AND `snoozedUntil < now`.
    ///   2. `lastSurfacedAt` is nil AND `createdAt + notifyAfterDays <= now`, OR
    ///      `lastSurfacedAt` is non-nil (already surfaced at least once).
    ///
    /// ANTI-ENGAGEMENT: Never surface more than 3 follow-ups at once.
    /// Updates `lastSurfacedAt` for each returned item.
    ///
    /// - Parameter userId: Firebase Auth UID of the current user.
    /// - Returns: Up to 3 items eligible for display. Empty array if none are due.
    func surfaceItems(userId: String) async throws -> [AmenFollowUpItem] {
        let now = Date()
        let candidates = activeItems.filter { item in
            switch item.status {
            case .active:
                // Never-surfaced items: only eligible once notifyAfterDays has elapsed.
                if item.lastSurfacedAt == nil, let days = item.notifyAfterDays {
                    let dueDate = item.createdAt.addingTimeInterval(Double(days) * 86_400)
                    return dueDate <= now
                }
                // Already surfaced at least once: always eligible when active.
                return item.lastSurfacedAt != nil
            case .snoozed:
                // Re-eligible when snooze period has expired.
                guard let until = item.snoozedUntil else { return false }
                return until < now
            default:
                return false
            }
        }

        // ANTI-ENGAGEMENT: Never surface more than 3 follow-ups at once.
        let toSurface = Array(candidates.prefix(3))
        guard !toSurface.isEmpty else { return [] }

        // Update lastSurfacedAt for each item in Firestore and local state.
        let batch = db.batch()
        for item in toSurface {
            let ref = followUpsCollection(userId: userId).document(item.id)
            batch.updateData(["lastSurfacedAt": FieldValue.serverTimestamp()], forDocument: ref)
            // Also re-activate any that were snoozed and have expired.
            if item.status == .snoozed {
                batch.updateData(["status": FollowUpStatus.active.rawValue], forDocument: ref)
            }
        }
        try await batch.commit()

        // Reflect changes locally.
        let surfacedIds = Set(toSurface.map { $0.id })
        for index in activeItems.indices where surfacedIds.contains(activeItems[index].id) {
            activeItems[index].lastSurfacedAt = now
            if activeItems[index].status == .snoozed {
                activeItems[index].status = .active
                activeItems[index].snoozedUntil = nil
            }
        }

        return toSurface
    }

    // MARK: - Local Notification Scheduling

    // MARK: scheduleReminder

    /// Schedules a local (device-only) notification for a follow-up item.
    ///
    /// ANTI-ENGAGEMENT: Local notifications only. Never push, never badge-count increases.
    /// If notification permission is not granted, this function does nothing and does NOT
    /// request permission again — permission prompts must be initiated by a human action,
    /// never triggered silently by the platform.
    ///
    /// - Parameters:
    ///   - item: The follow-up item to remind about.
    ///   - schedule: A `FollowUpReminderSchedule` describing when and what to remind.
    /// - Throws: `UNNotificationRequest` construction errors only. Auth-denied silently noops.
    @discardableResult
    func scheduleReminder(for item: AmenFollowUpItem, schedule: FollowUpReminderSchedule? = nil) throws -> String? {
        let center = UNUserNotificationCenter.current()

        // Resolve the schedule: use supplied value or derive from item.
        let resolvedSchedule: FollowUpReminderSchedule
        if let schedule = schedule {
            resolvedSchedule = schedule
        } else if let days = item.notifyAfterDays {
            resolvedSchedule = FollowUpReminderSchedule(
                itemId: item.id,
                triggerDate: item.createdAt.addingTimeInterval(Double(days) * 86_400),
                message: item.itemType.gentleReminderMessage
            )
        } else {
            return nil  // No trigger date — nothing to schedule.
        }

        // Check authorization status synchronously-ish via a detached check.
        // We use a local flag rather than awaiting because this method is synchronous
        // (called from non-async contexts). If status is unknown or denied we silently skip.
        var shouldSchedule = false
        let semaphore = DispatchSemaphore(value: 0)
        center.getNotificationSettings { settings in
            shouldSchedule = settings.authorizationStatus == .authorized ||
                             settings.authorizationStatus == .provisional
            semaphore.signal()
        }
        semaphore.wait()

        guard shouldSchedule else {
            // ANTI-ENGAGEMENT: Not granted — silently skip. Never re-prompt from here.
            return nil
        }

        let content = UNMutableNotificationContent()
        content.title = item.objectTitle
        content.body = resolvedSchedule.message
        // ANTI-ENGAGEMENT: No badge manipulation.
        content.badge = nil
        // Sound: use default so it respects the user's Focus / Do Not Disturb settings.
        content.sound = .default
        // Thread the notification under the item id so it groups cleanly.
        content.threadIdentifier = "amenFollowUp-\(resolvedSchedule.itemId)"

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: resolvedSchedule.triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: resolvedSchedule.itemId,
            content: content,
            trigger: trigger
        )

        center.add(request) { _ in
            // Error is intentionally swallowed — notification scheduling is best-effort.
            // The item lives in Firestore regardless; the notification is a convenience only.
        }

        return resolvedSchedule.itemId
    }

    // MARK: cancelReminder

    /// Cancels any pending local notification for the given follow-up item id.
    ///
    /// Safe to call even if no notification was scheduled.
    func cancelReminder(for itemId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [itemId]
        )
    }

    // MARK: - Private Helpers

    /// Encodes an `AmenFollowUpItem` to a Firestore-compatible `[String: Any]` dictionary.
    /// Dates are stored as `Timestamp` objects (Firestore native).
    private func encodeItem(_ item: AmenFollowUpItem) throws -> [String: Any] {
        var payload: [String: Any] = [
            "id":            item.id,
            "userId":        item.userId,
            "itemType":      item.itemType.rawValue,
            "objectRef":     item.objectRef,
            "objectTitle":   item.objectTitle,
            "status":        item.status.rawValue,
            "createdAt":     FieldValue.serverTimestamp(),
            "isPrivate":     item.isPrivate,
            "isDeleted":     false
        ]
        if let preview = item.objectPreview   { payload["objectPreview"]   = preview }
        if let days    = item.notifyAfterDays { payload["notifyAfterDays"] = days }
        if let note    = item.userNote        { payload["userNote"]        = note }
        return payload
    }

    /// Decodes a `DocumentSnapshot` into an `AmenFollowUpItem`.
    /// Returns `nil` for documents with missing required fields.
    private func decodeItem(from doc: DocumentSnapshot) throws -> AmenFollowUpItem? {
        guard let data = doc.data() else { return nil }

        guard
            let id          = data["id"]          as? String,
            let userId      = data["userId"]       as? String,
            let itemTypeRaw = data["itemType"]     as? String,
            let itemType    = FollowUpItemType(rawValue: itemTypeRaw),
            let objectRef   = data["objectRef"]    as? String,
            let objectTitle = data["objectTitle"]  as? String,
            let statusRaw   = data["status"]       as? String,
            let status      = FollowUpStatus(rawValue: statusRaw)
        else { return nil }

        func date(from key: String) -> Date? {
            if let ts = data[key] as? Timestamp { return ts.dateValue() }
            if let ti = data[key] as? TimeInterval { return Date(timeIntervalSince1970: ti) }
            return nil
        }

        let createdAt = date(from: "createdAt") ?? Date()

        return AmenFollowUpItem(
            id: id,
            userId: userId,
            itemType: itemType,
            objectRef: objectRef,
            objectTitle: objectTitle,
            objectPreview: data["objectPreview"]   as? String,
            status: status,
            createdAt: createdAt,
            lastSurfacedAt: date(from: "lastSurfacedAt"),
            resolvedAt: date(from: "resolvedAt"),
            snoozedUntil: date(from: "snoozedUntil"),
            notifyAfterDays: data["notifyAfterDays"] as? Int,
            userNote: data["userNote"] as? String,
            isPrivate: (data["isPrivate"] as? Bool) ?? true
        )
    }
}
