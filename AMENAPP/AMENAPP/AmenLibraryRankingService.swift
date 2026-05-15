// AmenLibraryRankingService.swift
// AMENAPP
//
// Ranks books for the library surfaces using an ethics-aware scoring model.
// Ranking intentionally avoids vanity signals (click bait, controversy, fear, shame, urgency).
// Signals used: theological relevance, format match, editorial curation, quality, and user signal.

import Foundation

// MARK: - Ranking Signals (all normalised 0.0–1.0)

struct AmenRankingSignals {
    var theologicalRelevance: Double = 0.5   // category + faith-stage match
    var formatPreference: Double    = 0.5    // matches user's preferred format
    var editorialCuration: Double   = 0.0    // isFeatured / curatedTag bonus
    var contentQuality: Double      = 0.5    // averageRating signal
    var userSignal: Double          = 0.0    // saved/noted/completed adjacency
}

// MARK: - Unsafe Category Guard
// Books exhibiting these signals are excluded from ranked surfaces.
// They may still appear in raw search results if the user explicitly searches.

private let unsafeCategorySignals: Set<String> = [
    "controversy", "fear", "shame", "urgency", "clickbait",
    "sensational", "scandal", "outrage", "celebrity gossip"
]

// MARK: - Service

final class AmenLibraryRankingService {

    static let shared = AmenLibraryRankingService()
    private init() {}

    // MARK: - Public Rank

    /// Returns `books` sorted by score descending, with unsafe books removed.
    func rank(
        books: [WLBook],
        faithStage: WalkWithChristViewModel.FaithStagePersonal,
        preferredFormat: AmenBookFormat,
        savedBookIds: Set<String>,
        notedBookIds: Set<String>
    ) -> [WLBook] {
        books
            .filter { isSafe($0) }
            .map { book -> (WLBook, Double) in
                let signals = buildSignals(
                    book: book,
                    faithStage: faithStage,
                    preferredFormat: preferredFormat,
                    savedBookIds: savedBookIds,
                    notedBookIds: notedBookIds
                )
                return (book, computeScore(signals))
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Score a single book for display (e.g., to order detail-page recommendations).
    func score(
        book: WLBook,
        faithStage: WalkWithChristViewModel.FaithStagePersonal,
        preferredFormat: AmenBookFormat,
        savedBookIds: Set<String>,
        notedBookIds: Set<String>
    ) -> Double {
        guard isSafe(book) else { return 0 }
        return computeScore(buildSignals(
            book: book, faithStage: faithStage,
            preferredFormat: preferredFormat,
            savedBookIds: savedBookIds,
            notedBookIds: notedBookIds
        ))
    }

    // MARK: - Safety Guard

    func isSafe(_ book: WLBook) -> Bool {
        let allText = ([book.title, book.subtitle, book.description].compactMap { $0 }
            + book.categories + book.curatedTags).joined(separator: " ").lowercased()
        return !unsafeCategorySignals.contains { allText.contains($0) }
    }

    // MARK: - Signal Building

    private func buildSignals(
        book: WLBook,
        faithStage: WalkWithChristViewModel.FaithStagePersonal,
        preferredFormat: AmenBookFormat,
        savedBookIds: Set<String>,
        notedBookIds: Set<String>
    ) -> AmenRankingSignals {
        var signals = AmenRankingSignals()

        // Theological relevance: faith-stage category alignment
        let stageCategory = stageToCategory(faithStage)
        let allTags = (book.curatedTags + book.categories).map(\.lowercased)
        let categoryMatch = allTags.contains { $0.contains(stageCategory.rawValue.lowercased()) }
        signals.theologicalRelevance = categoryMatch ? 0.9 : 0.5

        // Content quality: clamp rating 1–5 → 0–1
        if let rating = book.averageRating {
            signals.contentQuality = min(max((rating - 1) / 4.0, 0), 1)
        }

        // Editorial curation
        signals.editorialCuration = book.isFeatured ? 1.0 : (book.curatedTags.isEmpty ? 0 : 0.4)

        // Format preference: we infer from curatedTags for now
        // (Google Books API doesn't expose format reliably)
        if preferredFormat == .audio && allTags.contains(where: { $0.contains("audio") }) {
            signals.formatPreference = 1.0
        } else if preferredFormat == .ebook && book.previewLink != nil {
            signals.formatPreference = 0.8
        } else {
            signals.formatPreference = 0.5
        }

        // User signal: adjacent to noted/saved books
        if savedBookIds.contains(book.id) {
            signals.userSignal = 0.0    // already saved; don't re-surface
        } else if notedBookIds.contains(book.id) {
            signals.userSignal = 0.6    // partial engagement
        } else {
            signals.userSignal = 0.3
        }

        return signals
    }

    // MARK: - Scoring Formula

    private func computeScore(_ s: AmenRankingSignals) -> Double {
        // Weighted sum. Weights deliberately avoid click-bait signals.
        let raw = (s.theologicalRelevance * 0.35)
            + (s.contentQuality        * 0.25)
            + (s.editorialCuration     * 0.20)
            + (s.userSignal            * 0.15)
            + (s.formatPreference      * 0.05)
        return min(max(raw, 0), 1)
    }

    private func stageToCategory(_ stage: WalkWithChristViewModel.FaithStagePersonal) -> WLBookCategory {
        switch stage {
        case .exploring: return .discipleship
        case .growing:   return .devotional
        case .deepening: return .theology
        case .leading:   return .leadership
        }
    }
}
