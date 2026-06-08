//
//  EndPrayerSessionIntent.swift
//  AMENWidgetExtension
//
//  Live Activity intent that ends the running Prayer Session from the
//  Dynamic Island "End" button (iOS 17+). Runs entirely in the widget
//  extension process — no app target membership needed.
//

import AppIntents
import ActivityKit

@available(iOS 17.0, *)
struct EndPrayerSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End Prayer Session"
    // Not surfaced in Siri / Shortcuts — internal Dynamic Island control only.
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        for activity in Activity<PrayerSessionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
