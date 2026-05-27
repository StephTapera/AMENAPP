// BereanCarPlayAnalytics.swift
// AMEN — Berean Drive CarPlay
//
// Privacy-safe analytics for CarPlay sessions.
// Follows the ChurchNotesAnalyticsEvent pattern in AMENAnalyticsService.
//
// Privacy rules enforced here:
//   - NEVER log full prayer text
//   - NEVER log message content
//   - NEVER log spiritual query text
//   - NEVER log raw location (no lat/lon)
//   - No engagement metrics, social ranking, or session comparison
//   - commandType labels only (e.g. "ask_berean") — never query text

import Foundation
import FirebaseAnalytics

// MARK: - CarPlay Event Names

enum BereanCarPlayAnalyticsEvent: String {
    case sessionStarted             = "carplay_session_started"
    case sessionEnded               = "carplay_session_ended"
    case modeSelected               = "carplay_mode_selected"
    case prayerStarted              = "carplay_prayer_started"
    case bereanVoiceQuery           = "carplay_berean_voice_query"
    case churchNavigationStarted    = "carplay_church_navigation_started"
    case messageReplySent           = "carplay_message_reply_sent"
    case safetyBlockTriggered       = "carplay_safety_block_triggered"
    case handoffToPhone             = "carplay_handoff_to_phone"
    case handoffFromPhone           = "carplay_handoff_from_phone"
    case featureFlagBlocked         = "carplay_feature_flag_blocked"
}

// MARK: - AMENAnalyticsService CarPlay Extension

extension AMENAnalyticsService {

    /// Log a Berean CarPlay event with strictly bounded, non-sensitive parameters.
    ///
    /// Privacy contract — callers MUST pass mode labels, category strings, boolean
    /// flags, and reason strings. They MUST NOT pass:
    /// prayer text, message content, spiritual query text, scripture content,
    /// user emails, raw location coordinates, or full query strings.
    @MainActor
    func logCarPlay(_ event: BereanCarPlayAnalyticsEvent, parameters: [String: Any] = [:]) {
        guard AMENFeatureFlags.shared.analyticsEnabled, !isUserOptedOut else { return }
        guard AMENFeatureFlags.shared.carPlayBereanEnabled else { return }

        var safeParams: [String: Any] = [:]
        for (k, v) in parameters {
            switch v {
            case is String, is Int, is Double, is Bool, is NSNumber:
                safeParams[k] = v
            default:
                continue
            }
        }
        safeParams["session_id"] = sessionId

        Analytics.logEvent(event.rawValue, parameters: safeParams.isEmpty ? nil : safeParams)
        dlog("📊 CarPlay analytics: \(event.rawValue) keys=\(safeParams.keys.sorted())")
    }
}

// MARK: - BereanCarPlayAnalytics Facade

/// Convenience facade — wraps AMENAnalyticsService.logCarPlay with typed helpers.
@MainActor
final class BereanCarPlayAnalytics {

    static let shared = BereanCarPlayAnalytics()
    private init() {}

    private let service = AMENAnalyticsService.shared

    func track(_ event: BereanCarPlayAnalyticsEvent, parameters: [String: Any] = [:]) {
        service.logCarPlay(event, parameters: parameters)
    }

    // MARK: - Typed Helpers

    func track(_ event: Event) {
        let (analyticsEvent, params) = resolve(event)
        track(analyticsEvent, parameters: params)
    }

    enum Event {
        case sessionStarted
        case sessionEnded
        case modeSelected(mode: String)
        case prayerStarted(mode: String)
        case bereanVoiceQuery(commandType: String)    // type label only, never query text
        case churchNavigationStarted
        case messageReplySent
        case safetyBlockTriggered(category: String)
        case handoffToPhone(reason: String)
        case handoffFromPhone(surface: String)
        case featureFlagBlocked(feature: String)
    }

    private func resolve(_ event: Event) -> (BereanCarPlayAnalyticsEvent, [String: Any]) {
        switch event {
        case .sessionStarted:
            return (.sessionStarted, [:])
        case .sessionEnded:
            return (.sessionEnded, [:])
        case .modeSelected(let mode):
            return (.modeSelected, ["mode": mode])
        case .prayerStarted(let mode):
            return (.prayerStarted, ["prayer_mode": mode])
        case .bereanVoiceQuery(let commandType):
            return (.bereanVoiceQuery, ["command_type": commandType])
        case .churchNavigationStarted:
            return (.churchNavigationStarted, [:])
        case .messageReplySent:
            return (.messageReplySent, [:])
        case .safetyBlockTriggered(let category):
            return (.safetyBlockTriggered, ["category": category])
        case .handoffToPhone(let reason):
            return (.handoffToPhone, ["reason": reason])
        case .handoffFromPhone(let surface):
            return (.handoffFromPhone, ["surface": surface])
        case .featureFlagBlocked(let feature):
            return (.featureFlagBlocked, ["feature": feature])
        }
    }
}
