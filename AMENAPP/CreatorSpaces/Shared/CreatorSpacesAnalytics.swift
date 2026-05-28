import Foundation
import FirebaseAnalytics

struct CreatorSpacesAnalytics {
    static func track(_ event: Event, parameters: [String: Any] = [:]) {
        guard AMENFeatureFlags.shared.analyticsEnabled else { return }
        Analytics.logEvent(event.rawValue, parameters: parameters.isEmpty ? nil : parameters)
    }

    enum Event: String {
        case creatorSpaceCreated = "creator_space_created"
        case presencePostCreated = "presence_post_created"
        case dualCameraCaptureUsed = "dual_camera_capture_used"
        case smartClipGenerated = "smart_clip_generated"
        case collectiveMemoryCreated = "collective_memory_created"
        case authenticityBadgeViewed = "authenticity_badge_viewed"
        case creatorSubscriptionStarted = "creator_subscription_started"
        case eventMemoryShared = "event_memory_shared"
        case studyClipShared = "study_clip_shared"
        case creatorSpaceJoined = "creator_space_joined"
    }
}
