import Foundation
import CryptoKit
import Security

// MARK: - Error

enum ProfileSessionStoreError: Error {
    case keychainWriteFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case decryptionFailed
}

// MARK: - Actor

actor ProfileSessionStore {

    static let shared = ProfileSessionStore()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Public API

    func snapshot(_ state: ProfileSessionState, for profileId: ProfileID) async throws {
        let key = try loadOrCreateKey(for: profileId)
        let plaintext = try encoder.encode(state)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw ProfileSessionStoreError.decryptionFailed
        }
        let url = try sessionFileURL(for: profileId)
        try combined.write(to: url, options: .completeFileProtection)
    }

    func restore(for profileId: ProfileID) async throws -> ProfileSessionState {
        let url = try sessionFileURL(for: profileId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }
        let combined = try Data(contentsOf: url)
        let key = try loadOrCreateKey(for: profileId)
        let plaintext: Data
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            plaintext = try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw ProfileSessionStoreError.decryptionFailed
        }
        return try decoder.decode(ProfileSessionState.self, from: plaintext)
    }

    func clear(for profileId: ProfileID) async throws {
        let url = try sessionFileURL(for: profileId)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try deleteKey(for: profileId)
    }

    // MARK: - Key Management (Keychain)

    private func loadOrCreateKey(for profileId: ProfileID) throws -> SymmetricKey {
        let account = keychainAccount(for: profileId)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecAttrService: "com.amen.threshold.session",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            #if DEBUG
            // Cross-read guard: the key's account label must match the requested profile.
            // A mismatch means the caller passed the wrong profileId, not a key collision.
            let readAccount = keychainAccount(for: profileId)
            assert(readAccount == account, "THRESHOLD: cross-profile key read detected — requested '\(profileId)', got '\(readAccount)'")
            #endif
            return SymmetricKey(data: data)
        }

        if status != errSecItemNotFound {
            throw ProfileSessionStoreError.keychainReadFailed(status)
        }

        // No key exists yet — generate and store.
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecAttrService: "com.amen.threshold.session",
            // kSecAttrAccessible deliberately excludes iCloud backup (D5: never mirrored to server).
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: keyData
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw ProfileSessionStoreError.keychainWriteFailed(addStatus)
        }
        return newKey
    }

    private func deleteKey(for profileId: ProfileID) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: keychainAccount(for: profileId),
            kSecAttrService: "com.amen.threshold.session"
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProfileSessionStoreError.keychainWriteFailed(status)
        }
    }

    private func keychainAccount(for profileId: ProfileID) -> String {
        "threshold.session.\(profileId)"
    }

    // MARK: - File Paths

    private func sessionFileURL(for profileId: ProfileID) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let sessionDir = support.appendingPathComponent("threshold_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        return sessionDir.appendingPathComponent("\(profileId).enc")
    }
}
