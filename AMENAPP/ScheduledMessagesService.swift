//
//  ScheduledMessagesService.swift
//  AMENAPP
//
//  Service that manages Schedule Reply messages.
//
//  Architecture:
//  - Client writes to users/{uid}/scheduledMessages/{idempotencyKey}
//  - A Cloud Function (scheduleReplyDispatcher) polls / listens for messages
//    where scheduledAt <= now AND status == "scheduled", then:
//      1. Atomically marks status = "sending" (prevents duplicate dispatch)
//      2. Writes the message to conversations/{id}/messages
//      3. Marks status = "sent" or "failed"
//  - Client listens to its own scheduledMessages for UI state.
//
//  Idempotency: document ID == idempotencyKey, so concurrent retries are safe.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
final class ScheduledMessagesService: ObservableObject {

    static let shared = ScheduledMessagesService()

    @Published private(set) var scheduledMessages: [ScheduledMessage] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Lifecycle

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = db
            .collection("users").document(uid)
            .collection("scheduledMessages")
            .whereField("status", isEqualTo: ScheduledMessageStatus.scheduled.rawValue)
            .order(by: "scheduledAt")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot else { return }
                Task { @MainActor in
                    self.scheduledMessages = snapshot.documents.compactMap {
                        try? $0.data(as: ScheduledMessage.self)
                    }
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        scheduledMessages = []
    }

    // MARK: - Schedule a message

    func scheduleMessage(
        conversationId: String,
        text: String,
        scheduledAt: Date,
        replyToMessageId: String? = nil,
        replyToText: String? = nil,
        replyToAuthorName: String? = nil
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ScheduledMessages", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        let displayName = Auth.auth().currentUser?.displayName ?? "User"

        let idempotencyKey = UUID().uuidString
        let msg = ScheduledMessage(
            localId: idempotencyKey,
            conversationId: conversationId,
            senderId: uid,
            senderName: displayName,
            text: text,
            scheduledAt: scheduledAt,
            createdAt: Date(),
            status: .scheduled,
            replyToMessageId: replyToMessageId,
            replyToText: replyToText,
            replyToAuthorName: replyToAuthorName,
            idempotencyKey: idempotencyKey
        )

        let ref = db
            .collection("users").document(uid)
            .collection("scheduledMessages").document(idempotencyKey)

        let encoded = try Firestore.Encoder().encode(msg)
        try await ref.setData(encoded)
        dlog("✅ [ScheduledMessages] Scheduled message \(idempotencyKey) for \(scheduledAt)")
    }

    // MARK: - Edit scheduled message text / time

    func editScheduledMessage(
        _ msg: ScheduledMessage,
        newText: String,
        newScheduledAt: Date? = nil
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid,
              uid == msg.senderId,
              msg.isEditable else {
            throw NSError(domain: "ScheduledMessages", code: 403, userInfo: [NSLocalizedDescriptionKey: "Cannot edit this message"])
        }

        let ref = db
            .collection("users").document(uid)
            .collection("scheduledMessages").document(msg.id)

        var updates: [String: Any] = [
            "text": newText,
            "editCount": (msg.editCount + 1)
        ]
        if let newDate = newScheduledAt {
            updates["scheduledAt"] = Timestamp(date: newDate)
        }
        try await ref.updateData(updates)
        dlog("✅ [ScheduledMessages] Edited scheduled message \(msg.id)")
    }

    // MARK: - Cancel scheduled message

    func cancelScheduledMessage(_ msg: ScheduledMessage) async throws {
        guard let uid = Auth.auth().currentUser?.uid,
              uid == msg.senderId,
              msg.isCancelable else { return }

        let ref = db
            .collection("users").document(uid)
            .collection("scheduledMessages").document(msg.id)
        try await ref.updateData(["status": ScheduledMessageStatus.canceled.rawValue])
        dlog("✅ [ScheduledMessages] Canceled scheduled message \(msg.id)")
    }

    // MARK: - Convenience: messages for a specific conversation

    func scheduledMessages(for conversationId: String) -> [ScheduledMessage] {
        scheduledMessages.filter { $0.conversationId == conversationId }
    }
}
