// SelahLastReadResolverTests.swift
// AMENAPPTests
//
// Pure-resolver contract tests for SelahLastReadResolver — the logic that
// drives the "Continue in <reference>" banner in SelahView. These tests
// pin the contract that:
//   1. The banner stays hidden (nil entry) when there is no eligible
//      persisted reading state.
//   2. The banner surfaces a real entry when valid sessions exist.
//   3. The resolved reference matches the most-recent eligible session,
//      so tapping the banner can route to the correct verse.
//   4. No mock / fabricated scripture state is ever produced — empty or
//      empty-ref input always returns nil (this is the production default
//      when the user has no Selah history).

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

// MARK: - Test Fixtures

private func makeSession(
    id: String = UUID().uuidString,
    title: String = "",
    scriptureRefs: [String] = [],
    createdAt: Date = Date()
) -> SelahSession {
    var session = SelahSession(
        userId: "test-uid",
        title: title,
        query: "",
        responsePreview: "",
        format: "Essay",
        scriptureRefs: scriptureRefs,
        tags: [],
        createdAt: createdAt,
        updatedAt: createdAt
    )
    session.id = id
    return session
}

// MARK: - Tests

@MainActor
@Suite("SelahLastReadResolver")
struct SelahLastReadResolverTests {

    // MARK: 1. Banner hidden with no reading state

    @Test("Returns nil when there are no persisted sessions (banner hidden)")
    func emptySessionsReturnsNil() {
        let entry = SelahLastReadResolver.resolve(sessions: [])
        #expect(entry == nil)
    }

    @Test("Returns nil when sessions exist but none carry a scripture reference")
    func sessionsWithoutScriptureRefsReturnsNil() {
        let sessions: [SelahSession] = [
            makeSession(scriptureRefs: []),
            makeSession(scriptureRefs: []),
        ]
        let entry = SelahLastReadResolver.resolve(sessions: sessions)
        #expect(entry == nil)
    }

    @Test("Returns nil when the only session's first reference is whitespace-only")
    func sessionsWithBlankScriptureRefReturnsNil() {
        let sessions: [SelahSession] = [
            makeSession(scriptureRefs: ["   "])
        ]
        let entry = SelahLastReadResolver.resolve(sessions: sessions)
        #expect(entry == nil)
    }

    @Test("Returns nil when every session is older than the freshness window")
    func ignoresAncientSessions() {
        let now = Date()
        let ancient = now.addingTimeInterval(-60 * 24 * 60 * 60) // 60 days ago
        let sessions: [SelahSession] = [
            makeSession(scriptureRefs: ["Romans 5"], createdAt: ancient)
        ]
        let entry = SelahLastReadResolver.resolve(
            sessions: sessions,
            now: now,
            maxAge: 30 * 24 * 60 * 60
        )
        #expect(entry == nil)
    }

    // MARK: 2. Banner shown with valid reading state

    @Test("Returns the most recent session within the freshness window")
    func returnsMostRecentInWindow() {
        let now = Date()
        let day: TimeInterval = 24 * 60 * 60
        let sessions: [SelahSession] = [
            makeSession(title: "Older", scriptureRefs: ["Psalm 23"], createdAt: now.addingTimeInterval(-5 * day)),
            makeSession(title: "Most Recent", scriptureRefs: ["Romans 5"], createdAt: now.addingTimeInterval(-1 * day)),
            makeSession(title: "Middle", scriptureRefs: ["John 3"], createdAt: now.addingTimeInterval(-2 * day)),
        ]
        let entry = SelahLastReadResolver.resolve(sessions: sessions, now: now)
        #expect(entry?.reference == "Romans 5")
        #expect(entry?.sessionTitle == "Most Recent")
    }

    @Test("Falls back to the reference text when the session title is empty")
    func emptyTitleFallsBackToReference() {
        let sessions: [SelahSession] = [
            makeSession(title: "", scriptureRefs: ["1 Corinthians 13"], createdAt: Date())
        ]
        let entry = SelahLastReadResolver.resolve(sessions: sessions)
        #expect(entry?.reference == "1 Corinthians 13")
        #expect(entry?.sessionTitle == "1 Corinthians 13")
    }

    @Test("Trims whitespace-only titles before deciding fallback")
    func whitespaceTitleFallsBackToReference() {
        let sessions: [SelahSession] = [
            makeSession(title: "   \n  ", scriptureRefs: ["Hebrews 11"], createdAt: Date())
        ]
        let entry = SelahLastReadResolver.resolve(sessions: sessions)
        #expect(entry?.sessionTitle == "Hebrews 11")
    }

    // MARK: 3. Exclusion: don't surface what's already on screen

    @Test("Excludes sessions whose first ref already matches the current surface")
    func excludesCurrentReference() {
        let now = Date()
        let sessions: [SelahSession] = [
            makeSession(title: "Now Reading", scriptureRefs: ["Romans 5"], createdAt: now.addingTimeInterval(-30)),
            makeSession(title: "Earlier",     scriptureRefs: ["Psalm 23"], createdAt: now.addingTimeInterval(-3600)),
        ]
        let entry = SelahLastReadResolver.resolve(
            sessions: sessions,
            excluding: ["Romans 5"],
            now: now
        )
        // Should fall through to the next-most-recent eligible session
        #expect(entry?.reference == "Psalm 23")
        #expect(entry?.sessionTitle == "Earlier")
    }

    @Test("Returns nil when every eligible session is already on screen")
    func returnsNilWhenAllExcluded() {
        let sessions: [SelahSession] = [
            makeSession(title: "A", scriptureRefs: ["Romans 5"]),
            makeSession(title: "B", scriptureRefs: ["John 3:16"]),
        ]
        let entry = SelahLastReadResolver.resolve(
            sessions: sessions,
            excluding: ["Romans 5", "John 3:16"]
        )
        #expect(entry == nil)
    }

    // MARK: 4. Honesty: no fabricated state

    @Test("Resolver is pure — identical inputs always produce identical outputs")
    func resolverIsDeterministic() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let sessions: [SelahSession] = [
            makeSession(title: "Pinned", scriptureRefs: ["Ephesians 2"], createdAt: fixedDate)
        ]
        let a = SelahLastReadResolver.resolve(sessions: sessions, now: fixedDate.addingTimeInterval(60))
        let b = SelahLastReadResolver.resolve(sessions: sessions, now: fixedDate.addingTimeInterval(60))
        #expect(a == b)
        #expect(a?.reference == "Ephesians 2")
    }

    @Test("Empty session list — the production no-history default — never returns a placeholder entry")
    func productionDefaultProducesNoEntry() {
        // The production resolver path is fed by SelahService.sessions, which
        // is `[]` until Firestore loads. The banner must stay hidden in that
        // state — no mock / sample entry should appear.
        for excluded in [[], ["Romans 5"], ["John 3:16", "Psalm 23"]] {
            let entry = SelahLastReadResolver.resolve(sessions: [], excluding: excluded)
            #expect(entry == nil, "Empty sessions must never resolve to a placeholder entry")
        }
    }
}

#endif
