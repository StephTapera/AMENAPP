// ConsentLedgerService.swift — AMEN IntegrationOS
// Firestore-backed consent ledger. Writes to users/{uid}/consentLedger/{entryId}.

import Foundation
import FirebaseFirestore
import FirebaseAuth

actor ConsentLedgerService {
    static let shared = ConsentLedgerService()
    private init() {}

    private let db = Firestore.firestore()

    // MARK: - Grant

    func grant(scope: ConsentScope, providerId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }
        let entry = ConsentLedgerEntry(
            uid: uid,
            scope: scope,
            providerId: providerId,
            granted: true,
            grantedAt: Date(),
            revokedAt: nil,
            userAgent: await deviceUserAgent()
        )
        try db.collection("users").document(uid)
            .collection("consentLedger").document(entry.id)
            .setData(from: entry)
    }

    // MARK: - Revoke

    func revoke(scope: ConsentScope, providerId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }
        let snapshot = try await db.collection("users").document(uid)
            .collection("consentLedger")
            .whereField("scope", isEqualTo: scope.rawValue)
            .whereField("providerId", isEqualTo: providerId)
            .whereField("granted", isEqualTo: true)
            .getDocuments()
        for doc in snapshot.documents {
            try await doc.reference.updateData(["revokedAt": Timestamp(date: Date())])
        }
    }

    // MARK: - Query

    func isGranted(scope: ConsentScope, providerId: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("consentLedger")
                .whereField("scope", isEqualTo: scope.rawValue)
                .whereField("providerId", isEqualTo: providerId)
                .whereField("granted", isEqualTo: true)
                .limit(to: 1)
                .getDocuments()
            return !snapshot.documents.isEmpty
        } catch {
            return false
        }
    }

    func allGrantedScopes() async -> [ConsentScope] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("consentLedger")
                .whereField("granted", isEqualTo: true)
                .getDocuments()
            let entries = snapshot.documents.compactMap { try? $0.data(as: ConsentLedgerEntry.self) }
            return entries.compactMap { $0.revokedAt == nil ? $0.scope : nil }
        } catch {
            return []
        }
    }

    // MARK: - Helpers

    private func deviceUserAgent() async -> String {
        await MainActor.run {
            let device = UIDevice.current
            return "\(device.model)/\(device.systemVersion)"
        }
    }
}

enum IntegrationOSError: LocalizedError {
    case notAuthenticated
    case consentDenied(ConsentScope)
    case minorAccountBlocked(ConsentScope)
    case providerUnavailable(String)
    case costBudgetExceeded
    case webhookSignatureInvalid
    case invalidStoragePath

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:          return "Please sign in to use integrations."
        case .consentDenied(let s):      return "Consent not granted for \(s.rawValue)."
        case .minorAccountBlocked(let s): return "This feature (\(s.rawValue)) is not available for minor accounts."
        case .providerUnavailable(let p): return "Provider \(p) is currently unavailable."
        case .costBudgetExceeded:         return "Monthly integration budget exceeded."
        case .webhookSignatureInvalid:    return "Webhook signature verification failed."
        case .invalidStoragePath:         return "Invalid storage path."
        }
    }
}
