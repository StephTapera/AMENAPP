import Foundation
import CryptoKit
import Security

// MARK: - SacredChannelCrypto
//
// Near-E2E encryption for Sacred (adult-only 1:1) channels.
// Per-conversation SymmetricKey (AES-256-GCM), wrapped per-participant
// using ECDH (P-256) + HKDF + AES-GCM key wrapping.
//
// LIMITATION — must be disclosed per spec Non-Negotiable §3:
//   No forward secrecy / double ratchet. A single per-conversation key is used for
//   the lifetime of the channel. Product copy MUST say "AMEN cannot read your private
//   messages" — NOT "end-to-end encrypted" — unless upgraded to a full ratchet.

enum SacredChannelCrypto {

    // MARK: - Message Sealing / Opening

    static func seal(_ plaintext: String, with key: SymmetricKey) throws -> SealedPayload {
        let box = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        return SealedPayload(ciphertext: box.ciphertext, nonce: Data(box.nonce), tag: box.tag)
    }

    static func open(_ payload: SealedPayload, with key: SymmetricKey) throws -> String {
        let nonce = try AES.GCM.Nonce(data: payload.nonce)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: payload.ciphertext, tag: payload.tag)
        return String(decoding: try AES.GCM.open(box, using: key), as: UTF8.self)
    }

    // MARK: - Conversation Key

    static func generateConversationKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    // MARK: - Key Wrapping
    //
    // Envelope format: 65 bytes raw ephemeral P-256 pubkey | 12 bytes nonce | ciphertext | 16 bytes tag

    private static let hkdfSalt = Data("AmenSacredChannelV1".utf8)

    static func wrapConversationKey(_ key: SymmetricKey, for recipientPublicKey: P256.KeyAgreement.PublicKey) throws -> Data {
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        let wrapping = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: hkdfSalt, sharedInfo: Data(), outputByteCount: 32)
        let keyData = key.withUnsafeBytes { Data($0) }
        let box = try AES.GCM.seal(keyData, using: wrapping)
        return ephemeral.publicKey.rawRepresentation + Data(box.nonce) + box.ciphertext + box.tag
    }

    static func unwrapConversationKey(_ wrapped: Data, with privateKey: P256.KeyAgreement.PrivateKey) throws -> SymmetricKey {
        guard wrapped.count > 65 + 12 + 16 else { throw SacredCryptoError.malformedWrappedKey }
        let ephemeralPub = try P256.KeyAgreement.PublicKey(rawRepresentation: wrapped.prefix(65))
        let rest = wrapped.dropFirst(65)
        let nonce = try AES.GCM.Nonce(data: rest.prefix(12))
        let tag = rest.suffix(16)
        let ciphertext = rest.dropFirst(12).dropLast(16)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: ephemeralPub)
        let wrapping = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: hkdfSalt, sharedInfo: Data(), outputByteCount: 32)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return SymmetricKey(data: try AES.GCM.open(box, using: wrapping))
    }

    // MARK: - Identity Key Pair (one per user; private key lives only in Keychain)

    static func generateIdentityKeyPair() -> P256.KeyAgreement.PrivateKey {
        P256.KeyAgreement.PrivateKey()
    }

    static func storeIdentityPrivateKey(_ key: P256.KeyAgreement.PrivateKey, uid: String) throws {
        var query = keychainBase(uid: uid)
        query[kSecValueData as String] = key.rawRepresentation as CFData
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemDelete(keychainBase(uid: uid) as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SacredCryptoError.keychainWrite(status) }
    }

    static func loadIdentityPrivateKey(uid: String) throws -> P256.KeyAgreement.PrivateKey {
        var query = keychainBase(uid: uid)
        query[kSecReturnData as String] = true
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw SacredCryptoError.keychainRead(status)
        }
        return try P256.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    // MARK: - Conversation Key Cache (Keychain, per channel)

    static func cacheConversationKey(_ key: SymmetricKey, channelId: String, uid: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "amenConvKey_\(channelId)_\(uid)",
            kSecValueData as String: key.withUnsafeBytes { Data($0) } as CFData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func cachedConversationKey(channelId: String, uid: String) -> SymmetricKey? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "amenConvKey_\(channelId)_\(uid)",
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    // MARK: - Private

    private static func keychainBase(uid: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.amen.sacredIdentityKey",
         kSecAttrAccount as String: uid]
    }
}

// MARK: - Errors

enum SacredCryptoError: LocalizedError {
    case malformedWrappedKey
    case keychainWrite(OSStatus)
    case keychainRead(OSStatus)

    var errorDescription: String? {
        switch self {
        case .malformedWrappedKey: return "Encryption key data is malformed."
        case .keychainWrite(let s): return "Could not save encryption key (OSStatus \(s))."
        case .keychainRead(let s): return "Could not load encryption key (OSStatus \(s))."
        }
    }
}
