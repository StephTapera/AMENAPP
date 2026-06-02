// ONEThreadStore.swift
// ONE — Thread + Message Firestore persistence layer
// P1-C | E2E enforced: plaintext never written to Firestore.

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - ONEThreadStore

@MainActor
final class ONEThreadStore: ObservableObject {

    @Published private(set) var threads: [ONEThread] = []
    @Published private(set) var messages: [String: [ONEThreadMessage]] = [:]  // threadID → messages
    @Published private(set) var decryptedMessages: [String: [String: String]] = [:]  // threadID → msgID → plaintext

    private let db = Firestore.firestore()
    private var threadListener: ListenerRegistration?
    private var messageListeners: [String: ListenerRegistration] = [:]
    private let cryptoService = ONEKeyRatchetService()

    // MARK: - Thread Loading

    func startListeningToThreads(uid: String) {
        threadListener?.remove()
        threadListener = db.collection("one_threads")
            .whereField("participantUIDs", arrayContains: uid)
            .order(by: "lastActivityAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let documents = snapshot?.documents else { return }
                Task { @MainActor in
                    self.threads = documents.compactMap { doc in
                        try? doc.data(as: ONEThreadFirestoreDocument.self).toONEThread(id: doc.documentID)
                    }
                }
            }
    }

    func stopListeningToThreads() {
        threadListener?.remove()
        threadListener = nil
    }

    // MARK: - Message Loading (ciphertext only from Firestore)

    func startListeningToMessages(threadID: String) {
        guard messageListeners[threadID] == nil else { return }
        let listener = db.collection("one_threads")
            .document(threadID)
            .collection("messages")
            .order(by: "sentAt")
            .limit(toLast: 100)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let documents = snapshot?.documents else { return }
                Task { @MainActor in
                    let msgs = documents.compactMap { doc -> ONEThreadMessage? in
                        try? doc.data(as: ONEThreadMessageFirestoreDocument.self)
                            .toONEThreadMessage(id: doc.documentID, threadID: threadID)
                    }
                    self.messages[threadID] = msgs
                    await self.decryptBatch(msgs, threadID: threadID)
                }
            }
        messageListeners[threadID] = listener
    }

    func stopListeningToMessages(threadID: String) {
        messageListeners[threadID]?.remove()
        messageListeners.removeValue(forKey: threadID)
    }

    // MARK: - Send Message

    /// Encrypts plaintext client-side, uploads only ciphertext + metadata.
    func send(text: String, threadID: String, permissions: ONEMomentPermissions) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw ONEThreadStoreError.notAuthenticated }
        let plaintext = Data(text.utf8)
        let encrypted = try await cryptoService.encrypt(plaintext, threadID: threadID)

        let msgDoc: [String: Any] = [
            "threadID":        threadID,
            "senderUID":       uid,
            "ciphertext":      encrypted.ciphertext,
            "epoch":           encrypted.epoch,
            "senderDeviceID":  encrypted.senderDeviceID,
            "encryptionVersion": encrypted.encryptionVersion,
            "sentAt":          Timestamp(date: Date()),
            // Permission flags stored as metadata (not content)
            "forwardAllowed":  permissions.forwardAllowed,
            "saveAllowed":     permissions.saveAllowed,
            "quoteAllowed":    permissions.quoteAllowed,
            "reactAllowed":    permissions.reactAllowed
        ]

        try await db.collection("one_threads")
            .document(threadID)
            .collection("messages")
            .addDocument(data: msgDoc)

        // Update thread last activity
        try await db.collection("one_threads")
            .document(threadID)
            .updateData(["lastActivityAt": Timestamp(date: Date())])
    }

    // MARK: - Decrypt Batch (client-side, never uploaded)

    private func decryptBatch(_ msgs: [ONEThreadMessage], threadID: String) async {
        var decrypted = decryptedMessages[threadID] ?? [:]
        for msg in msgs where decrypted[msg.id] == nil {
            do {
                let payload = ONEEncryptedPayload(
                    ciphertext: msg.ciphertext,
                    epoch: msg.epoch,
                    senderDeviceID: msg.senderDeviceID,
                    encryptionVersion: msg.encryptionVersion
                )
                let plainData = try await cryptoService.decrypt(payload, threadID: threadID)
                decrypted[msg.id] = String(data: plainData, encoding: .utf8) ?? ""
            } catch {
                decrypted[msg.id] = "⚠️ Could not decrypt"
            }
        }
        decryptedMessages[threadID] = decrypted
    }
}

// MARK: - Firestore Document Helpers (decode only — no plaintext ever written)

private struct ONEThreadFirestoreDocument: Codable {
    var participantUIDs: [String]
    var encryptionVersion: String
    var isEphemeral: Bool
    var expiresAt: Timestamp?
    var consentOverrides: [String: [String: Bool]]?
    var createdAt: Timestamp
    var lastActivityAt: Timestamp
    var isArchived: Bool

    func toONEThread(id: String) throws -> ONEThread {
        ONEThread(
            id: id,
            participantUIDs: participantUIDs,
            encryptionVersion: encryptionVersion,
            isEphemeral: isEphemeral,
            expiresAt: expiresAt?.dateValue(),
            consentOverrides: [:],  // permission deserialisation wired in P1-G
            createdAt: createdAt.dateValue(),
            lastActivityAt: lastActivityAt.dateValue(),
            isArchived: isArchived
        )
    }
}

private struct ONEThreadMessageFirestoreDocument: Codable {
    var threadID: String
    var senderUID: String
    var ciphertext: Data
    var epoch: UInt64
    var senderDeviceID: String
    var encryptionVersion: String
    var sentAt: Timestamp
    var expiresAt: Timestamp?
    var isReported: Bool?

    func toONEThreadMessage(id: String, threadID: String) -> ONEThreadMessage {
        ONEThreadMessage(
            id: id,
            threadID: threadID,
            senderUID: senderUID,
            ciphertext: ciphertext,
            epoch: epoch,
            senderDeviceID: senderDeviceID,
            sentAt: sentAt.dateValue(),
            expiresAt: expiresAt?.dateValue(),
            isReported: isReported ?? false
        )
    }
}

// MARK: - Errors

enum ONEThreadStoreError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? { "You must be signed in to send messages." }
}
