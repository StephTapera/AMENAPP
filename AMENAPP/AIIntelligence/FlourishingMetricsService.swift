// FlourishingMetricsService.swift
// AMENAPP
//
// Wave 5 — Human Flourishing Metrics (anti-engagement).
//
// Computes flourishing signals from REAL events only. Each candidate signal has a
// resolver that returns nil when its source is not instrumented; those signals are
// OMITTED from the report and surfaced separately as "not yet measured" — never
// zero-filled or invented (§2.1, §2 brief). No leaderboards, no streaks.
//
// eventSource is mandatory and names the real source feeding each emitted signal.
//
// Gated by AMENFeatureFlags.shared.flourishingMetricsEnabled (default OFF).

import Foundation

@MainActor
final class FlourishingMetricsService: ObservableObject {

    @Published private(set) var metrics: FlourishingMetrics?
    /// Human-readable names of signals whose real source isn't instrumented yet.
    /// Shown honestly instead of fabricating values.
    @Published private(set) var notYetMeasured: [String] = []

    /// A candidate signal: title, the real source key, and a resolver that returns
    /// a real value or nil (not instrumented).
    private struct SignalSpec {
        let key: String
        let title: String
        let eventSource: String
        let resolve: () -> Double?
    }

    func refresh() {
        let specs = makeSpecs()

        var signals: [FlourishingSignal] = []
        var missing: [String] = []

        for spec in specs {
            if let value = spec.resolve() {
                signals.append(FlourishingSignal(key: spec.key, value: value, eventSource: spec.eventSource))
            } else {
                missing.append(spec.title)
            }
        }

        metrics = FlourishingMetrics(weekOf: currentWeekStartISO(), signals: signals)
        notYetMeasured = missing
    }

    // MARK: - Signal registry

    private func makeSpecs() -> [SignalSpec] {
        [
            // REAL sources (verified on-device):
            SignalSpec(
                key: "berean_topics_remembered",
                title: "Topics Berean remembers for you",
                eventSource: "BereanMemoryStore.records"
            ) {
                Double(BereanMemoryStore.shared.records.count)
            },
            SignalSpec(
                key: "prayer_logged_today",
                title: "Prayer logged today",
                eventSource: "UserDefaults:berean.prayer.today"
            ) {
                let entry = UserDefaults.standard.string(forKey: "berean.prayer.today") ?? ""
                return entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : 1
            },

            // NOT-yet-instrumented sources — resolve nil so they are omitted, not faked.
            SignalSpec(key: "meaningful_conversations", title: "Meaningful conversations",
                       eventSource: "n/a") { nil },
            SignalSpec(key: "resources_completed", title: "Resources completed",
                       eventSource: "n/a") { nil },
            SignalSpec(key: "encouragements_given", title: "Encouragements given",
                       eventSource: "n/a") { nil },
            SignalSpec(key: "volunteer_hours", title: "Volunteer hours",
                       eventSource: "n/a") { nil }
        ]
    }

    // MARK: - Week boundary

    private func currentWeekStartISO() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        let now = Date()
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: startOfWeek)
    }
}
