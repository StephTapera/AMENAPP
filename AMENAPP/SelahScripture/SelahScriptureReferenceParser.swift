//
//  SelahScriptureReferenceParser.swift
//  AMENAPP
//
//  Pure, allocation-light parser that turns free-form user input into a
//  `SelahScriptureReference`. Designed for both the search field
//  ("john 3:16", "rom 5:3-5") and for resolving references found in
//  external text.
//
//  Name-prefixed `Selah*` to avoid colliding with the legacy
//  `ScriptureReferenceParser` type used elsewhere in the app.
//

import Foundation

enum SelahScriptureReferenceParser {

    // MARK: - Public API

    /// Parse user input into a single reference.
    /// Returns `nil` if the input doesn't resemble a scripture address.
    static func parse(_ raw: String) -> SelahScriptureReference? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = normalize(trimmed)
        guard let (bookId, remainder) = matchBookPrefix(in: normalized) else { return nil }

        // Remainder shape: "" | "3" | "3:16" | "3:16-20" | "3:16,18"
        let tail = remainder.trimmingCharacters(in: .whitespaces)

        // Whole-book reference ("John") — defaults to chapter 1
        guard !tail.isEmpty else {
            return SelahScriptureReference(bookId: bookId, chapter: 1, startVerse: nil, endVerse: nil)
        }

        // Split chapter from verse portion
        let parts = tail.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let chapter = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              chapter > 0
        else { return nil }

        guard parts.count == 2 else {
            return SelahScriptureReference(bookId: bookId, chapter: chapter, startVerse: nil, endVerse: nil)
        }

        let versePart = String(parts[1]).trimmingCharacters(in: .whitespaces)
        let (start, end) = parseVerseRange(versePart)

        return SelahScriptureReference(
            bookId: bookId,
            chapter: chapter,
            startVerse: start,
            endVerse: end
        )
    }

    /// Suggest possible matching book canonical IDs for a partial input.
    /// Returns canon-ordered IDs. Used by search field for fuzzy book pickup.
    static func suggestBooks(prefix: String, limit: Int = 6) -> [String] {
        let needle = normalize(prefix)
        guard !needle.isEmpty else { return [] }

        let matches = SelahBibleBook.all.filter { book in
            let candidates = [book.displayName, book.abbreviation, book.id] + book.aliases
            return candidates.contains { candidate in
                let n = normalize(candidate)
                return n.hasPrefix(needle) || n.contains(needle)
            }
        }
        return matches.prefix(limit).map { $0.id }
    }

    // MARK: - Internals

    /// Normalize for matching: lowercase, collapse whitespace, strip punctuation
    /// EXCEPT for digits, ':', '-', ','.
    static func normalize(_ input: String) -> String {
        let lowered = input.lowercased()
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789 :-,")
        let filtered = String(lowered.unicodeScalars.compactMap { scalar -> Character? in
            let ch = Character(scalar)
            if allowed.contains(ch) { return ch }
            // collapse other separators to spaces
            return " "
        })
        // Collapse runs of whitespace
        return filtered
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Tries to find the longest book name/alias that prefixes the input.
    /// Returns `(bookId, remainder)` on success.
    private static func matchBookPrefix(in input: String) -> (String, String)? {
        // Build a list of (candidateString, bookId), sorted by length desc
        // so multi-word names like "1 corinthians" win over "1".
        struct Candidate { let needle: String; let bookId: String }
        var candidates: [Candidate] = []
        for book in SelahBibleBook.all {
            let pool = [book.displayName, book.abbreviation, book.id] + book.aliases
            for raw in pool {
                let n = normalize(raw)
                if !n.isEmpty { candidates.append(.init(needle: n, bookId: book.id)) }
            }
        }
        candidates.sort { $0.needle.count > $1.needle.count }

        for candidate in candidates {
            if input == candidate.needle {
                return (candidate.bookId, "")
            }
            if input.hasPrefix(candidate.needle + " ") {
                let remainder = String(input.dropFirst(candidate.needle.count + 1))
                return (candidate.bookId, remainder)
            }
            // Allow attached digits — "rom5", "ps23"
            if input.hasPrefix(candidate.needle),
               let first = input.dropFirst(candidate.needle.count).first,
               first.isNumber {
                let remainder = String(input.dropFirst(candidate.needle.count))
                return (candidate.bookId, remainder)
            }
        }
        return nil
    }

    /// Returns `(start, end)` from "16", "16-20", "16,18", "16 - 20", etc.
    /// For "16" → (16, nil). For "16-20" → (16, 20). For "16,18" → (16, nil)
    /// (we only support contiguous ranges; commas keep just the first).
    private static func parseVerseRange(_ raw: String) -> (Int?, Int?) {
        let cleaned = raw.replacingOccurrences(of: " ", with: "")
        // Comma is a list separator; we only take the first segment
        let firstSegment = cleaned.split(separator: ",").first.map(String.init) ?? cleaned

        if firstSegment.contains("-") {
            let parts = firstSegment.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2,
               let s = Int(parts[0]),
               let e = Int(parts[1]),
               s > 0, e >= s {
                return (s, e)
            }
            if parts.count == 1, let s = Int(parts[0]) {
                return (s, nil)
            }
            return (nil, nil)
        }
        if let s = Int(firstSegment), s > 0 {
            return (s, nil)
        }
        return (nil, nil)
    }
}
