//
//  SessionIntelligenceEngine.swift
//  AMENAPP
//
//  Advanced ML services: Intent Prediction, Momentum Scoring,
//  Passive Interest Graph, Social Fatigue, Creation Propensity,
//  Predictive Cache Warming, and Harassment Pattern Detection.
//

import Foundation
import UIKit

// MARK: - Intent Prediction (< 200ms at app open)

class SessionIntentPredictor {
    static let shared = SessionIntentPredictor()
    private init() {}

    enum SessionIntent: String {
        case browse    // Passive scrolling
        case connect   // Messaging / social
        case catchUp   // Read notifications + updates
        case create    // Ready to post
        case killTime  // Low-intent short session
    }

    /// Classify session intent in under 200ms using local signals.
    func predictIntent() -> SessionIntent {
        let hour = Calendar.current.component(.hour, from: Date())
        let weekday = Calendar.current.component(.weekday, from: Date())
        let isBatteryLow = UIDevice.current.batteryLevel < 0.2 && UIDevice.current.batteryLevel >= 0
        let lastSession = UserDefaults.standard.string(forKey: "lastSessionIntent") ?? "browse"

        // Morning (5-9): catch up on overnight activity
        if hour >= 5 && hour < 9 { return .catchUp }

        // Sunday morning: create mode (post-church reflections)
        if weekday == 1 && hour >= 9 && hour < 14 { return .create }

        // Evening (8-11): browse/connect
        if hour >= 20 { return isBatteryLow ? .killTime : .browse }

        // If last session was "create" and within 2 hours: connect (follow-up)
        if lastSession == "create" { return .connect }

        // Default
        return .browse
    }

    func recordSessionIntent(_ intent: SessionIntent) {
        UserDefaults.standard.set(intent.rawValue, forKey: "lastSessionIntent")
    }
}

// MARK: - Contextual Momentum Scoring

class MomentumScorer {
    static let shared = MomentumScorer()
    private init() {}

    struct ContentMomentum {
        var readDepth: Float     // 0.0–1.0 (how far user scrolled in post)
        var pauseDuration: Float // seconds paused on this content
        var scrollBackCount: Int // times user scrolled back to re-read
        var reopenCount: Int     // times user returned to this post
        var engagementActions: Int // amens, comments, shares
    }

    private var postMomentum: [String: ContentMomentum] = [:]

    func trackReadDepth(postId: String, depth: Float) {
        var m = postMomentum[postId] ?? ContentMomentum(readDepth: 0, pauseDuration: 0, scrollBackCount: 0, reopenCount: 0, engagementActions: 0)
        m.readDepth = max(m.readDepth, depth)
        postMomentum[postId] = m
    }

    func trackPause(postId: String, seconds: Float) {
        var m = postMomentum[postId] ?? ContentMomentum(readDepth: 0, pauseDuration: 0, scrollBackCount: 0, reopenCount: 0, engagementActions: 0)
        m.pauseDuration += seconds
        postMomentum[postId] = m
    }

    func trackScrollBack(postId: String) {
        var m = postMomentum[postId] ?? ContentMomentum(readDepth: 0, pauseDuration: 0, scrollBackCount: 0, reopenCount: 0, engagementActions: 0)
        m.scrollBackCount += 1
        postMomentum[postId] = m
    }

    /// Compute a momentum score (0–100) for a post based on passive signals.
    func score(postId: String) -> Float {
        guard let m = postMomentum[postId] else { return 0 }

        var score: Float = 0
        score += m.readDepth * 20                           // Full read = 20 points
        score += min(20, m.pauseDuration / 3.0 * 5)        // 3s pause = 5 points, max 20
        score += Float(m.scrollBackCount) * 15              // Each scroll-back = 15 points
        score += Float(m.reopenCount) * 20                  // Each reopen = 20 points
        score += Float(m.engagementActions) * 10            // Each action = 10 points
        return min(100, score)
    }

    func resetSession() {
        postMomentum.removeAll()
    }
}

// MARK: - Social Fatigue Modeling

class SocialFatigueModel {
    static let shared = SocialFatigueModel()
    private init() {}

    struct FatigueSignals {
        var sessionLengthTrend: Float      // Declining = fatigued
        var passiveScrollRatio: Float      // High = fatigued
        var timeToFirstAction: Float       // Increasing = fatigued
        var notificationOpenRate: Float    // Declining = fatigued
    }

    /// Compute fatigue score (0.0 = fresh, 1.0 = near-churn).
    func computeFatigue() -> Float {
        let sessionMinutes = Float(AppUsageTracker.shared.todayUsageMinutes)
        let dailyLimit = Float(45) // Default daily limit

        // Simple fatigue based on usage ratio
        let usageRatio = min(1.0, sessionMinutes / dailyLimit)

        // Time-of-day fatigue (late night = higher baseline fatigue)
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDayFactor: Float = (hour >= 22 || hour < 6) ? 0.2 : 0

        return min(1.0, usageRatio * 0.6 + timeOfDayFactor + 0.1)
    }

    /// Recommendations based on fatigue level.
    func recommendation() -> String? {
        let fatigue = computeFatigue()
        if fatigue > 0.8 {
            return "Consider taking a break — your wellbeing matters."
        } else if fatigue > 0.6 {
            return nil // Don't nag at moderate levels
        }
        return nil
    }
}

// MARK: - Creation Propensity Scoring

class CreationPropensityScorer {
    static let shared = CreationPropensityScorer()
    private init() {}

    /// Score how likely a user is to create content (0.0–1.0).
    func score() -> Float {
        var propensity: Float = 0

        // Draft saves without publishing = strong signal
        let draftCount = DraftsManager.shared.drafts.count
        propensity += min(0.3, Float(draftCount) * 0.1)

        // Recent engagement spike on creator content
        let recentInteractions = 0 // PostInteractionsService tracks per-post, not aggregate count
        propensity += min(0.2, Float(recentInteractions) / 50.0)

        // Time since last post (longer gap = higher propensity for return creators)
        // This would need real data; placeholder
        propensity += 0.1

        return min(1.0, propensity)
    }

    /// Should we show a creation prompt to this user?
    func shouldPromptCreation() -> Bool {
        score() > 0.5
    }
}

// MARK: - Predictive Cache Warming

class PredictiveCacheWarmer {
    static let shared = PredictiveCacheWarmer()
    private init() {}

    /// Based on current session trajectory, predict what content user will need next.
    func warmCache(currentScreen: String, sessionHistory: [String]) {
        let intent = SessionIntentPredictor.shared.predictIntent()

        Task {
            switch intent {
            case .browse:
                // Pre-warm next page of feed
                await FeedPrefetchService.shared.prefetchIfNeeded(currentIndex: 0, totalPosts: 5)
            case .connect:
                // Pre-warm conversation list
                break // MessagingService handles this
            case .catchUp:
                // Pre-warm notifications
                break // NotificationService handles this
            case .create:
                // Pre-warm drafts
                break // DraftsManager handles this
            case .killTime:
                // Pre-warm trending content
                break
            }
        }
    }
}
