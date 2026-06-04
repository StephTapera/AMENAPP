// BereanOnboardingAnalytics.swift
// AMENAPP — Berean Onboarding V3
// Protocol-backed analytics with privacy-safe payloads.

import Foundation
import FirebaseAnalytics

// MARK: - Protocol

protocol BereanOnboardingAnalyticsTracking {
    func trackViewed(source: String)
    func trackStepViewed(_ step: BereanOnboardingStep, selectedFocuses: Set<BereanFocus>, source: String)
    func trackContinueTapped(from step: BereanOnboardingStep, selectedFocuses: Set<BereanFocus>, source: String)
    func trackBackTapped(from step: BereanOnboardingStep, selectedFocuses: Set<BereanFocus>, source: String)
    func trackSkipTapped(from step: BereanOnboardingStep, selectedFocuses: Set<BereanFocus>, source: String)
    func trackFocusSelected(_ focus: BereanFocus, selectedFocuses: Set<BereanFocus>, step: BereanOnboardingStep, source: String)
    func trackFocusDeselected(_ focus: BereanFocus, selectedFocuses: Set<BereanFocus>, step: BereanOnboardingStep, source: String)
    func trackCompleted(mode: BereanOnboardingCompletionMode, focuses: Set<BereanFocus>, source: String)
}

// MARK: - Default Analytics

final class BereanOnboardingDefaultAnalytics: BereanOnboardingAnalyticsTracking {

    private enum Event {
        static let viewed = "berean_onboarding_viewed"
        static let stepViewed = "berean_onboarding_step_viewed"
        static let continueTapped = "berean_onboarding_continue_tapped"
        static let backTapped = "berean_onboarding_back_tapped"
        static let skipTapped = "berean_onboarding_skip_tapped"
        static let focusSelected = "berean_onboarding_focus_selected"
        static let focusDeselected = "berean_onboarding_focus_deselected"
        static let completed = "berean_onboarding_completed"
    }

    func trackViewed(source: String) {
        log(Event.viewed, ["source": source])
    }

    func trackStepViewed(_ step: BereanOnboardingStep, selectedFocuses: Set<BereanFocus>, source: String) {
        log(Event.stepViewed, payload(step: step, focuses: selectedFocuses, source: source))
    }

    func trackContinueTapped(from step: BereanOnboardingStep, selectedFocuses: Set<BereanFocus>, source: String) {
        log(Event.continueTapped, payload(step: step, focuses: selectedFocuses, source: source))
    }

    func trackBackTapped(from step: BereanOnboardingStep, selectedFocuses: Set<BereanFocus>, source: String) {
        log(Event.backTapped, payload(step: step, focuses: selectedFocuses, source: source))
    }

    func trackSkipTapped(from step: BereanOnboardingStep, selectedFocuses: Set<BereanFocus>, source: String) {
        log(Event.skipTapped, payload(step: step, focuses: selectedFocuses, source: source))
    }

    func trackFocusSelected(_ focus: BereanFocus, selectedFocuses: Set<BereanFocus>, step: BereanOnboardingStep, source: String) {
        var params = payload(step: step, focuses: selectedFocuses, source: source)
        params["focus_value"] = focus.rawValue
        log(Event.focusSelected, params)
    }

    func trackFocusDeselected(_ focus: BereanFocus, selectedFocuses: Set<BereanFocus>, step: BereanOnboardingStep, source: String) {
        var params = payload(step: step, focuses: selectedFocuses, source: source)
        params["focus_value"] = focus.rawValue
        log(Event.focusDeselected, params)
    }

    func trackCompleted(mode: BereanOnboardingCompletionMode, focuses: Set<BereanFocus>, source: String) {
        var params = payload(step: .ready, focuses: focuses, source: source)
        params["completion_mode"] = mode.rawValue
        log(Event.completed, params)
    }

    private func payload(step: BereanOnboardingStep, focuses: Set<BereanFocus>, source: String) -> [String: Any] {
        [
            "step_index": step.analyticsIndex,
            "step_name": step.analyticsName,
            "selected_focus_count": focuses.count,
            "selected_focus_values": focuses.map(\.rawValue).sorted().joined(separator: ","),
            "source": source
        ]
    }

    private func log(_ event: String, _ params: [String: Any]) {
        // Fire to Firebase Analytics — fire-and-forget, must not block onboarding progression.
        // Firebase Analytics caps parameter values at 100 characters; coerce [String: Any] → [String: Any]
        // by casting numeric values to Double (the only type Firebase accepts for numeric params).
        var firebaseParams: [String: Any] = [:]
        for (key, value) in params {
            switch value {
            case let s as String:
                firebaseParams[key] = String(s.prefix(100))
            case let i as Int:
                firebaseParams[key] = Double(i)
            case let d as Double:
                firebaseParams[key] = d
            default:
                firebaseParams[key] = "\(value)".prefix(100).description
            }
        }
        Analytics.logEvent(event, parameters: firebaseParams.isEmpty ? nil : firebaseParams)

        #if DEBUG
        print("[BereanAnalytics] \(event) \(params)")
        #endif
    }
}
