// ScriptureRefDetector.swift
// AMENAPP — Media/Save
//
// Detects scripture references in arbitrary text (e.g. "John 3:16", "Matt 5:3-12").
// Used by VerseTapLabel to make references tappable inline.

import Foundation

// MARK: - DetectedScriptureRef

/// A detected scripture reference and its location in the source string.
struct DetectedScriptureRef {
    /// The canonical reference string, e.g. "John 3:16" or "Genesis 1:1-3".
    var reference: String
    /// The location of the reference in the original source string.
    var range: Range<String.Index>
}

// MARK: - ScriptureRefDetector

struct ScriptureRefDetector {

    // MARK: Book name table

    /// Maps common abbreviations and full names to canonical short form.
    /// Pattern covers all 66 canonical Protestant books.
    private static let bookPattern: String = {
        let books = [
            // Old Testament
            "Genesis", "Gen", "Ge", "Gn",
            "Exodus", "Ex", "Exod",
            "Leviticus", "Lev", "Le", "Lv",
            "Numbers", "Num", "Nu", "Nm", "Nb",
            "Deuteronomy", "Deut", "De", "Dt",
            "Joshua", "Josh", "Jos", "Jsh",
            "Judges", "Judg", "Jdg", "Jg",
            "Ruth", "Rth", "Ru",
            "1\\s*Samuel", "1\\s*Sam", "1\\s*Sa", "1\\s*Sm",
            "2\\s*Samuel", "2\\s*Sam", "2\\s*Sa", "2\\s*Sm",
            "1\\s*Kings", "1\\s*Kgs", "1\\s*Ki",
            "2\\s*Kings", "2\\s*Kgs", "2\\s*Ki",
            "1\\s*Chronicles", "1\\s*Chr", "1\\s*Ch",
            "2\\s*Chronicles", "2\\s*Chr", "2\\s*Ch",
            "Ezra", "Ezr",
            "Nehemiah", "Neh", "Ne",
            "Esther", "Esth", "Est",
            "Job", "Jb",
            "Psalms", "Psalm", "Ps", "Psa",
            "Proverbs", "Prov", "Pro", "Prv",
            "Ecclesiastes", "Eccles", "Eccl", "Ec", "Qoh",
            "Song\\s+of\\s+Solomon", "Song\\s+of\\s+Songs", "Song", "SOS", "Sos", "SS",
            "Isaiah", "Isa", "Is",
            "Jeremiah", "Jer", "Je",
            "Lamentations", "Lam", "La",
            "Ezekiel", "Ezek", "Eze", "Ezk",
            "Daniel", "Dan", "Da", "Dn",
            "Hosea", "Hos", "Ho",
            "Joel", "Jl",
            "Amos", "Am",
            "Obadiah", "Obad", "Ob",
            "Jonah", "Jon", "Jnh",
            "Micah", "Mic", "Mi",
            "Nahum", "Nah", "Na",
            "Habakkuk", "Hab", "Hb",
            "Zephaniah", "Zeph", "Zep", "Zp",
            "Haggai", "Hag", "Hg",
            "Zechariah", "Zech", "Zec", "Zc",
            "Malachi", "Mal", "Ml",
            // New Testament
            "Matthew", "Matt", "Mt",
            "Mark", "Mk", "Mr",
            "Luke", "Lk", "Lu",
            "John", "Jn", "Joh",
            "Acts", "Ac",
            "Romans", "Rom", "Ro", "Rm",
            "1\\s*Corinthians", "1\\s*Cor", "1\\s*Co",
            "2\\s*Corinthians", "2\\s*Cor", "2\\s*Co",
            "Galatians", "Gal", "Ga",
            "Ephesians", "Eph",
            "Philippians", "Phil", "Php", "Pp",
            "Colossians", "Col",
            "1\\s*Thessalonians", "1\\s*Thess", "1\\s*Thes", "1\\s*Th",
            "2\\s*Thessalonians", "2\\s*Thess", "2\\s*Thes", "2\\s*Th",
            "1\\s*Timothy", "1\\s*Tim", "1\\s*Ti",
            "2\\s*Timothy", "2\\s*Tim", "2\\s*Ti",
            "Titus", "Tit",
            "Philemon", "Phlm", "Phm",
            "Hebrews", "Heb",
            "James", "Jas", "Jm",
            "1\\s*Peter", "1\\s*Pet", "1\\s*Pe", "1\\s*Pt",
            "2\\s*Peter", "2\\s*Pet", "2\\s*Pe", "2\\s*Pt",
            "1\\s*John", "1\\s*Jn", "1\\s*Jo",
            "2\\s*John", "2\\s*Jn", "2\\s*Jo",
            "3\\s*John", "3\\s*Jn", "3\\s*Jo",
            "Jude", "Jud",
            "Revelation", "Revelations", "Rev", "Re", "Rv",
        ]
        // Longest-first so the regex engine matches the most specific form
        return books.sorted { $0.count > $1.count }.joined(separator: "|")
    }()

    /// Full regex pattern: Book Chapter:Verse[-Verse] with optional trailing verse range.
    /// Anchored by word boundaries to avoid matching partial words.
    private static let pattern: String =
        "\\b(" + bookPattern + ")\\.?\\s+(\\d{1,3}):(\\d{1,3})(?:[-–](\\d{1,3}))?\\b"

    private static let regex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    // MARK: Public API

    /// Detects all scripture references in `text` and returns them in document order.
    /// Returns an empty array if the text contains none or the regex fails to compile.
    static func detect(in text: String) -> [DetectedScriptureRef] {
        guard let regex else { return [] }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: fullRange)

        return matches.compactMap { match -> DetectedScriptureRef? in
            guard let range = Range(match.range, in: text) else { return nil }
            let reference = String(text[range])
            return DetectedScriptureRef(reference: reference, range: range)
        }
    }
}
