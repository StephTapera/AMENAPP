// BereanContentConnector.swift
// AMEN App — Community Around Content OS / Berean Connector
//
// Maps ContentObjects to scripture passages using a curated local theme→verse table.
// All lookups are purely local — no network calls, no Firestore reads.
// Gated by CommunityOSFlag.bereanContentConnector.

import Foundation

// MARK: - BereanContentConnector

actor BereanContentConnector {

    // MARK: Shared

    static let shared = BereanContentConnector()

    // MARK: Cache

    private struct CacheEntry {
        let chips: [BereanScriptureChip]
        let expiresAt: Date
    }

    /// 10-minute TTL, keyed by ContentObject.id
    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 600

    // MARK: - Theme → Verse Table

    // swiftlint:disable line_length
    private let themeToVerses: [String: [BereanScriptureChip]] = [

        "trust": [
            BereanScriptureChip(
                reference: "Matthew 6:25-27",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Proverbs 3:5-6",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Psalm 56:3",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "faith": [
            BereanScriptureChip(
                reference: "Hebrews 11:1",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Matthew 17:20",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Romans 10:17",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "fear": [
            BereanScriptureChip(
                reference: "Isaiah 41:10",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Joshua 1:9",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "2 Timothy 1:7",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "worship": [
            BereanScriptureChip(
                reference: "John 4:24",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Psalm 150:6",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Romans 12:1",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "prayer": [
            BereanScriptureChip(
                reference: "Philippians 4:6-7",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Matthew 6:9-13",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "1 Thessalonians 5:17",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "hope": [
            BereanScriptureChip(
                reference: "Romans 15:13",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Jeremiah 29:11",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Romans 8:28",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "healing": [
            BereanScriptureChip(
                reference: "Psalm 147:3",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Isaiah 53:5",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "James 5:16",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "forgiveness": [
            BereanScriptureChip(
                reference: "Ephesians 4:32",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Colossians 3:13",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Matthew 6:14-15",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "grace": [
            BereanScriptureChip(
                reference: "Ephesians 2:8-9",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "2 Corinthians 12:9",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Titus 2:11",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "love": [
            BereanScriptureChip(
                reference: "1 Corinthians 13:4-7",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "John 3:16",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Romans 8:38-39",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "oceans": [
            BereanScriptureChip(
                reference: "Matthew 14:28-29",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Psalm 46:1-3",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Isaiah 43:2",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "water": [
            BereanScriptureChip(
                reference: "Isaiah 43:2",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Psalm 46:1-3",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "John 4:14",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "waves": [
            BereanScriptureChip(
                reference: "Matthew 14:28-29",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Psalm 46:1-3",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Isaiah 43:2",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "goodness": [
            BereanScriptureChip(
                reference: "Psalm 23:6",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Romans 8:28",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Psalm 34:8",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "leadership": [
            BereanScriptureChip(
                reference: "Matthew 20:26",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Proverbs 11:14",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "1 Peter 5:2-3",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "recovery": [
            BereanScriptureChip(
                reference: "Philippians 4:13",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "2 Corinthians 5:17",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Romans 7:18-19",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "addiction": [
            BereanScriptureChip(
                reference: "Philippians 4:13",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "2 Corinthians 5:17",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Romans 7:18-19",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "anxiety": [
            BereanScriptureChip(
                reference: "Philippians 4:6-7",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Matthew 6:34",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "1 Peter 5:7",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "worry": [
            BereanScriptureChip(
                reference: "Philippians 4:6-7",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Matthew 6:34",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "1 Peter 5:7",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "grief": [
            BereanScriptureChip(
                reference: "Psalm 34:18",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "John 11:35",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "2 Corinthians 1:3-4",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "loss": [
            BereanScriptureChip(
                reference: "Psalm 34:18",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "2 Corinthians 1:3-4",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Revelation 21:4",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "marriage": [
            BereanScriptureChip(
                reference: "Genesis 2:24",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Ephesians 5:25",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "1 Corinthians 13:4-7",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "purpose": [
            BereanScriptureChip(
                reference: "Jeremiah 29:11",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Ephesians 2:10",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Romans 8:28",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "praise": [
            BereanScriptureChip(
                reference: "Psalm 150:1-6",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Psalm 9:1-2",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Hebrews 13:15",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "redemption": [
            BereanScriptureChip(
                reference: "Ephesians 1:7",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Titus 2:14",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Isaiah 44:22",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "strength": [
            BereanScriptureChip(
                reference: "Philippians 4:13",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Isaiah 40:31",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Psalm 46:1",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "peace": [
            BereanScriptureChip(
                reference: "John 14:27",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Philippians 4:7",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Isaiah 26:3",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ],

        "joy": [
            BereanScriptureChip(
                reference: "Nehemiah 8:10",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "Psalm 16:11",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            ),
            BereanScriptureChip(
                reference: "John 15:11",
                text: "[Verse text will be fetched from licensed Bible API at runtime]",
                translation: "WEB"
            )
        ]
    ]
    // swiftlint:enable line_length

    // MARK: - Private Init

    private init() {}

    // MARK: - Public API

    /// Matches a ContentObject to relevant scripture chips using themes, title keywords,
    /// and any pre-linked verse references. Returns up to 5 deduplicated chips.
    func findVerses(for contentObject: ContentObject) -> [BereanScriptureChip] {
        // Return cached result if still valid
        if let entry = cache[contentObject.id], entry.expiresAt > Date() {
            return entry.chips
        }

        let normalised = normalizedThemes(from: contentObject.themes)

        // Extract keyword themes from the title
        let titleWords = contentObject.title
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        let titleThemes = Set(titleWords).intersection(Set(themeToVerses.keys))

        let allThemes = normalised.union(titleThemes)

        var collected: [BereanScriptureChip] = []

        // Theme-matched chips
        for theme in allThemes {
            if let chips = themeToVerses[theme] {
                collected.append(contentsOf: chips)
            }
        }

        // Chips seeded from linkedVerseRefs already on the ContentObject
        for ref in contentObject.linkedVerseRefs {
            let syntheticChip = BereanScriptureChip(reference: ref, text: "", translation: "")
            // Only insert if we don't already have a richer chip for this reference
            if !collected.contains(where: { $0.reference == ref }) {
                collected.append(syntheticChip)
            }
        }

        let result = deduplicated(collected, limit: 5)

        // Write to cache
        let expiry = Date().addingTimeInterval(cacheTTL)
        cache[contentObject.id] = CacheEntry(chips: result, expiresAt: expiry)

        dlog("[BereanContentConnector] Found \(result.count) verses for '\(contentObject.title)'")
        return result
    }

    /// Pure theme lookup. Returns up to 5 deduplicated scripture chips.
    func findVerses(for themes: [String]) -> [BereanScriptureChip] {
        let normalised = normalizedThemes(from: themes)
        var collected: [BereanScriptureChip] = []

        for theme in normalised {
            if let chips = themeToVerses[theme] {
                collected.append(contentsOf: chips)
            }
        }

        return deduplicated(collected, limit: 5)
    }

    /// Returns only the reference strings — useful for writing back to ContentObject.linkedVerseRefs.
    func verseRefsOnly(for themes: [String]) -> [String] {
        findVerses(for: themes).map(\.reference)
    }

    // MARK: - Private Helpers

    /// Lowercases raw themes and applies simple singular normalization so that
    /// e.g. "fears" → "fear", "prayers" → "prayer".
    private func normalizedThemes(from raw: [String]) -> Set<String> {
        var result = Set<String>()
        for theme in raw {
            let lower = theme.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip common plural suffixes to improve match rate
            let singular: String
            if lower.hasSuffix("ies") && lower.count > 4 {
                singular = String(lower.dropLast(3)) + "y"
            } else if lower.hasSuffix("es") && lower.count > 4 {
                singular = String(lower.dropLast(2))
            } else if lower.hasSuffix("s") && lower.count > 3 {
                singular = String(lower.dropLast(1))
            } else {
                singular = lower
            }
            result.insert(lower)
            if singular != lower { result.insert(singular) }
        }
        return result
    }

    /// Deduplicates chips by reference and returns at most `limit` items.
    private func deduplicated(_ chips: [BereanScriptureChip], limit: Int) -> [BereanScriptureChip] {
        var seen = Set<String>()
        var result: [BereanScriptureChip] = []
        for chip in chips {
            guard !chip.reference.isEmpty, seen.insert(chip.reference).inserted else { continue }
            result.append(chip)
            if result.count >= limit { break }
        }
        return result
    }
}
