// SpacesCommunityModels.swift
// AMENAPP — Spaces v2 Data Layer (Agent A)
//
// Canonical community, space, and membership models for Spaces v2.
// All agents import this file for community/space type definitions.
// Never redefine these types in agent-owned files.

import Foundation
import FirebaseFirestore

// CommunityRole and CommunityLink are defined canonically in
// AMENAPP/AMENAPP/Spaces/SpacesModels.swift — do not redefine here.

// MARK: - Community

struct AmenCommunity: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var handle: String
    var avatarURL: String?
    var ownerUserId: String
    var stripeConnectAccountId: String?
    var createdAt: Date?
}

// MARK: - Community Member

struct AmenCommunityMember: Codable {
    var userId: String
    var role: CommunityRole
    var joinedAt: Date?
}

// MARK: - Space V2 Type
// Distinct from AmenSpaceType (the Phase 0 multi-purpose type).
// Drives the body renderer selection for Spaces v2 surfaces.

enum SpaceV2Type: String, Codable, CaseIterable {
    case chat           = "chat"
    case bibleStudy     = "bibleStudy"
    case group          = "group"
    case announcement   = "announcement"

    var displayName: String {
        switch self {
        case .chat:         return "Chat"
        case .bibleStudy:   return "Bible Study"
        case .group:        return "Group"
        case .announcement: return "Announcements"
        }
    }

    var systemImageName: String {
        switch self {
        case .chat:         return "bubble.left.and.bubble.right.fill"
        case .bibleStudy:   return "books.vertical.fill"
        case .group:        return "person.3.fill"
        case .announcement: return "megaphone.fill"
        }
    }

    var isLocked: Bool { false }

    var supportsStudyBlocks: Bool {
        self == .bibleStudy
    }
}

// MARK: - Access Policy

enum AccessPolicy: String, Codable {
    case free       = "free"
    case oneTime    = "oneTime"
    case recurring  = "recurring"
}

// MARK: - Price Config

struct PriceConfig: Codable {
    var amountCents: Int
    var currency: String
    var interval: String?
}

// MARK: - Space Extended (Spaces v2 canonical model)
// Extends the core Space concept. AmenSpaceV2 remains the Phase 0 contract;
// AmenSpaceExtended carries the new communityId, access-policy, and sharing fields.

struct AmenSpaceExtended: Codable, Identifiable {
    @DocumentID var id: String?
    var communityId: String
    var type: SpaceV2Type
    var title: String
    var description: String?
    var avatarURL: String?
    var createdBy: String
    var createdAt: Date?
    var accessPolicy: AccessPolicy
    var priceConfig: PriceConfig?
    var sharedWith: [String]
    var isDeleted: Bool
}

// MARK: - Space Member (v1 — manual-decoded from Firestore snapshot data)

enum SpaceCommunityMemberAccess: String, Codable {
    case granted = "granted"
    case none    = "none"
}

struct SpaceCommunityMember: Codable, Identifiable {
    var id: String { userId }
    var userId: String
    var role: String
    var homeCommunityId: String?
    var access: SpaceCommunityMemberAccess
    var joinedAt: Date?
}
