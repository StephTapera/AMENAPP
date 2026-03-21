//
//  PrayerChainActivityAttributes.swift
//  AMENWidgetExtension
//
//  Data model for Prayer Chain Live Activity (Dynamic Island + Lock Screen).
//  Shows real-time prayer chain progress.
//

import Foundation
import ActivityKit

struct PrayerChainActivityAttributes: ActivityAttributes, Codable, Hashable {
    let prayerRequestID: String
    let prayerText: String
    let authorName: String
    let targetCount: Int
    
    struct ContentState: Codable, Hashable {
        var currentCount: Int
        var recentPrayers: [String] // Recent prayer names (max 3)
        var percentComplete: Double
        var isComplete: Bool
    }
}
