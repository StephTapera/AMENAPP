// MUSIC FEATURE — Agent A
import Foundation

extension MusicAttachment {
    static let sample: MusicAttachment = {
        let lyricsTrack = LRCParser.parse(StubLyricsProvider.sampleLRC)
        return MusicAttachment(
            id: "sample-faithful-001",
            title: "Faithful",
            artists: ["AMEN Worship"],
            albumArtURL: nil,
            previewURL: URL(string: "https://commondatastorage.googleapis.com/codeskulptor-demos/DDR_assets/Kangaroo_MusiQue_-_The_Neverwritten_Role_Playing_Game.mp3")!,
            durationMs: 34000,
            lyrics: lyricsTrack,
            startMs: 0,
            displayMode: .expanded
        )
    }()
}
