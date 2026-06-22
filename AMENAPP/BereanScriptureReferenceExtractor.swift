// BereanScriptureReferenceExtractor.swift
// AMENAPP
//
// Utility for extracting scripture references (e.g., "John 3:16") from text.
// Used by Berean bridges to attach detected scripture refs to saved entries.

import Foundation

enum BereanScriptureReferenceExtractor {

    /// Returns all scripture references found in the given text.
    /// Matches patterns like "John 3:16", "1 Corinthians 13:4-7", "Genesis 1:1".
    static func references(in text: String) -> [String] {
        let pattern = #"([1-3]?\s?[A-Za-z]+)\s+(\d+):(\d+(?:-\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap { match -> String? in
            guard match.numberOfRanges >= 4 else { return nil }
            let book    = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let chapter = nsString.substring(with: match.range(at: 2))
            let verses  = nsString.substring(with: match.range(at: 3))
            return "\(book) \(chapter):\(verses)"
        }
    }
}
