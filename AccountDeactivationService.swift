// AccountDeactivationService.swift
// AMEN App
//
// Handles temporary account deactivation (30-day grace period, reversible)
// vs. permanent deletion (handled by AccountDeletionService).
//
// Deactivation sets:
//   users/{uid}.isDeactivated         = true
//   users/{uid}.deactivatedAt         = Timestamp
//   users/{uid}.deactivationExpiresAt = Timestamp (+30 days)
//
// While deactivated the user is signed out; their profile, posts, and
// follow relationships are hidden from everyone else in the app and in
// Firestore queries that respect `isDeactivated`.
//
// Reactivation clears those fields and signs the user back in normally.

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AccountDeactivationService {

    static let shared = AccountDeactivationService()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Deactivation

    /// Marks the account as deactivated, sets a 30-day expiry, and returns.
    /// Caller is responsible for signing the user out afterwards.
    func deactivateAccount(userId: String, reason: DeactivationReason) async throws {
        let now = Date()
        let expiresAt = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now

        try await db.collection("users").document(userId).updateData([
            "isDeactivated":         true,
            "deactivatedAt":         Timestamp(date: now),
            "deactivationExpiresAt": Timestamp(date: expiresAt),
            "deactivationReason":    reason.rawValue
        ])

        // Log to Firestore audit trail (non-blocking)
        Task {
            try? await db
                .collection("users").document(userId)
                .collection("accountEvents")
                .addDocument(data: [
                    "type":      "deactivated",
                    "reason":    reason.rawValue,
                    "timestamp": Timestamp(date: now),
                    "expiresAt": Timestamp(date: expiresAt)
                ])
        }
    }

    // MARK: - Reactivation

    /// Clears deactivation fields so the user returns to normal active status.
    func reactivateAccount(userId: String) async throws {
        try await db.collection("users").document(userId).updateData([
            "isDeactivated":         FieldValue.delete(),
            "deactivatedAt":         FieldValue.delete(),
            "deactivationExpiresAt": FieldValue.delete(),
            "deactivationReason":    FieldValue.delete()
        ])

        Task {
            try? await db
                .collection("users").document(userId)
                .collection("accountEvents")
                .addDocument(data: [
                    "type":      "reactivated",
                    "timestamp": Timestamp(date: Date())
                ])
        }
    }

    // MARK: - Status Check

    struct DeactivationStatus {
        let isDeactivated: Bool
        let deactivatedAt: Date?
        let expiresAt: Date?
        let reason: DeactivationReason?

        /// Days remaining until the account is auto-deleted (nil if not deactivated)
        var daysRemaining: Int? {
            guard let expires = expiresAt else { return nil }
            let diff = Calendar.current.dateComponents([.day], from: Date(), to: expires)
            return max(0, diff.day ?? 0)
        }

        static let active = DeactivationStatus(
            isDeactivated: false, deactivatedAt: nil, expiresAt: nil, reason: nil
        )
    }

    func checkDeactivationStatus(userId: String) async throws -> DeactivationStatus {
        let doc = try await db.collection("users").document(userId).getDocument()
        guard let data = doc.data(),
              let isDeactivated = data["isDeactivated"] as? Bool,
              isDeactivated else {
            return .active
        }
        let deactivatedAt  = (data["deactivatedAt"]         as? Timestamp)?.dateValue()
        let expiresAt      = (data["deactivationExpiresAt"] as? Timestamp)?.dateValue()
        let reasonRaw      = data["deactivationReason"]     as? String ?? ""
        let reason         = DeactivationReason(rawValue: reasonRaw)
        return DeactivationStatus(
            isDeactivated: true,
            deactivatedAt: deactivatedAt,
            expiresAt: expiresAt,
            reason: reason
        )
    }

    // MARK: - Enum

    enum DeactivationReason: String, CaseIterable, Identifiable {
        case takingABreak     = "taking_a_break"
        case tooMuchTime      = "too_much_time"
        case privacyConcerns  = "privacy_concerns"
        case temporaryAbsence = "temporary_absence"
        case other            = "other"

        var id: String { rawValue }

        var displayTitle: String {
            switch self {
            case .takingABreak:     return "Taking a break"
            case .tooMuchTime:      return "Spending too much time here"
            case .privacyConcerns:  return "Privacy concerns"
            case .temporaryAbsence: return "Temporarily unavailable"
            case .other:            return "Other reason"
            }
        }

        var icon: String {
            switch self {
            case .takingABreak:     return "cup.and.saucer"
            case .tooMuchTime:      return "clock.badge.exclamationmark"
            case .privacyConcerns:  return "lock.shield"
            case .temporaryAbsence: return "airplane"
            case .other:            return "ellipsis.circle"
            }
        }
    }
}
