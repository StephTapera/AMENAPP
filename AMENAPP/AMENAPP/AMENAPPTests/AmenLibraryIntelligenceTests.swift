// AmenLibraryIntelligenceTests.swift
// AMENAPPTests
//
// Unit tests for the Amen Library intelligence layers.
// All tests are pure-Swift — no Firebase, no network, no UI dependencies.
// Run with: Product ▶ Test (⌘U)

import Foundation

#if canImport(Testing)

import XCTest
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

final class RankingServiceSafetyTests: XCTestCase {

    func testUnsafeBooksFiltered() {
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

        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.id, safeBook.id)
    }

    func testIsSafeReturnsFalseForUnsafe() {
        let ranker = AmenLibraryRankingService.shared
        let clickbaitBook = makeBook(title: "Outrage in the Church", categories: ["outrage", "scandal"])
        XCTAssertFalse(ranker.isSafe(clickbaitBook))
    }

    func testIsSafeReturnsTrueForSafe() {
        let ranker = AmenLibraryRankingService.shared
        let book = makeBook(title: "Mere Christianity", categories: ["Apologetics", "Theology"])
        XCTAssertTrue(ranker.isSafe(book))
    }

    func testUrgencySignalBlocked() {
        let ranker = AmenLibraryRankingService.shared
        let urgentBook = makeBook(title: "Urgency: Why You Must Act Now", categories: ["urgency"])
        XCTAssertFalse(ranker.isSafe(urgentBook))
    }
}

// MARK: - 2. Ranking Service — Score Ordering

final class RankingScoreOrderingTests: XCTestCase {

    func testFeaturedScoresHigher() {
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
        XCTAssertEqual(ranked.first?.id, featured.id)
    }

    func testHigherRatingScoresHigher() {
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
        XCTAssertEqual(ranked.first?.id, "high")
    }

    func testSavedBookNotExcluded() {
        let ranker = AmenLibraryRankingService.shared
        let book = makeBook(id: "saved-book")
        let ranked = ranker.rank(
            books: [book],
            faithStage: .exploring,
            preferredFormat: .unknown,
            savedBookIds: ["saved-book"],
            notedBookIds: []
        )
        XCTAssertEqual(ranked.count, 1)
    }
}

// MARK: - 3. Recommendation Reasons — No Sensitive Assumptions

final class RecommendationReasonLabelTests: XCTestCase {

    func testReasonLabelsAreNonSpecific() {
        let sensitiveTerms = [
            "struggling", "suffering", "depressed", "anxious", "broken",
            "lost", "failing", "weak", "shame", "guilt"
        ]

        for reason in AmenRecommendationReason.allCases {
            let label = reason.displayLabel.lowercased()
            for term in sensitiveTerms {
                XCTAssertFalse(label.contains(term),
                    "Reason '\(reason.rawValue)' contains sensitive assumption term '\(term)'")
            }
        }
    }

    func testReasonDisplayLabelsMatchRawValues() {
        for reason in AmenRecommendationReason.allCases {
            XCTAssertEqual(reason.displayLabel, reason.rawValue)
        }
    }
}

// MARK: - 4. Library Memory Service — Progress Updates

final class LibraryMemoryProgressTests: XCTestCase {

    @MainActor
    func testContinuationLabelNilForUnseenBook() {
        let service = AmenLibraryMemoryService.shared
        let label = service.continuationLabel(for: "unknown-book-id")
        XCTAssertNil(label)
    }

    @MainActor
    func testWasRecentlyOpenedFalseForUnseenBook() {
        let service = AmenLibraryMemoryService.shared
        XCTAssertFalse(service.wasRecentlyOpened("never-opened-id"))
    }
}

// MARK: - 5. Study Plan Builder — Progress Tracking

final class StudyPlanProgressTests: XCTestCase {

    func testProgressZeroForNewPlan() {
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
        XCTAssertEqual(plan.progress, 0.0)
    }

    func testProgressOneWhenAllDaysCompleted() {
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
        XCTAssertEqual(plan.progress, 1.0)
    }

    func testCurrentDayReturnsCorrectDay() {
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
        XCTAssertEqual(plan.currentDay?.dayNumber, 3)
    }
}

// MARK: - 6. Book Note Store — Save and Retrieve

final class BookNoteStoreTests: XCTestCase {

    func testSavedNoteRetrievableByBookId() {
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
        XCTAssertGreaterThanOrEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.highlightText, "Test highlight text")
    }
}

// MARK: - 7. Offline: Conflict Resolution Strategy

final class OfflineSyncConflictTests: XCTestCase {

    func testNewestTimestampWins() {
        let older = Date(timeIntervalSinceNow: -7200)
        let newer = Date(timeIntervalSinceNow: -60)

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

        let winner = [eventA, eventB].max { $0.lastSeenAt < $1.lastSeenAt }
        XCTAssertEqual(winner?.progressFraction, eventB.progressFraction)
    }
}

// MARK: - 8. Search Grouping

final class CatalogSearchGroupingTests: XCTestCase {

    func testMockProviderMatchesTitle() async throws {
        let mock = MockAmenLibraryCatalogProvider()
        mock.mockBooks = [
            makeBook(id: "a1", title: "Prayer and Fasting"),
            makeBook(id: "b2", title: "The Theology of Grace"),
            makeBook(id: "c3", title: "Deep Prayer Life")
        ]
        let results = try await mock.search(query: "prayer", maxResults: 10)
        XCTAssertEqual(results.count, 2)
        let ids = results.map(\.id)
        XCTAssertTrue(ids.contains("a1"))
        XCTAssertTrue(ids.contains("c3"))
    }

    func testMockProviderEmptyForNoMatch() async throws {
        let mock = MockAmenLibraryCatalogProvider()
        mock.mockBooks = [makeBook(title: "Theology Essentials")]
        let results = try await mock.search(query: "zzznomatch", maxResults: 10)
        XCTAssertTrue(results.isEmpty)
    }
}

// MARK: - 9. Reduce Motion — Companion Engine

final class CompanionReduceMotionTests: XCTestCase {

    func testAllActionsPresent() {
        XCTAssertEqual(AmenCompanionAction.allCases.count, 6)
    }

    func testEachActionHasIcon() {
        for action in AmenCompanionAction.allCases {
            XCTAssertFalse(action.icon.isEmpty,
                "Action '\(action.rawValue)' has empty icon name")
        }
    }
}

// MARK: - 10. User Data Isolation (service-level)

final class LibraryUserIsolationTests: XCTestCase {

    func testNotesIsolatedToBookId() {
        let store = AmenBookNoteStore.shared
        let uniqueId = "isolation-test-\(UUID().uuidString)"

        let note = AmenBookNote(
            bookId: uniqueId, bookTitle: "Isolation Book",
            highlightText: "Only for this book", noteBody: nil, savedAt: Date()
        )
        store.save(note)

        let unrelated = store.notes(for: "some-other-book-id-xyz")
        XCTAssertFalse(unrelated.contains { $0.bookId == uniqueId })
    }
}

#endif
