// AccountRecoveryService.swift — AMEN RecoveryOS
// Ban appeals, data export, soft-delete → hard delete pipeline.
import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class AccountRecoveryService: ObservableObject {
    static let shared = AccountRecoveryService()
    private init() {}

    @Published var isExportPending: Bool = false
    @Published var appealSubmitted: Bool = false

    private var db: Firestore { Firestore.firestore() }
    private var functions: Functions { Functions.functions() }

    // MARK: - Ban Appeal
    func submitBanAppeal(uid: String, reason: String) async throws {
        let data: [String: Any] = [
            "uid": uid,
            "reason": reason,
            "submittedAt": FieldValue.serverTimestamp(),
            "status": "pending"
        ]
        try await db.collection("banAppeals").document(uid).setData(data)
        appealSubmitted = true
    }

    // MARK: - Data Export (GDPR Art. 20)
    func requestDataExport(uid: String) async throws {
        isExportPending = true
        // Cloud Function emails the export package within 72 hours
        let result = try await functions.httpsCallable("exportUserData").call(["uid": uid])
        dlog("[RecoveryOS] Data export requested: \(result.data)")
        isExportPending = false
    }

    // MARK: - Soft Delete (30-day grace period)
    func softDeleteAccount(uid: String) async throws {
        try await db.collection("users").document(uid).updateData([
            "deletedAt": FieldValue.serverTimestamp(),
            "deletionScheduledFor": Timestamp(date: Calendar.current.date(byAdding: .day, value: 30, to: Date())!)
        ])
        // Sign out after soft delete
        try Auth.auth().signOut()
    }

    // MARK: - Hard Delete (immediate, no grace)
    func hardDeleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        _ = try await functions.httpsCallable("deleteUserAccount").call(["uid": user.uid])
        try Auth.auth().signOut()
    }
}
