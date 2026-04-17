//
//  GroupLinkModels.swift
//  AMENAPP
//
//  Data models for the Group Chat via Link feature.
//  Extends the existing messaging architecture without replacing it.
//

import Foundation
import FirebaseFirestore

// MARK: - Group Purpose

/// Purpose categories for link-created groups. Used for smart defaults.
enum GroupPurpose: String, Codable, CaseIterable, Identifiable {
    case general
    case prayer
    case bibleStudy = "bible_study"
    case event
    case church
    case fellowship

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return "General"
        case .prayer: return "Prayer"
        case .bibleStudy: return "Bible Study"
        case .event: return "Event"
        case .church: return "Church"
        case .fellowship: return "Fellowship"
        }
    }

    var icon: String {
        switch self {
        case .general: return "person.3.fill"
        case .prayer: return "hands.sparkles.fill"
        case .bibleStudy: return "book.fill"
        case .event: return "calendar"
        case .church: return "building.columns.fill"
        case .fellowship: return "heart.circle.fill"
        }
    }
}

// MARK: - Join Mode

/// How new members can join a link-created group.
enum GroupJoinMode: String, Codable, CaseIterable, Identifiable {
    case open
    case approvalRequired = "approval_required"
    case restricted

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .open: return "Open"
        case .approvalRequired: return "Approval Required"
        case .restricted: return "Restricted"
        }
    }

    var subtitle: String {
        switch self {
        case .open: return "Anyone with the link can join instantly"
        case .approvalRequired: return "Admins must approve each request"
        case .restricted: return "Only invited members can join"
        }
    }

    var icon: String {
        switch self {
        case .open: return "door.left.hand.open"
        case .approvalRequired: return "person.badge.clock"
        case .restricted: return "lock.fill"
        }
    }
}

// MARK: - Safety Tier

/// Safety tier controls how aggressively trust checks are applied.
enum GroupSafetyTier: String, Codable, CaseIterable, Identifiable {
    case standard
    case strict

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .strict: return "Strict"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: return "Basic trust checks for joiners"
        case .strict: return "Enhanced checks — recommended for prayer groups"
        }
    }
}

// MARK: - Group Link Status

enum GroupLinkStatus: String, Codable {
    case active
    case paused
    case disabled
    case expired
}

// MARK: - Group Link

/// Represents an active invite link for a group conversation.
/// Stored as a subcollection document under `conversations/{id}/groupLinks/{linkId}`.
struct GroupLink: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    let conversationId: String
    let token: String
    let createdBy: String
    let createdAt: Date
    var status: GroupLinkStatus
    var expiresAt: Date?
    var memberLimit: Int?
    var joinCount: Int
    var joinMode: GroupJoinMode
    var safetyTier: GroupSafetyTier

    enum CodingKeys: String, CodingKey {
        case id, conversationId, token, createdBy, createdAt
        case status, expiresAt, memberLimit, joinCount
        case joinMode, safetyTier
    }

    /// Whether this link is currently valid for use.
    var isUsable: Bool {
        guard status == .active else { return false }
        if let expiresAt, expiresAt < Date() { return false }
        if let memberLimit, joinCount >= memberLimit { return false }
        return true
    }

    /// Shareable URL for this link.
    var shareURL: URL? {
        URL(string: "https://amenapp.com/group/join?token=\(token)")
    }

    /// Deep link URL (app scheme).
    var deepLinkURL: URL? {
        URL(string: "amenapp://group/join?token=\(token)")
    }
}

// MARK: - Group Link Preview

/// Safe preview data shown to a user before they join.
struct GroupLinkPreview: Codable, Equatable {
    let groupName: String
    let purpose: GroupPurpose
    let memberCount: Int
    let joinMode: GroupJoinMode
    let safetyTier: GroupSafetyTier
    let isExpired: Bool
    let isFull: Bool
    let isDisabled: Bool
    let isPaused: Bool
    let groupAvatarURL: String?
    let creatorName: String?

    /// Number of people the viewer follows who are already in this group.
    var mutualMemberCount: Int = 0
    /// Display names of up to 2 mutual members for the trust signal.
    var mutualMemberNames: [String] = []

    enum CodingKeys: String, CodingKey {
        case groupName, purpose, memberCount, joinMode, safetyTier
        case isExpired, isFull, isDisabled, isPaused
        case groupAvatarURL, creatorName
        case mutualMemberCount, mutualMemberNames
    }

    /// Human-readable trust signal text.
    var trustSignalText: String? {
        if mutualMemberCount == 0 {
            return "You don't follow anyone in this group"
        } else if mutualMemberCount == 1, let first = mutualMemberNames.first {
            return "\(first) is in this group"
        } else if mutualMemberCount == 2, mutualMemberNames.count >= 2 {
            return "\(mutualMemberNames[0]) and \(mutualMemberNames[1]) are in this group"
        } else if let first = mutualMemberNames.first {
            return "\(first) and \(mutualMemberCount - 1) others you follow are here"
        }
        return "\(mutualMemberCount) people you follow are here"
    }
}

// MARK: - Join Evaluation Result

/// Server-side evaluation of whether a user can join.
enum JoinEvaluationOutcome: String, Codable {
    case allowed
    case requestRequired = "request_required"
    case blocked
    case expired
    case full
    case disabled
    case alreadyMember = "already_member"
    case paused
}

struct JoinEvaluationResult: Codable, Equatable {
    let outcome: JoinEvaluationOutcome
    let reason: String?
    let conversationId: String?
}

// MARK: - Join Request

/// A pending request from a user to join an approval-required group.
struct GroupJoinRequest: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    let conversationId: String
    let linkId: String
    let userId: String
    let userName: String
    let userPhotoURL: String?
    let requestedAt: Date
    var status: JoinRequestStatus
    var respondedBy: String?
    var respondedAt: Date?
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case id, conversationId, linkId, userId, userName
        case userPhotoURL, requestedAt, status
        case respondedBy, respondedAt, reason
    }
}

enum JoinRequestStatus: String, Codable {
    case pending
    case approved
    case denied
}

// MARK: - Create Group Link Configuration

/// Parameters for creating a new group with an invite link.
struct CreateGroupLinkConfig {
    var groupName: String = ""
    var purpose: GroupPurpose = .general
    var joinMode: GroupJoinMode = .open
    var safetyTier: GroupSafetyTier = .standard
    var memberLimit: Int? = nil
    var expirationDays: Int? = nil
    /// Sub-day expiration (1 = 1 hour, 24 = 1 day). When set, overrides expirationDays.
    var expirationHours: Int? = nil

    /// Effective expiration days accounting for hour-based expiration.
    var effectiveExpirationDays: Int? {
        if let hours = expirationHours {
            // For the service layer: convert hours to fractional days isn't possible,
            // so we pass hours directly and let the service handle it.
            return hours >= 24 ? hours / 24 : nil
        }
        return expirationDays
    }

    /// Apply smart defaults based on purpose.
    mutating func applyPurposeDefaults() {
        switch purpose {
        case .prayer:
            if joinMode == .open { joinMode = .approvalRequired }
            if safetyTier == .standard { safetyTier = .strict }
        case .bibleStudy:
            if expirationDays == nil && expirationHours == nil { expirationDays = 7 }
        case .event:
            if expirationDays == nil && expirationHours == nil { expirationDays = 3 }
        case .church:
            if joinMode == .open { joinMode = .approvalRequired }
        case .general, .fellowship:
            break
        }
    }
}
