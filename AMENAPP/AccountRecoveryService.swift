// AccountRecoveryService.swift
// AMENAPP
//
// OS-20: Recovery OS — soft-delete with 30-day recovery window.
//
// Flow:
//   scheduleAccountDeletion() — marks users/{uid} with deletedAt + status: "pending_deletion".
//     The Auth account is kept alive; the app signs the user out locally.
//     A scheduled Cloud Function (processAccountDeletion, runs daily) hard-deletes after 30 days.
//
//   cancelScheduledDeletion() — removes deletedAt/status flag within 30 days.
//     Restores full access. User signs back in normally.
//
//   checkPendingDeletion() — returns DeletionStatus: .notScheduled / .scheduled(daysRemaining)
//
// The existing AccountDeletionService.deleteAccount() remains available for users who want
// immediate hard-delete (with full purge + Auth delete) per Apple Guideline 5.1.1.

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - DeletionStatus

enum DeletionStatus: Equatable {
    case notScheduled
    case scheduled(daysRemaining: Int)
    case expired
}

// MARK: - AccountRecoveryService

@MainActor
final class AccountRecoveryService {

    static let shared = AccountRecoveryService()
    private init() {}

    private let db = Firestore.firestore()
    private let recoveryWindowDays = 30

    // MARK: - Schedule Deletion (Soft Delete)

    /// Marks the account as pending deletion. The Auth account is preserved for
    /// `recoveryWindowDays` so the user can cancel and recover.
    ///
    /// After calling this, sign the user out locally — they can recover by signing back in
    /// within the 30-day window.
    ///
    /// The `processAccountDeletion` Cloud Function runs daily and hard-deletes any
    /// account whose `deletedAt` is more than 30 days ago.
    func scheduleAccountDeletion(userId: String) async throws {
        let now = Timestamp(date: Date())
        try await db.collection("users").document(userId).updateData([
            "status": "pending_deletion",
            "deletedAt": now,
            "recoveryDeadline": Timestamp(date: Calendar.current.date(
                byAdding: .day, value: recoveryWindowDays, to: Date()
            ) ?? Date())
        ])

        // Sign out locally — the Auth account is preserved server-side for recovery.
        try Auth.auth().signOut()
    }

    // MARK: - Cancel Scheduled Deletion (Recovery)

    /// Restores a soft-deleted account within the recovery window.
    /// Call after the user signs back in and chooses "Recover my account".
    ///
    /// - Throws: `RecoveryError.recoveryWindowExpired` if 30 days have passed.
    func cancelScheduledDeletion(userId: String) async throws {
        let status = try await checkPendingDeletion(userId: userId)
        guard case .scheduled = status else {
            if case .expired = status {
                throw RecoveryError.recoveryWindowExpired
            }
            return // Nothing to cancel.
        }

        try await db.collection("users").document(userId).updateData([
            "status": FieldValue.delete(),
            "deletedAt": FieldValue.delete(),
            "recoveryDeadline": FieldValue.delete()
        ])
    }

    // MARK: - Check Pending Deletion

    /// Returns the current deletion status for the given user.
    func checkPendingDeletion(userId: String) async throws -> DeletionStatus {
        let doc = try await db.collection("users").document(userId).getDocument()
        guard let data = doc.data() else { return .notScheduled }

        guard let status = data["status"] as? String, status == "pending_deletion",
              let recoveryDeadlineTimestamp = data["recoveryDeadline"] as? Timestamp else {
            return .notScheduled
        }

        let deadline = recoveryDeadlineTimestamp.dateValue()
        let now = Date()

        if now >= deadline {
            return .expired
        }

        let daysRemaining = Calendar.current.dateComponents([.day], from: now, to: deadline).day ?? 0
        return .scheduled(daysRemaining: max(0, daysRemaining))
    }
}

// MARK: - RecoveryError

enum RecoveryError: LocalizedError {
    case recoveryWindowExpired
    case accountNotFound

    var errorDescription: String? {
        switch self {
        case .recoveryWindowExpired:
            return "The 30-day recovery window has passed. Your account has been permanently deleted."
        case .accountNotFound:
            return "Account not found. Please contact support if you believe this is an error."
        }
    }
}
