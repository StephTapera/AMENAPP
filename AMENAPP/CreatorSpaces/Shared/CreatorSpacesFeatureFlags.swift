import Foundation
import FirebaseRemoteConfig

@MainActor
final class CreatorSpacesFeatureFlags: ObservableObject {
    static let shared = CreatorSpacesFeatureFlags()

    private static let localDefault = true as NSNumber

    @Published private(set) var creatorSpacesEnabled: Bool = CreatorSpacesFeatureFlags.localDefault.boolValue
    @Published private(set) var presencePostsEnabled: Bool = CreatorSpacesFeatureFlags.localDefault.boolValue
    @Published private(set) var collectiveMemoryEnabled: Bool = CreatorSpacesFeatureFlags.localDefault.boolValue
    @Published private(set) var smartChurchClipsEnabled: Bool = CreatorSpacesFeatureFlags.localDefault.boolValue
    @Published private(set) var mediaAuthenticityEnabled: Bool = CreatorSpacesFeatureFlags.localDefault.boolValue
    @Published private(set) var creatorSubscriptionsEnabled: Bool = CreatorSpacesFeatureFlags.localDefault.boolValue
    @Published private(set) var aiCreativeDirectorEnabled: Bool = CreatorSpacesFeatureFlags.localDefault.boolValue
    @Published private(set) var creatorDiscoveryEnabled: Bool = CreatorSpacesFeatureFlags.localDefault.boolValue

    private enum RCKey: String, CaseIterable {
        case creatorSpaces = "creator_spaces_enabled"
        case presencePosts = "presence_posts_enabled"
        case collectiveMemory = "collective_memory_enabled"
        case smartChurchClips = "smart_church_clips_enabled"
        case mediaAuthenticity = "media_authenticity_enabled"
        case creatorSubscriptions = "creator_subscriptions_enabled"
        case aiCreativeDirector = "ai_creative_director_enabled"
        case creatorDiscovery = "creator_discovery_enabled"
    }

    private init() {
        // Activate cached values only — no network hit.
        // AMENAPPApp.setupRemoteConfig() is the sole Remote Config fetch owner.
        let rc = RemoteConfig.remoteConfig()
        Task { @MainActor [weak self] in
            guard let self, (try? await rc.activate()) == true else { return }
            self.applyValues(from: rc)
        }
        // Re-apply when this session's central fetch completes (covers first-launch cold cache).
        Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .remoteConfigActivated) {
                guard let self else { break }
                self.applyValues(from: RemoteConfig.remoteConfig())
            }
        }
    }

    func fetchRemoteConfig() async {
        let rc = RemoteConfig.remoteConfig()
        rc.setDefaults([
            RCKey.creatorSpaces.rawValue: Self.localDefault,
            RCKey.presencePosts.rawValue: Self.localDefault,
            RCKey.collectiveMemory.rawValue: Self.localDefault,
            RCKey.smartChurchClips.rawValue: Self.localDefault,
            RCKey.mediaAuthenticity.rawValue: Self.localDefault,
            RCKey.creatorSubscriptions.rawValue: Self.localDefault,
            RCKey.aiCreativeDirector.rawValue: Self.localDefault,
            RCKey.creatorDiscovery.rawValue: Self.localDefault
        ])

        do {
            try await rc.fetch(withExpirationDuration: 3600)
            try await rc.activate()
            applyValues(from: rc)
        } catch {
            // Local defaults remain active. Production defaults are OFF.
        }
    }

    private func applyValues(from rc: RemoteConfig) {
        creatorSpacesEnabled = rc[RCKey.creatorSpaces.rawValue].boolValue
        presencePostsEnabled = rc[RCKey.presencePosts.rawValue].boolValue
        collectiveMemoryEnabled = rc[RCKey.collectiveMemory.rawValue].boolValue
        smartChurchClipsEnabled = rc[RCKey.smartChurchClips.rawValue].boolValue
        mediaAuthenticityEnabled = rc[RCKey.mediaAuthenticity.rawValue].boolValue
        creatorSubscriptionsEnabled = rc[RCKey.creatorSubscriptions.rawValue].boolValue
        aiCreativeDirectorEnabled = rc[RCKey.aiCreativeDirector.rawValue].boolValue
        creatorDiscoveryEnabled = rc[RCKey.creatorDiscovery.rawValue].boolValue
    }
}
