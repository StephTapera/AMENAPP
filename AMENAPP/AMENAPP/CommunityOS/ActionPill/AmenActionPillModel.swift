// AmenActionPillModel.swift
// AMEN App — CommunityOS / ActionPill
//
// Phase 2 — Agent A18 (Universal Action Pill)
// Object-aware model that maps AmenObjectType → ordered PillActions.
//
// Design contract: C3 §8 "Toolbar / Action Pill pattern"
// Intent taxonomy:  C2 §2 (11 canonical intents)
// SystemCapability set:   ObjectCapability.capabilities(for:) in AmenCoreModels.swift
//
// Anti-engagement rule: PillAction NEVER surfaces view/like counts or comparative metrics.
// All composition intents route through AmenUniversalComposer (A3).
//
// FROZEN pattern — extend via AmenActionPillModel extensions, never modify the matrix here
// without a RUNLOG entry.

import Foundation

// MARK: - PillAction

/// A single resolved action for display in the pill.
///
/// `save` and `followUp` are handled locally by `AmenActionPillContainer` — they
/// toggle persistent state and never open the composer.
/// All other actions have an associated `AmenIntent` and open `AmenUniversalComposer`.
enum PillAction: String, CaseIterable, Identifiable, Sendable {

    // Intent-based actions (open AmenUniversalComposer)
    case discuss
    case pray
    case study
    case share
    case invite
    case volunteer
    case hire
    case mentor
    case ask

    // Special local actions (no composer)
    case save
    case followUp
    case more      // Overflow sentinel — never passed to onAction

    // MARK: Identifiable

    var id: String { rawValue }

    // MARK: Display

    /// Human-readable label.
    var label: String {
        switch self {
        case .discuss:   return "Discuss"
        case .pray:      return "Pray"
        case .study:     return "Study"
        case .share:     return "Share"
        case .invite:    return "Invite"
        case .volunteer: return "Volunteer"
        case .hire:      return "Hire"
        case .mentor:    return "Mentor"
        case .ask:       return "Ask"
        case .save:      return "Save"
        case .followUp:  return "Follow Up"
        case .more:      return "More"
        }
    }

    /// SF Symbol name — monochrome line-weight glyph per C3 §7.
    var systemImage: String {
        switch self {
        case .discuss:   return "bubble.left.and.bubble.right"
        case .pray:      return "hands.and.sparkles"
        case .study:     return "book.pages"
        case .share:     return "square.and.arrow.up"
        case .invite:    return "person.badge.plus"
        case .volunteer: return "figure.wave"
        case .hire:      return "briefcase"
        case .mentor:    return "person.line.dotted.person"
        case .ask:       return "questionmark.bubble"
        case .save:      return "bookmark"
        case .followUp:  return "arrow.uturn.right.circle"
        case .more:      return "ellipsis"
        }
    }

    /// VoiceOver accessibility hint string.
    var accessibilityHint: String {
        switch self {
        case .discuss:   return "Open a discussion about this"
        case .pray:      return "Add this to a prayer"
        case .study:     return "Start a Bible study from this"
        case .share:     return "Share this with others"
        case .invite:    return "Invite someone to this"
        case .volunteer: return "Sign up to volunteer"
        case .hire:      return "Post or respond to a role"
        case .mentor:    return "Request or offer mentorship"
        case .ask:       return "Ask a question about this"
        case .save:      return "Save to your library"
        case .followUp:  return "Add a follow-up to this"
        case .more:      return "Show more actions"
        }
    }

    /// Maps to an AmenIntent raw value for composer pre-selection.
    /// `nil` for local-only actions (save, followUp, more).
    var intentRawValue: String? {
        switch self {
        case .discuss:   return AmenIntent.discuss.rawValue
        case .pray:      return AmenIntent.pray.rawValue
        case .study:     return AmenIntent.study.rawValue
        case .share:     return AmenIntent.share.rawValue
        case .invite:    return AmenIntent.invite.rawValue
        case .volunteer: return AmenIntent.volunteer.rawValue
        case .hire:      return AmenIntent.hire.rawValue
        case .mentor:    return AmenIntent.mentor.rawValue
        case .ask:       return AmenIntent.ask.rawValue
        case .save, .followUp, .more:
            return nil
        }
    }

    /// Whether this action opens AmenUniversalComposer.
    var opensComposer: Bool { intentRawValue != nil }
}

// MARK: - AmenActionPillModel

/// Resolved action model for one object instance.
///
/// Constructed once per object render; held as a `let` in the view hierarchy.
/// All mutation (save toggling, followUp) happens in `AmenActionPillContainer`.
struct AmenActionPillModel: Sendable {

    // MARK: Object identity

    /// `AmenObjectType` of the object this pill is attached to.
    let objectType: AmenObjectType

    /// Firestore document path (e.g. `"posts/abc123"`).
    let objectRef: String

    /// Firebase UID of the object owner.
    let objectOwnerId: String

    /// Firebase UID of the viewing user.
    let currentUserId: String

    // MARK: Local state

    /// Whether the current user has saved this object.
    var isSaved: Bool

    /// Whether the current user has requested a follow-up on this object.
    var isFollowedUp: Bool

    // MARK: Available actions

    /// Ordered PillAction array for this object type.
    ///
    /// Derived from `ObjectCapability.capabilities(for:)` then mapped to PillActions.
    /// Priority order: discuss → pray → study → share → save → invite → volunteer → hire → mentor → ask → followUp
    ///
    /// Anti-engagement: No view/like/reaction counts are surfaced here.
    var availableActions: [PillAction] {
        let caps = ObjectCapability.capabilities(for: objectType)
        var actions: [PillAction] = []

        // Ordered by spiritual/social relevance priority
        if caps.contains(.discuss)  { actions.append(.discuss) }
        if caps.contains(.pray)     { actions.append(.pray) }
        if caps.contains(.study)    { actions.append(.study) }
        if caps.contains(.share)    { actions.append(.share) }
        if caps.contains(.save)     { actions.append(.save) }
        if caps.contains(.invite)   { actions.append(.invite) }

        // Role-gated / feature-flagged actions — appended after core set
        // Gated at compose time via AmenUniversalComposer / RBACService
        if caps.contains(.followUp) { actions.append(.followUp) }

        // Extended professional actions by object type
        switch objectType {
        case .job:
            actions.append(.hire)
            actions.append(.ask)
        case .organization, .church:
            actions.append(.volunteer)
            actions.append(.ask)
        case .space:
            actions.append(.volunteer)
        case .mentorship:
            actions.append(.mentor)
            actions.append(.ask)
        case .bereanInsight:
            actions.append(.mentor)
            actions.append(.ask)
        case .post, .moment:
            actions.append(.ask)
        case .event:
            actions.append(.volunteer)
        default:
            break
        }

        return actions
    }

    /// The top-N actions to show in the collapsed pill (before overflow).
    func collapsedActions(maxVisible: Int = 4) -> [PillAction] {
        Array(availableActions.prefix(maxVisible))
    }

    /// Actions that overflow into the expanded pill.
    func overflowActions(maxVisible: Int = 4) -> [PillAction] {
        let all = availableActions
        guard all.count > maxVisible else { return [] }
        return Array(all.dropFirst(maxVisible))
    }
}
