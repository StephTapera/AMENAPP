//
//  DiscoverModels.swift
//  AMENAPP
//
//  Data models for the Discover/Search system
//

import Foundation
import SwiftUI

// MARK: - Search Scope

enum DiscoverFilterScope: String, CaseIterable, Identifiable, Hashable {
    case all = "All"
    case people = "People"
    case posts = "Posts"
    case churches = "Churches"
    case videos = "Videos"
    case news = "News"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "sparkles"
        case .people: return "person.2"
        case .posts: return "text.bubble"
        case .churches: return "building.2"
        case .videos: return "play.rectangle"
        case .news: return "newspaper"
        }
    }
}

// MARK: - Discovery Person

struct DiscoverSearchPerson: Identifiable, Codable, Hashable, Equatable {
    let id: String
    let displayName: String
    let username: String
    let avatarURL: String?
    let bio: String?
    let followerCount: Int
    let followingCount: Int
    let mutualFollowerCount: Int
    let isVerified: Bool
    let isPrivate: Bool
    var isFollowing: Bool
    let churchName: String?
    let location: String?
    let topicAffinities: [String]?
    let badges: [String]?
    let joinedDate: Date?
    
    // For preview posts
    let recentPostCount: Int
    
    init(
        id: String,
        displayName: String,
        username: String,
        avatarURL: String? = nil,
        bio: String? = nil,
        followerCount: Int = 0,
        followingCount: Int = 0,
        mutualFollowerCount: Int = 0,
        isVerified: Bool = false,
        isPrivate: Bool = false,
        isFollowing: Bool = false,
        churchName: String? = nil,
        location: String? = nil,
        topicAffinities: [String]? = nil,
        badges: [String]? = nil,
        joinedDate: Date? = nil,
        recentPostCount: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.avatarURL = avatarURL
        self.bio = bio
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.mutualFollowerCount = mutualFollowerCount
        self.isVerified = isVerified
        self.isPrivate = isPrivate
        self.isFollowing = isFollowing
        self.churchName = churchName
        self.location = location
        self.topicAffinities = topicAffinities
        self.badges = badges
        self.joinedDate = joinedDate
        self.recentPostCount = recentPostCount
    }
}

// MARK: - Discovery Post

struct DiscoverFeedPost: Identifiable, Codable, Hashable, Equatable {
    let id: String
    let authorId: String
    let authorName: String
    let authorUsername: String
    let authorAvatarURL: String?
    let content: String
    let imageURL: String?
    let videoURL: String?
    let category: PostCategory
    let timestamp: Date
    let likeCount: Int
    let commentCount: Int
    let shareCount: Int
    let saveCount: Int
    let isVersePost: Bool
    let verseReference: String?
    let topicTags: [String]?
    var isLiked: Bool
    var isSaved: Bool
    
    enum PostCategory: String, Codable {
        case prayer = "prayer"
        case testimony = "testimony"
        case verse = "verse"
        case discussion = "discussion"
        case churchNote = "church_note"
        case general = "general"
    }
    
    init(
        id: String,
        authorId: String,
        authorName: String,
        authorUsername: String,
        authorAvatarURL: String? = nil,
        content: String,
        imageURL: String? = nil,
        videoURL: String? = nil,
        category: PostCategory = .general,
        timestamp: Date = Date(),
        likeCount: Int = 0,
        commentCount: Int = 0,
        shareCount: Int = 0,
        saveCount: Int = 0,
        isVersePost: Bool = false,
        verseReference: String? = nil,
        topicTags: [String]? = nil,
        isLiked: Bool = false,
        isSaved: Bool = false
    ) {
        self.id = id
        self.authorId = authorId
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.authorAvatarURL = authorAvatarURL
        self.content = content
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.category = category
        self.timestamp = timestamp
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.shareCount = shareCount
        self.saveCount = saveCount
        self.isVersePost = isVersePost
        self.verseReference = verseReference
        self.topicTags = topicTags
        self.isLiked = isLiked
        self.isSaved = isSaved
    }
}

// MARK: - Discover Pill Item

struct DiscoverPillItem: Identifiable, Hashable, Equatable {
    let id: String
    let title: String
    let systemImage: String?
    var isActive: Bool
    let count: Int?
    let filterType: FilterType
    let action: () -> Void
    
    enum FilterType: Hashable {
        case topic(String)
        case category(String)
        case scope(DiscoverFilterScope)
        case custom(String)
    }
    
    init(
        id: String,
        title: String,
        systemImage: String? = nil,
        isActive: Bool = false,
        count: Int? = nil,
        filterType: FilterType,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isActive = isActive
        self.count = count
        self.filterType = filterType
        self.action = action
    }
    
    static func == (lhs: DiscoverPillItem, rhs: DiscoverPillItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.systemImage == rhs.systemImage &&
        lhs.isActive == rhs.isActive &&
        lhs.count == rhs.count
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(systemImage)
        hasher.combine(isActive)
        hasher.combine(count)
    }
}

// MARK: - Daily Verse Data

struct DiscoverDailyVerseData: Identifiable, Codable, Hashable, Equatable {
    let id: String
    let text: String
    let reference: String
    let translation: String
    let testament: String
    let book: String
    let chapter: Int
    let verse: Int
    let theme: String?
    let devotional: String?
    let imageURL: String?
    let accentColor: String?
    let discussionCount: Int
    let saveCount: Int
    let shareCount: Int
    let date: Date
    
    init(
        id: String,
        text: String,
        reference: String,
        translation: String = "KJV", // TODO(legal): was ESV (Crossway, copyrighted) — changed to KJV per AMEN-CONTENT-001
        testament: String,
        book: String,
        chapter: Int,
        verse: Int,
        theme: String? = nil,
        devotional: String? = nil,
        imageURL: String? = nil,
        accentColor: String? = nil,
        discussionCount: Int = 0,
        saveCount: Int = 0,
        shareCount: Int = 0,
        date: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.reference = reference
        self.translation = translation
        self.testament = testament
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.theme = theme
        self.devotional = devotional
        self.imageURL = imageURL
        self.accentColor = accentColor
        self.discussionCount = discussionCount
        self.saveCount = saveCount
        self.shareCount = shareCount
        self.date = date
    }
}

// MARK: - News Item

struct DiscoverNewsItem: Identifiable, Codable, Hashable, Equatable {
    let id: String
    let headline: String
    let summary: String
    let thumbnailURL: String?
    let source: String
    let category: NewsCategory
    let publishedDate: Date
    let articleURL: String
    let readTimeMinutes: Int?
    
    enum NewsCategory: String, Codable {
        case faith = "Faith"
        case church = "Church"
        case global = "Global"
        case ministry = "Ministry"
        case culture = "Culture"
        case general = "General"
    }
    
    init(
        id: String,
        headline: String,
        summary: String,
        thumbnailURL: String? = nil,
        source: String,
        category: NewsCategory = .general,
        publishedDate: Date = Date(),
        articleURL: String,
        readTimeMinutes: Int? = nil
    ) {
        self.id = id
        self.headline = headline
        self.summary = summary
        self.thumbnailURL = thumbnailURL
        self.source = source
        self.category = category
        self.publishedDate = publishedDate
        self.articleURL = articleURL
        self.readTimeMinutes = readTimeMinutes
    }
}

// MARK: - Video Item

struct DiscoverVideoItem: Identifiable, Codable, Hashable, Equatable {
    let id: String
    let title: String
    let creator: String
    let creatorAvatarURL: String?
    let thumbnailURL: String?
    let duration: TimeInterval
    let category: VideoCategory
    let viewCount: Int
    let uploadDate: Date
    let videoURL: String
    let isLive: Bool
    
    enum VideoCategory: String, Codable {
        case sermon = "Sermon"
        case worship = "Worship"
        case teaching = "Teaching"
        case testimony = "Testimony"
        case prayer = "Prayer"
        case general = "General"
    }
    
    var durationFormatted: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    init(
        id: String,
        title: String,
        creator: String,
        creatorAvatarURL: String? = nil,
        thumbnailURL: String? = nil,
        duration: TimeInterval = 0,
        category: VideoCategory = .general,
        viewCount: Int = 0,
        uploadDate: Date = Date(),
        videoURL: String,
        isLive: Bool = false
    ) {
        self.id = id
        self.title = title
        self.creator = creator
        self.creatorAvatarURL = creatorAvatarURL
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.category = category
        self.viewCount = viewCount
        self.uploadDate = uploadDate
        self.videoURL = videoURL
        self.isLive = isLive
    }
}
