// SelahVerseEngagementStoreTests.swift
// AMENAPPTests
//
// Behavior tests for the local reactions + prayed-through engagement
// store, backed by an isolated UserDefaults suite per test.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

private func freshDefaults() -> UserDefaults {
    let suiteName = "SelahVerseEngagementStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private let romans5_3 = SelahScriptureReference(bookId: "romans", chapter: 5, startVerse: 3, endVerse: nil)
private let john3_16 = SelahScriptureReference(bookId: "john", chapter: 3, startVerse: 16, endVerse: nil)

@MainActor
@Suite("SelahVerseEngagementStore")
struct SelahVerseEngagementStoreTests {

    @Test("Reactions start empty for a fresh store")
    func emptyAtStart() {
        let store = SelahVerseEngagementStore(defaults: freshDefaults())
        #expect(store.reactions.isEmpty)
        #expect(store.prayedThrough.isEmpty)
    }

    @Test("Adding a reaction persists across instances")
    func addReactionPersists() {
        let defaults = freshDefaults()
        let a = SelahVerseEngagementStore(defaults: defaults)
        a.addReaction(.amen, to: romans5_3, translationId: "kjv")
        #expect(a.reactions.count == 1)

        let b = SelahVerseEngagementStore(defaults: defaults)
        #expect(b.reactions.count == 1)
        #expect(b.reactions.first?.kind == .amen)
    }

    @Test("Adding the same reaction twice is idempotent")
    func idempotentReactions() {
        let store = SelahVerseEngagementStore(defaults: freshDefaults())
        store.addReaction(.peace, to: romans5_3, translationId: "kjv")
        store.addReaction(.peace, to: romans5_3, translationId: "kjv")
        #expect(store.reactions.count == 1)
    }

    @Test("Different reactions on same verse all coexist")
    func multipleReactionKinds() {
        let store = SelahVerseEngagementStore(defaults: freshDefaults())
        store.addReaction(.peace, to: romans5_3, translationId: "kjv")
        store.addReaction(.hope, to: romans5_3, translationId: "kjv")
        #expect(store.reactions.count == 2)
        let kinds = Set(store.reactions.map { $0.kind })
        #expect(kinds == Set([.peace, .hope]))
    }

    @Test("removeReaction strips the matching entry only")
    func removeReaction() {
        let store = SelahVerseEngagementStore(defaults: freshDefaults())
        store.addReaction(.peace, to: romans5_3, translationId: "kjv")
        store.addReaction(.hope, to: romans5_3, translationId: "kjv")
        store.removeReaction(.peace, from: romans5_3, translationId: "kjv")
        #expect(store.reactions.count == 1)
        #expect(store.reactions.first?.kind == .hope)
    }

    @Test("reactions(for:) scopes by verse + translation")
    func reactionsScopedByVerseAndTranslation() {
        let store = SelahVerseEngagementStore(defaults: freshDefaults())
        store.addReaction(.amen, to: romans5_3, translationId: "kjv")
        store.addReaction(.amen, to: john3_16, translationId: "kjv")
        store.addReaction(.amen, to: romans5_3, translationId: "esv")
        let scoped = store.reactions(for: romans5_3, translationId: "kjv")
        #expect(scoped.count == 1)
        #expect(scoped.first?.kind == .amen)
    }

    @Test("Prayed-through starts false and toggles")
    func prayedThroughToggle() {
        let store = SelahVerseEngagementStore(defaults: freshDefaults())
        #expect(!store.hasPrayedThrough(romans5_3, translationId: "kjv"))
        store.togglePrayedThrough(romans5_3, translationId: "kjv")
        #expect(store.hasPrayedThrough(romans5_3, translationId: "kjv"))
        store.togglePrayedThrough(romans5_3, translationId: "kjv")
        #expect(!store.hasPrayedThrough(romans5_3, translationId: "kjv"))
    }

    @Test("Prayed-through persists across instances")
    func prayedThroughPersists() {
        let defaults = freshDefaults()
        let a = SelahVerseEngagementStore(defaults: defaults)
        a.togglePrayedThrough(john3_16, translationId: "kjv")
        let b = SelahVerseEngagementStore(defaults: defaults)
        #expect(b.hasPrayedThrough(john3_16, translationId: "kjv"))
    }

    @Test("Prayed-through can include an optional note")
    func prayedThroughNote() {
        let store = SelahVerseEngagementStore(defaults: freshDefaults())
        store.togglePrayedThrough(romans5_3, translationId: "kjv", note: "in suffering")
        let entry = store.prayedThrough.first
        #expect(entry?.note == "in suffering")
    }
}

#endif
