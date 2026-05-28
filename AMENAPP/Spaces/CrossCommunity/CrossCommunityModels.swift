// CrossCommunityModels.swift
// AMENAPP — Spaces v2 Cross-Community Links (Agent F)
//
// Value types for the cross-community linking system.
// These are Agent F's own models, distinct from the canonical CommunityLink
// in SpacesModels.swift (which maps directly to Firestore via @DocumentID).
// CrossCommunityLinkService converts between the two.
//
// Hard constraints honoured:
//   - No hard-deletes — status flips only.
//   - Money never crosses a link (v1).
//   - No "church" in field names or copy.

import Foundation

// MARK: - CommunityLinkRecord
//
// Agent F's rich view of a cross-community link.
// Distinct from SpacesModels.CommunityLink (which is the raw Firestore doc).
// The service layer maps Firestore -> CommunityLinkRecord.

struct CommunityLinkRecord: Identifiable, Equatable {
    /// The Firestore document ID for this link.
    let id: String

    /// Community that sent the invite.
    let fromCommunityId: String

    /// Community that received the invite.
    let toCommunityId: String

    /// Current lifecycle status.
    var status: CrossLinkStatus

    /// Human-readable scope description, e.g. "Shared: Romans Study".
    let scope: String

    /// userId who initiated the invite.
    let createdBy: String

    let createdAt: Date
    var updatedAt: Date

    static func == (lhs: CommunityLinkRecord, rhs: CommunityLinkRecord) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.updatedAt == rhs.updatedAt
    }
}

// MARK: - CrossLinkStatus

enum CrossLinkStatus: String, Codable, Equatable {
    case pending
    case active
    case revoked
}

// MARK: - LinkedCommunityRecord
//
// Denormalized snapshot of a community that is actively linked to a Space.
// Drives the "already linked" list in LinkInviteSheet and the evident signal everywhere.

struct LinkedCommunityRecord: Identifiable, Equatable {
    /// communityId — stable identity.
    let id: String

    let name: String
    let avatarURL: String?

    /// Number of external members currently in the Space from this community.
    let externalMemberCount: Int

    /// The link document id for this relationship.
    let linkId: String

    let linkStatus: CrossLinkStatus
}
