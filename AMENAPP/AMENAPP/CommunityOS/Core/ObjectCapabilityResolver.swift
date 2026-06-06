// ObjectCapabilityResolver.swift
// AMENAPP — CommunityOS / Core
//
// Phase 1 Core Spine: resolves the capability set for a given
// (objectType, viewerRole, audience) triple.
//
// Source contracts: C1 §2 "Shared Capability Set" capability table.
// `ContentAudience` is defined in ContentOSModels.swift — not redefined here.

import Foundation

// MARK: - ObjectCapabilityResolver

/// @MainActor class that resolves which ObjectCapabilities a viewer can exercise
/// on a given object, based on the C1 capability table, the viewer's RBAC role,
/// and the object's audience level.
@MainActor
final class ObjectCapabilityResolver {

    // MARK: - Public API

    /// Returns the capability set for the given triple.
    ///
    /// - Parameters:
    ///   - objectType: The type of the object being viewed.
    ///   - viewerRole: The RBAC role of the viewer within the object's org/space scope.
    ///   - audience: The raw value of the object's `ContentAudience`.
    /// - Returns: The set of capabilities the viewer may exercise.
    func resolve(
        objectType: AmenObjectType,
        viewerRole: AmenRole,
        audience: String
    ) -> Set<ObjectCapability> {
        // Visitors have no write capabilities; they can view public objects only.
        if viewerRole == .visitor {
            guard isPubliclyReadable(audience: audience) else { return [] }
            return baseCapabilities(for: objectType).intersection([.view, .share])
        }

        // Start from the base capability set for this object type (C1 §2 table)
        var caps = baseCapabilities(for: objectType)

        // Apply audience-level restrictions
        caps = applyAudienceRestrictions(caps, audience: audience, role: viewerRole)

        // Apply role-level restrictions
        caps = applyRoleRestrictions(caps, objectType: objectType, role: viewerRole)

        return caps
    }

    /// Derives which intents are available from the given capability set.
    /// Intents are the transform-layer expression of capabilities.
    func resolveIntents(for capabilities: Set<ObjectCapability>) -> [AmenIntent] {
        var intents: [AmenIntent] = []

        if capabilities.contains(.discuss) { intents.append(.discuss) }
        if capabilities.contains(.pray)    { intents.append(.pray) }
        if capabilities.contains(.study)   { intents.append(.study) }
        if capabilities.contains(.share)   { intents.append(.share) }
        if capabilities.contains(.invite)  { intents.append(.invite) }
        if capabilities.contains(.followUp) {
            // followUp maps to both mentor and announce depending on role;
            // return both and let the caller filter
            intents.append(.mentor)
            intents.append(.announce)
        }

        return intents
    }

    // MARK: - Private helpers

    /// The base capability set each object type exposes per C1 §2.
    /// This is independent of role or audience; role/audience restrict from here.
    private func baseCapabilities(for objectType: AmenObjectType) -> Set<ObjectCapability> {
        switch objectType {
        case .user:
            return [.view, .pray, .share, .invite]

        case .organization:
            return [.view, .discuss, .pray, .share, .save, .invite]

        case .church:
            return [.view, .discuss, .pray, .study, .share, .save, .invite, .followUp]

        case .team:
            return [.view, .discuss, .pray, .share, .invite, .followUp]

        case .space:
            return [.view, .discuss, .pray, .study, .share, .invite, .followUp]

        case .post:
            return [.view, .discuss, .pray, .share, .save]

        case .prayer:
            return [.view, .discuss, .pray, .share, .save, .followUp]

        case .discussion:
            return [.view, .discuss, .pray, .share, .invite]

        case .study:
            return [.view, .discuss, .pray, .study, .share, .save, .invite, .followUp]

        case .event:
            return [.view, .discuss, .pray, .share, .save, .invite, .followUp]

        case .volunteerOpportunity:
            return [.view, .discuss, .pray, .share, .save, .invite, .followUp]

        case .mentorship:
            return [.view, .discuss, .pray, .study, .invite, .followUp]

        case .job:
            return [.view, .discuss, .share, .save, .followUp]

        case .churchNote:
            return [.view, .pray, .study, .share, .save, .followUp]

        case .bereanInsight:
            return [.view, .discuss, .pray, .study, .share, .save]

        case .mediaObject:
            return [.view, .discuss, .pray, .share, .save]

        case .moment:
            return [.view, .pray, .share]

        case .actionThread:
            return [.view, .discuss, .pray, .invite, .followUp]
        }
    }

    /// Restrict capabilities based on audience level and the viewer's role membership.
    private func applyAudienceRestrictions(
        _ caps: Set<ObjectCapability>,
        audience: String,
        role: AmenRole
    ) -> Set<ObjectCapability> {
        switch audience {
        case "private":
            // Only owner-equivalent roles see private content
            guard role == .owner || role == .executiveAdmin else { return [] }
            return caps

        case "trusted_circle":
            // Trusted circle: owner + mutuals. Represented here as member+
            guard isMemberOrAbove(role) else { return [] }
            return caps

        case "small_group", "church_only":
            // Must be at least a member of the org
            guard isMemberOrAbove(role) else { return [] }
            return caps

        case "space_members", "paid_members":
            guard isMemberOrAbove(role) else { return [] }
            return caps

        case "public_feed", "public":
            // Public — all roles can view; non-members can't invite/follow_up
            var restricted = caps
            if role == .visitor {
                restricted = restricted.intersection([.view, .share])
            }
            return restricted

        default:
            return caps
        }
    }

    /// Apply role-specific restrictions on top of audience restrictions.
    private func applyRoleRestrictions(
        _ caps: Set<ObjectCapability>,
        objectType: AmenObjectType,
        role: AmenRole
    ) -> Set<ObjectCapability> {
        var result = caps

        // Jobs are blocked for visitors at the role layer (C5 §2l)
        if objectType == .job, role == .visitor {
            return []
        }

        // Members and visitors cannot use followUp on jobs
        if objectType == .job, role == .member || role == .visitor {
            result.remove(.followUp)
        }

        // Moments are owner-private by default; only owner may share
        if objectType == .moment, role != .owner, role != .executiveAdmin {
            result.remove(.share)
        }

        return result
    }

    /// Whether the audience string represents a publicly readable object.
    private func isPubliclyReadable(audience: String) -> Bool {
        audience == "public_feed" || audience == "public"
    }

    /// Whether the role is at least `member` (i.e., an authenticated, enrolled user).
    private func isMemberOrAbove(_ role: AmenRole) -> Bool {
        switch role {
        case .visitor, .minor:
            return false
        case .member, .volunteerLead, .contentManager, .eventManager,
             .moderator, .leader, .pastor, .owner, .executiveAdmin:
            return true
        }
    }
}
