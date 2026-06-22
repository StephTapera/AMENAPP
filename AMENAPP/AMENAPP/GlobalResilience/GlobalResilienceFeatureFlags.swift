// GlobalResilienceFeatureFlags.swift
// AMEN — Global Resilience System
//
// @MainActor ObservableObject that owns all 12 Remote Config-backed feature flags
// for the Global Resilience OS. Keys are defined in GRFlags (GlobalResilienceContracts.swift).
//
// All flags default to false (safe-off) until a successful Remote Config fetch.
// fetchAll() is the single entry point; call it once at app launch.
//
// Usage:
//   await GlobalResilienceFeatureFlags.shared.fetchAll()
//   if GlobalResilienceFeatureFlags.shared.globalResilienceEnabled { ... }

import SwiftUI
import FirebaseRemoteConfig

// MARK: - GlobalResilienceFeatureFlags

@MainActor
final class GlobalResilienceFeatureFlags: ObservableObject {

    // MARK: Shared instance

    static let shared = GlobalResilienceFeatureFlags()

    // MARK: Published flags (all default false — safe-off)

    @Published var globalResilienceEnabled: Bool = false
    @Published var lowDataModeEnabled: Bool = false
    @Published var offlineOutboxEnabled: Bool = false
    @Published var adaptiveMediaEnabled: Bool = false
    @Published var voiceTranscriptEnabled: Bool = false
    @Published var autoTranslateEnabled: Bool = false
    @Published var sharedDevicePrivacyEnabled: Bool = false
    @Published var localLanguagePolicyPacksEnabled: Bool = false
    @Published var antiScamTrustLayerEnabled: Bool = false
    @Published var verifiedDonationFlowEnabled: Bool = false
    @Published var crisisBulletinsEnabled: Bool = false
    @Published var constitutionalFeedRankingEnabled: Bool = false

    // MARK: Init

    private init() {}

    // MARK: Remote Config fetch

    /// Calls `fetchAndActivate()` then reads all 12 GR flag keys into their
    /// corresponding `@Published` properties.
    ///
    /// Safe to call multiple times — each call triggers a fresh fetch attempt.
    /// On failure the existing (default-false) values are preserved.
    func fetchAll() async {
        let config = RemoteConfig.remoteConfig()

        // Register conservative defaults so reads before fetch return false.
        let defaults: [String: NSObject] = [
            GRFlags.globalResilienceEnabled:          false as NSObject,
            GRFlags.lowDataModeEnabled:               false as NSObject,
            GRFlags.offlineOutboxEnabled:             false as NSObject,
            GRFlags.adaptiveMediaEnabled:             false as NSObject,
            GRFlags.voiceTranscriptEnabled:           false as NSObject,
            GRFlags.autoTranslateEnabled:             false as NSObject,
            GRFlags.sharedDevicePrivacyEnabled:       false as NSObject,
            GRFlags.localLanguagePolicyPacksEnabled:  false as NSObject,
            GRFlags.antiScamTrustLayerEnabled:        false as NSObject,
            GRFlags.verifiedDonationFlowEnabled:      false as NSObject,
            GRFlags.crisisBulletinsEnabled:           false as NSObject,
            GRFlags.constitutionalFeedRankingEnabled: false as NSObject
        ]
        config.setDefaults(defaults)

        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600 // 1 hour
        config.configSettings = settings

        do {
            let status = try await config.fetchAndActivate()
            switch status {
            case .successFetchedFromRemote, .successUsingPreFetchedData:
                applyFlags(from: config)
            case .error:
                // No-op: defaults remain.
                break
            @unknown default:
                // No-op: defaults remain.
                break
            }
        } catch {
            // Non-fatal: safe-off defaults remain in effect until the next successful fetch.
            print("[GlobalResilienceFeatureFlags] Remote Config fetchAndActivate failed: \(error)")
        }
    }

    // MARK: Private helpers

    private func applyFlags(from config: RemoteConfig) {
        globalResilienceEnabled          = config[GRFlags.globalResilienceEnabled].boolValue
        lowDataModeEnabled               = config[GRFlags.lowDataModeEnabled].boolValue
        offlineOutboxEnabled             = config[GRFlags.offlineOutboxEnabled].boolValue
        adaptiveMediaEnabled             = config[GRFlags.adaptiveMediaEnabled].boolValue
        voiceTranscriptEnabled           = config[GRFlags.voiceTranscriptEnabled].boolValue
        autoTranslateEnabled             = config[GRFlags.autoTranslateEnabled].boolValue
        sharedDevicePrivacyEnabled       = config[GRFlags.sharedDevicePrivacyEnabled].boolValue
        localLanguagePolicyPacksEnabled  = config[GRFlags.localLanguagePolicyPacksEnabled].boolValue
        antiScamTrustLayerEnabled        = config[GRFlags.antiScamTrustLayerEnabled].boolValue
        verifiedDonationFlowEnabled      = config[GRFlags.verifiedDonationFlowEnabled].boolValue
        crisisBulletinsEnabled           = config[GRFlags.crisisBulletinsEnabled].boolValue
        constitutionalFeedRankingEnabled = config[GRFlags.constitutionalFeedRankingEnabled].boolValue
    }
}
