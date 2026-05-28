import Foundation

enum AmenSpacesDiscussionSourceType: String, CaseIterable, Codable, Identifiable {
    case church
    case college
    case university
    case nonprofit
    case organization
    case personal
    case marketplace
    case mentor
    case creator

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .church: return "Church"
        case .college: return "College"
        case .university: return "University"
        case .nonprofit: return "Nonprofit"
        case .organization: return "Organization"
        case .personal: return "Personal"
        case .marketplace: return "Marketplace"
        case .mentor: return "Mentor"
        case .creator: return "Creator"
        }
    }
}

enum AmenSpacesDiscussionCategory: String, CaseIterable, Codable, Identifiable {
    case all = "All"
    case trending = "Trending"
    case churches = "Churches"
    case colleges = "Colleges"
    case universities = "Universities"
    case organizations = "Organizations"
    case bibleStudy = "Bible Study"
    case career = "Career"
    case mentorship = "Mentorship"
    case parents = "Parents"
    case jobs = "Jobs"
    case babysitting = "Babysitting"
    case tutoring = "Tutoring"
    case volunteering = "Volunteering"
    case localHelp = "Local Help"
    case liveNow = "Live Now"
    case new = "New"
    case nearYou = "Near You"

    var id: String { rawValue }
}

enum AmenSpacesDiscussionVisibility: String, CaseIterable, Codable {
    case publicOpen
    case organizationOnly
    case privateRestricted
    case paidMemberOnly
    case youthProtected
    case confidential
    case readOnlyPublic
}

enum AmenSpacesDiscussionJoinPolicy: String, CaseIterable, Codable {
    case open
    case requestRequired
    case inviteOnly
    case paidOnly
    case roleRestricted
    case readOnly
}

enum AmenSpacesDiscussionMembershipStatus: String, CaseIterable, Codable {
    case notJoined
    case requested
    case joined
    case blocked
    case unavailable
}

enum AmenSpacesDiscussionSafetyStatus: String, CaseIterable, Codable {
    case allowed
    case allowWithWarning
    case needsReview
    case blocked
}

enum AmenSpacesDiscussionModerationStatus: String, CaseIterable, Codable {
    case visible
    case underReview
    case hidden
    case deleted
}

enum AmenSpacesDiscussionTrustBadge: String, CaseIterable, Codable, Identifiable {
    case verified = "Verified"
    case moderated = "Moderated"
    case youthSafe = "Youth Safe"
    case backgroundChecked = "Background Checked"
    case organizationVerified = "Organization Verified"
    case trustedMarketplace = "Trusted Marketplace"

    var id: String { rawValue }
}

enum AmenSpacesDiscussionAccessAction: String, Codable, Equatable {
    case join = "Join"
    case request = "Request"
    case view = "View"
    case open = "Open"
    case joined = "Joined"
    case live = "Live"
    case unavailable = "Unavailable"
}

struct AmenSpacesDiscussionAccessContext: Equatable {
    var isOrganizationMember: Bool
    var userTierIds: Set<String>
    var canAccessYouthProtected: Bool
    var canViewConfidential: Bool
    var blockedDiscussionIds: Set<String>
    var mutedDiscussionIds: Set<String>

    static let guest = AmenSpacesDiscussionAccessContext(
        isOrganizationMember: false,
        userTierIds: [],
        canAccessYouthProtected: false,
        canViewConfidential: false,
        blockedDiscussionIds: [],
        mutedDiscussionIds: []
    )
}

struct AmenSpacesDiscussionDiscoveryItem: Identifiable, Hashable, Codable {
    var id: String
    var spaceId: String
    var organizationId: String?
    var sourceType: AmenSpacesDiscussionSourceType
    var title: String
    var subtitle: String
    var descriptionPreview: String
    var bannerImageURL: String?
    var avatarURL: String?
    var category: AmenSpacesDiscussionCategory
    var tags: [String]
    var visibility: AmenSpacesDiscussionVisibility
    var joinPolicy: AmenSpacesDiscussionJoinPolicy
    var membershipStatus: AmenSpacesDiscussionMembershipStatus
    var participantCount: Int
    var unreadCount: Int
    var trendingScore: Double
    var safetyStatus: AmenSpacesDiscussionSafetyStatus
    var moderationStatus: AmenSpacesDiscussionModerationStatus
    var trustBadges: [AmenSpacesDiscussionTrustBadge]
    var isLive: Bool
    var isVerified: Bool
    var isYouthProtected: Bool
    var isConfidential: Bool
    var requiresTier: String?
    var createdAt: Date
    var lastActivityAt: Date
    var recommendationReason: String?
    var aiSummary: String?
    var deepLink: URL?
    var isAIExcluded: Bool
    var isReportedByViewer: Bool
    var approximateRegion: String?

    var safeSubtitle: String {
        guard !isConfidential else { return "Confidential discussion" }
        if visibility == .paidMemberOnly { return "Member-only discussion" }
        if isYouthProtected { return "Youth-protected discussion" }
        return subtitle
    }

    func canSurface(in context: AmenSpacesDiscussionAccessContext) -> Bool {
        guard moderationStatus == .visible else { return false }
        guard safetyStatus == .allowed || safetyStatus == .allowWithWarning else { return false }
        guard membershipStatus != .blocked, !isReportedByViewer else { return false }
        guard !context.blockedDiscussionIds.contains(id), !context.mutedDiscussionIds.contains(id) else { return false }

        if isConfidential || visibility == .confidential {
            return context.canViewConfidential || membershipStatus == .joined
        }
        if isYouthProtected || visibility == .youthProtected {
            return context.canAccessYouthProtected
        }
        if visibility == .privateRestricted || joinPolicy == .inviteOnly {
            return membershipStatus == .joined || context.isOrganizationMember
        }
        return true
    }

    func preview(in context: AmenSpacesDiscussionAccessContext) -> String {
        guard canSurface(in: context) else { return "Preview unavailable until access is approved." }
        if isConfidential || visibility == .confidential { return "Confidential discussion. Preview hidden." }
        if visibility == .paidMemberOnly, let requiresTier, !context.userTierIds.contains(requiresTier) {
            return "Member-only discussion. Preview available after access is confirmed."
        }
        if isYouthProtected || visibility == .youthProtected {
            return context.canAccessYouthProtected ? descriptionPreview : "Youth-protected discussion. Preview hidden."
        }
        return aiSummary ?? descriptionPreview
    }

    func recommendationReason(in context: AmenSpacesDiscussionAccessContext) -> String? {
        guard canSurface(in: context) else { return nil }
        guard !isConfidential, visibility != .confidential, !isYouthProtected else { return nil }
        if isAIExcluded { return recommendationReason }
        return recommendationReason
    }

    func accessAction(in context: AmenSpacesDiscussionAccessContext) -> AmenSpacesDiscussionAccessAction {
        guard canSurface(in: context) else { return .unavailable }
        if isLive, membershipStatus == .joined { return .live }
        switch membershipStatus {
        case .joined: return .joined
        case .requested: return .request
        case .blocked, .unavailable: return .unavailable
        case .notJoined:
            switch joinPolicy {
            case .open: return .join
            case .requestRequired: return .request
            case .inviteOnly: return .unavailable
            case .paidOnly: return .join
            case .roleRestricted: return context.isOrganizationMember ? .request : .unavailable
            case .readOnly: return .view
            }
        }
    }

    func matches(category: AmenSpacesDiscussionCategory) -> Bool {
        switch category {
        case .all: return true
        case .trending: return trendingScore >= 70
        case .churches: return sourceType == .church || self.category == .churches
        case .colleges: return sourceType == .college || self.category == .colleges
        case .universities: return sourceType == .university || self.category == .universities
        case .organizations: return [.organization, .nonprofit].contains(sourceType) || self.category == .organizations
        case .liveNow: return isLive
        case .new: return createdAt > Date().addingTimeInterval(-7 * 24 * 60 * 60)
        case .nearYou: return approximateRegion != nil
        default: return self.category == category || tags.contains { $0.localizedCaseInsensitiveContains(category.rawValue) }
        }
    }

    func matches(searchQuery: String) -> Bool {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = ([title, subtitle, descriptionPreview, sourceType.displayName] + tags).joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(trimmed)
    }
}

struct AmenSpacesOrganizationSpotlightItem: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var subtitle: String
    var bannerImageURL: String?
    var avatarURL: String?
    var isVerified: Bool
    var openDiscussionCount: Int
    var upcomingEventCount: Int
    var trustBadges: [AmenSpacesDiscussionTrustBadge]
}

struct AmenSpacesDiscussionFilters: Equatable {
    var selectedCategory: AmenSpacesDiscussionCategory = .all
    var searchQuery: String = ""

    func apply(to items: [AmenSpacesDiscussionDiscoveryItem], context: AmenSpacesDiscussionAccessContext) -> [AmenSpacesDiscussionDiscoveryItem] {
        items
            .filter { $0.canSurface(in: context) }
            .filter { $0.matches(category: selectedCategory) }
            .filter { $0.matches(searchQuery: searchQuery) }
            .sorted { lhs, rhs in
                if lhs.isLive != rhs.isLive { return lhs.isLive && !rhs.isLive }
                if lhs.trendingScore != rhs.trendingScore { return lhs.trendingScore > rhs.trendingScore }
                return lhs.lastActivityAt > rhs.lastActivityAt
            }
    }
}
