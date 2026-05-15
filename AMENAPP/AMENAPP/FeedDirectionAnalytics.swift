import Foundation
import FirebaseAnalytics

struct FeedDirectionAnalytics {
    static func chipShown(confidence: Double) {
        Analytics.logEvent("feed_direction_chip_shown", parameters: ["confidence": confidence])
    }
    static func chipTapped(category: String) {
        Analytics.logEvent("feed_direction_chip_tapped", parameters: ["category": category])
    }
    static func sheetOpened(source: String) {
        Analytics.logEvent("guide_my_feed_sheet_opened", parameters: ["source": source])
    }
    static func submitted(intentType: String, duration: String, intensity: String, surfaces: [String]) {
        Analytics.logEvent("guide_my_feed_submitted", parameters: [
            "intent_type": intentType, "duration": duration,
            "intensity": intensity, "surfaces": surfaces.joined(separator: ",")
        ])
    }
    static func cancelled() {
        Analytics.logEvent("guide_my_feed_cancelled", parameters: nil)
    }
    static func applySuccess(signalId: String, intentType: String) {
        Analytics.logEvent("feed_direction_apply_success", parameters: ["signal_id": signalId, "intent_type": intentType])
    }
    static func applyFailed(reason: String) {
        Analytics.logEvent("feed_direction_apply_failed", parameters: ["reason": reason])
    }
    static func whyThisPostOpened(postId: String) {
        Analytics.logEvent("why_this_post_opened", parameters: ["post_id": postId])
    }
    static func adjustmentTapped(action: String, postId: String) {
        Analytics.logEvent("why_this_post_adjustment_tapped", parameters: ["action": action, "post_id": postId])
    }
    static func feedReset(scope: String) {
        Analytics.logEvent("feed_intelligence_reset", parameters: ["scope": scope])
    }
    static func modeActivated(mode: String) {
        Analytics.logEvent("feed_mode_activated", parameters: ["mode": mode])
    }
    static func undoTapped(signalId: String) {
        Analytics.logEvent("feed_direction_undo_tapped", parameters: ["signal_id": signalId])
    }
}
