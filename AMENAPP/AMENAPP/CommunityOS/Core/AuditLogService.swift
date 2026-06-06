// AuditLogService.swift
// AMENAPP — CommunityOS / Core
//
// Phase 1 Core Spine: immutable audit log writer.
//
// Source contracts:
//   C5 §7 "Audit Log Schema" — schema definition
//   C5 §5 I-2 — all admin mutations must write an audit entry atomically
//
// AuditLog documents are append-only. Writes go to:
//   /auditLog/{resourceId}/entries/{entryId}
//
// Audit failures MUST NOT block user actions — log() never throws.

import Foundation
import FirebaseFirestore

// MARK: - AuditLogEntry

/// An immutable record of a state-changing action on a resource.
/// Source: C5 §7 "Audit Log Schema".
struct AuditLogEntry: Codable, Sendable {
    /// Firestore document path of the affected resource (e.g. `/posts/abc`).
    let resourceRef: String
    /// Firebase Auth UID of the actor who performed the action.
    let actorId: String
    /// Verb describing the action (e.g. `"delete_post"`, `"update_user_role"`).
    let action: String
    /// Server-side timestamp. Written by the client but the CF also validates
    /// the timestamp. Do not rely on client accuracy for ordering.
    let timestamp: Date
    /// Arbitrary key-value metadata (e.g. `["orgId": "xyz", "outcome": "success"]`).
    let metadata: [String: String]
}

// MARK: - AuditLogService

/// Singleton actor that writes immutable audit log entries to Firestore.
///
/// Design invariant: `log()` is non-throwing. Audit failures are silently
/// swallowed with a debug-only print — they must never propagate upward
/// and block user-facing actions. (C5 §5 I-2: audit is co-required, but
/// it must fail gracefully, not fail loudly.)
actor AuditLogService {

    // MARK: - Singleton

    static let shared = AuditLogService()

    // MARK: - Private

    private let db: Firestore

    private init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    // MARK: - Log

    /// Writes an immutable audit log entry.
    ///
    /// This method never throws. All errors are swallowed internally.
    /// Do not `await` this call from critical-path UI code; fire-and-forget is fine.
    ///
    /// - Parameters:
    ///   - action: Verb describing the action (e.g. `"delete_post"`).
    ///   - resourceRef: Firestore document path of the affected resource.
    ///   - actorId: Firebase Auth UID of the actor.
    ///   - metadata: Optional key-value pairs for additional context.
    func log(
        action: String,
        resourceRef: String,
        actorId: String,
        metadata: [String: String] = [:]
    ) async {
        guard await AMENFeatureFlags.shared.communityOSEnabled else { return }

        // Derive a stable resourceId from the path by replacing slashes
        let resourceId = resourceRef
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/", with: "_")

        let entry = AuditLogEntry(
            resourceRef: resourceRef,
            actorId: actorId,
            action: action,
            timestamp: Date(),
            metadata: metadata
        )

        do {
            let docData: [String: Any] = [
                "resourceRef": entry.resourceRef,
                "actorId":     entry.actorId,
                "action":      entry.action,
                "timestamp":   Timestamp(date: entry.timestamp),
                "metadata":    entry.metadata
            ]

            try await db
                .collection("auditLog")
                .document(resourceId)
                .collection("entries")
                .addDocument(data: docData)
        } catch {
            // Audit failures must not block user actions — debug-only logging only
            #if DEBUG
            print("[AuditLogService] Non-fatal: failed to write audit entry for action=\(action) resource=\(resourceRef): \(error)")
            #endif
        }
    }
}
