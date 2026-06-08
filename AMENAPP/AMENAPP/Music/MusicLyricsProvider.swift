// MUSIC FEATURE — Agent A
import Foundation

protocol LyricsProvider {
    func lyrics(forTrackID id: String) async throws -> LyricsTrack?
}

final class StubLyricsProvider: LyricsProvider {
    static let sampleLRC = """
    [00:00.00] You are faithful, always faithful
    [00:04.50] Through the storm and through the fire
    [00:09.00] Every promise that You've spoken
    [00:13.50] Still remains, will not expire
    [00:18.00] Great is Your mercy, new every morning
    [00:22.50] Your lovingkindness never ends
    [00:27.00] When I am weak, You are my strength
    [00:31.50] Faithful God, my closest friend
    """

    func lyrics(forTrackID id: String) async throws -> LyricsTrack? {
        try await Task.sleep(nanoseconds: 300_000_000) // simulate fetch
        return LRCParser.parse(StubLyricsProvider.sampleLRC)
    }
}
