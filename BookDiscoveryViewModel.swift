// BookDiscoveryViewModel.swift
// AMENAPP
//
// ViewModel for the Wisdom Library / Book Discovery feature.
// Drives WisdomLibraryView with real book data from Google Books API.

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class BookDiscoveryViewModel: ObservableObject {

    // MARK: - Published State

    @Published var heroBooks: [WLBook] = []             // large hero shelf
    @Published var shelves: [WLBookShelf] = []          // curated section rows
    @Published var searchResults: [WLBook] = []         // search results
    @Published var selectedCategory: WLBookCategory = .all
    @Published var searchQuery: String = ""
    @Published var isLoadingHero: Bool = true
    @Published var isLoadingShelves: Bool = true
    @Published var isSearching: Bool = false
    @Published var savedBookIds: Set<String> = []
    @Published var readingStats = WLReadingStats.empty
    @Published var errorMessage: String? = nil

    // MARK: - Private

    private let booksService = GoogleBooksService.shared
    private let db = Firestore.firestore()
    private var searchTask: Task<Void, Never>?
    private var statsListener: ListenerRegistration?

    // MARK: - Init / Load

    init() {
        Task { await loadInitialData() }
    }

    func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadHeroShelf() }
            group.addTask { await self.loadCuratedShelves() }
            group.addTask { await self.loadReadingStats() }
        }
        loadSavedBooks()
    }

    // MARK: - Hero Shelf

    private func loadHeroShelf() async {
        isLoadingHero = true
        defer { isLoadingHero = false }
        do {
            let query = selectedCategory == .all
                ? buildPersonalisedQuery()
                : selectedCategory.googleQuery
            let books = try await booksService.search(query: query, maxResults: 12)
            // If API returns results, use them; otherwise seed with featured fallback books
            heroBooks = books.isEmpty
                ? GoogleBooksService.fallbackCatalog.filter { $0.isFeatured == true }
                : books
        } catch {
            // Network failure — use curated fallback so screen is never empty
            heroBooks = GoogleBooksService.fallbackCatalog.filter { $0.isFeatured == true }
            errorMessage = nil // Don't show error if we have fallback content
        }
    }

    // MARK: - Personalised Query Algorithm
    //
    // Derives a query from the user's actual reading behaviour:
    //   1. Counts which categories appear most in their saved books.
    //   2. Picks the top-scoring category and builds a targeted query.
    //   3. Falls back to a generic quality query if no save history exists.

    private func buildPersonalisedQuery() -> String {
        guard !savedBookIds.isEmpty else {
            // No history → broad quality signal
            return "christian spiritual growth faith"
        }

        // Score categories by how many saved books fall into each
        var categoryScores: [WLBookCategory: Int] = [:]
        // We don't have full book objects for saved IDs at this point, so
        // use the curated shelves we already loaded to infer categories.
        for shelf in shelves {
            guard let category = matchShelfToCategory(shelf.title) else { continue }
            let savedCount = shelf.books.filter { savedBookIds.contains($0.id) }.count
            if savedCount > 0 {
                categoryScores[category, default: 0] += savedCount
            }
        }

        if let topCategory = categoryScores.max(by: { $0.value < $1.value })?.key,
           categoryScores[topCategory, default: 0] > 0 {
            // Build a richer query: top category + a related signal
            return topCategory.googleQuery + " recommended"
        }

        // Shelves not loaded yet — use recency-biased generic
        return "christian books faith growth popular"
    }

    private func matchShelfToCategory(_ shelfTitle: String) -> WLBookCategory? {
        let t = shelfTitle.lowercased()
        if t.contains("theolog")    { return .theology }
        if t.contains("prayer") || t.contains("devot") { return .prayer }
        if t.contains("discipl")    { return .discipleship }
        if t.contains("marriage") || t.contains("family") { return .marriage }
        if t.contains("lead")       { return .leadership }
        if t.contains("spirit")     { return .spiritual }
        if t.contains("classic")    { return .classics }
        if t.contains("apolog")     { return .apologetics }
        if t.contains("mission")    { return .missions }
        if t.contains("histor")     { return .history }
        return nil
    }

    // MARK: - Curated Shelves

    private func loadCuratedShelves() async {
        isLoadingShelves = true
        defer { isLoadingShelves = false }
        let result = await booksService.fetchCuratedShelves()
        if !result.isEmpty {
            shelves = result
        } else {
            // API unavailable — build shelves from static fallback catalog
            shelves = buildFallbackShelves()
        }
    }

    /// Builds shelves from the static fallback catalog grouped by category tag.
    private func buildFallbackShelves() -> [WLBookShelf] {
        let catalog = GoogleBooksService.fallbackCatalog
        var shelvesList: [WLBookShelf] = []

        let groups: [(title: String, subtitle: String, tag: String, color: Color, icon: String)] = [
            ("Women of Faith",        "Voices for every season",     "Women of Faith",     .pink,   "person.crop.circle.badge.checkmark"),
            ("Prayer & Devotion",     "Deepen your walk",            "Prayer",             .purple, "hands.sparkles"),
            ("Discipleship",          "Follow Jesus daily",          "Discipleship",       .blue,   "figure.walk"),
            ("Apologetics",           "Defend the faith",            "Apologetics",        .green,  "shield"),
            ("Christian Classics",    "Timeless works",              "Classics",           .brown,  "crown"),
            ("Spiritual Disciplines", "Habits of the soul",          "Spiritual Disciplines", .teal, "sparkles"),
            ("Spiritual Growth",      "Grow in faith",               "Spiritual Growth",   .orange, "flame"),
            ("Testimony",             "Stories of transformation",   "Testimony",          .red,    "quote.bubble"),
        ]

        for group in groups {
            let books = catalog.filter { $0.curatedTags.contains(group.tag) }
            guard !books.isEmpty else { continue }
            shelvesList.append(WLBookShelf(
                id: group.tag,
                title: group.title,
                subtitle: group.subtitle,
                books: books,
                isPremium: false,
                accentColor: group.color,
                icon: group.icon
            ))
        }
        return shelvesList
    }

    // MARK: - Category Change

    func selectCategory(_ category: WLBookCategory) {
        guard category != selectedCategory else { return }
        selectedCategory = category
        heroBooks = []
        isLoadingHero = true
        Task { await loadHeroShelf() }
    }

    // MARK: - Search

    func performSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        searchTask?.cancel()
        searchTask = Task {
            isSearching = true
            defer { isSearching = false }
            do {
                // Small debounce so rapid keystrokes don't spam the API
                try await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                searchResults = try await booksService.search(query: trimmed, maxResults: 20)
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchQuery = ""
        searchResults = []
        isSearching = false
    }

    // MARK: - Save / Unsave

    func toggleSave(book: WLBook) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = db.collection("users").document(uid)
            .collection("savedBooks").document(book.id)

        if savedBookIds.contains(book.id) {
            savedBookIds.remove(book.id)
            ref.delete()
        } else {
            savedBookIds.insert(book.id)
            let saved = WLSavedBook(book: book, userId: uid)
            try? ref.setData(from: saved)
            WLBookAnalytics.trackSave(book: book)
        }
    }

    func isSaved(_ book: WLBook) -> Bool {
        savedBookIds.contains(book.id)
    }

    // MARK: - Load Saved Books

    private func loadSavedBooks() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = db.collection("users").document(uid).collection("savedBooks")
        Task { [weak self] in
            guard let self else { return }
            if let snapshot = try? await ref.getDocuments() {
                self.savedBookIds = Set(snapshot.documents.map { $0.documentID })
            }
        }
    }

    // MARK: - Reading Stats (personalized hero header)

    private func loadReadingStats() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snap = try? await db.collection("users").document(uid)
            .collection("savedBooks").getDocuments()
        let count = snap?.documents.count ?? 0
        // In production derive streak from readingEvents subcollection
        readingStats = WLReadingStats(
            streakDays: UserDefaults.standard.integer(forKey: "readingStreak_\(uid)"),
            booksThisMonth: count,
            totalSaved: count
        )
    }

    // MARK: - Hero headline (personalized)

    var heroHeadline: String {
        switch selectedCategory {
        case .all:          return "Discover Books"
        case .womenOfFaith: return "Women of Faith"
        case .prayer:       return "Prayer & Devotion"
        case .theology:     return "Theology Essentials"
        case .discipleship: return "Walk Deeper"
        case .marriage:     return "Marriage & Family"
        case .leadership:   return "Lead with Wisdom"
        case .classics:     return "Christian Classics"
        case .apologetics:  return "Defend the Faith"
        default:            return selectedCategory.rawValue
        }
    }

    var heroSubheadline: String {
        switch selectedCategory {
        case .all:          return "Curated for your journey in faith"
        case .womenOfFaith: return "Jackie Hill Perry, Priscilla Shirer & more"
        case .prayer:       return "Deepen your prayer life"
        case .theology:     return "Foundations of the faith"
        case .discipleship: return "Follow Jesus every day"
        case .classics:     return "Timeless works of the faith"
        case .apologetics:  return "Defend what you believe"
        default:            return "AMEN Wisdom Library"
        }
    }

    var streakLabel: String? {
        guard readingStats.streakDays > 0 else { return nil }
        return "Wow! \(readingStats.streakDays) days in the Word"
    }

    var streakSubLabel: String? {
        guard readingStats.totalSaved > 0 else { return nil }
        return "\(readingStats.totalSaved) books saved to your library"
    }

    deinit {
        statsListener?.remove()
        searchTask?.cancel()
    }
}
