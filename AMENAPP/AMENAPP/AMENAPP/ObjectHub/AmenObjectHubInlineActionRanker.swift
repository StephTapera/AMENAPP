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
        default:
            base = [.openHub, .discuss]
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
        case .genericLink: return "circle.grid.2x2"
        default: return "square.grid.2x2"
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
        case .genericLink: return "Open Hub"
        default: return "Open Hub"
        }
    }

    static func providerLabel(for objectType: AmenAttachmentType) -> String {
        switch objectType {
        case .song, .album, .playlist, .artist: return "Listen"
        case .video: return "Watch"
        case .podcast: return "Play"
        case .article: return "Read"
        case .genericLink: return "Open"
        default: return "Open"
        }
    }
}
