//
//  PrayerSessionAttributes.swift
//  AMENWidgetExtension  ←  widget-target copy
//
//  Duplicate of AMENAPP/AmenLiveActivities/PrayerSessionAttributes.swift.
//  Both targets compile this independently — keep both copies in sync.
//

import Foundation
import ActivityKit

struct PrayerSessionAttributes: ActivityAttributes {
    /// Displayed title of the session (e.g. "Evening Prayer").
    let title: String
    /// The moment the session began; drives the live countdown timer in the UI.
    let startedAt: Date

    struct ContentState: Codable, Hashable {
        /// Optional focus topic shown beneath the timer.
        var topic: String?
    }
}
