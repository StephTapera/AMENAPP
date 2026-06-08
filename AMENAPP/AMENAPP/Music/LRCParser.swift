// MUSIC FEATURE — Agent A
import Foundation

struct LRCParser {
    static func parse(_ lrc: String) -> LyricsTrack {
        var lines: [LyricLine] = []
        let isWordSynced = false
        let rawLines = lrc.components(separatedBy: "\n")

        for (index, rawLine) in rawLines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }

            // Match [mm:ss.xx] or [mm:ss.xxx]
            let pattern = #"^\[(\d+):(\d+\.\d+)\](.*)$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else { continue }

            let nsStr = trimmed as NSString
            let minutes = Double(nsStr.substring(with: match.range(at: 1))) ?? 0
            let seconds = Double(nsStr.substring(with: match.range(at: 2))) ?? 0
            let text = nsStr.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)

            guard !text.isEmpty else { continue }

            let startMs = Int((minutes * 60 + seconds) * 1000)
            lines.append(LyricLine(id: index, startMs: startMs, endMs: startMs + 4500, text: text, words: nil))
        }

        lines.sort { $0.startMs < $1.startMs }
        // Fix endMs: each line ends where the next begins
        for i in 0..<lines.count - 1 {
            lines[i] = LyricLine(id: lines[i].id, startMs: lines[i].startMs,
                                  endMs: lines[i + 1].startMs, text: lines[i].text, words: lines[i].words)
        }

        return LyricsTrack(lines: lines, isWordSynced: isWordSynced)
    }
}
