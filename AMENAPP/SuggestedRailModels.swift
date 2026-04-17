// SuggestedRailModels.swift
// AMENAPP
//
// Shared models for the Suggested Accounts rail system.
// Extracted from SuggestedForYouModule.swift and extended with
// surface-aware types for OpenTable, Prayer, and Testimonies feeds.

import Foundation

// MARK: - Surface Enum

/// Which feed surface is rendering the suggestions rail.
enum SuggestionSurface: String, Sendable, CaseIterable {
    case openTable     = "open_table"
    case prayer        = "prayer"
    case testimonies   = "testimonies"

    var title: String {
        switch self {
        case .openTable:    return "Suggested for you"
        case .prayer:       return "Prayer connections"
        case .testimonies:  return "Stories and voices for you"
        }
    }

    var subtitle: String {
        switch self {
        case .openTable:    return "Based on community, trust, and shared activity"
        case .prayer:       return "People who share your prayer heart"
        case .testimonies:  return "Testimonies from voices you may connect with"
        }
    }

    /// User-facing explanation shown when "Why am I seeing this?" is tapped.
    var whyShownExplanation: String {
        switch self {
        case .openTable:
            return "These suggestions are based on people followed by others in your community, shared interests, and activity on AMEN. You can dismiss any card or hide this section from the menu."
        case .prayer:
            return "These prayer connections are suggested based on shared prayer topics, mutual community members, and your activity in the prayer feed. You can dismiss or hide them anytime."
        case .testimonies:
            return "These voices are suggested based on testimony themes that resonate with your interests, mutual connections, and community engagement. You can dismiss or hide them anytime."
        }
    }
}

// MARK: - Account Type

enum SuggestionAccountType: String, Sendable {
    case personal, church, creator, business, ministry, official

    var badge: String? {
        switch self {
        case .church:    return "Church"
        case .creator:   return "Creator"
        case .ministry:  return "Ministry"
        case .business:  return "Business"
        case .official, .personal: return nil
        }
    }
}

// MARK: - Reason Type

enum SuggestionReasonType: String, Sendable {
    case mutuals           // "Followed by X + N others"
    case communityOverlap  // "Active in your community"
    case topicOverlap      // "Posts about {topic1} and {topic2}"
    case prayerActive      // "Active in prayer"
    case prayerThemeMatch  // "Prays about healing and family"
    case testimonyActive   // "Active in testimony"
    case churchNear        // "Church near you"
    case popularCreator    // "Popular faith creator"
    case recentlyActive    // "Recently active in topics you read"
    case newHighTrust      // "New here · high trust"
    case popularInAMEN     // "Popular in AMEN"
    case generic           // "Suggested for you"
}

// MARK: - Suggestion Item

struct SuggestionItem: Identifiable, Equatable {
    let id: String                         // userId
    let displayName: String
    let handle: String
    let avatarURL: String?
    let isVerified: Bool
    let isPrivate: Bool
    let accountType: SuggestionAccountType
    let reasonType: SuggestionReasonType
    let reasonText: String                 // Human-readable reason
    let mutualCount: Int                   // 0 = not shown
    let mutualNames: [String]              // Up to 2 display names for "Followed by X + N"
    let mutualAvatarURLs: [String]         // Up to 3 URLs for overlapping avatars
    let score: Double                      // Internal ranking score
    let contextLine: String?               // Optional sub-reason e.g. "Shared circles"

    // Extended fields for surface-specific content
    let bio: String?
    let prayerThemes: [String]
    let recentTestimonyExcerpt: String?
    let followerCount: Int
    let postCount: Int
    let sharedTopics: [String]

    var initials: String {
        String(
            displayName.components(separatedBy: " ")
                .compactMap { $0.first }
                .map { String($0) }
                .joined()
                .prefix(2)
                .uppercased()
        )
    }

    static func == (lhs: SuggestionItem, rhs: SuggestionItem) -> Bool {
        lhs.id == rhs.id
    }

    /// Convenience initializer with defaults for the new extended fields.
    init(
        id: String,
        displayName: String,
        handle: String,
        avatarURL: String?,
        isVerified: Bool,
        isPrivate: Bool,
        accountType: SuggestionAccountType,
        reasonType: SuggestionReasonType,
        reasonText: String,
        mutualCount: Int,
        mutualNames: [String],
        mutualAvatarURLs: [String],
        score: Double,
        contextLine: String?,
        bio: String? = nil,
        prayerThemes: [String] = [],
        recentTestimonyExcerpt: String? = nil,
        followerCount: Int = 0,
        postCount: Int = 0,
        sharedTopics: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.avatarURL = avatarURL
        self.isVerified = isVerified
        self.isPrivate = isPrivate
        self.accountType = accountType
        self.reasonType = reasonType
        self.reasonText = reasonText
        self.mutualCount = mutualCount
        self.mutualNames = mutualNames
        self.mutualAvatarURLs = mutualAvatarURLs
        self.score = score
        self.contextLine = contextLine
        self.bio = bio
        self.prayerThemes = prayerThemes
        self.recentTestimonyExcerpt = recentTestimonyExcerpt
        self.followerCount = followerCount
        self.postCount = postCount
        self.sharedTopics = sharedTopics
    }
}

// MARK: - Rail Configuration

/// Per-surface configuration for animation timing and layout.
struct SuggestionRailConfig {
    let surface: SuggestionSurface
    let animationResponse: Double
    let animationDamping: Double
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    static let openTable = SuggestionRailConfig(
        surface: .openTable,
        animationResponse: 0.25,
        animationDamping: 0.82,
        cardWidth: 168,
        cardHeight: 240
    )

    static let prayer = SuggestionRailConfig(
        surface: .prayer,
        animationResponse: 0.35,
        animationDamping: 0.88,
        cardWidth: 168,
        cardHeight: 240
    )

    static let testimonies = SuggestionRailConfig(
        surface: .testimonies,
        animationResponse: 0.30,
        animationDamping: 0.85,
        cardWidth: 168,
        cardHeight: 240
    )
}

// MARK: - Feedback Event

/// Tracks a user's interaction with a suggestion for fatigue/analytics.
struct SuggestionFeedbackEvent {
    enum Action: String {
        case impression, follow, dismiss, hide, peek, profileOpen, showFewer, whyShown
    }

    let targetUserId: String
    let action: Action
    let surface: SuggestionSurface
    let position: Int
    let timestamp: Date
    var impressionCount: Int
    var railHideCount: Int
    var reasonCluster: String?

    init(targetUserId: String, action: Action, surface: SuggestionSurface, position: Int = -1, impressionCount: Int = 0, railHideCount: Int = 0, reasonCluster: String? = nil) {
        self.targetUserId = targetUserId
        self.action = action
        self.surface = surface
        self.position = position
        self.timestamp = Date()
        self.impressionCount = impressionCount
        self.railHideCount = railHideCount
        self.reasonCluster = reasonCluster
    }
}
