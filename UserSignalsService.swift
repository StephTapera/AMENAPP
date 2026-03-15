// UserSignalsService.swift
// AMENAPP
//
// Unified behavioral signal aggregation across all app surfaces.
// Combines signals from:
//   - BehavioralAwarenessEngine (session distress)
//   - WellnessGuardianService (usage patterns)
//   - HomeFeedAlgorithm (engagement interests)
//   - AI response interactions (confidence, helpfulness)
//   - Safety events (moderation triggers)
//
// Used by:
//   - BereanCoreService (request context enrichment)
//   - FeedIntelligenceEngine (ranking + addiction-risk)
//   - RecommendationIntelligenceService (personalization)
//   - PromptPolicyEngine (rate limiting, risk context)
//
// PRIVACY: All signals are in-memory only.
// Nothing here is transmitted to any backend without explicit user action.
// Signals are aggregated (not raw), and can be cleared at any time.

import Foundation
import Combine

// MARK: - Signal Types

struct UserEngagementSignal {
    let postId: String
    let type: EngagementType
    let surface: AMENSurface
    let timestamp: Date
    let durationMs: Int?     // dwell time for views

    enum EngagementType: String {
        case viewed, reacted, commented, shared, saved, skipped, reported
        case bereanChatOpened, bereanResponseHelpful, bereanResponseUnhelpful
        case safetyFlagShown, safetyFlagDismissed, safetyFlagActedOn
        case crisisResourceViewed, crisisResourceCalled
        case translationUsed, notesSaved, prayerSubmitted
    }
}

// MARK: - Aggregated User Profile (in-memory only)

struct AggregatedUserSignals {
    // Engagement
    var topEngagedTopics: [String: Double] = [:]    // topic → affinity 0-1.0
    var contentQualityPreference: Double = 0.5       // 0=low, 1=high quality
    var preferredSurfaces: [AMENSurface: Int] = [:]  // surface → session count

    // AI interactions
    var bereanHelpfulRate: Double = 0.5    // ratio of helpful/total rated responses
    var avgAIRequestsPerSession: Double = 0
    var preferredResponseLength: ResponseLength = .medium

    // Wellness
    var addictionRiskScore: Double = 0.0   // 0-1.0; derived from session behavior
    var lastCrisisSignalDate: Date?
    var wellnessBreaksTaken: Int = 0

    // Safety
    var safetyEventCount: Int = 0
    var recentSafetyEvents: [Date] = []

    // Session
    var currentSessionStartTime: Date?
    var sessionCount: Int = 0

    var isInActiveSession: Bool {
        guard let start = currentSessionStartTime else { return false }
        return Date().timeIntervalSince(start) < 3600
    }

    enum ResponseLength { case short, medium, long }
}

// MARK: - UserSignalsService

@MainActor
final class UserSignalsService: ObservableObject {

    static let shared = UserSignalsService()

    @Published private(set) var signals = AggregatedUserSignals()

    private var engagementBuffer: [UserEngagementSignal] = []
    private var aiEventBuffer: [AISignalEvent] = []
    private let maxBufferSize = 300
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Observe wellness service for session tracking
        setupWellnessObservation()
    }

    // MARK: - Recording

    func recordEngagement(_ signal: UserEngagementSignal) {
        engagementBuffer.append(signal)
        if engagementBuffer.count > maxBufferSize {
            engagementBuffer = Array(engagementBuffer.suffix(maxBufferSize))
        }
        updateAggregates(from: signal)
    }

    func record(_ event: AISignalEvent) {
        aiEventBuffer.append(event)
        if aiEventBuffer.count > maxBufferSize {
            aiEventBuffer = Array(aiEventBuffer.suffix(maxBufferSize))
        }
        updateAIAggregates(from: event)
    }

    func recordSafetyEvent(severity: SafetyFlagSeverity) {
        signals.safetyEventCount += 1
        signals.recentSafetyEvents.append(Date())
        // Keep only last 30 days
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        signals.recentSafetyEvents = signals.recentSafetyEvents.filter { $0 > cutoff }
    }

    func startSession() {
        signals.currentSessionStartTime = Date()
        signals.sessionCount += 1
    }

    func endSession() {
        signals.currentSessionStartTime = nil
    }

    // MARK: - Queries

    /// Current addiction-risk score for this user (drives content deprioritization)
    func addictionRisk(for userId: String?) async -> Bool {
        signals.addictionRiskScore > 0.65
    }

    /// Top topic interests (for recommendation personalization)
    func topTopics(limit: Int = 5) -> [(topic: String, affinity: Double)] {
        signals.topEngagedTopics
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (topic: $0.key, affinity: $0.value) }
    }

    /// Whether the user frequently interacts with Berean (suggests they value AI assistance)
    var isBereanPowerUser: Bool {
        let bereanEvents = aiEventBuffer.filter { $0.surface == .bereanChat }
        return bereanEvents.count >= 10
    }

    /// Personalization context string for injection into AI requests
    func contextString() -> String {
        let topTopicNames = topTopics(limit: 3).map(\.topic).joined(separator: ", ")
        var parts: [String] = []
        if !topTopicNames.isEmpty {
            parts.append("User's top interests: \(topTopicNames)")
        }
        if signals.addictionRiskScore > 0.50 {
            parts.append("User may benefit from lighter, encouraging content.")
        }
        if let lastCrisis = signals.lastCrisisSignalDate,
           Date().timeIntervalSince(lastCrisis) < 86400 {
            parts.append("User has recently engaged with emotionally heavy content. Respond with extra warmth.")
        }
        return parts.joined(separator: " ")
    }

    /// Clear all signals (called from privacy settings)
    func clearAllSignals() {
        signals = AggregatedUserSignals()
        engagementBuffer.removeAll()
        aiEventBuffer.removeAll()
    }

    // MARK: - Private Aggregation

    private func updateAggregates(from signal: UserEngagementSignal) {
        // Update surface preference
        signals.preferredSurfaces[signal.surface, default: 0] += 1

        // Addiction risk: rapid consecutive skips without engagement = boredom-scroll
        let recentSkips = engagementBuffer.suffix(20).filter { $0.type == .skipped }.count
        let recentViews = engagementBuffer.suffix(20).filter { $0.type == .viewed }.count
        if recentViews > 0 {
            let skipRatio = Double(recentSkips) / Double(recentViews)
            signals.addictionRiskScore = min(1.0, skipRatio * 0.7)
        }

        // Crisis signal recency
        if signal.type == .crisisResourceViewed || signal.type == .crisisResourceCalled {
            signals.lastCrisisSignalDate = signal.timestamp
        }

        // Safety events
        if signal.type == .safetyFlagActedOn {
            recordSafetyEvent(severity: .medium)
        }
    }

    private func updateAIAggregates(from event: AISignalEvent) {
        // Track Berean helpfulness
        if event.surface == .bereanChat {
            let ratedEvents = aiEventBuffer.filter { $0.surface == .bereanChat }
            let highConfidence = ratedEvents.filter { $0.confidence >= 0.75 }.count
            if !ratedEvents.isEmpty {
                signals.bereanHelpfulRate = Double(highConfidence) / Double(ratedEvents.count)
            }
        }

        // Track AI usage rate
        let sessionEvents = aiEventBuffer.filter {
            guard let start = signals.currentSessionStartTime else { return false }
            return $0.timestamp > start
        }
        signals.avgAIRequestsPerSession = Double(sessionEvents.count)
    }

    private func setupWellnessObservation() {
        WellnessGuardianService.shared.$shouldShowBreakReminder
            .sink { [weak self] showing in
                if showing { self?.signals.addictionRiskScore = min(1.0, (self?.signals.addictionRiskScore ?? 0) + 0.1) }
            }
            .store(in: &cancellables)
    }
}
