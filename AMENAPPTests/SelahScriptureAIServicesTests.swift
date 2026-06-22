// SelahScriptureAIServicesTests.swift
// AMENAPPTests
//
// Contract tests for the three AI service surfaces. Since these services
// call `ClaudeService.shared` (a live backend), we don't assert on remote
// responses here — only on:
//   * Input validation (empty input → throws).
//   * Result envelope shape (AI-generated label always set).
//   * Rewrite mode metadata (all four modes have a system suffix).
//
// Full live integration is exercised via the existing Berean/Selah test
// path; this suite locks the local contract.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@MainActor
@Suite("SelahScriptureAIServices")
struct SelahScriptureAIServicesTests {

    @Test("AIResult always marks itself as AI-generated")
    func resultIsLabeled() {
        let result = SelahScriptureAIResult(content: "Some text", citations: ["John 3:16"])
        #expect(result.isAIGenerated == true)
        #expect(!result.content.isEmpty)
        #expect(result.citations.contains("John 3:16"))
    }

    @Test("Reflection rewriting throws on empty input")
    func emptyRewriteThrows() async {
        var didThrow = false
        do {
            _ = try await SelahReflectionRewritingService.shared.rewrite("   ", mode: .simplify)
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

    @Test("Scripture Companion throws on empty question")
    func emptyCompanionThrows() async {
        var didThrow = false
        let ref = SelahScriptureReference(bookId: "john", chapter: 3, startVerse: 16, endVerse: nil)
        do {
            _ = try await SelahScriptureCompanionService.shared.ask(
                "  ",
                about: ref,
                translationAbbreviation: "KJV",
                visibleVerses: []
            )
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

    @Test("Every reflection-rewrite mode has a non-empty system suffix")
    func everyModeHasSuffix() {
        for mode in SelahReflectionRewriteMode.allCases {
            #expect(!mode.systemSuffix.isEmpty)
            #expect(!mode.displayName.isEmpty)
        }
    }

    @Test("Reflection-rewrite mode raw values are stable")
    func modeRawValues() {
        #expect(SelahReflectionRewriteMode.simplify.rawValue == "simplify")
        #expect(SelahReflectionRewriteMode.poetic.rawValue == "poetic")
        #expect(SelahReflectionRewriteMode.journal.rawValue == "journal")
        #expect(SelahReflectionRewriteMode.prayer.rawValue == "prayer")
    }
}

#endif
