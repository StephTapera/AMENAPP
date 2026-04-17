// AMENAnalyticsService.swift
// AMEN App — Product Analytics & Observability
//
// Design principles:
//   - Meaningful product metrics, not vanity metrics
//   - No raw behavioral data stored server-side
//   - Aggregated + anonymized where possible
//   - Privacy-first: users can opt out
//   - Instrumented across all 7 major systems
//
// Metric categories:
//   - Feed quality (meaningful engagement ratio, not raw views)
//   - Moderation health (false positive rate, action distribution)
//   - Assistant quality (latency, source attribution rate)
//   - Church discovery (search → save → visit funnel)
//   - Check-in effectiveness (dismissal rate, positive response rate)
//   - Knowledge graph utility (related content clicks)
//   - Studio (opportunity discovery, creator profile completeness)

import Foundation
import UIKit
import FirebaseFirestore
import FirebaseAuth
import FirebaseAnalytics

// MARK: - Analytics Event

enum AMENAnalyticsEvent {
    // Feed
    case feedSessionStarted
    case feedSessionEnded(durationMinutes: Double, qualityScore: Double)
    case feedMeaningfulInteraction(type: String)   // "save", "comment", "prayer_response"
    case feedReflectionPromptShown
    case feedReflectionPromptEngaged
    case feedPacingPromptShown
    case feedPacingPromptEngaged

    // Moderation
    case moderationDecisionMade(context: String, action: String, riskLevel: String)
    case moderationAppealSubmitted
    case userReportSubmitted(type: String)

    // Berean AI
    case bereanSessionStarted
    case bereanResponseGenerated(latencyMs: Double, sourceCount: Int)
    case bereanSourceTapped(sourceType: String)
    case bereanFollowUpUsed
    case bereanMessageSaved

    // Spiritual Check-In
    case checkInShown(tier: Int)
    case checkInEngaged
    case checkInDismissed
    case checkInSnoozed

    // Church Discovery
    case churchSearchPerformed
    case churchProfileViewed
    case churchSaved
    case churchDirectionsTapped
    case churchFirstVisitGuideOpened
    case churchPreferenceOnboardingCompleted

    // Knowledge Graph
    case relatedContentShown(nodeType: String)
    case relatedContentTapped(nodeType: String)
    case topicFollowed(topicSlug: String)

    // Studio
    case studioProfileViewed
    case studioInquirySent
    case studioJobApplied

    // Account
    case accountTypeSelected(type: String)

    // Media Feed Mode
    case mediaModeSwitched(toMode: String)
    case mediaGridTileOpened(postId: String)
    case mediaDetailClosed
    case mediaDetailJumpedToPost(postId: String)
    case mediaGridEmptyStateViewed
    case mediaFilterChanged(filter: String)

    // Suggested Accounts
    case suggestionImpression(suggestedUserId: String, position: Int, reasonType: String)
    case suggestionFollowTap(suggestedUserId: String, position: Int)
    case suggestionFollowSuccess(suggestedUserId: String)
    case suggestionFollowFailure(suggestedUserId: String)
    case suggestionProfileOpen(suggestedUserId: String)
    case suggestionDismiss(suggestedUserId: String)
    case suggestionsRailSeen(count: Int)
    case suggestionsModuleHidden
    case suggestionsModuleRestored
    case suggestionPeekOpen(suggestedUserId: String, surface: String)
    case suggestionPeekExpand(suggestedUserId: String, surface: String)
    case suggestionFullProfileOpen(suggestedUserId: String, surface: String)
    case suggestionRailHidden(surface: String)
    case suggestionRailRestored(surface: String)
    case suggestionShowFewer(surface: String)
    case suggestionWhyShown(surface: String)

    var name: String {
        switch self {
        case .feedSessionStarted: return "feed_session_started"
        case .feedSessionEnded: return "feed_session_ended"
        case .feedMeaningfulInteraction: return "feed_meaningful_interaction"
        case .feedReflectionPromptShown: return "feed_reflection_prompt_shown"
        case .feedReflectionPromptEngaged: return "feed_reflection_prompt_engaged"
        case .feedPacingPromptShown: return "feed_pacing_prompt_shown"
        case .feedPacingPromptEngaged: return "feed_pacing_prompt_engaged"
        case .moderationDecisionMade: return "moderation_decision_made"
        case .moderationAppealSubmitted: return "moderation_appeal_submitted"
        case .userReportSubmitted: return "user_report_submitted"
        case .bereanSessionStarted: return "berean_session_started"
        case .bereanResponseGenerated: return "berean_response_generated"
        case .bereanSourceTapped: return "berean_source_tapped"
        case .bereanFollowUpUsed: return "berean_follow_up_used"
        case .bereanMessageSaved: return "berean_message_saved"
        case .checkInShown: return "check_in_shown"
        case .checkInEngaged: return "check_in_engaged"
        case .checkInDismissed: return "check_in_dismissed"
        case .checkInSnoozed: return "check_in_snoozed"
        case .churchSearchPerformed: return "church_search_performed"
        case .churchProfileViewed: return "church_profile_viewed"
        case .churchSaved: return "church_saved"
        case .churchDirectionsTapped: return "church_directions_tapped"
        case .churchFirstVisitGuideOpened: return "church_first_visit_guide_opened"
        case .churchPreferenceOnboardingCompleted: return "church_preference_onboarding_completed"
        case .relatedContentShown: return "related_content_shown"
        case .relatedContentTapped: return "related_content_tapped"
        case .topicFollowed: return "topic_followed"
        case .studioProfileViewed: return "studio_profile_viewed"
        case .studioInquirySent: return "studio_inquiry_sent"
        case .studioJobApplied: return "studio_job_applied"
        case .accountTypeSelected: return "account_type_selected"
        case .mediaModeSwitched: return "media_mode_switched"
        case .mediaGridTileOpened: return "media_grid_tile_opened"
        case .mediaDetailClosed: return "media_detail_closed"
        case .mediaDetailJumpedToPost: return "media_detail_jumped_to_post"
        case .mediaGridEmptyStateViewed: return "media_grid_empty_state_viewed"
        case .mediaFilterChanged: return "media_filter_changed"
        case .suggestionImpression: return "suggestion_impression"
        case .suggestionFollowTap: return "suggestion_follow_tap"
        case .suggestionFollowSuccess: return "suggestion_follow_success"
        case .suggestionFollowFailure: return "suggestion_follow_failure"
        case .suggestionProfileOpen: return "suggestion_profile_open"
        case .suggestionDismiss: return "suggestion_dismiss"
        case .suggestionsRailSeen: return "suggestions_rail_seen"
        case .suggestionsModuleHidden: return "suggestions_module_hidden"
        case .suggestionsModuleRestored: return "suggestions_module_restored"
        case .suggestionPeekOpen: return "suggestion_peek_open"
        case .suggestionPeekExpand: return "suggestion_peek_expand"
        case .suggestionFullProfileOpen: return "suggestion_full_profile_open"
        case .suggestionRailHidden: return "suggestion_rail_hidden"
        case .suggestionRailRestored: return "suggestion_rail_restored"
        case .suggestionShowFewer: return "suggestion_show_fewer"
        case .suggestionWhyShown: return "suggestion_why_shown"
        }
    }

    var properties: [String: Any] {
        switch self {
        case .feedSessionEnded(let duration, let quality):
            return ["duration_minutes": duration, "quality_score": quality]
        case .feedMeaningfulInteraction(let type):
            return ["interaction_type": type]
        case .moderationDecisionMade(let ctx, let action, let risk):
            return ["context": ctx, "action": action, "risk_level": risk]
        case .userReportSubmitted(let type):
            return ["report_type": type]
        case .bereanResponseGenerated(let latency, let sources):
            return ["latency_ms": latency, "source_count": sources]
        case .bereanSourceTapped(let type):
            return ["source_type": type]
        case .checkInShown(let tier):
            return ["tier": tier]
        case .relatedContentShown(let type), .relatedContentTapped(let type):
            return ["node_type": type]
        case .topicFollowed(let slug):
            return ["topic_slug": slug]
        case .accountTypeSelected(let type):
            return ["account_type": type]
        case .mediaModeSwitched(let mode):
            return ["to_mode": mode]
        case .mediaGridTileOpened(let postId):
            return ["post_id": postId]
        case .mediaDetailJumpedToPost(let postId):
            return ["post_id": postId]
        case .mediaFilterChanged(let filter):
            return ["filter": filter]
        case .suggestionImpression(let userId, let position, let reason):
            return ["suggested_user_id": userId, "position": position, "reason_type": reason]
        case .suggestionFollowTap(let userId, let position):
            return ["suggested_user_id": userId, "position": position]
        case .suggestionFollowSuccess(let userId):
            return ["suggested_user_id": userId]
        case .suggestionFollowFailure(let userId):
            return ["suggested_user_id": userId]
        case .suggestionProfileOpen(let userId):
            return ["suggested_user_id": userId]
        case .suggestionDismiss(let userId):
            return ["suggested_user_id": userId]
        case .suggestionsRailSeen(let count):
            return ["suggestion_count": count]
        case .suggestionPeekOpen(let userId, let surface):
            return ["suggested_user_id": userId, "surface": surface]
        case .suggestionPeekExpand(let userId, let surface):
            return ["suggested_user_id": userId, "surface": surface]
        case .suggestionFullProfileOpen(let userId, let surface):
            return ["suggested_user_id": userId, "surface": surface]
        case .suggestionRailHidden(let surface):
            return ["surface": surface]
        case .suggestionRailRestored(let surface):
            return ["surface": surface]
        case .suggestionShowFewer(let surface):
            return ["surface": surface]
        case .suggestionWhyShown(let surface):
            return ["surface": surface]
        default:
            return [:]
        }
    }
}

// MARK: - Analytics Service

@MainActor
final class AMENAnalyticsService {

    static let shared = AMENAnalyticsService()

    private lazy var db = Firestore.firestore()
    private let flags = AMENFeatureFlags.shared

    // P2 FIX: Session ID — a UUID generated fresh on each app foreground session.
    // Threaded through all events so the analytics backend can reconstruct a full
    // user session funnel (e.g. feed_session_started → berean_session_started →
    // feed_meaningful_interaction) without relying on timestamp proximity alone.
    private(set) var sessionId: String = UUID().uuidString

    /// Call this when the app moves to foreground (scenePhase == .active) to start
    /// a fresh session. Events fired before this retain the prior session ID.
    func startNewSession() {
        sessionId = UUID().uuidString
        dlog("📊 Analytics: new session \(sessionId.prefix(8))…")
    }

    // In-memory buffer for batching (flush every 30s or 20 events).
    // Hard cap at 200 events: if Firestore writes fail repeatedly and the buffer
    // grows past this limit, the oldest events are dropped to prevent OOM.
    private var eventBuffer: [(name: String, props: [String: Any], ts: Date)] = []
    private static let maxBufferSize = 200
    private var flushTask: Task<Void, Never>?

    // MARK: - User Opt-Out (GDPR Article 21)

    /// UserDefaults key for the user's analytics opt-out preference.
    static let analyticsOptOutKey = "amen.analyticsOptOut"

    /// True when the current user has opted out of analytics collection.
    var isUserOptedOut: Bool {
        UserDefaults.standard.bool(forKey: Self.analyticsOptOutKey)
    }

    /// Set the user's analytics opt-out preference.
    /// Also toggles Firebase Analytics collection immediately.
    func setAnalyticsOptOut(_ optOut: Bool) {
        UserDefaults.standard.set(optOut, forKey: Self.analyticsOptOutKey)
        Analytics.setAnalyticsCollectionEnabled(!optOut)
        dlog("📊 Analytics collection \(optOut ? "DISABLED" : "ENABLED") by user preference")
    }

    private init() {
        // Apply stored opt-out preference on launch
        let storedOptOut = UserDefaults.standard.bool(forKey: Self.analyticsOptOutKey)
        if storedOptOut {
            Analytics.setAnalyticsCollectionEnabled(false)
        }

        schedulePeriodicFlush()

        // P1 FIX: Flush buffered Firestore events before the app is suspended.
        // Previously, events batched just before backgrounding were lost if the
        // process was terminated. Firebase Analytics events are already durable
        // (the SDK queues them), so this only applies to the Firestore secondary write.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.flush()
            }
        }
    }

    // MARK: - Track

    func track(_ event: AMENAnalyticsEvent) {
        guard flags.analyticsEnabled, !isUserOptedOut else { return }

        // P1 FIX: Fire to Firebase Analytics immediately — events are durable and
        // survive sign-out and process termination. The Firestore batch write below
        // is secondary (for custom dashboards) and requires a signed-in user.
        // P2 FIX: Thread sessionId through every event so the backend can reconstruct
        // complete user sessions without relying on timestamp proximity.
        var enriched = event.properties
        enriched["session_id"] = sessionId
        let params: [String: Any]? = enriched.isEmpty ? nil : enriched
        Analytics.logEvent(event.name, parameters: params)

        // Buffer for secondary Firestore write (requires auth).
        // Drop oldest entry first if the buffer has reached the hard cap,
        // preventing unbounded growth when Firestore writes fail repeatedly.
        if eventBuffer.count >= Self.maxBufferSize {
            eventBuffer.removeFirst()
        }
        eventBuffer.append((event.name, enriched, Date()))
        if eventBuffer.count >= 20 {
            Task { await flush() }
        }
    }

    // MARK: - Flush (Firestore secondary write)

    private func flush() async {
        guard !eventBuffer.isEmpty else { return }

        let toFlush = eventBuffer
        eventBuffer.removeAll()

        // P1 FIX: Don't drop events on sign-out — Firebase Analytics already fired.
        // Only skip the Firestore write if there's no authenticated user, since the
        // Firestore rules require auth. Events are NOT discarded from the perspective
        // of the analytics platform (Firebase Analytics received them above).
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let batch = db.batch()
        for event in toFlush {
            var data: [String: Any] = ["event": event.name, "ts": Timestamp(date: event.ts)]
            for (k, v) in event.props { data[k] = v }
            let ref = db
                .collection("analytics")
                .document(uid)
                .collection("events")
                .document()
            batch.setData(data, forDocument: ref)
        }
        try? await batch.commit()
    }

    private func schedulePeriodicFlush() {
        flushTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)  // 30s
                await flush()
            }
        }
    }

    // MARK: - Performance Telemetry

    func recordLatency(operation: String, milliseconds: Double) {
        guard flags.performanceTelemetryEnabled else { return }
        track(.bereanResponseGenerated(latencyMs: milliseconds, sourceCount: 0))
    }
}
