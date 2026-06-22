// SelahScriptureReaderPreferencesStoreTests.swift
// AMENAPPTests
//
// Persistence contract tests for the reader preferences store, driven by
// an isolated in-memory UserDefaults suite per test.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

private func freshDefaults() -> UserDefaults {
    let suiteName = "SelahScriptureReaderPreferencesStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
@Suite("SelahScriptureReaderPreferencesStore")
struct SelahScriptureReaderPreferencesStoreTests {

    @Test("Returns defaults when nothing is persisted")
    func defaultsWhenEmpty() {
        let store = SelahScriptureReaderPreferencesStore(defaults: freshDefaults())
        #expect(store.preferences.translationId == "kjv")
        #expect(store.preferences.fontPointSize == 17)
        #expect(store.preferences.pageTurnSoundEnabled == false)
        #expect(store.lastReadPosition == nil)
    }

    @Test("Translation update persists across instances")
    func translationPersists() {
        let defaults = freshDefaults()
        let a = SelahScriptureReaderPreferencesStore(defaults: defaults)
        a.setTranslation("esv")
        #expect(a.preferences.translationId == "esv")

        let b = SelahScriptureReaderPreferencesStore(defaults: defaults)
        #expect(b.preferences.translationId == "esv")
    }

    @Test("Font size persists and is clamped to safe range")
    func fontSizeClampedAndPersists() {
        let defaults = freshDefaults()
        let store = SelahScriptureReaderPreferencesStore(defaults: defaults)
        store.setFontPointSize(8)
        #expect(store.preferences.fontPointSize == 12)
        store.setFontPointSize(40)
        #expect(store.preferences.fontPointSize == 28)
        store.setFontPointSize(18)
        #expect(store.preferences.fontPointSize == 18)

        let reload = SelahScriptureReaderPreferencesStore(defaults: defaults)
        #expect(reload.preferences.fontPointSize == 18)
    }

    @Test("Page-turn sound toggle persists")
    func pageTurnTogglePersists() {
        let defaults = freshDefaults()
        let store = SelahScriptureReaderPreferencesStore(defaults: defaults)
        store.setPageTurnSoundEnabled(true)
        #expect(store.preferences.pageTurnSoundEnabled == true)

        let reload = SelahScriptureReaderPreferencesStore(defaults: defaults)
        #expect(reload.preferences.pageTurnSoundEnabled == true)
    }

    @Test("Last-read position records and reloads")
    func lastReadPositionRecordsAndReloads() {
        let defaults = freshDefaults()
        let store = SelahScriptureReaderPreferencesStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.recordPosition(bookId: "romans", chapter: 5, verse: 3, translationId: "kjv", now: now)

        #expect(store.lastReadPosition?.bookId == "romans")
        #expect(store.lastReadPosition?.chapter == 5)
        #expect(store.lastReadPosition?.verse == 3)
        #expect(store.lastReadPosition?.translationId == "kjv")
        #expect(store.lastReadPosition?.updatedAt == now)

        let reload = SelahScriptureReaderPreferencesStore(defaults: defaults)
        #expect(reload.lastReadPosition?.bookId == "romans")
        #expect(reload.lastReadPosition?.chapter == 5)
        #expect(reload.lastReadPosition?.verse == 3)
    }

    @Test("clearLastReadPosition removes persisted state")
    func clearLastReadPosition() {
        let defaults = freshDefaults()
        let store = SelahScriptureReaderPreferencesStore(defaults: defaults)
        store.recordPosition(bookId: "psalms", chapter: 23, verse: nil, translationId: "kjv")
        #expect(store.lastReadPosition != nil)
        store.clearLastReadPosition()
        #expect(store.lastReadPosition == nil)

        let reload = SelahScriptureReaderPreferencesStore(defaults: defaults)
        #expect(reload.lastReadPosition == nil)
    }

    @Test("Recording a new position overwrites the previous one")
    func recordingOverwritesPrevious() {
        let store = SelahScriptureReaderPreferencesStore(defaults: freshDefaults())
        store.recordPosition(bookId: "romans", chapter: 5, verse: nil, translationId: "kjv")
        store.recordPosition(bookId: "john", chapter: 3, verse: 16, translationId: "kjv")
        #expect(store.lastReadPosition?.bookId == "john")
        #expect(store.lastReadPosition?.chapter == 3)
        #expect(store.lastReadPosition?.verse == 16)
    }
}

#endif
