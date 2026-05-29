import AppIntents
import ActivityKit

/// App Intent that ends the running Prayer Session Live Activity without opening the app.
/// Add this file to BOTH the AMENAPP target and AmenLiveActivities target in Xcode.
@available(iOS 16.2, *)
struct EndPrayerSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "End Prayer Session"
    static let description = IntentDescription("Ends your active prayer session and dismisses the Live Activity.")

    /// Runs in the app extension process — finds and ends all running prayer activities.
    func perform() async throws -> some IntentResult {
        if #available(iOS 16.2, *) {
            for activity in ActivityKit.Activity<PrayerSessionAttributes>.activities {
                await activity.end(dismissalPolicy: ActivityUIDismissalPolicy.immediate)
            }
        }
        return .result()
    }
}
