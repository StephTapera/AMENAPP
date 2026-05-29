//
//  AmenLiveActivityAttributes.swift
//  AMENAPP
//
//  ActivityKit attribute types for AMEN Live Activities.
//  Shared between the main app target (for starting/updating/ending)
//  and the AMENWidgetExtension target (for rendering views).
//
//  Requires iOS 16.2+.
//

import ActivityKit
import Foundation
import SwiftUI

// MARK: - Prayer Session

/// Attributes for a live group prayer session.
/// Static (unchanging) data is held on the outer struct;
/// dynamic (tick-updated) data lives in ContentState.
@available(iOS 16.2, *)
struct PrayerSessionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Short title shown on the Lock Screen / Dynamic Island.
        var prayerTitle: String
        /// How many minutes the session has been running.
        var elapsedMinutes: Int
        /// Number of people praying together in real time.
        var participantCount: Int
        /// When true the session was started from a church space.
        var isChurchMode: Bool
    }

    /// The broad topic or scripture reference the group is praying over.
    let prayerTopic: String
    /// Display name of the prayer group or Space.
    let groupName: String
}

// MARK: - Berean Study

/// Attributes for an active Berean bible-study session.
@available(iOS 16.2, *)
struct BereanStudyAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Short book abbreviation, e.g. "John".
        var currentBook: String
        /// Current verse reference, e.g. "3:16".
        var currentVerse: String
        /// Overall study-plan completion, 0.0–1.0.
        var progressPercent: Double
        /// User's consecutive-day reading streak.
        var streakDays: Int
    }

    /// Display name of the study plan the user is following.
    let studyPlanName: String
}

// MARK: - Church Event

/// Attributes for an upcoming or live church service / event.
@available(iOS 16.2, *)
struct ChurchEventAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Minutes remaining until the service starts (0 once live).
        var minutesUntilStart: Int
        /// Service name, e.g. "Sunday Morning Worship".
        var serviceName: String
        /// True once the service has begun.
        var isLive: Bool
    }

    /// Display name of the church hosting the event.
    let churchName: String
    /// Street address shown on the expanded island.
    let address: String
}
