// SelahScriptureReferenceParserTests.swift
// AMENAPPTests
//
// Contract tests for the user-facing scripture reference parser.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@MainActor
@Suite("SelahScriptureReferenceParser")
struct SelahScriptureReferenceParserTests {

    @Test("Parses simple book + chapter + verse (John 3:16)")
    func simpleReference() {
        let ref = SelahScriptureReferenceParser.parse("John 3:16")
        #expect(ref?.bookId == "john")
        #expect(ref?.chapter == 3)
        #expect(ref?.startVerse == 16)
        #expect(ref?.endVerse == nil)
        #expect(ref?.isSingleVerse == true)
    }

    @Test("Parses verse range (Romans 5:3-5)")
    func verseRange() {
        let ref = SelahScriptureReferenceParser.parse("Romans 5:3-5")
        #expect(ref?.bookId == "romans")
        #expect(ref?.chapter == 5)
        #expect(ref?.startVerse == 3)
        #expect(ref?.endVerse == 5)
    }

    @Test("Parses whole-chapter reference (Psalm 23)")
    func wholeChapter() {
        let ref = SelahScriptureReferenceParser.parse("Psalm 23")
        #expect(ref?.bookId == "psalms")
        #expect(ref?.chapter == 23)
        #expect(ref?.isWholeChapter == true)
    }

    @Test("Handles common abbreviations (Rom 5:8)")
    func abbreviations() {
        let ref = SelahScriptureReferenceParser.parse("Rom 5:8")
        #expect(ref?.bookId == "romans")
        #expect(ref?.chapter == 5)
        #expect(ref?.startVerse == 8)
    }

    @Test("Handles numbered books (1 Corinthians 13:4)")
    func numberedBook() {
        let ref = SelahScriptureReferenceParser.parse("1 Corinthians 13:4")
        #expect(ref?.bookId == "corinthians1")
        #expect(ref?.chapter == 13)
        #expect(ref?.startVerse == 4)
    }

    @Test("Handles compact numbered abbreviation (1 Cor 13)")
    func numberedAbbreviation() {
        let ref = SelahScriptureReferenceParser.parse("1 Cor 13")
        #expect(ref?.bookId == "corinthians1")
        #expect(ref?.chapter == 13)
        #expect(ref?.isWholeChapter == true)
    }

    @Test("Case-insensitive input")
    func caseInsensitive() {
        let ref = SelahScriptureReferenceParser.parse("psalm 1")
        #expect(ref?.bookId == "psalms")
        #expect(ref?.chapter == 1)
    }

    @Test("Stripped punctuation still parses")
    func noisyPunctuation() {
        let ref = SelahScriptureReferenceParser.parse(" John 3:16. ")
        #expect(ref?.bookId == "john")
        #expect(ref?.chapter == 3)
        #expect(ref?.startVerse == 16)
    }

    @Test("Returns nil on empty input")
    func emptyInput() {
        #expect(SelahScriptureReferenceParser.parse("") == nil)
        #expect(SelahScriptureReferenceParser.parse("   ") == nil)
    }

    @Test("Returns nil for unrecognized book")
    func unknownBook() {
        #expect(SelahScriptureReferenceParser.parse("Foo 1:1") == nil)
    }

    @Test("Returns nil for malformed chapter")
    func malformedChapter() {
        #expect(SelahScriptureReferenceParser.parse("John abc:1") == nil)
    }

    @Test("Compact form without space (rom5)")
    func compactCompactNumeric() {
        let ref = SelahScriptureReferenceParser.parse("rom5")
        #expect(ref?.bookId == "romans")
        #expect(ref?.chapter == 5)
    }

    @Test("suggestBooks returns multiple matches for short prefix")
    func suggestionsForShortPrefix() {
        let suggestions = SelahScriptureReferenceParser.suggestBooks(prefix: "joh", limit: 10)
        #expect(suggestions.contains("john"))
        #expect(suggestions.contains("john1"))
        #expect(suggestions.contains("john2"))
        #expect(suggestions.contains("john3"))
    }

    @Test("displayString round-trips for verse")
    func displayStringSingleVerse() {
        let ref = SelahScriptureReferenceParser.parse("John 3:16")!
        #expect(ref.displayString == "John 3:16")
    }

    @Test("displayString uses display name for whole chapter")
    func displayStringWholeChapter() {
        let ref = SelahScriptureReferenceParser.parse("Psalm 23")!
        #expect(ref.displayString == "Psalms 23")
    }
}

#endif
