// SelahBibleTranslationProviderTests.swift
// AMENAPPTests
//
// Contract tests for the BibleTranslationProvider stack: KJV availability,
// remote placeholder honesty, and the composite router.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@MainActor
@Suite("SelahBibleTranslationProvider stack")
struct SelahBibleTranslationProviderTests {

    // MARK: - Local KJV provider

    @Test("Local provider declares KJV available")
    func localKJVAvailable() {
        let provider = SelahLocalPublicDomainBibleProvider()
        let isAvailable = provider.availability(for: .kjv) == .available
        #expect(isAvailable)
    }

    @Test("Local provider declares non-KJV translations unavailable with a reason")
    func localNonKJVUnavailable() {
        let provider = SelahLocalPublicDomainBibleProvider()
        let availability = provider.availability(for: .esv)
        if case .unavailable(let reason) = availability {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("Expected .unavailable for ESV via local provider")
        }
    }

    @Test("Local provider serves a real bundled KJV chapter (John 3)")
    func localServesBundledChapter() async throws {
        let provider = SelahLocalPublicDomainBibleProvider()
        let chapter = try await provider.loadChapter(bookId: "john", chapter: 3, translation: .kjv)
        #expect(chapter.bookId == "john")
        #expect(chapter.chapter == 3)
        #expect(chapter.translationId == "kjv")
        #expect(!chapter.verses.isEmpty)
        let containsVerse16 = chapter.verses.contains { verse in
            verse.number == 16
        }
        #expect(containsVerse16)
        // Honest text — no mock string
        let john16 = chapter.verses.first { $0.number == 16 }
        let john16ContainsExpectedText = john16?.text.contains("For God so loved the world") == true
        #expect(john16ContainsExpectedText)
    }

    @Test("Local provider throws chapterNotFound when chapter isn't bundled")
    func localUnbundledChapterThrows() async {
        let provider = SelahLocalPublicDomainBibleProvider()
        do {
            _ = try await provider.loadChapter(bookId: "matthew", chapter: 5, translation: .kjv)
            Issue.record("Expected chapterNotFound for unbundled Matthew 5")
        } catch let error as SelahBibleTranslationProviderError {
            let isExpectedError = error == .chapterNotFound(bookId: "matthew", chapter: 5)
            #expect(isExpectedError)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Local provider rejects unknown books")
    func localUnknownBookThrows() async {
        let provider = SelahLocalPublicDomainBibleProvider()
        do {
            _ = try await provider.loadChapter(bookId: "foo", chapter: 1, translation: .kjv)
            Issue.record("Expected bookNotFound")
        } catch let error as SelahBibleTranslationProviderError {
            let isExpectedError = error == .bookNotFound(bookId: "foo")
            #expect(isExpectedError)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Local provider keyword search finds matches in bundled text")
    func localKeywordSearchFindsMatches() async throws {
        let provider = SelahLocalPublicDomainBibleProvider()
        let hits = try await provider.search(keyword: "shepherd", translation: .kjv, limit: 10)
        #expect(!hits.isEmpty)
        let containsPsalm23 = hits.contains { hit in
            hit.reference.bookId == "psalms" && hit.reference.chapter == 23
        }
        #expect(containsPsalm23)
    }

    @Test("Local provider keyword search returns empty for non-KJV translation")
    func localKeywordSearchEmptyForNonKJV() async throws {
        let provider = SelahLocalPublicDomainBibleProvider()
        let hits = try await provider.search(keyword: "shepherd", translation: .esv, limit: 10)
        #expect(hits.isEmpty)
    }

    // MARK: - Remote placeholder

    @Test("Remote provider returns unavailable for every supported translation")
    func remoteAlwaysUnavailable() {
        let provider = SelahRemoteBibleProvider()
        for translation in provider.supportedTranslations {
            if case .available = provider.availability(for: translation) {
                Issue.record("Remote placeholder should never report \(translation.id) as available")
            }
        }
    }

    @Test("Remote provider never returns mock text from loadChapter")
    func remoteLoadChapterThrows() async {
        let provider = SelahRemoteBibleProvider()
        do {
            _ = try await provider.loadChapter(bookId: "romans", chapter: 5, translation: .esv)
            Issue.record("Remote placeholder must not return chapter content")
        } catch {
            // Expected
        }
    }

    @Test("Remote provider search returns empty list (no fabricated results)")
    func remoteSearchEmpty() async throws {
        let provider = SelahRemoteBibleProvider()
        let hits = try await provider.search(keyword: "peace", translation: .niv, limit: 5)
        #expect(hits.isEmpty)
    }

    // MARK: - Composite

    @Test("Composite routes KJV requests to local provider")
    func compositeRoutesKJVLocally() async throws {
        let composite = SelahCompositeBibleProvider()
        let chapter = try await composite.loadChapter(bookId: "psalms", chapter: 23, translation: .kjv)
        #expect(chapter.bookId == "psalms")
        #expect(chapter.chapter == 23)
        let firstVerseMentionsShepherd = chapter.verses.first?.text.contains("shepherd") == true
        #expect(firstVerseMentionsShepherd)
    }

    @Test("Composite reports licensed translations as unavailable until remote ships")
    func compositeUnavailableForLicensed() {
        let composite = SelahCompositeBibleProvider()
        if case .available = composite.availability(for: .niv) {
            Issue.record("Composite must not claim NIV available without remote credentials")
        }
    }

    @Test("Composite exposes the full union of supported translations")
    func compositeUnion() {
        let composite = SelahCompositeBibleProvider()
        let ids = composite.supportedTranslations.map { $0.id }
        #expect(ids.contains("kjv"))
        #expect(ids.contains("esv"))
        #expect(ids.contains("nlt"))
    }
}

#endif
