//
//  SupportRecoveryState.swift
//  AMENAPP
//
//  Tracks recovery, stabilization, and back-off logic.
//  Stored at users/{userId}/support_recovery/current.
//

import Foundation

struct SupportRecoveryState: Codable, Sendable {
    var recoveryScore: Double               // 0.0–1.0
    var stabilityTrend: StabilityTrend
    var recentPositiveSignals: [String]     // SupportSignalType.rawValue keys
    var lastSupportActionAt: Date?
    var daysSinceElevatedState: Int
    var backoffEligible: Bool               // True when recovery is stable
    var updatedAt: Date?

    /// Whether the system should back off prompts for this user.
    var shouldBackOff: Bool {
        backoffEligible && recoveryScore > 0.55 && daysSinceElevatedState >= 7
    }

    static var empty: SupportRecoveryState {
        SupportRecoveryState(
            recoveryScore: 0.5,
            stabilityTrend: .stable,
            recentPositiveSignals: [],
            lastSupportActionAt: nil,
            daysSinceElevatedState: 0,
            backoffEligible: false,
            updatedAt: nil
        )
    }
}
