// HealthyUsageNudgeService.swift
// TrustOS — Healthy Usage Nudge
// Tracks session duration and surfaces gentle break reminders after threshold minutes.

import Foundation

@MainActor
final class HealthyUsageNudgeService: ObservableObject {

    static let shared = HealthyUsageNudgeService()

    @Published var shouldShowNudge: Bool = false
    @Published var nudgeMessage: String = ""

    private var sessionStartTime: Date? = nil
    private var nudgeThresholdMinutes: Int = 45

    private let nudgeMessages: [String] = [
        "You've been here a while.",
        "Time for a pause?",
        "A moment of reflection.",
        "Your eyes need rest — consider a break."
    ]

    private init() {}

    // MARK: - Session Control

    func beginSession() {
        sessionStartTime = Date()
        scheduleNudge(afterMinutes: nudgeThresholdMinutes)
    }

    func endSession() {
        sessionStartTime = nil
        shouldShowNudge = false
        nudgeMessage = ""
    }

    func dismissNudge() {
        shouldShowNudge = false
        scheduleNudge(afterMinutes: 20)
    }

    // MARK: - Computed Duration

    var sessionDurationMinutes: Int {
        guard let start = sessionStartTime else { return 0 }
        return Int(Date().timeIntervalSince(start) / 60)
    }

    // MARK: - Private

    private func scheduleNudge(afterMinutes minutes: Int) {
        let nanoseconds = UInt64(minutes) * 60 * 1_000_000_000
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            await MainActor.run {
                guard let self else { return }
                self.nudgeMessage = self.nudgeMessages.randomElement() ?? self.nudgeMessages[0]
                self.shouldShowNudge = true
            }
        }
    }
}
