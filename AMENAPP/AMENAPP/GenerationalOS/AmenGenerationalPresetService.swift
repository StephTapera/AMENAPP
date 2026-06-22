// AmenGenerationalPresetService.swift
// AMENAPP — GenerationalOS
//
// Observable singleton that owns the active generational preset.
// Changes are applied immediately and persisted to UserDefaults.
// The Firestore sync path is deliberately thin — all safety enforcement
// lives in the config struct; this service is only the source-of-truth store.
//
// Mutation entry points:
//   AmenGenerationalPresetService.shared.setPreset(.teen)
//   AmenGenerationalPresetService.shared.hasCompletedPresetOnboarding = true
//   AmenGenerationalPresetService.shared.activePreset  (read-only externally)

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - UserDefaultsKeys (GenerationalOS additions)

private enum GenerationalKeys {
    static let preset         = "amenGenerationalPreset"
    static let onboarding     = "amenGenerationalPresetOnboardingCompleted"
    static let simpleModeKey  = "bereanSimpleModeEnabled"
    static let vanityOverride = "amen_hide_vanity_metrics_override"
}

// MARK: - AmenGenerationalPresetService

@Observable
final class AmenGenerationalPresetService {

    // MARK: Shared instance

    static let shared = AmenGenerationalPresetService()

    // MARK: Observed state

    /// The currently active preset (observation-tracked, externally read-only).
    /// To change, call `setPreset(_:)`.
    private(set) var activePreset: AmenGenerationalPreset = .youngAdult

    /// True once the user has completed the first-run preset picker.
    /// Setting persists to UserDefaults immediately.
    var hasCompletedPresetOnboarding: Bool = false {
        didSet {
            UserDefaults.standard.set(hasCompletedPresetOnboarding, forKey: GenerationalKeys.onboarding)
        }
    }

    // MARK: Derived

    var config: AmenGenerationalSafetyConfig {
        AmenGenerationalSafetyConfig.config(for: activePreset)
    }

    var isTeenMode: Bool { activePreset == .teen }
    var simpleModeDefaulted: Bool { activePreset == .senior }

    // MARK: Init

    private init() {
        load()
    }

    // MARK: - Public mutation

    /// The canonical way to change the active preset from outside the service.
    /// Applies side-effects (UserDefaults, Simple Mode) and persists to Firestore.
    @MainActor
    func setPreset(_ preset: AmenGenerationalPreset) {
        activePreset = preset
        applyPreset()
        persistPreset()
    }

    // MARK: - Private helpers

    /// Side-effects applied whenever the preset changes.
    @MainActor
    private func applyPreset() {
        // Senior: auto-enable the Berean Simple Mode interface.
        if activePreset == .senior {
            UserDefaults.standard.set(true, forKey: GenerationalKeys.simpleModeKey)
        }
        // Teen: permanently suppress vanity metrics regardless of user toggle.
        if activePreset == .teen {
            UserDefaults.standard.set(true, forKey: GenerationalKeys.vanityOverride)
        } else {
            UserDefaults.standard.removeObject(forKey: GenerationalKeys.vanityOverride)
        }
    }

    /// Persist to UserDefaults and kick off a best-effort Firestore sync.
    private func persistPreset() {
        UserDefaults.standard.set(activePreset.rawValue, forKey: GenerationalKeys.preset)
        Task { await syncToFirestore() }
    }

    /// Load persisted state from UserDefaults on cold start.
    /// Direct property write avoids triggering didSet side-effects during restore.
    private func load() {
        hasCompletedPresetOnboarding = UserDefaults.standard.bool(forKey: GenerationalKeys.onboarding)

        let rawValue = UserDefaults.standard.string(forKey: GenerationalKeys.preset) ?? ""
        if let stored = AmenGenerationalPreset(rawValue: rawValue) {
            activePreset = stored    // @Observable: direct property write, no didSet involved
        }
    }

    /// Mirror the preset to the user's Firestore document for cross-device sync.
    /// Failures are silent — local UserDefaults remains the source of truth.
    private func syncToFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "generationalPreset": activePreset.rawValue,
            "generationalPresetOnboardingCompleted": hasCompletedPresetOnboarding,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        try? await Firestore.firestore()
            .collection("users")
            .document(uid)
            .setData(["presetConfig": data], merge: true)
    }
}
