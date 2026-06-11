// ComposerIntentEngine.swift
// AMEN — On-device intent detection engine for the Adaptive Composer.
// All types conform to contracts frozen in AdaptiveComposerContracts.swift.
import Foundation

// MARK: - OnDeviceIntentEngine

final class OnDeviceIntentEngine: IntentEngine {

    func detect(in text: String, context: ComposerContext) async -> [IntentSuggestion] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var all: [IntentSuggestion] = []
        all += detectScripture(in: text)
        all += detectPrayer(in: text)
        all += detectDateTime(in: text)
        all += detectMusic(in: text)
        all += detectYouTube(in: text)
        all += detectVolunteer(in: text)
        all += detectGenericURL(in: text)
        all += detectGiving(in: text)
        all += detectBibleStudy(in: text)
        if context.isChurchMode {
            all += detectChurchSermon(in: text)
            all += detectChurchService(in: text)
        }
        // Deduplicate: keep highest-confidence suggestion per primaryTool
        var best: [ToolID: IntentSuggestion] = [:]
        for s in all {
            if let existing = best[s.primaryTool] {
                if s.confidence > existing.confidence { best[s.primaryTool] = s }
            } else {
                best[s.primaryTool] = s
            }
        }
        return Array(best.values.sorted { $0.confidence > $1.confidence }.prefix(3))
    }

    // MARK: - Scripture detector
    // 66-book table with common abbreviations. Longer strings are listed first
    // so the compiled regex alternation prefers the greedier match.
    private static let scriptureBookNames: [String] = [
        // Multi-word long forms first
        "Song of Solomon", "Song of Songs",
        "1 Thessalonians", "2 Thessalonians",
        "1 Corinthians",   "2 Corinthians",
        "1 Chronicles",    "2 Chronicles",
        "1 Timothy",       "2 Timothy",
        "Deuteronomy",
        "Lamentations",
        "Philippians",
        "Revelation",
        "Ecclesiastes",
        "Habakkuk",
        "Colossians",
        "Ephesians",
        "Galatians",
        "Hebrews",
        "Zephaniah",
        "Zechariah",
        "1 Samuel",  "2 Samuel",
        "1 Kings",   "2 Kings",
        "1 Peter",   "2 Peter",
        "1 John",    "2 John",    "3 John",
        "Proverbs",
        "Jeremiah",
        "Nehemiah",
        "Obadiah",
        "Philemon",
        "Ezekiel",
        "Numbers",
        "Matthew",
        "Romans",
        "Joshua",
        "Judges",
        "Daniel",
        "Isaiah",
        "Micah",
        "Nahum",
        "Haggai",
        "Jonah",
        "Hosea",
        "Amos",
        "Joel",
        "Acts",
        "Luke",
        "Mark",
        "John",
        "Ruth",
        "Ezra",
        "Esther",
        "James",
        "Titus",
        "Jude",
        "Malachi",
        "Psalms", "Psalm",
        "Genesis",
        "Exodus",
        "Leviticus",
        "Song",
        // Spaced abbreviations (longer before shorter)
        "1 Thess", "2 Thess",
        "1 Cor",   "2 Cor",
        "1 Chr",   "2 Chr",
        "1 Tim",   "2 Tim",
        "1 Sam",   "2 Sam",
        "1 Kgs",   "2 Kgs",
        "1 Pet",   "2 Pet",
        "1 Jn",    "2 Jn",    "3 Jn",
        // Concatenated abbreviations
        "1Thess", "2Thess",
        "1Cor",   "2Cor",
        "1Chr",   "2Chr",
        "1Tim",   "2Tim",
        "1Sam",   "2Sam",
        "1Kgs",   "2Kgs",
        "1Pet",   "2Pet",
        "1Jn",    "2Jn",    "3Jn",
        // Short abbreviations
        "Deut",
        "Phil",
        "Zeph",
        "Zech",
        "Eccl", "Ecc",
        "Neh",
        "Obad",
        "Ezek",
        "Hab",
        "Hag",
        "Rev",
        "Prov",
        "Jer",
        "Dan",
        "Isa",
        "Mic",
        "Nah",
        "Jon",
        "Hos",
        "Col",
        "Gal",
        "Eph",
        "Heb",
        "Lam",
        "Mal",
        "Gen",
        "Num",
        "Lev",
        "Psa", "Ps",
        "Jn",
        "Jas",
        "Ex", "Exod",
        "Josh",
        "Judg",
        "Matt",
        "Rom",
        "Philem",
        "SoS"
    ]

    // Built once at class load; nil only if the pattern is malformed (impossible
    // with a static string list, but the guard below keeps it safe).
    private static let scripturePattern: NSRegularExpression? = {
        // Sort longest-first so alternation is greedy on book names
        let sorted = Set(scriptureBookNames)   // deduplicate
            .sorted { $0.count > $1.count || ($0.count == $1.count && $0 < $1) }
        let escaped = sorted
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        // Pattern: word-boundary, book name, whitespace, chapter[:verse[-verse]]
        let pat = "(?:^|\\b)(" + escaped + ")\\s+\\d+(?::\\d+(?:-\\d+)?)?"
        return try? NSRegularExpression(pattern: pat, options: [.caseInsensitive])
    }()

    private func detectScripture(in text: String) -> [IntentSuggestion] {
        guard let regex = Self.scripturePattern else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        guard regex.firstMatch(in: text, range: range) != nil else { return [] }
        return [IntentSuggestion(
            id: UUID(),
            primaryTool: .bible,
            alternativeTools: [.discussionThread],
            label: "Insert Scripture Card",
            confidence: 0.95,
            triggerText: "scripture"
        )]
    }

    // MARK: - Prayer detector
    // Longer / more-specific phrases first so they match before shorter substrings.
    private static let prayerKeywords: [String] = [
        "please pray",
        "intercession needed",
        "keep in prayer",
        "lifting up",
        "lift up",
        "intercede",
        "intercess",
        "praying",
        "prayer",
        "pray"
    ]

    private func detectPrayer(in text: String) -> [IntentSuggestion] {
        let lower = text.lowercased()
        guard let hit = Self.prayerKeywords.first(where: { lower.contains($0) }) else { return [] }
        return [IntentSuggestion(
            id: UUID(),
            primaryTool: .prayerRequest,
            alternativeTools: [.anonymousPrayer, .prayerCircle],
            label: "Add Prayer Request",
            confidence: 0.9,
            triggerText: hit
        )]
    }

    // MARK: - Date / time detector (NSDataDetector)
    private static let dateDetector: NSDataDetector? =
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    private func detectDateTime(in text: String) -> [IntentSuggestion] {
        guard let detector = Self.dateDetector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        guard detector.firstMatch(in: text, range: range) != nil else { return [] }
        return [IntentSuggestion(
            id: UUID(),
            primaryTool: .event,
            alternativeTools: [.rsvpCard, .reminder, .directionsCard],
            label: "Create Event Card",
            confidence: 0.85,
            triggerText: "date detected"
        )]
    }

    // MARK: - Music detector
    private static let musicURLHosts: [String] = [
        "music.apple.com",
        "open.spotify.com",
        "spotify.com/track"
    ]
    private static let musicKeywords: [String] = [
        "listen to this",
        "listen to",
        "this song",
        "playing now",
        "worship",
        "song"
    ]

    private func detectMusic(in text: String) -> [IntentSuggestion] {
        let lower = text.lowercased()
        let urlHit = Self.musicURLHosts.first { lower.contains($0) }
        let kwHit  = Self.musicKeywords.first  { lower.contains($0) }
        guard urlHit != nil || kwHit != nil else { return [] }
        return [IntentSuggestion(
            id: UUID(),
            primaryTool: .music,
            alternativeTools: [.podcast],
            label: "Attach Music Card",
            confidence: urlHit != nil ? 0.95 : 0.8,
            triggerText: urlHit ?? kwHit ?? ""
        )]
    }

    // MARK: - YouTube / video detector
    // ToolID has no .youtube case; .video is the correct mapping.
    private static let videoURLHosts: [String] = [
        "youtube.com",
        "youtu.be",
        "vimeo.com"
    ]
    private static let videoKeywords: [String] = [
        "watch this",
        "check out this video",
        "video here"
    ]

    private func detectYouTube(in text: String) -> [IntentSuggestion] {
        let lower = text.lowercased()
        let urlHit = Self.videoURLHosts.first { lower.contains($0) }
        let kwHit  = Self.videoKeywords.first  { lower.contains($0) }
        guard urlHit != nil || kwHit != nil else { return [] }
        return [IntentSuggestion(
            id: UUID(),
            primaryTool: .video,
            alternativeTools: [.discussionThread],
            label: "Embed Video Card",
            confidence: urlHit != nil ? 0.95 : 0.75,
            triggerText: urlHit ?? kwHit ?? ""
        )]
    }

    // MARK: - Volunteer detector
    private static let volunteerKeywords: [String] = [
        "we need volunteers",
        "ministry opportunity",
        "sign up to",
        "volunteer",
        "serving",
        "serve",
        "help us",
        "sign up"
    ]

    private func detectVolunteer(in text: String) -> [IntentSuggestion] {
        let lower = text.lowercased()
        guard let hit = Self.volunteerKeywords.first(where: { lower.contains($0) }) else { return [] }
        return [IntentSuggestion(
            id: UUID(),
            primaryTool: .volunteerSignup,
            alternativeTools: [.ministryInterestForm],
            label: "Add Volunteer Signup",
            confidence: 0.85,
            triggerText: hit
        )]
    }

    // MARK: - Generic URL detector (NSDataDetector)
    // Skips URLs already claimed by the music or video detectors.
    private static let linkDetector: NSDataDetector? =
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private func detectGenericURL(in text: String) -> [IntentSuggestion] {
        guard let detector = Self.linkDetector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        guard let first = detector.matches(in: text, range: range).first,
              let url = first.url else { return [] }
        let host = url.host?.lowercased() ?? ""
        let alreadyCovered = (Self.musicURLHosts + Self.videoURLHosts)
            .contains { host.contains($0) }
        guard !alreadyCovered else { return [] }
        return [IntentSuggestion(
            id: UUID(),
            primaryTool: .link,
            alternativeTools: [],
            label: "Attach Link Preview",
            confidence: 0.9,
            triggerText: url.absoluteString
        )]
    }

    // MARK: - Giving / donation detector
    private static let givingKeywords: [String] = [
        "support the ministry",
        "donation",
        "offering",
        "tithe",
        "giving",
        "donate",
        "give"
    ]

    private func detectGiving(in text: String) -> [IntentSuggestion] {
        let lower = text.lowercased()
        guard let hit = Self.givingKeywords.first(where: { lower.contains($0) }) else { return [] }
        return [IntentSuggestion(
            id: UUID(),
            primaryTool: .donation,
            alternativeTools: [],
            label: "Add Giving Card",
            confidence: 0.9,
            triggerText: hit
        )]
    }

    // MARK: - Bible study detector
    private static let bibleStudyKeywords: [String] = [
        "devotional group",
        "bible study",
        "study group",
        "group study",
        "small group"
    ]

    private func detectBibleStudy(in text: String) -> [IntentSuggestion] {
        let lower = text.lowercased()
        guard let hit = Self.bibleStudyKeywords.first(where: { lower.contains($0) }) else { return [] }
        return [IntentSuggestion(
            id: UUID(),
            primaryTool: .bibleStudy,
            alternativeTools: [.discussionThread],
            label: "Attach Bible Study",
            confidence: 0.9,
            triggerText: hit
        )]
    }

    // MARK: - Church-mode: sermon detector
    private static let sermonKeywords: [String] = [
        "today's sermon",
        "pastor spoke",
        "preaching",
        "message",
        "sermon"
    ]

    private func detectChurchSermon(in text: String) -> [IntentSuggestion] {
        let lower = text.lowercased()
        guard let hit = Self.sermonKeywords.first(where: { lower.contains($0) }) else { return [] }
        return [IntentSuggestion(
            id: UUID(),
            primaryTool: .churchNote,
            alternativeTools: [.worshipSong, .teachingSeries],
            label: "Create Church Note",
            confidence: 0.9,
            triggerText: hit
        )]
    }

    // MARK: - Church-mode: service detector
    private static let serviceKeywords: [String] = [
        "sunday service",
        "church service",
        "worship service",
        "join us"
    ]

    private func detectChurchService(in text: String) -> [IntentSuggestion] {
        let lower = text.lowercased()
        guard let hit = Self.serviceKeywords.first(where: { lower.contains($0) }) else { return [] }
        return [IntentSuggestion(
            id: UUID(),
            primaryTool: .event,
            alternativeTools: [.rsvpCard, .directionsCard],
            label: "Create Service Event",
            confidence: 0.9,
            triggerText: hit
        )]
    }
}

// MARK: - IntentDetectorFixtures
// Positive cases must produce at least one IntentSuggestion with the expected
// primaryTool. Negative cases must produce an empty array (no match).
struct IntentDetectorFixtures {

    struct Scripture {
        static let positive: [String] = [
            "Just read John 3:16",
            "1 Cor 13:4-7 is love",
            "Psalm 23 comforts me",
            "Genesis 1:1 in the beginning",
            "Rev 22:20 maranatha"
        ]
        static let negative: [String] = [
            "Let's grab coffee",
            "Great weather today",
            "Happy birthday",
            "I love pizza",
            "See you soon"
        ]
    }

    struct Prayer {
        static let positive: [String] = [
            "Please pray for my mom",
            "Can we lift up the Johnsons",
            "I've been praying a lot",
            "Intercession needed for our team",
            "Keep my friend in prayer"
        ]
        static let negative: [String] = [
            "What's for dinner",
            "The game was great",
            "New phone day",
            "She's so talented",
            "That movie was great"
        ]
    }

    struct Event {
        static let positive: [String] = [
            "Sunday at 10am",
            "Meeting Thursday at 7pm",
            "Tonight at 6",
            "January 15th conference",
            "Next Saturday morning"
        ]
        static let negative: [String] = [
            "I love worship music",
            "God is faithful always",
            "Scripture reading was great",
            "Praying for revival",
            "Check this out"
        ]
    }

    struct Music {
        static let positive: [String] = [
            "Listen to this worship song",
            "https://music.apple.com/album/123",
            "open.spotify.com/track/abc",
            "This song is powerful",
            "Playing now: Goodness of God"
        ]
        static let negative: [String] = [
            "Looking forward to Sunday",
            "Grateful for today",
            "Read the Bible daily",
            "Donate to the fund",
            "Volunteering this week"
        ]
    }

    struct Giving {
        static let positive: [String] = [
            "Please give to support the ministry",
            "Online offering is now open",
            "Don't forget your tithe",
            "Donate here to the campaign",
            "Giving is an act of worship"
        ]
        static let negative: [String] = [
            "See you at church",
            "Great sermon today",
            "Praying for you",
            "John 3:16",
            "Small group tonight"
        ]
    }
}
