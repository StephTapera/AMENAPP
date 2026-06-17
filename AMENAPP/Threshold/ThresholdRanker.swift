// ThresholdRanker.swift
// AMEN — THRESHOLD Smart Profile / Identity Switcher
//
// W2 IMPLEMENTATION — 2026-06-16
// On-device weighted scorer. No ML, no network, no Firebase. (D2)
//
// W5 TODO: Wire `predictedIntent` once intent-inference engine is available.
//
// ANTI-ENGAGEMENT CONTRACT (ThresholdAntiEngagementNote.swift §WHAT THIS MEANS IN CODE)
//   FORBIDDEN inputs to the scorer: DAU, session length, streak count,
//   return rate, unread-count-as-bait, or any engagement proxy.
//   ALLOWED inputs: time of day, weekday, liturgical season, deep-link
//   hint, and decayed on-device recency weight.
//
// All computation is pure and deterministic for identical inputs.
// This struct must never be instantiated on a background timer or in
// response to a push notification.

import Foundation

// MARK: - Feature Weights (spec §W2, must match exactly)

private enum FeatureWeight {
    static let deepLinkMatch:       Double = 0.40
    static let recencyDecayedUsage: Double = 0.30
    static let serviceWindowFit:    Double = 0.20
    static let timeOfDayFit:        Double = 0.05
    static let seasonFit:           Double = 0.05
}

// MARK: - Reason Strings (spec §W2, ≤ 60 chars each)

private enum ReasonString {
    static let deepLinkMatch       = "You tapped into this profile's content"
    static let recencyDecayedUsage = "You've been here recently"
    static let serviceWindowFit    = "Sunday morning — likely ministry time"
    static let timeOfDayFit        = "Typical time for this profile"
    static let seasonFit           = "Active season for this profile"
    static let fallback            = "Your profile"
}

// MARK: - Liturgical Seasons that elevate ministry profiles

private let ministrySeasons: Set<LiturgicalSeasonType> = [
    .advent, .lent, .holyWeek, .easter, .pentecost
]

// MARK: - DefaultThresholdRanker

/// Weighted on-device scorer for Threshold. Implements `ThresholdRanking`.
///
/// Score formula:
///   score = Σ (featureWeight × featureValue)
///
/// where featureValue is 0 or 1 (binary) for all features except
/// `recencyDecayedUsage`, which is continuous in 0…1.
///
/// Ties are broken alphabetically by profileId for determinism.
struct DefaultThresholdRanker: ThresholdRanking {

    // MARK: - ThresholdRanking

    func rank(_ profiles: [ProfileDescriptor], _ signal: SwitchSignal) -> SwitchPrediction {
        // ANTI-ENGAGEMENT: rank() is a pure function of its arguments.
        // It reads no mutable state, emits no notifications, and starts no timers.
        // Calling it twice with the same arguments always produces the same output.

        var ranked: [RankedProfile] = profiles.map { profile in
            let (score, reason) = scoreAndReason(profile: profile, signal: signal)
            return RankedProfile(profileId: profile.id, score: score, reason: reason)
        }

        // Sort: highest score first; ties broken by profileId alphabetical order
        // for strict determinism regardless of input order.
        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.profileId < rhs.profileId
        }

        let topScore = ranked.first?.score ?? 0.0
        // Clamp to 0…1 (scores are already in range by construction, but be explicit).
        let confidence = min(1.0, max(0.0, topScore))

        // ANTI-ENGAGEMENT: predictedIntent is nil until W5 wires the intent engine.
        // Leaving it nil here means no pre-staged action is shown, which is the
        // correct default — showing intent requires a separate, reviewed signal source.
        return SwitchPrediction(
            ranked: ranked,
            predictedIntent: nil,
            confidence: confidence
        )
    }

    // MARK: - Scorer

    /// Returns (score, reason) for a single profile against the current signal.
    private func scoreAndReason(
        profile: ProfileDescriptor,
        signal: SwitchSignal
    ) -> (Double, String) {

        // --- Feature 1: Deep-link match (weight 0.40) ---
        let deepLinkValue: Double = (signal.deepLinkProfileHint == profile.id) ? 1.0 : 0.0

        // --- Feature 2: Recency-decayed usage (weight 0.30) ---
        // Continuous 0…1. Sourced from on-device UsageStore (W6 stub = 0).
        // ANTI-ENGAGEMENT: this is a decayed *recency* weight, not a session-count
        // or DAU proxy. The decay half-life (~7 days) ensures old usage loses influence.
        let recencyValue: Double = signal.recentUsage[profile.id]?.weight ?? 0.0

        // --- Feature 3: Service-window fit (weight 0.20) ---
        // Binary: fires only for ministry profiles in the Sunday-morning service window.
        let serviceWindowValue: Double =
            (signal.isLikelyServiceWindow && profile.type == .ministry) ? 1.0 : 0.0

        // --- Feature 4: Time-of-day fit (weight 0.05) ---
        let timeOfDayValue: Double = timeOfDayFit(profile: profile, signal: signal)

        // --- Feature 5: Liturgical season fit (weight 0.05) ---
        // Binary: fires for ministry profiles in high-liturgical seasons only.
        let seasonValue: Double =
            (profile.type == .ministry && ministrySeasons.contains(signal.liturgicalSeason)) ? 1.0 : 0.0

        // Weighted sum
        let score =
            FeatureWeight.deepLinkMatch       * deepLinkValue       +
            FeatureWeight.recencyDecayedUsage * recencyValue        +
            FeatureWeight.serviceWindowFit    * serviceWindowValue   +
            FeatureWeight.timeOfDayFit        * timeOfDayValue       +
            FeatureWeight.seasonFit           * seasonValue

        let reason = topReason(
            deepLink:       deepLinkValue,
            recency:        recencyValue,
            serviceWindow:  serviceWindowValue,
            timeOfDay:      timeOfDayValue,
            season:         seasonValue
        )

        return (score, reason)
    }

    // MARK: - Time-of-day fit helper

    /// Binary feature: 1.0 if the profile type matches the typical time-of-day pattern.
    ///
    /// Ministry  → Sunday + morning or earlyMorning
    /// Creator   → midday
    /// Personal  → evening or night
    /// Org       → no time-of-day signal (returns 0)
    private func timeOfDayFit(profile: ProfileDescriptor, signal: SwitchSignal) -> Double {
        switch profile.type {
        case .ministry:
            let isSunday = (signal.dayOfWeek == .sunday)
            let isMorning = (signal.timeBucket == .morning || signal.timeBucket == .earlyMorning)
            return (isSunday && isMorning) ? 1.0 : 0.0

        case .creator:
            return (signal.timeBucket == .midday) ? 1.0 : 0.0

        case .personal:
            let isEvening = (signal.timeBucket == .evening || signal.timeBucket == .night)
            return isEvening ? 1.0 : 0.0

        case .org:
            // No time-of-day heuristic defined for org profiles in W2.
            return 0.0
        }
    }

    // MARK: - Reason resolver

    /// Returns the human-readable string for the single top-contributing feature.
    /// If all feature values are 0, returns the neutral fallback.
    ///
    /// Priority order (highest weight first, then alphabetical for equal weights):
    ///   deepLinkMatch (0.40) > recencyDecayedUsage (0.30) > serviceWindowFit (0.20)
    ///   > timeOfDayFit (0.05) = seasonFit (0.05) [tie → timeOfDayFit wins alphabetically]
    private func topReason(
        deepLink:      Double,
        recency:       Double,
        serviceWindow: Double,
        timeOfDay:     Double,
        season:        Double
    ) -> String {
        // Evaluate in descending weight order.
        // For features with equal weight (timeOfDay / season at 0.05), the one
        // whose weighted contribution is higher wins; at identical values, the
        // alphabetically first reason key is chosen — "seasonFit" < "timeOfDayFit"
        // alphabetically, but per spec timeOfDayFit is listed first (no defined
        // tiebreak in spec), so we check timeOfDay before season for stability.
        if deepLink > 0      { return ReasonString.deepLinkMatch }
        if recency > 0       { return ReasonString.recencyDecayedUsage }
        if serviceWindow > 0 { return ReasonString.serviceWindowFit }
        if timeOfDay > 0     { return ReasonString.timeOfDayFit }
        if season > 0        { return ReasonString.seasonFit }
        return ReasonString.fallback
    }
}
