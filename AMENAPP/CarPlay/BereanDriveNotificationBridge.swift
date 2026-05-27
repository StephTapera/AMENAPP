// BereanDriveNotificationBridge.swift
// AMEN — Berean Drive CarPlay
//
// Observes all CarPlay ↔ main-app notifications from BereanCarPlayCoordinator
// and routes them to the correct main-app handler.
//
// Owned by AppDelegate — lives for the app's full lifetime.
// Call register() once from application(_:didFinishLaunchingWithOptions:).

import Foundation
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

final class BereanDriveNotificationBridge: NSObject {

    private var observers: [NSObjectProtocol] = []

    func register() {
        let nc = NotificationCenter.default

        // CarPlay saved a church → persist to Firestore savedChurches collection
        observers.append(nc.addObserver(forName: .bereanDriveSaveChurch, object: nil, queue: .main) { note in
            Self.handleSaveChurch(note)
        })

        // CarPlay needs the user to look at their phone (sermon pick, message read, etc.)
        observers.append(nc.addObserver(forName: .bereanDriveHandoffToPhone, object: nil, queue: .main) { note in
            Self.handleHandoffToPhone(note)
        })

        // A dictated reply completed safety screening — relay to the active messaging view.
        // The active conversation screen observes .bereanDriveDictatedReplyDelivered directly.
        observers.append(nc.addObserver(forName: .bereanDriveDictatedReplyReady, object: nil, queue: .main) { note in
            NotificationCenter.default.post(
                name: .bereanDriveDictatedReplyDelivered,
                object: nil,
                userInfo: note.userInfo
            )
            dlog("💬 [CarPlayBridge] Dictated reply relayed — conversationId: \(note.userInfo?["conversationId"] ?? "n/a")")
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Save Church

    private static func handleSaveChurch(_ note: Notification) {
        guard
            let info = note.userInfo,
            let amenSpaceId = info["amenSpaceId"] as? String, !amenSpaceId.isEmpty,
            let churchName = info["churchName"] as? String,
            let userId = Auth.auth().currentUser?.uid
        else {
            dlog("⚠️ [CarPlayBridge] Save church skipped — missing amenSpaceId or unauthenticated")
            return
        }

        Task {
            do {
                try await Firestore.firestore()
                    .collection("users").document(userId)
                    .collection("savedChurches").document(amenSpaceId)
                    .setData(
                        ["name": churchName,
                         "savedAt": FieldValue.serverTimestamp(),
                         "source": "carplay"],
                        merge: true
                    )
                dlog("💾 [CarPlayBridge] Church saved from CarPlay: \(churchName)")
            } catch {
                dlog("⚠️ [CarPlayBridge] Church save failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Handoff to Phone

    private static func handleHandoffToPhone(_ note: Notification) {
        let reason = note.userInfo?["reason"] as? String ?? "detail"
        let content = UNMutableNotificationContent()
        content.title = "Berean Drive needs you"
        content.body = handoffMessage(for: reason)
        content.sound = .default
        content.interruptionLevel = .active

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "berean_drive_handoff_\(reason)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                dlog("⚠️ [CarPlayBridge] Handoff notification failed: \(error.localizedDescription)")
            }
        }
    }

    private static func handoffMessage(for reason: String) -> String {
        switch reason {
        case "sermon_selection": return "Pick a sermon in Amen, then return to CarPlay."
        case "message_reading":  return "Your messages are ready to review in Amen."
        case "content_review":   return "Berean has more detail waiting in the app."
        default:                 return "Open Amen for more details."
        }
    }
}

// MARK: - App-Internal Relay Notification Names

extension Notification.Name {
    /// Re-broadcast of bereanDriveDictatedReplyReady for the active conversation view.
    /// UserInfo: ["text": String, "conversationId": String]
    static let bereanDriveDictatedReplyDelivered = Notification.Name("bereanDriveDictatedReplyDelivered")
}
