//
//  ChurchNotesScriptureDetector.swift
//  AMENAPP
//
//  Feature 2: Scripture Auto-Detection
//  Regex-based detection of scripture references inside note content.
//  Detected references are auto-populated into note.scriptureReferences on save
//  and passed into ChurchNotesAIService for Berean context enrichment.
//

import Foundation

// MARK: - DetectedScripture

struct DetectedScripture: Identifiable, Codable, Hashable {
    var id: String
    var reference: String   // e.g. "John 3:16-18"
    var book: String        // e.g. "John"
    var chapter: Int        // e.g. 3
    var verseStart: Int?    // e.g. 16  (nil for whole-chapter refs like "Psalm 23")
    var verseEnd: Int?      // e.g. 18  (nil for single-verse refs)
    var rangeStart: Int     // character offset in source text
    var rangeEnd: Int       // character offset in source text

    /// Canonical normalised form, e.g. "1 Corinthians 13:4"
    var canonical: String { reference }

    init(
        reference: String,
        book: String,
        chapter: Int,
        verseStart: Int? = nil,
        verseEnd: Int? = nil,
        rangeStart: Int,
        rangeEnd: Int
    ) {
        self.id = UUID().uuidString
        self.reference = reference
        self.book = book
        self.chapter = chapter
        self.verseStart = verseStart
        self.verseEnd = verseEnd
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }
}

// MARK: - Scripture Detector

/// Detects Bible scripture references in free-form text using a multi-pass regex approach.
/// Handles numbered books, abbreviations, verse ranges, and whole-chapter references.
final class ChurchNotesScriptureDetector {

    static let shared = ChurchNotesScriptureDetector()
    private init() {}

    // MARK: - Book Aliases

    /// Maps common abbreviations and alternate spellings to canonical book names.
    private let bookAliases: [String: String] = {
        var d: [String: String] = [:]

        let entries: [(aliases: [String], canonical: String)] = [
            (["Gen", "Gn"], "Genesis"),
            (["Ex", "Exo", "Exod"], "Exodus"),
            (["Lev", "Lv"], "Leviticus"),
            (["Num", "Nm"], "Numbers"),
            (["Deut", "Dt", "Deu"], "Deuteronomy"),
            (["Josh", "Jos"], "Joshua"),
            (["Judg", "Jdg"], "Judges"),
            (["Ruth", "Ru"], "Ruth"),
            (["1 Sam", "1Sam", "1 Sa"], "1 Samuel"),
            (["2 Sam", "2Sam", "2 Sa"], "2 Samuel"),
            (["1 Kgs", "1Kgs", "1 Ki"], "1 Kings"),
            (["2 Kgs", "2Kgs", "2 Ki"], "2 Kings"),
            (["1 Chr", "1Chr", "1 Ch"], "1 Chronicles"),
            (["2 Chr", "2Chr", "2 Ch"], "2 Chronicles"),
            (["Ezra", "Ezr"], "Ezra"),
            (["Neh"], "Nehemiah"),
            (["Est", "Esth"], "Esther"),
            (["Ps", "Psa", "Psalm"], "Psalms"),
            (["Prov", "Prv", "Pr"], "Proverbs"),
            (["Eccl", "Ecc", "Qoh"], "Ecclesiastes"),
            (["Song", "SoS", "SS"], "Song of Solomon"),
            (["Isa", "Is"], "Isaiah"),
            (["Jer"], "Jeremiah"),
            (["Lam"], "Lamentations"),
            (["Ezek", "Eze"], "Ezekiel"),
            (["Dan", "Dn"], "Daniel"),
            (["Hos"], "Hosea"),
            (["Joel", "Jl"], "Joel"),
            (["Amos", "Am"], "Amos"),
            (["Obad", "Ob"], "Obadiah"),
            (["Jonah", "Jon"], "Jonah"),
            (["Mic"], "Micah"),
            (["Nah", "Na"], "Nahum"),
            (["Hab"], "Habakkuk"),
            (["Zeph", "Zep"], "Zephaniah"),
            (["Hag", "Hg"], "Haggai"),
            (["Zech", "Zec"], "Zechariah"),
            (["Mal"], "Malachi"),
            (["Matt", "Mt"], "Matthew"),
            (["Mk", "Mar"], "Mark"),
            (["Lk", "Lu"], "Luke"),
            (["Jn", "Jhn"], "John"),
            (["Acts", "Ac"], "Acts"),
            (["Rom", "Ro"], "Romans"),
            (["1 Cor", "1Cor", "1 Co"], "1 Corinthians"),
            (["2 Cor", "2Cor", "2 Co"], "2 Corinthians"),
            (["Gal", "Ga"], "Galatians"),
            (["Eph", "Ep"], "Ephesians"),
            (["Phil", "Php"], "Philippians"),
            (["Col"], "Colossians"),
            (["1 Thess", "1Thess", "1 Th"], "1 Thessalonians"),
            (["2 Thess", "2Thess", "2 Th"], "2 Thessalonians"),
            (["1 Tim", "1Tim"], "1 Timothy"),
            (["2 Tim", "2Tim"], "2 Timothy"),
            (["Titus", "Tit"], "Titus"),
            (["Phlm", "Phm"], "Philemon"),
            (["Heb"], "Hebrews"),
            (["Jas", "Jms"], "James"),
            (["1 Pet", "1Pet", "1 Pe"], "1 Peter"),
            (["2 Pet", "2Pet", "2 Pe"], "2 Peter"),
            (["1 Jn", "1Jn", "1 Jo"], "1 John"),
            (["2 Jn", "2Jn"], "2 John"),
            (["3 Jn", "3Jn"], "3 John"),
            (["Jude", "Jud"], "Jude"),
            (["Rev", "Rv", "Apoc"], "Revelation")
        ]

        for entry in entries {
            for alias in entry.aliases {
                d[alias.lowercased()] = entry.canonical
            }
        }
        return d
    }()

    // MARK: - Detection

    /// Primary entry point.
    /// Returns all detected scripture references found in `text`, deduplicated.
    func detectScriptureReferences(in text: String) -> [DetectedScripture] {
        var results: [DetectedScripture] = []

        // Pattern covers:
        //   Optional numbered prefix (1, 2, 3 + space)
        //   Book name (2+ letters)
        //   Chapter number
        //   Optional :verse(-verseEnd) suffix
        // Examples: "John 3:16", "1 Cor 13:4-8", "Psalm 23", "Rev 22:1-5"
        let pattern =
            #"(?<!\w)"# +                                  // not preceded by word char
            #"((?:[123]\s)?[A-Z][a-zA-Z]+\.?)\s+"# +      // book name
            #"(\d{1,3})"# +                                // chapter
            #"(?::(\d{1,3})(?:\s*[-–]\s*(\d{1,3}))?)?"#   // optional :verse or :verse-range

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }

            let fullRange     = match.range
            let bookRange     = match.range(at: 1)
            let chapterRange  = match.range(at: 2)
            let verseRange    = match.numberOfRanges > 3 ? match.range(at: 3) : NSRange(location: NSNotFound, length: 0)
            let verseEndRange = match.numberOfRanges > 4 ? match.range(at: 4) : NSRange(location: NSNotFound, length: 0)

            guard bookRange.location != NSNotFound,
                  chapterRange.location != NSNotFound else { continue }

            let rawBook   = nsText.substring(with: bookRange).trimmingCharacters(in: .whitespaces)
            let canonical = resolveBook(rawBook)

            guard let chapterNum = Int(nsText.substring(with: chapterRange)) else { continue }

            var verseStart: Int? = nil
            var verseEnd:   Int? = nil
            if verseRange.location != NSNotFound, verseRange.length > 0 {
                verseStart = Int(nsText.substring(with: verseRange))
            }
            if verseEndRange.location != NSNotFound, verseEndRange.length > 0 {
                verseEnd = Int(nsText.substring(with: verseEndRange))
            }

            let reference = buildReference(book: canonical, chapter: chapterNum,
                                           verseStart: verseStart, verseEnd: verseEnd)

            let detected = DetectedScripture(
                reference: reference,
                book: canonical,
                chapter: chapterNum,
                verseStart: verseStart,
                verseEnd: verseEnd,
                rangeStart: fullRange.location,
                rangeEnd: fullRange.location + fullRange.length
            )
            results.append(detected)
        }

        // Deduplicate by reference string, keeping first occurrence
        var seen = Set<String>()
        return results.filter { seen.insert($0.reference).inserted }
    }

    /// Convenience: returns just the reference strings (for note.scriptureReferences).
    func detectReferenceStrings(in text: String) -> [String] {
        detectScriptureReferences(in: text).map { $0.reference }
    }

    // MARK: - Helpers

    private func resolveBook(_ raw: String) -> String {
        let lower = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if let canonical = bookAliases[lower] {
            return canonical
        }
        // Try prefix matching for full names like "Matthew", "Genesis", etc.
        for (_, canonical) in bookAliases {
            if canonical.lowercased().hasPrefix(lower) && lower.count >= 3 {
                return canonical
            }
        }
        // Return the raw capitalised form if no alias found
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    private func buildReference(book: String, chapter: Int, verseStart: Int?, verseEnd: Int?) -> String {
        var ref = "\(book) \(chapter)"
        if let vs = verseStart {
            ref += ":\(vs)"
            if let ve = verseEnd {
                ref += "-\(ve)"
            }
        }
        return ref
    }
}

// MARK: - ChurchNotesAIService Integration Extension

extension ChurchNotesAIService {
    /// Detects scripture references in a note and returns them for Berean context.
    /// Called before sending notes to Claude so the model gets enriched context.
    func buildScriptureContext(for note: ChurchNote) -> String {
        let detector = ChurchNotesScriptureDetector.shared
        let allText  = [note.content, note.scripture ?? ""].joined(separator: " ")
        let refs     = detector.detectReferenceStrings(in: allText)

        guard !refs.isEmpty else { return "" }

        return "Referenced scriptures: " + refs.joined(separator: ", ") + "."
    }
}
