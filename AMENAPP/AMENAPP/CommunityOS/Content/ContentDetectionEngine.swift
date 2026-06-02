// ContentDetectionEngine.swift
// AMEN App — Community Around Content OS
//
// Parses a raw URL or plain-text scripture reference and determines the
// ContentObjectKind + ContentSource, then assembles a fully-populated ContentObject.
//
// Detection is synchronous where possible (detectKind) so it can be used inline
// in UI without awaiting; the full `detect(from:)` path is async because it calls
// ContentMetadataExtractor, which performs a network request.

import Foundation

// MARK: - ContentDetectionEngine

/// Actor-isolated engine that classifies URLs and text into ContentObjects.
actor ContentDetectionEngine {

    // MARK: - Singleton

    static let shared = ContentDetectionEngine()
    private init() {}

    // MARK: - Bible book lookup

    /// All canonical Bible book names and common abbreviations, lower-cased for comparison.
    private let bibleBookTokens: Set<String> = [
        // Old Testament
        "genesis", "gen",
        "exodus", "exod", "exo",
        "leviticus", "lev",
        "numbers", "num",
        "deuteronomy", "deut", "deu",
        "joshua", "josh",
        "judges", "judg",
        "ruth",
        "samuel", "sam",
        "kings", "kgs",
        "chronicles", "chr",
        "ezra",
        "nehemiah", "neh",
        "esther", "esth",
        "job",
        "psalms", "psalm", "ps",
        "proverbs", "prov",
        "ecclesiastes", "eccl",
        "song", "songs", "song of solomon", "sos",
        "isaiah", "isa",
        "jeremiah", "jer",
        "lamentations", "lam",
        "ezekiel", "ezek",
        "daniel", "dan",
        "hosea", "hos",
        "joel",
        "amos",
        "obadiah", "obad",
        "jonah", "jon",
        "micah", "mic",
        "nahum", "nah",
        "habakkuk", "hab",
        "zephaniah", "zeph",
        "haggai", "hag",
        "zechariah", "zech",
        "malachi", "mal",
        // New Testament
        "matthew", "matt", "mt",
        "mark", "mk",
        "luke", "lk",
        "john", "jn",
        "acts",
        "romans", "rom",
        "corinthians", "cor",
        "galatians", "gal",
        "ephesians", "eph",
        "philippians", "phil",
        "colossians", "col",
        "thessalonians", "thess",
        "timothy", "tim",
        "titus", "tit",
        "philemon", "phlm",
        "hebrews", "heb",
        "james", "jas",
        "peter", "pet",
        "jude",
        "revelation", "rev"
    ]

    // MARK: - Bible reference regex

    /// Matches patterns like "John 3:16", "Romans 8:28", "john+3:16", "Gen. 1:1-3"
    private let bibleRefPattern = #"(?i)\b([1-3]\s*)?([A-Za-z]+\.?)\s*[+\s](\d{1,3})\s*[:\.](\d{1,3})(?:\s*[-–]\s*\d{1,3})?\b"#

    // MARK: - Public API

    /// Full async detection path: classifies the URL, fetches metadata, and returns a ContentObject.
    func detect(from rawURL: String) async -> ContentObject {
        guard CommunityOSFlagService.shared.isEnabled(.contentDetectionEngine) else {
            dlog("[ContentDetectionEngine] flag is OFF — returning minimal article object")
            return makeMinimalObject(rawURL: rawURL, kind: .article, source: .unknown)
        }

        let (kind, source) = detectKind(from: rawURL)
        let meta = await ContentMetadataExtractor.extract(from: rawURL)

        let title = meta.title
            ?? ContentMetadataExtractor.titleFallback(for: kind, rawURL: rawURL)
        let subtitle = meta.subtitle
        let thumbnailURL = meta.thumbnailURL

        // Extract scripture refs if this is a Bible verse kind.
        let linkedVerseRefs: [String] = (kind == .bibleVerse) ? extractVerseRefs(from: rawURL) : []

        let obj = ContentObject(
            id: UUID().uuidString,
            kind: kind,
            source: source,
            title: title,
            subtitle: subtitle,
            thumbnailURL: thumbnailURL,
            contentURL: rawURL,
            rawURL: rawURL,
            metadata: [:],
            communityScore: 0.0,
            discussionCount: 0,
            prayerCount: 0,
            testimonyCount: 0,
            spaceCount: 0,
            purityRating: .unreviewed,
            themes: [],
            linkedVerseRefs: linkedVerseRefs,
            createdAt: Date(),
            updatedAt: Date()
        )

        dlog("[ContentDetectionEngine] detect — rawURL=\(rawURL) → kind=\(kind.rawValue) source=\(source.rawValue) title=\(title)")
        return obj
    }

    /// Pure, synchronous URL classification.
    /// Returns a (kind, source) tuple. Safe to call from any context.
    func detectKind(from urlString: String) -> (ContentObjectKind, ContentSource) {
        // 1. Bible reference in plain text (non-URL).
        if !urlString.contains("://") && isBibleReference(urlString) {
            return (.bibleVerse, .bibleRef)
        }

        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else {
            // Still might be a plain-text scripture ref even without a scheme.
            if isBibleReference(urlString) {
                return (.bibleVerse, .bibleRef)
            }
            return (.article, .unknown)
        }

        let path = url.path.lowercased()
        let fullString = urlString.lowercased()

        // 2. Spotify
        if host.contains("open.spotify.com") || host == "spotify.com" {
            if path.contains("/episode") || path.contains("/show") {
                return (.podcast, .spotify)
            }
            return (.song, .spotify)
        }

        // 3. Apple Music
        if host.contains("music.apple.com") {
            if path.contains("/podcast") || path.contains("/show") {
                return (.podcast, .appleMusic)
            }
            return (.song, .appleMusic)
        }

        // 4. YouTube
        if host.contains("youtube.com") || host == "youtu.be" {
            return (.video, .youtube)
        }

        // 5. Podcast platforms
        if host.contains("podcasts.apple.com")
            || host.contains("anchor.fm")
            || host.contains("podcasts.google.com")
            || host.contains("podbean.com")
            || host.contains("buzzsprout.com")
            || host.contains("simplecast.com") {
            return (.podcast, .podcast)
        }

        // 6. Books
        if host.contains("amazon.com") || host.contains("amzn.to") {
            if path.contains("/dp/") || path.contains("/gp/product") {
                return (.book, .amazonBook)
            }
        }
        if host.contains("goodreads.com") || host.contains("amazon.com/books") {
            return (.book, .amazonBook)
        }

        // 7. Bible verse in URL (e.g. "john+3:16" or "Romans+8:28" in path or query)
        if containsBibleReferencePattern(in: fullString) {
            return (.bibleVerse, .bibleRef)
        }

        // 8. Sermon / church links (common sermon hosts)
        if host.contains("youversion.com")
            || host.contains("bible.com")
            || host.contains("sermonaudio.com")
            || host.contains("rightnowmedia.org") {
            if path.contains("/verse") || path.contains("/bible") {
                return (.bibleVerse, .bibleRef)
            }
            return (.sermon, .sermonLink)
        }

        // 9. Default — treat any surviving URL as an article.
        return (.article, .unknown)
    }

    /// Returns true if the given text looks like a scripture reference.
    /// Handles "John 3:16", "Romans 8:28-29", "gen. 1:1", "john+3:16".
    func isBibleReference(_ text: String) -> Bool {
        containsBibleReferencePattern(in: text)
    }

    // MARK: - Private helpers

    private func containsBibleReferencePattern(in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: bibleRefPattern, options: []) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        let match = regex.firstMatch(in: text, options: [], range: range)
        guard let m = match else { return false }

        // Validate the captured book token is actually a Bible book.
        let bookRange = Range(m.range(at: 2), in: text)
        if let bookToken = bookRange.map({ String(text[$0]).lowercased().trimmingCharacters(in: .punctuationCharacters) }) {
            return bibleBookTokens.contains(bookToken)
        }
        return false
    }

    /// Extracts all scripture references from a raw URL or text string.
    private func extractVerseRefs(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: bibleRefPattern, options: []) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        return matches.compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    /// Builds a minimal ContentObject for error / flag-off fallback paths.
    private func makeMinimalObject(rawURL: String, kind: ContentObjectKind, source: ContentSource) -> ContentObject {
        ContentObject(
            id: UUID().uuidString,
            kind: kind,
            source: source,
            title: ContentMetadataExtractor.titleFallback(for: kind, rawURL: rawURL),
            rawURL: rawURL,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
