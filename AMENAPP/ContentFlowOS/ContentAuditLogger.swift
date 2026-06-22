// ContentAuditLogger.swift
// AMENAPP — ContentFlowOS
// Writes every share / forward / approval / denial decision to Firestore auditLog.

import Foundation
import FirebaseFirestore

enum ContentAuditLogger {
    private static let db = Firestore.firestore()

    static func log(
        contentId: String,
        contentType: String,
        actorId: String,
        action: String,
        destination: String?,
        isExternal: Bool,
        wasAnonymous: Bool,
        approvalOutcome: String?
    ) {
        let entry: [String: Any] = [
            "contentId":       contentId,
            "contentType":     contentType,
            "actorId":         actorId,
            "action":          action,
            "destination":     destination as Any,
            "isExternal":      isExternal,
            "wasAnonymous":    wasAnonymous,
            "approvalOutcome": approvalOutcome as Any,
            "timestamp":       FieldValue.serverTimestamp()
        ]
        // Fire-and-forget — audit log failure must not block the user action
        db.collection("auditLog").addDocument(data: entry) { error in
            if let error {
                // Log locally but never surface to user
                print("[AuditLog] write failed: \(error.localizedDescription)")
            }
        }
    }
}
