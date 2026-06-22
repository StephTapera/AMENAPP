// BereanScriptureConnectorService.swift
// AMENAPP — Berean Spiritual Intelligence Layer (Wave 1 → LIVE)
//
// Connector over Tier A scripture sources. All public methods guard on
// `bereanTierAConnectorsEnabled` and fail-closed (return nil) when OFF.
//
// LIVE PATH: the Free Use Bible API (https://bible.helloao.org) — public domain
// (BSB) + public-domain KJV/WEB. No API key, no server proxy, safe to call
// directly from the client. Proxied sources (API.Bible) remain disabled until
// their server proxy + key are deployed (registry.enabled == false for those).

import Foundation

@MainActor
final class BereanScriptureConnectorService: ObservableObject {

    static let shared = BereanScriptureConnectorService()

    private let registry = BereanTierARegistry.shared

    /// Lightweight in-memory chapter cache (public-domain text is cacheable).
    /// Keyed by "<translationId>/<usfm>/<chapter>".
    private var chapterCache: [String: [Int: String]] = [:]

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: cfg)
    }()

    // MARK: - Public Result

    /// A resolved verse with the text and the attribution required for display.
    struct VerseResult: Sendable, Equatable {
        let reference: String      // normalized, e.g. "John 3:16"
        let translation: String    // requested code, e.g. "BSB"
        let text: String
        let attribution: String
        let sourceId: String
    }

    // MARK: - Verse Fetch (LIVE)

    /// Fetches real verse text for `reference` in `translation`.
    /// Returns nil when connectors are OFF (fail-closed), when no active source
    /// supports the translation, when the reference can't be parsed, or on any
    /// network/parse error (callers treat nil as "unavailable", never fabricate).
    func fetchVerse(reference: String, translation: String = "BSB") async -> VerseResult? {
        guard AMENFeatureFlags.shared.bereanTierAConnectorsEnabled else {
            dlog("[BereanScriptureConnector] connectors OFF — nil for \(reference)")
            return nil
        }

        guard let source = activeSource(for: translation) else {
            dlog("[BereanScriptureConnector] no active source for '\(translation)'")
            return nil
        }

        // Proxied sources must NOT be called directly from the client.
        guard !source.requiresProxiedKey else {
            dlog("[BereanScriptureConnector] '\(source.id)' requires server proxy — skipping client call")
            return nil
        }

        guard let parsed = Self.parse(reference: reference) else {
            dlog("[BereanScriptureConnector] unparseable reference '\(reference)'")
            return nil
        }
        guard let usfm = Self.usfmCode(for: parsed.book) else {
            dlog("[BereanScriptureConnector] unknown book '\(parsed.book)'")
            return nil
        }

        let translationId = Self.helloAOTranslationId(for: translation)

        guard let verseText = await chapterVerse(
            translationId: translationId,
            usfm: usfm,
            chapter: parsed.chapter,
            verse: parsed.verse
        ) else {
            return nil
        }

        let normalizedRef = "\(Self.canonicalName(for: usfm) ?? parsed.book) \(parsed.chapter):\(parsed.verse)"
        return VerseResult(
            reference: normalizedRef,
            translation: translation,
            text: verseText,
            attribution: attribution(for: source),
            sourceId: source.id
        )
    }

    // MARK: - Attribution

    func attribution(for source: ScriptureSource) -> String {
        source.license.attributionText ?? source.license.name
    }

    /// The source descriptor that will service this translation (or nil).
    func activeSource(for translation: String) -> ScriptureSource? {
        registry.activeSources.first { $0.availableTranslations.contains(translation) }
            ?? registry.activeSources.first
    }

    // MARK: - Network + Decode

    /// Fetches a chapter (cached) and returns the requested verse text, or nil.
    private func chapterVerse(translationId: String, usfm: String, chapter: Int, verse: Int) async -> String? {
        let cacheKey = "\(translationId)/\(usfm)/\(chapter)"
        if let cached = chapterCache[cacheKey] {
            return cached[verse]
        }

        guard let url = URL(string: "https://bible.helloao.org/api/\(translationId)/\(usfm)/\(chapter).json") else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                dlog("[BereanScriptureConnector] non-2xx for \(url.absoluteString)")
                return nil
            }
            let decoded = try JSONDecoder().decode(HelloAOChapterResponse.self, from: data)
            var verses: [Int: String] = [:]
            for item in decoded.chapter.content where item.type == "verse" {
                guard let number = item.number else { continue }
                let text = item.flattenedText()
                if !text.isEmpty { verses[number] = text }
            }
            chapterCache[cacheKey] = verses
            return verses[verse]
        } catch {
            dlog("[BereanScriptureConnector] fetch/parse error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Reference Parsing

    struct ParsedReference: Equatable { let book: String; let chapter: Int; let verse: Int }

    /// Parses "John 3:16", "1 John 2:5", "Song of Solomon 2:1" → (book, chapter, verse).
    /// A verse range ("John 3:16-17") resolves to the first verse.
    static func parse(reference: String) -> ParsedReference? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        // Capture: book (letters/spaces, optional leading digit), chapter, verse.
        let pattern = #"^([1-3]?\s?[A-Za-z][A-Za-z\s]*?)\s+(\d+):(\d+)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let bookR = Range(m.range(at: 1), in: trimmed),
              let chR = Range(m.range(at: 2), in: trimmed),
              let vR = Range(m.range(at: 3), in: trimmed),
              let chapter = Int(trimmed[chR]),
              let verse = Int(trimmed[vR]) else {
            return nil
        }
        let book = trimmed[bookR].trimmingCharacters(in: .whitespaces)
        return ParsedReference(book: book, chapter: chapter, verse: verse)
    }

    // MARK: - Translation Code Mapping

    /// Maps an AMEN translation code to the helloao translation ID.
    static func helloAOTranslationId(for code: String) -> String {
        switch code.uppercased() {
        case "BSB": return "BSB"
        case "KJV": return "eng_kjv"
        case "WEB": return "eng_web"
        default:    return "BSB"   // safe public-domain default
        }
    }

    // MARK: - Book → USFM

    static func usfmCode(for bookName: String) -> String? {
        let key = bookName.lowercased().replacingOccurrences(of: " ", with: "")
        return Self.bookMap[key]
    }

    static func canonicalName(for usfm: String) -> String? {
        Self.usfmToName[usfm]
    }

    /// USFM 3-letter codes keyed by normalized (lowercased, spaceless) book name + common aliases.
    private static let bookMap: [String: String] = {
        var m: [String: String] = [:]
        func add(_ usfm: String, _ names: [String]) { for n in names { m[n.lowercased().replacingOccurrences(of: " ", with: "")] = usfm } }
        add("GEN", ["Genesis", "Gen"]);            add("EXO", ["Exodus", "Exo", "Ex"])
        add("LEV", ["Leviticus", "Lev"]);          add("NUM", ["Numbers", "Num"])
        add("DEU", ["Deuteronomy", "Deut", "Deu"]); add("JOS", ["Joshua", "Josh"])
        add("JDG", ["Judges", "Judg"]);            add("RUT", ["Ruth"])
        add("1SA", ["1 Samuel", "1Sam", "1 Sam"]); add("2SA", ["2 Samuel", "2Sam", "2 Sam"])
        add("1KI", ["1 Kings", "1Kings", "1 Kgs"]); add("2KI", ["2 Kings", "2Kings", "2 Kgs"])
        add("1CH", ["1 Chronicles", "1Chron", "1 Chr"]); add("2CH", ["2 Chronicles", "2Chron", "2 Chr"])
        add("EZR", ["Ezra"]);                      add("NEH", ["Nehemiah", "Neh"])
        add("EST", ["Esther", "Est"]);             add("JOB", ["Job"])
        add("PSA", ["Psalms", "Psalm", "Ps"]);     add("PRO", ["Proverbs", "Prov"])
        add("ECC", ["Ecclesiastes", "Eccl"]);      add("SNG", ["Song of Solomon", "Song of Songs", "Song"])
        add("ISA", ["Isaiah", "Isa"]);             add("JER", ["Jeremiah", "Jer"])
        add("LAM", ["Lamentations", "Lam"]);       add("EZK", ["Ezekiel", "Ezek"])
        add("DAN", ["Daniel", "Dan"]);             add("HOS", ["Hosea", "Hos"])
        add("JOL", ["Joel"]);                      add("AMO", ["Amos"])
        add("OBA", ["Obadiah", "Obad"]);           add("JON", ["Jonah"])
        add("MIC", ["Micah", "Mic"]);              add("NAM", ["Nahum", "Nah"])
        add("HAB", ["Habakkuk", "Hab"]);           add("ZEP", ["Zephaniah", "Zeph"])
        add("HAG", ["Haggai", "Hag"]);             add("ZEC", ["Zechariah", "Zech"])
        add("MAL", ["Malachi", "Mal"]);            add("MAT", ["Matthew", "Matt", "Mt"])
        add("MRK", ["Mark", "Mk"]);                add("LUK", ["Luke", "Lk"])
        add("JHN", ["John", "Jn"]);                add("ACT", ["Acts"])
        add("ROM", ["Romans", "Rom"]);             add("1CO", ["1 Corinthians", "1Cor", "1 Cor"])
        add("2CO", ["2 Corinthians", "2Cor", "2 Cor"]); add("GAL", ["Galatians", "Gal"])
        add("EPH", ["Ephesians", "Eph"]);          add("PHP", ["Philippians", "Phil"])
        add("COL", ["Colossians", "Col"]);         add("1TH", ["1 Thessalonians", "1Thess", "1 Thess"])
        add("2TH", ["2 Thessalonians", "2Thess", "2 Thess"]); add("1TI", ["1 Timothy", "1Tim", "1 Tim"])
        add("2TI", ["2 Timothy", "2Tim", "2 Tim"]); add("TIT", ["Titus"])
        add("PHM", ["Philemon", "Philem"]);        add("HEB", ["Hebrews", "Heb"])
        add("JAS", ["James", "Jas"]);              add("1PE", ["1 Peter", "1Pet", "1 Pet"])
        add("2PE", ["2 Peter", "2Pet", "2 Pet"]);  add("1JN", ["1 John", "1John", "1 Jn"])
        add("2JN", ["2 John", "2John", "2 Jn"]);   add("3JN", ["3 John", "3John", "3 Jn"])
        add("JUD", ["Jude"]);                      add("REV", ["Revelation", "Rev"])
        return m
    }()

    private static let usfmToName: [String: String] = [
        "GEN": "Genesis", "EXO": "Exodus", "LEV": "Leviticus", "NUM": "Numbers", "DEU": "Deuteronomy",
        "JOS": "Joshua", "JDG": "Judges", "RUT": "Ruth", "1SA": "1 Samuel", "2SA": "2 Samuel",
        "1KI": "1 Kings", "2KI": "2 Kings", "1CH": "1 Chronicles", "2CH": "2 Chronicles", "EZR": "Ezra",
        "NEH": "Nehemiah", "EST": "Esther", "JOB": "Job", "PSA": "Psalm", "PRO": "Proverbs",
        "ECC": "Ecclesiastes", "SNG": "Song of Solomon", "ISA": "Isaiah", "JER": "Jeremiah", "LAM": "Lamentations",
        "EZK": "Ezekiel", "DAN": "Daniel", "HOS": "Hosea", "JOL": "Joel", "AMO": "Amos",
        "OBA": "Obadiah", "JON": "Jonah", "MIC": "Micah", "NAM": "Nahum", "HAB": "Habakkuk",
        "ZEP": "Zephaniah", "HAG": "Haggai", "ZEC": "Zechariah", "MAL": "Malachi", "MAT": "Matthew",
        "MRK": "Mark", "LUK": "Luke", "JHN": "John", "ACT": "Acts", "ROM": "Romans",
        "1CO": "1 Corinthians", "2CO": "2 Corinthians", "GAL": "Galatians", "EPH": "Ephesians", "PHP": "Philippians",
        "COL": "Colossians", "1TH": "1 Thessalonians", "2TH": "2 Thessalonians", "1TI": "1 Timothy", "2TI": "2 Timothy",
        "TIT": "Titus", "PHM": "Philemon", "HEB": "Hebrews", "JAS": "James", "1PE": "1 Peter",
        "2PE": "2 Peter", "1JN": "1 John", "2JN": "2 John", "3JN": "3 John", "JUD": "Jude", "REV": "Revelation",
    ]
}

// MARK: - helloao JSON models (minimal)

private struct HelloAOChapterResponse: Decodable {
    let chapter: HelloAOChapter
}

private struct HelloAOChapter: Decodable {
    let number: Int
    let content: [HelloAOContentItem]
}

/// A content item is either a heading, a verse, a line break, etc. Verse items
/// carry a `number` and a `content` array of strings and/or formatting objects.
private struct HelloAOContentItem: Decodable {
    let type: String
    let number: Int?
    let content: [HelloAOInline]?

    /// Joins the inline string fragments of a verse into plain text.
    func flattenedText() -> String {
        guard let content else { return "" }
        let parts: [String] = content.compactMap { inline in
            switch inline {
            case .text(let s): return s
            case .formatted(let s): return s
            case .other: return nil
            }
        }
        return parts.joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Inline fragments are usually bare strings, sometimes objects like
/// {"text":"..."} (poetry/words-of-Jesus) or {"noteId":..} (footnotes — dropped).
private enum HelloAOInline: Decodable {
    case text(String)
    case formatted(String)
    case other

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let s = try? single.decode(String.self) {
            self = .text(s); return
        }
        if let obj = try? single.decode(InlineObject.self), let t = obj.text {
            self = .formatted(t); return
        }
        self = .other
    }

    private struct InlineObject: Decodable { let text: String? }
}
