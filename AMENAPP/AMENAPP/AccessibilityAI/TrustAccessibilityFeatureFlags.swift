// TrustAccessibilityFeatureFlags.swift
// AMEN Trust Layer + Universal Accessibility Engine — Feature Flags
// ALL flags default OFF. Backed by Firebase Remote Config.

import Foundation
import FirebaseRemoteConfig

@MainActor
final class TrustAccessibilityFeatureFlags: ObservableObject {
    static let shared = TrustAccessibilityFeatureFlags()

    // MARK: - Trust Layer
    @Published private(set) var trustLayerEnabled: Bool = false
    @Published private(set) var provenanceBadgesEnabled: Bool = false
    @Published private(set) var authenticityScoresEnabled: Bool = false
    @Published private(set) var syntheticDetectionEnabled: Bool = false

    // MARK: - Accessibility AI
    @Published private(set) var a11yTranslateEnabled: Bool = false
    @Published private(set) var a11yTranscribeEnabled: Bool = false
    @Published private(set) var a11yVisualEnabled: Bool = false
    @Published private(set) var a11yReadingEnabled: Bool = false
    @Published private(set) var a11ySimplifyEnabled: Bool = false
    @Published private(set) var a11yFaithIntelEnabled: Bool = false
    @Published private(set) var a11yNavigationEnabled: Bool = false
    @Published private(set) var a11yCoPilotEnabled: Bool = false
    @Published private(set) var a11yMemoryEnabled: Bool = false
    @Published private(set) var emotionalSafetyEnabled: Bool = false
    @Published private(set) var signLanguageAvatarEnabled: Bool = false

    private init() {
        refreshFromRemoteConfig()
    }

    func refreshFromRemoteConfig() {
        let rc = RemoteConfig.remoteConfig()
        trustLayerEnabled          = rc.configValue(forKey: "trust_layer_enabled").boolValue
        provenanceBadgesEnabled    = rc.configValue(forKey: "provenance_badges_enabled").boolValue
        authenticityScoresEnabled  = rc.configValue(forKey: "authenticity_scores_enabled").boolValue
        syntheticDetectionEnabled  = rc.configValue(forKey: "synthetic_detection_enabled").boolValue
        a11yTranslateEnabled       = rc.configValue(forKey: "a11y_translate_enabled").boolValue
        a11yTranscribeEnabled      = rc.configValue(forKey: "a11y_transcribe_enabled").boolValue
        a11yVisualEnabled          = rc.configValue(forKey: "a11y_visual_enabled").boolValue
        a11yReadingEnabled         = rc.configValue(forKey: "a11y_reading_enabled").boolValue
        a11ySimplifyEnabled        = rc.configValue(forKey: "a11y_simplify_enabled").boolValue
        a11yFaithIntelEnabled      = rc.configValue(forKey: "a11y_faith_intel_enabled").boolValue
        a11yNavigationEnabled      = rc.configValue(forKey: "a11y_navigation_enabled").boolValue
        a11yCoPilotEnabled         = rc.configValue(forKey: "a11y_copilot_enabled").boolValue
        a11yMemoryEnabled          = rc.configValue(forKey: "a11y_memory_enabled").boolValue
        emotionalSafetyEnabled     = rc.configValue(forKey: "emotional_safety_enabled").boolValue
        signLanguageAvatarEnabled  = rc.configValue(forKey: "sign_language_avatar_enabled").boolValue
    }
}
