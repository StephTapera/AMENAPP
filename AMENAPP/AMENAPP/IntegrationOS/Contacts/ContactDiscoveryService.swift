// ContactDiscoveryService.swift — AMEN IntegrationOS
// Actor that calls `matchHashedContacts` and `getContactDiscoverySalt` CFs.
// Contacts are hashed locally — raw contact data never leaves the device.

import Foundation
import Contacts
import CryptoKit
import FirebaseFunctions
import FirebaseAuth
import FirebaseRemoteConfig

actor ContactDiscoveryService {
    static let shared = ContactDiscoveryService()
    private init() {}

    private let functions = Functions.functions()
    private let store = CNContactStore()
    private let remoteConfig = RemoteConfig.remoteConfig()
    private var isEnabled: Bool { remoteConfig.configValue(forKey: "integration_contacts_enabled").boolValue }

    // MARK: - Authorization

    func requestAccess() async throws {
        guard isEnabled else { return }
        let status = try await store.requestAccess(for: .contacts)
        if !status { throw IntegrationOSError.consentDenied(.contactsHashedMatch) }
    }

    // MARK: - Discovery Flow

    func discoverContacts() async throws -> [ContactMatch] {
        guard isEnabled else { return [] }
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }

        // Step 1: get salt from CF
        let saltResult = try await functions.httpsCallable("getContactDiscoverySalt").call(["uid": uid])
        guard let saltData = saltResult.data as? [String: Any],
              let salt = saltData["salt"] as? String else {
            throw IntegrationOSError.providerUnavailable("getContactDiscoverySalt")
        }

        // Step 2: hash contact phone numbers locally
        let hashedPhones = try hashLocalContacts(salt: salt)
        guard !hashedPhones.isEmpty else { return [] }

        // Step 3: send hashes to CF — never raw phone numbers
        let matchResult = try await functions.httpsCallable("matchHashedContacts").call([
            "hashedPhones": hashedPhones,
            "limit": 50
        ])

        guard let matchData = matchResult.data as? [String: Any],
              let matches = matchData["matches"] as? [[String: Any]] else {
            return []
        }

        return matches.compactMap { parseMatch($0) }
    }

    // MARK: - Private: Local Hashing

    private func hashLocalContacts(salt: String) throws -> [String] {
        let keysToFetch = [CNContactPhoneNumbersKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        var hashes: [String] = []
        try store.enumerateContacts(with: request) { contact, _ in
            for phone in contact.phoneNumbers {
                let normalized = normalizePhone(phone.value.stringValue)
                guard !normalized.isEmpty else { continue }
                let salted = salt + normalized
                guard let data = salted.data(using: .utf8) else { continue }
                let digest = SHA256.hash(data: data)
                let hex = digest.map { String(format: "%02x", $0) }.joined()
                hashes.append(hex)
            }
        }
        return Array(Set(hashes)) // deduplicate
    }

    private func normalizePhone(_ raw: String) -> String {
        raw.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    }

    private func parseMatch(_ dict: [String: Any]) -> ContactMatch? {
        guard let uid = dict["uid"] as? String,
              let name = dict["displayName"] as? String else { return nil }
        return ContactMatch(
            matchedUID: uid,
            displayName: name,
            avatarURL: dict["avatarURL"] as? String,
            mutualConnectionCount: dict["mutualConnectionCount"] as? Int ?? 0,
            alreadyFollowing: dict["alreadyFollowing"] as? Bool ?? false
        )
    }
}
