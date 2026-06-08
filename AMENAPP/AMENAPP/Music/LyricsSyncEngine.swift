// MUSIC FEATURE — Agent A
import Foundation

struct LyricsSyncEngine {
    let track: LyricsTrack

    func activeLineIndex(atMs ms: Int) -> Int? {
        let lines = track.lines
        guard !lines.isEmpty else { return nil }
        // Binary search for the line whose startMs <= ms < endMs
        var lo = 0, hi = lines.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let line = lines[mid]
            if ms < line.startMs {
                hi = mid - 1
            } else if ms >= line.endMs {
                lo = mid + 1
            } else {
                return mid
            }
        }
        // Return the last line that started before ms (handles gaps at end)
        let candidate = min(lo, lines.count - 1)
        if ms >= lines[candidate].startMs {
            return candidate
        }
        return lo > 0 ? lo - 1 : nil
    }

    func wordProgress(atMs ms: Int) -> (line: Int, charsRevealed: Int)? {
        guard let lineIdx = activeLineIndex(atMs: ms) else { return nil }
        let line = track.lines[lineIdx]
        guard let words = line.words, !words.isEmpty else {
            // No word timings — reveal full line
            return (lineIdx, line.text.count)
        }
        var revealed = 0
        var charCount = 0
        for word in words {
            if ms >= word.startMs {
                charCount += word.text.count + 1 // +1 for space
                revealed = charCount
            }
        }
        return (lineIdx, min(revealed, line.text.count))
    }
}
