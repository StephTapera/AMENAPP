// FaithGlossary.swift
// AMEN App — Accessibility Intelligence Layer (Phase 4)
//
// Loads bundled FaithGlossaryData.json containing 200+ faith terms.
// Provides lookup by term and suggestion of unfamiliar terms per post.
// Fully on-device — zero API cost.

import Foundation

@MainActor
final class FaithGlossary {

    static let shared = FaithGlossary()

    private var terms: [String: FaithTermEntry] = [:]
    private var allTerms: [FaithTermEntry] = []
    private var isLoaded = false

    private init() {
        loadGlossary()
    }

    // MARK: - Public API

    /// Look up a single term (case-insensitive)
    func lookup(_ term: String) -> FaithTermEntry? {
        terms[term.lowercased()]
    }

    /// Suggest up to maxTerms unfamiliar terms found in text.
    /// Filters by user's likely familiarity based on context.
    func suggestTerms(
        in text: String,
        maxTerms: Int = 5
    ) -> [FaithTermEntry] {
        guard isLoaded else { return [] }

        let lowercased = text.lowercased()
        var found: [FaithTermEntry] = []

        for entry in allTerms {
            guard found.count < maxTerms else { break }

            // Check if the term appears in the text
            let searchTerm = entry.term.lowercased()
            if lowercased.contains(searchTerm) {
                found.append(entry)
            }

            // Also check aliases
            for alias in entry.aliases {
                if lowercased.contains(alias.lowercased()) && !found.contains(where: { $0.id == entry.id }) {
                    found.append(entry)
                    break
                }
            }
        }

        return found
    }

    /// Get all terms in a specific category
    func terms(inCategory category: String) -> [FaithTermEntry] {
        allTerms.filter { $0.category.lowercased() == category.lowercased() }
    }

    // MARK: - Loading

    private func loadGlossary() {
        guard let url = Bundle.main.url(forResource: "FaithGlossaryData", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([FaithTermEntry].self, from: data) else {
            dlog("[FaithGlossary] Failed to load glossary data")
            return
        }

        allTerms = entries
        for entry in entries {
            terms[entry.term.lowercased()] = entry
            for alias in entry.aliases {
                terms[alias.lowercased()] = entry
            }
        }
        isLoaded = true
        dlog("[FaithGlossary] Loaded \(entries.count) terms")
    }
}
