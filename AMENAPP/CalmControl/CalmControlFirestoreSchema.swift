// CalmControlFirestoreSchema.swift
// AMENAPP — Calm Control + Spiritual Rhythm OS
//
// Canonical Firestore path builders and field-name constants for all Calm Control
// subcollections. Use these instead of raw strings to prevent typos and enable
// compile-time refactoring.
//
// Schema lives under: users/{uid}/
//   ├── privacySettings/main
//   ├── feedControls/main
//   ├── notificationSettings/main
//   ├── spiritualRhythm/main
//   ├── streaks/{scripture|prayer|community|reading}
//   ├── presence/main
//   ├── audienceLayers/{layerId}
//   ├── activity/main
//   └── rateLimits/{limitType}

import Foundation

// MARK: - Path Builders

/// Path builders for Calm Control subcollections.
/// Usage: CalmControlPaths.privacySettings(uid: uid)
enum CalmControlPaths {
    static func privacySettings(uid: String) -> String {
        "users/\(uid)/privacySettings/main"
    }
    static func feedControls(uid: String) -> String {
        "users/\(uid)/feedControls/main"
    }
    static func notificationSettings(uid: String) -> String {
        "users/\(uid)/notificationSettings/main"
    }
    static func spiritualRhythm(uid: String) -> String {
        "users/\(uid)/spiritualRhythm/main"
    }
    static func streak(uid: String, type: String) -> String {
        "users/\(uid)/streaks/\(type)"
    }
    static func presence(uid: String) -> String {
        "users/\(uid)/presence/main"
    }
    static func audienceLayer(uid: String, layerId: String) -> String {
        "users/\(uid)/audienceLayers/\(layerId)"
    }
    static func activity(uid: String) -> String {
        "users/\(uid)/activity/main"
    }
    static func rateLimit(uid: String, limitType: String) -> String {
        "users/\(uid)/rateLimits/\(limitType)"
    }
}

// MARK: - Field Name Constants

/// Document field names as constants (prevents typo bugs).
/// Each nested comment block documents the document it belongs to.
enum CalmControlFields {

    // MARK: privacySettings/main
    static let hideFollowerCount         = "hideFollowerCount"
    static let hideFollowingCount        = "hideFollowingCount"
    static let privateFollowingGraph     = "privateFollowingGraph"
    static let quietProfileMode          = "quietProfileMode"
    static let disableReadReceipts       = "disableReadReceipts"
    static let presenceState             = "presenceState"
    static let anonymousReflectionEnabled = "anonymousReflectionEnabled"

    // MARK: feedControls/main
    static let textOnlyMode              = "textOnlyMode"
    static let hidePhotosVideos          = "hidePhotosVideos"
    static let hideViralContent          = "hideViralContent"
    static let noDebateFilter            = "noDebateFilter"
    static let motionReductionFeed       = "motionReductionFeed"
    static let audioAutoplayDisabled     = "audioAutoplayDisabled"
    static let emotionalEnergyFilter     = "emotionalEnergyFilter"

    // MARK: streaks/{type}
    static let currentCount              = "currentCount"
    static let longestCount              = "longestCount"
    static let lastActivityDate          = "lastActivityDate"
    static let gracePeriodsUsed          = "gracePeriodsUsed"
    static let gracePeriodsAllowed       = "gracePeriodsAllowed"
    static let streakState               = "state"

    // MARK: notificationSettings/main
    static let intensityMode             = "intensityMode"
    static let dailyVerseEnabled         = "dailyVerseEnabled"
    static let dailyVerseTime            = "dailyVerseTime"
    static let inactivityPaused          = "inactivityPaused"
    static let pauseNoticeSentAt         = "pauseNoticeSentAt"

    // MARK: activity/main
    static let lastActiveAt              = "lastActiveAt"

    // MARK: shared
    static let updatedAt                 = "updatedAt"
}
