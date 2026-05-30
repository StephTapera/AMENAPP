// ComposerContract.swift
// Shared types for the AMEN composer, custom feeds, search/discover, reply system,
// and music lyric card. ALL agent-written modules import only this file for shared types.
// Never re-declare these types in agent files.
//
// Naming note: existing codebase already defines PostDraft (DraftsManager.swift)
// and FeedItem (FeedItem.swift) — this file uses ComposerDraft and CustomFeedSlot instead.

import Foundation
import SwiftUI

// MARK: - ComposerDraft (rich in-flight draft, supersedes the lightweight PostDraft)

struct ComposerDraft: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String = ""
    var richSpans: [ComposerRichSpan] = []
    var attachments: [ComposerAttachment] = []
    var audience: ComposerAudience = .everyone
    var replyPolicy: ComposerReplyPolicy = .anyone
    var reviewAndApproveReplies: Bool = false
    var crossPostDestinations: [CrossPostDestination] = []
    var taggedCommunity: CommunityTag? = nil
    var scriptureRefs: [ComposerScriptureRef] = []
    var postType: ComposerPostType = .standard
    var isAnonymousPrayer: Bool = false
    var musicTrack: MusicTrack? = nil
    var scheduledAt: Date? = nil       // set → post queued; nil → publish immediately
    var savedAt: Date = Date()

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }
}

// MARK: - ComposerAttachment (struct with kind discriminator, fully Codable)

struct ComposerAttachment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: ComposerAttachmentKind
    var photo: ComposerPhotoAttachment?
    var video: ComposerVideoAttachment?
    var gif: ComposerGIFAttachment?
    var sticker: ComposerStickerAttachment?
    var music: MusicTrack?
    var verseCard: ComposerVerseCard?
    var poll: ComposerPollAttachment?
    var richText: ComposerRichTextAttachment?

    static func photo(_ p: ComposerPhotoAttachment) -> ComposerAttachment {
        ComposerAttachment(id: p.id, kind: .photo, photo: p)
    }
    static func video(_ v: ComposerVideoAttachment) -> ComposerAttachment {
        ComposerAttachment(id: v.id, kind: .video, video: v)
    }
    static func gif(_ g: ComposerGIFAttachment) -> ComposerAttachment {
        ComposerAttachment(id: g.id, kind: .gif, gif: g)
    }
    static func sticker(_ s: ComposerStickerAttachment) -> ComposerAttachment {
        ComposerAttachment(id: s.id, kind: .sticker, sticker: s)
    }
    static func music(_ m: MusicTrack) -> ComposerAttachment {
        ComposerAttachment(id: m.id, kind: .music, music: m)
    }
    static func verseCard(_ v: ComposerVerseCard) -> ComposerAttachment {
        ComposerAttachment(id: v.id, kind: .verseCard, verseCard: v)
    }
    static func poll(_ p: ComposerPollAttachment) -> ComposerAttachment {
        ComposerAttachment(id: p.id, kind: .poll, poll: p)
    }
    static func richText(_ r: ComposerRichTextAttachment) -> ComposerAttachment {
        ComposerAttachment(id: r.id, kind: .richText, richText: r)
    }
}

enum ComposerAttachmentKind: String, Codable, CaseIterable {
    case photo, video, gif, sticker, music, verseCard, poll, richText
}

// MARK: - Attachment subtypes

struct ComposerPhotoAttachment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var localURL: URL?
    var remoteURL: String?
    var altText: String = ""
    var sortOrder: Int = 0
}

struct ComposerVideoAttachment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var localURL: URL?
    var remoteURL: String?
    var thumbnailURL: String?
    var durationSeconds: Double = 0
    var sortOrder: Int = 0
}

struct ComposerGIFAttachment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var giphyId: String = ""
    var url: String = ""
    var previewURL: String? = nil
    var title: String? = nil
}

struct ComposerStickerAttachment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var stickerId: String = ""
    var url: String = ""
    var category: String = ""
    var packId: String = ""
}

struct ComposerVerseCard: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var reference: String = ""
    var text: String = ""
    var translation: String = "NIV"
    var book: String = ""
    var chapter: Int = 0
    var verse: Int = 0
    var endVerse: Int? = nil
}

struct ComposerPollAttachment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var question: String = ""
    var options: [String] = ["", ""]
    var durationHours: Int = 24
}

struct ComposerRichTextAttachment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String = ""
    var richSpans: [ComposerRichSpan] = []
}

// MARK: - Rich text spans

struct ComposerRichSpan: Codable, Equatable {
    var location: Int
    var length: Int
    var style: ComposerRichSpanStyle
}

enum ComposerRichSpanStyle: String, Codable, CaseIterable {
    case bold, italic, underline, strikethrough, highlight

    var toolbarSymbol: String {
        switch self {
        case .bold:          return "bold"
        case .italic:        return "italic"
        case .underline:     return "underline"
        case .strikethrough: return "strikethrough"
        case .highlight:     return "highlighter"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .bold:          return "Bold"
        case .italic:        return "Italic"
        case .underline:     return "Underline"
        case .strikethrough: return "Strikethrough"
        case .highlight:     return "Highlight"
        }
    }
}

// MARK: - Music track

struct MusicTrack: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var artists: [String] = []
    var albumArtURL: String? = nil
    var previewURL: String? = nil
    var fullURL: String? = nil
    var syncedLyrics: [SyncedLyricLine] = []
    var durationMs: Int = 0
    var provider: MusicTrackProvider = .appleMusic
    var externalId: String? = nil

    var artistsDisplay: String { artists.joined(separator: ", ") }
    var hasLyrics: Bool { !syncedLyrics.isEmpty }
}

struct SyncedLyricLine: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var startTimeMs: Int = 0
    var endTimeMs: Int = 0
    var text: String = ""
}

enum MusicTrackProvider: String, Codable, CaseIterable {
    case appleMusic, spotify, youtube, other
}

// MARK: - Audience & reply policy

enum ComposerAudience: String, Codable, CaseIterable {
    case everyone, followers, community

    var displayName: String {
        switch self {
        case .everyone:   return "Everyone"
        case .followers:  return "Followers"
        case .community:  return "Community"
        }
    }
    var icon: String {
        switch self {
        case .everyone:   return "globe"
        case .followers:  return "person.2.fill"
        case .community:  return "building.columns.fill"
        }
    }
}

enum ComposerReplyPolicy: String, Codable, CaseIterable {
    case anyone, followers, profilesYouFollow, profilesYouMention

    var displayName: String {
        switch self {
        case .anyone:               return "Anyone"
        case .followers:            return "Your followers"
        case .profilesYouFollow:    return "Profiles you follow"
        case .profilesYouMention:   return "Profiles you mention"
        }
    }
    var icon: String {
        switch self {
        case .anyone:               return "globe"
        case .followers:            return "person.2.fill"
        case .profilesYouFollow:    return "arrow.left.arrow.right"
        case .profilesYouMention:   return "at"
        }
    }
    var postReplyPermissionRaw: String {
        switch self {
        case .anyone:               return "everyone"
        case .followers:            return "followers"
        case .profilesYouFollow:    return "mutuals"
        case .profilesYouMention:   return "mentioned"
        }
    }
}

struct CrossPostDestination: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var isEnabled: Bool = false
    var iconName: String = ""
}

// MARK: - Community / topic tag

struct CommunityTag: Codable, Equatable {
    var id: String = ""
    var name: String = ""
    var type: CommunityTagType = .topic
}

enum CommunityTagType: String, Codable {
    case community, topic
}

// MARK: - Post type

enum ComposerPostType: String, Codable, CaseIterable {
    case standard
    case prayerRequest
    case testimony
    case churchNote

    var displayName: String {
        switch self {
        case .standard:       return "Standard"
        case .prayerRequest:  return "Prayer Request"
        case .testimony:      return "Testimony"
        case .churchNote:     return "Church Note"
        }
    }
    var icon: String {
        switch self {
        case .standard:       return "bubble.left.and.bubble.right.fill"
        case .prayerRequest:  return "hands.sparkles.fill"
        case .testimony:      return "star.bubble.fill"
        case .churchNote:     return "doc.text.fill"
        }
    }
    var tintColor: Color {
        switch self {
        case .standard:       return AmenTheme.Colors.amenBlue
        case .prayerRequest:  return .blue
        case .testimony:      return AmenTheme.Colors.amenGold
        case .churchNote:     return AmenTheme.Colors.amenPurple
        }
    }
    var showsAnonymousToggle: Bool { self == .prayerRequest }
    var postCategoryRaw: String {
        switch self {
        case .standard, .churchNote: return "openTable"
        case .prayerRequest:         return "prayer"
        case .testimony:             return "testimonies"
        }
    }
}

// MARK: - Composer scripture reference

struct ComposerScriptureRef: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var reference: String = ""
    var text: String = ""
    var translation: String = "NIV"
    var rangeLocation: Int? = nil
    var rangeLength: Int? = nil
}

// MARK: - ComposerAttachmentProvider protocol

@MainActor
protocol ComposerAttachmentProvider: AnyObject {
    var pendingAttachment: ComposerAttachment? { get }
    func reset()
}

// MARK: - Custom feeds

struct CustomFeedConfig: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var firestoreId: String? = nil
    var name: String = ""
    var feedDescription: String = ""
    var isPublic: Bool = false
    var profileIds: [String] = []
    var topicIds: [String] = []
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var ownerId: String = ""
    var isBuiltIn: Bool = false

    static func defaultFeeds(ownerId: String) -> [CustomFeedConfig] {
        let specs: [(String, String, Bool, Int)] = [
            ("For You",      "Personalized for your walk",         false, 0),
            ("Following",    "From people you follow",              false, 1),
            ("Prayer",       "Prayer requests and answered prayer", true,  2),
            ("Testimonies",  "Stories of God's faithfulness",       true,  3),
            ("Scripture",    "Verse reflections and study",         true,  4),
            ("Your Church",  "From your church community",          false, 5),
        ]
        return specs.map { name, desc, pub, order in
            CustomFeedConfig(
                id: UUID(), firestoreId: nil,
                name: name, feedDescription: desc,
                isPublic: pub, sortOrder: order,
                ownerId: ownerId, isBuiltIn: true
            )
        }
    }
}

struct CustomFeedSlot: Identifiable {
    var id: String
    var postId: String
    var feedId: String
    var score: Double = 0
}

// MARK: - Reply node (threaded reply tree)

struct ReplyNode: Identifiable {
    var id: String
    var postId: String
    var parentId: String?
    var rootPostId: String
    var authorId: String
    var authorName: String
    var authorUsername: String?
    var authorProfileImageURL: String?
    var authorInitials: String
    var content: String
    var createdAt: Date
    var likeCount: Int = 0
    var replyCount: Int = 0
    var depth: Int = 0
    var children: [ReplyNode] = []
    var sortKey: Double = 0
}

// MARK: - Discover topic (renamed from TrendingTopic to avoid clash with ModelsTrendingTopic.TrendingTopic visual pill model)

struct DiscoverTopic: Identifiable {
    var id: String
    var key: String
    var displayName: String
    var postCount: Int
    var aiSummary: String?
    var thumbnailURL: String?
    var isFollowing: Bool = false
}

// MARK: - Berean AI response types

struct BereanRefineResult {
    var refined: String
    var diff: String
    var mode: BereanRefineMode
}

enum BereanRefineMode: String, Codable, CaseIterable {
    case tighten, addVerse, softenTone

    var displayName: String {
        switch self {
        case .tighten:    return "Tighten wording"
        case .addVerse:   return "Add a verse"
        case .softenTone: return "Soften tone"
        }
    }
    var icon: String {
        switch self {
        case .tighten:    return "scissors"
        case .addVerse:   return "book.fill"
        case .softenTone: return "heart.fill"
        }
    }
}

struct BereanConvictionResult {
    var hasConcerns: Bool
    var suggestion: String?
    var tone: String
}

struct BereanTopicSuggestion: Identifiable {
    var id: String
    var name: String
    var communityId: String?
}
