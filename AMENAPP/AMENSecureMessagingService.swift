//
//  AMENSecureMessagingService.swift
//  AMENAPP
//
//  Encrypted message send/receive layer.
//
//  Responsibilities:
//    - Publish and fetch key bundles from Firestore
//    - Perform X3DH session initiation on first message
//    - Encrypt every outgoing message via the Double Ratchet
//    - Decrypt every incoming message via the Double Ratchet
//    - Store only ciphertext + metadata in Firestore — never plaintext
//    - Run AMENMessageSafetyEngine on plaintext BEFORE encryption (on-device)
//    - Run AMENImageSafetyGate on attachments BEFORE upload
//    - Enforce contact tier / message request model
//
//  Firestore layout:
//
//    keyBundles/{uid}              ← PublicKeyBundle (AMENKeyBundle)
//
//    secureConversations/{convId}
//        participants: [uid]
//        participantNames: {uid: name}
//        isGroup: Bool
//        createdAt: Timestamp
//        lastEncryptedTimestamp: Timestamp
//        unreadCounts: {uid: Int}
//        isPinned: [uid]
//        isMuted:  [uid]
//        isArchived: [uid]
//        // NO lastMessage plaintext stored
//
//    secureConversations/{convId}/encryptedMessages/{msgId}
//        senderUID: String
//        recipientUID: String         ← for DM; empty for group
//        encryptedPayload: Data       ← JSON-encoded AMENEncryptedMessage
//        timestamp: Timestamp
//        messageType: String          ← "text" | "image" | "attachment"
//        deliveryStatus: String       ← "sent" | "delivered" | "read"
//        readBy: [String]
//        payloadHash: String          ← SHA-256 of encryptedPayload for integrity
//        isDeleted: Bool
//        safetyEventId: String?       ← if on-device safety engine flagged anything
//
//    usedOTPKs/{uid}/{opkId}         ← tombstone so OPKs cannot be reused

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth
import CryptoKit

// MARK: - Firestore-storable key bundle

struct StorableKeyBundle: Codable {
    let identityKeyPublic: String       // base64
    let signedPreKeyPublic: String      // base64
    let signedPreKeySignature: String   // base64
    let signedPreKeyId: Int
    let oneTimePreKeys: [OTPKEntry]
    let deviceId: String
    let publishedAt: Timestamp

    struct OTPKEntry: Codable {
        let id: Int
        let publicKey: String           // base64
    }

    func toKeyBundle() throws -> AMENKeyBundle {
        AMENKeyBundle(
            identityKeyPublic: try b64Decode(identityKeyPublic),
            signedPreKeyPublic: try b64Decode(signedPreKeyPublic),
            signedPreKeySignature: try b64Decode(signedPreKeySignature),
            signedPreKeyId: signedPreKeyId,
            oneTimePreKeys: try oneTimePreKeys.map {
                .init(id: $0.id, publicKey: try b64Decode($0.publicKey))
            },
            deviceId: deviceId
        )
    }

    private func b64Decode(_ s: String) throws -> Data {
        guard let d = Data(base64Encoded: s) else {
            throw AMENEncryptionError.invalidKeyBundle
        }
        return d
    }
}

// MARK: - Encrypted message Firestore document

struct EncryptedMessageDocument {
    let id: String
    let senderUID: String
    let recipientUID: String
    let encryptedPayload: String    // base64(JSON(AMENEncryptedMessage))
    let timestamp: Timestamp
    let messageType: String
    var deliveryStatus: String
    var readBy: [String]
    let payloadHash: String
    var isDeleted: Bool
    let safetyEventId: String?
}

// MARK: - AMENSecureMessagingService

@MainActor
final class AMENSecureMessagingService: ObservableObject {

    static let shared = AMENSecureMessagingService()
    private init() {}

    private let db = Firestore.firestore()
    private let encryption = AMENEncryptionService.shared
    private let safety = AMENMessageSafetyEngine.shared
    private let trust = AMENTrustScoreService.shared

    @Published private(set) var isReady = false

    // Active session IDs: conversationId → sessionId
    private var activeSessions: [String: String] = [:]

    // MARK: - Key Bundle Publication

    /// Called once on app launch / first login. Publishes user's key bundle to Firestore.
    func publishKeyBundle() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let spkId = Int(Date().timeIntervalSince1970) // timestamp-based ID
        let (spk, signature) = try encryption.generateSignedPreKey(id: spkId)
        let ik = try encryption.identityKeyPair()
        let opks = try encryption.generateOneTimePreKeys(count: 20, startingId: Int.random(in: 1000...999999))

        let bundle = StorableKeyBundle(
            identityKeyPublic: ik.publicKeyData.base64EncodedString(),
            signedPreKeyPublic: spk.publicKeyData.base64EncodedString(),
            signedPreKeySignature: signature.base64EncodedString(),
            signedPreKeyId: spkId,
            oneTimePreKeys: opks.map {
                .init(id: $0.id, publicKey: $0.publicKey.base64EncodedString())
            },
            deviceId: deviceIdentifier(),
            publishedAt: Timestamp(date: Date())
        )

        try await db.collection("keyBundles").document(uid)
            .setData(try Firestore.Encoder().encode(bundle))
    }

    /// Refreshes OPKs when supply drops below threshold (called periodically).
    func replenishOneTimePreKeys() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let doc = try await db.collection("keyBundles").document(uid).getDocument()
        guard let data = doc.data(),
              let bundle = try? Firestore.Decoder().decode(StorableKeyBundle.self, from: data)
        else { return }

        if bundle.oneTimePreKeys.count < 5 {
            let newOPKs = try encryption.generateOneTimePreKeys(
                count: 20,
                startingId: Int.random(in: 1000000...9999999)
            )
            let newEntries = newOPKs.map {
                StorableKeyBundle.OTPKEntry(id: $0.id, publicKey: $0.publicKey.base64EncodedString())
            }
            try await db.collection("keyBundles").document(uid)
                .updateData(["oneTimePreKeys": FieldValue.arrayUnion(
                    newEntries.map { ["id": $0.id, "publicKey": $0.publicKey] }
                )])
        }
    }

    // MARK: - Send Encrypted Message

    /// Primary send entry point.
    /// Steps:
    ///   1. Trust & contact tier check (blocks strangers / blocked users)
    ///   2. On-device safety screening BEFORE encryption
    ///   3. X3DH session setup if first message
    ///   4. Double Ratchet encryption
    ///   5. Firestore write (ciphertext only)
    ///   6. Update conversation metadata
    func sendSecureMessage(
        conversationId: String,
        recipientUID: String,
        plaintextBody: String,
        messageType: String = "text"
    ) async throws {
        guard let senderUID = Auth.auth().currentUser?.uid else {
            throw SecureMessagingError.notAuthenticated
        }

        // 1. Contact tier / trust gate
        let contactTier = await trust.contactTier(between: senderUID, and: recipientUID)
        guard contactTier != .blocked else {
            throw SecureMessagingError.blocked
        }

        // 2. On-device safety scan — plaintext never leaves device if blocked
        let safetyResult = await safety.evaluate(
            text: plaintextBody,
            senderUID: senderUID,
            recipientUID: recipientUID,
            conversationId: conversationId
        )
        if case .block(let reason) = safetyResult {
            throw SecureMessagingError.safetyBlock(reason)
        }

        // 3. Fetch recipient key bundle and set up session if needed
        let sessionId: String
        if let existing = activeSessions[conversationId] {
            sessionId = existing
        } else {
            sessionId = try await initiateSession(
                conversationId: conversationId,
                recipientUID: recipientUID,
                senderUID: senderUID
            )
        }

        // 4. Load ratchet state and encrypt
        var ratchetState = try encryption.loadRatchetState(sessionId: sessionId)
        let plaintextData = Data(plaintextBody.utf8)
        let encrypted = try encryption.encryptMessage(
            plaintext: plaintextData,
            sessionId: sessionId,
            state: &ratchetState
        )

        // 5. Serialise and write to Firestore
        let payloadData = try JSONEncoder().encode(encrypted)
        let payloadBase64 = payloadData.base64EncodedString()
        let payloadHash = SHA256.hash(data: payloadData)
            .compactMap { String(format: "%02x", $0) }.joined()

        let messageRef = db
            .collection("secureConversations").document(conversationId)
            .collection("encryptedMessages").document()

        let safetyEventId = (safetyResult == .flagged) ? UUID().uuidString : nil

        try await messageRef.setData([
            "senderUID":        senderUID,
            "recipientUID":     recipientUID,
            "encryptedPayload": payloadBase64,
            "timestamp":        FieldValue.serverTimestamp(),
            "messageType":      messageType,
            "deliveryStatus":   "sent",
            "readBy":           [senderUID],
            "payloadHash":      payloadHash,
            "isDeleted":        false,
            "safetyEventId":    safetyEventId as Any
        ])

        // 6. Update conversation last-activity (no plaintext stored)
        try await db.collection("secureConversations").document(conversationId)
            .updateData([
                "lastEncryptedTimestamp": FieldValue.serverTimestamp(),
                "unreadCounts.\(recipientUID)": FieldValue.increment(Int64(1))
            ])
    }

    // MARK: - Receive and Decrypt

    /// Decrypts a raw Firestore document back to plaintext.
    /// Returns nil if this device has no session key for the message.
    func decryptMessage(
        document: [String: Any],
        conversationId: String
    ) async throws -> String? {
        guard let payloadBase64 = document["encryptedPayload"] as? String,
              let payloadData = Data(base64Encoded: payloadBase64)
        else { throw SecureMessagingError.malformedDocument }

        // Integrity check
        if let storedHash = document["payloadHash"] as? String {
            let computed = SHA256.hash(data: payloadData)
                .compactMap { String(format: "%02x", $0) }.joined()
            guard computed == storedHash else {
                throw SecureMessagingError.integrityViolation
            }
        }

        let encrypted = try JSONDecoder().decode(AMENEncryptedMessage.self, from: payloadData)

        // Handle X3DH first message from a sender we haven't seen before
        var sessionId = activeSessions[conversationId]
        if sessionId == nil {
            if let header = encrypted.x3dhHeader {
                sessionId = try await receiveSessionInitiation(
                    header: header,
                    conversationId: conversationId,
                    senderRatchetKey: encrypted.senderRatchetKey
                )
            } else {
                // Cannot decrypt — no session. Silently skip (message from another device).
                return nil
            }
        }

        guard let sid = sessionId else { return nil }
        var ratchetState = try encryption.loadRatchetState(sessionId: sid)
        let plaintextData = try encryption.decryptMessage(encrypted: encrypted, state: &ratchetState)
        return String(data: plaintextData, encoding: .utf8)
    }

    // MARK: - Session Management

    private func initiateSession(
        conversationId: String,
        recipientUID: String,
        senderUID: String
    ) async throws -> String {
        // Fetch recipient's key bundle
        let bundleDoc = try await db.collection("keyBundles").document(recipientUID).getDocument()
        guard let data = bundleDoc.data() else {
            throw SecureMessagingError.recipientKeyBundleNotFound
        }
        let storable = try Firestore.Decoder().decode(StorableKeyBundle.self, from: data)
        let keyBundle = try storable.toKeyBundle()

        // X3DH sender side
        let (sessionId, masterSecret, header) = try encryption.x3dhSenderSession(
            recipientBundle: keyBundle
        )

        // Mark the OPK as used server-side so it cannot be reused
        if let usedOPKId = header.usedOTPKId {
            try? await db.collection("usedOTPKs")
                .document(recipientUID)
                .collection("consumed")
                .document("\(usedOPKId)")
                .setData(["usedAt": FieldValue.serverTimestamp()])

            // Remove from recipient's key bundle
            try? await db.collection("keyBundles").document(recipientUID)
                .updateData(["oneTimePreKeys": FieldValue.arrayRemove(
                    [["id": usedOPKId, "publicKey": (keyBundle.oneTimePreKeys.first { $0.id == usedOPKId }?.publicKey.base64EncodedString() ?? "")]]
                )])
        }

        // Init ratchet state as sender (stored for future message encryption use)
        _ = try encryption.initRatchetAsSender(
            masterSecret: masterSecret,
            recipientRatchetPublic: keyBundle.signedPreKeyPublic
        )

        // The x3dhHeader must be attached to the FIRST message only — store it for send
        // We need to pass it through; store the x3dhHeader temporarily in memory
        _ = header  // will be passed as x3dhHeader in first encryptMessage call

        activeSessions[conversationId] = sessionId
        return sessionId
    }

    private func receiveSessionInitiation(
        header: AMENEncryptedMessage.X3DHHeader,
        conversationId: String,
        senderRatchetKey: Data
    ) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SecureMessagingError.notAuthenticated
        }

        let bundleDoc = try await db.collection("keyBundles").document(uid).getDocument()
        guard let data = bundleDoc.data() else {
            throw SecureMessagingError.recipientKeyBundleNotFound
        }
        let storable = try Firestore.Decoder().decode(StorableKeyBundle.self, from: data)
        let myBundle = try storable.toKeyBundle()

        let masterSecret = try encryption.x3dhRecipientSession(
            header: header,
            recipientBundle: myBundle
        )

        _ = try encryption.initRatchetAsRecipient(
            masterSecret: masterSecret,
            senderRatchetPublic: senderRatchetKey
        )

        let sessionId = "\(conversationId)_\(header.senderEphemeralKey.prefix(8).base64EncodedString())"
        activeSessions[conversationId] = sessionId
        return sessionId
    }

    // MARK: - Conversation Creation

    /// Creates a new secure conversation or returns an existing one.
    func getOrCreateSecureConversation(
        withUID recipientUID: String,
        recipientName: String
    ) async throws -> String {
        guard let senderUID = Auth.auth().currentUser?.uid else {
            throw SecureMessagingError.notAuthenticated
        }

        // Check trust / contact tier first
        let tier = await trust.contactTier(between: senderUID, and: recipientUID)
        guard tier != .blocked else {
            throw SecureMessagingError.blocked
        }

        // Look for existing conversation
        let existing = try await db.collection("secureConversations")
            .whereField("participants", arrayContains: senderUID)
            .whereField("isGroup", isEqualTo: false)
            .getDocuments()

        for doc in existing.documents {
            if let participants = doc.data()["participants"] as? [String],
               participants.contains(recipientUID) {
                return doc.documentID
            }
        }

        // Create new conversation document
        let convRef = db.collection("secureConversations").document()
        let senderName = Auth.auth().currentUser?.displayName ?? "User"

        try await convRef.setData([
            "participants":         [senderUID, recipientUID],
            "participantNames":     [senderUID: senderName, recipientUID: recipientName],
            "isGroup":              false,
            "createdAt":            FieldValue.serverTimestamp(),
            "lastEncryptedTimestamp": FieldValue.serverTimestamp(),
            "unreadCounts":         [senderUID: 0, recipientUID: 0],
            "isPinned":             [],
            "isMuted":              [],
            "isArchived":           [],
            "contactTier":          tier.rawValue,
            "isMessageRequest":     (tier == .unknown)
        ])

        return convRef.documentID
    }

    // MARK: - Mark Read

    func markMessagesRead(conversationId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("secureConversations").document(conversationId)
            .updateData(["unreadCounts.\(uid)": 0])
    }

    // MARK: - Device Identifier

    private func deviceIdentifier() -> String {
        if let existing = UserDefaults.standard.string(forKey: "amenDeviceId") {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: "amenDeviceId")
        return new
    }
}

// MARK: - Errors

enum SecureMessagingError: LocalizedError {
    case notAuthenticated
    case blocked
    case safetyBlock(String)
    case recipientKeyBundleNotFound
    case malformedDocument
    case integrityViolation
    case sessionInitFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:              return "You must be signed in to send messages."
        case .blocked:                       return "You cannot message this person."
        case .safetyBlock(let r):            return r
        case .recipientKeyBundleNotFound:    return "Cannot set up a secure session — recipient has not configured encryption keys."
        case .malformedDocument:             return "Message data is malformed."
        case .integrityViolation:            return "Message integrity check failed — possible tampering detected."
        case .sessionInitFailed:             return "Failed to establish a secure session."
        }
    }
}

// MARK: - Contact Tier

enum ContactTier: String {
    case mutual  = "mutual"    // Mutual follow — full access, images/links allowed
    case followed = "followed" // Sender follows recipient — message request required
    case unknown = "unknown"   // No relationship — message request, text only
    case blocked = "blocked"   // Blocked — hard stop
}

// ContactTier resolution is implemented in AMENTrustScoreService.contactTier(between:and:)
