//
//  CalmModeManager.swift
//  AMENAPP
//
//  Observable manager for Calm Mode — a spiritual digital wellness system
//  that reduces stimulation so users can be fully present.
//
//  All preferences are backed by UserDefaults with a "calmMode." prefix
//  so they survive app restarts and can be read without the manager.
//
//  Usage (SwiftUI):
//    @ObservedObject var calm = CalmModeManager.shared
//    // or via environment:
//    @Environment(\.calmMode) var calm
//

import SwiftUI

// MARK: - CalmModeManager

@MainActor
final class CalmModeManager: ObservableObject {

    // MARK: Singleton
    static let shared = CalmModeManager()
    private init() {
        // Read initial values from UserDefaults (handled by computed setters below)
    }

    // MARK: - Notification Name

    static let changedNotification = Notification.Name("AMENCalmModeChanged")

    // MARK: - Persisted Preferences

    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: Keys.enabled) {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }

    @Published var hideEngagementMetrics: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: Keys.hideMetrics) as? Bool ?? true
    }() {
        didSet { UserDefaults.standard.set(hideEngagementMetrics, forKey: Keys.hideMetrics) }
    }

    @Published var disableInfiniteScroll: Bool = UserDefaults.standard.bool(forKey: Keys.limitScroll) {
        didSet { UserDefaults.standard.set(disableInfiniteScroll, forKey: Keys.limitScroll) }
    }

    @Published var reducedAnimations: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: Keys.reducedAnim) as? Bool ?? true
    }() {
        didSet { UserDefaults.standard.set(reducedAnimations, forKey: Keys.reducedAnim) }
    }

    @Published var grayscaleMode: Bool = UserDefaults.standard.bool(forKey: Keys.grayscale) {
        didSet { UserDefaults.standard.set(grayscaleMode, forKey: Keys.grayscale) }
    }

    @Published var audioFirstMode: Bool = UserDefaults.standard.bool(forKey: Keys.audioFirst) {
        didSet { UserDefaults.standard.set(audioFirstMode, forKey: Keys.audioFirst) }
    }

    @Published var sessionScrollLimit: Int = {
        let ud = UserDefaults.standard
        let stored = ud.integer(forKey: Keys.scrollLimit)
        return stored > 0 ? stored : 20
    }() {
        didSet { UserDefaults.standard.set(sessionScrollLimit, forKey: Keys.scrollLimit) }
    }

    // MARK: - Actions

    /// Toggles Calm Mode on/off, fires a haptic, and broadcasts the change.
    func toggle() {
        isEnabled.toggle()
        Task {
            await AmenHapticEngine.shared.play(.safeSpaceActivated)
        }
        NotificationCenter.default.post(name: CalmModeManager.changedNotification, object: nil)
        dlog("CalmModeManager: isEnabled = \(isEnabled)")
    }

    /// Resets all settings to their design defaults and broadcasts the change.
    func reset() {
        isEnabled = false
        hideEngagementMetrics = true
        disableInfiniteScroll = false
        reducedAnimations = true
        grayscaleMode = false
        audioFirstMode = false
        sessionScrollLimit = 20
        NotificationCenter.default.post(name: CalmModeManager.changedNotification, object: nil)
        dlog("CalmModeManager: reset to defaults")
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let enabled      = "calmMode.enabled"
        static let hideMetrics  = "calmMode.hideMetrics"
        static let limitScroll  = "calmMode.limitScroll"
        static let reducedAnim  = "calmMode.reducedAnim"
        static let grayscale    = "calmMode.grayscale"
        static let audioFirst   = "calmMode.audioFirst"
        static let scrollLimit  = "calmMode.scrollLimit"
    }
}

// MARK: - SwiftUI Environment Integration

private struct CalmModeKey: EnvironmentKey {
    static let defaultValue: CalmModeManager = CalmModeManager.shared
}

extension EnvironmentValues {
    var calmMode: CalmModeManager {
        get { self[CalmModeKey.self] }
        set { self[CalmModeKey.self] = newValue }
    }
}
