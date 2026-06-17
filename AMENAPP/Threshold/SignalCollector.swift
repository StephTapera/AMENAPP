// SignalCollector.swift
// AMEN — THRESHOLD Smart Profile / Identity Switcher
//
// W2 IMPLEMENTATION — 2026-06-16
// Builds a SwitchSignal from the device's current calendar state
// and the app entry context. All computation is on-device. (D2)
//
// W5 TODO: Replace `.standard` networkClass with NWPathMonitor integration.
// W6 TODO: Replace empty `recentUsage` with UsageStore read.
//
// ANTI-ENGAGEMENT: This file must never be called from a background worker,
// push notification handler, or any timer. It is called only when the user
// explicitly opens Threshold. No notification, badge, or nudge is emitted.
// See ThresholdAntiEngagementNote.swift for the full constraint.

import Foundation

// MARK: - SignalCollector

/// Builds the on-device SwitchSignal when the user opens Threshold.
/// Value type — stateless. Inject `now` for testability.
struct SignalCollector {

    // MARK: - Public API

    /// Builds a SwitchSignal from the device's current state.
    ///
    /// - Parameters:
    ///   - now:            The reference moment. Defaults to `Date()` in production;
    ///                     pass a fixed date in tests for determinism.
    ///   - entryContext:   How the user arrived at Threshold.
    ///   - deepLinkHint:   ProfileID carried by an incoming deep link, if any.
    /// - Returns:          A fully-populated SwitchSignal. No network calls made.
    static func collect(
        now: Date = Date(),
        entryContext: EntryContext,
        deepLinkHint: ProfileID? = nil
    ) -> SwitchSignal {
        let calendar = Calendar.current

        let hour = calendar.component(.hour, from: now)
        let bucket = timeBucket(for: hour)

        // Calendar.current weekday: 1=Sunday … 7=Saturday, matching Weekday raw values.
        let calendarWeekday = calendar.component(.weekday, from: now)
        let weekday = Weekday(rawValue: calendarWeekday) ?? .sunday

        let serviceWindow = isLikelyServiceWindow(weekday: weekday, hour: hour)

        let season = LiturgicalCalendarEngine.shared.currentSeason()

        // ANTI-ENGAGEMENT: recentUsage is intentionally empty until W6 wires UsageStore.
        // The stub ensures the ranker cannot observe session-derived data that hasn't
        // been explicitly reviewed for anti-engagement compliance.
        let recentUsage: [ProfileID: DecayedUsage] = [:]

        // ANTI-ENGAGEMENT: networkClass defaults to .standard until W5 wires NWPathMonitor.
        // Defaulting here (not reading a live path) avoids any background-reachability
        // subscription that could inadvertently drive re-engagement decisions.
        let networkClass: NetworkClass = .standard

        return SwitchSignal(
            now: now,
            timeBucket: bucket,
            dayOfWeek: weekday,
            isLikelyServiceWindow: serviceWindow,
            liturgicalSeason: season,
            entrySurface: entryContext,
            deepLinkProfileHint: deepLinkHint,
            networkClass: networkClass,
            recentUsage: recentUsage
        )
    }

    // MARK: - Private Helpers

    /// Maps a 0–23 hour to the appropriate TimeBucket.
    ///
    /// earlyMorning: 04–06   morning: 07–11   midday: 12–14
    /// afternoon: 15–17      evening: 18–20   night: everything else (21–03)
    private static func timeBucket(for hour: Int) -> TimeBucket {
        switch hour {
        case 4...6:   return .earlyMorning
        case 7...11:  return .morning
        case 12...14: return .midday
        case 15...17: return .afternoon
        case 18...20: return .evening
        default:      return .night      // 21–23 and 0–3
        }
    }

    /// Returns true when the moment falls in the canonical Sunday-morning
    /// service window (Sunday, 08:00–12:00 inclusive).
    ///
    /// The hour range is 8...12 per spec (inclusive of noon for late services).
    private static func isLikelyServiceWindow(weekday: Weekday, hour: Int) -> Bool {
        weekday == .sunday && (8...12).contains(hour)
    }
}
