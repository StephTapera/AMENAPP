import Foundation

actor PostComposerSmartDetectionService {

    func detectAll(in text: String) async -> [DetectedPostContextItem] {
        var results: [DetectedPostContextItem] = []
        results += detectIntent(in: text)
        results += detectTopicTags(in: text)
        results += detectLinks(in: text)
        results += detectLinkTrustSignals(in: text)
        results += detectDates(in: text)
        results += detectMusicMentions(in: text)
        results += detectSensitiveSignals(in: text)
        results += detectAudienceRisks(in: text)
        return deduplicated(results)
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

    func detectLinkTrustSignals(in text: String) -> [DetectedPostContextItem] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        let shortenedHosts = ["bit.ly", "tinyurl.com", "t.co", "lnkd.in", "goo.gl", "buff.ly"]

        return matches.compactMap { match -> DetectedPostContextItem? in
            guard let url = match.url else { return nil }
            let host = url.host?.lowercased() ?? ""

            if url.scheme?.lowercased() == "http" {
                return DetectedPostContextItem(
                    id: UUID(),
                    type: .linkTrust,
                    displayText: "Check HTTP link",
                    rawValue: url.absoluteString
                )
            }

            if shortenedHosts.contains(host) {
                return DetectedPostContextItem(
                    id: UUID(),
                    type: .linkTrust,
                    displayText: "Short link",
                    rawValue: url.absoluteString
                )
            }

            return nil
        }
    }

    func detectIntent(in text: String) -> [DetectedPostContextItem] {
        let lower = text.lowercased()
        let candidates: [(keywords: [String], label: String, rawValue: String)] = [
            (["please pray", "pray for", "prayer", "healing", "anxious", "struggling"], "Prayer draft", "prayer"),
            (["testimony", "god did", "breakthrough", "answered prayer", "miracle"], "Testimony draft", "testimony"),
            (["what do you think", "has anyone", "question", "thoughts on", "how do"], "Question draft", "question"),
            (["join us", "register", "rsvp", "service", "event", "tonight", "tomorrow"], "Announcement draft", "announcement"),
            (["scripture", "verse", "bible says", "devotional", "psalm", "john "], "Scripture draft", "verse"),
            (["worship", "song", "playlist", "lyrics", "album"], "Worship draft", "worship")
        ]

        guard let match = candidates.first(where: { candidate in
            candidate.keywords.contains { lower.contains($0) }
        }) else {
            return []
        }

        return [
            DetectedPostContextItem(
                id: UUID(),
                type: .intent,
                displayText: match.label,
                rawValue: match.rawValue
            )
        ]
    }

    func detectTopicTags(in text: String) -> [DetectedPostContextItem] {
        let lower = text.lowercased()
        let tagRules: [(tag: String, keywords: [String])] = [
            ("#Prayer", ["pray", "prayer", "healing", "intercede", "anxious", "burden"]),
            ("#Testimony", ["testimony", "answered prayer", "miracle", "breakthrough", "god did"]),
            ("#BibleStudy", ["scripture", "verse", "bible", "devotional", "study", "psalm"]),
            ("#Worship", ["worship", "song", "hymn", "playlist", "lyrics", "praise"]),
            ("#ChurchUpdate", ["service", "church", "announcement", "volunteer", "register", "rsvp"]),
            ("#Question", ["?", "question", "thoughts", "has anyone", "what do you think"])
        ]

        return tagRules.compactMap { rule in
            guard rule.keywords.contains(where: { lower.contains($0) }) else { return nil }
            return DetectedPostContextItem(
                id: UUID(),
                type: .topicTag,
                displayText: rule.tag,
                rawValue: rule.tag
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

    func detectAudienceRisks(in text: String) -> [DetectedPostContextItem] {
        let lower = text.lowercased()
        let privateSignals = [
            "confession", "confess", "struggling with", "addiction", "relapse",
            "marriage problem", "divorce", "abuse", "diagnosed", "therapy",
            "my address", "phone number", "private"
        ]

        guard privateSignals.contains(where: { lower.contains($0) }) else { return [] }
        return [
            DetectedPostContextItem(
                id: UUID(),
                type: .audienceRisk,
                displayText: "Privacy check",
                rawValue: "personal_context"
            )
        ]
    }

    private func deduplicated(_ items: [DetectedPostContextItem]) -> [DetectedPostContextItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = "\(item.type)-\(item.rawValue.lowercased())"
            return seen.insert(key).inserted
        }
    }
}
