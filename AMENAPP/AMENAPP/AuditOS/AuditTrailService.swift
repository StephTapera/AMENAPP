// AuditTrailService.swift — AMEN AuditOS
// Append-only audit trail for GDPR/COPPA compliance.
// Firestore path: auditTrail/{uid}/events/{auto-id}
// INVARIANT: Never updates or deletes events — append only.
import Foundation
import FirebaseFirestore
import FirebaseAuth

enum AuditAction: String, Codable {
    case postCreated        = "post_created"
    case postDeleted        = "post_deleted"
    case commentCreated     = "comment_created"
    case commentDeleted     = "comment_deleted"
    case accountDeleted     = "account_deleted"
    case reportFiled        = "report_filed"
    case banIssued          = "ban_issued"
    case banAppealed        = "ban_appealed"
    case dataExportRequested = "data_export_requested"
    case loginSuccess       = "login_success"
    case loginFailure       = "login_failure"
    case privacySettingChanged = "privacy_setting_changed"
}

struct AuditEvent: Codable {
    let uid: String
    let action: AuditAction
    let metadata: [String: String]
    let timestamp: Double  // server timestamp via FieldValue
    let sessionId: String
}

actor AuditTrailService {
    static let shared = AuditTrailService()
    private init() {}

    private var db: Firestore { Firestore.firestore() }
    private let sessionId = UUID().uuidString

    // MARK: - Append event (never update/delete)
    func logEvent(uid: String, action: AuditAction, metadata: [String: String] = [:]) async {
        guard !uid.isEmpty else { return }
        let data: [String: Any] = [
            "uid": uid,
            "action": action.rawValue,
            "metadata": metadata,
            "timestamp": FieldValue.serverTimestamp(),
            "sessionId": sessionId
        ]
        do {
            // Auto-ID to prevent any overwrite possibility
            try await db.collection("auditTrail").document(uid)
                .collection("events").addDocument(data: data)
        } catch {
            dlog("[AuditOS] logEvent failed: \(error)")
        }
    }

    // MARK: - Fetch recent events (admin use only — Firestore rules enforce server-side)
    func fetchRecentEvents(uid: String, limit: Int = 50) async -> [QueryDocumentSnapshot] {
        do {
            let snapshot = try await db.collection("auditTrail").document(uid)
                .collection("events")
                .order(by: "timestamp", descending: true)
                .limit(to: limit)
                .getDocuments()
            return snapshot.documents
        } catch {
            dlog("[AuditOS] fetchRecentEvents failed: \(error)")
            return []
        }
    }
}
