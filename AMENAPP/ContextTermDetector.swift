// ContextTermDetector.swift
// AMEN App — Accessibility Intelligence Layer (Phase 4)
//
// On-device term detection using NLTagger noun extraction + FaithGlossary cross-reference.
// Returns [DetectedTerm] with ranges for underlining in PostCard.
// Zero API cost.

import Foundation
import NaturalLanguage

@MainActor
final class ContextTermDetector {

    static let shared = ContextTermDetector()

    private init() {}

    // MARK: - Public API

    /// Detect faith terms in text that the user might not understand.
    /// Returns terms with their ranges in the original text for UI highlighting.
    func detectTerms(
        in text: String,
        maxTerms: Int = 5
    ) -> [DetectedTerm] {
        guard AMENFeatureFlags.shared.contextBridgeEnabled else { return [] }

        let glossary = FaithGlossary.shared

        // First pass: find glossary matches with ranges
        var detected: [DetectedTerm] = []
        let lowercased = text.lowercased()

        let allSuggested = glossary.suggestTerms(in: text, maxTerms: maxTerms + 3)

        for entry in allSuggested {
            guard detected.count < maxTerms else { break }

            // Find the range of this term in the original text (case-insensitive)
            let searchTerm = entry.term.lowercased()
            if let range = lowercased.range(of: searchTerm) {
                // Map back to original text indices
                let originalRange = text.index(text.startIndex, offsetBy: lowercased.distance(from: lowercased.startIndex, to: range.lowerBound)) ..< text.index(text.startIndex, offsetBy: lowercased.distance(from: lowercased.startIndex, to: range.upperBound))

                detected.append(DetectedTerm(
                    term: entry.term,
                    range: originalRange,
                    glossaryEntry: entry
                ))
            }
        }

        return detected
    }
}
