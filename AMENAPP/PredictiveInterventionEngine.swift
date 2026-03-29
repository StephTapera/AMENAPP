//
//  PredictiveInterventionEngine.swift
//  AMENAPP
//
//  Predictive Intervention Engine — don't wait for the user, anticipate behavior.
//
//  Monitors behavioral signals across the app and generates preemptive prompts
//  when patterns suggest temptation risk, isolation, or discipline breakdown.
//
//  Privacy guarantees:
//    - All signal processing is in-memory only
//    - No raw content is stored or analyzed — only behavioral metadata
//    - Interventions are optional and dismissible
//    - User can disable predictive interventions at any time
//    - Signal data is never sent to any server
//
//  Architecture:
//    PredictiveInterventionEngine (singleton, @MainActor)
//    ├── BehavioralSignal           (raw app behavior events)
//    ├── InterventionCandidate      (generated intervention to surface)
//    ├── ingestSignal()             (process a new behavioral event)
//    ├── evaluateInterventions()    (check if any intervention should fire)
//    └── interventionForContext()   (get the best intervention for current state)
//

import Foundation
import Combine

// MARK: - Behavioral Signal

/// A behavioral event observed from app usage (never content).
struct BehavioralSignal {
    let type: SignalType
    let timestamp: Date
    let metadata: [String: String]

    enum SignalType: String {
        // Usage patterns
        case lateNightUsage           // App used after 11 PM
        case prolongedScrolling       // Extended feed scrolling (>10 min)
        case rapidAppSwitching        // Opening/closing app repeatedly
        case extendedSession          // Single session > 30 minutes

        // Engagement gaps
        case noChurchFeatureUse       // No church notes/find church in 14+ days
        case noPrayerActivity         // No prayer posts in 7+ days
        case noScriptureEngagement    // No Berean/scripture interaction in 7+ days
        case noCommunityInteraction   // No posts/comments/messages in 7+ days

        // Content signals (metadata-only, not content)
        case repeatedUnfinishedPrompts // Started typing in Berean 3+ times without sending
        case deletedDraft             // Deleted a post/prayer draft
        case searchedSensitiveTopic   // Searched for topic flagged as sensitive

        // Positive signals (reduce intervention urgency)
        case churchNoteCreated        // User wrote a church note
        case prayerPosted             // User posted a prayer
        case bereanConversation       // User had a Berean conversation
        case communityPost            // User posted/commented
        case churchVisit              // User used Find a Church
    }

    var isPositive: Bool {
        switch type {
        case .churchNoteCreated, .prayerPosted, .bereanConversation,
             .communityPost, .churchVisit:
            return true
        default:
            return false
        }
    }

    /// How much this signal contributes to intervention urgency.
    var urgencyWeight: Double {
        switch type {
        case .lateNightUsage:            return 0.6
        case .prolongedScrolling:        return 0.5
        case .rapidAppSwitching:         return 0.7
        case .extendedSession:           return 0.3
        case .noChurchFeatureUse:        return 0.8
        case .noPrayerActivity:          return 0.6
        case .noScriptureEngagement:     return 0.7
        case .noCommunityInteraction:    return 0.8
        case .repeatedUnfinishedPrompts: return 0.5
        case .deletedDraft:              return 0.3
        case .searchedSensitiveTopic:    return 0.6
        case .churchNoteCreated:         return -0.5
        case .prayerPosted:              return -0.5
        case .bereanConversation:        return -0.4
        case .communityPost:             return -0.3
        case .churchVisit:               return -0.6
        }
    }
}

// MARK: - Intervention Type

enum InterventionType: String, Codable {
    case temptationGuard       // "Before you continue, pause..."
    case isolationCheck        // "You've been quiet this week..."
    case disciplineReminder    // "You haven't been in the Word..."
    case communityNudge        // "Have you connected with anyone?"
    case lateNightReflection   // "It's late — what's on your mind?"
    case scrollingPause        // "You've been scrolling a while..."
    case prayerInvitation      // "Would you like to pause and pray?"
    case churchSuggestion      // "It's Sunday — find a church nearby?"
}

// MARK: - Intervention Candidate

/// A generated intervention ready to be surfaced to the user.
struct InterventionCandidate: Identifiable {
    let id: String
    let type: InterventionType
    let message: String
    let scriptureReference: String?
    let actionLabel: String?           // CTA button text
    let actionDeepLink: String?        // Where the CTA goes
    let urgency: Double                // 0.0 – 1.0
    let generatedAt: Date
    let expiresAt: Date                // Don't show after this time

    var isExpired: Bool {
        Date() > expiresAt
    }
}

// MARK: - Intervention Rules

/// A rule that maps signal patterns to interventions.
private struct InterventionRule {
    let requiredSignals: Set<BehavioralSignal.SignalType>
    let minimumCount: Int              // How many of these signals needed
    let timeWindowSeconds: TimeInterval // Within what time window
    let cooldownSeconds: TimeInterval  // Don't re-fire within this period
    let builder: () -> InterventionCandidate
}

// MARK: - Predictive Intervention Engine

@MainActor
final class PredictiveInterventionEngine: ObservableObject {

    static let shared = PredictiveInterventionEngine()

    /// The current intervention to show (nil = nothing to show).
    @Published private(set) var currentIntervention: InterventionCandidate?

    /// Whether the user has disabled predictive interventions.
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        }
    }

    private var signals: [BehavioralSignal] = []
    private var lastInterventionTimes: [InterventionType: Date] = [:]
    private let maxSignals = 100
    private let enabledKey = "berean_predictive_interventions_enabled"

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    // MARK: - Signal Ingestion

    /// Records a behavioral signal. Call this from various parts of the app
    /// when behavioral events occur.
    func ingestSignal(_ type: BehavioralSignal.SignalType, metadata: [String: String] = [:]) {
        guard isEnabled else { return }

        let signal = BehavioralSignal(type: type, timestamp: Date(), metadata: metadata)
        signals.append(signal)

        // Trim old signals (keep last 24 hours)
        let cutoff = Date().addingTimeInterval(-86400)
        signals = signals.filter { $0.timestamp > cutoff }
        if signals.count > maxSignals {
            signals = Array(signals.suffix(maxSignals))
        }

        // Evaluate after each new signal
        evaluateInterventions()
    }

    // MARK: - Intervention Evaluation

    /// Evaluates all rules and surfaces the highest-urgency intervention.
    func evaluateInterventions() {
        guard isEnabled else { return }

        let candidates = rules.compactMap { evaluate(rule: $0) }

        // Pick the highest urgency candidate that isn't expired and isn't in cooldown
        let best = candidates
            .filter { !$0.isExpired }
            .sorted { $0.urgency > $1.urgency }
            .first

        currentIntervention = best
    }

    /// Dismisses the current intervention. Records that it was shown.
    func dismissIntervention() {
        if let intervention = currentIntervention {
            lastInterventionTimes[intervention.type] = Date()
        }
        currentIntervention = nil
    }

    /// Marks the current intervention as acted upon (user tapped CTA).
    func actOnIntervention() {
        if let intervention = currentIntervention {
            lastInterventionTimes[intervention.type] = Date()
            // Record positive signal — user engaged with intervention
            signals.append(BehavioralSignal(
                type: .bereanConversation,
                timestamp: Date(),
                metadata: ["source": "intervention_\(intervention.type.rawValue)"]
            ))
        }
        currentIntervention = nil
    }

    // MARK: - Rule Evaluation

    private func evaluate(rule: InterventionRule) -> InterventionCandidate? {
        let now = Date()
        let windowStart = now.addingTimeInterval(-rule.timeWindowSeconds)

        let matchingSignals = signals.filter {
            rule.requiredSignals.contains($0.type) && $0.timestamp > windowStart
        }

        guard matchingSignals.count >= rule.minimumCount else { return nil }

        // Check cooldown
        let candidate = rule.builder()
        if let lastFired = lastInterventionTimes[candidate.type],
           now.timeIntervalSince(lastFired) < rule.cooldownSeconds {
            return nil
        }

        return candidate
    }

    // MARK: - Rules

    private var rules: [InterventionRule] {
        let now = Date()

        return [
            // Late night + scrolling → temptation guard
            InterventionRule(
                requiredSignals: [.lateNightUsage, .prolongedScrolling],
                minimumCount: 1,
                timeWindowSeconds: 1800, // 30 min
                cooldownSeconds: 43200,  // 12 hours
                builder: {
                    InterventionCandidate(
                        id: UUID().uuidString,
                        type: .temptationGuard,
                        message: "Before you continue, pause — what are you about to feed your mind?",
                        scriptureReference: "Proverbs 4:23",
                        actionLabel: "Open Berean",
                        actionDeepLink: "amen://berean",
                        urgency: 0.8,
                        generatedAt: now,
                        expiresAt: now.addingTimeInterval(3600) // 1 hour
                    )
                }
            ),

            // No community interaction → isolation check
            InterventionRule(
                requiredSignals: [.noCommunityInteraction],
                minimumCount: 1,
                timeWindowSeconds: 86400, // 24 hours
                cooldownSeconds: 172800,  // 48 hours
                builder: {
                    InterventionCandidate(
                        id: UUID().uuidString,
                        type: .isolationCheck,
                        message: "You've been quiet this week — have you connected with anyone?",
                        scriptureReference: "Hebrews 10:24-25",
                        actionLabel: "Find a Church",
                        actionDeepLink: "amen://find-church",
                        urgency: 0.7,
                        generatedAt: now,
                        expiresAt: now.addingTimeInterval(86400) // 24 hours
                    )
                }
            ),

            // No scripture engagement → discipline reminder
            InterventionRule(
                requiredSignals: [.noScriptureEngagement],
                minimumCount: 1,
                timeWindowSeconds: 86400,
                cooldownSeconds: 172800,
                builder: {
                    InterventionCandidate(
                        id: UUID().uuidString,
                        type: .disciplineReminder,
                        message: "Your Word is a lamp to my feet — when was the last time you opened it?",
                        scriptureReference: "Psalm 119:105",
                        actionLabel: "Ask Berean",
                        actionDeepLink: "amen://berean",
                        urgency: 0.6,
                        generatedAt: now,
                        expiresAt: now.addingTimeInterval(86400)
                    )
                }
            ),

            // Rapid app switching → scroll pause
            InterventionRule(
                requiredSignals: [.rapidAppSwitching],
                minimumCount: 3,
                timeWindowSeconds: 600, // 10 minutes
                cooldownSeconds: 21600, // 6 hours
                builder: {
                    InterventionCandidate(
                        id: UUID().uuidString,
                        type: .scrollingPause,
                        message: "You seem restless. Would you like to pause and center yourself?",
                        scriptureReference: "Philippians 4:6-7",
                        actionLabel: "Pause & Pray",
                        actionDeepLink: "amen://berean?mode=reflection",
                        urgency: 0.5,
                        generatedAt: now,
                        expiresAt: now.addingTimeInterval(1800) // 30 min
                    )
                }
            ),

            // Late night usage alone → late night reflection
            InterventionRule(
                requiredSignals: [.lateNightUsage],
                minimumCount: 1,
                timeWindowSeconds: 3600,
                cooldownSeconds: 86400, // 24 hours
                builder: {
                    InterventionCandidate(
                        id: UUID().uuidString,
                        type: .lateNightReflection,
                        message: "It's late — what's keeping you up? Let's talk about it.",
                        scriptureReference: "Psalm 4:8",
                        actionLabel: "Talk to Berean",
                        actionDeepLink: "amen://berean?mode=reflection",
                        urgency: 0.4,
                        generatedAt: now,
                        expiresAt: now.addingTimeInterval(7200) // 2 hours
                    )
                }
            ),

            // Repeated unfinished prompts → discipline breakdown
            InterventionRule(
                requiredSignals: [.repeatedUnfinishedPrompts],
                minimumCount: 3,
                timeWindowSeconds: 3600, // 1 hour
                cooldownSeconds: 43200,  // 12 hours
                builder: {
                    InterventionCandidate(
                        id: UUID().uuidString,
                        type: .prayerInvitation,
                        message: "It seems like something's on your heart but hard to express. Would you like help putting it into words?",
                        scriptureReference: "Romans 8:26",
                        actionLabel: "Start a Prayer",
                        actionDeepLink: "amen://berean?mode=reflection",
                        urgency: 0.5,
                        generatedAt: now,
                        expiresAt: now.addingTimeInterval(7200)
                    )
                }
            ),

            // No church features → Sunday suggestion
            InterventionRule(
                requiredSignals: [.noChurchFeatureUse],
                minimumCount: 1,
                timeWindowSeconds: 86400,
                cooldownSeconds: 604800, // 7 days
                builder: {
                    InterventionCandidate(
                        id: UUID().uuidString,
                        type: .churchSuggestion,
                        message: "Have you been connected to a local church lately? Community matters.",
                        scriptureReference: "Hebrews 10:24-25",
                        actionLabel: "Find a Church",
                        actionDeepLink: "amen://find-church",
                        urgency: 0.5,
                        generatedAt: now,
                        expiresAt: now.addingTimeInterval(172800) // 48 hours
                    )
                }
            ),

            // No prayer activity → prayer invitation
            InterventionRule(
                requiredSignals: [.noPrayerActivity],
                minimumCount: 1,
                timeWindowSeconds: 86400,
                cooldownSeconds: 172800,
                builder: {
                    InterventionCandidate(
                        id: UUID().uuidString,
                        type: .prayerInvitation,
                        message: "Prayer changes things — and it changes us. Would you like to pray right now?",
                        scriptureReference: "1 Thessalonians 5:17",
                        actionLabel: "Write a Prayer",
                        actionDeepLink: "amen://prayer",
                        urgency: 0.5,
                        generatedAt: now,
                        expiresAt: now.addingTimeInterval(86400)
                    )
                }
            )
        ]
    }

    // MARK: - Time-of-Day Intelligence

    /// Returns whether it's currently late night (11 PM – 5 AM).
    var isLateNight: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 23 || hour < 5
    }

    /// Returns whether it's Sunday morning (before noon).
    var isSundayMorning: Bool {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        return weekday == 1 && hour < 12 // Sunday before noon
    }

    /// Generates a time-aware context hint for Berean's system prompt.
    func timeContextHint() -> String? {
        if isSundayMorning {
            return "It's Sunday morning. If appropriate, gently encourage church attendance or offer to help the user find a church nearby."
        }
        if isLateNight {
            return "It's late at night. Use a more reflective, protective tone. Be gentle and check on the user's state of mind."
        }
        return nil
    }

    // MARK: - Reset

    func reset() {
        signals.removeAll()
        currentIntervention = nil
        lastInterventionTimes.removeAll()
    }
}
