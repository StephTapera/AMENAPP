import Foundation

// MARK: - Member Composer Type
// Defines which post types a member can create inside a Covenant room.
// Role-gated: higher roles unlock additional types.

enum MemberComposerType: String, CaseIterable, Identifiable {
    case post
    case prayerRequest
    case question
    case testimony
    case announcement

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .post:          return "Post"
        case .prayerRequest: return "Prayer Request"
        case .question:      return "Question"
        case .testimony:     return "Testimony"
        case .announcement:  return "Announcement"
        }
    }

    var icon: String {
        switch self {
        case .post:          return "doc.richtext"
        case .prayerRequest: return "hands.sparkles.fill"
        case .question:      return "questionmark.bubble.fill"
        case .testimony:     return "star.fill"
        case .announcement:  return "megaphone.fill"
        }
    }
}

// MARK: - Covenant Permissions

/// Pure-function permission evaluator. No state — call from any view or VM.
/// All inputs are value types; nil membership means unauthenticated or non-member.
enum AmenCovenantPermissions {

    // MARK: - Covenant Visibility

    /// Public covenants are always visible. Private covenants require authentication.
    static func canViewCovenant(covenant: Covenant, isAuthenticated: Bool) -> Bool {
        covenant.isPublic || isAuthenticated
    }

    // MARK: - Room Access

    /// Unlocked rooms are visible to anyone who can view the covenant.
    /// Locked rooms require an active membership whose tierId is in the room's requiredTierId.
    static func canViewRoom(room: CovenantRoom, membership: CovenantMembership?) -> Bool {
        guard room.isLocked else { return true }
        guard let membership, membership.status.isActive else { return false }
        // Creator and admin always pass the locked check
        if membership.role == .creator || membership.role == .admin { return true }
        // If no specific tier requirement, active membership is sufficient
        guard let required = room.requiredTierId else { return true }
        return membership.tierId == required
    }

    /// Members can post in a room if they can view it AND the room is not creator-only
    /// (unless they are creator / admin / moderator).
    static func canPostInRoom(room: CovenantRoom, membership: CovenantMembership?) -> Bool {
        guard canViewRoom(room: room, membership: membership) else { return false }
        guard room.creatorOnly else { return true }
        guard let membership else { return false }
        return membership.role == .creator || membership.role == .admin || membership.role == .moderator
    }

    // MARK: - Content Creation

    /// Any member with an active membership may create content.
    static func canCreatePost(membership: CovenantMembership?) -> Bool {
        guard let membership else { return false }
        return membership.status.isActive
    }

    // MARK: - Management & Moderation

    /// Only the creator or an admin can access the management hub, analytics,
    /// member directory (edit), content calendar, and tier settings.
    static func canManageCovenant(membership: CovenantMembership?) -> Bool {
        guard let membership else { return false }
        return membership.role == .creator || membership.role == .admin
    }

    /// Creator, admin, or moderator can action the moderation queue.
    static func canModerate(membership: CovenantMembership?) -> Bool {
        guard let membership else { return false }
        return membership.role == .creator
            || membership.role == .admin
            || membership.role == .moderator
    }

    /// Convenience — true for creator or admin only (used for destructive actions).
    static func isCreatorOrAdmin(membership: CovenantMembership?) -> Bool {
        canManageCovenant(membership: membership)
    }

    // MARK: - Composer Type Gate

    /// Returns the set of composer types available to a member based on their role.
    /// - Members:    post, prayerRequest, question, testimony
    /// - Moderators: + announcement
    /// - Admin/Creator: all types
    static func memberComposerTypes(membership: CovenantMembership?) -> [MemberComposerType] {
        guard let membership, membership.status.isActive else { return [] }
        switch membership.role {
        case .member:
            return [.post, .prayerRequest, .question, .testimony]
        case .moderator:
            return [.post, .prayerRequest, .question, .testimony, .announcement]
        case .admin, .creator:
            return MemberComposerType.allCases
        }
    }
}
