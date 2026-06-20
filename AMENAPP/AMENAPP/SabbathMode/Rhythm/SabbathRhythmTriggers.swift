// SabbathRhythmTriggers.swift
// AMENAPP — SabbathMode / Rhythm (Sabbath Mode v2, Wave 0)
//
// Wave 0 trigger sources + resolver. Mic-free, no new permissions.
// Wave 1 adds location (church), consented audio (sermon/worship), usage pattern
// (doomscroll) and motion (walk) triggers — each its own sub-flag, all OFF.

import Foundation

// MARK: - Resolver

/// Arbitrates the active state from a set of trigger proposals. The highest-confidence
/// proposal at or above `confidenceThreshold` wins; everything else stays silent
/// (`.normal`). Low-confidence inputs never surface — by contract.
struct SabbathTriggerResolver {

    /// Minimum confidence for a proposal to take effect. Below this, stay `.normal`.
    let confidenceThreshold: Double

    init(confidenceThreshold: Double = 0.5) {
        self.confidenceThreshold = confidenceThreshold
    }

    /// Resolve the active state from enabled triggers. Pure — safe to unit test.
    func resolve(triggers: [SabbathTriggerSource], now: Date) -> SabbathRhythmState {
        let winning = triggers
            .filter { $0.isEnabled }
            .map { $0.proposal(now: now) }
            .filter { $0.confidence >= confidenceThreshold && $0.proposedState != .normal }
            .max { $0.confidence < $1.confidence }
        return winning?.proposedState ?? .normal
    }
}

// MARK: - ManualTrigger

/// User-driven toggle. When the user has begun rest manually, proposes `.rest`
/// with full confidence; otherwise silent. The single source for the manual override
/// is held by `SabbathRhythmController`; this struct just reads it.
struct SabbathManualTrigger: SabbathTriggerSource {
    let id = "manual"
    let isEnabled: Bool
    /// Whether the user has manually entered rest.
    let isManuallyResting: Bool

    func proposal(now: Date) -> SabbathTriggerProposal {
        guard isEnabled, isManuallyResting else { return .silent }
        return SabbathTriggerProposal(proposedState: .rest, confidence: 1.0)
    }
}

// MARK: - ScheduleTrigger

/// User-set weekly rest window (a day + start/end hour in local time). Proposes
/// `.rest` with high confidence while `now` falls inside the window.
struct SabbathScheduleTrigger: SabbathTriggerSource {
    let id = "schedule"
    let isEnabled: Bool
    /// The configured weekly window. Nil → never proposes.
    let schedule: SabbathSchedule?

    func proposal(now: Date) -> SabbathTriggerProposal {
        guard isEnabled, let schedule, schedule.contains(now) else { return .silent }
        return SabbathTriggerProposal(proposedState: .rest, confidence: 0.9)
    }
}

/// A weekly rest window in the user's local calendar. Start/end are whole hours
/// [0, 24]; if `endHour <= startHour` the window wraps past midnight.
struct SabbathSchedule: Codable, Equatable {
    /// 1 = Sunday … 7 = Saturday (matches `Calendar.component(.weekday:)`).
    var weekday: Int
    var startHour: Int
    var endHour: Int

    /// Whether `date` falls inside this weekly window, in the current calendar.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let comps = calendar.dateComponents([.weekday, .hour], from: date)
        guard let weekday = comps.weekday, let hour = comps.hour else { return false }
        guard weekday == self.weekday else { return false }
        if endHour <= startHour {
            // Wraps past midnight — active from startHour to end of day.
            return hour >= startHour || hour < endHour
        }
        return hour >= startHour && hour < endHour
    }
}
