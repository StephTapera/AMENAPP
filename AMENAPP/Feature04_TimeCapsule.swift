//
//  Feature04_TimeCapsule.swift
//  AMENAPP
//
//  Time Capsule Message — schedule a message for future delivery.
//  Sealed in Firestore; Cloud Function unseals when deliverAt is reached.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Model

struct TimeCapsuleMessage: Identifiable {
    let id: String
    let senderId: String
    let sealedContent: String  // XOR-obfuscated on write, cleared on delivery
    let deliverAt: Date
    var status: String          // "sealed" | "delivered"
    let createdAt: Date
}

// MARK: - XOR obfuscation (not cryptographic — just basic obfuscation)

private func xorObfuscate(_ text: String, seed: Int) -> String {
    let bytes = Array(text.utf8)
    let key   = UInt8(seed & 0xFF)
    let xored = bytes.map { $0 ^ key }
    return Data(xored).base64EncodedString()
}

// MARK: - Manager

final class TimeCapsuleManager: ObservableObject {
    static let shared = TimeCapsuleManager()

    @Published var selectedDeliverAt: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @Published var showDatePicker: Bool = false

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Send

    /// Writes the message to Firestore as a sealed time capsule.
    func sealAndSend(
        conversationId: String,
        messageText: String,
        recipientId: String,
        deliverAt: Date
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let seed = Int(deliverAt.timeIntervalSince1970)
        let sealed = xorObfuscate(messageText, seed: seed)

        let data: [String: Any] = [
            "senderId":      uid,
            "recipientId":   recipientId,
            "sealedContent": sealed,
            "text":          "",           // Empty until delivered
            "isTimeCapsule": true,
            "deliverAt":     Timestamp(date: deliverAt),
            "status":        "sealed",
            "createdAt":     FieldValue.serverTimestamp(),
        ]

        try await db
            .collection("conversations").document(conversationId)
            .collection("messages")
            .addDocument(data: data)

        dlog("✅ [TimeCapsule] Sealed message queued for delivery at \(deliverAt)")
    }

    // MARK: - Listen for delivery status changes

    /// Returns a listener on a specific message doc so the UI can animate
    /// the "envelope opening" when status changes to "delivered".
    func listenToMessage(
        conversationId: String,
        messageId: String,
        onChange: @escaping (String) -> Void  // delivers new `status`
    ) -> ListenerRegistration {
        return db
            .collection("conversations").document(conversationId)
            .collection("messages").document(messageId)
            .addSnapshotListener { snap, _ in
                guard let status = snap?.data()?["status"] as? String else { return }
                DispatchQueue.main.async { onChange(status) }
            }
    }
}
