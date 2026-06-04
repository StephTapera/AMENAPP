import Foundation

actor PostComposerSmartDetectionService {

    func detectAll(in text: String) async -> [DetectedPostContextItem] {
        var results: [DetectedPostContextItem] = []
        results += detectLinks(in: text)
        results += detectDates(in: text)
        results += detectMusicMentions(in: text)
        results += detectSensitiveSignals(in: text)
        return results
    }

    func detectLinks(in text: String) -> [DetectedPostContextItem] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        return matches.compactMap { match -> DetectedPostContextItem? in
            guard let url = match.url else { return nil }
            let display = url.host ?? url.absoluteString
            return DetectedPostContextItem(
                id: UUID(),
                type: .link,
                displayText: display,
                rawValue: url.absoluteString
            )
        }
    }

    func detectDates(in text: String) -> [DetectedPostContextItem] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return matches.compactMap { match -> DetectedPostContextItem? in
            guard let date = match.date else { return nil }
            guard let stringRange = Range(match.range, in: text) else { return nil }
            let snippet = String(text[stringRange])
            return DetectedPostContextItem(
                id: UUID(),
                type: .date,
                displayText: snippet,
                rawValue: formatter.string(from: date)
            )
        }
    }

    func detectMusicMentions(in text: String) -> [DetectedPostContextItem] {
        // Heuristic patterns: "album", "song", "track", "playlist", or "by [CapitalizedWord]"
        let keywords = ["album", "song", "track", "playlist", "lyrics", "EP", "single"]
        var results: [DetectedPostContextItem] = []

        for keyword in keywords {
            if text.range(of: keyword, options: [.caseInsensitive]) != nil {
                results.append(DetectedPostContextItem(
                    id: UUID(),
                    type: .music,
                    displayText: keyword,
                    rawValue: keyword
                ))
                // One music signal is enough per check pass
                break
            }
        }

        // Check for "by [Capitalized Artist]" pattern
        if results.isEmpty {
            let pattern = #"\bby\s+([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)?)\b"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let artistRange = Range(match.range(at: 1), in: text) {
                let artist = String(text[artistRange])
                results.append(DetectedPostContextItem(
                    id: UUID(),
                    type: .music,
                    displayText: artist,
                    rawValue: artist
                ))
            }
        }

        return results
    }

    func detectSensitiveSignals(in text: String) -> [DetectedPostContextItem] {
        // Surface only — never blocks posting
        let signals: [(keyword: String, label: String)] = [
            ("suicid", "Crisis signal"),
            ("self-harm", "Crisis signal"),
            ("self harm", "Crisis signal"),
            ("end my life", "Crisis signal"),
            ("don't want to live", "Crisis signal"),
            ("abuse", "Safety signal"),
            ("crisis", "Safety signal")
        ]

        let lowered = text.lowercased()
        for signal in signals {
            if lowered.contains(signal.keyword) {
                return [DetectedPostContextItem(
                    id: UUID(),
                    type: .sensitiveSignal,
                    displayText: signal.label,
                    rawValue: signal.keyword
                )]
            }
        }
        return []
    }
}
