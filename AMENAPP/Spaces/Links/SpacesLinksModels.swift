// SpacesLinksModels.swift
// AMENAPP — Spaces v2 Cross-Community Links (Agent F)
//
// View-layer models for the Links UX. These extend the canonical types
// defined by Agent A in SpacesCommunityModels.swift and SpacesModels.swift.
// Do NOT redefine CommunityLink or CommunityLinkStatus (those live in SpacesModels.swift).
//
// Hard constraints honoured:
//   - No hard-deletes — status flips only.
//   - Money never crosses a link (v1).
//   - No "church" in field names, string literals, or comments.
//   - No force-unwrap.

import Foundation

// MARK: - LinkInviteState

/// The invite flow state for the attach UX in LinkSpaceSheet.
enum LinkInviteState: Equatable {
    case idle
    case searching
    case found(community: AmenCommunity)
    case pendingAcceptance(linkId: String)
    case active
    case error(String)

    // Manual Equatable — AmenCommunity is Codable but may not be Equatable.
    static func == (lhs: LinkInviteState, rhs: LinkInviteState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):                          return true
        case (.searching, .searching):                return true
        case (.found(let a), .found(let b)):          return a.id == b.id
        case (.pendingAcceptance(let a), .pendingAcceptance(let b)): return a == b
        case (.active, .active):                      return true
        case (.error(let a), .error(let b)):          return a == b
        default:                                      return false
        }
    }
}

// MARK: - PendingLinkInvitation

/// Pending link invitation surfaced to target community admins in PendingInvitationsSheet.
/// Resolved from the sending community's links sub-collection.
struct PendingLinkInvitation: Identifiable {
    /// The Firestore link document ID.
    let id: String
    /// The Space being shared.
    let spaceId: String
    /// Human-readable title of the Space, resolved on load.
    let spaceTitle: String
    /// Community that sent the invite.
    let fromCommunityId: String
    /// Resolved display name of the sending community.
    let fromCommunityName: String
    /// Optional avatar URL of the sending community.
    let fromCommunityAvatarURL: String?
    /// When the invite was created.
    let createdAt: Date
}
