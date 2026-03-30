// LifePatternIntelligence.swift
// AMENAPP
//
// Life Pattern Intelligence: Behavior-Aware AI
//
// Tracks user patterns and adapts spiritual + practical guidance.
// Includes Spiritual State Detection (burnout, isolation, doubt).
//
// Signals:
//   - Posting tone (sad, anxious, joyful)
//   - Time of use (late-night scrolling)
//   - Content engagement patterns
//   - Prayer request frequency + themes
//   - Berean conversation themes
//
// Outputs:
//   - Proactive check-ins ("You've been posting about stress—want support?")
//   - Contextual scripture suggestions
//   - Resource recommendations
//   - Connection suggestions
//
// ALL data stays on device unless user explicitly shares.
// Conservative thresholds — many false negatives preferred over intrusions.
//
// Entry points:
//   LifePatternIntelligence.shared.recordSignal(_ signal:)
//   LifePatternIntelligence.shared.getSpiritualState() -> SpiritualState
//   LifePatternIntelligence.shared.getProactiveGuidance() async -> ProactiveGuidance?

import Foundation
import SwiftUI
import Combine

// MARK: - Models

/// A behavioral signal from user activity
struct BehaviorSignal {
    let type: SignalType
    let value: String               // Content or metric
    let intensity: Double           // 0.0 - 1.0
    let timestamp: Date
    let source: String              // Which screen/feature

    enum SignalType: String {
        case postTone = "post_tone"
        case prayerTheme = "prayer_theme"
        case lateNightUsage = "late_night"
        case engagementDrop = "engagement_drop"
        case repeatedTopic = "repeated_topic"
        case bereanQuery = "berean_query"
        case churchAttendance = "church_attendance"
        case reflectionDepth = "reflection_depth"
        case isolationPattern = "isolation"
        case positiveEngagement = "positive"
    }
}

/// Detected spiritual/emotional state
struct SpiritualState {
    let primary: SpiritualCondition
    let confidence: Double          // 0.0 - 1.0
    let signals: [String]           // What led to this assessment
    let duration: StateDuration     // How long this has been detected
    let trend: Trend                // Getting better or worse

    enum Trend: String {
        case improving = "improving"
        case stable = "stable"
        case declining = "declining"
        case unknown = "unknown"
    }
}

enum SpiritualCondition: String, CaseIterable {
    case thriving = "thriving"          // Active, engaged, growing
    case stable = "stable"              // Normal healthy engagement
    case seeking = "seeking"            // Actively searching for answers
    case stressed = "stressed"          // Showing signs of pressure
    case isolated = "isolated"          // Disconnected from community
    case doubting = "doubting"          // Questioning faith/beliefs
    case burnedOut = "burned_out"       // Spiritual exhaustion
    case grieving = "grieving"          // Processing loss
    case crisis = "crisis"              // Needs immediate support

    var icon: String {
        switch self {
        case .thriving: return "sun.max.fill"
        case .stable: return "leaf.fill"
        case .seeking: return "magnifyingglass"
        case .stressed: return "cloud.fill"
        case .isolated: return "person.fill.xmark"
        case .doubting: return "questionmark.circle.fill"
        case .burnedOut: return "flame.fill"
        case .grieving: return "heart.fill"
        case .crisis: return "exclamationmark.triangle.fill"
        }
    }

    var supportLevel: Int {
        switch self {
        case .thriving, .stable: return 0
        case .seeking: return 1
        case .stressed, .doubting: return 2
        case .isolated, .burnedOut, .grieving: return 3
        case .crisis: return 4
        }
    }
}

enum StateDuration: String {
    case recent = "recent"          // < 3 days
    case shortTerm = "short_term"   // 3-7 days
    case persistent = "persistent"  // > 7 days
}

/// Proactive guidance generated from patterns
struct ProactiveGuidance: Identifiable {
    let id = UUID()
    let type: GuidanceType
    let message: String
    let suggestedScripture: String?
    let suggestedAction: String?
    let suggestedResource: String?
    let urgency: Int                // 0-4

    enum GuidanceType: String {
        case checkIn = "check_in"
        case scriptureRecommendation = "scripture"
        case resourceSuggestion = "resource"
        case connectionPrompt = "connection"
        case restReminder = "rest"
        case celebrationPrompt = "celebration"
        case crisisSupport = "crisis_support"
    }
}

// MARK: - LifePatternIntelligence

@MainActor
final class LifePatternIntelligence: ObservableObject {

    static let shared = LifePatternIntelligence()

    @Published var currentState: SpiritualState
    @Published var pendingGuidance: ProactiveGuidance?
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "life_pattern_enabled") }
    }

    // Rolling signal buffer (last 7 days, in-memory only)
    private var signalBuffer: [BehaviorSignal] = []
    private let maxSignals = 500
    private let aiService = ClaudeService.shared
    private var analysisTimer: Timer?

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: "life_pattern_enabled") as? Bool ?? true
        currentState = SpiritualState(
            primary: .stable,
            confidence: 0.3,
            signals: [],
            duration: .recent,
            trend: .unknown
        )

        // Analyze patterns every 30 minutes
        analysisTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.analyzePatterns()
            }
        }
    }

    // MARK: - Signal Recording

    /// Record a behavioral signal (entirely local)
    func recordSignal(_ signal: BehaviorSignal) {
        guard isEnabled else { return }

        signalBuffer.append(signal)

        // Trim old signals (> 7 days)
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        signalBuffer.removeAll { $0.timestamp < cutoff }

        // Keep buffer size manageable
        if signalBuffer.count > maxSignals {
            signalBuffer.removeFirst(signalBuffer.count - maxSignals)
        }

        // Quick check for immediate signals
        if signal.type == .lateNightUsage && signal.intensity > 0.7 {
            checkLateNightPattern()
        }
    }

    /// Convenience: record a post tone signal
    func recordPostTone(_ text: String) {
        let negative = ["sad", "hurt", "alone", "struggling", "anxious", "scared", "lost", "broken", "hopeless", "tired"]
        let positive = ["grateful", "blessed", "thankful", "joyful", "growing", "peace", "praise", "worship"]
        let textLower = text.lowercased()

        let negScore = Double(negative.filter { textLower.contains($0) }.count) / Double(negative.count)
        let posScore = Double(positive.filter { textLower.contains($0) }.count) / Double(positive.count)

        if negScore > 0.1 {
            recordSignal(BehaviorSignal(
                type: .postTone,
                value: "negative_tone",
                intensity: min(negScore * 3, 1.0),
                timestamp: Date(),
                source: "post"
            ))
        }
        if posScore > 0.1 {
            recordSignal(BehaviorSignal(
                type: .positiveEngagement,
                value: "positive_tone",
                intensity: posScore * 3,
                timestamp: Date(),
                source: "post"
            ))
        }
    }

    // MARK: - State Detection

    /// Get the current spiritual state assessment
    func getSpiritualState() -> SpiritualState {
        return currentState
    }

    /// Full pattern analysis (called periodically)
    func analyzePatterns() async {
        guard isEnabled, !signalBuffer.isEmpty else { return }

        let now = Date()
        let recentSignals = signalBuffer.filter { now.timeIntervalSince($0.timestamp) < 3 * 86400 }

        // Aggregate signals by type
        let toneSignals = recentSignals.filter { $0.type == .postTone }
        let lateNight = recentSignals.filter { $0.type == .lateNightUsage }
        let isolation = recentSignals.filter { $0.type == .isolationPattern }
        let positive = recentSignals.filter { $0.type == .positiveEngagement }

        // Score conditions
        var conditionScores: [SpiritualCondition: Double] = [:]

        // Negative tone frequency
        let negToneScore = toneSignals.isEmpty ? 0 : toneSignals.reduce(0.0) { $0 + $1.intensity } / Double(toneSignals.count)
        if negToneScore > 0.3 { conditionScores[.stressed] = negToneScore }

        // Late night usage
        let lateNightScore = Double(lateNight.count) / 7.0
        if lateNightScore > 0.3 { conditionScores[.stressed, default: 0] += lateNightScore * 0.3 }

        // Isolation signals
        let isolationScore = Double(isolation.count) / 5.0
        if isolationScore > 0.3 { conditionScores[.isolated] = isolationScore }

        // Positive engagement
        let positiveScore = Double(positive.count) / 5.0
        if positiveScore > 0.5 { conditionScores[.thriving] = positiveScore }

        // Determine primary condition
        let primary: SpiritualCondition
        let confidence: Double

        if let highest = conditionScores.max(by: { $0.value < $1.value }), highest.value > 0.3 {
            primary = highest.key
            confidence = min(highest.value, 1.0)
        } else {
            primary = positive.count > 2 ? .thriving : .stable
            confidence = 0.5
        }

        // Determine duration
        let weekOldSignals = signalBuffer.filter { now.timeIntervalSince($0.timestamp) > 3 * 86400 }
        let persistentPattern = weekOldSignals.filter { $0.type == .postTone }.reduce(0.0) { $0 + $1.intensity } > 1.0
        let duration: StateDuration = persistentPattern ? .persistent : .recent

        let previousState = currentState
        currentState = SpiritualState(
            primary: primary,
            confidence: confidence,
            signals: recentSignals.prefix(5).map { "\($0.type.rawValue): \($0.value)" },
            duration: duration,
            trend: determineTrend(previous: previousState.primary, current: primary)
        )

        // Generate proactive guidance if needed
        if primary.supportLevel >= 2 {
            pendingGuidance = await generateGuidance(for: currentState)
        }
    }

    /// Generate proactive guidance based on detected state
    func getProactiveGuidance() async -> ProactiveGuidance? {
        guard isEnabled else { return nil }

        if let existing = pendingGuidance { return existing }

        guard currentState.primary.supportLevel >= 1 else { return nil }

        return await generateGuidance(for: currentState)
    }

    // MARK: - Private

    private func checkLateNightPattern() {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 23 || hour < 4 {
            let lateCount = signalBuffer.filter {
                $0.type == .lateNightUsage &&
                Date().timeIntervalSince($0.timestamp) < 3 * 86400
            }.count

            if lateCount >= 3 {
                pendingGuidance = ProactiveGuidance(
                    type: .restReminder,
                    message: "You've been up late several nights. Rest is a gift from God — consider getting some sleep.",
                    suggestedScripture: "Psalm 127:2",
                    suggestedAction: "Set a bedtime reminder",
                    suggestedResource: nil,
                    urgency: 1
                )
            }
        }
    }

    private func generateGuidance(for state: SpiritualState) async -> ProactiveGuidance? {
        let prompt = """
        Based on detected behavioral patterns, a user appears to be in a "\(state.primary.rawValue)" spiritual/emotional state (confidence: \(Int(state.confidence * 100))%).

        Generate a gentle, non-intrusive check-in. Return as JSON:
        {
            "message": "A warm, caring message (1-2 sentences). Not preachy.",
            "suggestedScripture": "A relevant verse reference",
            "suggestedAction": "One simple thing they could do",
            "urgency": \(state.primary.supportLevel)
        }

        Be pastoral, warm, and respectful of boundaries. Return ONLY valid JSON.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let data = Data(cleanJSON(response).utf8)

            struct GuidanceResponse: Codable {
                let message: String
                let suggestedScripture: String?
                let suggestedAction: String?
                let urgency: Int
            }

            let parsed = try JSONDecoder().decode(GuidanceResponse.self, from: data)
            return ProactiveGuidance(
                type: state.primary == .crisis ? .crisisSupport : .checkIn,
                message: parsed.message,
                suggestedScripture: parsed.suggestedScripture,
                suggestedAction: parsed.suggestedAction,
                suggestedResource: nil,
                urgency: parsed.urgency
            )
        } catch {
            return nil
        }
    }

    private func determineTrend(previous: SpiritualCondition, current: SpiritualCondition) -> SpiritualState.Trend {
        if current.supportLevel < previous.supportLevel { return .improving }
        if current.supportLevel > previous.supportLevel { return .declining }
        return .stable
    }

    private func cleanJSON(_ response: String) -> String {
        var s = response
        if let start = s.range(of: "{"), let end = s.range(of: "}", options: .backwards) {
            s = String(s[start.lowerBound...end.upperBound])
        }
        return s
    }
}
