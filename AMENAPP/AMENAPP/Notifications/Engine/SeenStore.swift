// SeenStore.swift
// AMENAPP — Smart Notification Engine
//
// Persists which AmenActions have had their educational card shown
// across app relaunches, using UserDefaults (no SwiftData dependency).
//
// Format stored: [String] of AmenAction.rawValues under key "AmenNotif.seenActions"
//
// Thread safety: intentionally not @MainActor — reads are cheap and
// all callers (NotificationCoordinator) already run on the main actor.

import Foundation

// MARK: - SeenStore

final class SeenStore {

    // MARK: - Singleton

    static let shared = SeenStore()

    // MARK: - Private

    private let defaults = UserDefaults.standard
    private let key = "AmenNotif.seenActions"

    private init() {}

    // MARK: - Public API

    /// Returns `true` if the educational card for `action` has already been shown.
    func hasSeen(_ action: AmenAction) -> Bool {
        let seen = defaults.stringArray(forKey: key) ?? []
        return seen.contains(action.rawValue)
    }

    /// Records that the educational card for `action` has been shown.
    /// Idempotent — calling multiple times for the same action is safe.
    func markSeen(_ action: AmenAction) {
        var seen = defaults.stringArray(forKey: key) ?? []
        guard !seen.contains(action.rawValue) else { return }
        seen.append(action.rawValue)
        defaults.set(seen, forKey: key)
    }

    /// Clears all seen state — called from the Settings screen to let
    /// users see educational cards again (e.g. after a device restore or
    /// when explicitly requested via "Reset Notification Tips").
    func reset() {
        defaults.removeObject(forKey: key)
    }
}
