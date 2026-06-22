// RhythmEngineService.swift — Features/Intelligence/RhythmEngine
// Observes formation signals and computes a private, on-device rhythm model.
//
// Invariants:
//  • Free capability (SystemCapability.rhythmEngine) — no upsell
//  • ConsentEdge.activityToRhythm is default ON; user can revoke
//  • All computed state is device-only (UserDefaults) — never Firestore-synced
//  • Flag: ctx_rhythm_engine_enabled — default false
//  • Crisis dampening: EntitlementGate handles; no check needed here

import Foundation

// MARK: - FormationRhythm

struct FormationRhythm: Codable, Sendable {
    /// Total formation actions logged this week (prayer, study, verse reflection)
    let weeklyCount: Int
    /// Longest unbroken daily streak (days)
    let longestStreakDays: Int
    /// Current unbroken daily streak (days)
    let currentStreakDays: Int
    /// Estimated preferred time of day (hour 0–23), nil if < 5 signals
    let preferredHour: Int?
    /// Days since last formation signal, nil if none ever recorded
    let daysSinceLastSignal: Double?
    let updatedAt: Date
}

// MARK: - RhythmEngineService

@MainActor
final class RhythmEngineService: ObservableObject {
    static let shared = RhythmEngineService()

    @Published private(set) var rhythm: FormationRhythm? = nil

    // Rolling window of formation timestamps — last 90 days, on-device only
    private var formationTimestamps: [Date] = []
    private var subscriptionTask: Task<Void, Never>? = nil

    private static let defaultsKey = "ctx_rhythm_timestamps"
    private static let maxWindow: TimeInterval = 90 * 86_400

    private init() {
        loadFromDefaults()
        recompute()
    }

    // MARK: - Start / Stop

    func startObserving() {
        guard ContextIntelligenceFlags.rhythmEngine else { return }
        guard subscriptionTask == nil else { return }

        subscriptionTask = Task {
            let formationTypes: [SignalType] = [
                .prayerCreated, .prayerAnswered, .studyStarted, .studyCompleted,
                .verseReflected, .wellnessToolUsed, .prayerReminderActed
            ]
            let stream = await ContextBus.shared.subscribe(to: formationTypes)
            for await signal in stream {
                guard !Task.isCancelled else { break }
                guard ConsentStore.shared.isEnabled(.activityToRhythm) else { continue }
                await MainActor.run {
                    self.record(signal.occurredAt)
                }
            }
        }
    }

    func stopObserving() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    // MARK: - Recording

    private func record(_ date: Date) {
        let cutoff = Date().addingTimeInterval(-Self.maxWindow)
        formationTimestamps = formationTimestamps
            .filter { $0 > cutoff }
            .appending(date)
        saveToDefaults()
        recompute()
    }

    // MARK: - Computation

    private func recompute() {
        let cutoff = Date().addingTimeInterval(-Self.maxWindow)
        let recent = formationTimestamps.filter { $0 > cutoff }.sorted()

        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let weeklyCount = recent.filter { $0 > weekAgo }.count

        let (current, longest) = computeStreaks(from: recent)

        var preferredHour: Int? = nil
        if recent.count >= 5 {
            let hours = recent.map { Calendar.current.component(.hour, from: $0) }
            let buckets = Dictionary(grouping: hours, by: { $0 / 3 })
            let topBucket = buckets.max(by: { $0.value.count < $1.value.count })?.key ?? 0
            preferredHour = topBucket * 3 + 1   // mid-point of 3-hour bucket
        }

        let daysSinceLast: Double? = recent.last.map {
            Date().timeIntervalSince($0) / 86_400
        }

        rhythm = FormationRhythm(
            weeklyCount: weeklyCount,
            longestStreakDays: longest,
            currentStreakDays: current,
            preferredHour: preferredHour,
            daysSinceLastSignal: daysSinceLast,
            updatedAt: Date()
        )
    }

    /// Returns (currentStreak, longestStreak) in calendar days.
    private func computeStreaks(from sorted: [Date]) -> (current: Int, longest: Int) {
        guard !sorted.isEmpty else { return (0, 0) }

        var activeDays = Set<Int>()
        for date in sorted {
            let dayIndex = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
            activeDays.insert(dayIndex)
        }

        let todayIndex = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        var current = 0
        var day = todayIndex
        while activeDays.contains(day) {
            current += 1
            day -= 1
        }

        var longest = 0
        var run = 0
        let sortedDays = activeDays.sorted()
        for i in sortedDays.indices {
            if i == 0 || sortedDays[i] != sortedDays[i - 1] + 1 {
                run = 1
            } else {
                run += 1
            }
            longest = max(longest, run)
        }

        return (current, longest)
    }

    // MARK: - Persistence

    private func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([Date].self, from: data) else { return }
        formationTimestamps = decoded
    }

    private func saveToDefaults() {
        guard let data = try? JSONEncoder().encode(formationTimestamps) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

// MARK: - Array helper

private extension Array {
    func appending(_ element: Element) -> Array {
        var copy = self
        copy.append(element)
        return copy
    }
}
