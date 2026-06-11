// AmenPulseDigestService.swift
// AMENAPP/MusicContentLayer/
// Pulse digest data models and service for the AMEN app.

import SwiftUI

// MARK: - Item Type

enum AmenPulseDigestItemType: String, Codable, Sendable, CaseIterable {
    case newMusic
    case newSermon
    case churchNote
    case savedPost
    case unreadComment
    case prayerUpdate
    case upcomingEvent
    case listeningRoom
    case communityActivity
    case recommendedContent
    case trendingWorship

    var displayName: String {
        switch self {
        case .newMusic:           return "New Music"
        case .newSermon:          return "New Sermon"
        case .churchNote:         return "Church Note"
        case .savedPost:          return "Saved Post"
        case .unreadComment:      return "Unread Comment"
        case .prayerUpdate:       return "Prayer Update"
        case .upcomingEvent:      return "Upcoming Event"
        case .listeningRoom:      return "Listening Room"
        case .communityActivity:  return "Community Activity"
        case .recommendedContent: return "Recommended"
        case .trendingWorship:    return "Trending Worship"
        }
    }

    var sfSymbol: String {
        switch self {
        case .newMusic:           return "music.note"
        case .newSermon:          return "book.fill"
        case .churchNote:         return "note.text"
        case .savedPost:          return "bookmark.fill"
        case .unreadComment:      return "bubble.left.fill"
        case .prayerUpdate:       return "hands.sparkles.fill"
        case .upcomingEvent:      return "calendar"
        case .listeningRoom:      return "waveform.circle.fill"
        case .communityActivity:  return "person.3.fill"
        case .recommendedContent: return "sparkles"
        case .trendingWorship:    return "flame.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .newMusic:           return Color(red: 0.38, green: 0.52, blue: 0.88)
        case .newSermon:          return Color(red: 0.55, green: 0.38, blue: 0.80)
        case .churchNote:         return Color(red: 0.30, green: 0.65, blue: 0.55)
        case .savedPost:          return Color(red: 0.80, green: 0.60, blue: 0.20)
        case .unreadComment:      return Color(red: 0.50, green: 0.72, blue: 0.88)
        case .prayerUpdate:       return Color(red: 0.70, green: 0.42, blue: 0.75)
        case .upcomingEvent:      return Color(red: 0.25, green: 0.72, blue: 0.45)
        case .listeningRoom:      return Color(red: 0.88, green: 0.45, blue: 0.35)
        case .communityActivity:  return Color(red: 0.40, green: 0.65, blue: 0.78)
        case .recommendedContent: return Color(red: 0.78, green: 0.55, blue: 0.35)
        case .trendingWorship:    return Color(red: 0.88, green: 0.35, blue: 0.45)
        }
    }
}

// MARK: - Item

struct AmenPulseDigestItem: Codable, Sendable, Identifiable {
    let id: String
    let type: AmenPulseDigestItemType
    let title: String
    let summary: String
    let sourceLabel: String
    let artworkURL: URL?
    let deepLink: String
    let reasonLabel: String
    var isSaved: Bool
    let isMuted: Bool
    let rightsPolicy: String
    let publishedAt: String
}

// MARK: - Digest Type

enum AmenPulseDigestType: String, Codable, Sendable {
    case daily
    case weekly
    case churchSpecific
    case communitySpecific
    case musicRelease
    case sermonRecap
    case prayerUpdate
}

// MARK: - Section

struct AmenPulseDigestSection: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let items: [AmenPulseDigestItem]
    let isExpanded: Bool
}

// MARK: - Digest

struct AmenPulseDigest: Codable, Sendable, Identifiable {
    let id: String
    let generatedAt: String
    let digestType: AmenPulseDigestType
    let greeting: String
    let sections: [AmenPulseDigestSection]
    let totalItemCount: Int
}

// MARK: - Service

@MainActor final class AmenPulseDigestService: ObservableObject {
    @Published private(set) var currentDigest: AmenPulseDigest?
    @Published private(set) var isLoading = false
    @Published private(set) var mutedSources: Set<String> = []
    @Published private(set) var mutedTopics: Set<String> = []

    func loadDailyDigest() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        try? await Task.sleep(nanoseconds: 600_000_000) // 600ms

        let churchesSection = AmenPulseDigestSection(
            id: "section-churches",
            title: "New from Your Churches",
            items: [
                AmenPulseDigestItem(
                    id: "item-nm-1",
                    type: .newMusic,
                    title: "Graves Into Gardens (Live)",
                    summary: "A new live worship recording from Sunday's service, featuring the full worship team.",
                    sourceLabel: "Elevation Church",
                    artworkURL: URL(string: "https://picsum.photos/seed/nm1/200"),
                    deepLink: "amen://music/graves-into-gardens-live",
                    reasonLabel: "You follow Elevation Church and listen to their worship releases.",
                    isSaved: false,
                    isMuted: false,
                    rightsPolicy: "free",
                    publishedAt: "2026-06-10T08:00:00Z"
                ),
                AmenPulseDigestItem(
                    id: "item-nm-2",
                    type: .newMusic,
                    title: "Emmanuel (God With Us) — Single",
                    summary: "New original worship single released this morning by Bethel Music.",
                    sourceLabel: "Bethel Music",
                    artworkURL: URL(string: "https://picsum.photos/seed/nm2/200"),
                    deepLink: "amen://music/emmanuel-bethel",
                    reasonLabel: "Bethel Music is in your top followed artists this month.",
                    isSaved: false,
                    isMuted: false,
                    rightsPolicy: "free",
                    publishedAt: "2026-06-10T07:30:00Z"
                ),
                AmenPulseDigestItem(
                    id: "item-ser-1",
                    type: .newSermon,
                    title: "Walking in Purpose — Week 3",
                    summary: "Pastor Mike continues the series on discovering God's call for your season of life.",
                    sourceLabel: "Life Church",
                    artworkURL: URL(string: "https://picsum.photos/seed/ser1/200"),
                    deepLink: "amen://sermon/walking-in-purpose-w3",
                    reasonLabel: "You watched weeks 1 and 2 of this series.",
                    isSaved: false,
                    isMuted: false,
                    rightsPolicy: "free",
                    publishedAt: "2026-06-10T06:00:00Z"
                )
            ],
            isExpanded: true
        )

        let prayerSection = AmenPulseDigestSection(
            id: "section-prayer",
            title: "Prayer Updates",
            items: [
                AmenPulseDigestItem(
                    id: "item-pu-1",
                    type: .prayerUpdate,
                    title: "Marcus's Surgery — Answered Prayer",
                    summary: "Marcus shared that his surgery went well and he's recovering at home. The community rejoiced with him.",
                    sourceLabel: "Your Community",
                    artworkURL: nil,
                    deepLink: "amen://prayer/marcus-surgery-update",
                    reasonLabel: "You prayed for Marcus three days ago.",
                    isSaved: false,
                    isMuted: false,
                    rightsPolicy: "membersOnly",
                    publishedAt: "2026-06-10T05:45:00Z"
                ),
                AmenPulseDigestItem(
                    id: "item-pu-2",
                    type: .prayerUpdate,
                    title: "Community Fast — Day 3 Reflection",
                    summary: "The 7-day fast your church group is participating in has reached day 3. Here's today's reflection.",
                    sourceLabel: "Crossroads Bible Church",
                    artworkURL: nil,
                    deepLink: "amen://prayer/community-fast-day3",
                    reasonLabel: "You joined the community fast event last Sunday.",
                    isSaved: false,
                    isMuted: false,
                    rightsPolicy: "membersOnly",
                    publishedAt: "2026-06-10T07:00:00Z"
                )
            ],
            isExpanded: true
        )

        let communitySection = AmenPulseDigestSection(
            id: "section-community",
            title: "Community Activity",
            items: [
                AmenPulseDigestItem(
                    id: "item-ca-1",
                    type: .communityActivity,
                    title: "Jordan and 14 others reacted to your post",
                    summary: "Your post about the worship night last Friday has been getting a lot of love from your community.",
                    sourceLabel: "Your Community",
                    artworkURL: nil,
                    deepLink: "amen://post/worship-night-friday",
                    reasonLabel: "This is activity on a post you shared.",
                    isSaved: false,
                    isMuted: false,
                    rightsPolicy: "free",
                    publishedAt: "2026-06-10T09:15:00Z"
                ),
                AmenPulseDigestItem(
                    id: "item-ca-2",
                    type: .communityActivity,
                    title: "New discussion in Faith & Doubt Circle",
                    summary: "A thoughtful conversation started about navigating seasons of spiritual dryness.",
                    sourceLabel: "Faith & Doubt Circle",
                    artworkURL: nil,
                    deepLink: "amen://spaces/faith-doubt-discussion",
                    reasonLabel: "You are a member of Faith & Doubt Circle.",
                    isSaved: false,
                    isMuted: false,
                    rightsPolicy: "free",
                    publishedAt: "2026-06-10T08:45:00Z"
                )
            ],
            isExpanded: false
        )

        let recommendedSection = AmenPulseDigestSection(
            id: "section-recommended",
            title: "Recommended for You",
            items: [
                AmenPulseDigestItem(
                    id: "item-rc-1",
                    type: .recommendedContent,
                    title: "Worship Playlist: Monday Morning Reset",
                    summary: "A curated 30-minute playlist to start your week grounded in worship and prayer.",
                    sourceLabel: "AMEN Curation",
                    artworkURL: URL(string: "https://picsum.photos/seed/rc1/200"),
                    deepLink: "amen://playlist/monday-morning-reset",
                    reasonLabel: "You often listen to worship music on Monday mornings.",
                    isSaved: false,
                    isMuted: false,
                    rightsPolicy: "free",
                    publishedAt: "2026-06-10T06:30:00Z"
                ),
                AmenPulseDigestItem(
                    id: "item-rc-2",
                    type: .recommendedContent,
                    title: "Podcast: The Practice of Sabbath",
                    summary: "A 22-minute episode exploring what it means to truly rest in a productivity-obsessed culture.",
                    sourceLabel: "The Good Table Podcast",
                    artworkURL: URL(string: "https://picsum.photos/seed/rc2/200"),
                    deepLink: "amen://podcast/practice-of-sabbath",
                    reasonLabel: "Based on your interest in Sabbath Mode and spiritual rest topics.",
                    isSaved: false,
                    isMuted: false,
                    rightsPolicy: "free",
                    publishedAt: "2026-06-09T14:00:00Z"
                )
            ],
            isExpanded: false
        )

        let allSections = [churchesSection, prayerSection, communitySection, recommendedSection]
        let totalCount = allSections.reduce(0) { $0 + $1.items.count }

        currentDigest = AmenPulseDigest(
            id: "digest-\(Date().timeIntervalSince1970)",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            digestType: .daily,
            greeting: "Good morning, here's what's new in your faith community today.",
            sections: allSections,
            totalItemCount: totalCount
        )
    }

    func muteSource(_ sourceLabel: String) {
        mutedSources.insert(sourceLabel)
        guard let digest = currentDigest else { return }
        let filteredSections = digest.sections.map { section in
            let filteredItems = section.items.filter { $0.sourceLabel != sourceLabel }
            return AmenPulseDigestSection(
                id: section.id,
                title: section.title,
                items: filteredItems,
                isExpanded: section.isExpanded
            )
        }
        let totalCount = filteredSections.reduce(0) { $0 + $1.items.count }
        currentDigest = AmenPulseDigest(
            id: digest.id,
            generatedAt: digest.generatedAt,
            digestType: digest.digestType,
            greeting: digest.greeting,
            sections: filteredSections,
            totalItemCount: totalCount
        )
    }

    func muteTopic(_ topic: String) {
        mutedTopics.insert(topic)
    }

    func saveItem(_ itemID: String) async {
        guard let digest = currentDigest else { return }
        let updatedSections = digest.sections.map { section in
            let updatedItems = section.items.map { item -> AmenPulseDigestItem in
                guard item.id == itemID else { return item }
                return AmenPulseDigestItem(
                    id: item.id,
                    type: item.type,
                    title: item.title,
                    summary: item.summary,
                    sourceLabel: item.sourceLabel,
                    artworkURL: item.artworkURL,
                    deepLink: item.deepLink,
                    reasonLabel: item.reasonLabel,
                    isSaved: true,
                    isMuted: item.isMuted,
                    rightsPolicy: item.rightsPolicy,
                    publishedAt: item.publishedAt
                )
            }
            return AmenPulseDigestSection(
                id: section.id,
                title: section.title,
                items: updatedItems,
                isExpanded: section.isExpanded
            )
        }
        currentDigest = AmenPulseDigest(
            id: digest.id,
            generatedAt: digest.generatedAt,
            digestType: digest.digestType,
            greeting: digest.greeting,
            sections: updatedSections,
            totalItemCount: digest.totalItemCount
        )
    }

    func refreshDigest() async {
        currentDigest = nil
        await loadDailyDigest()
    }
}
