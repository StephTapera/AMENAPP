import Foundation

// MARK: - Supporting Enums

enum AmenHubPrivacyLevel: String, Codable, CaseIterable, Hashable {
    case `public`
    case followersVisible
    case `private`
}

enum AmenHubInteractionType: String, Codable, CaseIterable, Hashable {
    case posted
    case saved
    case listened
    case watched
    case prayed
    case discussed
    case joined
    case shared
}

// MARK: - AmenHubTopicChip

struct AmenHubTopicChip: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let label: String
    let iconName: String?
    let postCount: Int
}

// MARK: - AmenHubActivitySummary

struct AmenHubActivitySummary: Codable, Equatable, Hashable {
    let recentPosterCount: Int
    let totalPrayerCount: Int
    let weeklyPostCount: Int
    let weeklyGrowthPercent: Double
    let lastActivityAt: Date?
}

// MARK: - AmenCanonicalObject

/// Cross-provider canonical entity. The same song on Spotify and Apple Music resolves to one canonical object.
struct AmenCanonicalObject: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let objectType: AmenSmartObjectType
    let title: String
    let subtitle: String?
    let creatorName: String?
    let artworkUrl: String?
    let canonicalUrl: String?
    let providerIds: [String: String]     // provider rawValue → providerId
    let primaryProvider: AmenAttachmentProvider?
    let safetyStatus: AmenAttachmentSafetyStatus
    let explicitContentState: AmenExplicitContentState
    let totalPostCount: Int
    let activeUserCount: Int
    let hubId: String?
    let contentCategory: AmenSmartContentCategory
    let createdAt: Date?
    let updatedAt: Date?

    var primaryProviderLogoName: String? {
        guard let provider = primaryProvider else { return nil }
        switch provider {
        case .appleMusic: return "applemusic"
        case .spotify: return "spotify"
        case .youtube: return "youtube"
        case .generic: return nil
        default: return nil
        }
    }
}

// MARK: - AmenCommunityHub

/// A community hub that forms around a canonical object (a song, video, article, etc.).
/// Hubs aggregate posts, prayers, discussions, and activity related to that object.
struct AmenCommunityHub: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let canonicalObjectId: String
    let title: String
    let subtitle: String?
    let artworkUrl: String?
    let totalMembers: Int
    let weeklyPostCount: Int
    let totalPostCount: Int
    let safetyStatus: AmenAttachmentSafetyStatus
    let privacyLevel: AmenHubPrivacyLevel
    let topicChips: [AmenHubTopicChip]
    let relatedObjectIds: [String]
    let discussionPrompts: [String]
    let activitySummary: AmenHubActivitySummary?
    let contentCategory: AmenSmartContentCategory
    let explicitContentState: AmenExplicitContentState
    let createdAt: Date?
    let updatedAt: Date?

    var isDiscoverable: Bool {
        privacyLevel == .public && safetyStatus != .blocked && explicitContentState != .blocked
    }
}

// MARK: - AmenObjectHubMembership

/// Tracks a user's relationship with a specific hub.
struct AmenObjectHubMembership: Codable, Equatable, Hashable {
    let hubId: String
    let userId: String
    let interactionTypes: [AmenHubInteractionType]
    let lastInteractedAt: Date?
    let isMuted: Bool
    let joinedAt: Date?

    var hasJoined: Bool { joinedAt != nil }

    var primaryInteraction: AmenHubInteractionType? {
        let priority: [AmenHubInteractionType] = [.posted, .discussed, .prayed, .saved, .listened, .watched, .shared, .joined]
        return priority.first { interactionTypes.contains($0) }
    }
}

// MARK: - AmenHubRecentActivity

/// Aggregate-safe activity card shown in the activity strip.
struct AmenHubRecentActivity: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let label: String
    let count: Int
    let iconName: String
    let period: String  // e.g. "this week", "today"
}

extension AmenCommunityHub {
    /// Generates aggregate-safe activity cards for the activity strip.
    func activityCards() -> [AmenHubRecentActivity] {
        guard let summary = activitySummary else { return [] }
        var cards: [AmenHubRecentActivity] = []

        if summary.totalPrayerCount > 0 {
            cards.append(AmenHubRecentActivity(
                id: "\(id)_prayer",
                label: "praying with this",
                count: summary.totalPrayerCount,
                iconName: "hands.sparkles",
                period: "total"
            ))
        }
        if summary.weeklyPostCount > 0 {
            cards.append(AmenHubRecentActivity(
                id: "\(id)_posts",
                label: "posts",
                count: summary.weeklyPostCount,
                iconName: "bubble.left.and.bubble.right",
                period: "this week"
            ))
        }
        if summary.recentPosterCount > 0 {
            cards.append(AmenHubRecentActivity(
                id: "\(id)_people",
                label: "people active",
                count: summary.recentPosterCount,
                iconName: "person.2",
                period: "this week"
            ))
        }
        return cards
    }
}

// MARK: - AmenPostCommunityHubPreview

/// Lightweight preview of the community hub attached to a single post.
struct AmenPostCommunityHubPreview: Identifiable, Codable, Equatable, Hashable {
    var id: String { hubId }
    let hubId: String
    let canonicalObjectId: String
    let objectTypeRaw: String
    let title: String
    let aggregateText: String
    let actionText: String
    let safetyStateRaw: String
    let explicitContentStateRaw: String
    let privacyStateRaw: String
    let iconKind: String?
    let canonicalUrl: String?
}
