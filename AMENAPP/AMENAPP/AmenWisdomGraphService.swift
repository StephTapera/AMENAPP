// AmenWisdomGraphService.swift
// AMENAPP

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Recommendation

struct AmenBookRecommendation: Identifiable {
    let id = UUID()
    let book: WLBook
    let reason: AmenRecommendationReason
    let score: Double    // 0.0–1.0 internal; never shown to user
}

enum AmenRecommendationReason: String {
    case recentStudy     = "Based on your recent study"
    case scriptureLink   = "Connects to a scripture you've explored"
    case themeChain      = "Continue this theme"
    case quietNextStep   = "A quiet next step"
    case faithStage      = "Recommended for your stage of faith"
    case complements     = "Pairs well with what you've been reading"
    case editorial       = "Selected by the AMEN library team"

    // Intentionally non-specific — never exposes spiritual state assumptions
    var displayLabel: String { rawValue }
}

// MARK: - Service

@MainActor
final class AmenWisdomGraphService: ObservableObject {

    static let shared = AmenWisdomGraphService()

    @Published private(set) var recommendations: [AmenBookRecommendation] = []
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()
    private let booksService = GoogleBooksService.shared
    private var catalog: AmenLibraryCatalogProvider = GoogleBooksAmenCatalogProvider()

    private init() {}

    // MARK: - Public

    func refresh(faithStage: WalkWithChristViewModel.FaithStagePersonal) {
        Task { await buildRecommendations(faithStage: faithStage) }
    }

    // MARK: - Core Graph

    private func buildRecommendations(faithStage: WalkWithChristViewModel.FaithStagePersonal) async {
        isLoading = true
        defer { isLoading = false }

        guard let uid = Auth.auth().currentUser?.uid else { return }

        async let savedBooks = fetchSavedBooks(uid: uid)
        async let studyRefs  = fetchBereanStudyRefs()
        async let prayerThemes = fetchPrayerThemes(uid: uid)

        let (saved, refs, themes) = await (savedBooks, studyRefs, prayerThemes)

        var candidates: [AmenBookRecommendation] = []

        // 1. Stage-based entry point
        let stageQuery = stageSearchQuery(faithStage)
        if let stageBooks = try? await catalog.fetchByCategory(stagePrimaryCategory(faithStage), maxResults: 6) {
            for book in stageBooks where !saved.contains(book.id) {
                candidates.append(.init(book: book, reason: .faithStage, score: 0.75))
            }
        }
        _ = stageQuery // suppress unused warning; used for fallback below

        // 2. Complement saved-book categories
        let topCategories = topSavedCategories(from: saved, shelves: [])
        for category in topCategories.prefix(2) {
            if let books = try? await catalog.fetchByCategory(category, maxResults: 4) {
                for book in books where !saved.contains(book.id) {
                    candidates.append(.init(book: book, reason: .complements, score: 0.65))
                }
            }
        }

        // 3. Scripture-linked books
        for ref in refs.prefix(3) {
            let query = "\(ref) christian book"
            if let books = try? await catalog.search(query: query, maxResults: 3) {
                for book in books where !saved.contains(book.id) {
                    candidates.append(.init(book: book, reason: .scriptureLink, score: 0.80))
                }
            }
        }

        // 4. Prayer-theme adjacent books
        for theme in themes.prefix(2) {
            if let books = try? await catalog.search(query: "\(theme) christian prayer", maxResults: 3) {
                for book in books where !saved.contains(book.id) {
                    candidates.append(.init(book: book, reason: .themeChain, score: 0.60))
                }
            }
        }

        // 5. Quiet next step (editorial picks, lowest-pressure)
        if let editorial = try? await catalog.fetchFeatured() {
            for book in editorial.prefix(3) where !saved.contains(book.id) {
                candidates.append(.init(book: book, reason: .quietNextStep, score: 0.50))
            }
        }

        // Deduplicate by book.id, keeping highest score
        var seen = Set<String>()
        let deduped = candidates
            .sorted { $0.score > $1.score }
            .filter { seen.insert($0.book.id).inserted }

        recommendations = Array(deduped.prefix(15))
    }

    // MARK: - Helpers

    private func fetchSavedBooks(uid: String) async -> Set<String> {
        let snap = try? await db.collection("users").document(uid)
            .collection("savedBooks").getDocuments()
        return Set(snap?.documents.map { $0.documentID } ?? [])
    }

    private func fetchBereanStudyRefs() async -> [String] {
        // BereanStudyNotes are persisted in UserDefaults as `berean_study_notes_v1`
        guard let data = UserDefaults.standard.data(forKey: "berean_study_notes_v1"),
              let notes = try? JSONDecoder().decode([[String: String]].self, from: data)
        else { return [] }
        // Extract any strings that look like scripture refs (e.g. "John 3:16", "Psalm 23")
        let allText = notes.compactMap { $0["text"] ?? $0["note"] }.joined(separator: " ")
        return extractScriptureRefs(from: allText)
    }

    private func fetchPrayerThemes(uid: String) async -> [String] {
        let snap = try? await db.collection("users").document(uid)
            .collection("prayers")
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .getDocuments()
        guard let docs = snap?.documents else { return [] }
        let words = docs.compactMap { $0.data()["category"] as? String }
        return Array(Set(words))
    }

    private func topSavedCategories(from savedIds: Set<String>, shelves: [WLBookShelf]) -> [WLBookCategory] {
        // Map saved IDs back to categories using fallback catalog tags
        let catalog = GoogleBooksService.fallbackCatalog
        var scores: [WLBookCategory: Int] = [:]
        for book in catalog where savedIds.contains(book.id) {
            for tag in book.curatedTags {
                if let cat = WLBookCategory.allCases.first(where: { tag.localizedCaseInsensitiveContains($0.rawValue) }) {
                    scores[cat, default: 0] += 1
                }
            }
        }
        return scores.sorted { $0.value > $1.value }.map(\.key)
    }

    private func stagePrimaryCategory(_ stage: WalkWithChristViewModel.FaithStagePersonal) -> WLBookCategory {
        switch stage {
        case .exploring: return .discipleship
        case .growing:   return .prayer
        case .deepening: return .theology
        case .leading:   return .leadership
        }
    }

    private func stageSearchQuery(_ stage: WalkWithChristViewModel.FaithStagePersonal) -> String {
        switch stage {
        case .exploring: return "christian new believer faith basics"
        case .growing:   return "christian growth discipleship daily"
        case .deepening: return "christian theology spiritual formation"
        case .leading:   return "christian leadership ministry service"
        }
    }

    // Lightweight scripture reference extractor — no LLM required
    private func extractScriptureRefs(from text: String) -> [String] {
        let books = ["Genesis","Exodus","Psalms","Psalm","Proverbs","Isaiah","Matthew","Mark",
                     "Luke","John","Acts","Romans","Corinthians","Galatians","Ephesians",
                     "Philippians","Colossians","Thessalonians","Timothy","Hebrews","James",
                     "Peter","Revelation"]
        let pattern = "(?:" + books.joined(separator: "|") + ")\\s+\\d+(?::\\d+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return Array(Set(matches.compactMap { Range($0.range, in: text).map { String(text[$0]) } })).prefix(5).map { $0 }
    }
}
