import Foundation
import FirebaseFirestore
import FirebaseAuth
import CryptoKit

// MARK: - ChannelService
//
// Implements the routing logic from Diagram 1:
//   group → communal
//   1:1 / discipleship + both adults → sacred
//   1:1 / discipleship + either isMinor → monitored (forced communal, never E2E)
//
// Communal message flow:
//   Client writes with isDelivered=false → Guardian Cloud Function classifies →
//   Cloud Function sets isDelivered + guardianDecision → listener shows message.
//
// Sacred message flow:
//   Client encrypts locally → writes ciphertext → other client decrypts.
//   No Cloud Function ever touches sacredMessages or keyMaterial subcollections.

@MainActor
final class ChannelService: ObservableObject {
    static let shared = ChannelService()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Channel Resolution

    func openOrCreateDirectChannel(with otherUid: String) async throws -> AmenChannel {
        guard let uid = Auth.auth().currentUser?.uid else { throw ChannelError.notAuthenticated }
        let myIsMinor = try await fetchIsMinor(uid: uid)
        let theirIsMinor = try await fetchIsMinor(uid: otherUid)
        // SAFETY RULE: if either participant is a minor, channel MUST be monitored. No override.
        let channelClass: ChannelClass = (myIsMinor || theirIsMinor) ? .monitored : .sacred
        let sorted = [uid, otherUid].sorted()
        if let existing = try await findDirectChannel(sortedUids: sorted) { return existing }
        return try await createDirectChannel(sortedUids: sorted, channelClass: channelClass, otherUid: otherUid)
    }

    func openOrCreateGroupChannel(groupId: String) async throws -> AmenChannel {
        if let existing = try await findGroupChannel(groupId: groupId) { return existing }
        let ref = db.collection("channels").document()
        var ch = AmenChannel(channelClass: .communal, participantUids: [], groupId: groupId,
                             discipleshipPairId: nil, createdAt: Date())
        try ref.setData(from: ch)
        ch.id = ref.documentID
        return ch
    }

    // MARK: - Communal Send

    func sendCommunalMessage(channelId: String, text: String) async throws -> CommunalMessage {
        guard let uid = Auth.auth().currentUser?.uid else { throw ChannelError.notAuthenticated }
        let ref = db.collection("channels").document(channelId).collection("messages").document()
        var msg = CommunalMessage(channelId: channelId, senderId: uid, text: text, createdAt: Date(),
                                  isDelivered: false, guardianDecision: nil,
                                  supportResourcesAttached: false, prayerRequestId: nil, scriptureRefs: [])
        try ref.setData(from: msg)
        try await db.collection("channels").document(channelId).updateData([
            "lastMessageAt": FieldValue.serverTimestamp()
        ])
        msg.id = ref.documentID
        return msg
    }

    // MARK: - Sacred Send

    func sendSacredMessage(channelId: String, plaintext: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw ChannelError.notAuthenticated }
        let key = try await resolveConversationKey(channelId: channelId, uid: uid)
        let sealed = try SacredChannelCrypto.seal(plaintext, with: key)
        let ref = db.collection("channels").document(channelId).collection("sacredMessages").document()
        var msg = SacredMessage(channelId: channelId, senderId: uid,
                                ciphertextBase64: sealed.ciphertext.base64EncodedString(),
                                nonceBase64: sealed.nonce.base64EncodedString(),
                                tagBase64: sealed.tag.base64EncodedString(),
                                createdAt: Date())
        try ref.setData(from: msg)
        // Intentionally no lastMessagePreview — server cannot read sacred content
        try await db.collection("channels").document(channelId).updateData([
            "lastMessageAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Decryption

    func decryptMessage(_ message: SacredMessage) throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw ChannelError.notAuthenticated }
        guard let key = SacredChannelCrypto.cachedConversationKey(channelId: message.channelId, uid: uid) else {
            throw ChannelError.keyMaterialMissing
        }
        guard let ct = Data(base64Encoded: message.ciphertextBase64),
              let nonce = Data(base64Encoded: message.nonceBase64),
              let tag = Data(base64Encoded: message.tagBase64) else {
            throw ChannelError.invalidCiphertext
        }
        return try SacredChannelCrypto.open(SealedPayload(ciphertext: ct, nonce: nonce, tag: tag), with: key)
    }

    // MARK: - Listeners

    func listenCommunalMessages(channelId: String, handler: @escaping ([CommunalMessage]) -> Void) -> ListenerRegistration {
        db.collection("channels").document(channelId).collection("messages")
            .whereField("isDelivered", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { snap, _ in
                let sorted = (snap?.documents.compactMap { try? $0.data(as: CommunalMessage.self) } ?? [])
                    .sorted { $0.createdAt < $1.createdAt }
                handler(sorted)
            }
    }

    func listenSacredMessages(channelId: String, handler: @escaping ([SacredMessage]) -> Void) -> ListenerRegistration {
        db.collection("channels").document(channelId).collection("sacredMessages")
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { snap, _ in
                let sorted = (snap?.documents.compactMap { try? $0.data(as: SacredMessage.self) } ?? [])
                    .sorted { $0.createdAt < $1.createdAt }
                handler(sorted)
            }
    }

    // MARK: - Identity Key Bootstrap (call at account creation or first sign-in)

    func bootstrapIdentityKeyIfNeeded() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if (try? SacredChannelCrypto.loadIdentityPrivateKey(uid: uid)) != nil { return }
        let privateKey = SacredChannelCrypto.generateIdentityKeyPair()
        try SacredChannelCrypto.storeIdentityPrivateKey(privateKey, uid: uid)
        let pubBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
        try await db.collection("users").document(uid).updateData(["sacredPublicKey": pubBase64])
    }

    // MARK: - Private Helpers

    private func findDirectChannel(sortedUids: [String]) async throws -> AmenChannel? {
        let snap = try await db.collection("channels")
            .whereField("participantUids", isEqualTo: sortedUids)
            .limit(to: 1).getDocuments()
        return snap.documents.compactMap { try? $0.data(as: AmenChannel.self) }.first
    }

    private func findGroupChannel(groupId: String) async throws -> AmenChannel? {
        let snap = try await db.collection("channels")
            .whereField("groupId", isEqualTo: groupId)
            .limit(to: 1).getDocuments()
        return snap.documents.compactMap { try? $0.data(as: AmenChannel.self) }.first
    }

    private func createDirectChannel(sortedUids: [String], channelClass: ChannelClass, otherUid: String) async throws -> AmenChannel {
        let ref = db.collection("channels").document()
        var ch = AmenChannel(channelClass: channelClass, participantUids: sortedUids,
                             groupId: nil, discipleshipPairId: nil, createdAt: Date())
        try ref.setData(from: ch)
        ch.id = ref.documentID
        if channelClass == .sacred, let uid = Auth.auth().currentUser?.uid {
            try await bootstrapSacredKeys(channelId: ref.documentID, myUid: uid, otherUid: otherUid)
        }
        return ch
    }

    private func bootstrapSacredKeys(channelId: String, myUid: String, otherUid: String) async throws {
        let conversationKey = SacredChannelCrypto.generateConversationKey()
        let myPriv = try SacredChannelCrypto.loadIdentityPrivateKey(uid: myUid)
        let myWrapped = try SacredChannelCrypto.wrapConversationKey(conversationKey, for: myPriv.publicKey)
        SacredChannelCrypto.cacheConversationKey(conversationKey, channelId: channelId, uid: myUid)

        var entries: [[String: Any]] = [["uid": myUid, "wrappedKey": myWrapped.base64EncodedString()]]

        let theirDoc = try await db.collection("users").document(otherUid).getDocument()
        if let pubBase64 = theirDoc.data()?["sacredPublicKey"] as? String,
           let pubData = Data(base64Encoded: pubBase64),
           let theirPub = try? P256.KeyAgreement.PublicKey(rawRepresentation: pubData) {
            let theirWrapped = try SacredChannelCrypto.wrapConversationKey(conversationKey, for: theirPub)
            entries.append(["uid": otherUid, "wrappedKey": theirWrapped.base64EncodedString()])
        }

        try await db.collection("channels").document(channelId)
            .collection("keyMaterial").document("keys")
            .setData(["wrappedKeys": entries])
    }

    private func resolveConversationKey(channelId: String, uid: String) async throws -> SymmetricKey {
        if let cached = SacredChannelCrypto.cachedConversationKey(channelId: channelId, uid: uid) {
            return cached
        }
        let keyDoc = try await db.collection("channels").document(channelId)
            .collection("keyMaterial").document("keys").getDocument()
        guard let entries = keyDoc.data()?["wrappedKeys"] as? [[String: Any]],
              let mine = entries.first(where: { ($0["uid"] as? String) == uid }),
              let base64 = mine["wrappedKey"] as? String,
              let wrapped = Data(base64Encoded: base64) else {
            throw ChannelError.keyMaterialMissing
        }
        let priv = try SacredChannelCrypto.loadIdentityPrivateKey(uid: uid)
        let key = try SacredChannelCrypto.unwrapConversationKey(wrapped, with: priv)
        SacredChannelCrypto.cacheConversationKey(key, channelId: channelId, uid: uid)
        return key
    }

    private func fetchIsMinor(uid: String) async throws -> Bool {
        let doc = try await db.collection("users").document(uid).getDocument()
        return doc.data()?["isMinor"] as? Bool ?? false
    }
}

// MARK: - ChannelError

enum ChannelError: LocalizedError {
    case notAuthenticated, keyMaterialMissing, invalidCiphertext, channelClassMismatch

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Please sign in to continue."
        case .keyMaterialMissing: return "Encryption key not available. Try opening the conversation again."
        case .invalidCiphertext: return "Message could not be decrypted."
        case .channelClassMismatch: return "Channel type mismatch."
        }
    }
}
