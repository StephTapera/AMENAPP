//
//  SelahLockScreenWidgetPayload.swift
//  AMENAPP
//
//  Data shape consumed by a future Selah lock-screen / home-screen Widget
//  Extension. The extension target itself is NOT in this codebase yet
//  (adding a widget extension requires creating a new Xcode target in the
//  project file, which is outside the scope of source-only edits).
//
//  This file lets the host app *prepare* a payload and write it to an App
//  Group container the widget can read once the extension target is added.
//
//  Setup notes when adding the Widget Extension:
//   1. Create an App Group ID, e.g. `group.app.amen.selah`.
//   2. Enable the App Group entitlement for both targets.
//   3. Read this payload from `UserDefaults(suiteName:)` in the widget's
//      `TimelineProvider`.
//

import Foundation

/// The compact, render-ready payload for one lock-screen widget slot.
struct SelahLockScreenWidgetPayload: Codable, Equatable {
    /// "Continue in <ref>" or "Daily verse" — short user-facing line.
    let headline: String
    /// Reference text: "Romans 5:3-5" — for display.
    let reference: String
    /// Body text snippet — KEEP SHORT; widgets clip aggressively.
    let snippet: String
    /// Translation abbreviation: "KJV"
    let translationAbbreviation: String
    /// Last refreshed.
    let updatedAt: Date

    static let placeholder = SelahLockScreenWidgetPayload(
        headline: "Daily verse",
        reference: "Psalm 23:1",
        snippet: "The LORD is my shepherd; I shall not want.",
        translationAbbreviation: "KJV",
        updatedAt: Date()
    )
}

/// Writes the latest widget payload into an App Group `UserDefaults` suite
/// so the future widget extension can read it without a network call.
@MainActor
enum SelahLockScreenWidgetPublisher {

    /// Update once when the App Group has been configured; default behavior
    /// no-ops cleanly so this is safe to call from the host today.
    static let appGroupSuite: String? = nil   // Set to e.g. "group.app.amen.selah" when configured.

    static let payloadKey = "selah.lockScreen.payload.v1"

    /// Build a payload from the user's real last-read position if available;
    /// otherwise from a bundled KJV chapter we know exists.
    static func currentPayload(
        from preferences: SelahScriptureReaderPreferencesStore,
        provider: SelahBibleTranslationProvider
    ) async -> SelahLockScreenWidgetPayload? {
        let translation = SelahBibleTranslation.known.first {
            $0.id == preferences.preferences.translationId
        } ?? .kjv

        // Prefer "continue reading" — last-read position drives the widget.
        if let pos = preferences.lastReadPosition {
            guard let chapter = try? await provider.loadChapter(
                bookId: pos.bookId,
                chapter: pos.chapter,
                translation: translation
            ) else { return nil }
            let verse = chapter.verses.first { $0.number == (pos.verse ?? 1) } ?? chapter.verses.first
            guard let v = verse else { return nil }
            return SelahLockScreenWidgetPayload(
                headline: "Continue reading",
                reference: v.reference.displayString,
                snippet: v.text,
                translationAbbreviation: translation.abbreviation,
                updatedAt: Date()
            )
        }

        // Daily fallback: pick a stable verse based on the day-of-year so it
        // varies day to day but doesn't shuffle randomly within a single day.
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let candidates: [(String, Int, Int)] = [
            ("psalms", 23, 1),
            ("psalms", 1, 1),
            ("john", 3, 16),
            ("romans", 5, 8),
            ("genesis", 1, 1)
        ]
        let pick = candidates[day % candidates.count]
        guard let chapter = try? await provider.loadChapter(
            bookId: pick.0, chapter: pick.1, translation: translation
        ) else { return nil }
        guard let v = chapter.verses.first(where: { $0.number == pick.2 }) else { return nil }
        return SelahLockScreenWidgetPayload(
            headline: "Daily verse",
            reference: v.reference.displayString,
            snippet: v.text,
            translationAbbreviation: translation.abbreviation,
            updatedAt: Date()
        )
    }

    /// Persist the payload. No-op when no App Group is configured yet.
    static func publish(_ payload: SelahLockScreenWidgetPayload) {
        guard let suite = appGroupSuite,
              let defaults = UserDefaults(suiteName: suite),
              let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: payloadKey)
    }
}
