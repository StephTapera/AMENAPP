// AmenRBACService.swift
// AMENAPP — CommunityOS/Identity
//
// Unified RBAC enforcement service. Reconciles the five existing role systems:
//   1. ChurchRole (ChurchRole.swift): owner, pastor, admin, mediaManager, eventsManager, moderator
//   2. CovenantMembership.MemberRole (CovenantModels.swift): creator, admin, moderator, member
//   3. SpaceMemberRole (SpaceOSModels.swift): pastor, admin, leader, member, guest
//   4. OrgRBACRole (OrgKnowledgeModels.swift): owner, admin, editor, broadcaster, volunteer, member
//   5. ActionThreadParticipant.ParticipantRole (ActionThreadModels.swift): owner, coordinator, supporter, observer
//
// Mapping to AmenRole (canonical):
//   ChurchRole.owner              → .owner
//   ChurchRole.pastor             → .pastor
//   ChurchRole.admin              → .leader  (church admin = ministry leader in unified model)
//   ChurchRole.mediaManager       → .contentManager
//   ChurchRole.eventsManager      → .eventManager
//   ChurchRole.moderator          → .moderator
//   CovenantMembership.creator    → .owner
//   CovenantMembership.admin      → .leader
//   CovenantMembership.moderator  → .moderator
//   CovenantMembership.member     → .member
//   SpaceMemberRole.pastor        → .pastor
//   SpaceMemberRole.admin         → .leader
//   SpaceMemberRole.leader        → .leader
//   SpaceMemberRole.member        → .member
//   SpaceMemberRole.guest         → .visitor
//   OrgRBACRole.owner             → .owner
//   OrgRBACRole.admin             → .leader
//   OrgRBACRole.editor            → .contentManager
//   OrgRBACRole.broadcaster       → .contentManager
//   OrgRBACRole.volunteer         → .volunteerLead
//   OrgRBACRole.member            → .member
//   ActionThread.owner            → .owner  (thread-scoped)
//   ActionThread.coordinator      → .leader (thread-scoped)
//   ActionThread.supporter        → .member (thread-scoped)
//   ActionThread.observer         → .visitor (thread-scoped)
//
// Phase 1 Agent A2 — Identity & Trust
// C5 contract: contracts/C5-security-rules.md + contracts/C5-rbac-test-matrix.md

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - AmenRole

/// Canonical unified role enum. Maps from all five existing role systems.
/// Firestore `role` field values match C5 §1 "Firestore `role` field value" column.
enum AmenRole: String, Codable, CaseIterable, Sendable {
    case owner              = "owner"
    case executiveAdmin     = "executive_admin"
    case pastor             = "pastor"
    case leader             = "leader"
    case moderator          = "moderator"
    case volunteerLead      = "volunteer_lead"
    case contentManager     = "content_manager"
    case eventManager       = "event_manager"
    case member             = "member"
    case visitor            = "visitor"
    case minor              = "minor"

    /// Human-readable display label.
    var displayName: String {
        switch self {
        case .owner:           return "Owner"
        case .executiveAdmin:  return "Executive Admin"
        case .pastor:          return "Pastor"
        case .leader:          return "Leader"
        case .moderator:       return "Moderator"
        case .volunteerLead:   return "Volunteer Lead"
        case .contentManager:  return "Content Manager"
        case .eventManager:    return "Event Manager"
        case .member:          return "Member"
        case .visitor:         return "Visitor"
        case .minor:           return "Minor"
        }
    }

    /// Numeric privilege level used for quick hierarchy comparisons.
    /// Higher = more privilege. Do NOT use for RBAC decisions — use the matrix.
    var privilegeLevel: Int {
        switch self {
        case .executiveAdmin:  return 10
        case .owner:           return 9
        case .pastor:          return 8
        case .leader:          return 7
        case .moderator:       return 6
        case .contentManager:  return 5
        case .eventManager:    return 4
        case .volunteerLead:   return 3
        case .member:          return 2
        case .minor:           return 1
        case .visitor:         return 0
        }
    }
}

// MARK: - AmenResource

/// All resource types in the RBAC matrix (C5 §2).
enum AmenResource: String, Codable, CaseIterable {
    case user
    case post
    case prayer
    case discussion
    case comment
    case organization
    case church
    case team
    case space
    case event
    case volunteerOpportunity
    case job
    case mentorshipRequest
    case edge
    case moderationQueue
    case adminDashboard
    case broadcastMessage
    case privateMessage
    case churchNote
    case bereanInsight
}

// MARK: - AmenRBACAction

/// All actions that can be performed on a resource.
enum AmenRBACAction: String, Codable, CaseIterable {
    case create
    case read
    case update
    case delete
    case moderate
    case escalate
    case viewAnalytics
    case sendDM
}

// MARK: - PermissionResult

/// Result of a single RBAC evaluation.
struct PermissionResult {
    let allowed: Bool
    let reason: String

    static func allow(_ reason: String = "Permitted by RBAC policy") -> PermissionResult {
        PermissionResult(allowed: true, reason: reason)
    }

    static func deny(_ reason: String) -> PermissionResult {
        PermissionResult(allowed: false, reason: reason)
    }
}

// MARK: - PermissionContext

/// Optional context that drives conditional (C-*) overrides on top of the base matrix.
struct PermissionContext {
    var targetUserId: String?
    var targetIsMinor: Bool
    var isOwnContent: Bool
    var privacyLevel: String     // "public" | "private" | "church" | "space" | "trustedCircle"
    var contextId: String?       // churchId / spaceId / orgId relevant to this check
    var contextType: String?     // "church" | "space" | "org" | "team"

    static let `default` = PermissionContext(
        targetUserId: nil,
        targetIsMinor: false,
        isOwnContent: false,
        privacyLevel: "public"
    )
}

// MARK: - AmenRBACService

@MainActor
class AmenRBACService: ObservableObject {

    static let shared = AmenRBACService()

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Public API

    /// Primary permission check. Returns a PermissionResult driven by the C5 matrix
    /// with contextual overrides applied.
    func check(
        role: AmenRole,
        resource: AmenResource,
        action: AmenRBACAction,
        context: PermissionContext? = nil
    ) -> PermissionResult {

        let ctx = context ?? .default

        // --- Hard safety invariants (override everything) ---

        // [MINOR] DM hard-block: minors can never sendDM via the base matrix
        // C-MINOR-DM is handled by allowDM(); the matrix entry for minor_privateMessage_sendDM
        // is false, so the conditional path below applies separately.
        if role == .minor && action == .sendDM {
            if !allowDM(actorRole: .minor, targetIsMinor: ctx.targetIsMinor) {
                return .deny("[MINOR] Direct messages require mutual follow and minor-safe contact check.")
            }
        }

        // [MINOR] Job listings completely blocked for minors (C-AGE, I-1)
        if role == .minor && resource == .job {
            return .deny("[MINOR] Job listings are not available for minor accounts.")
        }

        // Visitors cannot create anything
        if role == .visitor && action == .create &&
           resource != .user && resource != .edge {
            return .deny("Visitors cannot create content. Please join the community first.")
        }

        // Soft-delete invariant: no hard-delete via client (I-1)
        // The matrix uses delete to mean soft-delete (set deletedAt). We allow the matrix
        // to handle this; direct .delete Firestore operations are blocked at the rules layer.

        // --- Own content override ---
        // Owners of their own content always have full CRUD rights over it.
        // This applies before the matrix for update/delete on content resources.
        if ctx.isOwnContent && role != .visitor &&
           (action == .update || action == .delete) &&
           isContentResource(resource) {
            return .allow("Content owner: full rights over own content.")
        }

        // --- Matrix lookup ---
        let key = matrixKey(role: role, resource: resource, action: action)
        if let matrixDecision = Self.matrix[key] {
            if matrixDecision {
                return .allow()
            } else {
                return .deny("Action '\(action.rawValue)' on '\(resource.rawValue)' is not permitted for role '\(role.rawValue)'.")
            }
        }

        // --- Default deny for unknown combinations ---
        return .deny("No RBAC rule found for \(role.rawValue)/\(resource.rawValue)/\(action.rawValue). Defaulting to deny.")
    }

    /// Checks if a user's Firestore profile marks them as a minor (ageTier == 'teen' or 'under_minimum').
    func isMinor(userId: String) async throws -> Bool {
        let doc = try await db.collection("users").document(userId).getDocument()
        guard let data = doc.data() else { return false }
        let ageTier = data["ageTier"] as? String ?? ""
        return ageTier == "teen" || ageTier == "under_minimum"
    }

    /// Resolves the canonical AmenRole for a user within a given context (church/space/org/team).
    /// Falls back to .visitor if no membership document is found.
    func resolveRole(for userId: String, in contextType: String, contextId: String) async throws -> AmenRole {
        let doc = try await db
            .collection("roles")
            .document(contextType)
            .collection(contextId)
            .document("members")
            .collection(userId)
            .document("membership")
            .getDocument()

        // Try the flat role path first
        if let data = doc.data(), let rawRole = data["role"] as? String {
            return AmenRole(rawValue: rawRole) ?? .visitor
        }

        // Fallback: try /roles/{contextType}/{contextId}/members/{userId}
        let altDoc = try await db
            .collection("roles")
            .document(contextType)
            .collection(contextId)
            .document("members")
            .getDocument()

        if let data = altDoc.data(), let rawRole = data[userId] as? String {
            return AmenRole(rawValue: rawRole) ?? .visitor
        }

        return .visitor
    }

    // MARK: - DM Guard

    /// Returns true if an actor with the given role may send a direct message,
    /// applying C-MINOR-DM rules.
    /// Note: full C-MINOR-DM also requires mutual follow verification at the CF layer.
    func allowDM(actorRole: AmenRole, targetIsMinor: Bool) -> Bool {
        // Visitors never DM
        if actorRole == .visitor { return false }

        // Minor DM: only allowed if both parties are mutual follows (enforced server-side).
        // At the iOS layer we permit the action; the CF checkContentSafety gate enforces mutuality.
        if actorRole == .minor { return true } // CF will enforce C-MINOR-DM

        // Non-minor cannot DM a minor unless they are a church leader with verified parental consent.
        // Church-leader + minor DM is flagged to CF for parental-consent verification.
        // At this layer: allow the send; CF enforces the consent check.
        return true
    }

    // MARK: - Private Helpers

    private func isContentResource(_ resource: AmenResource) -> Bool {
        switch resource {
        case .post, .prayer, .discussion, .comment, .churchNote, .broadcastMessage,
             .event, .volunteerOpportunity, .job, .mentorshipRequest:
            return true
        default:
            return false
        }
    }

    private func matrixKey(role: AmenRole, resource: AmenResource, action: AmenRBACAction) -> String {
        "\(role.rawValue)_\(resource.rawValue)_\(action.rawValue)"
    }

    // MARK: - RBAC Matrix
    // Source: C5-security-rules.md §2 and C5-rbac-test-matrix.md
    // Key format: "{role}_{resource}_{action}" — true = allow, false = deny
    // Conditional (C-*) entries: true in the matrix means "conditionally allowed";
    // runtime code applies the specific condition check on top.
    // All 35 test cases from C5-rbac-test-matrix.md are covered.

    // swiftlint:disable function_body_length
    private static let matrix: [String: Bool] = buildMatrix()

    private static func buildMatrix() -> [String: Bool] {
        var m: [String: Bool] = [:]

        // Helper
        func allow(_ role: AmenRole, _ res: AmenResource, _ act: AmenRBACAction) {
            m["\(role.rawValue)_\(res.rawValue)_\(act.rawValue)"] = true
        }
        func deny(_ role: AmenRole, _ res: AmenResource, _ act: AmenRBACAction) {
            m["\(role.rawValue)_\(res.rawValue)_\(act.rawValue)"] = false
        }

        // ─────────────────────────────────────────────────
        // POST resource (§2b)
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .post, .create)
        }
        deny(.visitor, .post, .create)   // C5-V-03

        for role in AmenRole.allCases { allow(role, .post, .read) } // public read always

        // update own
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .post, .update)
        }
        deny(.visitor, .post, .update)

        // delete (soft-delete)
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader,
                     .moderator, .contentManager, .member, .minor,
                     .volunteerLead, .eventManager] {
            allow(role, .post, .delete)
        }
        deny(.visitor, .post, .delete)

        // moderate
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator] {
            allow(role, .post, .moderate) // C5-MOD-01
        }
        for role in [AmenRole.volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .post, .moderate)
        }

        // escalate
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .post, .escalate)
        }
        deny(.visitor, .post, .escalate)

        // viewAnalytics
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader,
                     .contentManager, .member, .minor] {
            allow(role, .post, .viewAnalytics)
        }
        for role in [AmenRole.moderator, .volunteerLead, .eventManager, .visitor] {
            deny(role, .post, .viewAnalytics)
        }

        // ─────────────────────────────────────────────────
        // USER resource (§2a)
        // ─────────────────────────────────────────────────
        for role in AmenRole.allCases { allow(role, .user, .create) }
        for role in AmenRole.allCases { allow(role, .user, .read) }
        for role in AmenRole.allCases { allow(role, .user, .update) }
        // delete (soft-delete own profile — C-AUDIT applies)
        for role in AmenRole.allCases { allow(role, .user, .delete) }
        // viewAnalytics own
        for role in AmenRole.allCases { allow(role, .user, .viewAnalytics) }

        // ─────────────────────────────────────────────────
        // PRAYER resource (§2c)
        // ─────────────────────────────────────────────────
        for role in AmenRole.allCases { allow(role, .prayer, .create) }
        for role in AmenRole.allCases { allow(role, .prayer, .read) }
        for role in AmenRole.allCases { allow(role, .prayer, .update) }
        for role in AmenRole.allCases { allow(role, .prayer, .delete) }
        // moderate
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator] {
            allow(role, .prayer, .moderate)
        }
        for role in [AmenRole.volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .prayer, .moderate)
        }
        // escalate
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .prayer, .escalate)
        }
        deny(.visitor, .prayer, .escalate)

        // sendDM on prayer context — tied to role's DM ability
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader] {
            allow(role, .prayer, .sendDM)
        }
        for role in [AmenRole.moderator, .volunteerLead, .contentManager, .eventManager, .visitor] {
            deny(role, .prayer, .sendDM)
        }
        deny(.minor, .prayer, .sendDM)  // C-MINOR-DM enforced at runtime

        // ─────────────────────────────────────────────────
        // DISCUSSION resource (§2d)
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .discussion, .create)
        }
        deny(.visitor, .discussion, .create)  // C5-V-03 (discussions = not public post)

        for role in AmenRole.allCases { allow(role, .discussion, .read) }
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .discussion, .update)
        }
        deny(.visitor, .discussion, .update)

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .discussion, .delete)
        }
        deny(.visitor, .discussion, .delete)

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator] {
            allow(role, .discussion, .moderate)
        }
        for role in [AmenRole.volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .discussion, .moderate)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .discussion, .escalate)
        }
        deny(.visitor, .discussion, .escalate)

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .contentManager] {
            allow(role, .discussion, .viewAnalytics)
        }
        for role in [AmenRole.leader, .moderator, .volunteerLead, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .discussion, .viewAnalytics)
        }

        // ─────────────────────────────────────────────────
        // COMMENT resource (§2e)
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .comment, .create)
        }
        deny(.visitor, .comment, .create)

        for role in AmenRole.allCases { allow(role, .comment, .read) }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .comment, .update)
        }
        deny(.visitor, .comment, .update)

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .comment, .delete)
        }
        deny(.visitor, .comment, .delete)

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator] {
            allow(role, .comment, .moderate)
        }
        for role in [AmenRole.volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .comment, .moderate)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .comment, .escalate)
        }
        allow(.visitor, .comment, .escalate)

        // ─────────────────────────────────────────────────
        // ORGANIZATION resource (§2f)
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin, .pastor] {
            allow(role, .organization, .create)
        }
        for role in [AmenRole.leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .organization, .create)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member] {
            allow(role, .organization, .read)
        }
        deny(.visitor, .organization, .read) // C-PRIV
        deny(.minor, .organization, .read)   // C-PRIV

        for role in [AmenRole.owner, .executiveAdmin, .pastor] {
            allow(role, .organization, .update)
        }
        for role in [AmenRole.leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .organization, .update)
        }

        for role in [AmenRole.owner, .executiveAdmin] {
            allow(role, .organization, .delete)
        }
        for role in [AmenRole.pastor, .leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .organization, .delete)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor] {
            allow(role, .organization, .viewAnalytics)
        }
        for role in [AmenRole.leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .organization, .viewAnalytics)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .moderator] {
            allow(role, .organization, .moderate)
        }
        for role in [AmenRole.leader, .volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .organization, .moderate)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .organization, .escalate)
        }
        deny(.visitor, .organization, .escalate)

        // ─────────────────────────────────────────────────
        // CHURCH resource (§2g)
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin, .pastor] {
            allow(role, .church, .create)
        }
        for role in [AmenRole.leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .church, .create)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member] {
            allow(role, .church, .read)
        }
        deny(.visitor, .church, .read) // C-PRIV
        deny(.minor, .church, .read)   // C-PRIV

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .contentManager] {
            allow(role, .church, .update)
        }
        for role in [AmenRole.leader, .moderator, .volunteerLead,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .church, .update)
        }

        for role in [AmenRole.owner, .executiveAdmin] {
            allow(role, .church, .delete)
        }
        for role in [AmenRole.pastor, .leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .church, .delete)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor] {
            allow(role, .church, .viewAnalytics)
        }
        for role in [AmenRole.leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .church, .viewAnalytics)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .moderator] {
            allow(role, .church, .moderate)
        }
        for role in [AmenRole.leader, .volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .church, .moderate)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .church, .escalate)
        }
        deny(.visitor, .church, .escalate)

        // ─────────────────────────────────────────────────
        // TEAM resource (§2h)
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader] {
            allow(role, .team, .create)
        }
        for role in [AmenRole.moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .team, .create)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager] {
            allow(role, .team, .read)
        }
        deny(.visitor, .team, .read)
        deny(.minor, .team, .read)   // C-ORG required
        deny(.member, .team, .read)  // C-ORG

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader] {
            allow(role, .team, .update)
        }
        for role in [AmenRole.moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .team, .update)
        }

        for role in [AmenRole.owner, .executiveAdmin] {
            allow(role, .team, .delete)
        }
        for role in [AmenRole.pastor, .leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .team, .delete)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor] {
            allow(role, .team, .viewAnalytics)
        }
        for role in [AmenRole.leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .team, .viewAnalytics)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .moderator] {
            allow(role, .team, .moderate)
        }
        for role in [AmenRole.leader, .volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .team, .moderate)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .team, .escalate)
        }
        deny(.visitor, .team, .escalate)

        // ─────────────────────────────────────────────────
        // SPACE resource (§2i)
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader] {
            allow(role, .space, .create)
        }
        for role in [AmenRole.moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .space, .create)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager] {
            allow(role, .space, .read)
        }
        deny(.visitor, .space, .read)  // C-PRIV
        deny(.minor, .space, .read)    // C-PRIV: only church-verified spaces
        deny(.member, .space, .read)   // C-PRIV

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader] {
            allow(role, .space, .update)
        }
        for role in [AmenRole.moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .space, .update)
        }

        for role in [AmenRole.owner, .executiveAdmin] {
            allow(role, .space, .delete)
        }
        for role in [AmenRole.pastor, .leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .space, .delete)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor] {
            allow(role, .space, .viewAnalytics)
        }
        for role in [AmenRole.leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .space, .viewAnalytics)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator] {
            allow(role, .space, .moderate)
        }
        for role in [AmenRole.volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .space, .moderate)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .space, .escalate)
        }
        deny(.visitor, .space, .escalate)

        // ─────────────────────────────────────────────────
        // EVENT resource (§2j)
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .eventManager] {
            allow(role, .event, .create)
        }
        for role in [AmenRole.moderator, .volunteerLead, .contentManager,
                     .member, .visitor, .minor] {
            deny(role, .event, .create)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .event, .read)
        }
        deny(.visitor, .event, .read)  // C-PRIV

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .eventManager] {
            allow(role, .event, .update)
        }
        for role in [AmenRole.moderator, .volunteerLead, .contentManager,
                     .member, .visitor, .minor] {
            deny(role, .event, .update)
        }

        for role in [AmenRole.owner, .executiveAdmin, .eventManager] {
            allow(role, .event, .delete)
        }
        for role in [AmenRole.pastor, .leader, .moderator, .volunteerLead, .contentManager,
                     .member, .visitor, .minor] {
            deny(role, .event, .delete)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .eventManager] {
            allow(role, .event, .viewAnalytics)
        }
        for role in [AmenRole.leader, .moderator, .volunteerLead, .contentManager,
                     .member, .visitor, .minor] {
            deny(role, .event, .viewAnalytics)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .moderator] {
            allow(role, .event, .moderate)
        }
        for role in [AmenRole.leader, .volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .event, .moderate)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .event, .escalate)
        }
        deny(.visitor, .event, .escalate)

        // ─────────────────────────────────────────────────
        // VOLUNTEER OPPORTUNITY resource (§2k)
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .volunteerLead] {
            allow(role, .volunteerOpportunity, .create)
        }
        for role in [AmenRole.moderator, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .volunteerOpportunity, .create)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .volunteerOpportunity, .read)
        }
        deny(.visitor, .volunteerOpportunity, .read) // C-PRIV

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .volunteerLead] {
            allow(role, .volunteerOpportunity, .update)
        }
        for role in [AmenRole.moderator, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .volunteerOpportunity, .update)
        }

        for role in [AmenRole.owner, .executiveAdmin, .volunteerLead] {
            allow(role, .volunteerOpportunity, .delete)
        }
        for role in [AmenRole.pastor, .leader, .moderator, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .volunteerOpportunity, .delete)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .moderator] {
            allow(role, .volunteerOpportunity, .moderate)
        }
        for role in [AmenRole.leader, .volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .volunteerOpportunity, .moderate)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .volunteerOpportunity, .escalate)
        }
        deny(.visitor, .volunteerOpportunity, .escalate)

        // ─────────────────────────────────────────────────
        // JOB resource (§2l)
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader] {
            allow(role, .job, .create)
        }
        for role in [AmenRole.moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor] {
            deny(role, .job, .create)
        }
        deny(.minor, .job, .create)  // C5-M-04, §2l: blocked entirely

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member] {
            allow(role, .job, .read)
        }
        deny(.visitor, .job, .read) // C-PRIV
        deny(.minor, .job, .read)   // C5-M-04: C-AGE — blocked entirely for minors

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader] {
            allow(role, .job, .update)
        }
        for role in [AmenRole.moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .job, .update)
        }

        for role in [AmenRole.owner, .executiveAdmin] {
            allow(role, .job, .delete)
        }
        for role in [AmenRole.pastor, .leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .job, .delete)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .moderator] {
            allow(role, .job, .moderate)
        }
        for role in [AmenRole.leader, .volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .job, .moderate)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member] {
            allow(role, .job, .escalate)
        }
        deny(.visitor, .job, .escalate)
        deny(.minor, .job, .escalate)

        // ─────────────────────────────────────────────────
        // MENTORSHIP REQUEST resource (§2m)
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader,
                     .volunteerLead, .member, .minor] {
            allow(role, .mentorshipRequest, .create)
        }
        for role in [AmenRole.moderator, .contentManager, .eventManager, .visitor] {
            deny(role, .mentorshipRequest, .create)
        }

        for role in AmenRole.allCases { allow(role, .mentorshipRequest, .read) }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader,
                     .volunteerLead, .member, .minor] {
            allow(role, .mentorshipRequest, .update)
        }
        for role in [AmenRole.moderator, .contentManager, .eventManager, .visitor] {
            deny(role, .mentorshipRequest, .update)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .volunteerLead, .member, .minor] {
            allow(role, .mentorshipRequest, .delete)
        }
        for role in [AmenRole.leader, .moderator, .contentManager, .eventManager, .visitor] {
            deny(role, .mentorshipRequest, .delete)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .moderator] {
            allow(role, .mentorshipRequest, .moderate)
        }
        for role in [AmenRole.leader, .volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .mentorshipRequest, .moderate)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .mentorshipRequest, .escalate)
        }
        deny(.visitor, .mentorshipRequest, .escalate)

        // sendDM on mentorship context
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader] {
            allow(role, .mentorshipRequest, .sendDM)
        }
        for role in [AmenRole.moderator, .contentManager, .eventManager, .visitor] {
            deny(role, .mentorshipRequest, .sendDM)
        }
        deny(.minor, .mentorshipRequest, .sendDM) // C-MINOR-DM enforced at runtime

        // ─────────────────────────────────────────────────
        // EDGE (social graph) resource (§2n)
        // ─────────────────────────────────────────────────
        for role in AmenRole.allCases { allow(role, .edge, .create) }
        for role in AmenRole.allCases { allow(role, .edge, .read) }
        for role in AmenRole.allCases { allow(role, .edge, .delete) }
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .moderator] {
            allow(role, .edge, .moderate)
        }
        for role in [AmenRole.leader, .volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .edge, .moderate)
        }
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .edge, .escalate)
        }
        deny(.visitor, .edge, .escalate)

        // ─────────────────────────────────────────────────
        // MODERATION QUEUE resource (§2o)
        // C5-MOD-03, C5-MOD-04, C5-ESC-01, C5-ESC-02
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin] {
            allow(role, .moderationQueue, .create)
        }
        for role in [AmenRole.pastor, .leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .moderationQueue, .create)
        }

        // read: Owner, ExecAdmin, Pastor, Moderator can read; C5-MOD-03
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .moderator] {
            allow(role, .moderationQueue, .read)
        }
        for role in [AmenRole.leader, .volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .moderationQueue, .read) // C5-MOD-04, C5-ESC-01
        }

        // update (action items)
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .moderator] {
            allow(role, .moderationQueue, .update) // C5-MOD-01
        }
        for role in [AmenRole.leader, .volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .moderationQueue, .update) // C5-ESC-01, C5-ESC-02
        }

        for role in [AmenRole.owner, .executiveAdmin] {
            allow(role, .moderationQueue, .delete)
        }
        for role in [AmenRole.pastor, .leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .moderationQueue, .delete)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .moderator] {
            allow(role, .moderationQueue, .viewAnalytics)
        }
        for role in [AmenRole.leader, .volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .moderationQueue, .viewAnalytics)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .moderationQueue, .escalate)
        }
        deny(.visitor, .moderationQueue, .escalate)

        // ─────────────────────────────────────────────────
        // ADMIN DASHBOARD resource (§2p)
        // C5-MOD-04
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin] {
            allow(role, .adminDashboard, .read)
        }
        allow(.pastor, .adminDashboard, .read)    // C-CHURCH scoped
        allow(.moderator, .adminDashboard, .read) // queue-only view per C5-MOD-04
        for role in [AmenRole.leader, .volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .adminDashboard, .read) // C5-MOD-04
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor] {
            allow(role, .adminDashboard, .update)
        }
        for role in [AmenRole.leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .adminDashboard, .update)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor] {
            allow(role, .adminDashboard, .viewAnalytics)
        }
        for role in [AmenRole.leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .adminDashboard, .viewAnalytics)
        }

        // ─────────────────────────────────────────────────
        // BROADCAST MESSAGE resource (§2q)
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .contentManager] {
            allow(role, .broadcastMessage, .create)
        }
        // leader: C-SPACE; eventManager: C-ORG event-related only — both allowed conditionally
        allow(.leader, .broadcastMessage, .create)
        allow(.eventManager, .broadcastMessage, .create)
        for role in [AmenRole.moderator, .volunteerLead,
                     .member, .visitor, .minor] {
            deny(role, .broadcastMessage, .create)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .broadcastMessage, .read)
        }
        deny(.visitor, .broadcastMessage, .read) // C-PRIV

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader,
                     .contentManager, .eventManager] {
            allow(role, .broadcastMessage, .update)
        }
        for role in [AmenRole.moderator, .volunteerLead,
                     .member, .visitor, .minor] {
            deny(role, .broadcastMessage, .update)
        }

        for role in [AmenRole.owner, .executiveAdmin] {
            allow(role, .broadcastMessage, .delete)
        }
        for role in [AmenRole.pastor, .leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .broadcastMessage, .delete)
        }

        for role in [AmenRole.owner, .executiveAdmin, .moderator] {
            allow(role, .broadcastMessage, .moderate)
        }
        for role in [AmenRole.pastor, .leader, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .broadcastMessage, .moderate)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .broadcastMessage, .escalate)
        }
        deny(.visitor, .broadcastMessage, .escalate)

        // ─────────────────────────────────────────────────
        // PRIVATE MESSAGE / DM resource (§2r)
        // C5-V-05, C5-M-01
        // ─────────────────────────────────────────────────
        // create (initiating a DM thread)
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member] {
            allow(role, .privateMessage, .create)
        }
        deny(.visitor, .privateMessage, .create) // C5-V-05
        deny(.minor, .privateMessage, .create)   // C-MINOR-DM: matrix false; runtime allows if mutual-follow

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .privateMessage, .read)
        }
        deny(.visitor, .privateMessage, .read)

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .privateMessage, .delete)
        }
        deny(.visitor, .privateMessage, .delete)

        for role in [AmenRole.owner, .executiveAdmin, .pastor] {
            allow(role, .privateMessage, .moderate)
        }
        for role in [AmenRole.leader, .moderator, .volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .privateMessage, .moderate)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .privateMessage, .escalate)
        }
        deny(.visitor, .privateMessage, .escalate)

        // sendDM: the canonical "can this role initiate a DM"
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member] {
            allow(role, .privateMessage, .sendDM)
        }
        deny(.visitor, .privateMessage, .sendDM)  // C5-V-05
        deny(.minor, .privateMessage, .sendDM)    // C5-M-01 base; C-MINOR-DM gate at runtime

        // ─────────────────────────────────────────────────
        // CHURCH NOTE resource (§2s)
        // ─────────────────────────────────────────────────
        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .churchNote, .create)
        }
        deny(.visitor, .churchNote, .create)

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager] {
            allow(role, .churchNote, .read)
        }
        deny(.visitor, .churchNote, .read)
        // member/minor: C-OWN (own notes only) — true in matrix; runtime checks ownership
        allow(.member, .churchNote, .read)
        allow(.minor, .churchNote, .read)

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .churchNote, .update)
        }
        deny(.visitor, .churchNote, .update)

        for role in [AmenRole.owner, .executiveAdmin] {
            allow(role, .churchNote, .delete)
        }
        for role in [AmenRole.pastor, .leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .churchNote, .delete)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .moderator] {
            allow(role, .churchNote, .moderate)
        }
        for role in [AmenRole.leader, .volunteerLead, .contentManager, .eventManager,
                     .member, .visitor, .minor] {
            deny(role, .churchNote, .moderate)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .churchNote, .escalate)
        }
        deny(.visitor, .churchNote, .escalate)

        // ─────────────────────────────────────────────────
        // BEREAN INSIGHT resource (§2t)
        // I-7: create is CF-only — all client creates denied
        // ─────────────────────────────────────────────────
        for role in AmenRole.allCases {
            deny(role, .bereanInsight, .create) // C5-EDGE-02: I-7
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager] {
            allow(role, .bereanInsight, .read)
        }
        deny(.visitor, .bereanInsight, .read)
        // member/minor: C-OWN — runtime checks
        allow(.member, .bereanInsight, .read)
        allow(.minor, .bereanInsight, .read)

        for role in AmenRole.allCases {
            deny(role, .bereanInsight, .update) // CF-only writes
        }

        for role in [AmenRole.owner, .executiveAdmin] {
            allow(role, .bereanInsight, .delete)
        }
        for role in [AmenRole.pastor, .leader, .moderator, .volunteerLead, .contentManager,
                     .eventManager, .member, .visitor, .minor] {
            deny(role, .bereanInsight, .delete)
        }

        for role in [AmenRole.owner, .executiveAdmin, .pastor, .leader, .moderator,
                     .volunteerLead, .contentManager, .eventManager, .member, .minor] {
            allow(role, .bereanInsight, .escalate)
        }
        deny(.visitor, .bereanInsight, .escalate)

        return m
    }
    // swiftlint:enable function_body_length
}
