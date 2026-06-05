// AmenAuditLogService.swift
// AMENAPP — CommunityOS/Identity
//
// Immutable audit log for all admin and destructive mutations.
//
// Design rules (C5 §7, Invariant I-2):
//   - Audit log entries are WRITE-ONCE. Never update or delete.
//   - log() is best-effort: it uses `try?` and NEVER throws or interrupts the main flow.
//   - Firestore rules enforce no-update/delete on /auditLog.
//   - fetchLog / fetchActorLog ARE allowed to throw — they are query helpers, not safety paths.
//
// Phase 1 Agent A2 — Identity & Trust

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - AuditEventType

/// All event types that require an audit entry per C5 §7.
enum AuditEventType: String, Codable, CaseIterable {
    case roleChange         = "role_change"
    case contentDelete      = "content_delete"
    case contentRestore     = "content_restore"
    case memberRemove       = "member_remove"
    case memberBan          = "member_ban"
    case contentModerate    = "content_moderate"
    case appealSubmit       = "appeal_submit"
    case appealResolve      = "appeal_resolve"
    case settingsChange     = "settings_change"
    case accountRecovery    = "account_recovery"

    /// Human-readable description for admin UI display.
    var displayName: String {
        switch self {
        case .roleChange:       return "Role Changed"
        case .contentDelete:    return "Content Deleted"
        case .contentRestore:   return "Content Restored"
        case .memberRemove:     return "Member Removed"
        case .memberBan:        return "Member Banned"
        case .contentModerate:  return "Content Moderated"
        case .appealSubmit:     return "Appeal Submitted"
        case .appealResolve:    return "Appeal Resolved"
        case .settingsChange:   return "Settings Changed"
        case .accountRecovery:  return "Account Recovery"
        }
    }
}

// MARK: - AuditLogEntry

/// A single immutable audit record. Stored at /auditLog/{eventId}.
/// Matches the schema in C5 §7 exactly.
struct AuditLogEntry: Codable, Identifiable {
    /// Firestore document ID — auto-generated on write.
    var id: String

    /// UID of the user who performed the action.
    var actorId: String

    /// Role of the actor at the time of the action.
    var actorRole: String

    /// UID of the affected user (if applicable). nil for org/content events.
    var targetId: String?

    /// Category of the event.
    var eventType: AuditEventType

    /// Resource type (e.g. "post", "user", "organization").
    var resourceType: String

    /// Firestore document ID of the affected resource.
    var resourceId: String

    /// Arbitrary key-value metadata (e.g. old/new role, reason for deletion).
    var metadata: [String: String]

    /// Server timestamp — set by AmenAuditLogService, never by the caller.
    var timestamp: Date

    /// HMAC-SHA256 hash of the actor's IP address. Never the raw IP.
    /// Optional — present only when IP is available from server context (CF-written entries).
    var ipAddressHash: String?

    /// Organization context.
    var orgId: String?

    /// Church context.
    var churchId: String?

    /// Space context.
    var spaceId: String?

    /// Outcome of the action.
    var outcome: AuditOutcome

    /// Codable conformance uses explicit CodingKeys to match the C5 §7 Firestore schema.
    enum CodingKeys: String, CodingKey {
        case id
        case actorId        = "actorUid"
        case actorRole
        case targetId       = "targetUid"
        case eventType      = "action"
        case resourceType
        case resourceId
        case metadata
        case timestamp
        case ipAddressHash  = "ipHash"
        case orgId
        case churchId
        case spaceId
        case outcome
    }
}

// MARK: - AuditOutcome

enum AuditOutcome: String, Codable {
    case success    = "success"
    case denied     = "denied"
    case escalated  = "escalated"
}

// MARK: - AmenAuditLogService

@MainActor
class AmenAuditLogService: ObservableObject {

    static let shared = AmenAuditLogService()

    private let db = Firestore.firestore()
    private let collectionPath = "auditLog"

    private init() {}

    // MARK: - Write (best-effort, never throws)

    /// Appends a new audit log entry to /auditLog.
    /// Uses try? — a write failure is silently swallowed so it never interrupts
    /// the main flow. Entries are never updated or deleted.
    ///
    /// - Parameters:
    ///   - event:        The type of event being logged.
    ///   - actorId:      UID of the user who triggered the action.
    ///   - actorRole:    Role string of the actor (AmenRole.rawValue).
    ///   - resourceType: The resource collection name (e.g. "post", "user").
    ///   - resourceId:   Firestore document ID of the resource.
    ///   - targetId:     UID of the affected user, if applicable.
    ///   - metadata:     Arbitrary key/value pairs for debugging/audit purposes.
    ///   - outcome:      Result of the action (.success / .denied / .escalated).
    ///   - orgId:        Organization context (optional).
    ///   - churchId:     Church context (optional).
    ///   - spaceId:      Space context (optional).
    func log(
        event: AuditEventType,
        actorId: String,
        actorRole: String = "",
        resourceType: String,
        resourceId: String,
        targetId: String? = nil,
        metadata: [String: String] = [:],
        outcome: AuditOutcome = .success,
        orgId: String? = nil,
        churchId: String? = nil,
        spaceId: String? = nil
    ) async {
        let ref = db.collection(collectionPath).document()
        let entry: [String: Any] = buildEntryPayload(
            id: ref.documentID,
            event: event,
            actorId: actorId,
            actorRole: actorRole,
            resourceType: resourceType,
            resourceId: resourceId,
            targetId: targetId,
            metadata: metadata,
            outcome: outcome,
            orgId: orgId,
            churchId: churchId,
            spaceId: spaceId
        )
        // Best-effort: swallow all errors — audit writes MUST NOT interrupt the main flow.
        try? await ref.setData(entry)
    }

    // MARK: - Convenience: derive actorRole from current Firebase Auth user

    /// Convenience overload that resolves the current user's role from AmenRBACService
    /// before writing. Falls back to "unknown" if resolution fails.
    func logCurrentUser(
        event: AuditEventType,
        resourceType: String,
        resourceId: String,
        targetId: String? = nil,
        metadata: [String: String] = [:],
        outcome: AuditOutcome = .success,
        contextType: String? = nil,
        contextId: String? = nil,
        orgId: String? = nil,
        churchId: String? = nil,
        spaceId: String? = nil
    ) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        var roleString = "unknown"
        if let ct = contextType, let ci = contextId {
            if let resolved = try? await AmenRBACService.shared.resolveRole(
                for: uid, in: ct, contextId: ci
            ) {
                roleString = resolved.rawValue
            }
        }

        await log(
            event: event,
            actorId: uid,
            actorRole: roleString,
            resourceType: resourceType,
            resourceId: resourceId,
            targetId: targetId,
            metadata: metadata,
            outcome: outcome,
            orgId: orgId,
            churchId: churchId,
            spaceId: spaceId
        )
    }

    // MARK: - Fetch

    /// Returns up to `limit` audit entries for a given resource, ordered by timestamp descending.
    /// Requires ExecutiveAdmin or Owner role — enforce this check before calling.
    func fetchLog(resourceId: String, limit: Int = 50) async throws -> [AuditLogEntry] {
        let snap = try await db.collection(collectionPath)
            .whereField("resourceId", isEqualTo: resourceId)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { parseEntry(from: $0) }
    }

    /// Returns up to `limit` audit entries for a given actor, ordered by timestamp descending.
    func fetchActorLog(actorId: String, limit: Int = 50) async throws -> [AuditLogEntry] {
        let snap = try await db.collection(collectionPath)
            .whereField("actorUid", isEqualTo: actorId)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { parseEntry(from: $0) }
    }

    // MARK: - Private Helpers

    private func buildEntryPayload(
        id: String,
        event: AuditEventType,
        actorId: String,
        actorRole: String,
        resourceType: String,
        resourceId: String,
        targetId: String?,
        metadata: [String: String],
        outcome: AuditOutcome,
        orgId: String?,
        churchId: String?,
        spaceId: String?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "actorUid":     actorId,
            "actorRole":    actorRole,
            "action":       event.rawValue,
            "resourceType": resourceType,
            "resourceId":   resourceId,
            "metadata":     metadata,
            "timestamp":    Timestamp(date: Date()),
            "outcome":      outcome.rawValue
        ]
        if let tid = targetId    { payload["targetUid"] = tid }
        if let oid = orgId       { payload["orgId"] = oid }
        if let cid = churchId    { payload["churchId"] = cid }
        if let sid = spaceId     { payload["spaceId"] = sid }
        // ipHash is only set by Cloud Functions via Admin SDK — never by the iOS client.
        return payload
    }

    private func parseEntry(from doc: QueryDocumentSnapshot) -> AuditLogEntry? {
        let data = doc.data()
        guard
            let actorId      = data["actorUid"] as? String,
            let eventRaw     = data["action"] as? String,
            let eventType    = AuditEventType(rawValue: eventRaw),
            let resourceType = data["resourceType"] as? String,
            let resourceId   = data["resourceId"] as? String,
            let outcomeRaw   = data["outcome"] as? String,
            let outcome      = AuditOutcome(rawValue: outcomeRaw),
            let ts           = data["timestamp"] as? Timestamp
        else {
            return nil
        }

        return AuditLogEntry(
            id:            doc.documentID,
            actorId:       actorId,
            actorRole:     data["actorRole"] as? String ?? "",
            targetId:      data["targetUid"] as? String,
            eventType:     eventType,
            resourceType:  resourceType,
            resourceId:    resourceId,
            metadata:      data["metadata"] as? [String: String] ?? [:],
            timestamp:     ts.dateValue(),
            ipAddressHash: data["ipHash"] as? String,
            orgId:         data["orgId"] as? String,
            churchId:      data["churchId"] as? String,
            spaceId:       data["spaceId"] as? String,
            outcome:       outcome
        )
    }
}
