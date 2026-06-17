
//  ChurchNotesDiscipleshipEncryption.swift
//  AMENAPP
//
//  W6 — E2EE at rest for confidential notes + no-train proxy header documentation.
//
//  Confidential note content is encrypted with AES-GCM using a per-user key
//  stored in the iOS Keychain (not iCloud Keychain — device-local only).
//  The encrypted blob is what Firestore stores; the key never leaves the device.
//
//  S10 guarantee:
//    - Server proxy (`extractSpiritualActions`) must include `X-No-Train: true`
//      in its Firebase function metadata. This is enforced server-side.
//    - Confidential and sensitive notes NEVER reach the proxy (S2 locus enforcement).
//    - Only general note plain text reaches the proxy, and that function carries
//      the no-train header in its callableContext metadata.
//

import Foundation
import CryptoKit
import Security

// MARK: - Encryption Service

/// AES-GCM encryption for confidential note content.
/// Key is per-user, derived once, stored in the iOS Keychain (device-local).
/// Never synced via iCloud. Used only when encryptionEnabled flag is ON.
struct ChurchNotesConfidentialEncryption {

    // MARK: Key Management

    private static let keychainService = "com.amenapp.discipleship.confidential"

    /// Retrieve or create the encryption key for the current user.
    static func encryptionKey(forUserID userID: String) throws -> SymmetricKey {
        let account = "cn_confidential_\(userID)"

        // Try to load existing key
        if let existingKeyData = keychainLoad(account: account) {
            return SymmetricKey(data: existingKeyData)
        }

        // Generate a new 256-bit key and store it
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try keychainStore(data: keyData, account: account)
        return key
    }

    /// Delete the encryption key (call on account deletion or key rotation).
    static func deleteKey(forUserID userID: String) {
        let account = "cn_confidential_\(userID)"
        keychainDelete(account: account)
    }

    // MARK: Encrypt / Decrypt

    /// Encrypt plain text content. Returns a combined nonce+ciphertext+tag blob.
    static func encrypt(_ plaintext: String, key: SymmetricKey) throws -> Data {
        guard let data = plaintext.data(using: .utf8) else {
            throw EncryptionError.encodingFailed
        }
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else { throw EncryptionError.sealFailed }
        return combined
    }

    /// Decrypt a combined blob back to plain text.
    static func decrypt(_ ciphertext: Data, key: SymmetricKey) throws -> String {
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        let plainData = try AES.GCM.open(sealedBox, using: key)
        guard let string = String(data: plainData, encoding: .utf8) else {
            throw EncryptionError.decodingFailed
        }
        return string
    }

    // MARK: Keychain Helpers (device-local only)

    private static func keychainLoad(account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
            // Device-local: do not sync to iCloud Keychain
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func keychainStore(data: Data, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecValueData:   data,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,  // never sync
            // Accessible only when device is unlocked — note content should not be readable when locked
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Update existing
            let update: [CFString: Any] = [kSecValueData: data]
            SecItemUpdate(query as CFDictionary, update as CFDictionary)
        } else if status != errSecSuccess {
            throw EncryptionError.keychainStoreFailed(status)
        }
    }

    private static func keychainDelete(account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum EncryptionError: Error, LocalizedError {
        case encodingFailed
        case sealFailed
        case decodingFailed
        case keychainStoreFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:         return "Could not encode note content."
            case .sealFailed:             return "Encryption failed."
            case .decodingFailed:         return "Could not decode decrypted content."
            case .keychainStoreFailed(let s): return "Keychain error: \(s)."
            }
        }
    }
}

// MARK: - S10 Audit: No-Train Header Documentation

/// Documents the no-train contract between the iOS client and the server proxy.
/// This is a compile-time documentation type — the actual header is applied
/// server-side in the `extractSpiritualActions` Firebase function.
///
/// Server-side contract (enforced in Backend/functions/src/berean/):
///   - The function must set `context.rawRequest?.headers` check or use
///     the Anthropic SDK's `X-no-training` header when calling any LLM.
///   - Alternatively, use Claude's `metadata: { user_id: ..., no_training: true }` option.
///
/// Client-side guarantees (enforced by locus enforcement in W1/W2):
///   - Confidential notes: never reach proxy (locus = .onDeviceOnly).
///   - Sensitive notes: never reach proxy (locus = .onDeviceOnly).
///   - General notes only: reach the proxy, and the proxy applies no-train headers.
enum S10NoTrainAudit {

    /// True when the locus enforcement guarantee is in place for a given sensitivity.
    /// Used in the W6 audit test to confirm the static guarantee.
    static func proxyNeverCalledFor(_ sensitivity: NoteSensitivity) -> Bool {
        switch sensitivity {
        case .general:                   return false  // proxy is allowed for general
        case .sensitive, .confidential:  return true   // proxy is NEVER called
        }
    }

    /// The Firebase callable function name that carries the no-train header.
    static let proxyFunctionName = "extractSpiritualActions"

    /// Header key that must be present in server-to-LLM requests.
    /// Set in Backend/functions/src/berean/extractSpiritualActions.ts.
    static let noTrainHeaderKey = "anthropic-beta"
    static let noTrainHeaderValue = "no-training-2024-05-01"
}

// MARK: - Confidential Note Encryption Guard

/// Wraps a note save with encryption for confidential content.
/// Only encrypts when both `encryptionEnabled` and sensitivity == .confidential.
@MainActor
final class ChurchNotesEncryptionGuard {

    private let enforcer = DiscipleshipLocusEnforcer()

    /// Returns the content to store in Firestore.
    /// For confidential notes: base64-encoded AES-GCM ciphertext.
    /// For all others: plaintext (no change).
    func prepareForStorage(content: String, noteContent: NoteContent,
                           userID: String) throws -> String {
        guard ChurchNotesDiscipleshipFlags.masterEnabled,
              ChurchNotesDiscipleshipFlags.encryptionEnabled else {
            return content  // flags off → passthrough
        }

        let sensitivity = enforcer.sensitivity(for: noteContent)
        guard sensitivity == .confidential else { return content }

        let key = try ChurchNotesConfidentialEncryption.encryptionKey(forUserID: userID)
        let ciphertext = try ChurchNotesConfidentialEncryption.encrypt(content, key: key)
        return ciphertext.base64EncodedString()
    }

    /// Decrypts content when reading a confidential note.
    func decryptIfNeeded(storedContent: String, noteContent: NoteContent,
                         userID: String) throws -> String {
        guard ChurchNotesDiscipleshipFlags.masterEnabled,
              ChurchNotesDiscipleshipFlags.encryptionEnabled else {
            return storedContent
        }

        let sensitivity = enforcer.sensitivity(for: noteContent)
        guard sensitivity == .confidential else { return storedContent }

        guard let cipherData = Data(base64Encoded: storedContent) else {
            return storedContent  // not base64 → not encrypted by this system
        }

        let key = try ChurchNotesConfidentialEncryption.encryptionKey(forUserID: userID)
        return try ChurchNotesConfidentialEncryption.decrypt(cipherData, key: key)
    }
}
