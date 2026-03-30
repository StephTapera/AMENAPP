// DiscoveryModels.swift
// AMEN App — Discovery & Search System
//
// Data models for the universal search and discovery experience.
// Designed for AMEN's safety-first, spiritually-grounded platform values.

import Foundation
import SwiftUI

// MARK: - Unified Search Result

/// A single result item returned from universal search across all entity types
struct DiscoveryResult: Identifiable, Equatable {
    let id: String
    let type: DiscoveryResultType
    var relevanceScore: Double       // 0–100, used for Top tab blending
    var safetyScore: Double          // 0–100; items below threshold are suppressed
}

enum DiscoveryResultType: Equatable {
    case person(DiscoveryPerson)
    case post(DiscoveryPost)
    case topic(DiscoveryTopic)
    case church(DiscoveryChurch)
    case note(DiscoveryNote)
    case resource(DiscoveryResource)
    case job(DiscoveryJob)

    var displayTitle: String {
        switch self {
        case .person(let p): return p.displayName
        case .post(let p): return p.excerpt
        case .topic(let t): return t.title
        case .church(let c): return c.name
        case .note(let n): return n.title
        case .resource(let r): return r.title
        case .job(let j): return j.title
        }
    }
}

// MARK: - Person Discovery Card Model

struct DiscoveryPerson: Identifiable, Equatable {
    let id: String              // userId
    let displayName: String
    let username: String
    let bio: String
    let avatarURL: String?
    let followerCount: Int
    let isVerified: Bool
    var isFollowing: Bool
    var mutualFollowersCount: Int
    var followReason: String?   // "Popular in Christian entrepreneurship"
    var topicAffinities: [String]
    var qualityScore: Double    // computed from profile completeness, engagement quality
}

// MARK: - Post Discovery Card Model

struct DiscoveryPost: Identifiable, Equatable {
    let id: String              // postId
    let authorId: String
    let authorName: String
    let authorHandle: String
    let authorAvatarURL: String?
    let excerpt: String         // truncated content for card
    let fullContent: String
    let category: String        // "prayer", "testimonies", etc.
    let topicTag: String?
    let createdAt: Date
    let amenCount: Int
    let commentCount: Int
    let imageURL: String?
    var highlightedExcerpt: String?  // query terms bolded
}

// MARK: - Topic Discovery Model

struct DiscoveryTopic: Identifiable, Equatable {
    let id: String
    let title: String
    let canonicalSlug: String   // URL-friendly identifier
    let description: String
    let icon: String            // SF Symbol name
    let iconColor: Color
    let backgroundColor: Color
    let postCount: Int
    let trendScore: Double      // 0–100; drives "trending" badge
    var isTrending: Bool        // true if trendScore >= 70
    var isFollowedByUser: Bool
    var relatedScripture: String?  // e.g. "Proverbs 3:5-6"
    var safetyState: TopicSafetyState

    enum TopicSafetyState: String {
        case approved       // cleared for discovery
        case restricted     // visible but de-ranked from broad discovery
        case pending        // awaiting moderation review
        case blocked        // removed from all discovery surfaces
    }

    // The curated AMEN topic catalog — safe, edifying, Christian-community-relevant
    static let catalog: [DiscoveryTopic] = [
        DiscoveryTopic(id: "personal-growth", title: "Personal Growth", canonicalSlug: "personal-growth",
                       description: "Faith-driven growth in character, discipline, and discipleship.",
                       icon: "leaf.fill", iconColor: .green, backgroundColor: Color.green.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: "2 Peter 1:5-8", safetyState: .approved),
        DiscoveryTopic(id: "prayer", title: "Prayer", canonicalSlug: "prayer",
                       description: "Prayer requests, testimonies of answered prayer, and how to pray.",
                       icon: "hands.sparkles.fill", iconColor: .purple, backgroundColor: Color.purple.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: "Philippians 4:6", safetyState: .approved),
        DiscoveryTopic(id: "bible-study", title: "Bible Study", canonicalSlug: "bible-study",
                       description: "Scripture-grounded discussion, notes, commentary, and reflection.",
                       icon: "book.fill", iconColor: .indigo, backgroundColor: Color.indigo.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: "2 Timothy 3:16", safetyState: .approved),
        DiscoveryTopic(id: "testimonies", title: "Testimonies", canonicalSlug: "testimonies",
                       description: "Stories of God's faithfulness, redemption, and transformation.",
                       icon: "star.fill", iconColor: .orange, backgroundColor: Color.orange.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: "Revelation 12:11", safetyState: .approved),
        DiscoveryTopic(id: "worship", title: "Worship", canonicalSlug: "worship",
                       description: "Music, liturgy, and reflections on worship and praise.",
                       icon: "music.note", iconColor: .pink, backgroundColor: Color.pink.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: "Psalm 150:6", safetyState: .approved),
        DiscoveryTopic(id: "christian-entrepreneurship", title: "Faith & Work", canonicalSlug: "faith-work",
                       description: "Integrating faith into career, business, and calling.",
                       icon: "briefcase.fill", iconColor: .teal, backgroundColor: Color.teal.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: "Colossians 3:23", safetyState: .approved),
        DiscoveryTopic(id: "marriage", title: "Marriage", canonicalSlug: "marriage",
                       description: "Advice, prayer, and resources for Christian marriage and family.",
                       icon: "heart.fill", iconColor: .red, backgroundColor: Color.red.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: "Ephesians 5:25", safetyState: .approved),
        DiscoveryTopic(id: "church-notes", title: "Church Notes", canonicalSlug: "church-notes",
                       description: "Sermon notes, discussion questions, and study materials.",
                       icon: "doc.text.fill", iconColor: .blue, backgroundColor: Color.blue.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: nil, safetyState: .approved),
        DiscoveryTopic(id: "mental-wellness", title: "Mental Wellness", canonicalSlug: "mental-wellness",
                       description: "Faith-based support for mental health, anxiety, and healing.",
                       icon: "brain.head.profile", iconColor: .cyan, backgroundColor: Color.cyan.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: "Isaiah 26:3", safetyState: .approved),
        DiscoveryTopic(id: "discipleship", title: "Discipleship", canonicalSlug: "discipleship",
                       description: "Following Jesus, mentorship, and growing as a disciple.",
                       icon: "person.2.fill", iconColor: .brown, backgroundColor: Color.brown.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: "Matthew 28:19", safetyState: .approved),
        DiscoveryTopic(id: "missions", title: "Missions", canonicalSlug: "missions",
                       description: "Global and local missions, evangelism, and serving others.",
                       icon: "globe.americas.fill", iconColor: .mint, backgroundColor: Color.mint.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: "Acts 1:8", safetyState: .approved),
        DiscoveryTopic(id: "young-adults", title: "Young Adults", canonicalSlug: "young-adults",
                       description: "Faith conversations relevant to college students and young adults.",
                       icon: "person.crop.circle", iconColor: .yellow, backgroundColor: Color.yellow.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: "1 Timothy 4:12", safetyState: .approved),
        DiscoveryTopic(id: "stewardship", title: "Finance & Stewardship", canonicalSlug: "stewardship",
                       description: "Biblical wisdom about money, giving, and generosity.",
                       icon: "dollarsign.circle.fill", iconColor: .green, backgroundColor: Color.green.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: "Proverbs 3:9", safetyState: .approved),
        DiscoveryTopic(id: "theology", title: "Theology", canonicalSlug: "theology",
                       description: "Doctrine, church history, apologetics, and theological reflection.",
                       icon: "building.columns.fill", iconColor: .indigo, backgroundColor: Color.indigo.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: nil, safetyState: .approved),
        DiscoveryTopic(id: "leadership", title: "Leadership", canonicalSlug: "leadership",
                       description: "Servant leadership, pastoral care, and ministry building.",
                       icon: "star.circle.fill", iconColor: .orange, backgroundColor: Color.orange.opacity(0.08),
                       postCount: 0, trendScore: 0, isTrending: false, isFollowedByUser: false,
                       relatedScripture: "Mark 10:45", safetyState: .approved),
    ]
}

// MARK: - Church Discovery Model

struct DiscoveryChurch: Identifiable, Equatable {
    let id: String
    let name: String
    let denomination: String?
    let city: String
    let state: String
    let nextServiceTime: String?
    let imageURL: String?
    let tags: [String]          // "young adults", "expository", "worship-led"
    var distanceMiles: Double?
    var isVerified: Bool
}

// MARK: - Church Note / Resource Discovery Models

struct DiscoveryNote: Identifiable, Equatable {
    let id: String
    let title: String
    let speakerName: String?
    let churchName: String?
    let scriptureReference: String?
    let summary: String
    let createdAt: Date
    let tags: [String]
}

struct DiscoveryResource: Identifiable, Equatable {
    let id: String
    let title: String
    let type: String            // "book", "guide", "devotional", "course"
    let description: String
    let thumbnailURL: String?
    let tags: [String]
}

// MARK: - Job Discovery Model

struct DiscoveryJob: Identifiable, Equatable {
    let id: String
    let title: String
    let employerName: String
    let employerLogoURL: String?
    let jobType: String          // e.g. "Full-Time"
    let arrangement: String      // e.g. "Remote"
    let location: String?
    let salaryRange: String?
    let isVerifiedEmployer: Bool
    let classification: String   // e.g. "Church Ministry"
}

// MARK: - Trending Discussion Model

struct DiscoveryTrend: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String         // AI-generated, calm and neutral
    let discussionCount: Int    // total posts in this trend window
    let uniqueAuthors: Int
    let trendScore: Double      // 0–100
    let safetyStatus: TrendSafetyStatus
    let thumbnailURL: String?
    let createdAt: Date
    var topTopics: [String]     // associated topic slugs

    enum TrendSafetyStatus: String {
        case approved           // cleared for display
        case contextRequired    // shown with context label
        case restricted         // only shown in topic page, not broad discovery
        case blocked            // removed entirely
    }
}

// MARK: - Recent Search Item

struct RecentSearchItem: Identifiable, Codable, Equatable {
    let id: String
    let query: String
    let type: RecentSearchType
    let timestamp: Date
    var displayName: String?    // for person/church results
    var avatarURL: String?

    enum RecentSearchType: String, Codable {
        case query, person, topic, church, post
    }
}

// MARK: - Search State Machine

enum DiscoverySearchState: Equatable {
    case landing            // empty search bar — show discovery modules
    case typing(String)     // user is typing — show live suggestions
    case results(String)    // search submitted — show full results
    case topicPage(DiscoveryTopic)  // tapped a topic chip
}

// MARK: - Search Tab

enum DiscoverySearchTab: String, CaseIterable, Identifiable {
    case top = "Top"
    case people = "People"
    case posts = "Posts"
    case topics = "Topics"
    case churches = "Churches"
    case notes = "Notes"

    var id: String { rawValue }
}

// MARK: - Typeahead Suggestion

struct TypeaheadSuggestion: Identifiable, Equatable {
    let id: String
    let text: String
    let type: SuggestionType
    var subtitle: String?
    var avatarURL: String?

    enum SuggestionType {
        case recentSearch
        case queryCompletion
        case person
        case topic
        case church
        case scripture
    }

    var icon: String {
        switch type {
        case .recentSearch: return "clock"
        case .queryCompletion: return "magnifyingglass"
        case .person: return "person.circle"
        case .topic: return "tag"
        case .church: return "building.columns"
        case .scripture: return "book"
        }
    }
}

// MARK: - Follow Suggestion

struct FollowSuggestion: Identifiable, Equatable {
    let id: String          // userId
    let person: DiscoveryPerson
    let reason: String      // "Posts church notes on Proverbs"
    var isFollowing: Bool
}

// MARK: - Discovery Query Intent Classification

enum DiscoveryQueryIntent: Equatable {
    case person             // "jackie hill perry"
    case topic              // "marriage", "anxiety prayer"
    case church             // "elevation church", "church near me"
    case scripture          // "proverbs 3", "john 3:16"
    case resource           // "sermon on fasting"
    case local              // "church in austin"
    case ambiguous          // multiple intents
}

// MARK: - Safety Score Threshold Constants

enum DiscoverySafetyThresholds {
    static let minimumSafetyScore: Double = 40    // Items below this suppressed entirely
    static let deRankThreshold: Double = 60       // Items below this de-ranked (shown last)
    static let safeForBroadDiscovery: Double = 75 // Items must exceed this for trending/recommendations
}
