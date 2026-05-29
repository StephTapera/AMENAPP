#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation

/// Manages the Active Prayer Session Live Activity lifecycle.
/// Local-only — no push tokens, no Cloud Functions.
/// Superseded by AmenLiveActivityManager for richer multi-type support;
/// kept here for call-site compatibility.
@available(iOS 16.2, *)
@MainActor
final class PrayerSessionManager {
    static let shared = PrayerSessionManager()
    private init() {}

#if canImport(ActivityKit)
    private var activity: ActivityKit.Activity<PrayerSessionAttributes>?
#endif

    /// Starts a new Live Activity. No-ops if one is already running or Activities are disabled.
    func start(title: String) {
#if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else { return }

        let attributes = PrayerSessionAttributes(prayerTopic: title, groupName: "")
        let state = PrayerSessionAttributes.ContentState(
            prayerTitle: title,
            elapsedMinutes: 0,
            participantCount: 1,
            isChurchMode: false
        )
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            activity = try ActivityKit.Activity<PrayerSessionAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            // Silently ignored — simulator, dev device with Live Activities off, etc.
        }
#endif
    }

    /// Updates the currently displayed prayer topic / phase.
    func updateTopic(_ topic: String?) {
#if canImport(ActivityKit)
        guard let activity else { return }
        let state = PrayerSessionAttributes.ContentState(
            prayerTitle: topic ?? "",
            elapsedMinutes: 0,
            participantCount: 1,
            isChurchMode: false
        )
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await activity.update(content) }
#endif
    }

    /// Ends and immediately dismisses the Live Activity. Idempotent.
    func end() {
#if canImport(ActivityKit)
        guard let activity else { return }
        let captured = activity
        self.activity = nil
        Task { await captured.end(nil, dismissalPolicy: .immediate) }
#endif
    }
}
