//
//  RolePermissionService.swift
//  AMENAPP
//
//  Validates role-based permissions for church staff actions.
//
//  Design rules:
//  - `can(_:userId:churchId:)` is synchronous and safe to call in view render paths.
//  - All sensitive mutations (assignRole, revokeRole) gate on `manageAdmins` before
//    touching Firestore, providing a defence-in-depth check alongside Firestore Rules.
//  - `currentUserRole` and `currentPermissions` are populated by `fetchRole(for:churchId:)`
//    and remain nil until that call succeeds, causing `can(...)` to return false by default.
//

import Foundation
import Combine
// import FirebaseFirestore   ← add when Firebase SDK is linked
// import FirebaseAuth        ← add when Firebase SDK is linked

// MARK: - Service

/// Validates role-based permissions for church staff actions.
///
/// Firestore collection: `churchStaffRoles`
/// Document path: `churchStaffRoles/{churchId}_{userId}`
///
/// All sensitive mutations must call `can(_:userId:churchId:)` and receive `true`
/// before proceeding. This service is the single authoritative source for client-side
/// permission evaluation.
@MainActor
final class RolePermissionService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var currentUserRole: ChurchRole?
    @Published private(set) var currentPermissions: RolePermissions?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?

    // Firestore reference placeholder:
    // private lazy var db = Firestore.firestore()

    // MARK: - Fetch

    /// Loads the role and permission set for the given user in the given church.
    ///
    /// Queries `churchStaffRoles` where `userId == userId` and `churchId == churchId`
    /// and `status == "active"`. Publishes `currentUserRole` and `currentPermissions`.
    ///
    /// - Parameters:
    ///   - userId: The UID of the staff member.
    ///   - churchId: The church context.
    func fetchRole(for userId: String, churchId: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Firestore query:
        // let snapshot = try await db.collection("churchStaffRoles")
        //     .whereField("userId", isEqualTo: userId)
        //     .whereField("churchId", isEqualTo: churchId)
        //     .whereField("status", isEqualTo: "active")
        //     .limit(to: 1)
        //     .getDocuments()
        //
        // guard let doc = snapshot.documents.first,
        //       let roleRaw = doc.data()["role"] as? String,
        //       let role = ChurchRole(rawValue: roleRaw) else {
        //     self.currentUserRole = nil
        //     self.currentPermissions = nil
        //     return
        // }
        //
        // self.currentUserRole = role
        // self.currentPermissions = RolePermissions.permissions(for: role)

        _ = userId      // suppress unused-variable warning until Firestore is wired
        _ = churchId
    }

    // MARK: - Permission Check

    /// Returns whether the currently loaded permissions include the given key.
    ///
    /// This method is synchronous and safe to call during view rendering.
    /// Returns `false` if `fetchRole(for:churchId:)` has not yet completed successfully.
    ///
    /// - Parameters:
    ///   - permission: The ``PermissionKey`` to evaluate.
    ///   - userId: Unused at the client layer; present for call-site clarity and future audit logging.
    ///   - churchId: Unused at the client layer; present for call-site clarity and future audit logging.
    /// - Returns: `true` if the current user holds the requested permission; `false` otherwise.
    func can(_ permission: PermissionKey, userId: String, churchId: String) -> Bool {
        guard let perms = currentPermissions else { return false }
        switch permission {
        case .manageProfile:       return perms.manageProfile
        case .manageLive:          return perms.manageLive
        case .manageEvents:        return perms.manageEvents
        case .moderateComments:    return perms.moderateComments
        case .manageSermons:       return perms.manageSermons
        case .manageAdmins:        return perms.manageAdmins
        case .manageAnnouncements: return perms.manageAnnouncements
        }
    }

    // MARK: - Role Mutation

    /// Assigns a new role to a staff member.
    ///
    /// Requires the `assignedBy` user to hold the `.manageAdmins` permission.
    /// Writes to `churchStaffRoles/{churchId}_{toUserId}`.
    ///
    /// - Parameters:
    ///   - role: The ``ChurchRole`` to grant.
    ///   - toUserId: The UID of the staff member receiving the role.
    ///   - churchId: The church context.
    ///   - assignedBy: The UID of the admin performing the assignment.
    /// - Throws: ``PermissionError.unauthorized`` if the caller lacks `.manageAdmins`,
    ///   or a Firestore error if the write fails.
    func assignRole(
        _ role: ChurchRole,
        toUserId: String,
        churchId: String,
        assignedBy: String
    ) async throws {
        guard can(.manageAdmins, userId: assignedBy, churchId: churchId) else {
            throw PermissionError.unauthorized
        }

        // Firestore write:
        // let docId = "\(churchId)_\(toUserId)"
        // let payload: [String: Any] = [
        //     "userId": toUserId,
        //     "churchId": churchId,
        //     "role": role.rawValue,
        //     "assignedBy": assignedBy,
        //     "assignedAt": FieldValue.serverTimestamp(),
        //     "status": "active"
        // ]
        // try await db.collection("churchStaffRoles").document(docId).setData(payload, merge: true)
    }

    /// Revokes the active role for a staff member.
    ///
    /// Performs a soft delete by setting `status = "revoked"` rather than
    /// deleting the document, preserving the audit trail.
    ///
    /// Requires the `revokedBy` user to hold the `.manageAdmins` permission.
    ///
    /// - Parameters:
    ///   - forUserId: The UID of the staff member whose role is being revoked.
    ///   - churchId: The church context.
    ///   - revokedBy: The UID of the admin performing the revocation.
    /// - Throws: ``PermissionError.unauthorized`` if the caller lacks `.manageAdmins`,
    ///   or a Firestore error if the write fails.
    func revokeRole(forUserId: String, churchId: String, revokedBy: String) async throws {
        guard can(.manageAdmins, userId: revokedBy, churchId: churchId) else {
            throw PermissionError.unauthorized
        }

        // Firestore soft delete:
        // let docId = "\(churchId)_\(forUserId)"
        // try await db.collection("churchStaffRoles").document(docId)
        //     .updateData([
        //         "status": "revoked",
        //         "revokedBy": revokedBy,
        //         "revokedAt": FieldValue.serverTimestamp()
        //     ])
    }
}

// MARK: - Permission Key

/// Enumeration of discrete permission gates used across the church management surface.
enum PermissionKey {
    case manageProfile
    case manageLive
    case manageEvents
    case moderateComments
    case manageSermons
    case manageAdmins
    case manageAnnouncements
}

// MARK: - Permission Error

/// Errors thrown by ``RolePermissionService`` during role mutations.
enum PermissionError: LocalizedError {
    case unauthorized
    case roleNotFound

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "You do not have permission to perform this action."
        case .roleNotFound:
            return "No active role was found for this user in this church."
        }
    }
}

// MARK: - RolePermissions Extension

extension RolePermissions {
    /// Returns the canonical ``RolePermissions`` preset for a given ``ChurchRole``.
    static func permissions(for role: ChurchRole) -> RolePermissions {
        switch role {
        case .owner:        return .owner
        case .pastor:       return .pastor
        case .admin:        return .admin
        case .mediaManager: return .mediaManager
        case .eventsManager: return .eventsManager
        case .moderator:    return .moderator
        }
    }
}
