//
//  SelahScriptureReaderPreferencesStore.swift
//  AMENAPP
//
//  UserDefaults-backed persistence for reader preferences and the last-read
//  scripture position. Designed to be safe to construct in tests (callers
//  can inject a custom `UserDefaults` suite).
//

import Foundation

@MainActor
final class SelahScriptureReaderPreferencesStore: ObservableObject {

    // MARK: - Keys

    private enum Keys {
        static let preferences = "selah.scriptureReader.preferences.v1"
        static let lastReadPosition = "selah.scriptureReader.lastReadPosition.v1"
    }

    // MARK: - Published State

    @Published private(set) var preferences: SelahScriptureReaderPreferences
    @Published private(set) var lastReadPosition: SelahLastReadScripturePosition?

    // MARK: - Dependencies

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferences = SelahScriptureReaderPreferencesStore.load(
            SelahScriptureReaderPreferences.self,
            forKey: Keys.preferences,
            in: defaults,
            decoder: decoder
        ) ?? SelahScriptureReaderPreferences.defaults

        self.lastReadPosition = SelahScriptureReaderPreferencesStore.load(
            SelahLastReadScripturePosition.self,
            forKey: Keys.lastReadPosition,
            in: defaults,
            decoder: decoder
        )
    }

    // MARK: - Preferences

    func setTranslation(_ translationId: String) {
        var next = preferences
        next.translationId = translationId
        savePreferences(next)
    }

    func setFontPointSize(_ size: CGFloat) {
        let clamped = max(12, min(28, size))
        var next = preferences
        next.fontPointSize = clamped
        savePreferences(next)
    }

    func setPageTurnSoundEnabled(_ enabled: Bool) {
        var next = preferences
        next.pageTurnSoundEnabled = enabled
        savePreferences(next)
    }

    private func savePreferences(_ value: SelahScriptureReaderPreferences) {
        preferences = value
        persist(value, forKey: Keys.preferences)
    }

    // MARK: - Last Read Position

    func recordPosition(
        bookId: String,
        chapter: Int,
        verse: Int?,
        translationId: String,
        now: Date = Date()
    ) {
        let position = SelahLastReadScripturePosition(
            bookId: bookId,
            chapter: chapter,
            verse: verse,
            translationId: translationId,
            updatedAt: now
        )
        lastReadPosition = position
        persist(position, forKey: Keys.lastReadPosition)
    }

    func clearLastReadPosition() {
        lastReadPosition = nil
        defaults.removeObject(forKey: Keys.lastReadPosition)
    }

    // MARK: - Persistence helpers

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(
        _ type: T.Type,
        forKey key: String,
        in defaults: UserDefaults,
        decoder: JSONDecoder
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}
