// AmenMediaModels.swift
// AMENAPP
//
// Universal media attachment data model for the AMEN post composer system.
// All types are Codable and Sendable-safe. Old FirestorePost documents that
// lack the mediaAttachments field will decode it as nil — fully additive.
//
// Usage:
//   let attachment = AmenMediaAttachment(id: UUID().uuidString, kind: .music, ...)
//   var draft = AmenPostDraft(...)
//   draft.mediaAttachments.append(attachment)

import Foundation

// MARK: - Media Kind

/// Top-level discriminator for the type of media attached to a post.
enum AmenMediaKind: String, Codable, Sendable {
    case music
    case podcast
    case video
    case article
    case book
    case product
    case scripture
    case link
}

// MARK: - Universal Attachment Envelope

/// A fully self-describing media attachment that can accompany any AMEN post.
/// One envelope covers all eight media kinds; only the relevant detail payload
/// is non-nil, keeping Firestore documents compact for older content types.
struct AmenMediaAttachment: Codable, Identifiable, Equatable, Sendable {

    // MARK: Core identity

    let id: String
    let kind: AmenMediaKind

    // MARK: Universal display fields

    /// Canonical source URL (web page, streaming link, or deep link).
    let sourceURL: String?

    /// Primary display title: track name, episode title, headline, book title, etc.
    let title: String

    /// Secondary display line: artist, show name, author, publication, merchant.
    let subtitle: String?

    /// Square or portrait thumbnail/cover art URL.
    let thumbnailURL: String?

    /// Optional accent color as a six-character hex string (e.g. "D4A017").
    /// Used by card views to tint backgrounds and progress rings.
    let accentHex: String?

    // MARK: Playback

    /// Present when the attachment has a playable audio or video stream.
    var playable: AmenPlayableInfo? = nil

    // MARK: Timeline (lyrics / chapters / captions)

    /// Present when the attachment carries timed text (lyrics, chapters, transcript).
    var timeline: AmenMediaTimeline? = nil

    // MARK: Kind-specific detail payloads (at most one will be non-nil)

    var musicDetails: AmenMusicDetails? = nil
    var podcastDetails: AmenPodcastDetails? = nil
    var videoDetails: AmenVideoDetails? = nil
    var articleDetails: AmenArticleDetails? = nil
    var bookDetails: AmenBookDetails? = nil
    var productDetails: AmenProductDetails? = nil
    var scriptureDetails: AmenScriptureDetails? = nil
    var linkDetails: AmenLinkDetails? = nil
}

// MARK: - Playback Transport

/// Describes how this attachment should be played back.
struct AmenPlayableInfo: Codable, Equatable, Sendable {

    enum Transport: String, Codable, Sendable {
        /// AVPlayer with a local or remote audio file.
        case nativeAudio
        /// AVPlayer with a local or remote video file.
        case nativeVideo
        /// WKWebView or YouTube iframe embed.
        case youtubeEmbed
        /// Opens the system browser or a third-party app.
        case external
    }

    let transport: Transport

    /// Direct media file URL (HLS, MP3, MP4, etc.). Nil for youtubeEmbed/external.
    let mediaURL: String?

    /// Total duration in milliseconds. Nil if unknown before playback starts.
    let durationMs: Int?

    /// Playback start offset in milliseconds (for resume / timestamp linking).
    var startMs: Int
}

// MARK: - Timed Timeline

/// A sequence of timed text segments: lyric lines, podcast chapters, or transcript cues.
struct AmenMediaTimeline: Codable, Equatable, Sendable {

    enum SegmentKind: String, Codable, Sendable {
        /// A single lyric line or stanza.
        case lyricLine
        /// A named chapter within a podcast or video.
        case chapter
        /// A subtitle or auto-caption cue.
        case transcriptCue
    }

    let segmentKind: SegmentKind
    let segments: [AmenTimedSegment]

    /// True when individual words within segments carry their own timing data
    /// (enables word-by-word wipe animation).
    let isWordSynced: Bool
}

/// A single timed segment within a timeline.
struct AmenTimedSegment: Codable, Equatable, Identifiable, Sendable {

    /// 0-based index used as a stable identifier within its timeline.
    let id: Int

    let startMs: Int
    let endMs: Int?

    /// Display text: a lyric line, chapter name, or transcript cue.
    let label: String

    /// Word-level timing data. Non-nil only when `isWordSynced` is true.
    let words: [AmenLyricWord]?

    /// Optional thumbnail URL — used for chapter preview images in video/podcast.
    let thumbnailURL: String?
}

/// A single word with its own start/end timing, enabling karaoke-style wipe animation.
struct AmenLyricWord: Codable, Equatable, Sendable {
    let startMs: Int
    let endMs: Int
    let text: String
}

// MARK: - Kind-Specific Detail Payloads

struct AmenMusicDetails: Codable, Equatable, Sendable {
    let artists: [String]
    let albumArtURL: String?
    var displayMode: AmenMusicCardMode
}

enum AmenMusicCardMode: String, Codable, Sendable {
    /// Single-line compact player pill.
    case compact
    /// Full-height card with artwork and progress ring.
    case expanded
    /// Spinning vinyl platter animation.
    case vinyl
}

struct AmenPodcastDetails: Codable, Equatable, Sendable {
    let showName: String
    let episodeNumber: Int?
    /// Supported playback speed multipliers shown in the speed picker.
    let speedOptions: [Double]
}

struct AmenVideoDetails: Codable, Equatable, Sendable {
    let channelName: String?
    let youtubeVideoID: String?
    let hasChapters: Bool
}

struct AmenArticleDetails: Codable, Equatable, Sendable {
    let sourceName: String
    let faviconURL: String?
    let readingTimeMinutes: Int?
    let excerpt: String?
}

struct AmenBookDetails: Codable, Equatable, Sendable {
    let authorName: String
    let coverURL: String?
    let isbn: String?
    let rating: Double?
    let blurb: String?
}

struct AmenProductDetails: Codable, Equatable, Sendable {
    let merchantName: String
    let imageURL: String?
    let isAffiliate: Bool
    /// Safety/transparency label shown to users (e.g. "Affiliate link").
    let safetyLabel: String?
}

struct AmenScriptureDetails: Codable, Equatable, Sendable {
    let reference: String
    let verseText: String
    let translation: String
    let youVersionDeepLink: String?
}

struct AmenLinkDetails: Codable, Equatable, Sendable {
    let domain: String
    let ogTitle: String?
    let ogDescription: String?
    let ogImageURL: String?
}

// MARK: - Post Draft

/// An in-progress post being composed by the user, persisted locally
/// (via AmenDraftPersistenceService) and optionally synced to Firestore.
struct AmenPostDraft: Codable, Identifiable, Sendable {
    var id: String
    var text: String
    var mediaAttachments: [AmenMediaAttachment]
    var imageURLs: [String]

    /// Optional community/space the post is directed to.
    var communityId: String?

    /// Topic tag IDs associated with this draft.
    var topicIds: [String]

    /// Mirrors FirestorePost.visibility: "everyone", "followers", or "community".
    var audienceVisibility: String

    /// Wall-clock timestamp of the most recent local save.
    var savedAt: Date
}

// MARK: - FirestorePost Extension

/// Adds the new `mediaAttachments` field to FirestorePost in an additive manner.
/// Old Firestore documents without this field decode it as nil — no migration needed.
extension FirestorePost {
    // NOTE: The actual stored property must be declared directly on FirestorePost
    // (in FirebasePostService.swift) to participate in Codable synthesis.
    // This extension documents the intent and provides the Firestore field key.

    /// The Firestore document key used to store media attachments.
    static let mediaAttachmentsKey = "mediaAttachments"
}

// MARK: - Sample Data

extension AmenMediaAttachment {

    /// Sample worship-song attachment for SwiftUI previews and unit tests.
    /// Note: AmenMusicAttachmentCards.swift has the authoritative `sampleMusic` static.
    static var sampleMusicWayMaker: AmenMediaAttachment {
        AmenMediaAttachment(
            id: "sample-music-001",
            kind: .music,
            sourceURL: "https://music.apple.com/us/album/way-maker/1234567890",
            title: "Way Maker",
            subtitle: "Sinach",
            thumbnailURL: "https://example.com/waymaker-cover.jpg",
            accentHex: "D4A017",
            playable: AmenPlayableInfo(
                transport: .nativeAudio,
                mediaURL: "https://example.com/audio/waymaker.m4a",
                durationMs: 285_000,
                startMs: 0
            ),
            timeline: AmenMediaTimeline(
                segmentKind: .lyricLine,
                segments: [
                    AmenTimedSegment(
                        id: 0,
                        startMs: 0,
                        endMs: 4_500,
                        label: "You are here, moving in our midst",
                        words: nil,
                        thumbnailURL: nil
                    ),
                    AmenTimedSegment(
                        id: 1,
                        startMs: 4_500,
                        endMs: 9_000,
                        label: "I worship You, I worship You",
                        words: nil,
                        thumbnailURL: nil
                    ),
                ],
                isWordSynced: false
            ),
            musicDetails: AmenMusicDetails(
                artists: ["Sinach"],
                albumArtURL: "https://example.com/waymaker-cover.jpg",
                displayMode: .expanded
            ),
            podcastDetails: nil,
            videoDetails: nil,
            articleDetails: nil,
            bookDetails: nil,
            productDetails: nil,
            scriptureDetails: nil,
            linkDetails: nil
        )
    }

    /// Sample podcast episode attachment for SwiftUI previews and unit tests.
    static var samplePodcast: AmenMediaAttachment {
        AmenMediaAttachment(
            id: "sample-podcast-001",
            kind: .podcast,
            sourceURL: "https://podcasts.apple.com/us/podcast/the-bible-project/id1038675066",
            title: "The Book of Job — Part 1",
            subtitle: "BibleProject Podcast",
            thumbnailURL: "https://example.com/bibleproject-cover.jpg",
            accentHex: "4A6FA5",
            playable: AmenPlayableInfo(
                transport: .nativeAudio,
                mediaURL: "https://example.com/audio/job-part1.mp3",
                durationMs: 3_600_000,
                startMs: 0
            ),
            timeline: AmenMediaTimeline(
                segmentKind: .chapter,
                segments: [
                    AmenTimedSegment(
                        id: 0,
                        startMs: 0,
                        endMs: 300_000,
                        label: "Introduction",
                        words: nil,
                        thumbnailURL: nil
                    ),
                    AmenTimedSegment(
                        id: 1,
                        startMs: 300_000,
                        endMs: 900_000,
                        label: "The Cosmic Conflict",
                        words: nil,
                        thumbnailURL: nil
                    ),
                ],
                isWordSynced: false
            ),
            musicDetails: nil,
            podcastDetails: AmenPodcastDetails(
                showName: "BibleProject Podcast",
                episodeNumber: 142,
                speedOptions: [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
            ),
            videoDetails: nil,
            articleDetails: nil,
            bookDetails: nil,
            productDetails: nil,
            scriptureDetails: nil,
            linkDetails: nil
        )
    }

    /// Sample article attachment for SwiftUI previews and unit tests.
    static var sampleArticle: AmenMediaAttachment {
        AmenMediaAttachment(
            id: "sample-article-001",
            kind: .article,
            sourceURL: "https://www.desiringgod.org/articles/gods-sovereignty-over-suffering",
            title: "God's Sovereignty Over Suffering",
            subtitle: "Desiring God",
            thumbnailURL: "https://example.com/dg-article-hero.jpg",
            accentHex: "8C3D3D",
            playable: nil,
            timeline: nil,
            musicDetails: nil,
            podcastDetails: nil,
            videoDetails: nil,
            articleDetails: AmenArticleDetails(
                sourceName: "Desiring God",
                faviconURL: "https://www.desiringgod.org/favicon.ico",
                readingTimeMinutes: 8,
                excerpt: "When suffering comes, we are invited to trust the God who holds every moment in His hand."
            ),
            bookDetails: nil,
            productDetails: nil,
            scriptureDetails: nil,
            linkDetails: nil
        )
    }
}
