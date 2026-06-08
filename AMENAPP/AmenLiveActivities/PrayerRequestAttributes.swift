//
//  PrayerRequestAttributes.swift
//  AMENAPP  /  AMENWidgetExtension
//
//  Shared ActivityAttributes for the push-driven Prayer Request Live Activity.
//  Both targets compile this independently — keep both copies in sync.
//  NOTE: prayerRequests/{id} is a separate denormalized collection from
//  canonical prayers/{id}; the no-spectacle invariant for intelligence cards
//  (formationGovernor.js:41) is not affected.
//

import ActivityKit

struct PrayerRequestAttributes: ActivityAttributes {
    let requestId: String
    let requesterName: String
    let title: String

    struct ContentState: Codable, Hashable {
        var prayingCount: Int
        var encouragementCount: Int
        var isAnswered: Bool
    }
}
