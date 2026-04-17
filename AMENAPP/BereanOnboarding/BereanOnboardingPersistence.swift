// BereanOnboardingPersistence.swift
// AMENAPP — Berean Onboarding V3
// Protocol-backed persistence with a UserDefaults implementation.

import Foundation

// MARK: - Protocol

protocol BereanOnboardingPersisting {
    func loadState() -> BereanOnboardingState
    func saveLastViewedStep(_ step: BereanOnboardingStep)
    func saveSelectedFocuses(_ focuses: Set<BereanFocus>)
    func markCompleted(mode: BereanOnboardingCompletionMode, focuses: Set<BereanFocus>)
    func reset()
}

// MARK: - UserDefaults Implementation

final class BereanOnboardingUserDefaultsPersistence: BereanOnboardingPersisting {

    private enum Keys {
        static let hasCompleted = "berean_onboarding_completed_v3"
        static let lastStep = "berean_onboarding_last_step_v3"
        static let selectedFocuses = "berean_onboarding_focuses_v3"
        static let completionMode = "berean_onboarding_mode_v3"
        static let completionDate = "berean_onboarding_date_v3"
        static let legacyCompleted = "bereanOnboardingComplete"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadState() -> BereanOnboardingState {
        let hasCompletedBereanOnboarding = defaults.bool(forKey: Keys.hasCompleted)
            || defaults.bool(forKey: Keys.legacyCompleted)
        let lastStepRaw = defaults.object(forKey: Keys.lastStep) as? Int ?? 0
        let selectedFocusValues = defaults.array(forKey: Keys.selectedFocuses) as? [String] ?? []
        let completionModeRaw = defaults.string(forKey: Keys.completionMode)
        let completionDate = defaults.object(forKey: Keys.completionDate) as? Date

        return BereanOnboardingState(
            hasCompletedBereanOnboarding: hasCompletedBereanOnboarding,
            selectedFocuses: Set(selectedFocusValues.compactMap(BereanFocus.init(rawValue:))),
            lastViewedStep: BereanOnboardingStep(rawValue: lastStepRaw) ?? .introduction,
            completionDate: completionDate,
            completionMode: completionModeRaw.flatMap(BereanOnboardingCompletionMode.init(rawValue:))
        )
    }

    func saveLastViewedStep(_ step: BereanOnboardingStep) {
        defaults.set(step.rawValue, forKey: Keys.lastStep)
    }

    func saveSelectedFocuses(_ focuses: Set<BereanFocus>) {
        defaults.set(focuses.map(\.rawValue).sorted(), forKey: Keys.selectedFocuses)
    }

    func markCompleted(mode: BereanOnboardingCompletionMode, focuses: Set<BereanFocus>) {
        defaults.set(true, forKey: Keys.hasCompleted)
        defaults.set(true, forKey: Keys.legacyCompleted)
        defaults.set(mode.rawValue, forKey: Keys.completionMode)
        defaults.set(Date(), forKey: Keys.completionDate)
        saveSelectedFocuses(focuses)
        defaults.set(BereanOnboardingStep.introduction.rawValue, forKey: Keys.lastStep)
    }

    func reset() {
        [
            Keys.hasCompleted,
            Keys.lastStep,
            Keys.selectedFocuses,
            Keys.completionMode,
            Keys.completionDate,
            Keys.legacyCompleted
        ].forEach { defaults.removeObject(forKey: $0) }
    }
}
