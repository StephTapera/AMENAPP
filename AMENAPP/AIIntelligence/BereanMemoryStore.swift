// BereanMemoryStore.swift
// AMENAPP — Berean Spiritual Intelligence Layer (Wave 3)
//
// Zone-classified spiritual memory store.
// - Non-sensitive fields (preference, behavioral): stored in UserDefaults via @AppStorage.
// - High-zone fields (prayerHistory): AES-256-GCM encrypted, stored in Keychain.
//
// Flag guard: save() is a no-op when bereanSpiritualMemoryEnabled is false.
// All records carry userCanInspect: true, userCanDelete: true.

import Foundation
import CryptoKit
import Security
import SwiftUI

@MainActor
final class BereanMemoryStore: ObservableObject {

    static let shared = BereanMemoryStore()

    @Published private(set) var records: [BereanMemoryRecord] = []

    // UserDefaults keys mirror MemoryField.rawValue
    @AppStorage("berean.memory.preferredTranslation") private var storedPreferredTranslation: String = ""
    @AppStorage("berean.memory.studyStyle")           private var storedStudyStyle: String = ""
    @AppStorage("berean.memory.theologicalLean")      private var storedTheologicalLean: String = ""
    @AppStorage("berean.memory.denominationalLean")   private var storedDenominationalLean: String = ""
    @AppStorage("berean.memory.readingHabits")        private var storedReadingHabits: String = ""

    private let keychainTagBase = "com.amenapp.berean.memory."

    private init() {
        refreshRecords()
    }

    // MARK: - Save

    /// Persists a field value. Encrypts when field.mustEncryptAtRest.
    /// No-op if bereanSpiritualMemoryEnabled is false.
    func save(field: MemoryField, value: String) async {
        guard AMENFeatureFlags.shared.bereanSpiritualMemoryEnabled else { return }

        if field.mustEncryptAtRest {
            // AES-256-GCM encrypt and store in Keychain
            guard let plaintext = value.data(using: .utf8) else { return }
            do {
                let ciphertextData = try encryptAESGCM(plaintext)
                try saveToKeychain(ciphertextData, tag: keychainTagBase + field.rawValue)
            } catch {
                dlog("[BereanMemoryStore] Encrypt/save failed for \(field.rawValue): \(error)")
                return
            }
        } else {
            // Non-sensitive: store in UserDefaults via @AppStorage backing store
            UserDefaults.standard.set(value, forKey: "berean.memory.\(field.rawValue)")
        }

        refreshRecords()
    }

    // MARK: - Delete

    func delete(field: MemoryField) {
        if field.mustEncryptAtRest {
            deleteFromKeychain(tag: keychainTagBase + field.rawValue)
        } else {
            UserDefaults.standard.removeObject(forKey: "berean.memory.\(field.rawValue)")
        }
        refreshRecords()
    }

    // MARK: - Delete All

    /// Wipes all Berean memory. This is the "user deletes all memory" path.
    func deleteAll() {
        for field in MemoryField.allCases {
            delete(field: field)
        }
        refreshRecords()
    }

    // MARK: - Read

    /// Returns the plaintext value for a field, decrypting if needed.
    func value(for field: MemoryField) -> String? {
        if field.mustEncryptAtRest {
            guard let ciphertextData = loadFromKeychain(tag: keychainTagBase + field.rawValue) else {
                return nil
            }
            do {
                let plaintextData = try decryptAESGCM(ciphertextData)
                return String(data: plaintextData, encoding: .utf8)
            } catch {
                dlog("[BereanMemoryStore] Decrypt failed for \(field.rawValue): \(error)")
                return nil
            }
        } else {
            let raw = UserDefaults.standard.string(forKey: "berean.memory.\(field.rawValue)")
            return raw?.isEmpty == false ? raw : nil
        }
    }

    // MARK: - Refresh Published Records

    private func refreshRecords() {
        let now = Date().timeIntervalSince1970
        records = MemoryField.allCases.compactMap { field in
            guard let val = value(for: field) else { return nil }
            return BereanMemoryRecord(
                id: field.rawValue,
                uid: "",            // caller fills uid from auth context if needed
                field: field,
                zone: field.zone,
                value: val,
                encryptedAtRest: field.mustEncryptAtRest,
                createdAt: now,
                updatedAt: now,
                userCanInspect: true,
                userCanDelete: true
            )
        }
    }

    // MARK: - AES-256-GCM Helpers

    /// Returns ciphertext as nonce (12 bytes) || ciphertext || tag (16 bytes).
    private func encryptAESGCM(_ plaintext: Data) throws -> Data {
        let key = try memoryEncryptionKey()
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        return Data(nonce) + sealed.ciphertext + sealed.tag
    }

    /// Expects the ciphertext layout written by encryptAESGCM above.
    private func decryptAESGCM(_ combined: Data) throws -> Data {
        guard combined.count > 28 else {
            throw BereanMemoryStoreError.malformedCiphertext
        }
        let nonceData = combined.prefix(12)
        let tag       = combined.suffix(16)
        let ct        = combined.dropFirst(12).dropLast(16)

        let key    = try memoryEncryptionKey()
        let nonce  = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
        return try AES.GCM.open(sealed, using: key)
    }

    /// Derives or loads a persistent 256-bit AES key from the Keychain.
    private func memoryEncryptionKey() throws -> SymmetricKey {
        let tag = "com.amenapp.berean.memory.aes256key"
        if let existing = loadFromKeychain(tag: tag) {
            return SymmetricKey(data: existing)
        }
        // Generate and persist a new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try saveToKeychain(keyData, tag: tag)
        return newKey
    }

    // MARK: - Keychain Helpers

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
            throw BereanMemoryStoreError.keychainError(status)
        }
    }

    private func loadFromKeychain(tag: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:               kSecClassGenericPassword,
            kSecAttrAccount as String:         tag,
            kSecReturnData as String:          true,
            kSecMatchLimit as String:          kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private func deleteFromKeychain(tag: String) {
        let query: [String: Any] = [
            kSecClass as String:    kSecClassGenericPassword,
            kSecAttrAccount as String: tag
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum BereanMemoryStoreError: LocalizedError {
    case malformedCiphertext
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .malformedCiphertext:      return "Berean memory ciphertext is malformed."
        case .keychainError(let s):     return "Berean memory Keychain error: \(s)"
        }
    }
}
