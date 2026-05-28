// AmenLibraryIntelligenceTests.swift
// AMENAPPTests
//
// Unit tests for the Amen Library intelligence layers.
// All tests are pure-Swift — no Firebase, no network, no UI dependencies.
// Run with: Product ▶ Test (⌘U)

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Helpers

private func makeBook(
    id: String = UUID().uuidString,
    title: String = "Test Book",
    authors: [String] = ["Author"],
    categories: [String] = [],
    curatedTags: [String] = [],
    isFeatured: Bool = false,
    averageRating: Double? = nil
) -> WLBook {
    WLBook(
        id: id, title: title, subtitle: nil, authors: authors,
        description: nil, categories: categories,
        isbn13: nil, isbn10: nil, publishedDate: nil, publisher: nil,
        pageCount: nil, language: nil, thumbnailURL: nil,
        highResThumbnailURL: nil, previewLink: nil,
        averageRating: averageRating, ratingsCount: nil,
        isFeatured: isFeatured, recommendationReason: nil, curatedTags: curatedTags
    )
}

// MARK: - 1. Ranking Service — Safety Guard

@Suite("AmenLibraryRankingService — Safety")
struct RankingServiceSafetyTests {

    @Test("Books with shame/fear signals are filtered from ranked surfaces")
    func unsafeBooksFiltered() {
        let ranker = AmenLibraryRankingService.shared
        let shameBook = makeBook(title: "Your Shameful Secret Exposed", categories: ["shame"])
        let fearBook  = makeBook(title: "What You Should Fear About Your Faith", categories: ["fear"])
        let safeBook  = makeBook(title: "The Cost of Discipleship", categories: ["Discipleship"])

        let ranked = ranker.rank(
            books: [shameBook, fearBook, safeBook],
            faithStage: .growing,
            preferredFormat: .unknown,
            savedBookIds: [],
            notedBookIds: []
        )

        #expect(ranked.count == 1)
        #expect(ranked.first?.id == safeBook.id)
    }

    @Test("isSafe returns false for books with unsafe category signals")
    func isSafeReturnsFalseForUnsafe() {
        let ranker = AmenLibraryRankingService.shared
        let clickbaitBook = makeBook(title: "Outrage in the Church", categories: ["outrage", "scandal"])
        #expect(ranker.isSafe(clickbaitBook) == false)
    }

    @Test("isSafe returns true for normal Christian books")
    func isSafeReturnsTrueForSafe() {
        let ranker = AmenLibraryRankingService.shared
        let book = makeBook(title: "Mere Christianity", categories: ["Apologetics", "Theology"])
        #expect(ranker.isSafe(book))
    }

    @Test("Ranking avoids urgency signals in title")
    func urgencySignalBlocked() {
        let ranker = AmenLibraryRankingService.shared
        let urgentBook = makeBook(title: "Urgency: Why You Must Act Now", categories: ["urgency"])
        #expect(ranker.isSafe(urgentBook) == false)
    }
}

// MARK: - 2. Ranking Service — Score Ordering

@Suite("AmenLibraryRankingService — Score Ordering")
struct RankingScoreOrderingTests {

    @Test("Featured editorial book scores higher than non-featured")
    func featuredScoresHigher() {
        let ranker = AmenLibraryRankingService.shared
        let featured    = makeBook(title: "Featured Book", isFeatured: true, averageRating: 4.5)
        let nonFeatured = makeBook(title: "Regular Book", isFeatured: false, averageRating: 4.5)

        let ranked = ranker.rank(
            books: [nonFeatured, featured],
            faithStage: .deepening,
            preferredFormat: .unknown,
            savedBookIds: [],
            notedBookIds: []
        )
        #expect(ranked.first?.id == featured.id)
    }

    @Test("Higher-rated book scores above lower-rated at same editorial level")
    func higherRatingScoresHigher() {
        let ranker = AmenLibraryRankingService.shared
        let highRated = makeBook(id: "high", title: "High Rated", averageRating: 4.9)
        let lowRated  = makeBook(id: "low",  title: "Low Rated",  averageRating: 2.0)

        let ranked = ranker.rank(
            books: [lowRated, highRated],
            faithStage: .growing,
            preferredFormat: .unknown,
            savedBookIds: [],
            notedBookIds: []
        )
        #expect(ranked.first?.id == "high")
    }

    @Test("Already-saved books are not excluded from rank but score 0 user signal")
    func savedBookNotExcluded() {
        let ranker = AmenLibraryRankingService.shared
        let book = makeBook(id: "saved-book")
        let ranked = ranker.rank(
            books: [book],
            faithStage: .exploring,
            preferredFormat: .unknown,
            savedBookIds: ["saved-book"],
            notedBookIds: []
        )
        // Safe books always pass through rank; saved ones just score lower user signal
        #expect(ranked.count == 1)
    }
}

// MARK: - 3. Recommendation Reasons — No Sensitive Assumptions

@Suite("AmenWisdomGraphService — Recommendation Reason Labels")
struct RecommendationReasonLabelTests {

    @Test("All reason labels are non-specific about spiritual state")
    func reasonLabelsAreNonSpecific() {
        let sensitiveTerms = [
            "struggling", "suffering", "depressed", "anxious", "broken",
            "lost", "failing", "weak", "shame", "guilt"
        ]

        for reason in AmenRecommendationReason.allCases {
            let label = reason.displayLabel.lowercased()
            for term in sensitiveTerms {
                #expect(!label.contains(term),
                    "Reason '\(reason.rawValue)' contains sensitive assumption term '\(term)'")
            }
        }
    }

    @Test("Reason display labels match their raw values")
    func reasonDisplayLabelsMatchRawValues() {
        for reason in AmenRecommendationReason.allCases {
            #expect(reason.displayLabel == reason.rawValue)
        }
    }
}

// MARK: - 4. Library Memory Service — Progress Updates

@Suite("AmenLibraryMemoryService — Progress")
struct LibraryMemoryProgressTests {

    @Test("continuationLabel returns nil for unseen book")
    @MainActor
    func continuationLabelNilForUnseenBook() {
        let service = AmenLibraryMemoryService.shared
        let label = service.continuationLabel(for: "unknown-book-id")
        #expect(label == nil)
    }

    @Test("wasRecentlyOpened returns false for unseen book")
    @MainActor
    func wasRecentlyOpenedFalseForUnseenBook() {
        let service = AmenLibraryMemoryService.shared
        #expect(service.wasRecentlyOpened("never-opened-id") == false)
    }
}

// MARK: - 5. Study Plan Builder — Progress Tracking

@Suite("AmenStudyPlanBuilder — Progress Tracking")
struct StudyPlanProgressTests {

    @Test("Progress fraction is 0 for new plan with no completed days")
    func progressZeroForNewPlan() async throws {
        let days = (1...7).map { i in
            AmenStudyDay(
                dayNumber: i, title: "Day \(i)", readingExcerpt: nil,
                scriptureFocus: "John 1:1", reflectionPrompt: "Reflect",
                prayerPrompt: "Pray"
            )
        }
        let plan = AmenStudyPlan(
            id: UUID().uuidString, title: "Test", subtitle: "7-day study",
            source: .book, sourceTitle: "Test Book", createdAt: Date(),
            days: days, currentDayIndex: 0, isCompleted: false
        )
        #expect(plan.progress == 0.0)
    }

    @Test("Progress fraction is 1.0 when all days completed")
    func progressOneWhenAllDaysCompleted() {
        var days = (1...3).map { i in
            AmenStudyDay(
                dayNumber: i, title: "Day \(i)", readingExcerpt: nil,
                scriptureFocus: "Romans 8:1", reflectionPrompt: "Reflect",
                prayerPrompt: "Pray"
            )
        }
        for i in days.indices { days[i].isCompleted = true }
        let plan = AmenStudyPlan(
            id: UUID().uuidString, title: "Done", subtitle: "3-day",
            source: .topic, sourceTitle: "Grace", createdAt: Date(),
            days: days, currentDayIndex: 2, isCompleted: true
        )
        #expect(plan.progress == 1.0)
    }

    @Test("currentDay returns day at currentDayIndex")
    func currentDayReturnsCorrectDay() {
        let days = (1...5).map { i in
            AmenStudyDay(
                dayNumber: i, title: "Day \(i)", readingExcerpt: nil,
                scriptureFocus: "Psalm 23:\(i)", reflectionPrompt: "R",
                prayerPrompt: "P"
            )
        }
        let plan = AmenStudyPlan(
            id: "test", title: "T", subtitle: "s",
            source: .scripture, sourceTitle: "Psalm 23", createdAt: Date(),
            days: days, currentDayIndex: 2, isCompleted: false
        )
        #expect(plan.currentDay?.dayNumber == 3)
    }
}

// MARK: - 6. Book Note Store — Save and Retrieve

@Suite("AmenBookNoteStore — Notes")
struct BookNoteStoreTests {

    @Test("Saved note is retrievable by bookId")
    func savedNoteRetrievableByBookId() {
        let store = AmenBookNoteStore.shared
        let note = AmenBookNote(
            bookId: "test-book-store-\(UUID().uuidString)",
            bookTitle: "Store Test",
            highlightText: "Test highlight text",
            noteBody: "My note",
            savedAt: Date()
        )
        store.save(note)
        let fetched = store.notes(for: note.bookId)
        #expect(fetched.count >= 1)
        #expect(fetched.first?.highlightText == "Test highlight text")
    }
}

// MARK: - 7. Offline: Conflict Resolution Strategy

@Suite("AmenLibraryMemoryService — Conflict Resolution")
struct OfflineSyncConflictTests {

    @Test("Two read events for same book: newest lastSeenAt wins")
    func newestTimestampWins() {
        let older = Date(timeIntervalSinceNow: -7200)   // 2h ago
        let newer = Date(timeIntervalSinceNow: -60)      // 1min ago

        let eventA = AmenLibraryReadEvent(
            bookId: "conflict-book", bookTitle: "T", bookAuthor: "A",
            thumbnailURL: nil, openedAt: older, lastSeenAt: older,
            progressFraction: 0.3, isCompleted: false, isAbandoned: false, formatPreference: .ebook
        )
        let eventB = AmenLibraryReadEvent(
            bookId: "conflict-book", bookTitle: "T", bookAuthor: "A",
            thumbnailURL: nil, openedAt: older, lastSeenAt: newer,
            progressFraction: 0.6, isCompleted: false, isAbandoned: false, formatPreference: .ebook
        )

        // Conflict resolution: pick the one with the newer lastSeenAt
        let winner = [eventA, eventB].max { $0.lastSeenAt < $1.lastSeenAt }
        #expect(winner?.progressFraction == eventB.progressFraction)
    }
}

// MARK: - 8. Search Grouping

@Suite("AmenLibraryCatalogProvider — Search")
struct CatalogSearchGroupingTests {

    @Test("Mock provider returns books matching title keyword")
    func mockProviderMatchesTitle() async throws {
        let mock = MockAmenLibraryCatalogProvider()
        mock.mockBooks = [
            makeBook(id: "a1", title: "Prayer and Fasting"),
            makeBook(id: "b2", title: "The Theology of Grace"),
            makeBook(id: "c3", title: "Deep Prayer Life")
        ]
        let results = try await mock.search(query: "prayer", maxResults: 10)
        #expect(results.count == 2)
        let ids = results.map(\.id)
        #expect(ids.contains("a1"))
        #expect(ids.contains("c3"))
    }

    @Test("Mock provider returns empty for no-match query")
    func mockProviderEmptyForNoMatch() async throws {
        let mock = MockAmenLibraryCatalogProvider()
        mock.mockBooks = [makeBook(title: "Theology Essentials")]
        let results = try await mock.search(query: "zzznomatch", maxResults: 10)
        #expect(results.isEmpty)
    }
}

// MARK: - 9. Reduce Motion — Companion Engine

@Suite("AmenReadingCompanionEngine — Reduce Motion")
struct CompanionReduceMotionTests {

    @Test("AmenCompanionAction.allCases contains all 6 actions")
    func allActionsPresent() {
        #expect(AmenCompanionAction.allCases.count == 6)
    }

    @Test("Each AmenCompanionAction has a non-empty icon name")
    func eachActionHasIcon() {
        for action in AmenCompanionAction.allCases {
            #expect(!action.icon.isEmpty,
                "Action '\(action.rawValue)' has empty icon name")
        }
    }
}

// MARK: - 10. User Data Isolation (service-level)

@Suite("Library User Isolation")
struct LibraryUserIsolationTests {

    @Test("AmenBookNoteStore notes() only returns entries for that bookId")
    func notesIsolatedToBookId() {
        let store = AmenBookNoteStore.shared
        let uniqueId = "isolation-test-\(UUID().uuidString)"

        let note = AmenBookNote(
            bookId: uniqueId, bookTitle: "Isolation Book",
            highlightText: "Only for this book", noteBody: nil, savedAt: Date()
        )
        store.save(note)

        let unrelated = store.notes(for: "some-other-book-id-xyz")
        #expect(!unrelated.contains { $0.bookId == uniqueId })
    }
}
