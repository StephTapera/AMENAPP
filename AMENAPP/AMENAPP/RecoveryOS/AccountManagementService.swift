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
        // Always derive uid from the authenticated session — Cloud Function also validates
        // the token-authenticated uid server-side, but sending the wrong uid wastes a call.
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "AccountManagement", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user."])
        }
        isExportPending = true
        _ = try await functions.httpsCallable("exportUserData").call(["uid": currentUser.uid])
        dlog("[RecoveryOS] Data export requested for \(currentUser.uid.prefix(8))…")
        isExportPending = false
    }

    // MARK: - Soft Delete (30-day grace period then hard delete)
    func softDeleteAccount(uid: String) async throws {
        // Always derive uid from the authenticated session — never trust the caller's parameter.
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "AccountManagement", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user."])
        }
        let safeUID = currentUser.uid
        let deadline = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        try await db.collection("users").document(safeUID).updateData([
            "deletedAt": FieldValue.serverTimestamp(),
            "deletionScheduledFor": Timestamp(date: deadline)
        ])
        try Auth.auth().signOut()
    }

    // MARK: - Hard Delete (immediate, via Cloud Function — no 30-day grace)
    func hardDeleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        // Server CF: userAccountDeletionCascade — matched per audit AUTH-callable-mismatch
        _ = try await functions.httpsCallable("userAccountDeletionCascade").call(["uid": user.uid])
        try Auth.auth().signOut()
    }
}
