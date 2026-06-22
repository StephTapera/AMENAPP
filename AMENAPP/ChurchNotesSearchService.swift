//
//  ChurchNotesSearchService.swift
//  AMENAPP
//
//  Feature 8: Smart Search
//  Local scoring-based search with scripture-awareness, tag/date filtering,
//  semantic Claude re-ranking (async, debounced), match highlighting,
//  and UserDefaults-backed recent search history.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Search Query

struct ChurchNoteSearchQuery {
    var text: String
    var tags: [String]               = []
    var dateRange: ClosedRange<Date>? = nil
    var hasAudio: Bool?               = nil
    var hasAttachments: Bool?         = nil
    var scriptureReference: String?   = nil
    var churchName: String?           = nil

    var isEmpty: Bool {
        text.isEmpty &&
        tags.isEmpty &&
        dateRange == nil &&
        hasAudio == nil &&
        hasAttachments == nil &&
        scriptureReference == nil &&
        (churchName?.isEmpty ?? true)
    }
}

// MARK: - Search Result

struct ChurchNoteSearchResult: Identifiable {
    var id: String { note.id ?? UUID().uuidString }
    var note: ChurchNote
    var score: Double            // higher = better match
    var matchedFields: [String]  // e.g. ["title", "scripture"]
}

// MARK: - Smart Search Service

@MainActor
final class ChurchNotesSearchService: ObservableObject {
    static let shared = ChurchNotesSearchService()

    @Published var results: [ChurchNoteSearchResult] = []
    @Published var isSearching       = false
    @Published var isSemanticRanking = false
    @Published var recentSearches: [String] = []

    private let recentSearchesKey = "churchNotes.recentSearches"
    private let maxRecentSearches = 10
    private var semanticDebounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadRecentSearches()
    }

    // MARK: - Main Search Entry Point

    /// Performs local scoring search immediately.
    /// Also fires an async semantic re-ranking pass via Claude (debounced 800ms).
    func search(query: ChurchNoteSearchQuery, in notes: [ChurchNote]) -> [ChurchNoteSearchResult] {
        guard !query.isEmpty else {
            results = []
            return []
        }

        isSearching = true
        defer { isSearching = false }

        let scored = notes.compactMap { note -> ChurchNoteSearchResult? in
            let (score, fields) = scoreNote(note, for: query)
            guard score > 0 else { return nil }
            return ChurchNoteSearchResult(note: note, score: score, matchedFields: fields)
        }.sorted { $0.score > $1.score }

        results = scored

        // Persist search text to recents
        if !query.text.isEmpty {
            addToRecentSearches(query.text)
        }

        // Fire async semantic pass
        if !query.text.isEmpty {
            triggerSemanticReranking(query: query, candidates: scored, allNotes: notes)
        }

        return scored
    }

    // MARK: - Scoring

    private func scoreNote(_ note: ChurchNote, for query: ChurchNoteSearchQuery) -> (Double, [String]) {
        var score: Double = 0
        var fields: [String] = []

        // --- Text matching ---
        if !query.text.isEmpty {
            let q    = query.text.lowercased()
            let refs = ChurchNotesScriptureDetector.shared.detectReferenceStrings(in: query.text)

            // Title match — highest weight
            if note.title.lowercased().contains(q) {
                score += 10
                fields.append("title")
            }
            // Sermon title
            if (note.sermonTitle ?? "").lowercased().contains(q) {
                score += 7
                fields.append("sermonTitle")
            }
            // Content full-text
            if note.content.lowercased().contains(q) {
                let occurrences = note.content.lowercased().components(separatedBy: q).count - 1
                score += Double(min(occurrences, 5)) * 3
                fields.append("content")
            }
            // Tags
            let tagMatch = (note.tags + note.claudeTags).filter { $0.lowercased().contains(q) }
            if !tagMatch.isEmpty {
                score += Double(tagMatch.count) * 2
                fields.append("tags")
            }
            // Pastor / church
            if (note.pastor ?? "").lowercased().contains(q) {
                score += 4; fields.append("pastor")
            }
            if (note.churchName ?? "").lowercased().contains(q) {
                score += 4; fields.append("church")
            }
            // Scripture-aware: match against detected references
            for ref in refs {
                let refLower = ref.lowercased()
                if note.scriptureReferences.map({ $0.lowercased() }).contains(where: { $0.contains(refLower) }) {
                    score += 8; fields.append("scriptureReferences")
                }
                if note.content.lowercased().contains(refLower) {
                    score += 5; if !fields.contains("content") { fields.append("content") }
                }
                if (note.scripture ?? "").lowercased().contains(refLower) {
                    score += 6; fields.append("scripture")
                }
            }
        }

        // --- Filter gates (must-match) ---
        if let tagFilter = query.tags.first, !tagFilter.isEmpty {
            let allTags = note.tags + note.claudeTags
            let matches = query.tags.allSatisfy { t in allTags.map({ $0.lowercased() }).contains(t.lowercased()) }
            if !matches { return (0, []) }
            score += 2; fields.append("tags")
        }

        if let range = query.dateRange {
            if !range.contains(note.date) { return (0, []) }
            score += 1
        }

        if let hasAudio = query.hasAudio {
            let noteHasAudio = note.hasTranscript || note.audioRecordingURL != nil
            if hasAudio != noteHasAudio { return (0, []) }
        }

        if let hasAttachments = query.hasAttachments {
            let noteHasAttachments = note.attachmentCount > 0
            if hasAttachments != noteHasAttachments { return (0, []) }
        }

        if let refFilter = query.scriptureReference, !refFilter.isEmpty {
            let refLower = refFilter.lowercased()
            let inRefs   = note.scriptureReferences.map({ $0.lowercased() }).contains(where: { $0.contains(refLower) })
            let inContent = note.content.lowercased().contains(refLower)
            if !inRefs && !inContent { return (0, []) }
            score += 5; fields.append("scriptureReferences")
        }

        if let church = query.churchName, !church.isEmpty {
            if !(note.churchName ?? "").lowercased().contains(church.lowercased()) { return (0, []) }
            score += 3
        }

        // Recency bonus (up to 3 points for notes in last 30 days)
        let daysAgo = Calendar.current.dateComponents([.day], from: note.date, to: Date()).day ?? 0
        if daysAgo <= 30 {
            score += Double(30 - daysAgo) / 10.0
        }

        return (score, Array(Set(fields)))
    }

    // MARK: - Semantic Re-ranking

    private func triggerSemanticReranking(
        query: ChurchNoteSearchQuery,
        candidates: [ChurchNoteSearchResult],
        allNotes: [ChurchNote]
    ) {
        semanticDebounceTask?.cancel()
        semanticDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }

                self.isSemanticRanking = true
                defer { self.isSemanticRanking = false }

                let reranked = try await self.semanticRerank(
                    query: query.text,
                    candidates: candidates
                )
                guard !Task.isCancelled else { return }
                self.results = reranked
            } catch {
                // Silently fall back to local results — semantic is best-effort
            }
        }
    }

    private func semanticRerank(
        query: String,
        candidates: [ChurchNoteSearchResult]
    ) async throws -> [ChurchNoteSearchResult] {
        guard !candidates.isEmpty else { return candidates }

        // Build note summaries (limit to top 8 for cost/performance)
        let top     = Array(candidates.prefix(8))
        let summaries = top.map { r -> String in
            let note = r.note
            return "[\(note.id ?? "?")] \(note.title) — \(note.content.prefix(120))"
        }.joined(separator: "\n")

        let prompt = """
        Given the search query "\(query)", rank the following church notes by relevance.
        Return ONLY the note IDs in order from most to least relevant, one per line, no other text.

        Notes:
        \(summaries)
        """

        var response = ""
        for try await chunk in ClaudeService.shared.sendMessage(prompt) {
            response += chunk
        }

        let orderedIds = response
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var reranked: [ChurchNoteSearchResult] = []
        for id in orderedIds {
            if let match = top.first(where: { $0.note.id == id }) {
                reranked.append(match)
            }
        }
        // Append any not mentioned by Claude (preserves completeness)
        let mentionedIds = Set(orderedIds)
        for result in top where !mentionedIds.contains(result.note.id ?? "") {
            reranked.append(result)
        }
        // Add remaining candidates beyond top 8 at the end
        if candidates.count > 8 {
            reranked += Array(candidates.dropFirst(8))
        }
        return reranked
    }

    // MARK: - Highlight Matches

    /// Returns an AttributedString with query occurrences highlighted.
    func highlightMatches(in text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard !query.isEmpty else { return attributed }

        let lower   = text.lowercased()
        let qLower  = query.lowercased()
        var searchStart = lower.startIndex

        while let range = lower.range(of: qLower, range: searchStart..<lower.endIndex) {
            // Map the String range into an AttributedString range.
            // We use the original text's String.Index range directly.
            let attrStart = attributed.index(attributed.startIndex, offsetByCharacters: lower.distance(from: lower.startIndex, to: range.lowerBound))
            let attrEnd   = attributed.index(attrStart, offsetByCharacters: qLower.count)
            let attrRange = attrStart..<attrEnd

            var container = AttributeContainer()
            container.foregroundColor = Color.primary
            container.font            = Font.body.bold()
            // backgroundColor is available via AttributeScopes.SwiftUIAttributes
            // accessible through the SwiftUI scope on AttributedString
            attributed[attrRange].mergeAttributes(container)
            // Apply highlight via UIKit scope for broader compatibility
            attributed[attrRange].backgroundColor = Color.yellow.opacity(0.4)

            searchStart = range.upperBound
        }
        return attributed
    }

    // MARK: - Recent Searches

    func addToRecentSearches(_ query: String) {
        var searches = recentSearches.filter { $0 != query }
        searches.insert(query, at: 0)
        if searches.count > maxRecentSearches {
            searches = Array(searches.prefix(maxRecentSearches))
        }
        recentSearches = searches
        UserDefaults.standard.set(searches, forKey: recentSearchesKey)
    }

    func removeRecentSearch(_ query: String) {
        recentSearches.removeAll { $0 == query }
        UserDefaults.standard.set(recentSearches, forKey: recentSearchesKey)
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
    }

    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
    }
}
