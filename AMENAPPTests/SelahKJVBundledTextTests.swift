// SelahKJVBundledTextTests.swift
// AMENAPPTests
//
// Confidence tests for the expanded inline KJV catalog. These pin that
// the most-referenced chapters exist, have real (non-empty) text, and
// belong to a known canonical book.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@MainActor
@Suite("SelahKJVBundledText")
struct SelahKJVBundledTextTests {

    @Test("Catalog contains at least 20 chapters")
    func catalogSize() {
        #expect(SelahKJVBundledText.allChapters.count >= 20)
    }

    @Test("Every bundled chapter belongs to a canonical book")
    func chaptersBelongToCanon() {
        for chapter in SelahKJVBundledText.allChapters {
            let book = SelahBibleBook.find(id: chapter.bookId)
            #expect(book != nil, "Unknown book id: \(chapter.bookId)")
            // Chapter number must be within the book's chapter count.
            if let book {
                let inRange = chapter.chapter >= 1 && chapter.chapter <= book.chapterCount
                #expect(inRange, "\(book.displayName) \(chapter.chapter) out of range (max \(book.chapterCount))")
            }
        }
    }

    @Test("Every bundled chapter has at least one non-empty verse")
    func chaptersHaveContent() {
        for chapter in SelahKJVBundledText.allChapters {
            #expect(!chapter.verses.isEmpty, "\(chapter.bookId) \(chapter.chapter) has no verses")
            let firstNonEmpty = chapter.verses.first { !$0.text.isEmpty }
            #expect(firstNonEmpty != nil, "\(chapter.bookId) \(chapter.chapter) has only empty verses")
        }
    }

    @Test("Verse references are consistent with their parent chapter")
    func verseReferencesConsistent() {
        for chapter in SelahKJVBundledText.allChapters {
            for verse in chapter.verses {
                #expect(verse.reference.bookId == chapter.bookId)
                #expect(verse.reference.chapter == chapter.chapter)
                #expect(verse.reference.startVerse == verse.number)
            }
        }
    }

    @Test("Iconic verses are present: John 3:16, Psalm 23:1, Romans 8:28")
    func iconicVersesPresent() {
        let john3 = SelahKJVBundledText.chapter(bookId: "john", chapter: 3)
        let psalm23 = SelahKJVBundledText.chapter(bookId: "psalms", chapter: 23)
        let romans8 = SelahKJVBundledText.chapter(bookId: "romans", chapter: 8)
        #expect(john3?.verses.contains(where: { $0.number == 16 }) == true)
        #expect(psalm23?.verses.contains(where: { $0.number == 1 }) == true)
        #expect(romans8?.verses.contains(where: { $0.number == 28 }) == true)
    }

    @Test("All chapters declare translation id 'kjv'")
    func allKJV() {
        for chapter in SelahKJVBundledText.allChapters {
            #expect(chapter.translationId == "kjv")
        }
    }
}

#endif
