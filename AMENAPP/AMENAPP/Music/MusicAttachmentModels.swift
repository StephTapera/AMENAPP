// MUSIC FEATURE — Agent A
import Foundation

struct MusicAttachment: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let artists: [String]
    let albumArtURL: URL?
    let previewURL: URL
    let durationMs: Int
    var lyrics: LyricsTrack?
    var startMs: Int
    var displayMode: MusicCardMode

    init(id: String, title: String, artists: [String], albumArtURL: URL? = nil,
         previewURL: URL, durationMs: Int, lyrics: LyricsTrack? = nil,
         startMs: Int = 0, displayMode: MusicCardMode = .expanded) {
        self.id = id; self.title = title; self.artists = artists
        self.albumArtURL = albumArtURL; self.previewURL = previewURL
        self.durationMs = durationMs; self.lyrics = lyrics
        self.startMs = startMs; self.displayMode = displayMode
    }
}

struct LyricsTrack: Codable, Equatable {
    let lines: [LyricLine]
    let isWordSynced: Bool
}

struct LyricLine: Codable, Equatable, Identifiable {
    let id: Int
    let startMs: Int
    let endMs: Int
    let text: String
    let words: [LyricWord]?
}

struct LyricWord: Codable, Equatable {
    let startMs: Int
    let endMs: Int
    let text: String
}

enum MusicCardMode: String, Codable { case compact, expanded, vinyl }
