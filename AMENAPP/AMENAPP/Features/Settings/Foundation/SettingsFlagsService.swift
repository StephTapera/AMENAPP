// SettingsFlagsService.swift
// AMEN — Settings/Safety system · Foundation
//
// Resolves the Settings/Safety feature-flag registry (SettingsFeatureFlag) from
// Firebase Remote Config. Every flag DEFAULTS OFF (S1) and self-registers its
// default here so this layer never has to edit the shared AMENFeatureFlags.swift.
//
// Pattern mirrors TranslationFeatureFlags.swift.

import Foundation
import Combine
import FirebaseRemoteConfig

@MainActor
final class SettingsFlagsService: ObservableObject {

    static let shared = SettingsFlagsService()

    /// Resolved value per flag. Absent key => treat as flag.defaultValue (false).
    @Published private(set) var resolved: [SettingsFeatureFlag: Bool] = [:]

    private init() {
        // Seed with safe defaults immediately so the first synchronous reads are protective.
        resolved = Dictionary(uniqueKeysWithValues: SettingsFeatureFlag.allCases.map { ($0, $0.defaultValue) })
        Task { await fetchRemoteConfig() }
    }

    // MARK: - Public API

    /// Whether a Settings/Safety surface flag is enabled. Defaults OFF on any uncertainty.
    func isEnabled(_ flag: SettingsFeatureFlag) -> Bool {
        resolved[flag] ?? flag.defaultValue
    }

    // MARK: - Remote Config

    private func fetchRemoteConfig() async {
        let config = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600 // 1 hour
        config.configSettings = settings

        // Self-register defaults (all OFF) without touching the shared AMENFeatureFlags defaults dictionary.
        var defaults: [String: NSObject] = [:]
        for flag in SettingsFeatureFlag.allCases {
            defaults[flag.rawValue] = flag.defaultValue as NSObject
        }
        config.setDefaults(defaults)

        do {
            let status = try await config.fetch()
            if status == .success {
                try await config.activate()
            }
            applyRemoteConfig(config)
        } catch {
            // Non-fatal: the protective defaults seeded in init remain in effect.
            dlog("[SettingsFlags] Remote config fetch failed, using defaults: \(error)")
        }
    }

    private func applyRemoteConfig(_ config: RemoteConfig) {
        var next: [SettingsFeatureFlag: Bool] = [:]
        for flag in SettingsFeatureFlag.allCases {
            // RemoteConfig returns the registered default (false) when the key is absent.
            next[flag] = config[flag.rawValue].boolValue
        }
        resolved = next
    }
}
