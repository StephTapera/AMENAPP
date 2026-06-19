// SabbathRhythmConfig.swift
// AMENAPP — SabbathMode / Rhythm (Sabbath Mode v2, Wave 1)
//
// The user's local, private Sabbath configuration: the weekly rest window that drives
// `SabbathScheduleTrigger`, plus per-trigger enablement for the Wave 1 ambient triggers.
//
// This is the missing seam that makes a *scheduled* Sabbath actually fire — Wave 0 shipped
// the schedule trigger but nothing ever called `configureSchedule`. The controller now loads
// this config at init and re-applies it whenever the settings surface changes it.
//
// Storage is local-only (UserDefaults). No upload, no server sync — consistent with the
// privacy contract (Guardrail 1 / I2). Every Wave 1 ambient trigger defaults OFF, so this
// changes nothing until the user opts in *and* `sabbath_mode_enabled` is ON.

import Foundation

// MARK: - Config

/// The user's private Sabbath rhythm preferences. Value type; persisted via `SabbathRhythmConfigStore`.
struct SabbathRhythmConfig: Codable, Equatable {

    /// The weekly rest window. Nil → no scheduled Sabbath (schedule trigger stays silent).
    var schedule: SabbathSchedule?

    /// Wave 1 ambient triggers — each its own opt-in, all default OFF. These never own a
    /// sensor; they read injected `SabbathAmbientSignals`, so enabling one adds no OS permission.
    var usageTriggerEnabled: Bool
    var locationTriggerEnabled: Bool
    var motionTriggerEnabled: Bool

    /// The default — no schedule, every ambient trigger off. The app behaves exactly as
    /// Wave 0 until the user changes something here.
    static let disabled = SabbathRhythmConfig(
        schedule: nil,
        usageTriggerEnabled: false,
        locationTriggerEnabled: false,
        motionTriggerEnabled: false
    )

    /// Whether anything here could ever propose rest. Used by the settings surface for status copy.
    var hasAnyActiveTrigger: Bool {
        schedule != nil || usageTriggerEnabled || locationTriggerEnabled || motionTriggerEnabled
    }
}

// MARK: - Store

/// Local-only persistence for `SabbathRhythmConfig`. Single key, JSON-encoded in UserDefaults.
/// Pure I/O — holds no state of its own, so it is trivially testable with an injected store.
struct SabbathRhythmConfigStore {

    private let defaults: UserDefaults
    private let key = "sabbath_rhythm_config_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Load the saved config, or `.disabled` if none has been saved (or it can't be decoded).
    func load() -> SabbathRhythmConfig {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(SabbathRhythmConfig.self, from: data) else {
            return .disabled
        }
        return config
    }

    /// Persist the config locally. Best-effort: a failed encode silently leaves the prior value.
    func save(_ config: SabbathRhythmConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key)
    }
}
