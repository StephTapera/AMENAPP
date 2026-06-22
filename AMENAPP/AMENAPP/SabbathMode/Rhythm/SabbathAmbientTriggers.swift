// SabbathAmbientTriggers.swift
// AMENAPP — SabbathMode / Rhythm (Sabbath Mode v2, Wave 1)
//
// The Wave 1 ambient triggers: usage (doomscroll), location (at a place of worship),
// and motion (a sustained walk). Each PROPOSES a state, never sets it — the resolver
// still arbitrates exactly as in Wave 0.
//
// Design rule: a trigger NEVER owns a sensor. It reads an injected `SabbathAmbientSignals`
// snapshot, which keeps every proposal pure / testable and — crucially — adds NO new OS
// permission. A future sensor layer simply calls `SabbathRhythmController.updateAmbientSignals`;
// until it does, the signals stay at their neutral defaults and these triggers stay silent.
//
// All three are opt-in via `SabbathRhythmConfig` and inert unless `sabbath_mode_enabled` is ON.

import Foundation

// MARK: - Injected signals

/// A neutral snapshot of ambient context the app may (optionally, later) provide. Defaults
/// describe "nothing detected", so an absent sensor layer can never trigger a Sabbath state.
struct SabbathAmbientSignals: Equatable {
    /// Continuous seconds the user has been dwelling in a feed — the doomscroll measure.
    var feedDwellSeconds: TimeInterval
    /// True while the device is at a known place of worship (church check-in / geofence).
    var isAtPlaceOfWorship: Bool
    /// True during a sustained walk (a natural moment to set the phone down).
    var isWalking: Bool

    /// "Nothing detected" — the safe default the controller starts with.
    static let none = SabbathAmbientSignals(
        feedDwellSeconds: 0,
        isAtPlaceOfWorship: false,
        isWalking: false
    )
}

// MARK: - Usage (doomscroll) trigger

/// Proposes `.rest` once feed dwell crosses a gentle threshold, with confidence ramping
/// up the longer the scroll continues. This is an *invitation* to rest, not a lockout.
struct SabbathUsageTrigger: SabbathTriggerSource {
    let id = "usage"
    let isEnabled: Bool
    let dwellSeconds: TimeInterval

    /// Rest is first *proposed* at 25 minutes of continuous feed dwell …
    private let onsetSeconds: TimeInterval = 25 * 60
    /// … and reaches full confidence by 40 minutes.
    private let fullConfidenceSeconds: TimeInterval = 40 * 60

    func proposal(now: Date) -> SabbathTriggerProposal {
        guard isEnabled, dwellSeconds >= onsetSeconds else { return .silent }
        let span = fullConfidenceSeconds - onsetSeconds
        let fraction = span > 0 ? min(1.0, (dwellSeconds - onsetSeconds) / span) : 1.0
        // Start exactly at the resolver threshold (0.5) so onset takes effect immediately.
        let confidence = 0.5 + 0.5 * fraction
        return SabbathTriggerProposal(proposedState: .rest, confidence: confidence)
    }
}

// MARK: - Location (place of worship) trigger

/// Proposes `.presence` while at a place of worship — quiet the social layer but keep
/// navigation so the Bible / Church Notes remain reachable during the service.
struct SabbathLocationTrigger: SabbathTriggerSource {
    let id = "location"
    let isEnabled: Bool
    let isAtPlaceOfWorship: Bool

    func proposal(now: Date) -> SabbathTriggerProposal {
        guard isEnabled, isAtPlaceOfWorship else { return .silent }
        return SabbathTriggerProposal(proposedState: .presence, confidence: 0.8)
    }
}

// MARK: - Motion (sustained walk) trigger

/// Proposes `.rest` during a sustained walk. Lower confidence than the explicit signals —
/// a nudge to look up, easily overridden by the one-tap exit.
struct SabbathMotionTrigger: SabbathTriggerSource {
    let id = "motion"
    let isEnabled: Bool
    let isWalking: Bool

    func proposal(now: Date) -> SabbathTriggerProposal {
        guard isEnabled, isWalking else { return .silent }
        return SabbathTriggerProposal(proposedState: .rest, confidence: 0.6)
    }
}
