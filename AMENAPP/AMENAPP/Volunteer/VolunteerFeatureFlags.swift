//  VolunteerFeatureFlags.swift
//  AMEN — Smart Volunteer Board · Wave 0 feature flags.
//
//  Standalone Remote Config module (same pattern as CommunityOSFeatureFlags) so the volunteer
//  flags do not contend with the large shared AMENFeatureFlags file. ALL flags default OFF —
//  nothing volunteer-related is user-visible until a human flips Remote Config after verification.
//  The server re-asserts every safety gate (leader-only notes, atomic fill) regardless of these
//  client flags; flags gate UI surfaces only.
//
//  Usage:
//    if VolunteerFlagService.shared.isEnabled(.board) { ... }

import Foundation
import Combine
import FirebaseRemoteConfig

// MARK: - VolunteerFlag

/// Wave 0 volunteer-scheduling flags. Raw values are the exact Remote Config parameter keys.
enum VolunteerFlag: String, CaseIterable {
    /// Master gate for the whole volunteer-scheduling surface.
    case scheduling = "volunteer_scheduling_enabled"
    /// Gates the Smart Volunteer Board read surface.
    case board      = "volunteer_board_enabled"
    /// Gates one-tap sign-up (the transactional fill is server-enforced regardless).
    case signup     = "volunteer_signup_enabled"
    /// Gates push + email reminder scheduling.
    case reminders  = "volunteer_reminders_enabled"
    /// SMS reminders — gated for later (TCPA consent + provider). HARD-OFF in Wave 0.
    case sms        = "volunteer_sms_enabled"

    /// Every volunteer flag defaults OFF; Remote Config can raise it after verification.
    var defaultValue: Bool { false }
}

// MARK: - VolunteerFlagService

/// @MainActor service wrapping Firebase Remote Config for the volunteer flags. All default OFF.
@MainActor
final class VolunteerFlagService: ObservableObject {

    static let shared = VolunteerFlagService()

    /// Local cache of resolved flag values. Defaults (all false) are used before first fetch.
    @Published private var resolvedValues: [VolunteerFlag: Bool] = [:]

    private var fetchTask: Task<Void, Never>?

    private init() {
        fetchTask = Task { await fetchRemoteConfig() }
    }

    /// Returns the Remote Config value for the flag, or `false` before the first fetch.
    func isEnabled(_ flag: VolunteerFlag) -> Bool {
        resolvedValues[flag] ?? flag.defaultValue
    }

    private func fetchRemoteConfig() async {
        let config = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600
        config.configSettings = settings

        var defaults: [String: NSObject] = [:]
        for flag in VolunteerFlag.allCases {
            defaults[flag.rawValue] = flag.defaultValue as NSObject
        }
        config.setDefaults(defaults)

        do {
            let status = try await config.fetch()
            if status == .success {
                try await config.activate()
                applyRemoteConfig(config)
            }
        } catch {
            // Non-fatal: conservative OFF defaults remain in effect until the next fetch.
            dlog("[VolunteerFlagService] Remote Config fetch failed, using OFF defaults: \(error)")
        }
    }

    private func applyRemoteConfig(_ config: RemoteConfig) {
        var updated: [VolunteerFlag: Bool] = [:]
        for flag in VolunteerFlag.allCases {
            updated[flag] = config[flag.rawValue].boolValue
        }
        resolvedValues = updated
    }
}
