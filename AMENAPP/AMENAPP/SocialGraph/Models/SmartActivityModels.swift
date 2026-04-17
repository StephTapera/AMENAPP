// SmartActivityModels.swift
// AMENAPP
//
// Core data models for the Smart Activity Layer on follower/following lists.
// Designed for Firestore precomputed aggregation — no client-side fan-out.

import Foundation

// MARK: - UserActivitySummary

/// Firestore path: user_activity_summary/{userId}
/// Written by `updateUserActivitySummary` Cloud Function on post/prayer/note activity.
struct UserActivitySummary: Codable, Identifiable {
    var id: String { userId }
    let userId: String

    var lastPostAt: Date?
    var lastPrayerAt: Date?
    var lastNoteAt: Date?
    var lastActiveAt: Date?

    var postCount7d: Int
    var prayerCount7d: Int
    var noteCount7d: Int

    var latestPostSnippet: String?
    var latestPostId: String?

    var topicTags: [String]
    var activeStreak: Int   // consecutive days with any activity

    var updatedAt: Date

    // MARK: Derived

    var hasRecentActivity: Bool {
        guard let last = lastActiveAt else { return false }
        return Date().timeIntervalSince(last) < 7 * 86_400
    }

    var primaryActivityType: SmartActivityType {
        let scores: [(SmartActivityType, Int)] = [
            (.post, postCount7d),
            (.prayer, prayerCount7d),
            (.note, noteCount7d),
        ]
        return scores.max(by: { $0.1 < $1.1 })?.0 ?? .post
    }

    init(userId: String) {
        self.userId = userId
        self.postCount7d = 0
        self.prayerCount7d = 0
        self.noteCount7d = 0
        self.topicTags = []
        self.activeStreak = 0
        self.updatedAt = Date()
    }
}

// MARK: - RelationshipActivityState

/// Firestore path: relationship_activity_state/{viewerId}_{targetId}
/// Written by `computeRelationshipActivityState` Cloud Function.
/// Viewer-specific: tracks what THIS viewer has/hasn't seen about the target.
struct RelationshipActivityState: Codable {
    let viewerId: String
    let targetId: String

    var unseenPostCount: Int
    var unseenPrayerCount: Int
    var unseenNoteCount: Int

    var lastSeenAt: Date?
    var lastActivityAt: Date?

    var hasMutualInteraction: Bool  // viewer ↔ target commented/reacted to each other
    var mutualTopics: [String]      // overlapping topic interests

    var computedAt: Date

    var compositeId: String { "\(viewerId)_\(targetId)" }

    var totalUnseenCount: Int {
        unseenPostCount + unseenPrayerCount + unseenNoteCount
    }

    var hasUnseen: Bool { totalUnseenCount > 0 }

    init(viewerId: String, targetId: String) {
        self.viewerId = viewerId
        self.targetId = targetId
        self.unseenPostCount = 0
        self.unseenPrayerCount = 0
        self.unseenNoteCount = 0
        self.hasMutualInteraction = false
        self.mutualTopics = []
        self.computedAt = Date()
    }
}

// MARK: - SmartActivityType

enum SmartActivityType: String, Codable, CaseIterable {
    case post
    case prayer
    case note
    case verse
    case none

    var systemImage: String {
        switch self {
        case .post: return "text.bubble"
        case .prayer: return "hands.sparkles"
        case .note: return "note.text"
        case .verse: return "book.closed"
        case .none: return "circle.dashed"
        }
    }

    var displayLabel: String {
        switch self {
        case .post: return "posted"
        case .prayer: return "prayed"
        case .note: return "took notes"
        case .verse: return "shared a verse"
        case .none: return ""
        }
    }
}

// MARK: - SmartActivityState

/// Distilled activity state for a single user row — computed from
/// UserActivitySummary + RelationshipActivityState combined.
struct SmartActivityState: Equatable {
    let userId: String

    var activityType: SmartActivityType
    var unseenCount: Int
    var lastActivityAt: Date?
    var hasUnseen: Bool
    var hasMutualInteraction: Bool
    var activeStreak: Int
    var mutualTopics: [String]
    var snippet: String?

    var isActive: Bool {
        guard let last = lastActivityAt else { return false }
        return Date().timeIntervalSince(last) < 3 * 86_400
    }

    static let empty = SmartActivityState(
        userId: "",
        activityType: .none,
        unseenCount: 0,
        lastActivityAt: nil,
        hasUnseen: false,
        hasMutualInteraction: false,
        activeStreak: 0,
        mutualTopics: [],
        snippet: nil
    )
}

// MARK: - SmartActivityCopyModel

/// Display copy for a row's activity badge — localizable, concise.
struct SmartActivityCopyModel: Equatable {
    let headline: String        // e.g. "Posted 3h ago"
    let subtext: String?        // e.g. "2 new posts · Shared a verse"
    let badgeCount: Int         // > 0 → show badge
    let badgeLabel: String?     // e.g. "2 new"
    let accentColor: ActivityAccentColor

    static let empty = SmartActivityCopyModel(
        headline: "",
        subtext: nil,
        badgeCount: 0,
        badgeLabel: nil,
        accentColor: .muted
    )
}

enum ActivityAccentColor: String, Codable {
    case vibrant   // recently active, unseen content
    case moderate  // some activity, all seen
    case muted     // no recent activity

    var opacity: Double {
        switch self {
        case .vibrant: return 1.0
        case .moderate: return 0.7
        case .muted: return 0.4
        }
    }
}

// MARK: - SmartUserRowViewModel

/// Fully-resolved model for rendering a SmartUserRow.
struct SmartUserRowViewModel: Identifiable, Equatable {
    let id: String              // userId
    let displayName: String
    let username: String
    let profileImageURL: String?
    let bio: String?
    let isFollowing: Bool
    let isFollowedBack: Bool    // target follows viewer back (mutual)

    var activityState: SmartActivityState
    var copy: SmartActivityCopyModel

    var isMutual: Bool { isFollowing && isFollowedBack }

    static func == (lhs: SmartUserRowViewModel, rhs: SmartUserRowViewModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.isFollowing == rhs.isFollowing &&
        lhs.activityState == rhs.activityState
    }
}

// MARK: - SocialGraphFilter

enum SocialGraphFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case mutual = "Mutual"
    case recentlyActive = "Active"
    case hasUnseen = "New"
    case notFollowingBack = "Not back"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: return "person.2"
        case .mutual: return "arrow.triangle.2.circlepath"
        case .recentlyActive: return "bolt"
        case .hasUnseen: return "circle.badge.fill"
        case .notFollowingBack: return "person.badge.minus"
        }
    }
}

// MARK: - SocialGraphSortMode

enum SocialGraphSortMode: String, CaseIterable, Identifiable {
    case smartDefault = "Smart"
    case newest = "Newest"
    case oldest = "Oldest"
    case mostActive = "Most Active"
    case alphabetical = "A–Z"

    var id: String { rawValue }
}

// MARK: - SocialGraphListType

enum SocialGraphListType {
    case followers(userId: String)
    case following(userId: String)
    case mutuals(userId: String)

    var userId: String {
        switch self {
        case .followers(let uid), .following(let uid), .mutuals(let uid): return uid
        }
    }

    var title: String {
        switch self {
        case .followers: return "Followers"
        case .following: return "Following"
        case .mutuals: return "Mutual"
        }
    }
}
