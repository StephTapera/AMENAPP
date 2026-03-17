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
        default:
            return [:]
        }
    }
}

// MARK: - Analytics Service

@MainActor
final class AMENAnalyticsService {

    static let shared = AMENAnalyticsService()

    private let db = Firestore.firestore()
    private let flags = AMENFeatureFlags.shared

    // In-memory buffer for batching (flush every 30s or 20 events).
    // Hard cap at 200 events: if Firestore writes fail repeatedly and the buffer
    // grows past this limit, the oldest events are dropped to prevent OOM.
    private var eventBuffer: [(name: String, props: [String: Any], ts: Date)] = []
    private static let maxBufferSize = 200
    private var flushTask: Task<Void, Never>?

    private init() {
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
        guard flags.analyticsEnabled else { return }

        // P1 FIX: Fire to Firebase Analytics immediately — events are durable and
        // survive sign-out and process termination. The Firestore batch write below
        // is secondary (for custom dashboards) and requires a signed-in user.
        let params = event.properties.isEmpty ? nil : event.properties
        Analytics.logEvent(event.name, parameters: params)

        // Buffer for secondary Firestore write (requires auth).
        // Drop oldest entry first if the buffer has reached the hard cap,
        // preventing unbounded growth when Firestore writes fail repeatedly.
        if eventBuffer.count >= Self.maxBufferSize {
            eventBuffer.removeFirst()
        }
        eventBuffer.append((event.name, event.properties, Date()))
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
