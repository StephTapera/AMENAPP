// AmenWellbeingService.swift
// AMENAPP
// Tracks in-session wellbeing signals and gates Selah Pause / emotional check-in.

import Foundation
import Combine
import SwiftUI
import FirebaseAuth

@MainActor
final class AmenWellbeingService: ObservableObject {
    static let shared = AmenWellbeingService()

    @Published private(set) var activeBoundary: SessionBoundary?
    @Published private(set) var shouldShowSelahPause = false
    @Published private(set) var emotionalCheckInPending = false

    private let core = AmenSocialSafetyService.shared
    private var sessionStartTime: Date = Date()
    private var scrollEventCount: Int = 0
    private var rapidScrollStreak: Int = 0

    // MARK: - Session Tracking

    func onSessionStart() {
        sessionStartTime = Date()
        scrollEventCount = 0
        rapidScrollStreak = 0
        Task { await refreshBoundary() }
    }

    func onScrollEvent(velocity: CGFloat) {
        scrollEventCount += 1
        if abs(velocity) > 1500 {
            rapidScrollStreak += 1
        } else {
            rapidScrollStreak = 0
        }
        if rapidScrollStreak >= 8 {
            recordSignal(.rapidScroll, intensity: min(Double(abs(velocity)) / 3000.0, 1.0))
            rapidScrollStreak = 0
        }
        // Check 30-min session milestone
        let elapsed = Date().timeIntervalSince(sessionStartTime) / 60
        if Int(elapsed) % 30 == 0 && Int(elapsed) > 0 {
            checkSessionDuration(minutes: Int(elapsed))
        }
    }

    func onNegativeReactionReceived() {
        recordSignal(.negativeEngagement, intensity: 0.6)
    }

    func onLateNightUsage() {
        guard AMENFeatureFlags.shared.selahPauseEnabled else { return }
        recordSignal(.lateNightUse, intensity: 0.9)
        shouldShowSelahPause = true
    }

    func onEmotionalKeywordDetected(keyword: String) {
        guard AMENFeatureFlags.shared.emotionalCheckInEnabled else { return }
        recordSignal(.highEmotionalDraft, intensity: 0.7, context: keyword)
        emotionalCheckInPending = true
    }

    func dismissSelahPause() {
        shouldShowSelahPause = false
    }

    func dismissEmotionalCheckIn() {
        emotionalCheckInPending = false
    }

    // MARK: - Private Helpers

    private func checkSessionDuration(minutes: Int) {
        guard AMENFeatureFlags.shared.healthyUseDashboardEnabled else { return }
        Task {
            if let boundary = try? await core.checkSessionBoundary(), !boundary.pauseShown {
                activeBoundary = boundary
            }
        }
    }

    private func recordSignal(
        _ type: WellbeingSignalType,
        intensity: Double,
        context: String? = nil
    ) {
        let signal = WellbeingSignal(
            id: UUID().uuidString,
            uid: Auth.auth().currentUser?.uid ?? "",
            signalType: type,
            value: intensity,
            confidence: context == nil ? 1.0 : 0.9,
            createdAt: Date(),
            source: "client",
            isClientVisible: false
        )
        core.appendWellbeingSignal(signal)
    }

    private func refreshBoundary() async {
        activeBoundary = try? await core.checkSessionBoundary()
    }
}
