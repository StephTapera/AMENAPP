//
//  BereanSafetyEscalationService.swift
//  AMENAPP
//
//  Enhanced Spiritual + Emotional Safety Engine
//
//  Detects and responds to:
//    - Burnout (spiritual exhaustion, performance-driven faith)
//    - Shame loops (self-condemnation cycles, scrupulosity)
//    - Isolation (withdrawal from community, social disconnection)
//
//  Response strategy (graduated):
//    1. Scripture-based encouragement
//    2. Gentle prompt to connect with someone
//    3. Surface real-world resources (Find a Church, crisis line)
//    4. Escalate to SafetyOrchestrator for crisis-level concerns
//
//  Transparency layer:
//    - User can see why Berean suggested something
//    - Pattern explanations are human-readable
//    - No "black box" decisions
//
//  Privacy:
//    - All detection is in-memory (no raw content stored)
//    - Only aggregated escalation state is persisted
//    - User can disable enhanced safety features
//
//  Architecture:
//    BereanSafetyEscalationService (singleton, @MainActor)
//    ├── SafetyPattern              (detected pattern types)
//    ├── EscalationLevel            (graduated response levels)
//    ├── EscalationResponse         (what to surface to the user)
//    ├── analyzeMessage()           (process a message for safety signals)
//    ├── evaluateState()            (determine current escalation level)
//    └── transparencyExplanation()  (why Berean made this suggestion)
//

import Foundation
import Combine

// MARK: - Safety Pattern

/// Types of concerning patterns the safety engine can detect.
enum SafetyPattern: String, Codable {
    // Burnout patterns
    case spiritualExhaustion       // "I'm tired of trying"
    case performanceFaith          // "I'm never good enough for God"
    case obligationOverJoy         // "I have to pray/read" (duty, not desire)
    case comparisonDespair         // "Everyone else is growing but me"

    // Shame loop patterns
    case selfCondemnation          // "I'm worthless", "God must be disappointed"
    case repeatedConfession        // Same sin confessed 3+ times without progress
    case scrupulosity              // Obsessive religious guilt
    case identityInSin             // "I am my sin" (identity confusion)

    // Isolation patterns
    case socialWithdrawal          // Avoiding community features
    case trustErosion              // "Nobody understands", "I can't tell anyone"
    case secretKeeping             // "I've been hiding this"
    case communityRejection        // "Church hurt me", "Christians are fake"

    // Acute distress (immediate escalation)
    case hopelessness              // "There's no point"
    case selfHarmLanguage          // References to self-harm
    case suicidalIdeation          // Any mention of ending life

    var category: PatternCategory {
        switch self {
        case .spiritualExhaustion, .performanceFaith, .obligationOverJoy, .comparisonDespair:
            return .burnout
        case .selfCondemnation, .repeatedConfession, .scrupulosity, .identityInSin:
            return .shameLoop
        case .socialWithdrawal, .trustErosion, .secretKeeping, .communityRejection:
            return .isolation
        case .hopelessness, .selfHarmLanguage, .suicidalIdeation:
            return .acuteDistress
        }
    }

    enum PatternCategory: String, Codable {
        case burnout       = "burnout"
        case shameLoop     = "shame_loop"
        case isolation     = "isolation"
        case acuteDistress = "acute_distress"
    }

    /// Human-readable explanation for the transparency layer.
    var transparencyLabel: String {
        switch self {
        case .spiritualExhaustion:   return "You may be experiencing spiritual exhaustion"
        case .performanceFaith:      return "Your faith journey seems performance-driven right now"
        case .obligationOverJoy:     return "Your spiritual practices may feel like obligations"
        case .comparisonDespair:     return "You seem to be comparing your journey to others"
        case .selfCondemnation:      return "You may be caught in a cycle of self-condemnation"
        case .repeatedConfession:    return "This struggle has come up several times"
        case .scrupulosity:          return "You may be experiencing excessive religious guilt"
        case .identityInSin:         return "You may be confusing your identity with your struggles"
        case .socialWithdrawal:      return "You seem to be pulling away from community"
        case .trustErosion:          return "Trust in others seems to be a challenge right now"
        case .secretKeeping:         return "You're carrying something alone"
        case .communityRejection:    return "You may have experienced hurt from community"
        case .hopelessness:          return "You may be feeling hopeless"
        case .selfHarmLanguage:      return "Your words suggest you may be in pain"
        case .suicidalIdeation:      return "Your safety is the most important thing right now"
        }
    }
}

// MARK: - Escalation Level

enum EscalationLevel: Int, Codable, Comparable {
    case none = 0               // No concern detected
    case gentle = 1             // Scripture encouragement
    case moderate = 2           // Prompt to connect with someone
    case elevated = 3           // Surface real-world resources
    case critical = 4           // Escalate to crisis flow

    static func < (lhs: EscalationLevel, rhs: EscalationLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .none:     return "Normal"
        case .gentle:   return "Gentle care"
        case .moderate: return "Supportive"
        case .elevated: return "Resource connection"
        case .critical: return "Crisis support"
        }
    }
}

// MARK: - Escalation Response

/// What the safety engine recommends surfacing to the user.
struct EscalationResponse: Identifiable {
    let id: String
    let level: EscalationLevel
    let pattern: SafetyPattern
    let scriptureComfort: String           // Verse for comfort
    let bereanPromptInjection: String      // Added to Berean's system prompt
    let userFacingMessage: String?         // Direct message to show (elevated+)
    let suggestedAction: SuggestedSafetyAction?
    let transparencyNote: String           // Why this was triggered
    let generatedAt: Date

    enum SuggestedSafetyAction: String, Codable {
        case suggestFindChurch         // "Find a church near you"
        case suggestTrustedPerson      // "Talk to someone you trust"
        case suggestPastor             // "Consider reaching out to a pastor"
        case suggestCrisisLine         // "988 Suicide & Crisis Lifeline"
        case suggestProfessionalHelp   // "A counselor could help"
        case suggestCommunityGroup     // "A small group could be helpful"
        case suggestRest               // "It's okay to rest"
    }
}

// MARK: - Detection Signal

/// An in-memory signal from message analysis.
private struct DetectionSignal {
    let pattern: SafetyPattern
    let confidence: Double  // 0.0 – 1.0
    let timestamp: Date
}

// MARK: - Service

@MainActor
final class BereanSafetyEscalationService: ObservableObject {

    static let shared = BereanSafetyEscalationService()

    @Published private(set) var currentEscalation: EscalationResponse?
    @Published private(set) var currentLevel: EscalationLevel = .none

    /// Whether enhanced safety detection is enabled (user can disable).
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        }
    }

    private var signals: [DetectionSignal] = []
    private let maxSignals = 50
    private let signalWindowSeconds: TimeInterval = 1800 // 30 minutes
    private let enabledKey = "berean_safety_escalation_enabled"

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    // MARK: - Message Analysis

    /// Analyzes a user message for safety-relevant patterns.
    /// Call this for every user message in Berean chat.
    func analyzeMessage(_ text: String) {
        guard isEnabled else { return }

        let lowered = text.lowercased()

        // Acute distress — immediate escalation
        let suicidalPatterns = ["kill myself", "end my life", "suicide", "want to die", "no reason to live", "better off dead"]
        for pattern in suicidalPatterns {
            if lowered.contains(pattern) {
                addSignal(.suicidalIdeation, confidence: 0.95)
                evaluateState()
                return
            }
        }

        let selfHarmPatterns = ["hurt myself", "cutting", "self-harm", "harm myself", "punish myself physically"]
        for pattern in selfHarmPatterns {
            if lowered.contains(pattern) {
                addSignal(.selfHarmLanguage, confidence: 0.9)
                evaluateState()
                return
            }
        }

        let hopelessPatterns = ["no point", "no hope", "nothing matters", "why bother", "give up", "can't go on"]
        for pattern in hopelessPatterns {
            if lowered.contains(pattern) {
                addSignal(.hopelessness, confidence: 0.7)
            }
        }

        // Burnout patterns
        let exhaustionPatterns = ["tired of trying", "exhausted", "burned out", "can't keep up", "spiritually drained", "faith is empty"]
        for pattern in exhaustionPatterns {
            if lowered.contains(pattern) {
                addSignal(.spiritualExhaustion, confidence: 0.7)
            }
        }

        let performancePatterns = ["never good enough", "not enough for god", "always failing god", "can't measure up", "disappointing god"]
        for pattern in performancePatterns {
            if lowered.contains(pattern) {
                addSignal(.performanceFaith, confidence: 0.7)
            }
        }

        let obligationPatterns = ["have to pray", "should read my bible", "supposed to", "feel guilty for not"]
        for pattern in obligationPatterns {
            if lowered.contains(pattern) {
                addSignal(.obligationOverJoy, confidence: 0.5)
            }
        }

        // Shame loop patterns
        let condemnationPatterns = ["i'm worthless", "god hates me", "i'm a terrible", "i'm disgusting", "unforgivable", "god is done with me"]
        for pattern in condemnationPatterns {
            if lowered.contains(pattern) {
                addSignal(.selfCondemnation, confidence: 0.8)
            }
        }

        let scrupulosityPatterns = ["committed the unpardonable", "blasphemed", "lost my salvation", "unforgivable sin"]
        for pattern in scrupulosityPatterns {
            if lowered.contains(pattern) {
                addSignal(.scrupulosity, confidence: 0.8)
            }
        }

        let identityPatterns = ["i am my sin", "i'll never change", "this is who i am", "born this way and it's wrong"]
        for pattern in identityPatterns {
            if lowered.contains(pattern) {
                addSignal(.identityInSin, confidence: 0.7)
            }
        }

        // Isolation patterns
        let withdrawalPatterns = ["nobody understands", "all alone", "can't tell anyone", "no one cares", "don't belong"]
        for pattern in withdrawalPatterns {
            if lowered.contains(pattern) {
                addSignal(.socialWithdrawal, confidence: 0.6)
            }
        }

        let trustPatterns = ["can't trust", "church hurt", "christians are fake", "betrayed by", "pastors are"]
        for pattern in trustPatterns {
            if lowered.contains(pattern) {
                addSignal(.communityRejection, confidence: 0.6)
            }
        }

        let secretPatterns = ["hiding this", "secret", "can't admit", "ashamed to tell", "no one knows"]
        for pattern in secretPatterns {
            if lowered.contains(pattern) {
                addSignal(.secretKeeping, confidence: 0.5)
            }
        }

        evaluateState()
    }

    // MARK: - State Evaluation

    /// Evaluates all signals and determines the current escalation level + response.
    func evaluateState() {
        guard isEnabled else { return }

        // Clean expired signals
        let cutoff = Date().addingTimeInterval(-signalWindowSeconds)
        signals = signals.filter { $0.timestamp > cutoff }

        guard !signals.isEmpty else {
            currentLevel = .none
            currentEscalation = nil
            return
        }

        // Check for acute distress (immediate critical escalation)
        let acuteSignals = signals.filter { $0.pattern.category == .acuteDistress }
        if let strongest = acuteSignals.max(by: { $0.confidence < $1.confidence }),
           strongest.confidence > 0.7 {
            currentLevel = .critical
            currentEscalation = buildResponse(for: strongest.pattern, level: .critical)
            return
        }

        // Score by category
        var categoryScores: [SafetyPattern.PatternCategory: Double] = [:]
        for signal in signals {
            categoryScores[signal.pattern.category, default: 0] += signal.confidence
        }

        // Determine level based on highest category score
        let maxScore = categoryScores.values.max() ?? 0
        let level: EscalationLevel
        if maxScore >= 2.5 {
            level = .elevated
        } else if maxScore >= 1.5 {
            level = .moderate
        } else if maxScore >= 0.5 {
            level = .gentle
        } else {
            level = .none
        }

        currentLevel = level

        if level != .none,
           let (_, highestCategory) = categoryScores.max(by: { $0.value < $1.value }),
           let representativeSignal = signals.last(where: { $0.pattern.category == highestCategory }) {
            currentEscalation = buildResponse(for: representativeSignal.pattern, level: level)
        } else {
            currentEscalation = nil
        }
    }

    // MARK: - Response Builder

    private func buildResponse(for pattern: SafetyPattern, level: EscalationLevel) -> EscalationResponse {
        let (scripture, prompt, message, action) = responseContent(for: pattern, level: level)

        return EscalationResponse(
            id: UUID().uuidString,
            level: level,
            pattern: pattern,
            scriptureComfort: scripture,
            bereanPromptInjection: prompt,
            userFacingMessage: level >= .elevated ? message : nil,
            suggestedAction: action,
            transparencyNote: pattern.transparencyLabel,
            generatedAt: Date()
        )
    }

    private func responseContent(
        for pattern: SafetyPattern,
        level: EscalationLevel
    ) -> (scripture: String, prompt: String, message: String?, action: EscalationResponse.SuggestedSafetyAction?) {
        switch pattern {
        // Burnout
        case .spiritualExhaustion, .obligationOverJoy:
            return (
                "Matthew 11:28-30 — Come to me, all who are weary and burdened.",
                "The user shows signs of spiritual burnout. Do NOT push harder. Offer rest, grace, and remind them that God's love is not earned. Break the performance cycle gently.",
                "It's okay to rest. God's love for you doesn't depend on your output.",
                .suggestRest
            )

        case .performanceFaith, .comparisonDespair:
            return (
                "Ephesians 2:8-9 — By grace you have been saved through faith, not by works.",
                "The user is trapped in performance-driven faith. Redirect to grace. Do not give more tasks or challenges. Affirm their worth in Christ apart from performance.",
                "Your worth isn't measured by your spiritual performance. You are loved as you are.",
                .suggestRest
            )

        // Shame loops
        case .selfCondemnation:
            return (
                "Romans 8:1 — There is now no condemnation for those who are in Christ.",
                "The user is in a self-condemnation loop. BREAK THE CYCLE. Do not agree with their self-assessment. Redirect firmly to grace. Distinguish conviction from condemnation.",
                nil,
                nil
            )

        case .scrupulosity:
            return (
                "1 John 1:9 — If we confess our sins, He is faithful and just to forgive us.",
                "The user may be experiencing scrupulosity (obsessive religious guilt). Be very gentle. Affirm that God's forgiveness is complete. Do not explore whether their fear is valid — reassure with Scripture. Consider suggesting they speak with a pastor or counselor.",
                "This kind of persistent guilt can be overwhelming. A pastor or counselor could help you work through this in person.",
                .suggestPastor
            )

        case .repeatedConfession:
            return (
                "Psalm 103:12 — As far as the east is from the west, so far has He removed our transgressions.",
                "The user has confessed this struggle multiple times. Do not just repeat forgiveness — help them understand the difference between struggling and identity. Suggest practical accountability.",
                nil,
                .suggestTrustedPerson
            )

        case .identityInSin:
            return (
                "2 Corinthians 5:17 — If anyone is in Christ, the new creation has come.",
                "The user is confusing their identity with their sin. Firmly but lovingly distinguish between 'I struggle with X' and 'I am X'. Ground their identity in Christ, not behavior.",
                nil,
                nil
            )

        // Isolation
        case .socialWithdrawal:
            return (
                "Hebrews 10:24-25 — Let us not neglect meeting together.",
                "The user is withdrawing from community. Don't force — gently explore why. Suggest low-pressure connection options.",
                "You don't have to carry this alone. Even one trusted person can make a difference.",
                .suggestCommunityGroup
            )

        case .trustErosion:
            return (
                "Psalm 34:18 — The Lord is close to the brokenhearted.",
                "The user has trust issues, possibly from church hurt. Validate their pain first. Do NOT defend the church or minimize their experience. Then gently point to God's trustworthiness.",
                nil,
                nil
            )

        case .secretKeeping:
            return (
                "James 5:16 — Confess your sins to each other and pray for each other so that you may be healed.",
                "The user is carrying a secret. Validate the courage it took to share here. Gently encourage finding one safe person to talk to in real life.",
                nil,
                .suggestTrustedPerson
            )

        case .communityRejection:
            return (
                "Psalm 147:3 — He heals the brokenhearted and binds up their wounds.",
                "The user has experienced church hurt. Acknowledge the pain without dismissing it. Help them separate the actions of people from the character of God. Don't rush to suggest a new church.",
                nil,
                nil
            )

        // Acute distress
        case .hopelessness:
            return (
                "Jeremiah 29:11 — 'For I know the plans I have for you,' declares the Lord.",
                "The user expresses hopelessness. Lead with empathy. Offer presence. Gently remind of God's faithfulness. If hopelessness deepens, suggest real-world support.",
                "What you're feeling is real, and it matters. You're not alone in this.",
                .suggestProfessionalHelp
            )

        case .selfHarmLanguage:
            return (
                "Psalm 139:13-14 — You are fearfully and wonderfully made.",
                "SAFETY CRITICAL: The user has expressed self-harm. Respond with immediate care. Surface crisis resources. Do not try to counsel — redirect to professional help.",
                BereanSafetyPolicy.refusal(for: .selfHarm),
                .suggestCrisisLine
            )

        case .suicidalIdeation:
            return (
                "Psalm 139:13-14 — You are fearfully and wonderfully made.",
                "SAFETY CRITICAL: The user has expressed suicidal thoughts. Respond with immediate care. Surface crisis resources immediately. This is the highest priority.",
                BereanSafetyPolicy.refusal(for: .selfHarm),
                .suggestCrisisLine
            )
        }
    }

    // MARK: - System Prompt Injection

    /// Returns the safety-aware system prompt injection for Berean.
    func systemPromptInjection() -> String {
        guard let escalation = currentEscalation else { return "" }

        var lines: [String] = []
        lines.append("--- Safety Context (Confidential) ---")
        lines.append("Detected pattern: \(escalation.pattern.rawValue)")
        lines.append("Escalation level: \(escalation.level.displayName)")
        lines.append("")
        lines.append(escalation.bereanPromptInjection)
        lines.append("")
        lines.append("Comfort scripture: \(escalation.scriptureComfort)")
        lines.append("--- End Safety Context ---")

        return lines.joined(separator: "\n")
    }

    // MARK: - Transparency Layer

    /// Returns a user-facing explanation of why Berean made a particular suggestion.
    /// This builds trust by being transparent about pattern detection.
    func transparencyExplanation() -> String? {
        guard let escalation = currentEscalation else { return nil }

        return """
            Why Berean suggested this: \(escalation.transparencyNote). \
            This is based on patterns in our recent conversation, not stored personal data. \
            You can disable these suggestions in Settings.
            """
    }

    // MARK: - Signal Management

    private func addSignal(_ pattern: SafetyPattern, confidence: Double) {
        signals.append(DetectionSignal(
            pattern: pattern,
            confidence: min(1.0, max(0.0, confidence)),
            timestamp: Date()
        ))

        if signals.count > maxSignals {
            signals = Array(signals.suffix(maxSignals))
        }
    }

    /// Clears the current escalation state.
    func clearEscalation() {
        currentEscalation = nil
        currentLevel = .none
    }

    func reset() {
        signals.removeAll()
        currentEscalation = nil
        currentLevel = .none
    }
}
