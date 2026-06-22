// AmenRoleManager.swift
// AMENAPP — CommunityOS/Identity
//
// Role assignment and management for all context types (church | space | org | team).
//
// Design rules:
//   - Soft-delete only: revoke sets isActive = false + revokedAt; never deletes documents.
//   - All mutations call AmenAuditLogService.log() with a .roleChange event.
//   - transferOwnership creates new owner role and revokes old, logging both events.
//   - currentUserRole returns .visitor if no active membership found.
//
// Firestore path convention: /roles/{contextType}/{contextId}/members/{userId}
//
// Phase 1 Agent A2 — Identity & Trust

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - RoleMembership

/// A single role assignment record. Stored at
/// /roles/{contextType}/{contextId}/members/{userId}
struct RoleMembership: Codable, Identifiable {
    /// Firestore document ID — typically the userId for easy lookup.
    var id: String

    /// UID of the user this membership belongs to.
    var userId: String

    /// The canonical role assigned.
    var role: AmenRole

    /// Context type: "church" | "space" | "org" | "team"
    var contextType: String

    /// Firestore ID of the context (churchId, spaceId, orgId, or teamId).
    var contextId: String

    /// UID of the user who granted this role.
    var grantedBy: String

    /// Timestamp when this role was granted.
    var grantedAt: Date

    /// Timestamp when this role was revoked. nil if still active.
    var revokedAt: Date?

    /// Whether this membership is currently active.
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case role
        case contextType
        case contextId
        case grantedBy
        case grantedAt
        case revokedAt
        case isActive
    }
}

// MARK: - AmenRoleManager

@MainActor
class AmenRoleManager: ObservableObject {

    static let shared = AmenRoleManager()

    private let db = Firestore.firestore()
    private let auditLog = AmenAuditLogService.shared

    private init() {}

    // MARK: - Assign Role

    /// Assigns a role to a user within a given context.
    /// Writes the RoleMembership document and logs a .roleChange audit event.
    ///
    /// - Parameters:
    ///   - role:        The AmenRole to assign.
    ///   - userId:      UID of the user receiving the role.
    ///   - contextType: "church" | "space" | "org" | "team"
    ///   - contextId:   Firestore ID of the context.
    ///   - grantedBy:   UID of the admin performing the assignment.
    func assignRole(
        _ role: AmenRole,
        to userId: String,
        in contextType: String,
        contextId: String,
        grantedBy: String
    ) async throws {
        let ref = memberRef(contextType: contextType, contextId: contextId, userId: userId)

        let membership = RoleMembership(
            id:          userId,
            userId:      userId,
            role:        role,
            contextType: contextType,
            contextId:   contextId,
            grantedBy:   grantedBy,
            grantedAt:   Date(),
            revokedAt:   nil,
            isActive:    true
        )

        let data = try encodeMembership(membership)
        try await ref.setData(data, merge: false)

        await auditLog.log(
            event:        .roleChange,
            actorId:      grantedBy,
            actorRole:    "",
            resourceType: "role",
            resourceId:   ref.documentID,
            targetId:     userId,
            metadata:     [
                "newRole":     role.rawValue,
                "contextType": contextType,
                "contextId":   contextId,
                "action":      "assign"
            ],
            outcome:  .success,
            churchId: contextType == "church" ? contextId : nil,
            spaceId:  contextType == "space"  ? contextId : nil
        )
    }

    // MARK: - Revoke Role

    /// Soft-revokes a user's role in a given context.
    /// Sets isActive = false and revokedAt = now. The document is never deleted.
    ///
    /// - Parameters:
    ///   - userId:      UID of the user whose role is being revoked.
    ///   - contextType: "church" | "space" | "org" | "team"
    ///   - contextId:   Firestore ID of the context.
    ///   - revokedBy:   UID of the admin performing the revocation.
    func revokeRole(
        userId: String,
        in contextType: String,
        contextId: String,
        revokedBy: String
    ) async throws {
        let ref = memberRef(contextType: contextType, contextId: contextId, userId: userId)

        // Read current role for audit metadata
        let snapshot = try await ref.getDocument()
        let currentRoleRaw = snapshot.data()?["role"] as? String ?? "unknown"

        let updateData: [String: Any] = [
            "isActive":  false,
            "revokedAt": Timestamp(date: Date())
        ]
        try await ref.updateData(updateData)

        await auditLog.log(
            event:        .roleChange,
            actorId:      revokedBy,
            actorRole:    "",
            resourceType: "role",
            resourceId:   ref.documentID,
            targetId:     userId,
            metadata:     [
                "revokedRole": currentRoleRaw,
                "contextType": contextType,
                "contextId":   contextId,
                "action":      "revoke"
            ],
            outcome:  .success,
            churchId: contextType == "church" ? contextId : nil,
            spaceId:  contextType == "space"  ? contextId : nil
        )
    }

    // MARK: - Fetch Members

    /// Returns all active RoleMembership records for a given context.
    func fetchMembers(contextType: String, contextId: String) async throws -> [RoleMembership] {
        let snap = try await db
            .collection("roles")
            .document(contextType)
            .collection(contextId)
            .document("members")
            .collection("_list") // flat list sub-collection for queryability
            .whereField("isActive", isEqualTo: true)
            .getDocuments()

        return snap.documents.compactMap { parseMembership(from: $0) }
    }

    /// Returns all active RoleMembership records for a given user across all contexts.
    ///
    /// Note: This requires a Firestore collection group query on "members".
    /// Ensure the Firestore index for "userId" + "isActive" on the members group is deployed.
    func fetchUserRoles(userId: String) async throws -> [RoleMembership] {
        let snap = try await db
            .collectionGroup("_list")
            .whereField("userId", isEqualTo: userId)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()

        return snap.documents.compactMap { parseMembership(from: $0) }
    }

    // MARK: - Current User Convenience

    /// Returns the canonical AmenRole for the currently authenticated Firebase user
    /// within a given context. Returns .visitor if no active membership is found.
    ///
    /// - Parameters:
    ///   - contextType: "church" | "space" | "org" | "team"
    ///   - contextId:   Firestore ID of the context.
    func currentUserRole(in contextType: String, contextId: String) async throws -> AmenRole {
        guard let uid = Auth.auth().currentUser?.uid else {
            return .visitor
        }

        let ref = memberRef(contextType: contextType, contextId: contextId, userId: uid)
        let doc = try await ref.getDocument()

        guard
            let data     = doc.data(),
            let isActive = data["isActive"] as? Bool,
            isActive,
            let roleRaw  = data["role"] as? String,
            let role     = AmenRole(rawValue: roleRaw)
        else {
            return .visitor
        }

        return role
    }

    // MARK: - Transfer Ownership

    /// Atomically transfers ownership from one user to another within a context.
    /// Creates the new owner membership, revokes the old one, and logs both audit events.
    ///
    /// - Parameters:
    ///   - from:         UID of the current owner.
    ///   - to:           UID of the new owner.
    ///   - contextType:  "church" | "space" | "org" | "team"
    ///   - contextId:    Firestore ID of the context.
    ///   - authorizedBy: UID of the admin authorizing the transfer (usually == from or executiveAdmin).
    func transferOwnership(
        from fromUserId: String,
        to toUserId: String,
        contextType: String,
        contextId: String,
        authorizedBy: String
    ) async throws {
        let fromRef = memberRef(contextType: contextType, contextId: contextId, userId: fromUserId)
        let toRef   = memberRef(contextType: contextType, contextId: contextId, userId: toUserId)

        let now = Date()
        let nowTS = Timestamp(date: now)

        // Build new owner membership for the recipient
        let newOwnership = RoleMembership(
            id:          toUserId,
            userId:      toUserId,
            role:        .owner,
            contextType: contextType,
            contextId:   contextId,
            grantedBy:   authorizedBy,
            grantedAt:   now,
            revokedAt:   nil,
            isActive:    true
        )
        let newOwnerData = try encodeMembership(newOwnership)

        // Revoke old owner's membership
        let revokeData: [String: Any] = [
            "isActive":  false,
            "revokedAt": nowTS
        ]

        // Use a Firestore batch for atomicity
        let batch = db.batch()
        batch.setData(newOwnerData, forDocument: toRef, merge: false)
        batch.updateData(revokeData, forDocument: fromRef)
        try await batch.commit()

        // Log both events (best-effort)
        await auditLog.log(
            event:        .roleChange,
            actorId:      authorizedBy,
            actorRole:    AmenRole.owner.rawValue,
            resourceType: "role",
            resourceId:   toRef.documentID,
            targetId:     toUserId,
            metadata:     [
                "newRole":     AmenRole.owner.rawValue,
                "contextType": contextType,
                "contextId":   contextId,
                "action":      "transfer_ownership_grant",
                "fromUserId":  fromUserId
            ],
            outcome:  .success,
            churchId: contextType == "church" ? contextId : nil,
            spaceId:  contextType == "space"  ? contextId : nil
        )

        await auditLog.log(
            event:        .roleChange,
            actorId:      authorizedBy,
            actorRole:    AmenRole.owner.rawValue,
            resourceType: "role",
            resourceId:   fromRef.documentID,
            targetId:     fromUserId,
            metadata:     [
                "revokedRole": AmenRole.owner.rawValue,
                "contextType": contextType,
                "contextId":   contextId,
                "action":      "transfer_ownership_revoke",
                "toUserId":    toUserId
            ],
            outcome:  .success,
            churchId: contextType == "church" ? contextId : nil,
            spaceId:  contextType == "space"  ? contextId : nil
        )
    }

    // MARK: - Private Helpers

    /// Canonical Firestore reference for a user's membership document.
    /// Path: /roles/{contextType}/{contextId}/members/{userId}
    private func memberRef(contextType: String, contextId: String, userId: String) -> DocumentReference {
        db.collection("roles")
            .document(contextType)
            .collection(contextId)
            .document("members")
            .collection("_list")
            .document(userId)
    }

    private func encodeMembership(_ membership: RoleMembership) throws -> [String: Any] {
        var data: [String: Any] = [
            "id":          membership.id,
            "userId":      membership.userId,
            "role":        membership.role.rawValue,
            "contextType": membership.contextType,
            "contextId":   membership.contextId,
            "grantedBy":   membership.grantedBy,
            "grantedAt":   Timestamp(date: membership.grantedAt),
            "isActive":    membership.isActive
        ]
        if let revokedAt = membership.revokedAt {
            data["revokedAt"] = Timestamp(date: revokedAt)
        }
        return data
    }

    private func parseMembership(from doc: QueryDocumentSnapshot) -> RoleMembership? {
        let data = doc.data()
        guard
            let userId      = data["userId"] as? String,
            let roleRaw     = data["role"] as? String,
            let role        = AmenRole(rawValue: roleRaw),
            let contextType = data["contextType"] as? String,
            let contextId   = data["contextId"] as? String,
            let grantedBy   = data["grantedBy"] as? String,
            let grantedTS   = data["grantedAt"] as? Timestamp,
            let isActive    = data["isActive"] as? Bool
        else {
            return nil
        }

        let revokedAt: Date? = (data["revokedAt"] as? Timestamp)?.dateValue()

        return RoleMembership(
            id:          doc.documentID,
            userId:      userId,
            role:        role,
            contextType: contextType,
            contextId:   contextId,
            grantedBy:   grantedBy,
            grantedAt:   grantedTS.dateValue(),
            revokedAt:   revokedAt,
            isActive:    isActive
        )
    }
}
