//
//  PrayerSessionAttributes.swift
//  AMENAPP
//
//  ActivityAttributes for the local-only Prayer Session Live Activity.
//  Both the app target and AMENWidgetExtensionExtension compile this file
//  independently — keep both copies in sync.
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
