//
//  DeviceIntegrityService.swift
//  AMENAPP
//
//  Tracks device-level integrity signals:
//  - Failed login attempts (locks after 5)
//  - Rapid identical action bursts (>10 in 60s)
//  - Time-between-action anomalies (bot-like behavior)
//
//  Writes suspicious activity score increments to users/{uid} on Firestore.
//  Works alongside NewAccountRestrictionService for new-account throttling.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class DeviceIntegrityService {

    static let shared = DeviceIntegrityService()
    private init() {}

    // MARK: - State

    private var failedLoginCount = 0
    private var loginLockUntil: Date?

    // Action burst detection — keyed by action name
    private var actionTimestamps: [String: [Date]] = [:]
    private let burstWindow: TimeInterval = 60   // 60s window
    private let burstThreshold = 10              // >10 identical actions in 60s

    // Minimum time between actions (bot detection) — keyed by action
    private let minActionInterval: [String: TimeInterval] = [
        "comment": 0.5,
        "amen": 0.3,
        "follow": 1.0,
        "post": 2.0,
        "report": 2.0,
    ]

    private let db = Firestore.firestore()

    // MARK: - Login Lockout

    /// Returns nil if login is allowed, or an error message if locked.
    func checkLoginAllowed() -> String? {
        if let lockUntil = loginLockUntil, Date() < lockUntil {
            let remaining = Int(lockUntil.timeIntervalSince(Date()))
            return "Too many failed login attempts. Please wait \(remaining) seconds before trying again."
        }
        return nil
    }

    func recordLoginSuccess() {
        failedLoginCount = 0
        loginLockUntil = nil
    }

    func recordLoginFailure() {
        failedLoginCount += 1
        if failedLoginCount >= 5 {
            // Lock for 15 minutes
            loginLockUntil = Date().addingTimeInterval(15 * 60)
            dlog("⚠️ [DeviceIntegrity] Login locked after \(failedLoginCount) failures")
        }
    }

    // MARK: - Burst Detection

    /// Call before any user action. Returns false + reason if the action should be blocked.
    @discardableResult
    func checkAction(_ action: String) -> (allowed: Bool, reason: String?) {
        let now = Date()

        // Check minimum interval (bot-like speed)
        if let min = minActionInterval[action] {
            let timestamps = actionTimestamps[action] ?? []
            if let last = timestamps.last, now.timeIntervalSince(last) < min {
                return (false, "You're acting too quickly. Please slow down.")
            }
        }

        // Record timestamp
        var timestamps = actionTimestamps[action] ?? []
        timestamps.append(now)

        // Prune old timestamps outside the burst window
        timestamps = timestamps.filter { now.timeIntervalSince($0) <= burstWindow }
        actionTimestamps[action] = timestamps

        // Check for burst
        if timestamps.count > burstThreshold {
            dlog("⚠️ [DeviceIntegrity] Burst detected: \(timestamps.count) \(action) actions in \(burstWindow)s")
            incrementSuspiciousScore(reason: "burst_\(action)")
            return (false, "You're performing this action too quickly. Please wait a moment.")
        }

        return (true, nil)
    }

    // MARK: - Suspicious Score

    private func incrementSuspiciousScore(reason: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            try? await db.collection("users").document(uid).updateData([
                "suspiciousActivityScore": FieldValue.increment(Int64(1)),
                "lastSuspiciousReason": reason,
                "lastSuspiciousAt": FieldValue.serverTimestamp(),
            ])
        }
    }

    // MARK: - Reset (call on sign-out)

    func reset() {
        failedLoginCount = 0
        loginLockUntil = nil
        actionTimestamps.removeAll()
    }
}
