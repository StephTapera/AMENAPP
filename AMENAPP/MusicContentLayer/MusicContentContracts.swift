// MusicContentContracts.swift
// AMENAPP — MusicContentLayer
//
// FROZEN — v1.1  2026-06-10
// Do NOT change existing case values or property names without a version bump.
// Add new cases / properties only at the end of each declaration.
//
// §1  ContentAttachmentType
// §2  MusicResource
// §3  SermonResource
// §4  ContentAttachment
// §5  PostIntentType
// §6  CommentContentContextRecord
// §7  ProfileResourceItem
// §8  ProfileResourceCategory
// §9  RightsPolicy
// §10 VisibilityPolicy
// §11 MusicContentModerationStatus
// §12 FaithGraphNodeType
// §13 ListeningRoomState + ListeningRoomRecord
// §14 AmenPulseDigestItemType + AmenPulseDigestItemRecord

import Foundation

// MARK: - §1  ContentAttachmentType

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
    let createdAt: String
}

// MARK: - §3  SermonResource

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
    let createdAt: String
}

// MARK: - §4  ContentAttachment

struct ContentAttachment: Codable, Sendable, Identifiable {
    let id: String
    let type: ContentAttachmentType
    let musicResource: MusicResource?
    let sermonResource: SermonResource?
    let profileID: String?
    let externalURL: URL?
    let displayTitle: String
    let displaySubtitle: String?
    let displayArtworkURL: URL?
    let rightsPolicy: RightsPolicy
    let visibility: VisibilityPolicy
    let isVerifiedClean: Bool
    let createdAt: String
}

// MARK: - §5  PostIntentType

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

    /// Human-readable label used in suggestion pills and accessibility strings.
    var displayName: String {
        switch self {
        case .songShare:            return "Song Share"
        case .albumShare:           return "Album Share"
        case .sermonNote:           return "Sermon Note"
        case .churchNote:           return "Church Note"
        case .prayerRequest:        return "Prayer Request"
        case .testimony:            return "Testimony"
        case .eventAnnouncement:    return "Event"
        case .scriptureQuote:       return "Scripture"
        case .devotional:           return "Devotional"
        case .resourceShare:        return "Resource"
        case .question:             return "Question"
        case .poll:                 return "Poll"
        case .worshipRelease:       return "Worship Release"
        case .orgUpdate:            return "Org Update"
        case .communityDiscussion:  return "Discussion"
        }
    }

    /// SF Symbol name for use in suggestion pills and intent indicators.
    var sfSymbol: String {
        switch self {
        case .songShare, .albumShare:   return "music.note"
        case .sermonNote, .churchNote:  return "note.text"
        case .prayerRequest:            return "hands.sparkles"
        case .testimony:                return "person.wave.2"
        case .eventAnnouncement:        return "calendar.badge.plus"
        case .scriptureQuote:           return "book.closed"
        case .devotional:               return "heart.text.square"
        case .resourceShare:            return "square.and.arrow.up"
        case .question:                 return "questionmark.bubble"
        case .poll:                     return "chart.bar"
        case .worshipRelease:           return "music.mic"
        case .orgUpdate:                return "building.2"
        case .communityDiscussion:      return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - §6  CommentContentContextRecord

struct CommentContentContextRecord: Codable, Sendable, Identifiable {
    let id: String
    let postID: String
    let detectedIntent: PostIntentType
    let primaryAttachmentType: ContentAttachmentType?
    let faithGraphNodeTypes: [FaithGraphNodeType]
    let createdAt: String
}

// MARK: - §7  ProfileResourceItem

struct ProfileResourceItem: Codable, Sendable, Identifiable {
    let id: String
    let profileID: String
    let category: ProfileResourceCategory
    let attachment: ContentAttachment
    let sortOrder: Int
    let isPinned: Bool
    let createdAt: String
}

// MARK: - §8  ProfileResourceCategory

enum ProfileResourceCategory: String, Codable, Sendable, CaseIterable {
    case music           = "music"
    case sermons         = "sermons"
    case podcasts        = "podcasts"
    case events          = "events"
    case devotionals     = "devotionals"
    case choirAndWorship = "choir_and_worship"
    case resources       = "resources"
    case other           = "other"
}

// MARK: - §9  RightsPolicy

enum RightsPolicy: String, Codable, Sendable, CaseIterable {
    case free              = "free"
    case paid              = "paid"
    case memberOnly        = "member_only"
    case donationSupported = "donation_supported"
    case licensed          = "licensed"
    case streamOnly        = "stream_only"
    case downloadable      = "downloadable"
    case `private`         = "private"
    case unlisted          = "unlisted"
    case restricted        = "restricted"
    case pendingReview     = "pending_review"
}

// MARK: - §10  VisibilityPolicy

enum VisibilityPolicy: String, Codable, Sendable, CaseIterable {
    case `public`    = "public"
    case `private`   = "private"
    case unlisted    = "unlisted"
    case membersOnly = "members_only"
    case childSafe   = "child_safe"
    case adminOnly   = "admin_only"
}

// MARK: - §11  MusicContentModerationStatus

enum MusicContentModerationStatus: String, Codable, Sendable, CaseIterable {
    case approved    = "approved"
    case pending     = "pending"
    case flagged     = "flagged"
    case blocked     = "blocked"
    case underReview = "under_review"
    case appealing   = "appealing"
}

// MARK: - §12  FaithGraphNodeType

enum FaithGraphNodeType: String, Codable, Sendable, CaseIterable {
    case song       = "song"
    case sermon     = "sermon"
    case church     = "church"
    case scripture  = "scripture"
    case artist     = "artist"
    case album      = "album"
    case playlist   = "playlist"
    case devotional = "devotional"
    case podcast    = "podcast"
    case event      = "event"
    case ministry   = "ministry"
    case person     = "person"
}

// MARK: - §13  ListeningRoomState + ListeningRoomRecord

enum ListeningRoomState: String, Codable, Sendable, CaseIterable {
    case scheduled = "scheduled"
    case live      = "live"
    case ended     = "ended"
    case cancelled = "cancelled"
}

struct ListeningRoomRecord: Codable, Sendable, Identifiable {
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
    let createdAt: String
}

// MARK: - §14  AmenPulseDigestItemType + AmenPulseDigestItemRecord

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

struct AmenPulseDigestItemRecord: Codable, Sendable, Identifiable {
    let id: String
    let digestType: AmenPulseDigestItemType
    let attachment: ContentAttachment?
    let headlineText: String
    let bodyText: String?
    let callToActionLabel: String?
    let callToActionURL: URL?
    let sortOrder: Int
    let createdAt: String
}

// MARK: - Contract Assertions

func _musicContentContractAssertions() {
    let encoder = JSONEncoder()
    let sampleMusic = MusicResource(
        id: "assert-1", title: "Test", artistName: "Artist",
        albumName: nil, artworkURL: nil, previewURL: nil,
        durationSeconds: 180, isVerifiedClean: true,
        rightsPolicy: .free, visibility: .public,
        moderationStatus: .approved, createdAt: "2026-06-10T00:00:00Z"
    )
    _ = try? encoder.encode(sampleMusic)
    assert(!RightsPolicy.allCases.isEmpty)
    assert(!VisibilityPolicy.allCases.isEmpty)
    assert(!FaithGraphNodeType.allCases.isEmpty)
    // Verify UI properties compile
    assert(!PostIntentType.allCases.map(\.displayName).isEmpty)
    assert(!PostIntentType.allCases.map(\.sfSymbol).isEmpty)
}
