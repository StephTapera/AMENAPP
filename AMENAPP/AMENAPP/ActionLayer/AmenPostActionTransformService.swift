// AmenPostActionTransformService.swift
// AMEN App — Action Layer: Firestore-backed service + local notification scheduling
//
// App Store compliance notes:
//  • Permission is requested lazily only when the user saves a reminder/event.
//  • If the user has denied permission we surface an actionable Settings deep-link,
//    never silently swallow the failure.
//  • Notification identifiers are namespaced by actionId to allow future cancellation.

import Foundation
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

// MARK: - Persisted Action Record

struct AmenPersistedAction: Identifiable {
    let id: String
    let type: String
    let postId: String
    let postText: String
    let authorName: String
    let scheduledDate: Date?
    let title: String?
    let createdAt: Date
    let status: String
}

// MARK: - AmenPostActionTransformService

@Observable
@MainActor
final class AmenPostActionTransformService {
    static let shared = AmenPostActionTransformService()

    private(set) var isSaving = false

    /// Set to true when the user has explicitly denied notification permission
    /// and we need to surface a Settings deep-link in the UI.
    private(set) var notificationPermissionDenied = false

    private let db = Firestore.firestore()
    private let userDefaultsKey = "amenPendingTransformActions"
    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Write + Schedule

    /// Writes the action to Firestore and, for reminder/event, schedules a
    /// local UNNotificationRequest. Throws on Firestore failure; notification
    /// scheduling failure is surfaced via `notificationPermissionDenied` flag
    /// rather than throwing so the save still succeeds.
    func transformPost(_ request: AmenPostTransformRequest) async throws {
        isSaving = true
        defer { isSaving = false }

        guard let uid = Auth.auth().currentUser?.uid else {
            throw AmenActionError.notAuthenticated
        }

        let actionId = UUID().uuidString
        let title = request.customTitle
            ?? "\(request.action.displayName): \(request.postText.prefix(60))"

        var payload: [String: Any] = [
            "type":        request.action.rawValue,
            "postId":      request.postId,
            "postText":    request.postText,
            "authorName":  request.authorName,
            "title":       title,
            "createdAt":   Timestamp(date: Date()),
            "status":      "pending"
        ]
        if let date = request.scheduledDate {
            payload["scheduledDate"] = Timestamp(date: date)
        }
        if let assignee = request.assignedTo {
            payload["assignedTo"] = assignee
        }

        do {
            try await db
                .collection("users")
                .document(uid)
                .collection("actions")
                .document(actionId)
                .setData(payload)
        } catch {
            appendToUserDefaults(payload: payload, actionId: actionId)
            throw error
        }

        // Schedule local notification for reminder + event actions.
        if (request.action == .reminder || request.action == .event),
           let fireDate = request.scheduledDate,
           fireDate > Date() {
            await scheduleLocalNotification(
                identifier: "amen.action.\(actionId)",
                title: title,
                body: "From @\(request.authorName)",
                date: fireDate
            )
        }
    }

    // MARK: - Read

    func pendingActions(for userId: String) async -> [AmenPostTransformAction] {
        do {
            let snapshot = try await db
                .collection("users")
                .document(userId)
                .collection("actions")
                .whereField("status", isEqualTo: "pending")
                .getDocuments()

            return snapshot.documents.compactMap { doc in
                guard let raw = doc.data()["type"] as? String else { return nil }
                return AmenPostTransformAction(rawValue: raw)
            }
        } catch {
            return []
        }
    }

    // MARK: - Local notification scheduling

    private func scheduleLocalNotification(
        identifier: String,
        title: String,
        body: String,
        date: Date
    ) async {
        let granted = await ensureNotificationPermission()
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Increment app badge by 1 when the notification fires.
        content.badge = 1

        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        components.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
        } catch {
            // Notification scheduling failed but Firestore write already succeeded.
            // Non-fatal: user will still see the action in their list.
        }
    }

    /// Checks current authorization status and requests permission if not yet
    /// determined. Returns true if notifications are (or become) authorized.
    /// Sets `notificationPermissionDenied = true` if the user has denied.
    private func ensureNotificationPermission() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationPermissionDenied = false
            return true
        case .notDetermined:
            do {
                let granted = try await notificationCenter.requestAuthorization(
                    options: [.alert, .sound, .badge]
                )
                notificationPermissionDenied = !granted
                return granted
            } catch {
                return false
            }
        case .denied:
            notificationPermissionDenied = true
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Cancel a scheduled notification (e.g. if user deletes the action)

    func cancelNotification(actionId: String) {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: ["amen.action.\(actionId)"]
        )
    }

    // MARK: - UserDefaults fallback

    private func appendToUserDefaults(payload: [String: Any], actionId: String) {
        var existing = (UserDefaults.standard.array(forKey: userDefaultsKey) as? [[String: Any]]) ?? []
        var entry = payload
        entry["id"] = actionId
        existing.append(entry)
        UserDefaults.standard.set(existing, forKey: userDefaultsKey)
    }
}

// MARK: - Error

enum AmenActionError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to save actions."
        }
    }
}
