//
//  SelahScriptureModels.swift
//  AMENAPP
//
//  Core data models for the Selah Scripture Reader. Everything here is a
//  plain value type — there is no service / network / Firestore coupling.
//  Providers (see BibleTranslationProvider.swift) own the loading.
//

import Foundation

// MARK: - Bible Book Catalog

/// Canonical metadata for one of the 66 books of the Protestant canon.
/// Books have a stable `id` so that persistence (last-read position, saved
/// verses) is decoupled from localized `displayName`.
struct BibleBook: Codable, Identifiable, Hashable {
    let id: String              // stable canonical id, e.g. "romans"
    let displayName: String     // "Romans"
    let abbreviation: String    // "Rom"
    let canonOrder: Int         // 1...66
    let chapterCount: Int
    let testament: Testament
    let aliases: [String]       // additional accepted spellings (parser input)

    enum Testament: String, Codable { case old, new }
}

extension BibleBook {
    /// The full canonical catalog (Protestant 66-book canon).
    static let all: [BibleBook] = [
        // MARK: Old Testament
        BibleBook(id: "genesis",      displayName: "Genesis",      abbreviation: "Gen",  canonOrder:  1, chapterCount: 50, testament: .old, aliases: ["ge", "gn"]),
        BibleBook(id: "exodus",       displayName: "Exodus",       abbreviation: "Ex",   canonOrder:  2, chapterCount: 40, testament: .old, aliases: ["exo", "exod"]),
        BibleBook(id: "leviticus",    displayName: "Leviticus",    abbreviation: "Lev",  canonOrder:  3, chapterCount: 27, testament: .old, aliases: ["lv"]),
        BibleBook(id: "numbers",      displayName: "Numbers",      abbreviation: "Num",  canonOrder:  4, chapterCount: 36, testament: .old, aliases: ["nm", "nb"]),
        BibleBook(id: "deuteronomy",  displayName: "Deuteronomy",  abbreviation: "Deut", canonOrder:  5, chapterCount: 34, testament: .old, aliases: ["dt"]),
        BibleBook(id: "joshua",       displayName: "Joshua",       abbreviation: "Josh", canonOrder:  6, chapterCount: 24, testament: .old, aliases: ["jos", "jsh"]),
        BibleBook(id: "judges",       displayName: "Judges",       abbreviation: "Judg", canonOrder:  7, chapterCount: 21, testament: .old, aliases: ["jdg", "jgs"]),
        BibleBook(id: "ruth",         displayName: "Ruth",         abbreviation: "Ruth", canonOrder:  8, chapterCount:  4, testament: .old, aliases: ["rth"]),
        BibleBook(id: "samuel1",      displayName: "1 Samuel",     abbreviation: "1 Sam", canonOrder:  9, chapterCount: 31, testament: .old, aliases: ["1sa", "1 sam", "i samuel", "first samuel"]),
        BibleBook(id: "samuel2",      displayName: "2 Samuel",     abbreviation: "2 Sam", canonOrder: 10, chapterCount: 24, testament: .old, aliases: ["2sa", "2 sam", "ii samuel", "second samuel"]),
        BibleBook(id: "kings1",       displayName: "1 Kings",      abbreviation: "1 Kgs", canonOrder: 11, chapterCount: 22, testament: .old, aliases: ["1ki", "1 ki", "i kings", "first kings"]),
        BibleBook(id: "kings2",       displayName: "2 Kings",      abbreviation: "2 Kgs", canonOrder: 12, chapterCount: 25, testament: .old, aliases: ["2ki", "2 ki", "ii kings", "second kings"]),
        BibleBook(id: "chronicles1",  displayName: "1 Chronicles", abbreviation: "1 Chr", canonOrder: 13, chapterCount: 29, testament: .old, aliases: ["1ch", "1 ch", "i chronicles", "first chronicles"]),
        BibleBook(id: "chronicles2",  displayName: "2 Chronicles", abbreviation: "2 Chr", canonOrder: 14, chapterCount: 36, testament: .old, aliases: ["2ch", "2 ch", "ii chronicles", "second chronicles"]),
        BibleBook(id: "ezra",         displayName: "Ezra",         abbreviation: "Ezra", canonOrder: 15, chapterCount: 10, testament: .old, aliases: ["ezr"]),
        BibleBook(id: "nehemiah",     displayName: "Nehemiah",     abbreviation: "Neh",  canonOrder: 16, chapterCount: 13, testament: .old, aliases: ["ne"]),
        BibleBook(id: "esther",       displayName: "Esther",       abbreviation: "Est",  canonOrder: 17, chapterCount: 10, testament: .old, aliases: ["es"]),
        BibleBook(id: "job",          displayName: "Job",          abbreviation: "Job",  canonOrder: 18, chapterCount: 42, testament: .old, aliases: ["jb"]),
        BibleBook(id: "psalms",       displayName: "Psalms",       abbreviation: "Ps",   canonOrder: 19, chapterCount: 150, testament: .old, aliases: ["psalm", "psa", "pslm"]),
        BibleBook(id: "proverbs",     displayName: "Proverbs",     abbreviation: "Prov", canonOrder: 20, chapterCount: 31, testament: .old, aliases: ["pr", "pro", "prv"]),
        BibleBook(id: "ecclesiastes", displayName: "Ecclesiastes", abbreviation: "Eccl", canonOrder: 21, chapterCount: 12, testament: .old, aliases: ["ec", "ecc"]),
        BibleBook(id: "songOfSolomon", displayName: "Song of Solomon", abbreviation: "Song", canonOrder: 22, chapterCount: 8, testament: .old, aliases: ["song", "sos", "canticle", "canticles", "song of songs"]),
        BibleBook(id: "isaiah",       displayName: "Isaiah",       abbreviation: "Isa",  canonOrder: 23, chapterCount: 66, testament: .old, aliases: ["is"]),
        BibleBook(id: "jeremiah",     displayName: "Jeremiah",     abbreviation: "Jer",  canonOrder: 24, chapterCount: 52, testament: .old, aliases: ["je", "jr"]),
        BibleBook(id: "lamentations", displayName: "Lamentations", abbreviation: "Lam",  canonOrder: 25, chapterCount:  5, testament: .old, aliases: ["la"]),
        BibleBook(id: "ezekiel",      displayName: "Ezekiel",      abbreviation: "Ezek", canonOrder: 26, chapterCount: 48, testament: .old, aliases: ["eze", "ezk"]),
        BibleBook(id: "daniel",       displayName: "Daniel",       abbreviation: "Dan",  canonOrder: 27, chapterCount: 12, testament: .old, aliases: ["da"]),
        BibleBook(id: "hosea",        displayName: "Hosea",        abbreviation: "Hos",  canonOrder: 28, chapterCount: 14, testament: .old, aliases: ["ho"]),
        BibleBook(id: "joel",         displayName: "Joel",         abbreviation: "Joel", canonOrder: 29, chapterCount:  3, testament: .old, aliases: ["jl"]),
        BibleBook(id: "amos",         displayName: "Amos",         abbreviation: "Am",   canonOrder: 30, chapterCount:  9, testament: .old, aliases: ["amo"]),
        BibleBook(id: "obadiah",      displayName: "Obadiah",      abbreviation: "Obad", canonOrder: 31, chapterCount:  1, testament: .old, aliases: ["ob"]),
        BibleBook(id: "jonah",        displayName: "Jonah",        abbreviation: "Jonah", canonOrder: 32, chapterCount: 4, testament: .old, aliases: ["jon", "jnh"]),
        BibleBook(id: "micah",        displayName: "Micah",        abbreviation: "Mic",  canonOrder: 33, chapterCount:  7, testament: .old, aliases: ["mi"]),
        BibleBook(id: "nahum",        displayName: "Nahum",        abbreviation: "Nah",  canonOrder: 34, chapterCount:  3, testament: .old, aliases: ["na"]),
        BibleBook(id: "habakkuk",     displayName: "Habakkuk",     abbreviation: "Hab",  canonOrder: 35, chapterCount:  3, testament: .old, aliases: ["hb"]),
        BibleBook(id: "zephaniah",    displayName: "Zephaniah",    abbreviation: "Zeph", canonOrder: 36, chapterCount:  3, testament: .old, aliases: ["zep", "zp"]),
        BibleBook(id: "haggai",       displayName: "Haggai",       abbreviation: "Hag",  canonOrder: 37, chapterCount:  2, testament: .old, aliases: ["hg"]),
        BibleBook(id: "zechariah",    displayName: "Zechariah",    abbreviation: "Zech", canonOrder: 38, chapterCount: 14, testament: .old, aliases: ["zec", "zc"]),
        BibleBook(id: "malachi",      displayName: "Malachi",      abbreviation: "Mal",  canonOrder: 39, chapterCount:  4, testament: .old, aliases: ["ml"]),

        // MARK: New Testament
        BibleBook(id: "matthew",      displayName: "Matthew",      abbreviation: "Matt", canonOrder: 40, chapterCount: 28, testament: .new, aliases: ["mt"]),
        BibleBook(id: "mark",         displayName: "Mark",         abbreviation: "Mark", canonOrder: 41, chapterCount: 16, testament: .new, aliases: ["mk", "mrk"]),
        BibleBook(id: "luke",         displayName: "Luke",         abbreviation: "Luke", canonOrder: 42, chapterCount: 24, testament: .new, aliases: ["lk", "luk"]),
        BibleBook(id: "john",         displayName: "John",         abbreviation: "John", canonOrder: 43, chapterCount: 21, testament: .new, aliases: ["jn", "jhn"]),
        BibleBook(id: "acts",         displayName: "Acts",         abbreviation: "Acts", canonOrder: 44, chapterCount: 28, testament: .new, aliases: ["ac"]),
        BibleBook(id: "romans",       displayName: "Romans",       abbreviation: "Rom",  canonOrder: 45, chapterCount: 16, testament: .new, aliases: ["ro", "rm"]),
        BibleBook(id: "corinthians1", displayName: "1 Corinthians", abbreviation: "1 Cor", canonOrder: 46, chapterCount: 16, testament: .new, aliases: ["1co", "1 cor", "i corinthians", "first corinthians"]),
        BibleBook(id: "corinthians2", displayName: "2 Corinthians", abbreviation: "2 Cor", canonOrder: 47, chapterCount: 13, testament: .new, aliases: ["2co", "2 cor", "ii corinthians", "second corinthians"]),
        BibleBook(id: "galatians",    displayName: "Galatians",    abbreviation: "Gal",  canonOrder: 48, chapterCount:  6, testament: .new, aliases: ["ga"]),
        BibleBook(id: "ephesians",    displayName: "Ephesians",    abbreviation: "Eph",  canonOrder: 49, chapterCount:  6, testament: .new, aliases: ["ephes"]),
        BibleBook(id: "philippians",  displayName: "Philippians",  abbreviation: "Phil", canonOrder: 50, chapterCount:  4, testament: .new, aliases: ["php", "pp"]),
        BibleBook(id: "colossians",   displayName: "Colossians",   abbreviation: "Col",  canonOrder: 51, chapterCount:  4, testament: .new, aliases: ["co"]),
        BibleBook(id: "thessalonians1", displayName: "1 Thessalonians", abbreviation: "1 Thess", canonOrder: 52, chapterCount: 5, testament: .new, aliases: ["1th", "1 thess", "i thessalonians", "first thessalonians"]),
        BibleBook(id: "thessalonians2", displayName: "2 Thessalonians", abbreviation: "2 Thess", canonOrder: 53, chapterCount: 3, testament: .new, aliases: ["2th", "2 thess", "ii thessalonians", "second thessalonians"]),
        BibleBook(id: "timothy1",     displayName: "1 Timothy",    abbreviation: "1 Tim", canonOrder: 54, chapterCount:  6, testament: .new, aliases: ["1ti", "1 tim", "i timothy", "first timothy"]),
        BibleBook(id: "timothy2",     displayName: "2 Timothy",    abbreviation: "2 Tim", canonOrder: 55, chapterCount:  4, testament: .new, aliases: ["2ti", "2 tim", "ii timothy", "second timothy"]),
        BibleBook(id: "titus",        displayName: "Titus",        abbreviation: "Titus", canonOrder: 56, chapterCount:  3, testament: .new, aliases: ["ti"]),
        BibleBook(id: "philemon",     displayName: "Philemon",     abbreviation: "Phlm", canonOrder: 57, chapterCount:  1, testament: .new, aliases: ["phm"]),
        BibleBook(id: "hebrews",      displayName: "Hebrews",      abbreviation: "Heb",  canonOrder: 58, chapterCount: 13, testament: .new, aliases: ["he"]),
        BibleBook(id: "james",        displayName: "James",        abbreviation: "Jas",  canonOrder: 59, chapterCount:  5, testament: .new, aliases: ["jm"]),
        BibleBook(id: "peter1",       displayName: "1 Peter",      abbreviation: "1 Pet", canonOrder: 60, chapterCount:  5, testament: .new, aliases: ["1pe", "1 pet", "i peter", "first peter"]),
        BibleBook(id: "peter2",       displayName: "2 Peter",      abbreviation: "2 Pet", canonOrder: 61, chapterCount:  3, testament: .new, aliases: ["2pe", "2 pet", "ii peter", "second peter"]),
        BibleBook(id: "john1",        displayName: "1 John",       abbreviation: "1 Jn",  canonOrder: 62, chapterCount:  5, testament: .new, aliases: ["1jn", "1 jn", "i john", "first john"]),
        BibleBook(id: "john2",        displayName: "2 John",       abbreviation: "2 Jn",  canonOrder: 63, chapterCount:  1, testament: .new, aliases: ["2jn", "2 jn", "ii john", "second john"]),
        BibleBook(id: "john3",        displayName: "3 John",       abbreviation: "3 Jn",  canonOrder: 64, chapterCount:  1, testament: .new, aliases: ["3jn", "3 jn", "iii john", "third john"]),
        BibleBook(id: "jude",         displayName: "Jude",         abbreviation: "Jude", canonOrder: 65, chapterCount:  1, testament: .new, aliases: ["jud"]),
        BibleBook(id: "revelation",   displayName: "Revelation",   abbreviation: "Rev",  canonOrder: 66, chapterCount: 22, testament: .new, aliases: ["re", "apocalypse", "the revelation"]),
    ]

    /// Lookup by canonical id.
    static func find(id: String) -> BibleBook? {
        all.first { $0.id == id }
    }
}

// MARK: - Scripture Reference

/// A parsed scripture address: book + chapter, with optional verse range.
struct ScriptureReference: Equatable, Hashable, Codable {
    /// Canonical `BibleBook.id`.
    let bookId: String
    let chapter: Int
    /// `nil` => whole chapter.
    let startVerse: Int?
    /// `nil` and `startVerse != nil` => single verse.
    let endVerse: Int?

    var book: BibleBook? { BibleBook.find(id: bookId) }

    var isWholeChapter: Bool { startVerse == nil }

    var isSingleVerse: Bool { startVerse != nil && (endVerse == nil || endVerse == startVerse) }

    /// "Romans 5", "Romans 5:3", "Romans 5:3-5"
    var displayString: String {
        let name = book?.displayName ?? bookId.capitalized
        guard let start = startVerse else { return "\(name) \(chapter)" }
        if let end = endVerse, end != start { return "\(name) \(chapter):\(start)-\(end)" }
        return "\(name) \(chapter):\(start)"
    }
}

/// Alias used by the Selah reader surfaces (SelahScriptureReaderView, previews, etc.)
typealias SelahScriptureReference = ScriptureReference

// MARK: - Translation

/// A Bible translation identifier + license metadata. License is honest
/// metadata only — runtime providers are responsible for refusing to ship
/// copyrighted text without authorization.
struct SelahBibleTranslation: Codable, Identifiable, Hashable {
    let id: String              // "kjv", "esv", ...
    let displayName: String     // "King James Version"
    let abbreviation: String    // "KJV"
    let license: License

    enum License: String, Codable {
        /// Public domain — safe to bundle locally.
        case publicDomain
        /// Licensed under a commercial agreement; requires a remote provider
        /// with valid credentials. Never bundled.
        case licensed
        /// Synthetic; only safe for unit tests / DEBUG builds.
        case mock
    }
}

extension SelahBibleTranslation {
    // Public-domain / open-license — safe to render in-app (AMEN-CONTENT-001).
    static let kjv  = SelahBibleTranslation(id: "kjv",  displayName: "King James Version",      abbreviation: "KJV",  license: .publicDomain)
    static let web  = SelahBibleTranslation(id: "web",  displayName: "World English Bible",      abbreviation: "WEB",  license: .publicDomain)
    static let bsb  = SelahBibleTranslation(id: "bsb",  displayName: "Berean Study Bible",       abbreviation: "BSB",  license: .publicDomain)
    static let nkjv = SelahBibleTranslation(id: "nkjv", displayName: "New King James Version",   abbreviation: "NKJV", license: .licensed)
    static let csb  = SelahBibleTranslation(id: "csb",  displayName: "Christian Standard Bible", abbreviation: "CSB",  license: .licensed)

    // TODO(legal): restore once commercial licenses confirmed (AMEN-CONTENT-001).
    // NIV (Biblica), ESV (Crossway), NLT (Tyndale), NASB (Lockman Foundation) require paid licenses.
    static let esv  = SelahBibleTranslation(id: "esv",  displayName: "English Standard Version", abbreviation: "ESV",  license: .licensed)
    static let niv  = SelahBibleTranslation(id: "niv",  displayName: "New International Version", abbreviation: "NIV", license: .licensed)
    static let nlt  = SelahBibleTranslation(id: "nlt",  displayName: "New Living Translation",    abbreviation: "NLT",  license: .licensed)
    static let nasb = SelahBibleTranslation(id: "nasb", displayName: "New American Standard Bible", abbreviation: "NASB", license: .licensed)

    /// Translations the app exposes in the UI. Restricted to public-domain / open-license.
    /// TODO(legal): Add .esv / .niv / .nlt / .nasb back when commercial licenses are in place (AMEN-CONTENT-001).
    static let known: [SelahBibleTranslation] = [.kjv, .web, .bsb]
}

// MARK: - Verse / Chapter

struct BibleVerse: Codable, Identifiable, Hashable {
    var id: String { "\(reference.bookId).\(reference.chapter).\(number)" }
    let reference: ScriptureReference   // address of THIS verse (chapter + startVerse=number)
    let number: Int
    let text: String
    var translation: String = ""
}

struct BibleChapter: Codable, Identifiable, Hashable {
    var id: String { "\(bookId).\(chapter).\(translationId)" }
    let bookId: String
    let chapter: Int
    let translationId: String
    let verses: [BibleVerse]
}

// MARK: - Reader State

struct LastReadScripturePosition: Codable, Equatable {
    let bookId: String
    let chapter: Int
    let verse: Int?
    let translationId: String
    let updatedAt: Date
}

struct ScriptureReaderPreferences: Codable, Equatable {
    var translationId: String
    var fontPointSize: CGFloat
    var pageTurnSoundEnabled: Bool

    static let defaults = ScriptureReaderPreferences(
        translationId: SelahBibleTranslation.kjv.id,
        fontPointSize: 17,
        pageTurnSoundEnabled: false
    )
}

// MARK: - Saved / Highlighted

struct SavedScripture: Codable, Identifiable, Hashable {
    let id: UUID
    let reference: ScriptureReference
    let translationId: String
    let savedAt: Date
    init(id: UUID = UUID(), reference: ScriptureReference, translationId: String, savedAt: Date = Date()) {
        self.id = id
        self.reference = reference
        self.translationId = translationId
        self.savedAt = savedAt
    }
}

struct ScriptureHighlight: Codable, Identifiable, Hashable {
    let id: UUID
    let reference: ScriptureReference
    let translationId: String
    let toneKey: String         // e.g. "wisdom", "peace", "prayer"
    let createdAt: Date
    init(id: UUID = UUID(), reference: ScriptureReference, translationId: String, toneKey: String, createdAt: Date = Date()) {
        self.id = id
        self.reference = reference
        self.translationId = translationId
        self.toneKey = toneKey
        self.createdAt = createdAt
    }
}

// MARK: - Search

struct SelahSearchResult: Identifiable, Equatable {
    let id: UUID
    let reference: ScriptureReference
    let translationId: String
    /// Short preview text, may be empty if provider doesn't expose snippets.
    let preview: String
    /// 0...1 — provider's confidence that this is a relevant match.
    let score: Double

    init(reference: ScriptureReference, translationId: String, preview: String = "", score: Double = 1.0) {
        self.id = UUID()
        self.reference = reference
        self.translationId = translationId
        self.preview = preview
        self.score = score
    }
}

// MARK: - Provider Availability

/// What the active provider can deliver for a given translation right now.
enum SelahBibleTranslationAvailability: Equatable {
    case available
    /// Translation is known but has no text available in this build (e.g.
    /// KJV data file not bundled, or remote provider has no credentials).
    case unavailable(reason: String)
}

// MARK: - Selah-prefixed typealiases (used by Selah reader surfaces)

typealias SelahBibleBook = BibleBook
typealias SelahBibleVerse = BibleVerse
typealias SelahBibleChapter = BibleChapter
typealias SelahScriptureSearchResult = SelahSearchResult
typealias SelahScriptureReaderPreferences = ScriptureReaderPreferences
typealias SelahLastReadScripturePosition = LastReadScripturePosition
typealias SelahSavedScripture = SavedScripture
typealias SelahScriptureHighlightEntry = ScriptureHighlight

// MARK: - BibleBook navigation

extension BibleBook {
    /// The next book in canonical order, or nil at Revelation.
    var nextBook: BibleBook? {
        BibleBook.all.first { $0.canonOrder == canonOrder + 1 }
    }
    /// The previous book in canonical order, or nil at Genesis.
    var previousBook: BibleBook? {
        BibleBook.all.first { $0.canonOrder == canonOrder - 1 }
    }
}
