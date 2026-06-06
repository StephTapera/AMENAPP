// AmenOSBridge.swift
// AMENAPP
//
// Thin signal bus between Trust OS and Berean OS.
// Fire-and-forget — no return values; both OSes remain independently
// operable if the other is unavailable.
//
// Trust OS → Berean OS:
//   .crisisDetected   → Berean surfaces CrisisCard only (no AI, no callModel)
//   .supportStateChanged → Berean surfaces gentle check-in
//
// Berean OS → Trust OS:
//   .formationStreakActive    → BehavioralAwarenessEngine de-escalates one level
//   .mentoringSessionCompleted → CommunityHealthService positive signal

import Foundation

// MARK: - Notification Names

extension Notification.Name {
    static let amenOSCrisisDetected            = Notification.Name("amenOS.crisisDetected")
    static let amenOSSupportStateChanged       = Notification.Name("amenOS.supportStateChanged")
    static let amenOSFormationStreakActive      = Notification.Name("amenOS.formationStreakActive")
    static let amenOSMentoringSessionCompleted = Notification.Name("amenOS.mentoringSessionCompleted")
}

// MARK: - UserInfo Keys

enum AmenOSBridgeKey {
    static let uid      = "uid"
    static let state    = "state"
    static let signal   = "signal"
    static let streakDay = "streakDay"
}

// MARK: - Bridge

final class AmenOSBridge {
    static let shared = AmenOSBridge()
    private init() {}

    // MARK: Trust OS → Berean OS

    /// SafetyOrchestrator calls this when supportState reaches .crisisUrgent / .crisisRecommended.
    /// Berean MUST surface CrisisCard only — no AI card, no callModel call.
    func crisisDetected(uid: String, sessionSignal: String) {
        NotificationCenter.default.post(
            name: .amenOSCrisisDetected,
            object: nil,
            userInfo: [AmenOSBridgeKey.uid: uid, AmenOSBridgeKey.signal: sessionSignal]
        )
    }

    /// SafetyOrchestrator calls this on every supportState transition.
    /// Berean uses stateRawValue (SafetySupportState.rawValue Int) to decide
    /// whether to show a gentle check-in card.
    func supportStateChanged(uid: String, stateRawValue: Int) {
        NotificationCenter.default.post(
            name: .amenOSSupportStateChanged,
            object: nil,
            userInfo: [AmenOSBridgeKey.uid: uid, AmenOSBridgeKey.state: stateRawValue]
        )
    }

    // MARK: Berean OS → Trust OS

    /// FormationOSIntegrationService calls this when a user completes a streak day.
    /// BehavioralAwarenessEngine de-escalates .distressedScrolling by one level
    /// because active spiritual engagement is a positive behavioral signal.
    func formationStreakActive(uid: String, streakDay: Int) {
        NotificationCenter.default.post(
            name: .amenOSFormationStreakActive,
            object: nil,
            userInfo: [AmenOSBridgeKey.uid: uid, AmenOSBridgeKey.streakDay: streakDay]
        )
    }

    /// MentorshipIntelligenceService calls this after a session is marked complete.
    /// CommunityHealthService uses this as a positive mentorship engagement signal.
    func mentoringSessionCompleted(uid: String) {
        NotificationCenter.default.post(
            name: .amenOSMentoringSessionCompleted,
            object: nil,
            userInfo: [AmenOSBridgeKey.uid: uid]
        )
    }
}
