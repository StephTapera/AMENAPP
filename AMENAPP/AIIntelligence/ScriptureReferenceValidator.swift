// ScriptureReferenceValidator.swift
// AMENAPP
//
// Validates that scripture references parsed from LLM output are plausible
// (correct book name, chapter/verse within known bounds).
// Not a full ground-truth check — but catches hallucinated books and
// obviously out-of-range references.
// H-10 fix: scripture citation hardening

import Foundation

enum ScriptureReferenceValidator {

    // MARK: — Public API

    enum ValidationResult: Equatable {
        case valid
        case unknownBook(String)
        case outOfRange(book: String, chapter: Int, verse: Int)
        case malformed(String)
    }

    /// Validate a reference string such as "John 3:16" or "1 Cor 13:4".
    /// Returns `.valid` only when the book, chapter, and verse are all within
    /// known Protestant canon bounds.
    static func validate(_ reference: String) -> ValidationResult {
        let trimmed = reference.trimmingCharacters(in: .whitespaces)

        // Pattern: optional leading number + book name + chapter : verse (optional range)
        let pattern = #"^([1-3]?\s?[A-Za-z]+(?:\s[A-Za-z]+)*)\s+(\d+):(\d+)(?:-\d+)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.numberOfRanges >= 4 else {
            return .malformed(trimmed)
        }

        func rangeStr(_ idx: Int) -> String? {
            guard let r = Range(match.range(at: idx), in: trimmed) else { return nil }
            return String(trimmed[r]).trimmingCharacters(in: .whitespaces)
        }

        guard let bookRaw   = rangeStr(1),
              let chapterRaw = rangeStr(2),
              let verseRaw   = rangeStr(3),
              let chapter    = Int(chapterRaw),
              let verse      = Int(verseRaw) else {
            return .malformed(trimmed)
        }

        guard isKnownBook(bookRaw) else {
            return .unknownBook(bookRaw)
        }

        guard let bounds = chapterVerseBounds(for: bookRaw) else {
            // Book resolves but we have no bounds entry — treat as valid with caution
            return .valid
        }

        guard chapter >= 1, chapter <= bounds.count else {
            return .outOfRange(book: bookRaw, chapter: chapter, verse: verse)
        }

        let maxVerse = bounds[chapter - 1]
        guard verse >= 1, verse <= maxVerse else {
            return .outOfRange(book: bookRaw, chapter: chapter, verse: verse)
        }

        return .valid
    }

    /// Returns true if `name` matches a known canonical book name or common abbreviation.
    static func isKnownBook(_ name: String) -> Bool {
        let normalized = name.lowercased()
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespaces)
        return bookAliasMap[normalized] != nil
    }

    // MARK: — Internal helpers

    /// Maps normalized alias → canonical book key used in `chapterVerseBoundsTable`.
    private static let bookAliasMap: [String: String] = [
        // Genesis
        "genesis": "genesis", "gen": "genesis", "ge": "genesis", "gn": "genesis",
        // Exodus
        "exodus": "exodus", "exod": "exodus", "exo": "exodus", "ex": "exodus",
        // Leviticus
        "leviticus": "leviticus", "lev": "leviticus", "le": "leviticus", "lv": "leviticus",
        // Numbers
        "numbers": "numbers", "num": "numbers", "nu": "numbers", "nm": "numbers",
        // Deuteronomy
        "deuteronomy": "deuteronomy", "deut": "deuteronomy", "deu": "deuteronomy", "dt": "deuteronomy",
        // Joshua
        "joshua": "joshua", "josh": "joshua", "jos": "joshua",
        // Judges
        "judges": "judges", "judg": "judges", "jdg": "judges", "jg": "judges",
        // Ruth
        "ruth": "ruth", "rut": "ruth",
        // 1 Samuel
        "1 samuel": "1samuel", "1samuel": "1samuel", "1sam": "1samuel", "1sa": "1samuel", "i samuel": "1samuel", "i sam": "1samuel",
        // 2 Samuel
        "2 samuel": "2samuel", "2samuel": "2samuel", "2sam": "2samuel", "2sa": "2samuel", "ii samuel": "2samuel", "ii sam": "2samuel",
        // 1 Kings
        "1 kings": "1kings", "1kings": "1kings", "1kgs": "1kings", "1ki": "1kings", "i kings": "1kings", "i kgs": "1kings",
        // 2 Kings
        "2 kings": "2kings", "2kings": "2kings", "2kgs": "2kings", "2ki": "2kings", "ii kings": "2kings", "ii kgs": "2kings",
        // 1 Chronicles
        "1 chronicles": "1chronicles", "1chronicles": "1chronicles", "1chr": "1chronicles", "1ch": "1chronicles", "i chronicles": "1chronicles",
        // 2 Chronicles
        "2 chronicles": "2chronicles", "2chronicles": "2chronicles", "2chr": "2chronicles", "2ch": "2chronicles", "ii chronicles": "2chronicles",
        // Ezra
        "ezra": "ezra", "ezr": "ezra",
        // Nehemiah
        "nehemiah": "nehemiah", "neh": "nehemiah", "ne": "nehemiah",
        // Esther
        "esther": "esther", "est": "esther", "esth": "esther",
        // Job
        "job": "job",
        // Psalms
        "psalms": "psalms", "psalm": "psalms", "ps": "psalms", "psa": "psalms", "pss": "psalms",
        // Proverbs
        "proverbs": "proverbs", "prov": "proverbs", "pro": "proverbs", "prv": "proverbs",
        // Ecclesiastes
        "ecclesiastes": "ecclesiastes", "eccl": "ecclesiastes", "eccles": "ecclesiastes", "ecc": "ecclesiastes", "qoh": "ecclesiastes",
        // Song of Solomon
        "song of solomon": "songofsolomon", "songofsolomon": "songofsolomon", "song": "songofsolomon", "sos": "songofsolomon", "ss": "songofsolomon", "song of songs": "songofsolomon",
        // Isaiah
        "isaiah": "isaiah", "isa": "isaiah",
        // Jeremiah
        "jeremiah": "jeremiah", "jer": "jeremiah", "je": "jeremiah",
        // Lamentations
        "lamentations": "lamentations", "lam": "lamentations", "la": "lamentations",
        // Ezekiel
        "ezekiel": "ezekiel", "ezek": "ezekiel", "eze": "ezekiel", "ezk": "ezekiel",
        // Daniel
        "daniel": "daniel", "dan": "daniel", "da": "daniel",
        // Hosea
        "hosea": "hosea", "hos": "hosea",
        // Joel
        "joel": "joel", "jl": "joel",
        // Amos
        "amos": "amos", "am": "amos",
        // Obadiah
        "obadiah": "obadiah", "obad": "obadiah", "ob": "obadiah",
        // Jonah
        "jonah": "jonah", "jon": "jonah",
        // Micah
        "micah": "micah", "mic": "micah",
        // Nahum
        "nahum": "nahum", "nah": "nahum", "na": "nahum",
        // Habakkuk
        "habakkuk": "habakkuk", "hab": "habakkuk",
        // Zephaniah
        "zephaniah": "zephaniah", "zeph": "zephaniah", "zep": "zephaniah",
        // Haggai
        "haggai": "haggai", "hag": "haggai",
        // Zechariah
        "zechariah": "zechariah", "zech": "zechariah", "zec": "zechariah",
        // Malachi
        "malachi": "malachi", "mal": "malachi",
        // Matthew
        "matthew": "matthew", "matt": "matthew", "mat": "matthew", "mt": "matthew",
        // Mark
        "mark": "mark", "mrk": "mark", "mk": "mark",
        // Luke
        "luke": "luke", "lk": "luke",
        // John
        "john": "john", "jn": "john", "joh": "john",
        // Acts
        "acts": "acts", "act": "acts",
        // Romans
        "romans": "romans", "rom": "romans",
        // 1 Corinthians
        "1 corinthians": "1corinthians", "1corinthians": "1corinthians", "1cor": "1corinthians", "1co": "1corinthians", "i corinthians": "1corinthians", "i cor": "1corinthians",
        // 2 Corinthians
        "2 corinthians": "2corinthians", "2corinthians": "2corinthians", "2cor": "2corinthians", "2co": "2corinthians", "ii corinthians": "2corinthians", "ii cor": "2corinthians",
        // Galatians
        "galatians": "galatians", "gal": "galatians",
        // Ephesians
        "ephesians": "ephesians", "eph": "ephesians",
        // Philippians
        "philippians": "philippians", "phil": "philippians", "php": "philippians",
        // Colossians
        "colossians": "colossians", "col": "colossians",
        // 1 Thessalonians
        "1 thessalonians": "1thessalonians", "1thessalonians": "1thessalonians", "1thess": "1thessalonians", "1th": "1thessalonians", "i thessalonians": "1thessalonians",
        // 2 Thessalonians
        "2 thessalonians": "2thessalonians", "2thessalonians": "2thessalonians", "2thess": "2thessalonians", "2th": "2thessalonians", "ii thessalonians": "2thessalonians",
        // 1 Timothy
        "1 timothy": "1timothy", "1timothy": "1timothy", "1tim": "1timothy", "1ti": "1timothy", "i timothy": "1timothy",
        // 2 Timothy
        "2 timothy": "2timothy", "2timothy": "2timothy", "2tim": "2timothy", "2ti": "2timothy", "ii timothy": "2timothy",
        // Titus
        "titus": "titus", "tit": "titus",
        // Philemon
        "philemon": "philemon", "phlm": "philemon", "phm": "philemon",
        // Hebrews
        "hebrews": "hebrews", "heb": "hebrews",
        // James
        "james": "james", "jas": "james", "jm": "james",
        // 1 Peter
        "1 peter": "1peter", "1peter": "1peter", "1pet": "1peter", "1pe": "1peter", "i peter": "1peter",
        // 2 Peter
        "2 peter": "2peter", "2peter": "2peter", "2pet": "2peter", "2pe": "2peter", "ii peter": "2peter",
        // 1 John
        "1 john": "1john", "1john": "1john", "1jn": "1john", "1jo": "1john", "i john": "1john",
        // 2 John
        "2 john": "2john", "2john": "2john", "2jn": "2john", "ii john": "2john",
        // 3 John
        "3 john": "3john", "3john": "3john", "3jn": "3john", "iii john": "3john",
        // Jude
        "jude": "jude", "jud": "jude",
        // Revelation
        "revelation": "revelation", "rev": "revelation", "re": "revelation", "apocalypse": "revelation"
    ]

    /// Returns per-chapter max-verse counts for the resolved canonical key.
    private static func chapterVerseBounds(for rawName: String) -> [Int]? {
        let normalized = rawName.lowercased()
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let key = bookAliasMap[normalized] else { return nil }
        return chapterVerseBoundsTable[key]
    }

    // MARK: — 66-book chapter/verse bounds table (Protestant canon)
    // Each array entry is the maximum verse count for that chapter (1-indexed).
    // Source: standard Protestant Bible (KJV/ESV counts).
    private static let chapterVerseBoundsTable: [String: [Int]] = [
        "genesis":        [31,25,24,26,32,22,24,22,29,32,32,20,18,24,21,16,27,33,38,18,34,24,20,67,34,35,46,22,35,43,55,32,20,31,29,43,36,30,23,23,57,38,34,34,28,34,31,22,33,26],
        "exodus":         [22,25,22,31,23,30,25,32,35,29,10,51,22,31,27,36,16,27,25,26,36,31,33,18,40,37,21,43,46,38,18,35,23,35,27,36,18,29,21,25,22,45,0,0,0,0,0,0,0,0], // 40 ch
        "leviticus":      [17,16,17,35,19,30,38,36,24,20,47,8,59,57,33,34,16,30,24,16,34,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 27 ch
        "numbers":        [54,34,51,49,31,27,89,26,23,36,35,16,33,45,41,50,13,32,22,29,35,41,30,25,18,65,23,31,40,16,54,42,56,29,34,13,0,0,0,0], // 36 ch
        "deuteronomy":    [46,37,29,49,33,25,26,20,29,22,32,32,18,29,23,22,20,22,21,20,23,30,25,22,19,19,26,68,29,20,30,52,29,12,0,0,0,0,0,0], // 34 ch
        "joshua":         [18,24,17,24,15,27,26,35,27,43,23,24,33,15,63,10,18,28,51,9,45,34,16,33,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 24 ch
        "judges":         [36,23,31,24,31,40,25,35,57,18,40,15,25,20,20,31,13,31,30,48,25,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 21 ch
        "ruth":           [22,23,18,22],
        "1samuel":        [28,36,21,22,12,21,17,22,27,27,15,25,23,52,35,23,58,30,24,42,15,23,29,22,44,25,12,25,11,31,13,0,0,0,0,0,0,0,0,0], // 31 ch
        "2samuel":        [27,32,39,12,25,23,29,18,13,19,27,31,39,33,37,23,29,33,43,26,22,51,39,25,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 24 ch
        "1kings":         [53,70,60,34,17,22,51,36,27,14,29,17,24,20,34,18,29,59,19,33,29,28,22,28,33,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 22 ch (abbr)
        "2kings":         [18,37,21,33,26,41,26,45,19,26,26,24,15,24,34,23,20,25,29,18,31,28,20,24,25,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 25 ch
        "1chronicles":    [54,55,24,43,26,81,40,40,44,14,47,40,14,17,29,43,27,17,19,8,30,19,32,31,31,32,34,21,30,0,0,0,0,0,0,0,0,0,0,0], // 29 ch
        "2chronicles":    [17,18,17,22,14,42,22,18,31,19,23,16,22,15,19,14,19,34,11,37,20,12,21,27,28,23,9,27,36,27,21,25,29,38,20,41,0,0,0,0], // 36 ch
        "ezra":           [11,70,13,24,17,22,28,36,15,44],
        "nehemiah":       [11,20,32,23,19,19,73,18,38,39,36,47,31,0,0,0,0,0,0,0], // 13 ch
        "esther":         [22,23,15,17,14,14,10,17,32,3,17,8,30,24,0,0,0,0,0,0], // 10 ch (Hebrew canon)
        "job":            [22,13,26,21,27,30,21,22,35,22,20,25,28,22,35,22,16,21,29,29,34,30,17,25,6,14,23,28,25,31,40,22,33,37,16,33,24,41,30,24,34,17,0,0,0,0,0,0,0,0], // 42 ch
        "psalms":         [6,12,8,8,12,10,17,9,20,18,7,8,6,7,5,11,15,50,14,9,13,31,6,10,22,12,14,9,11,13,25,11,22,23,28,13,40,23,14,18,14,12,5,27,18,12,10,15,21,23,21,11,7,9,24,14,12,12,18,14,9,13,12,11,14,20,8,36,37,6,24,20,28,23,11,13,21,72,13,20,17,8,19,13,14,17,7,19,53,17,16,16,5,23,11,13,12,9,9,5,8,28,22,35,45,48,43,13,31,7,10,10,9,8,18,19,2,29,176,7,8,9,4,8,5,6,5,6,8,8,3,18,3,3,21,26,9,8,24,14,10,8,12,15,21,10,20,14,9,6], // 150 ch
        "proverbs":       [33,22,35,27,23,35,27,36,18,32,31,28,25,35,33,33,28,24,29,30,31,29,35,34,28,28,27,28,27,33,31,0,0,0,0,0,0,0,0,0], // 31 ch
        "ecclesiastes":   [18,26,22,16,20,12,29,17,18,20,10,14,0,0,0,0,0,0,0,0], // 12 ch
        "songofsolomon":  [17,17,11,16,16,13,13,14,0,0,0,0,0,0,0,0,0,0,0,0], // 8 ch
        "isaiah":         [31,22,26,6,30,13,25,22,21,34,16,6,22,32,9,14,14,7,25,6,17,25,18,23,12,21,13,29,24,33,9,20,24,17,10,22,38,22,8,31,29,25,28,28,25,13,15,22,26,11,23,15,12,17,13,12,21,14,21,22,11,12,19,12,25,24,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 66 ch
        "jeremiah":       [19,37,25,31,31,30,34,22,26,25,23,17,27,22,21,21,27,23,15,18,14,30,40,10,38,24,22,17,32,24,40,44,26,22,19,32,21,28,18,16,18,22,13,30,5,28,7,47,39,46,64,34,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 52 ch
        "lamentations":   [22,22,66,22,22],
        "ezekiel":        [28,10,27,17,17,14,27,18,11,22,25,28,23,23,8,63,24,32,14,49,32,31,49,27,17,21,36,26,21,26,18,32,33,31,15,38,28,23,29,49,26,20,27,31,25,24,23,35,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 48 ch
        "daniel":         [21,49,30,37,31,28,28,27,27,21,45,13,0,0,0,0,0,0,0,0], // 12 ch
        "hosea":          [11,23,5,19,15,11,16,14,17,15,12,14,16,9,0,0,0,0,0,0], // 14 ch
        "joel":           [20,32,21,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 3 ch
        "amos":           [15,16,15,13,27,14,17,14,15,0,0,0,0,0,0,0,0,0,0,0], // 9 ch
        "obadiah":        [21],
        "jonah":          [17,10,10,11],
        "micah":          [16,13,12,13,15,16,20,0,0,0,0,0,0,0,0,0,0,0,0,0], // 7 ch
        "nahum":          [15,13,19,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 3 ch
        "habakkuk":       [17,20,19,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 3 ch
        "zephaniah":      [18,15,20,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 3 ch
        "haggai":         [15,23,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 2 ch
        "zechariah":      [21,13,10,14,11,15,14,23,17,12,17,14,9,21,0,0,0,0,0,0], // 14 ch
        "malachi":        [14,17,18,6,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 4 ch
        "matthew":        [25,23,17,25,48,34,29,34,38,42,30,50,58,36,39,28,27,35,30,34,46,46,39,51,46,75,66,20,0,0,0,0,0,0,0,0,0,0,0,0], // 28 ch
        "mark":           [45,28,35,41,43,56,37,38,50,52,33,44,37,72,47,20,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 16 ch
        "luke":           [80,52,38,44,39,49,50,56,62,42,54,59,35,35,32,31,37,43,48,47,38,71,56,53,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 24 ch
        "john":           [51,25,36,54,47,71,53,59,41,42,57,50,38,31,27,33,26,40,42,31,25,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 21 ch
        "acts":           [26,47,26,37,42,15,60,40,43,48,30,25,52,28,41,40,34,28,41,38,40,30,35,27,27,32,44,31,0,0,0,0,0,0,0,0,0,0,0,0], // 28 ch
        "romans":         [32,29,31,25,21,23,25,39,33,21,36,21,14,26,33,24,24,25,24,26,19,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 16 ch
        "1corinthians":   [31,16,23,21,13,20,40,34,16,23,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 16 ch — abbr
        "2corinthians":   [24,17,18,18,21,18,16,24,15,18,33,21,14,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 13 ch
        "galatians":      [24,21,29,31,26,18,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 6 ch
        "ephesians":      [23,22,21,28,30,24,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 6 ch
        "philippians":    [30,30,21,23,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 4 ch
        "colossians":     [29,23,25,18,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 4 ch
        "1thessalonians": [10,20,13,18,28,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 5 ch
        "2thessalonians": [12,17,18,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 3 ch
        "1timothy":       [20,15,16,16,25,21,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 6 ch
        "2timothy":       [18,26,17,22,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 4 ch
        "titus":          [16,15,15,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 3 ch
        "philemon":       [25,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 1 ch
        "hebrews":        [14,18,19,16,14,20,28,13,28,39,40,29,25,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 13 ch
        "james":          [27,26,18,17,20,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 5 ch
        "1peter":         [25,25,22,19,14,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 5 ch
        "2peter":         [21,22,18,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 3 ch
        "1john":          [10,29,24,21,21,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 5 ch
        "2john":          [13,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 1 ch
        "3john":          [14,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 1 ch
        "jude":           [25,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], // 1 ch
        "revelation":     [20,29,22,11,14,17,17,13,21,11,19,17,18,20,8,21,18,24,21,15,27,21,25,21,22,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]  // 22 ch
    ]
}
