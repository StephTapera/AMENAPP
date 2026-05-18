// SelahKJVTextIntegrityTests.swift
// AMENAPPTests
//
// Pinned-text integrity check for the inline KJV catalog. These tests
// match each iconic verse against its canonical KJV wording (public
// domain) character-for-character. If the bundled text drifts from the
// canonical KJV, these tests fail loudly — the safest defense against
// silent transcription typos in scripture.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

private func verseText(_ bookId: String, _ chapter: Int, _ verseNumber: Int) -> String? {
    SelahKJVBundledText.chapter(bookId: bookId, chapter: chapter)?
        .verses.first(where: { $0.number == verseNumber })?.text
}

@MainActor
@Suite("SelahKJVBundledText integrity")
struct SelahKJVTextIntegrityTests {

    @Test("Psalm 23:1 matches canonical KJV")
    func psalm23_1() {
        let canonical = "The LORD is my shepherd; I shall not want."
        #expect(verseText("psalms", 23, 1) == canonical)
    }

    @Test("Psalm 23:4 matches canonical KJV")
    func psalm23_4() {
        let canonical = "Yea, though I walk through the valley of the shadow of death, I will fear no evil: for thou art with me; thy rod and thy staff they comfort me."
        #expect(verseText("psalms", 23, 4) == canonical)
    }

    @Test("John 3:16 matches canonical KJV")
    func john3_16() {
        let canonical = "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life."
        #expect(verseText("john", 3, 16) == canonical)
    }

    @Test("Romans 8:28 matches canonical KJV")
    func romans8_28() {
        let canonical = "And we know that all things work together for good to them that love God, to them who are the called according to his purpose."
        #expect(verseText("romans", 8, 28) == canonical)
    }

    @Test("Romans 8:38 matches canonical KJV")
    func romans8_38() {
        let canonical = "For I am persuaded, that neither death, nor life, nor angels, nor principalities, nor powers, nor things present, nor things to come,"
        #expect(verseText("romans", 8, 38) == canonical)
    }

    @Test("1 Corinthians 13:13 matches canonical KJV")
    func corinthians13_13() {
        let canonical = "And now abideth faith, hope, charity, these three; but the greatest of these is charity."
        #expect(verseText("corinthians1", 13, 13) == canonical)
    }

    @Test("Philippians 4:13 matches canonical KJV")
    func philippians4_13() {
        let canonical = "I can do all things through Christ which strengtheneth me."
        #expect(verseText("philippians", 4, 13) == canonical)
    }

    @Test("Isaiah 40:31 matches canonical KJV")
    func isaiah40_31() {
        let canonical = "But they that wait upon the LORD shall renew their strength; they shall mount up with wings as eagles; they shall run, and not be weary; and they shall walk, and not faint."
        #expect(verseText("isaiah", 40, 31) == canonical)
    }

    @Test("Hebrews 11:1 matches canonical KJV")
    func hebrews11_1() {
        let canonical = "Now faith is the substance of things hoped for, the evidence of things not seen."
        #expect(verseText("hebrews", 11, 1) == canonical)
    }

    @Test("Proverbs 3:5 matches canonical KJV")
    func proverbs3_5() {
        let canonical = "Trust in the LORD with all thine heart; and lean not unto thine own understanding."
        #expect(verseText("proverbs", 3, 5) == canonical)
    }

    @Test("Genesis 1:1 matches canonical KJV")
    func genesis1_1() {
        let canonical = "In the beginning God created the heaven and the earth."
        #expect(verseText("genesis", 1, 1) == canonical)
    }

    @Test("Matthew 5:8 (pure in heart beatitude) matches canonical KJV")
    func matthew5_8() {
        let canonical = "Blessed are the pure in heart: for they shall see God."
        #expect(verseText("matthew", 5, 8) == canonical)
    }

    @Test("Revelation 21:4 matches canonical KJV")
    func revelation21_4() {
        let canonical = "And God shall wipe away all tears from their eyes; and there shall be no more death, neither sorrow, nor crying, neither shall there be any more pain: for the former things are passed away."
        #expect(verseText("revelation", 21, 4) == canonical)
    }
}

#endif
