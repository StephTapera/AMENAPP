// AmenSmartPromptStateStore.swift
// AMEN App — Smart Contextual Prompt System State Store
//
// Persists prompt impressions, dismissals, cooldowns, and last actions
// using UserDefaults. Device-local only — no Firestore sync required
// since prompt suppression state is ephemeral and session-personal.
//
// All keys are namespaced under "amen_prompt_" to avoid collisions.

import Foundation

@MainActor
final class AmenSmartPromptStateStore {

    static let shared = AmenSmartPromptStateStore()

    private let defaults: UserDefaults

    /// Designated for tests: inject a named suite to isolate state.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Key Helpers

    private func key(_ suffix: String, promptKey: String) -> String {
        "amen_prompt_\(suffix)_\(promptKey)"
    }

    private func surfaceKey(_ surface: AmenSmartPromptSurface) -> String {
        "amen_prompt_surface_last_\(surface.rawValue)"
    }

    private let globalLastKey = "amen_prompt_global_last"

    // MARK: - Impression

    func recordImpression(for persistenceKey: String) {
        defaults.set(Date().timeIntervalSince1970, forKey: key("impression", promptKey: persistenceKey))
    }

    func lastImpressionDate(for persistenceKey: String) -> Date? {
        timestamp(forKey: key("impression", promptKey: persistenceKey))
    }

    // MARK: - Dismissal

    func recordDismissal(for persistenceKey: String) {
        let count = dismissalCount(for: persistenceKey) + 1
        defaults.set(count, forKey: key("dismissals", promptKey: persistenceKey))
        defaults.set(Date().timeIntervalSince1970, forKey: key("dismissed_at", promptKey: persistenceKey))
    }

    func dismissalCount(for persistenceKey: String) -> Int {
        defaults.integer(forKey: key("dismissals", promptKey: persistenceKey))
    }

    func lastDismissalDate(for persistenceKey: String) -> Date? {
        timestamp(forKey: key("dismissed_at", promptKey: persistenceKey))
    }

    // MARK: - Action (primary CTA tapped)

    func recordAction(for persistenceKey: String) {
        defaults.set(Date().timeIntervalSince1970, forKey: key("action_at", promptKey: persistenceKey))
    }

    func lastActionDate(for persistenceKey: String) -> Date? {
        timestamp(forKey: key("action_at", promptKey: persistenceKey))
    }

    // MARK: - Permanent Suppression

    func markPermanentlySuppressed(_ persistenceKey: String) {
        defaults.set(true, forKey: key("suppressed", promptKey: persistenceKey))
    }

    func isPermanentlySuppressed(_ persistenceKey: String) -> Bool {
        defaults.bool(forKey: key("suppressed", promptKey: persistenceKey))
    }

    // MARK: - Surface-level Cooldown

    func recordSurfacePrompt(for surface: AmenSmartPromptSurface) {
        defaults.set(Date().timeIntervalSince1970, forKey: surfaceKey(surface))
    }

    func lastPromptDate(for surface: AmenSmartPromptSurface) -> Date? {
        timestamp(forKey: surfaceKey(surface))
    }

    // MARK: - Global Cooldown

    func recordGlobalPrompt() {
        defaults.set(Date().timeIntervalSince1970, forKey: globalLastKey)
    }

    var globalLastPromptDate: Date? {
        timestamp(forKey: globalLastKey)
    }

    // MARK: - Reset (used in tests and debug builds)

    func resetAll() {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("amen_prompt_") }
            .forEach { defaults.removeObject(forKey: $0) }
    }

    // MARK: - Private

    private func timestamp(forKey key: String) -> Date? {
        let ts = defaults.double(forKey: key)
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }
}
