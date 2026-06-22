import Foundation
import FirebaseAnalytics

// Phase-5: Communities / Threads-style Feeds analytics.
//
// Centralized event helper so the call sites (HomeView, composer, saved
// service, scope switcher) all emit consistent event names and safe payload
// shapes. Strict denylist: never log raw post text, never log private
// message text, never log email/phone/tokens/payment secrets.

enum CommunitiesAnalytics {

    // Whitelist of payload keys ever emitted by this helper. Anything not
    // on this list is unsafe and must not be added without review.
    private static let allowedKeys: Set<String> = [
        "feed_mode",
        "feed_scope_type",
        "feed_scope_id_hashed",      // ALWAYS hashed if we ever attach an id
        "community_type",
        "community_id_hashed",       // ALWAYS hashed if we ever attach an id
        "saved",
        "tone_severity",
        "tone_categories_count",
        "result",
        "kind",
        "page",
        "count",
    ]

    private static func sanitize(_ params: [String: Any]) -> [String: Any] {
        var safe: [String: Any] = [:]
        for (k, v) in params where allowedKeys.contains(k) {
            // Coerce to Firebase-supported scalar types only.
            switch v {
            case let s as String: safe[k] = s
            case let n as NSNumber: safe[k] = n
            case let b as Bool: safe[k] = b ? "true" : "false"
            case let i as Int: safe[k] = i
            case let d as Double: safe[k] = d
            default: continue
            }
        }
        return safe
    }

    private static func emit(_ name: String, _ params: [String: Any] = [:]) {
        Analytics.logEvent(name, parameters: sanitize(params))
    }

    // ── Surface entry / selection ────────────────────────────────────────────

    static func feedsPanelOpened() {
        emit("feeds_panel_opened")
    }

    static func feedSelected(mode: String) {
        emit("feed_selected", ["feed_mode": mode])
    }

    static func communityViewed(type: String) {
        emit("community_viewed", ["community_type": type])
    }

    static func communityViewInFeedSelected(type: String) {
        emit("community_view_in_feed_selected", ["community_type": type])
    }

    // ── Save / unsave ────────────────────────────────────────────────────────

    static func communitySaved(type: String) {
        emit("community_saved", ["community_type": type])
    }

    static func communityUnsaved(type: String) {
        emit("community_unsaved", ["community_type": type])
    }

    // ── Scoped feed lifecycle ────────────────────────────────────────────────

    static func communityFeedLoaded(scopeType: String, count: Int, page: Int) {
        emit("community_feed_loaded", [
            "feed_scope_type": scopeType,
            "count": count,
            "page": page,
        ])
    }

    static func communityFeedFailed(scopeType: String) {
        emit("community_feed_failed", ["feed_scope_type": scopeType])
    }

    static func communityFeedPaginated(scopeType: String, page: Int) {
        emit("community_feed_paginated", [
            "feed_scope_type": scopeType,
            "page": page,
        ])
    }

    // ── Tone check ───────────────────────────────────────────────────────────

    static func toneCheckStarted(kind: String) {
        emit("community_tone_check_started", ["kind": kind])
    }

    static func toneCheckSucceeded(kind: String, severity: String, categoriesCount: Int) {
        emit("community_tone_check_succeeded", [
            "kind": kind,
            "tone_severity": severity,
            "tone_categories_count": categoriesCount,
            "result": "allowed",
        ])
    }

    static func toneCheckBlocked(kind: String, categoriesCount: Int) {
        emit("community_tone_check_blocked", [
            "kind": kind,
            "tone_categories_count": categoriesCount,
            "result": "blocked",
        ])
    }

    static func toneCheckFailed(kind: String) {
        emit("community_tone_check_failed", [
            "kind": kind,
            "result": "error",
        ])
    }
}
