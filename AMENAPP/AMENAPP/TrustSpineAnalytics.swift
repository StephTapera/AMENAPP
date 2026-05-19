// TrustSpineAnalytics.swift
// AMENAPP
//
// Phase 6 — System 35 telemetry.
// Lightweight analytics surface for the Trust Spine + Spatial Social OS
// rebuild. Mirrors the pattern used by `AmenImmersiveMediaAnalytics`:
//   - A single `track(_:params:)` entrypoint
//   - Strongly-typed events so call sites stay self-documenting
//   - Gated by `AMENFeatureFlags.shared.analyticsEnabled` so a global kill
//     switch is always available
//
// These events stay local-side for now (dlog-only). The canonical
// `AMENAnalyticsService` already routes its core enum to Firebase Analytics
// + Firestore; adding 11 cases there mid-rebuild would be churn. When the
// rebuild graduates to GA, fold these into AMENAnalyticsEvent.

import Foundation

enum TrustSpineAnalyticsEvent: String {
    // Trust gate lifecycle
    case publishTrustGatePassed = "publish_trust_gate_passed"
    case publishTrustGateFailed = "publish_trust_gate_failed"

    // Trust UI surfaces
    case provenanceViewed       = "provenance_viewed"
    case aiDisclosureViewed     = "ai_disclosure_viewed"
    case discoveryWhyViewed     = "discovery_why_viewed"
    case safetyTrustLayerShown  = "safety_trust_layer_shown"

    // Composer + capture
    case postCreated            = "post_created"
    case aiAssistUsed           = "ai_assist_used"

    // Safety
    case reportSubmitted        = "report_submitted"

    // Spatial messages
    case sharedRoomCreated      = "shared_room_created"
    case sharedRoomJoined       = "shared_room_joined"
    case anchoredReplyPosted    = "anchored_reply_posted"
}

enum TrustSpineAnalytics {
    static func track(_ event: TrustSpineAnalyticsEvent, params: [String: Any] = [:]) {
        guard AMENFeatureFlags.shared.analyticsEnabled else { return }
        dlog("[TrustSpineAnalytics] \(event.rawValue)\(params.isEmpty ? "" : " \(params)")")
    }
}
