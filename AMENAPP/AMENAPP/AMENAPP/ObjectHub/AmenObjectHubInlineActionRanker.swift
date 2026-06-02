import Foundation

enum AmenInlineObjectHubAction: String, CaseIterable, Hashable {
    case openHub
    case openProvider
    case save
    case discuss
}

enum AmenObjectHubInlineActionRanker {
    static func actions(for objectType: AmenAttachmentType, safetyState: AmenAttachmentSafetyStatus) -> [AmenInlineObjectHubAction] {
        guard safetyState != .blocked else { return [] }
        if safetyState == .limited {
            return [.openHub]
        }

        let base: [AmenInlineObjectHubAction]
        switch objectType {
        case .song, .album, .playlist, .artist, .video, .podcast, .article, .genericLink:
            base = [.openProvider, .save, .discuss, .openHub]
        case .scripture, .sermon:
            base = [.openHub, .save, .discuss]
        case .profile, .post:
            base = [.openProvider, .discuss, .openHub]
        case .reel, .short, .channel, .episode:
            base = [.openProvider, .discuss, .openHub]
        case .event, .donation, .rssFeed:
            base = [.openProvider, .discuss, .openHub]
        }
        return Array(base.prefix(4))
    }

    static func icon(for objectType: AmenAttachmentType) -> String {
        switch objectType {
        case .song: return "music.note"
        case .album: return "square.stack"
        case .artist: return "person.wave.2"
        case .playlist: return "music.note.list"
        case .video: return "film"
        case .podcast: return "waveform"
        case .article: return "doc.text"
        case .scripture: return "book.fill"
        case .sermon: return "mic.fill"
        case .profile: return "person.circle"
        case .post: return "text.bubble"
        case .reel: return "play.rectangle"
        case .short: return "play.square"
        case .channel: return "tv"
        case .episode: return "headphones"
        case .event: return "calendar"
        case .donation: return "heart.fill"
        case .rssFeed: return "dot.radiowaves.left.and.right"
        case .genericLink: return "circle.grid.2x2"
        }
    }

    static func actionText(for objectType: AmenAttachmentType) -> String {
        switch objectType {
        case .song: return "Song Hub"
        case .album: return "Album Hub"
        case .artist: return "Artist Hub"
        case .playlist: return "Playlist Hub"
        case .video: return "Video Hub"
        case .podcast: return "Podcast Hub"
        case .article: return "Discuss"
        case .scripture: return "Scripture Hub"
        case .sermon: return "Sermon Hub"
        case .profile: return "View Profile"
        case .post: return "Open Post"
        case .reel: return "Watch Reel"
        case .short: return "Watch Short"
        case .channel: return "View Channel"
        case .episode: return "Episode Hub"
        case .event: return "Event Hub"
        case .donation: return "Give"
        case .rssFeed: return "Follow"
        case .genericLink: return "Open Hub"
        }
    }

    static func providerLabel(for objectType: AmenAttachmentType) -> String {
        switch objectType {
        case .song, .album, .playlist, .artist: return "Listen"
        case .video, .reel, .short: return "Watch"
        case .podcast, .episode: return "Play"
        case .article, .scripture, .sermon: return "Read"
        case .profile, .channel: return "View"
        case .post: return "See Post"
        case .event: return "RSVP"
        case .donation: return "Give"
        case .rssFeed: return "Follow"
        case .genericLink: return "Open"
        }
    }
}
