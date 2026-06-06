// AccountManagementService.swift — AMEN RecoveryOS
// Ban appeals, data export, soft-delete → hard delete pipeline.
// GDPR Art. 17 (right to erasure) + App Store §5.1.1 (account deletion ≤3 taps).
import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class AccountManagementService: ObservableObject {
    static let shared = AccountManagementService()
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

    // MARK: - Data Export (GDPR Art. 20 — right to portability)
    func requestDataExport(uid: String) async throws {
        isExportPending = true
        _ = try await functions.httpsCallable("exportUserData").call(["uid": uid])
        dlog("[RecoveryOS] Data export requested for \(uid)")
        isExportPending = false
    }

    // MARK: - Soft Delete (30-day grace period then hard delete)
    func softDeleteAccount(uid: String) async throws {
        let deadline = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        try await db.collection("users").document(uid).updateData([
            "deletedAt": FieldValue.serverTimestamp(),
            "deletionScheduledFor": Timestamp(date: deadline)
        ])
        try Auth.auth().signOut()
    }

    // MARK: - Hard Delete (immediate, via Cloud Function — no 30-day grace)
    func hardDeleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        _ = try await functions.httpsCallable("deleteUserAccount").call(["uid": user.uid])
        try Auth.auth().signOut()
    }
}
