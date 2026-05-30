// TranslationFeatureFlags.swift
// AMEN App — Translation System
//
// Feature flags for safe staged rollout.
// In production, these can be driven by Firebase Remote Config.
// For MVP, they are hardcoded to safe defaults.
//
// Rollout plan:
//   Phase 1 (current): Posts + Testimonies + Prayer (public content only)
//   Phase 2: Comments + Replies
//   Phase 3: Profile bios + Resource descriptions
//   Phase 4: DMs (requires separate privacy review / legal sign-off)

import Foundation
import Combine
import FirebaseRemoteConfig

@MainActor
final class TranslationFeatureFlags: ObservableObject {

    static let shared = TranslationFeatureFlags()

    // MARK: - Published Flags

    @Published private(set) var translationSystemEnabled: Bool = true
    @Published private(set) var gcpBackendEnabled: Bool = true
    @Published private(set) var appleOnDeviceFallbackEnabled: Bool = true
    @Published private(set) var autoTranslationEnabled: Bool = true
    @Published private(set) var messagesTranslationEnabled: Bool = true
    @Published private(set) var analyticsEnabled: Bool = true

    // Meaning-Aware Translation (Accessibility Intelligence Layer)
    @Published private(set) var meaningAwareTranslationEnabled: Bool = true
    @Published private(set) var naturalModeEnabled: Bool = true
    @Published private(set) var contextualModeEnabled: Bool = true

    // Per-surface flags
    @Published private(set) var postsTranslationEnabled: Bool = true
    @Published private(set) var testimoniesTranslationEnabled: Bool = true
    @Published private(set) var prayerTranslationEnabled: Bool = true
    @Published private(set) var commentsTranslationEnabled: Bool = true
    @Published private(set) var repliesTranslationEnabled: Bool = true
    @Published private(set) var profileBioTranslationEnabled: Bool = true
    @Published private(set) var resourceDescriptionTranslationEnabled: Bool = true
    @Published private(set) var churchNotesTranslationEnabled: Bool = true

    // Language Intelligence Layer
    @Published private(set) var smartTranslationVisibilityEnabled: Bool = true
    @Published private(set) var sideBySideTranslationEnabled: Bool = true
    @Published private(set) var perLanguageAutoTranslateEnabled: Bool = true
    @Published private(set) var creationLanguageEnabled: Bool = true
    @Published private(set) var adaptiveTranslationEnabled: Bool = true

    // Cost guardrails
    @Published private(set) var maxCharsPerRequest: Int = 5000
    @Published private(set) var maxRequestsPerUserPerDay: Int = 100
    @Published private(set) var preTranslationThreshold: Int = 50 // impressions before pre-computing

    private init() {
        Task { await fetchRemoteConfig() }
    }

    // MARK: - Public API

    /// Whether translation is enabled for a given content type
    func isEnabled(for contentType: TranslatableContentType) -> Bool {
        guard translationSystemEnabled else { return false }
        switch contentType {
        case .post:                    return postsTranslationEnabled
        case .testimony:               return testimoniesTranslationEnabled
        case .prayerRequest:           return prayerTranslationEnabled
        case .comment:                 return commentsTranslationEnabled
        case .reply:                   return repliesTranslationEnabled
        case .profileBio:              return profileBioTranslationEnabled
        case .resourceDescription:     return resourceDescriptionTranslationEnabled
        case .churchNote:              return churchNotesTranslationEnabled
        case .message:                 return messagesTranslationEnabled
        }
    }

    /// Preferred engine strategy — GCP backend first, Apple on-device as fallback
    var preferredEngine: TranslationEngine {
        if gcpBackendEnabled { return .gcpV3 }
        if appleOnDeviceFallbackEnabled { return .appleOnDevice }
        return .unknown
    }

    // MARK: - Remote Config Fetch

    private func fetchRemoteConfig() async {
        let config = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600 // 1 hour
        config.configSettings = settings

        // Remote Config defaults
        config.setDefaults([
            "translation_system_enabled": true as NSObject,
            "translation_gcp_backend_enabled": true as NSObject,
            "translation_apple_fallback_enabled": true as NSObject,
            "translation_auto_enabled": true as NSObject,
            "translation_messages_enabled": true as NSObject,
            "translation_posts_enabled": true as NSObject,
            "translation_testimonies_enabled": true as NSObject,
            "translation_prayer_enabled": true as NSObject,
            "translation_comments_enabled": true as NSObject,
            "translation_replies_enabled": true as NSObject,
            "translation_profile_bio_enabled": true as NSObject,
            "translation_max_chars": 5000 as NSObject,
            "translation_max_requests_per_day": 100 as NSObject,
            "translation_precompute_threshold": 50 as NSObject,
            "translation_meaning_aware_enabled": true as NSObject,
            "translation_natural_mode_enabled": true as NSObject,
            "translation_contextual_mode_enabled": true as NSObject,
            "translation_smart_visibility_enabled": true as NSObject,
            "translation_side_by_side_enabled": true as NSObject,
            "translation_per_language_auto_enabled": true as NSObject,
            "translation_creation_language_enabled": true as NSObject,
            "translation_adaptive_enabled": true as NSObject,
        ])

        do {
            let status = try await config.fetch()
            if status == .success {
                try await config.activate()
                applyRemoteConfig(config)
            }
        } catch {
            // Non-fatal: hardcoded defaults above remain in effect
            dlog("[TranslationFlags] Remote config fetch failed, using defaults: \(error)")
        }
    }

    private func applyRemoteConfig(_ config: RemoteConfig) {
        translationSystemEnabled = config["translation_system_enabled"].boolValue
        gcpBackendEnabled = config["translation_gcp_backend_enabled"].boolValue
        appleOnDeviceFallbackEnabled = config["translation_apple_fallback_enabled"].boolValue
        autoTranslationEnabled = config["translation_auto_enabled"].boolValue
        messagesTranslationEnabled = config["translation_messages_enabled"].boolValue
        postsTranslationEnabled = config["translation_posts_enabled"].boolValue
        testimoniesTranslationEnabled = config["translation_testimonies_enabled"].boolValue
        prayerTranslationEnabled = config["translation_prayer_enabled"].boolValue
        commentsTranslationEnabled = config["translation_comments_enabled"].boolValue
        repliesTranslationEnabled = config["translation_replies_enabled"].boolValue
        profileBioTranslationEnabled = config["translation_profile_bio_enabled"].boolValue
        maxCharsPerRequest = config["translation_max_chars"].numberValue.intValue
        maxRequestsPerUserPerDay = config["translation_max_requests_per_day"].numberValue.intValue
        preTranslationThreshold = config["translation_precompute_threshold"].numberValue.intValue
        meaningAwareTranslationEnabled = config["translation_meaning_aware_enabled"].boolValue
        naturalModeEnabled = config["translation_natural_mode_enabled"].boolValue
        contextualModeEnabled = config["translation_contextual_mode_enabled"].boolValue
        smartTranslationVisibilityEnabled = config["translation_smart_visibility_enabled"].boolValue
        sideBySideTranslationEnabled = config["translation_side_by_side_enabled"].boolValue
        perLanguageAutoTranslateEnabled = config["translation_per_language_auto_enabled"].boolValue
        creationLanguageEnabled = config["translation_creation_language_enabled"].boolValue
        adaptiveTranslationEnabled = config["translation_adaptive_enabled"].boolValue
    }
}
