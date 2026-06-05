// RBACService.swift
// AMENAPP — CommunityOS / Core
//
// Phase 1 Core Spine: role resolution and permission checking.
//
// Source contracts: C5 "Security Rules & RBAC Contract".
// The `resolveRBACRole` Cloud Function call is a stub — wired to the CF
// that will be deployed separately.

import Foundation
import FirebaseFunctions

// MARK: - RBACPermission

/// Fine-grained permission actions used in the RBAC matrix.
/// Source: C5 §2 role × resource × action matrix.
enum RBACPermission: String, Sendable {
    case create         = "create"
    case read           = "read"
    case update         = "update"
    case softDelete     = "soft_delete"
    case moderate       = "moderate"
    case pin            = "pin"
    case manageMembers  = "manage_members"
    case viewAnalytics  = "view_analytics"
    case manageRoles    = "manage_roles"
}

// MARK: - RBACService

/// @MainActor service for RBAC role resolution and permission checking.
/// Role resolution is done server-side (via `resolveRBACRole` CF) to prevent
/// client-side privilege escalation.
@MainActor
final class RBACService {

    // MARK: - Singleton

    static let shared = RBACService()

    // MARK: - Private

    private let functions: Functions
    /// In-memory cache: `"userId|resourceRef"` → `AmenRole`
    private var roleCache: [String: AmenRole] = [:]

    private init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    // MARK: - Role Resolution

    /// Resolves the RBAC role for a given user within the scope of a resource.
    ///
    /// Results are cached in memory for the lifetime of the app session.
    /// Call `invalidateRoleCache()` on logout or org membership change.
    ///
    /// - Parameters:
    ///   - userId: The Firebase Auth UID of the actor.
    ///   - resourceRef: The Firestore path of the resource (e.g. `/posts/abc`).
    /// - Returns: The resolved `AmenRole` for the actor within that resource's scope.
    func resolveRole(for userId: String, resourceRef: String) async throws -> AmenRole {
        let cacheKey = "\(userId)|\(resourceRef)"
        if let cached = roleCache[cacheKey] {
            return cached
        }

        guard AMENFeatureFlags.shared.communityOSEnabled else {
            return .visitor
        }

        let payload: [String: Any] = [
            "userId":      userId,
            "resourceRef": resourceRef
        ]

        let callable = functions.httpsCallable("resolveRBACRole")
        let result = try await callable.call(payload)

        guard
            let data = result.data as? [String: Any],
            let roleRaw = data["role"] as? String,
            let role = AmenRole(rawValue: roleRaw)
        else {
            return .visitor
        }

        roleCache[cacheKey] = role
        return role
    }

    /// Clears the in-memory role cache. Call on logout or membership change.
    func invalidateRoleCache() {
        roleCache.removeAll()
    }

    // MARK: - Permission Check

    /// Checks whether a given role has a specific permission.
    /// Implements the C5 §2 RBAC matrix as a switch statement.
    ///
    /// - Parameters:
    ///   - permission: The permission action to check.
    ///   - role: The RBAC role of the actor.
    /// - Returns: `true` if the role has the permission.
    func hasPermission(_ permission: RBACPermission, role: AmenRole) -> Bool {
        switch permission {

        case .create:
            // Any authenticated role can create content
            switch role {
            case .owner, .executiveAdmin, .pastor, .leader, .moderator,
                 .volunteerLead, .contentManager, .eventManager, .member:
                return true
            case .visitor:
                return false
            }

        case .read:
            // All roles can read; visitors limited to public content (enforced by audience)
            return true

        case .update:
            // Members and above can update their own content (C-OWN enforced server-side)
            switch role {
            case .owner, .executiveAdmin, .pastor, .leader, .moderator,
                 .volunteerLead, .contentManager, .eventManager, .member:
                return true
            case .visitor:
                return false
            }

        case .softDelete:
            // Member+ can soft-delete own content; moderation roles can delete others
            switch role {
            case .owner, .executiveAdmin, .pastor, .leader, .moderator,
                 .volunteerLead, .contentManager, .eventManager, .member:
                return true
            case .visitor:
                return false
            }

        case .moderate:
            // Moderator, pastor, leader (within scope), owner, executiveAdmin
            switch role {
            case .owner, .executiveAdmin, .pastor, .leader, .moderator:
                return true
            case .volunteerLead, .contentManager, .eventManager, .member, .visitor:
                return false
            }

        case .pin:
            // Pastor+, leader, moderator, contentManager can pin
            switch role {
            case .owner, .executiveAdmin, .pastor, .leader, .moderator, .contentManager:
                return true
            case .volunteerLead, .eventManager, .member, .visitor:
                return false
            }

        case .manageMembers:
            // Owner, executiveAdmin, pastor, leader can manage members
            switch role {
            case .owner, .executiveAdmin, .pastor, .leader:
                return true
            case .moderator, .volunteerLead, .contentManager, .eventManager, .member, .visitor:
                return false
            }

        case .viewAnalytics:
            // All authenticated roles except visitor can view own analytics;
            // org-scoped analytics require leader+ (enforced server-side via C5 conditions)
            switch role {
            case .owner, .executiveAdmin, .pastor, .leader, .moderator,
                 .volunteerLead, .contentManager, .eventManager, .member:
                return true
            case .visitor:
                return false
            }

        case .manageRoles:
            // Only owner and executiveAdmin can manage roles
            switch role {
            case .owner, .executiveAdmin:
                return true
            case .pastor, .leader, .moderator, .volunteerLead,
                 .contentManager, .eventManager, .member, .visitor:
                return false
            }
        }
    }
}
