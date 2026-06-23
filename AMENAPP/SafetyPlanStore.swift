//
//  SafetyPlanStore.swift
//  AMENAPP
//
//  Persists the user's interactive safety plan locally.
//  Never sent to a server — privacy-first, works offline.
//
//  GOVERNANCE (G-2 / red line `crisis_data_unencrypted`):
//  Crisis-path data is field-level encrypted AT REST and FAILS CLOSED if
//  encryption cannot be verified. The safety plan (warning signs, coping
//  strategies, trusted people + phone numbers) is AES-GCM encrypted with a
//  per-device key held in the iOS Keychain (device-local, never iCloud-synced).
//  Only the ciphertext is written to disk. If encryption is unavailable we
//  refuse to persist plaintext — the plan stays in memory for the session
//  rather than landing unencrypted on disk.
//

import Foundation
import Combine
import CryptoKit
import Security

// MARK: - Data Model

struct SafetyPlan: Codable {
    var warningSignsINotice: [String] = []
    var internalCopingStrategies: [String] = []
    var peopleAndPlacesThatHelp: [String] = []
    var trustedPeopleToCall: [TrustedPerson] = []
    var professionalContacts: [String] = []
    var environmentSafetySteps: [String] = []
    var lastModified: Date = Date()
}

struct TrustedPerson: Codable, Identifiable {
    var id = UUID()
    var name: String
    var phone: String
}

// MARK: - Crisis Safety-Plan Cipher (at-rest encryption)

/// AES-GCM encryption for the crisis safety plan.
/// Key is per-device, generated once, stored in the iOS Keychain
/// (`WhenUnlockedThisDeviceOnly`, never synced to iCloud). The plaintext plan
/// never leaves memory unencrypted — only the sealed blob is persisted.
enum CrisisSafetyPlanCipher {

    private static let keychainService = "com.amenapp.crisis.safetyPlan"
    private static let keychainAccount = "amen.crisis.safetyPlan.key"

    enum CipherError: Error {
        case sealFailed
        case keychainStoreFailed(OSStatus)
    }

    /// Retrieve or create the device-local encryption key.
    static func encryptionKey() throws -> SymmetricKey {
        if let existing = keychainLoad() {
            return SymmetricKey(data: existing)
        }
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try keychainStore(keyData)
        return key
    }

    /// Encrypt arbitrary data into a combined nonce+ciphertext+tag blob.
    static func encrypt(_ plaintext: Data) throws -> Data {
        let key = try encryptionKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CipherError.sealFailed }
        return combined
    }

    /// Decrypt a combined blob back to the original data.
    static func decrypt(_ ciphertext: Data) throws -> Data {
        let key = try encryptionKey()
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }

    /// Permanently remove the key (account deletion / explicit wipe).
    static func deleteKey() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: Keychain helpers (device-local only)

    private static func keychainLoad() -> Data? {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrService:        keychainService,
            kSecAttrAccount:        keychainAccount,
            kSecReturnData:         true,
            kSecMatchLimit:         kSecMatchLimitOne,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func keychainStore(_ data: Data) throws {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrService:        keychainService,
            kSecAttrAccount:        keychainAccount,
            kSecValueData:          data,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
            kSecAttrAccessible:     kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        } else if status != errSecSuccess {
            throw CipherError.keychainStoreFailed(status)
        }
    }
}

// MARK: - Store

@MainActor
final class SafetyPlanStore: ObservableObject {
    static let shared = SafetyPlanStore()

    @Published var plan: SafetyPlan {
        didSet { save() }
    }

    /// True when the most recent persist wrote encrypted ciphertext to disk.
    /// False means the plan is held in memory only (fail-closed: no plaintext at rest).
    @Published private(set) var isPersistedEncrypted: Bool = false

    /// Encrypted-at-rest key. The legacy plaintext key is migrated then removed.
    private let encKey = "amen.safetyPlan.enc"
    private let legacyPlaintextKey = "amen.safetyPlan"

    private let defaults: UserDefaults

    /// Designated initializer. `UserDefaults` is injectable for tests; production
    /// uses `.standard` via `shared`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // 1. Preferred path: decrypt an existing encrypted blob.
        if let blob = defaults.data(forKey: encKey),
           let clear = try? CrisisSafetyPlanCipher.decrypt(blob),
           let decoded = try? JSONDecoder().decode(SafetyPlan.self, from: clear) {
            plan = decoded
            isPersistedEncrypted = true
            return
        }

        // 2. Migration: an older build may have left a PLAINTEXT plan on disk.
        if let legacy = defaults.data(forKey: legacyPlaintextKey),
           let decoded = try? JSONDecoder().decode(SafetyPlan.self, from: legacy) {
            plan = decoded
            // Re-persist encrypted, then remove the plaintext vulnerability.
            // `save()` is fail-closed; whether or not it succeeds we strip the
            // plaintext copy so crisis data never lingers unencrypted at rest.
            save()
            defaults.removeObject(forKey: legacyPlaintextKey)
            return
        }

        // 3. Fresh state.
        plan = SafetyPlan()
    }

    private func save() {
        plan.lastModified = Date()

        guard let clear = try? JSONEncoder().encode(plan) else {
            isPersistedEncrypted = false
            return
        }

        do {
            let blob = try CrisisSafetyPlanCipher.encrypt(clear)
            defaults.set(blob, forKey: encKey)
            // Defense in depth: never let a plaintext copy survive a save.
            defaults.removeObject(forKey: legacyPlaintextKey)
            isPersistedEncrypted = true
        } catch {
            // FAIL CLOSED: encryption unavailable → do NOT write plaintext.
            // Drop any stale ciphertext/plaintext and keep the plan in memory only.
            defaults.removeObject(forKey: encKey)
            defaults.removeObject(forKey: legacyPlaintextKey)
            isPersistedEncrypted = false
            print("[SafetyPlanStore] FAIL-CLOSED: could not encrypt safety plan; held in memory only. \(error)")
        }
    }

    /// True if the user has entered anything at all.
    var hasContent: Bool {
        !plan.warningSignsINotice.isEmpty ||
        !plan.internalCopingStrategies.isEmpty ||
        !plan.peopleAndPlacesThatHelp.isEmpty ||
        !plan.trustedPeopleToCall.isEmpty ||
        !plan.professionalContacts.isEmpty ||
        !plan.environmentSafetySteps.isEmpty
    }
}
