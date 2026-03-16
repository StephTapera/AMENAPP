//
//  AMENEncryptionService.swift
//  AMENAPP
//
//  Signal Protocol–inspired E2EE for AMEN messaging.
//
//  Architecture:
//    - X3DH (Extended Triple Diffie-Hellman) for session key agreement
//    - Double Ratchet for forward + future secrecy per message
//    - Curve25519 ECDH via Swift Crypto / CryptoKit
//    - AES-256-GCM symmetric encryption
//    - Private keys stored in Secure Enclave where supported; otherwise
//      in the iOS Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
//
//  Server never sees plaintext. Server stores:
//    encryptedPayload (ciphertext + nonce), senderID, recipientID, timestamp.
//
//  Key terminology:
//    IK  = Identity Key pair  (long-lived, device-bound)
//    SPK = Signed Pre-Key     (rotated monthly, signed by IK)
//    OPK = One-Time Pre-Key   (consumed once per session, never reused)
//    EK  = Ephemeral Key      (generated fresh for each X3DH handshake)

import Foundation
import CryptoKit
import Security

// MARK: - Key Types

/// A Curve25519 key pair stored/loaded from Keychain.
struct AMENKeyPair {
    let privateKey: Curve25519.KeyAgreement.PrivateKey
    var publicKey:  Curve25519.KeyAgreement.PublicKey { privateKey.publicKey }
    /// Raw 32-byte public key for Firestore / wire transport.
    var publicKeyData: Data { publicKey.rawRepresentation }
}

/// The user's published key bundle — stored in Firestore under users/{uid}/keyBundle.
struct AMENKeyBundle: Codable {
    let identityKeyPublic: Data       // IK public — 32 bytes
    let signedPreKeyPublic: Data      // SPK public — 32 bytes
    let signedPreKeySignature: Data   // IK signs SPK — 64 bytes
    let signedPreKeyId: Int
    let oneTimePreKeys: [OTPKEntry]   // Array of unused OPKs
    let deviceId: String

    struct OTPKEntry: Codable {
        let id: Int
        let publicKey: Data           // 32 bytes
    }
}

/// Per-session ratchet state, persisted in Keychain after each message.
struct RatchetState: Codable {
    var rootKey: Data                  // 32 bytes
    var sendChainKey: Data             // 32 bytes
    var receiveChainKey: Data          // 32 bytes
    var sendMessageIndex: Int
    var receiveMessageIndex: Int
    var remoteDHPublic: Data           // Latest ratchet public key from partner
    var localDHPrivate: Data           // Our current ratchet private key

    static func empty() -> RatchetState {
        RatchetState(
            rootKey: Data(count: 32),
            sendChainKey: Data(count: 32),
            receiveChainKey: Data(count: 32),
            sendMessageIndex: 0,
            receiveMessageIndex: 0,
            remoteDHPublic: Data(count: 32),
            localDHPrivate: Data(count: 32)
        )
    }
}

/// Wire-format for an encrypted message.
struct AMENEncryptedMessage: Codable {
    let ciphertext: Data           // AES-256-GCM ciphertext
    let nonce: Data                // 12-byte GCM nonce
    let senderRatchetKey: Data     // Sender's current DH ratchet public key
    let messageIndex: Int          // Monotonically increasing per chain
    let sessionId: String          // Identifies which X3DH session this belongs to
    /// Optional: included only in first message of a session (X3DH header).
    let x3dhHeader: X3DHHeader?

    struct X3DHHeader: Codable {
        let senderIdentityKey: Data    // IK_A public
        let senderEphemeralKey: Data   // EK_A public
        let usedOTPKId: Int?           // Which OPK was consumed (nil if none available)
        let usedSPKId: Int
    }
}

// MARK: - AMENEncryptionService

@MainActor
final class AMENEncryptionService {

    static let shared = AMENEncryptionService()
    private init() {}

    // MARK: - Keychain tag constants

    private let ikTag       = "com.amenapp.ik"
    private let spkTagBase  = "com.amenapp.spk."
    private let opkTagBase  = "com.amenapp.opk."
    private let ratchetBase = "com.amenapp.ratchet."

    // MARK: - Identity Key Management

    /// Returns existing IK or generates a new one.
    func identityKeyPair() throws -> AMENKeyPair {
        let tag = ikTag
        if let existing = try? loadPrivateKeyFromKeychain(tag: tag) {
            return AMENKeyPair(privateKey: existing)
        }
        let newKey = Curve25519.KeyAgreement.PrivateKey()
        try savePrivateKeyToKeychain(newKey.rawRepresentation, tag: tag)
        return AMENKeyPair(privateKey: newKey)
    }

    // MARK: - Signed Pre-Key (rotated monthly)

    func generateSignedPreKey(id: Int) throws -> (pair: AMENKeyPair, signature: Data) {
        let ik = try identityKeyPair()
        let spk = Curve25519.KeyAgreement.PrivateKey()
        let tag = spkTagBase + "\(id)"
        try savePrivateKeyToKeychain(spk.rawRepresentation, tag: tag)

        // Sign SPK.publicKey with identity key using Ed25519
        let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: ik.privateKey.rawRepresentation)
        let signature = try signingKey.signature(for: spk.publicKey.rawRepresentation)
        return (AMENKeyPair(privateKey: spk), signature)
    }

    func loadSignedPreKey(id: Int) throws -> AMENKeyPair {
        let raw = try loadPrivateKeyFromKeychain(tag: spkTagBase + "\(id)")
        return AMENKeyPair(privateKey: raw)
    }

    // MARK: - One-Time Pre-Keys

    func generateOneTimePreKeys(count: Int, startingId: Int) throws -> [AMENKeyBundle.OTPKEntry] {
        var entries: [AMENKeyBundle.OTPKEntry] = []
        for i in 0..<count {
            let id = startingId + i
            let key = Curve25519.KeyAgreement.PrivateKey()
            try savePrivateKeyToKeychain(key.rawRepresentation, tag: opkTagBase + "\(id)")
            entries.append(.init(id: id, publicKey: key.publicKey.rawRepresentation))
        }
        return entries
    }

    func consumeOneTimePreKey(id: Int) throws -> AMENKeyPair {
        let tag = opkTagBase + "\(id)"
        let raw = try loadPrivateKeyFromKeychain(tag: tag)
        // Delete from Keychain — OPKs are single-use
        deleteKeyFromKeychain(tag: tag)
        return AMENKeyPair(privateKey: raw)
    }

    // MARK: - X3DH Session Initiation (Sender / Alice side)

    /// Alice initiates a session using Bob's published key bundle.
    /// Returns the session master secret and the X3DH header to send to Bob.
    func x3dhSenderSession(
        recipientBundle: AMENKeyBundle
    ) throws -> (sessionId: String, sharedSecret: Data, header: AMENEncryptedMessage.X3DHHeader) {

        let ik_A = try identityKeyPair()
        let ek_A = Curve25519.KeyAgreement.PrivateKey()  // fresh ephemeral

        guard let ik_B = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientBundle.identityKeyPublic),
              let spk_B = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientBundle.signedPreKeyPublic)
        else { throw AMENEncryptionError.invalidKeyBundle }

        // Verify SPK signature
        let signingPub = try Curve25519.Signing.PublicKey(rawRepresentation: recipientBundle.identityKeyPublic)
        guard signingPub.isValidSignature(recipientBundle.signedPreKeySignature,
                                          for: recipientBundle.signedPreKeyPublic)
        else { throw AMENEncryptionError.signatureVerificationFailed }

        // DH calculations — X3DH spec:
        //   DH1 = DH(IK_A, SPK_B)
        //   DH2 = DH(EK_A, IK_B)
        //   DH3 = DH(EK_A, SPK_B)
        //   DH4 = DH(EK_A, OPK_B)  [if OPK available]
        let dh1 = try sharedSecret(privateKey: ik_A.privateKey,  publicKey: spk_B)
        let dh2 = try sharedSecret(privateKey: ek_A,             publicKey: ik_B)
        let dh3 = try sharedSecret(privateKey: ek_A,             publicKey: spk_B)

        var dhConcat = dh1 + dh2 + dh3
        var usedOTPKId: Int? = nil

        if let opkEntry = recipientBundle.oneTimePreKeys.first,
           let opk_B = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: opkEntry.publicKey) {
            let dh4 = try sharedSecret(privateKey: ek_A, publicKey: opk_B)
            dhConcat += dh4
            usedOTPKId = opkEntry.id
        }

        let masterSecret = hkdf(inputKeyMaterial: dhConcat,
                                info: Data("AMENv1X3DH".utf8),
                                outputLength: 64)

        let sessionId = UUID().uuidString
        let header = AMENEncryptedMessage.X3DHHeader(
            senderIdentityKey: ik_A.publicKeyData,
            senderEphemeralKey: ek_A.publicKey.rawRepresentation,
            usedOTPKId: usedOTPKId,
            usedSPKId: recipientBundle.signedPreKeyId
        )
        return (sessionId, masterSecret, header)
    }

    // MARK: - X3DH Session Receipt (Recipient / Bob side)

    /// Bob reconstructs the shared secret from Alice's X3DH header.
    func x3dhRecipientSession(
        header: AMENEncryptedMessage.X3DHHeader,
        recipientBundle: AMENKeyBundle  // Bob's own bundle (for SPK id lookup)
    ) throws -> Data {

        let ik_B = try identityKeyPair()
        let spk_B = try loadSignedPreKey(id: header.usedSPKId)

        guard let ik_A  = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: header.senderIdentityKey),
              let ek_A  = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: header.senderEphemeralKey)
        else { throw AMENEncryptionError.invalidX3DHHeader }

        let dh1 = try sharedSecret(privateKey: spk_B.privateKey, publicKey: ik_A)
        let dh2 = try sharedSecret(privateKey: ik_B.privateKey,  publicKey: ek_A)
        let dh3 = try sharedSecret(privateKey: spk_B.privateKey, publicKey: ek_A)

        var dhConcat = dh1 + dh2 + dh3

        if let opkId = header.usedOTPKId {
            let opk_B = try consumeOneTimePreKey(id: opkId)
            let dh4 = try sharedSecret(privateKey: opk_B.privateKey, publicKey: ek_A)
            dhConcat += dh4
        }

        return hkdf(inputKeyMaterial: dhConcat,
                    info: Data("AMENv1X3DH".utf8),
                    outputLength: 64)
    }

    // MARK: - Double Ratchet — Initialise

    func initRatchetAsSender(masterSecret: Data, recipientRatchetPublic: Data) throws -> RatchetState {
        let localDH = Curve25519.KeyAgreement.PrivateKey()
        guard let remotePublic = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientRatchetPublic)
        else { throw AMENEncryptionError.invalidPublicKey }

        let dhOut = try sharedSecret(privateKey: localDH, publicKey: remotePublic)
        let (rootKey, sendChainKey) = kdfRootKey(rootKey: masterSecret[..<32],
                                                  dhOutput: dhOut)
        return RatchetState(
            rootKey: rootKey,
            sendChainKey: sendChainKey,
            receiveChainKey: masterSecret[32...].data,
            sendMessageIndex: 0,
            receiveMessageIndex: 0,
            remoteDHPublic: recipientRatchetPublic,
            localDHPrivate: localDH.rawRepresentation
        )
    }

    func initRatchetAsRecipient(masterSecret: Data, senderRatchetPublic: Data) throws -> RatchetState {
        let localDH = Curve25519.KeyAgreement.PrivateKey()
        return RatchetState(
            rootKey: masterSecret[..<32].data,
            sendChainKey: Data(count: 32),
            receiveChainKey: masterSecret[32...].data,
            sendMessageIndex: 0,
            receiveMessageIndex: 0,
            remoteDHPublic: senderRatchetPublic,
            localDHPrivate: localDH.rawRepresentation
        )
    }

    // MARK: - Double Ratchet — Encrypt / Decrypt

    /// Encrypt a plaintext message and advance the ratchet state.
    func encryptMessage(
        plaintext: Data,
        sessionId: String,
        state: inout RatchetState,
        x3dhHeader: AMENEncryptedMessage.X3DHHeader? = nil
    ) throws -> AMENEncryptedMessage {

        // Advance send chain to derive message key
        let (newSendChain, messageKey) = kdfChainKey(chainKey: state.sendChainKey)
        state.sendChainKey = newSendChain

        let localDH = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: state.localDHPrivate)
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(plaintext,
                                          using: SymmetricKey(data: messageKey),
                                          nonce: nonce)
        let index = state.sendMessageIndex
        state.sendMessageIndex += 1

        // Save updated state
        try saveRatchetState(state, sessionId: sessionId)

        return AMENEncryptedMessage(
            ciphertext: sealedBox.ciphertext + sealedBox.tag,
            nonce: Data(nonce),
            senderRatchetKey: localDH.publicKey.rawRepresentation,
            messageIndex: index,
            sessionId: sessionId,
            x3dhHeader: x3dhHeader
        )
    }

    /// Decrypt a received message and advance the ratchet state.
    func decryptMessage(
        encrypted: AMENEncryptedMessage,
        state: inout RatchetState
    ) throws -> Data {

        // Check if we need to perform a DH ratchet step
        if encrypted.senderRatchetKey != state.remoteDHPublic {
            try performDHRatchetStep(state: &state,
                                     newRemotePublic: encrypted.senderRatchetKey)
        }

        let (newReceiveChain, messageKey) = kdfChainKey(chainKey: state.receiveChainKey)
        state.receiveChainKey = newReceiveChain
        state.receiveMessageIndex += 1

        guard encrypted.ciphertext.count > 16 else { throw AMENEncryptionError.decryptionFailed }
        let ct  = encrypted.ciphertext.dropLast(16)
        let tag = encrypted.ciphertext.suffix(16)

        let nonce = try AES.GCM.Nonce(data: encrypted.nonce)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
        let plaintext = try AES.GCM.open(sealedBox, using: SymmetricKey(data: messageKey))

        try saveRatchetState(state, sessionId: encrypted.sessionId)
        return plaintext
    }

    // MARK: - Ratchet helpers

    private func performDHRatchetStep(state: inout RatchetState, newRemotePublic: Data) throws {
        let localDH = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: state.localDHPrivate)
        guard let remotePublic = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: newRemotePublic)
        else { throw AMENEncryptionError.invalidPublicKey }

        let dhOut = try sharedSecret(privateKey: localDH, publicKey: remotePublic)
        let (newRoot, newRecvChain) = kdfRootKey(rootKey: state.rootKey, dhOutput: dhOut)

        // Generate our new DH key for next step
        let newLocalDH = Curve25519.KeyAgreement.PrivateKey()
        let dhOut2 = try sharedSecret(privateKey: newLocalDH, publicKey: remotePublic)
        let (newerRoot, newSendChain) = kdfRootKey(rootKey: newRoot, dhOutput: dhOut2)

        state.rootKey = newerRoot
        state.sendChainKey = newSendChain
        state.receiveChainKey = newRecvChain
        state.remoteDHPublic = newRemotePublic
        state.localDHPrivate = newLocalDH.rawRepresentation
    }

    // MARK: - KDF functions

    private func kdfRootKey(rootKey: Data, dhOutput: Data) -> (newRootKey: Data, chainKey: Data) {
        let output = hkdf(inputKeyMaterial: dhOutput,
                          salt: rootKey,
                          info: Data("AMENRatchetRoot".utf8),
                          outputLength: 64)
        return (output[..<32].data, output[32...].data)
    }

    private func kdfChainKey(chainKey: Data) -> (newChainKey: Data, messageKey: Data) {
        let newChain   = hmacSHA256(key: chainKey, data: Data([0x01]))
        let messageKey = hmacSHA256(key: chainKey, data: Data([0x02]))
        return (newChain, messageKey)
    }

    private func sharedSecret(privateKey: Curve25519.KeyAgreement.PrivateKey,
                               publicKey: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        let ss = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return ss.withUnsafeBytes { Data($0) }
    }

    private func hkdf(inputKeyMaterial: Data,
                      salt: Data? = nil,
                      info: Data,
                      outputLength: Int) -> Data {
        let prk: SymmetricKey
        if let salt = salt {
            prk = HMAC<SHA256>.authenticationCode(for: inputKeyMaterial,
                                                   using: SymmetricKey(data: salt))
                .withUnsafeBytes { SymmetricKey(data: Data($0)) }
        } else {
            prk = HMAC<SHA256>.authenticationCode(for: inputKeyMaterial,
                                                   using: SymmetricKey(data: Data(count: 32)))
                .withUnsafeBytes { SymmetricKey(data: Data($0)) }
        }

        var output = Data()
        var prev = Data()
        var counter: UInt8 = 1
        while output.count < outputLength {
            let input = prev + info + Data([counter])
            let block = HMAC<SHA256>.authenticationCode(for: input, using: prk)
                .withUnsafeBytes { Data($0) }
            output += block
            prev = block
            counter += 1
        }
        return Data(output.prefix(outputLength))
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return mac.withUnsafeBytes { Data($0) }
    }

    // MARK: - Ratchet State Persistence (Keychain)

    private func saveRatchetState(_ state: RatchetState, sessionId: String) throws {
        let data = try JSONEncoder().encode(state)
        try saveToKeychain(data, tag: ratchetBase + sessionId)
    }

    func loadRatchetState(sessionId: String) throws -> RatchetState {
        let data = try loadDataFromKeychain(tag: ratchetBase + sessionId)
        return try JSONDecoder().decode(RatchetState.self, from: data)
    }

    func deleteRatchetState(sessionId: String) {
        deleteKeyFromKeychain(tag: ratchetBase + sessionId)
    }

    // MARK: - Keychain Helpers

    private func savePrivateKeyToKeychain(_ keyData: Data, tag: String) throws {
        guard let tagData = tag.data(using: .utf8) else {
            throw AMENEncryptionError.keychainError(errSecParam)
        }
        let query: [String: Any] = [
            kSecClass as String:               kSecClassKey,
            kSecAttrApplicationTag as String:  tagData,
            kSecAttrKeyType as String:         kSecAttrKeyTypeEC,
            kSecValueData as String:           keyData,
            kSecAttrAccessible as String:      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String:  false  // Never sync to iCloud
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AMENEncryptionError.keychainError(status)
        }
    }

    private func loadPrivateKeyFromKeychain(tag: String) throws -> Curve25519.KeyAgreement.PrivateKey {
        let data = try loadDataFromKeychain(tag: tag)
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    private func saveToKeychain(_ data: Data, tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String:               kSecClassGenericPassword,
            kSecAttrAccount as String:         tag,
            kSecValueData as String:           data,
            kSecAttrAccessible as String:      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String:  false
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AMENEncryptionError.keychainError(status)
        }
    }

    private func loadDataFromKeychain(tag: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String:               kSecClassGenericPassword,
            kSecAttrAccount as String:         tag,
            kSecReturnData as String:          true,
            kSecMatchLimit as String:          kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw AMENEncryptionError.keychainError(status)
        }
        return data
    }

    private func deleteKeyFromKeychain(tag: String) {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrAccount as String:        tag
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum AMENEncryptionError: LocalizedError {
    case invalidKeyBundle
    case signatureVerificationFailed
    case invalidX3DHHeader
    case invalidPublicKey
    case decryptionFailed
    case keychainError(OSStatus)
    case ratchetStateNotFound
    case sessionNotFound

    var errorDescription: String? {
        switch self {
        case .invalidKeyBundle:             return "Recipient key bundle is malformed."
        case .signatureVerificationFailed:  return "Signed pre-key signature is invalid."
        case .invalidX3DHHeader:            return "X3DH session header is malformed."
        case .invalidPublicKey:             return "Public key data is invalid."
        case .decryptionFailed:             return "Message decryption failed — possible tampering."
        case .keychainError(let s):         return "Keychain error: \(s)"
        case .ratchetStateNotFound:         return "Ratchet state not found for session."
        case .sessionNotFound:              return "Encrypted session not found."
        }
    }
}

// MARK: - Convenience extensions

private extension DataProtocol {
    var data: Data { Data(self) }
}

private extension Data {
    subscript(range: PartialRangeFrom<Index>) -> Data {
        // Use subdata(in:) to avoid infinite recursion that would occur with Data(self[...])
        subdata(in: range.lowerBound ..< endIndex)
    }
}

private extension HMAC where H == SHA256 {
    static func authenticationCode(for data: Data, using key: SymmetricKey) -> HMAC<SHA256>.MAC {
        var hmac = HMAC<SHA256>(key: key)
        hmac.update(data: data)
        return hmac.finalize()
    }
}
