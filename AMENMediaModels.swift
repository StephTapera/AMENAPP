// AMENMediaModels.swift
// AMENAPP
//
// Core data models for the Christian Media Resources system.
// Covers Sermons (YouTube), Podcasts (Spotify/RSS), Worship Tracks,
// Teaching Series, and curated Resource cards.

import Foundation

// MARK: - Protocol

protocol AMENMediaItem: Identifiable, Equatable {
    var id: String { get }
    var title: String { get }
    var thumbnailURL: String? { get }
    var durationSeconds: Int? { get }
    var publishedAt: Date? { get }
    var sourceLabel: String { get }   // "YouTube · Elevation Church"
    var deepLinkURL: URL? { get }
}

// MARK: - Sermon (YouTube)

struct AMENSermon: AMENMediaItem, Codable, Hashable {
    let id: String
    let title: String
    let speaker: String
    let church: String
    let topic: String           // "Faith", "Identity", "Prayer" …
    let youtubeVideoID: String
    let thumbnailURL: String?
    let durationSeconds: Int?
    let publishedAt: Date?
    let description: String?
    let scriptureReference: String?   // "John 3:16"
    let series: String?               // Teaching series name
    let viewCount: Int?

    var sourceLabel: String { "YouTube · \(church)" }

    var deepLinkURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(youtubeVideoID)")
    }

    var embedURL: URL? {
        // Modestbranding + rel=0 keep users in our context
        URL(string: "https://www.youtube.com/embed/\(youtubeVideoID)?modestbranding=1&rel=0&playsinline=1")
    }
}

// MARK: - Podcast Episode (Spotify)

struct AMENPodcastEpisode: AMENMediaItem, Codable, Hashable {
    let id: String
    let title: String
    let showName: String
    let host: String
    let thumbnailURL: String?
    let durationSeconds: Int?
    let publishedAt: Date?
    let description: String?
    let spotifyEpisodeID: String?       // nil for RSS-only episodes
    let spotifyShowID: String?
    let rssAudioURL: String?            // Direct MP3 (fallback)
    let topic: String

    var sourceLabel: String { "Podcast · \(showName)" }

    var deepLinkURL: URL? {
        if let epID = spotifyEpisodeID {
            return URL(string: "https://open.spotify.com/episode/\(epID)")
        }
        if let audio = rssAudioURL { return URL(string: audio) }
        return nil
    }

    /// Spotify embed URL (180px tall, light theme)
    var spotifyEmbedURL: URL? {
        guard let epID = spotifyEpisodeID else { return nil }
        return URL(string: "https://open.spotify.com/embed/episode/\(epID)?utm_source=generator&theme=0")
    }
}

// MARK: - Worship Track

struct AMENWorshipTrack: AMENMediaItem, Codable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let thumbnailURL: String?
    let durationSeconds: Int?
    let publishedAt: Date?
    let spotifyTrackID: String?
    let youtubeVideoID: String?
    let appleMusicID: String?
    let scriptureReference: String?
    let topic: String

    var sourceLabel: String { "Worship · \(artist)" }

    var deepLinkURL: URL? {
        if let spotifyID = spotifyTrackID {
            return URL(string: "https://open.spotify.com/track/\(spotifyID)")
        }
        if let ytID = youtubeVideoID {
            return URL(string: "https://www.youtube.com/watch?v=\(ytID)")
        }
        return nil
    }

    var spotifyEmbedURL: URL? {
        guard let trackID = spotifyTrackID else { return nil }
        return URL(string: "https://open.spotify.com/embed/track/\(trackID)?utm_source=generator&theme=0")
    }
}

// MARK: - Teaching Series

struct AMENTeachingSeries: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let teacher: String
    let church: String
    let coverImageURL: String?
    let description: String?
    let episodeCount: Int
    let episodes: [AMENSermon]
    let topic: String
    let publishedAt: Date?

    var sourceLabel: String { "Series · \(church)" }
}

// MARK: - Saved Media

struct AMENSavedMediaItem: Identifiable, Codable {
    let id: String
    let userID: String
    let savedAt: Date
    let mediaType: MediaType
    let sermon: AMENSermon?
    let episode: AMENPodcastEpisode?
    let track: AMENWorshipTrack?

    enum MediaType: String, Codable {
        case sermon, podcast, worship
    }

    init(userID: String, sermon: AMENSermon) {
        self.id = UUID().uuidString
        self.userID = userID
        self.savedAt = Date()
        self.mediaType = .sermon
        self.sermon = sermon
        self.episode = nil
        self.track = nil
    }

    init(userID: String, episode: AMENPodcastEpisode) {
        self.id = UUID().uuidString
        self.userID = userID
        self.savedAt = Date()
        self.mediaType = .podcast
        self.sermon = nil
        self.episode = episode
        self.track = nil
    }

    init(userID: String, track: AMENWorshipTrack) {
        self.id = UUID().uuidString
        self.userID = userID
        self.savedAt = Date()
        self.mediaType = .worship
        self.sermon = nil
        self.episode = nil
        self.track = track
    }

    var title: String {
        sermon?.title ?? episode?.title ?? track?.title ?? ""
    }

    var thumbnailURL: String? {
        sermon?.thumbnailURL ?? episode?.thumbnailURL ?? track?.thumbnailURL
    }

    var sourceLabel: String {
        sermon?.sourceLabel ?? episode?.sourceLabel ?? track?.sourceLabel ?? ""
    }
}

// MARK: - Curated Resource Card (static editorial content)

struct AMENResourceCard: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let category: AMENResourceCategory
    let heroImageURL: String?
    let accentColorHex: String?
    let sermon: AMENSermon?
    let episode: AMENPodcastEpisode?
    let track: AMENWorshipTrack?
    let relatedBookTitle: String?       // For affiliate link row
    let relatedBookAuthor: String?
    let relatedBookISBN13: String?
    let scriptureReference: String?
    let featuredQuote: String?
    let isFeatured: Bool

    var mediaType: AMENSavedMediaItem.MediaType? {
        if sermon != nil { return .sermon }
        if episode != nil { return .podcast }
        if track != nil { return .worship }
        return nil
    }
}

// MARK: - Category

enum AMENResourceCategory: String, CaseIterable, Codable, Hashable {
    case all        = "All"
    case sermons    = "Sermons"
    case podcasts   = "Podcasts"
    case worship    = "Worship"
    case series     = "Series"
    case saved      = "Saved"

    var sfSymbol: String {
        switch self {
        case .all:      return "square.grid.2x2"
        case .sermons:  return "video.fill"
        case .podcasts: return "headphones"
        case .worship:  return "music.note"
        case .series:   return "play.rectangle.on.rectangle.fill"
        case .saved:    return "bookmark.fill"
        }
    }
}

// MARK: - YouTube Search Response (Data API v3)

struct YouTubeSearchResponse: Codable {
    let items: [YouTubeSearchItem]
    let nextPageToken: String?
}

struct YouTubeSearchItem: Codable {
    let id: YouTubeItemID
    let snippet: YouTubeSnippet
}

struct YouTubeItemID: Codable {
    let kind: String
    let videoId: String?
}

struct YouTubeSnippet: Codable {
    let title: String
    let channelTitle: String
    let description: String
    let publishedAt: String
    let thumbnails: YouTubeThumbnails
}

struct YouTubeThumbnails: Codable {
    let high: YouTubeThumbnail?
    let medium: YouTubeThumbnail?
    let standard: YouTubeThumbnail?
    let maxres: YouTubeThumbnail?

    var bestURL: String? {
        maxres?.url ?? standard?.url ?? high?.url ?? medium?.url
    }
}

struct YouTubeThumbnail: Codable {
    let url: String
}

// MARK: - Spotify Search Response

struct SpotifySearchResponse: Codable {
    let episodes: SpotifyEpisodePage?
}

struct SpotifyEpisodePage: Codable {
    let items: [SpotifyEpisodeItem]
    let next: String?
}

struct SpotifyEpisodeItem: Codable {
    let id: String
    let name: String
    let description: String
    let duration_ms: Int
    let release_date: String
    let images: [SpotifyImage]
    let show: SpotifyShow?
    let html_description: String?
    let external_urls: SpotifyExternalURLs?

    var thumbnailURL: String? { images.first?.url }
    var durationSeconds: Int { duration_ms / 1000 }
}

struct SpotifyShow: Codable {
    let id: String
    let name: String
    let publisher: String
    let images: [SpotifyImage]
}

struct SpotifyImage: Codable {
    let url: String
}

struct SpotifyExternalURLs: Codable {
    let spotify: String?
}

// MARK: - Spotify Token Response

struct SpotifyTokenResponse: Codable {
    let access_token: String
    let token_type: String
    let expires_in: Int
}

// MARK: - Static Curated Content

extension AMENSermon {
    /// Hand-curated seed sermons shown before API results load.
    static let curated: [AMENSermon] = [
        AMENSermon(
            id: "EHE7TRyK0co",
            title: "Who Is Jesus, Really?",
            speaker: "Steven Furtick",
            church: "Elevation Church",
            topic: "Identity",
            youtubeVideoID: "EHE7TRyK0co",
            thumbnailURL: "https://i.ytimg.com/vi/EHE7TRyK0co/maxresdefault.jpg",
            durationSeconds: 2640,
            publishedAt: nil,
            description: "An exploration of Christ's true identity and what it means for your own.",
            scriptureReference: "John 1:1–14",
            series: nil,
            viewCount: nil
        ),
        AMENSermon(
            id: "Ow3Hnlf0kEg",
            title: "Your Hurt Is Not Wasted",
            speaker: "T.D. Jakes",
            church: "The Potter's House",
            topic: "Faith",
            youtubeVideoID: "Ow3Hnlf0kEg",
            thumbnailURL: "https://i.ytimg.com/vi/Ow3Hnlf0kEg/maxresdefault.jpg",
            durationSeconds: 3180,
            publishedAt: nil,
            description: nil,
            scriptureReference: "Romans 8:28",
            series: nil,
            viewCount: nil
        ),
        AMENSermon(
            id: "7YXy3RLBOoA",
            title: "Grace That Is Greater",
            speaker: "Louie Giglio",
            church: "Passion City Church",
            topic: "Grace",
            youtubeVideoID: "7YXy3RLBOoA",
            thumbnailURL: "https://i.ytimg.com/vi/7YXy3RLBOoA/maxresdefault.jpg",
            durationSeconds: 2880,
            publishedAt: nil,
            description: nil,
            scriptureReference: "Romans 5:20",
            series: nil,
            viewCount: nil
        ),
        AMENSermon(
            id: "4Eab_AUmVJo",
            title: "Fear Is Not My Future",
            speaker: "Levi Lusko",
            church: "Fresh Life Church",
            topic: "Fear",
            youtubeVideoID: "4Eab_AUmVJo",
            thumbnailURL: "https://i.ytimg.com/vi/4Eab_AUmVJo/maxresdefault.jpg",
            durationSeconds: 2520,
            publishedAt: nil,
            description: nil,
            scriptureReference: "Isaiah 41:10",
            series: nil,
            viewCount: nil
        ),
        AMENSermon(
            id: "9OIhyVS_VqM",
            title: "Built to Last",
            speaker: "Andy Stanley",
            church: "North Point Ministries",
            topic: "Kingdom",
            youtubeVideoID: "9OIhyVS_VqM",
            thumbnailURL: "https://i.ytimg.com/vi/9OIhyVS_VqM/maxresdefault.jpg",
            durationSeconds: 2760,
            publishedAt: nil,
            description: nil,
            scriptureReference: "Matthew 7:24–27",
            series: nil,
            viewCount: nil
        )
    ]
}

extension AMENPodcastEpisode {
    static let curated: [AMENPodcastEpisode] = [
        AMENPodcastEpisode(
            id: "elevated-convo-1",
            title: "How to Hear God in the Noise",
            showName: "Elevation with Steven Furtick",
            host: "Steven Furtick",
            thumbnailURL: nil,
            durationSeconds: 2700,
            publishedAt: nil,
            description: "What does it mean to truly listen for God's voice in a distracted world?",
            spotifyEpisodeID: nil,
            spotifyShowID: nil,
            rssAudioURL: nil,
            topic: "Prayer"
        ),
        AMENPodcastEpisode(
            id: "jesus-calling-1",
            title: "Peace in Chaos",
            showName: "Jesus Calling Podcast",
            host: "Sarah Young",
            thumbnailURL: nil,
            durationSeconds: 1800,
            publishedAt: nil,
            description: "Discovering peace that transcends understanding.",
            spotifyEpisodeID: nil,
            spotifyShowID: nil,
            rssAudioURL: nil,
            topic: "Peace"
        )
    ]
}
