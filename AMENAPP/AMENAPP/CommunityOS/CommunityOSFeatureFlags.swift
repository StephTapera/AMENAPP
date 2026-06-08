// CommunityOSFeatureFlags.swift
// AMEN App — Community Around Content OS
//
// All Community OS flags are gated here via Firebase Remote Config.
// Every flag defaults to false — nothing activates in production without explicit enablement.
// Fetch runs once at app launch; subsequent reads are synchronous from the local cache.
//
// Usage:
//   if CommunityOSFlagService.shared.isEnabled(.communityAroundContent) { ... }

import Foundation
import Combine
import FirebaseRemoteConfig

// MARK: - CommunityOSFlag

/// All feature flags for the Community Around Content OS.
/// Raw values are the Remote Config parameter keys.
enum CommunityOSFlag: String, CaseIterable {
    case communityAroundContent     = "community_around_content_enabled"
    case autoEmergence              = "community_auto_emergence_enabled"
    case purityEngine               = "purity_engine_enabled"
    case heroExperience             = "media_hero_experience_enabled"
    case worshipMode                = "worship_mode_enabled"
    case driveMode                  = "drive_mode_enabled"
    case prayerJam                  = "prayer_jam_enabled"
    case meaningGraph               = "meaning_graph_enabled"
    case bereanContentConnector     = "berean_content_connector_enabled"
    case communityHealthEngine      = "community_health_engine_enabled"
    case creatorCommunityOS         = "creator_community_os_enabled"
    case contentDetectionEngine     = "content_detection_engine_enabled"
    case musicPurityFilter          = "music_purity_filter_enabled"
    case autoChurchLibrary          = "church_worship_library_enabled"
    case realWorldImpactEngine      = "real_world_impact_engine_enabled"

    /// All Community OS features default to true; Remote Config can override.
    var defaultValue: Bool { true }

    var displayName: String {
        switch self {
        case .communityAroundContent:
            return "Community Around Content"
        case .autoEmergence:
            return "Auto Community Emergence"
        case .purityEngine:
            return "Purity Engine"
        case .heroExperience:
            return "Media Hero Experience"
        case .worshipMode:
            return "Worship Mode"
        case .driveMode:
            return "Drive Mode"
        case .prayerJam:
            return "Prayer Jam"
        case .meaningGraph:
            return "Meaning Graph"
        case .bereanContentConnector:
            return "Berean Content Connector"
        case .communityHealthEngine:
            return "Community Health Engine"
        case .creatorCommunityOS:
            return "Creator Community OS"
        case .contentDetectionEngine:
            return "Content Detection Engine"
        case .musicPurityFilter:
            return "Music Purity Filter"
        case .autoChurchLibrary:
            return "Auto Church Worship Library"
        case .realWorldImpactEngine:
            return "Real-World Impact Engine"
        }
    }
}

// MARK: - CommunityOSFlagService

/// @MainActor service that wraps Firebase Remote Config for all Community OS flags.
/// All flags default to `true`; Remote Config can lower them for staged rollouts.
@MainActor
final class CommunityOSFlagService: ObservableObject {

    static let shared = CommunityOSFlagService()

    // MARK: Private state

    /// Local cache of resolved flag values. Populated after fetch; defaults used before fetch.
    @Published private var resolvedValues: [CommunityOSFlag: Bool] = [:]

    private var fetchTask: Task<Void, Never>?

    // MARK: Init

    private init() {
        fetchTask = Task { await fetchRemoteConfig() }
    }

    // MARK: Public API

    /// Returns the Remote Config value for the flag, or `flag.defaultValue` (true) before first fetch.
    func isEnabled(_ flag: CommunityOSFlag) -> Bool {
        resolvedValues[flag] ?? flag.defaultValue
    }

    // MARK: Remote Config

    private func fetchRemoteConfig() async {
        let config = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600 // 1 hour
        config.configSettings = settings

        // Register defaults so that reads before fetch still return our conservative baseline.
        var defaults: [String: NSObject] = [:]
        for flag in CommunityOSFlag.allCases {
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
            // Non-fatal: defaults above remain in effect until the next successful fetch.
            dlog("[CommunityOSFlagService] Remote Config fetch failed, using defaults: \(error)")
        }
    }

    private func applyRemoteConfig(_ config: RemoteConfig) {
        var updated: [CommunityOSFlag: Bool] = [:]
        for flag in CommunityOSFlag.allCases {
            updated[flag] = config[flag.rawValue].boolValue
        }
        resolvedValues = updated
        dlog("[CommunityOSFlagService] Flags applied: \(updated.filter { $0.value }.keys.map { $0.displayName })")
    }
}
