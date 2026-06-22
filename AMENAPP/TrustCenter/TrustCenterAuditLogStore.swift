import Foundation
import CryptoKit
import Security

final class TrustCenterAuditLogStore {
    static let shared = TrustCenterAuditLogStore()

    private let featureGate: TrustCenterFeatureGate
    private let fileManager: FileManager
    private let storageURL: URL
    private let keychainService = "com.amenapp.trustcenter.auditlog"
    private let keychainAccount = "trust_center_audit_log_key_v1"

    init(
        featureGate: TrustCenterFeatureGate = .disabled,
        fileManager: FileManager = .default,
        storageURL: URL? = nil
    ) {
        self.featureGate = featureGate
        self.fileManager = fileManager
        self.storageURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)
    }

    @discardableResult
    func append(
        verdict: TrustCenterVerdict,
        actionTaken: String,
        isReversibleOrAppealable: Bool,
        timestamp: Date = Date()
    ) throws -> TrustCenterAuditEntry? {
        let entry = TrustCenterAuditEntry(
            timestamp: timestamp,
            category: verdict.reasonCode,
            verdictLevel: verdict.level,
            actionTaken: actionTaken,
            isReversibleOrAppealable: isReversibleOrAppealable
        )
        try append(entry)
        return entry
    }

    func append(_ entry: TrustCenterAuditEntry) throws {
        guard featureGate.isEnabled(.auditLog) else { return }

        let key = try encryptionKey()
        let payload = AuditEntryPayload(entry: entry)
        let plaintext = try Self.encoder.encode(payload)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)

        guard let combined = sealedBox.combined else {
            throw TrustCenterAuditLogStoreError.encryptionFailed
        }

        var records = try loadEncryptedRecords()
        records.append(
            EncryptedAuditRecord(
                id: entry.id,
                timestamp: entry.timestamp,
                ciphertext: combined
            )
        )
        try persistEncryptedRecords(records)
    }

    func entries(limit: Int? = nil) throws -> [TrustCenterAuditEntry] {
        guard featureGate.isEnabled(.auditLog) else { return [] }

        let key = try encryptionKey()
        let records = try loadEncryptedRecords()
            .sorted { $0.timestamp > $1.timestamp }
        let limitedRecords = limit.map { Array(records.prefix(max(0, $0))) } ?? records

        return try limitedRecords.map { record in
            let sealedBox = try AES.GCM.SealedBox(combined: record.ciphertext)
            let plaintext = try AES.GCM.open(sealedBox, using: key)
            let payload = try Self.decoder.decode(AuditEntryPayload.self, from: plaintext)
            return payload.entry
        }
    }

    func clearLocalEntries() throws {
        guard featureGate.isEnabled(.auditLog) else { return }
        guard fileManager.fileExists(atPath: storageURL.path) else { return }
        try fileManager.removeItem(at: storageURL)
    }

    private func loadEncryptedRecords() throws -> [EncryptedAuditRecord] {
        guard fileManager.fileExists(atPath: storageURL.path) else { return [] }
        let data = try Data(contentsOf: storageURL)
        return try Self.decoder.decode([EncryptedAuditRecord].self, from: data)
    }

    private func persistEncryptedRecords(_ records: [EncryptedAuditRecord]) throws {
        let directoryURL = storageURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let data = try Self.encoder.encode(records)
        try data.write(to: storageURL, options: .atomic)

        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: storageURL.path
        )
        #endif
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let existingKeyData = loadKeyDataFromKeychain() {
            return SymmetricKey(data: existingKeyData)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try storeKeyDataInKeychain(keyData)
        return key
    }

    private func loadKeyDataFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func storeKeyDataInKeychain(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TrustCenterAuditLogStoreError.keychainStoreFailed(status)
        }
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return baseURL
            .appendingPathComponent("TrustCenter", isDirectory: true)
            .appendingPathComponent("audit-log-v1.json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum TrustCenterAuditLogStoreError: LocalizedError {
    case encryptionFailed
    case keychainStoreFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Trust Center audit entry encryption failed."
        case .keychainStoreFailed(let status):
            return "Trust Center audit log keychain write failed: \(status)."
        }
    }
}

private struct EncryptedAuditRecord: Codable {
    let id: UUID
    let timestamp: Date
    let ciphertext: Data
}

private struct AuditEntryPayload: Codable {
    let id: UUID
    let timestamp: Date
    let category: String
    let verdictLevel: String
    let actionTaken: String
    let isReversibleOrAppealable: Bool

    init(entry: TrustCenterAuditEntry) {
        self.id = entry.id
        self.timestamp = entry.timestamp
        self.category = entry.category
        self.verdictLevel = entry.verdictLevel.rawValue
        self.actionTaken = entry.actionTaken
        self.isReversibleOrAppealable = entry.isReversibleOrAppealable
    }

    var entry: TrustCenterAuditEntry {
        TrustCenterAuditEntry(
            id: id,
            timestamp: timestamp,
            category: category,
            verdictLevel: TrustCenterVerdictLevel(rawValue: verdictLevel) ?? .caution,
            actionTaken: actionTaken,
            isReversibleOrAppealable: isReversibleOrAppealable
        )
    }
}
