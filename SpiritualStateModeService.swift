//
//  SpiritualStateModeService.swift
//  AMENAPP
//
//  Spiritual State Modes — lets Berean operate in context-appropriate modes:
//    - Growth Mode:      Structured training + accountability
//    - Crisis Mode:      Immediate support + human escalation
//    - Reflection Mode:  Journaling + deep questions
//    - Exploration Mode: Theology + learning + discovery
//
//  Mode switching = intelligence sophistication.
//  Modes can be set manually by the user or auto-detected from signals.
//
//  Architecture:
//    SpiritualStateModeService (singleton, @MainActor)
//    ├── SpiritualStateMode          (the four modes)
//    ├── ModeSignal                  (input signals for auto-detection)
//    ├── setMode()                   (manual mode switch)
//    ├── detectMode()                (auto-detect from signals)
//    └── systemPromptForMode()       (inject mode behavior into Berean prompt)
//

import Foundation
import Combine

// MARK: - Spiritual State Mode

enum SpiritualStateMode: String, Codable, CaseIterable {
    case growth       = "growth"
    case crisis       = "crisis"
    case reflection   = "reflection"
    case exploration  = "exploration"

    var displayName: String {
        switch self {
        case .growth:      return "Growth"
        case .crisis:      return "Crisis Support"
        case .reflection:  return "Reflection"
        case .exploration: return "Exploration"
        }
    }

    var icon: String {
        switch self {
        case .growth:      return "arrow.up.right.circle.fill"
        case .crisis:      return "heart.circle.fill"
        case .reflection:  return "moon.stars.fill"
        case .exploration: return "compass.drawing"
        }
    }

    var shortDescription: String {
        switch self {
        case .growth:      return "Structured training and accountability"
        case .crisis:      return "Immediate support and care"
        case .reflection:  return "Deep questions and journaling"
        case .exploration: return "Theology, learning, and discovery"
        }
    }

    /// System prompt prefix that shapes Berean's behavior in this mode.
    var systemPromptPrefix: String {
        switch self {
        case .growth:
            return """
                You are in GROWTH MODE. The user is actively training in their faith.
                Your role: structured accountability partner.
                - Ask direct, challenging questions about obedience and discipline.
                - Suggest concrete daily actions with follow-up.
                - Reference their spiritual patterns and growth areas.
                - Be encouraging but don't soften the truth.
                - Track commitments and ask about follow-through.
                - Celebrate progress with genuine recognition.
                """

        case .crisis:
            return """
                You are in CRISIS MODE. The user may be in distress or facing an urgent struggle.
                Your role: compassionate first responder.
                - Lead with empathy and presence — "I'm here."
                - Keep responses shorter and warmer.
                - Offer Scripture as comfort, not correction.
                - Do NOT challenge or push accountability right now.
                - Gently suggest connecting with a real person (pastor, friend, counselor).
                - If self-harm or danger is indicated, surface crisis resources immediately.
                - Stay in this mode until the user shows stabilization.
                """

        case .reflection:
            return """
                You are in REFLECTION MODE. The user wants to go deeper.
                Your role: thoughtful spiritual guide.
                - Ask open-ended, contemplative questions.
                - Allow silence and space — don't rush to fill gaps.
                - Encourage journaling and self-examination.
                - Reference Psalm 139:23-24 style introspection.
                - Connect current reflections to past patterns when relevant.
                - Suggest writing or prayer exercises, not action items.
                """

        case .exploration:
            return """
                You are in EXPLORATION MODE. The user is curious and learning.
                Your role: knowledgeable theologian and teacher.
                - Provide thorough, well-cited explanations.
                - Explore multiple perspectives on debatable topics.
                - Offer historical context, word studies, and cross-references.
                - Be intellectually honest about areas of theological disagreement.
                - Encourage further study with specific resources.
                - Keep the tone academic but accessible.
                """
        }
    }
}

// MARK: - Mode Signal

/// Input signals used for automatic mode detection.
struct ModeSignal {
    let type: SignalType
    let confidence: Double  // 0.0 – 1.0
    let timestamp: Date

    enum SignalType {
        // Crisis indicators
        case distressLanguage          // "I can't take this", "I'm falling apart"
        case crisisKeyword             // "suicidal", "hopeless", "give up"
        case repeatedNegativeEmotion   // 3+ negative messages in a row
        case lateNightDistress         // Distress + late night usage

        // Growth indicators
        case commitmentLanguage        // "I want to grow", "help me be disciplined"
        case followUpOnAction          // User reporting back on a challenge
        case goalSetting               // Setting spiritual goals
        case consistentEngagement      // Regular daily usage

        // Reflection indicators
        case introspectiveLanguage     // "I've been thinking about...", "Why do I..."
        case journalingBehavior        // Long-form input, self-examination
        case quietTone                 // Slow, contemplative messages
        case pastPatternReference      // Referencing past struggles/growth

        // Exploration indicators
        case theologicalQuestion       // "What does the Bible say about..."
        case wordStudyRequest          // "What does X mean in Greek?"
        case comparativeQuestion       // "What do different denominations think?"
        case historicalContextRequest  // "What was happening in Israel when..."
    }

    /// Which mode this signal suggests.
    var suggestedMode: SpiritualStateMode {
        switch type {
        case .distressLanguage, .crisisKeyword, .repeatedNegativeEmotion, .lateNightDistress:
            return .crisis
        case .commitmentLanguage, .followUpOnAction, .goalSetting, .consistentEngagement:
            return .growth
        case .introspectiveLanguage, .journalingBehavior, .quietTone, .pastPatternReference:
            return .reflection
        case .theologicalQuestion, .wordStudyRequest, .comparativeQuestion, .historicalContextRequest:
            return .exploration
        }
    }
}

// MARK: - Mode Transition

/// Records a mode transition for observability.
struct ModeTransition: Codable {
    let fromMode: String
    let toMode: String
    let reason: TransitionReason
    let timestamp: Date

    enum TransitionReason: String, Codable {
        case userManual       // User explicitly switched
        case autoDetected     // System detected from signals
        case sessionStart     // Default mode at session start
        case crisisEscalation // Automatic escalation to crisis
        case crisisDeescalation // Leaving crisis mode
    }
}

// MARK: - Service

@MainActor
final class SpiritualStateModeService: ObservableObject {

    static let shared = SpiritualStateModeService()

    @Published private(set) var currentMode: SpiritualStateMode = .growth
    @Published private(set) var isAutoDetected: Bool = false

    /// Recent signals for mode detection (in-memory only, not persisted).
    private var recentSignals: [ModeSignal] = []
    private let maxSignals = 20
    private let signalWindowSeconds: TimeInterval = 600 // 10 minutes

    /// Mode transition history (in-memory for session).
    private(set) var transitions: [ModeTransition] = []

    private let storageKey = "berean_spiritual_mode_v1"

    private init() {
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           let mode = SpiritualStateMode(rawValue: saved) {
            currentMode = mode
        }
    }

    // MARK: - Manual Mode Switch

    /// User explicitly sets the mode.
    func setMode(_ mode: SpiritualStateMode) {
        let previous = currentMode
        currentMode = mode
        isAutoDetected = false
        UserDefaults.standard.set(mode.rawValue, forKey: storageKey)

        transitions.append(ModeTransition(
            fromMode: previous.rawValue,
            toMode: mode.rawValue,
            reason: .userManual,
            timestamp: Date()
        ))
    }

    // MARK: - Signal Ingestion

    /// Adds a signal for mode auto-detection. Call from message analysis.
    func addSignal(_ signal: ModeSignal) {
        recentSignals.append(signal)

        // Trim old signals
        let cutoff = Date().addingTimeInterval(-signalWindowSeconds)
        recentSignals = recentSignals
            .filter { $0.timestamp > cutoff }
            .suffix(maxSignals)
            .map { $0 }

        // Crisis signals get immediate escalation
        if signal.type == .crisisKeyword && signal.confidence > 0.7 {
            escalateToCrisis(reason: .crisisEscalation)
            return
        }

        // Auto-detect if we have enough signals
        if recentSignals.count >= 3 {
            autoDetectMode()
        }
    }

    /// Convenience: classify a user message and add relevant signals.
    func classifyMessage(_ text: String) {
        let lowered = text.lowercased()
        let now = Date()

        // Crisis keywords (high priority)
        let crisisKeywords = ["suicidal", "kill myself", "end it all", "can't go on", "give up on life", "no reason to live"]
        for keyword in crisisKeywords {
            if lowered.contains(keyword) {
                addSignal(ModeSignal(type: .crisisKeyword, confidence: 0.9, timestamp: now))
                return
            }
        }

        // Distress language
        let distressPatterns = ["i can't take", "falling apart", "breaking down", "so scared", "terrified", "desperate", "drowning"]
        for pattern in distressPatterns {
            if lowered.contains(pattern) {
                addSignal(ModeSignal(type: .distressLanguage, confidence: 0.7, timestamp: now))
                return
            }
        }

        // Growth language
        let growthPatterns = ["i want to grow", "help me be", "hold me accountable", "i committed to", "i did it", "followed through", "challenge me"]
        for pattern in growthPatterns {
            if lowered.contains(pattern) {
                addSignal(ModeSignal(type: .commitmentLanguage, confidence: 0.7, timestamp: now))
                return
            }
        }

        // Reflection language
        let reflectionPatterns = ["i've been thinking", "why do i", "what does it mean that", "i realized", "looking back", "i wonder why", "i need to process"]
        for pattern in reflectionPatterns {
            if lowered.contains(pattern) {
                addSignal(ModeSignal(type: .introspectiveLanguage, confidence: 0.7, timestamp: now))
                return
            }
        }

        // Exploration language
        let explorationPatterns = ["what does the bible say", "in the greek", "in the hebrew", "what denomination", "historically", "theologians think", "what's the context of", "explain the doctrine"]
        for pattern in explorationPatterns {
            if lowered.contains(pattern) {
                addSignal(ModeSignal(type: .theologicalQuestion, confidence: 0.8, timestamp: now))
                return
            }
        }
    }

    // MARK: - Auto Detection

    private func autoDetectMode() {
        // Count signals per mode
        var modeScores: [SpiritualStateMode: Double] = [:]
        for signal in recentSignals {
            let mode = signal.suggestedMode
            modeScores[mode, default: 0] += signal.confidence
        }

        // Crisis always wins if present
        if let crisisScore = modeScores[.crisis], crisisScore > 1.0 {
            if currentMode != .crisis {
                escalateToCrisis(reason: .crisisEscalation)
            }
            return
        }

        // Find highest-scoring non-crisis mode
        let nonCrisis = modeScores.filter { $0.key != .crisis }
        guard let (bestMode, bestScore) = nonCrisis.max(by: { $0.value < $1.value }),
              bestScore > 1.5,  // Need sufficient confidence
              bestMode != currentMode else {
            return
        }

        let previous = currentMode
        currentMode = bestMode
        isAutoDetected = true
        UserDefaults.standard.set(bestMode.rawValue, forKey: storageKey)

        transitions.append(ModeTransition(
            fromMode: previous.rawValue,
            toMode: bestMode.rawValue,
            reason: .autoDetected,
            timestamp: Date()
        ))
    }

    private func escalateToCrisis(reason: ModeTransition.TransitionReason) {
        let previous = currentMode
        currentMode = .crisis
        isAutoDetected = true
        UserDefaults.standard.set(SpiritualStateMode.crisis.rawValue, forKey: storageKey)

        transitions.append(ModeTransition(
            fromMode: previous.rawValue,
            toMode: SpiritualStateMode.crisis.rawValue,
            reason: reason,
            timestamp: Date()
        ))
    }

    // MARK: - System Prompt

    /// Returns the full system prompt injection for the current mode.
    func currentSystemPrompt() -> String {
        var prompt = currentMode.systemPromptPrefix

        if isAutoDetected {
            prompt += "\n\n(Mode was auto-detected from conversation signals. " +
                      "If the user seems to be in a different mode, adjust naturally.)"
        }

        return prompt
    }

    /// Returns the system prompt for a specific mode.
    func systemPrompt(for mode: SpiritualStateMode) -> String {
        mode.systemPromptPrefix
    }

    // MARK: - Reset

    func reset() {
        currentMode = .growth
        isAutoDetected = false
        recentSignals.removeAll()
        transitions.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
