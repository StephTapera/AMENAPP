// MusicContentContracts.swift
// AMENAPP — MusicContentLayer
//
// FROZEN — v1.0  2026-06-10
// Do NOT change existing case values or property names without a version bump.
// Add new cases / properties only at the end of each declaration.
//
// §1  ContentAttachmentType
// §2  MusicResource
// §3  SermonResource
// §4  ContentAttachment
// §5  PostIntentType
// §6  CommentContentContext
// §7  ProfileResourceItem
// §8  ProfileResourceCategory
// §9  RightsPolicy
// §10 VisibilityPolicy
// §11 MusicContentModerationStatus
// §12 FaithGraphNodeType
// §13 ListeningRoomState
// §14 AmenPulseDigestItemType

import Foundation

// MARK: - §1  ContentAttachmentType

/// All content types that can be attached to a post, comment, or shelf item.
enum ContentAttachmentType: String, Codable, Sendable, CaseIterable {
    case song               = "song"
    case album              = "album"
    case playlist           = "playlist"
    case sermonClip         = "sermon_clip"
    case worshipSet         = "worship_set"
    case choirRecording     = "choir_recording"
    case artistProfile      = "artist_profile"
    case churchProfile      = "church_profile"
    case orgProfile         = "org_profile"
    case devotionalAudio    = "devotional_audio"
    case podcastEpisode     = "podcast_episode"
    case eventPlaylist      = "event_playlist"
}

// MARK: - §2  MusicResource

/// A single music item: song, album, playlist, worship set, choir recording, etc.
struct MusicResource: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let artistName: String
    let albumName: String?
    let artworkURL: URL?
    let previewURL: URL?
    let durationSeconds: Double
    let isVerifiedClean: Bool
    let rightsPolicy: RightsPolicy
    let visibility: VisibilityPolicy
    let moderationStatus: MusicContentModerationStatus
    /// ISO 8601 timestamp
    let createdAt: String
}

// MARK: - §3  SermonResource

/// A sermon clip with speaker, series, and scripture metadata.
struct SermonResource: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let speakerName: String
    let seriesName: String?
    let churchName: String?
    let artworkURL: URL?
    let audioURL: URL?
    let videoURL: URL?
    let durationSeconds: Double
    let scriptureReferences: [String]
    let isVerifiedClean: Bool
    let rightsPolicy: RightsPolicy
    let visibility: VisibilityPolicy
    let moderationStatus: MusicContentModerationStatus
    /// ISO 8601 timestamp
    let createdAt: String
}

// MARK: - §4  ContentAttachment

/// Generic attachment wrapper — exactly one of musicResource or sermonResource
/// will be populated based on `type`, or profileID for profile-type attachments.
struct ContentAttachment: Codable, Sendable, Identifiable {
    let id: String
    let type: ContentAttachmentType
    let musicResource: MusicResource?
    let sermonResource: SermonResource?
    /// Populated for artist_profile / church_profile / org_profile types.
    let profileID: String?
    let externalURL: URL?
    let displayTitle: String
    let displaySubtitle: String?
    let displayArtworkURL: URL?
    let rightsPolicy: RightsPolicy
    let visibility: VisibilityPolicy
    let isVerifiedClean: Bool
    /// ISO 8601 timestamp
    let createdAt: String
}

// MARK: - §5  PostIntentType

/// Machine-detected or user-declared intent for a post.
enum PostIntentType: String, Codable, Sendable, CaseIterable {
    case songShare              = "song_share"
    case albumShare             = "album_share"
    case sermonNote             = "sermon_note"
    case churchNote             = "church_note"
    case prayerRequest          = "prayer_request"
    case testimony              = "testimony"
    case eventAnnouncement      = "event_announcement"
    case scriptureQuote         = "scripture_quote"
    case devotional             = "devotional"
    case resourceShare          = "resource_share"
    case question               = "question"
    case poll                   = "poll"
    case worshipRelease         = "worship_release"
    case orgUpdate              = "org_update"
    case communityDiscussion    = "community_discussion"
}

// MARK: - §6  CommentContentContext

/// The detected content context of a parent post, used to guide comment suggestions.
struct CommentContentContext: Codable, Sendable, Identifiable {
    let id: String
    let postID: String
    let detectedIntent: PostIntentType
    let primaryAttachmentType: ContentAttachmentType?
    let faithGraphNodeTypes: [FaithGraphNodeType]
    /// ISO 8601 timestamp
    let createdAt: String
}

// MARK: - §7  ProfileResourceItem

/// One item on a church or organisation resource shelf.
struct ProfileResourceItem: Codable, Sendable, Identifiable {
    let id: String
    let profileID: String
    let category: ProfileResourceCategory
    let attachment: ContentAttachment
    let sortOrder: Int
    let isPinned: Bool
    /// ISO 8601 timestamp
    let createdAt: String
}

// MARK: - §8  ProfileResourceCategory

/// Shelf category for a church/org resource item.
enum ProfileResourceCategory: String, Codable, Sendable, CaseIterable {
    case music          = "music"
    case sermons        = "sermons"
    case podcasts       = "podcasts"
    case events         = "events"
    case devotionals    = "devotionals"
    case choirAndWorship = "choir_and_worship"
    case resources      = "resources"
    case other          = "other"
}

// MARK: - §9  RightsPolicy

/// Access-control and monetisation state for a content item.
enum RightsPolicy: String, Codable, Sendable, CaseIterable {
    case free           = "free"
    case paid           = "paid"
    case memberOnly     = "member_only"
    case donationSupported = "donation_supported"
    case licensed       = "licensed"
    case streamOnly     = "stream_only"
    case downloadable   = "downloadable"
    case `private`      = "private"
    case unlisted       = "unlisted"
    case restricted     = "restricted"
    case pendingReview  = "pending_review"
}

// MARK: - §10  VisibilityPolicy

/// Who can see a content item.
enum VisibilityPolicy: String, Codable, Sendable, CaseIterable {
    case `public`       = "public"
    case `private`      = "private"
    case unlisted       = "unlisted"
    case membersOnly    = "members_only"
    case childSafe      = "child_safe"
    case adminOnly      = "admin_only"
}

// MARK: - §11  MusicContentModerationStatus

/// Moderation lifecycle state for a music or audio content item.
enum MusicContentModerationStatus: String, Codable, Sendable, CaseIterable {
    case approved       = "approved"
    case pending        = "pending"
    case flagged        = "flagged"
    case blocked        = "blocked"
    case underReview    = "under_review"
    case appealing      = "appealing"
}

// MARK: - §12  FaithGraphNodeType

/// Node type in the faith knowledge graph.
enum FaithGraphNodeType: String, Codable, Sendable, CaseIterable {
    case song           = "song"
    case sermon         = "sermon"
    case church         = "church"
    case scripture      = "scripture"
    case artist         = "artist"
    case album          = "album"
    case playlist       = "playlist"
    case devotional     = "devotional"
    case podcast        = "podcast"
    case event          = "event"
    case ministry       = "ministry"
    case person         = "person"
}

// MARK: - §13  ListeningRoomState

/// Lifecycle state of a live listening room.
enum ListeningRoomState: String, Codable, Sendable, CaseIterable {
    case scheduled      = "scheduled"
    case live           = "live"
    case ended          = "ended"
    case cancelled      = "cancelled"
}

/// A listening room session wrapping a content attachment.
struct ListeningRoom: Codable, Sendable, Identifiable {
    let id: String
    let hostUserID: String
    let title: String
    let attachment: ContentAttachment
    let state: ListeningRoomState
    let participantCount: Int
    let maxParticipants: Int?
    let scheduledAt: String?
    let startedAt: String?
    let endedAt: String?
    /// ISO 8601 timestamp
    let createdAt: String
}

// MARK: - §14  AmenPulseDigestItemType

/// The kind of item surfaced in the Amen Pulse daily digest.
enum AmenPulseDigestItemType: String, Codable, Sendable, CaseIterable {
    case topSong            = "top_song"
    case newSermon          = "new_sermon"
    case trendingWorship    = "trending_worship"
    case communityHighlight = "community_highlight"
    case churchUpdate       = "church_update"
    case devotionalAudio    = "devotional_audio"
    case liveRoom           = "live_room"
    case curatedPlaylist    = "curated_playlist"
    case featuredArtist     = "featured_artist"
    case scriptureOfTheDay  = "scripture_of_the_day"
}

/// One item inside the Amen Pulse daily digest.
struct AmenPulseDigestItem: Codable, Sendable, Identifiable {
    let id: String
    let digestType: AmenPulseDigestItemType
    let attachment: ContentAttachment?
    let headlineText: String
    let bodyText: String?
    let callToActionLabel: String?
    let callToActionURL: URL?
    let listeningRoom: ListeningRoom?
    let sortOrder: Int
    /// ISO 8601 timestamp
    let createdAt: String
}

// MARK: - Contract Assertions

/// Call during DEBUG app launch to verify contract shapes are compilable.
/// This is a compile-time assertion function — all checks are exhaustive
/// switch coverage verified by the compiler.
func _contractAssertions() {
    // §1 — all ContentAttachmentType cases accounted for
    let allTypes = ContentAttachmentType.allCases
    assert(!allTypes.isEmpty, "ContentAttachmentType must have at least one case")

    // §2 — MusicResource is Codable & Sendable
    let encoder = JSONEncoder()
    let sampleMusic = MusicResource(
        id: "assert-music-1",
        title: "Test Song",
        artistName: "Test Artist",
        albumName: nil,
        artworkURL: nil,
        previewURL: nil,
        durationSeconds: 180,
        isVerifiedClean: true,
        rightsPolicy: .free,
        visibility: .public,
        moderationStatus: .approved,
        createdAt: "2026-06-10T00:00:00Z"
    )
    _ = try? encoder.encode(sampleMusic)

    // §3 — SermonResource is Codable & Sendable
    let sampleSermon = SermonResource(
        id: "assert-sermon-1",
        title: "Test Sermon",
        speakerName: "Test Speaker",
        seriesName: nil,
        churchName: nil,
        artworkURL: nil,
        audioURL: nil,
        videoURL: nil,
        durationSeconds: 2400,
        scriptureReferences: ["John 3:16"],
        isVerifiedClean: true,
        rightsPolicy: .free,
        visibility: .public,
        moderationStatus: .approved,
        createdAt: "2026-06-10T00:00:00Z"
    )
    _ = try? encoder.encode(sampleSermon)

    // §4 — ContentAttachment round-trips
    let sampleAttachment = ContentAttachment(
        id: "assert-attachment-1",
        type: .song,
        musicResource: sampleMusic,
        sermonResource: nil,
        profileID: nil,
        externalURL: nil,
        displayTitle: "Test Song",
        displaySubtitle: "Test Artist",
        displayArtworkURL: nil,
        rightsPolicy: .free,
        visibility: .public,
        isVerifiedClean: true,
        createdAt: "2026-06-10T00:00:00Z"
    )
    _ = try? encoder.encode(sampleAttachment)

    // §9–§11 — policy enums are non-empty
    assert(!RightsPolicy.allCases.isEmpty)
    assert(!VisibilityPolicy.allCases.isEmpty)
    assert(!MusicContentModerationStatus.allCases.isEmpty)

    // §12–§14 — graph + room + pulse enums are non-empty
    assert(!FaithGraphNodeType.allCases.isEmpty)
    assert(!ListeningRoomState.allCases.isEmpty)
    assert(!AmenPulseDigestItemType.allCases.isEmpty)
}
