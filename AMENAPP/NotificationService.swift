//
//  NotificationService.swift
//  AMENAPP
//
//  Core notification service, models, and Firestore listener.
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - NotificationActor

struct NotificationActor: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let username: String
    let profileImageURL: String?
}

// MARK: - AppNotification

struct AppNotification: Identifiable, Equatable {

    // MARK: Type

    enum NotificationType: String, Codable, Equatable, CaseIterable {
        case follow                = "follow"
        case followRequestAccepted = "followRequestAccepted"
        case mention               = "mention"
        case comment               = "comment"
        case reply                 = "reply"
        case repost                = "repost"
        case amen                  = "amen"
        case prayerReminder        = "prayerReminder"
        case prayerAnswered        = "prayerAnswered"
        case prayerSupported       = "prayerSupported"
        case churchNoteShared      = "churchNoteShared"
        case churchNoteReplied     = "churchNoteReplied"
        case message               = "message"
        case messageRequest        = "messageRequest"
        case messageRequestAccepted = "messageRequestAccepted"
        case actionThreadInvite    = "actionThreadInvite"
        case actionThreadUpdate    = "actionThreadUpdate"
        case actionThreadReminder  = "actionThreadReminder"
        case unknown               = "unknown"

        var actionText: String {
            switch self {
            case .follow:                  return "followed you"
            case .followRequestAccepted:   return "accepted your follow request"
            case .mention:                 return "mentioned you"
            case .comment:                 return "commented on your post"
            case .reply:                   return "replied to your comment"
            case .repost:                  return "reposted your post"
            case .amen:                    return "said amen to your post"
            case .prayerReminder:          return "reminded you to pray"
            case .prayerAnswered:          return "marked a prayer as answered"
            case .prayerSupported:         return "prayed for you"
            case .churchNoteShared:        return "shared church notes with you"
            case .churchNoteReplied:       return "replied to your church notes"
            case .message:                 return "sent you a message"
            case .messageRequest:          return "sent you a message request"
            case .messageRequestAccepted:  return "accepted your message request"
            case .actionThreadInvite:      return "invited you to a support thread"
            case .actionThreadUpdate:      return "updated a support thread"
            case .actionThreadReminder:    return "has a support thread update"
            case .unknown:                 return "interacted with your content"
            }
        }

        var trustRank: Int {
            switch self {
            case .actionThreadInvite:      return 11
            case .mention:                 return 10
            case .comment:                 return 9
            case .reply, .message:         return 8
            case .messageRequestAccepted:  return 7
            case .follow, .followRequestAccepted, .messageRequest: return 7
            case .repost:                  return 6
            case .prayerReminder, .prayerAnswered: return 5
            case .prayerSupported, .churchNoteShared, .churchNoteReplied: return 4
            case .actionThreadUpdate:      return 4
            case .actionThreadReminder:    return 3
            case .amen:                    return 3
            case .unknown:                 return 1
            }
        }
    }

    // MARK: Properties

    var id: String?
    var type: NotificationType
    var actorId: String?
    var actorName: String?
    var actorUsername: String?
    var actorProfileImageURL: String?
    var actorCount: Int?
    var actors: [NotificationActor]?
    var postId: String?
    var conversationId: String?
    var commentId: String?
    var prayerId: String?
    var noteId: String?
    var groupId: String?
    var read: Bool
    var seenAt: Timestamp?
    var createdAt: Timestamp
    var updatedAt: Timestamp?
    var priority: Int?
    var commentText: String?

    var actionText: String { type.actionText }

    static func == (lhs: AppNotification, rhs: AppNotification) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type && lhs.read == rhs.read
    }

    // MARK: Firestore Init

    init(document: QueryDocumentSnapshot) {
        let d = document.data()
        self.id = document.documentID
        let typeRaw = d["type"] as? String ?? "unknown"
        self.type = NotificationType(rawValue: typeRaw) ?? .unknown
        self.actorId               = d["actorId"] as? String
        self.actorName             = d["actorName"] as? String
        self.actorUsername         = d["actorUsername"] as? String
        self.actorProfileImageURL  = d["actorProfileImageURL"] as? String
        self.actorCount            = d["actorCount"] as? Int
        self.postId                = d["postId"] as? String
        self.conversationId        = d["conversationId"] as? String
        self.commentId             = d["commentId"] as? String
        self.prayerId              = d["prayerId"] as? String
        self.noteId                = d["noteId"] as? String
        self.groupId               = d["groupId"] as? String
        self.read                  = d["read"] as? Bool ?? false
        self.seenAt                = d["seenAt"] as? Timestamp
        self.createdAt             = d["createdAt"] as? Timestamp ?? Timestamp(date: Date())
        self.updatedAt             = d["updatedAt"] as? Timestamp
        self.priority              = d["priority"] as? Int
        self.commentText           = d["commentText"] as? String

        if let actorsData = d["actors"] as? [[String: Any]] {
            self.actors = actorsData.compactMap { a in
                guard let id = a["id"] as? String, let name = a["name"] as? String else { return nil }
                return NotificationActor(
                    id: id, name: name,
                    username: a["username"] as? String ?? "",
                    profileImageURL: a["profileImageURL"] as? String
                )
            }
        } else {
            self.actors = nil
        }
    }
}

// MARK: - NotificationService

@MainActor
final class NotificationService: ObservableObject {

    static let shared = NotificationService()

    @Published var notifications: [AppNotification] = []
    @Published var unreadCount: Int = 0
    @Published var isLoading: Bool = false

    // Non-private so NotificationServiceExtensions can access it
    var db: Firestore = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Listener

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard listener == nil else { return }
        isLoading = true
        listener = db.collection("users").document(uid)
            .collection("notifications")
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    dlog("❌ NotificationService listener error: \(error)")
                    self.isLoading = false
                    return
                }
                guard let snapshot else { return }
                let parsed = snapshot.documents.map { AppNotification(document: $0) }
                self.notifications = parsed
                self.unreadCount = parsed.filter { !$0.read }.count
                self.isLoading = false
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        notifications = []
        unreadCount = 0
        isLoading = false
    }

    func refresh() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("notifications")
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
                .getDocuments()
            let parsed = snapshot.documents.map { AppNotification(document: $0) }
            notifications = parsed
            unreadCount = parsed.filter { !$0.read }.count
        } catch {
            dlog("❌ NotificationService.refresh error: \(error)")
        }
    }

    // MARK: - Read State

    func markAsRead(_ notificationId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid)
            .collection("notifications")
            .document(notificationId)
            .updateData(["read": true])
        if let idx = notifications.firstIndex(where: { $0.id == notificationId }) {
            notifications[idx].read = true
            unreadCount = notifications.filter { !$0.read }.count
        }
    }

    func markAllAsRead() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let unread = notifications.filter { !$0.read }
        guard !unread.isEmpty else { return }
        let chunks = stride(from: 0, to: unread.count, by: 500).map {
            Array(unread[$0..<min($0 + 500, unread.count)])
        }
        for chunk in chunks {
            let batch = db.batch()
            for n in chunk {
                guard let nid = n.id else { continue }
                let ref = db.collection("users").document(uid)
                    .collection("notifications").document(nid)
                batch.updateData(["read": true], forDocument: ref)
            }
            try await batch.commit()
        }
        for idx in notifications.indices { notifications[idx].read = true }
        unreadCount = 0
    }

    func markAllAsReadViaQuery() async {
        try? await markAllAsRead()
    }

    // MARK: - Deletion

    func deleteNotification(_ notificationId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid)
            .collection("notifications")
            .document(notificationId)
            .delete()
        notifications.removeAll { $0.id == notificationId }
        unreadCount = notifications.filter { !$0.read }.count
    }

    func deleteAllRead() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let read = notifications.filter { $0.read }
        guard !read.isEmpty else { return }
        let batch = db.batch()
        for n in read {
            guard let nid = n.id else { continue }
            let ref = db.collection("users").document(uid)
                .collection("notifications").document(nid)
            batch.deleteDocument(ref)
        }
        try await batch.commit()
        notifications.removeAll { $0.read }
        unreadCount = notifications.filter { !$0.read }.count
    }

    // Accessible from NotificationServiceExtensions.swift
    func removeNotifications(where predicate: (AppNotification) -> Bool) {
        notifications.removeAll(where: predicate)
        unreadCount = notifications.filter { !$0.read }.count
    }

    // MARK: - Mention Notifications

    func sendMentionNotifications(
        mentions: [String],
        actorId: String,
        actorName: String,
        actorUsername: String?,
        postId: String,
        contentType: String
    ) async {
        for userId in mentions {
            guard userId != actorId else { continue }
            let docId = "mention_\(actorId)_\(postId)_\(userId)"
            let data: [String: Any] = [
                "type": AppNotification.NotificationType.mention.rawValue,
                "actorId": actorId,
                "actorName": actorName,
                "actorUsername": actorUsername as Any,
                "postId": postId,
                "read": false,
                "createdAt": Timestamp(date: Date())
            ]
            do {
                try await db.collection("users").document(userId)
                    .collection("notifications").document(docId).setData(data, merge: true)
            } catch {
                dlog("❌ sendMentionNotifications error for \(userId): \(error)")
            }
        }
    }

    // MARK: - Church Note Notifications

    func sendChurchNoteSharedNotifications(
        noteId: String,
        noteTitle: String,
        recipientIds: [String],
        sharerId: String,
        sharerName: String,
        sharerUsername: String?
    ) async {
        for userId in recipientIds {
            guard userId != sharerId else { continue }
            let docId = "churchnote_\(sharerId)_\(noteId)_\(userId)"
            let data: [String: Any] = [
                "type": AppNotification.NotificationType.churchNoteShared.rawValue,
                "actorId": sharerId,
                "actorName": sharerName,
                "actorUsername": sharerUsername as Any,
                "postId": noteId,
                "noteId": noteId,
                "read": false,
                "createdAt": Timestamp(date: Date())
            ]
            do {
                try await db.collection("users").document(userId)
                    .collection("notifications").document(docId).setData(data, merge: true)
            } catch {
                dlog("❌ sendChurchNoteSharedNotifications error for \(userId): \(error)")
            }
        }
    }

    // MARK: - Analytics

    func recordInboxOpened() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "event": "inbox_opened",
            "uid": uid,
            "timestamp": FieldValue.serverTimestamp()
        ]
        do {
            try await db.collection("users").document(uid)
                .collection("analytics").addDocument(data: data)
        } catch {
            dlog("❌ recordInboxOpened error: \(error)")
        }
    }
}
