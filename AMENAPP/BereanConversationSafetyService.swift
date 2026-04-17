// BereanConversationSafetyService.swift
// AMENAPP
//
// Graduated intervention system: soft awareness → friction → boundary
// Evaluates sliding window of last 5-10 messages for risk signals.
// Never hard-blocks first — always graduated.

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Risk Level

enum ConversationRiskLevel: Int, Comparable {
    case safe     = 0
    case mild     = 1   // soft pill awareness
    case moderate = 2   // typing delay friction (200-400ms)
    case elevated = 3   // boundary prompt with options
    case critical = 4   // hard redirect required

    static func < (lhs: ConversationRiskLevel, rhs: ConversationRiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Risk Signals

struct ConversationRiskSignals {
    var sexualIntentScore: Double = 0         // 0.0 – 1.0
    var aggressionScore: Double = 0
    var manipulationScore: Double = 0
    var escalationVelocity: Double = 0        // how fast risk is growing
    var isReciprocated: Bool = true           // is the conversation mutual
    var relationshipTrustScore: Double = 1.0  // 0.0 – 1.0, based on mutual follows/history
    var lateNightRisk: Bool = false           // past 10 pm
    var rapidBurstCount: Int = 0             // messages sent within 30 s

    var computedLevel: ConversationRiskLevel {
        let combined = (sexualIntentScore  * 0.4)
                     + (aggressionScore    * 0.3)
                     + (manipulationScore  * 0.2)
                     + (escalationVelocity * 0.1)
        let boost  = (!isReciprocated ? 0.15 : 0.0)
                   + (lateNightRisk   ? 0.10 : 0.0)
        let total  = min(combined + boost, 1.0)
        switch total {
        case ..<0.15:        return .safe
        case 0.15..<0.35:    return .mild
        case 0.35..<0.55:    return .moderate
        case 0.55..<0.75:    return .elevated
        default:             return .critical
        }
    }
}

// MARK: - Safety Intervention

struct SafetyIntervention {
    let level: ConversationRiskLevel
    let message: String
    let scripture: String?
    let options: [SafetyOption]

    struct SafetyOption: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let action: SafetyAction

        enum SafetyAction {
            case dismiss
            case redirectConversation
            case pauseChat(minutes: Int)
            case sendBoundaryMessage(String)
            case continueLogged
            case restrictSender
        }
    }
}

// MARK: - Local Heuristics Keywords

private struct LocalHeuristicsKeywords {
    // Sexual intent phrases — conservative, only clear violations
    static let sexualIntent: Set<String> = [
        "send pics", "send nudes", "you're so hot", "you're sexy",
        "what are you wearing", "let's hook up", "come over tonight",
        "you turn me on", "i want you", "thinking about you at night",
        "are you alone", "facetime tonight", "late night?", "body goals",
        "slide in", "dtf", "no strings", "friends with benefits"
    ]

    // Aggression words
    static let aggression: Set<String> = [
        "you're stupid", "you're an idiot", "shut up", "i hate you",
        "you're worthless", "go to hell", "you're trash", "i'll hurt you",
        "you're pathetic", "nobody likes you", "you're ugly", "loser",
        "you make me sick", "i'll tell everyone"
    ]

    // Manipulation patterns
    static let manipulation: Set<String> = [
        "if you loved me", "you owe me", "after everything i've done",
        "no one else will", "don't tell anyone", "this is our secret",
        "you'll regret this", "i'll leave if you don't", "just this once",
        "you're overreacting", "stop being dramatic", "you know you want to",
        "prove it", "trust me on this"
    ]

    // Excessive flattery / grooming signals
    static let excessiveFlattery: Set<String> = [
        "you're perfect", "you're the only one who understands me",
        "i've never felt this way", "you're not like the others",
        "destiny brought us together", "i need you"
    ]
}

// MARK: - Service

@MainActor
final class BereanConversationSafetyService: ObservableObject {

    static let shared = BereanConversationSafetyService()

    @Published var currentRisk: ConversationRiskLevel = .safe
    @Published var activeIntervention: SafetyIntervention? = nil
    @Published var typingDelayMs: Int = 0  // 0 = no delay

    // Sliding window: last 10 messages for context
    private var messageWindow: [String] = []

    // Timestamps for rapid-burst detection
    private var recentSendTimestamps: [Date] = []

    private lazy var db = Firestore.firestore()

    private init() {}

    // MARK: - Core Analysis

    /// Analyze a message about to be sent. Returns true if send should proceed, false if blocked.
    func analyzePendingMessage(
        _ text: String,
        in conversationId: String,
        signals: ConversationRiskSignals
    ) async -> Bool {

        // 1. Update sliding window (keep last 10)
        messageWindow.append(text)
        if messageWindow.count > 10 { messageWindow.removeFirst() }

        // 2. Local heuristic score (fast, no AI)
        var localScore = localRiskScore(text: text)

        // 3. Rapid-burst detection
        let now = Date()
        recentSendTimestamps.append(now)
        recentSendTimestamps = recentSendTimestamps.filter { now.timeIntervalSince($0) <= 30 }
        if recentSendTimestamps.count >= 5 { localScore = min(localScore + 0.15, 1.0) }

        // 4. Late-night boost
        let hour = Calendar.current.component(.hour, from: now)
        let isLateNight = hour >= 22 || hour < 5

        var updatedSignals = signals
        updatedSignals.lateNightRisk = isLateNight

        // 5. If borderline, call Claude for deeper analysis
        if localScore > 0.3 && localScore < 0.7 {
            updatedSignals = await analyzeConversationContext(messageWindow, signals: updatedSignals)
        } else {
            // Blend local score into the signal set
            updatedSignals.sexualIntentScore  = max(updatedSignals.sexualIntentScore,  localScore * 0.6)
            updatedSignals.aggressionScore    = max(updatedSignals.aggressionScore,    localScore * 0.4)
            updatedSignals.manipulationScore  = max(updatedSignals.manipulationScore,  localScore * 0.3)
        }

        // 6. Update published risk
        let level = updatedSignals.computedLevel
        currentRisk = level

        // 7. Set typing delay
        switch level {
        case .safe, .mild:  typingDelayMs = 0
        case .moderate:     typingDelayMs = 200
        case .elevated:     typingDelayMs = 400
        case .critical:     typingDelayMs = 400
        }

        // 8. Build intervention if needed
        if level >= .mild {
            activeIntervention = buildIntervention(for: level, isRecipient: false)
        }

        dlog("[BereanSafety] risk=\(level) localScore=\(String(format: "%.2f", localScore)) conv=\(conversationId)")

        // Critical always blocks; elevated blocks and shows intervention
        return level < .critical
    }

    /// Analyze full conversation context using Claude .shepherd mode.
    func analyzeConversationContext(
        _ messages: [String],
        signals: ConversationRiskSignals
    ) async -> ConversationRiskSignals {

        guard !messages.isEmpty else { return signals }

        let windowText = messages.suffix(8).enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n")

        let prompt = """
        You are a Christian AI safety evaluator. Analyze this conversation window for risk signals.
        Evaluate conservatively — only flag clear violations of purity, respect, and dignity.

        Conversation:
        \(windowText)

        Respond ONLY as a JSON object with these keys:
        {
          "sexualIntentScore": 0.0,
          "aggressionScore": 0.0,
          "manipulationScore": 0.0,
          "escalationVelocity": 0.0
        }
        All values 0.0–1.0. No explanation.
        """

        do {
            let response = try await ClaudeService.shared.sendMessageSync(prompt, mode: .shepherd)
            if let data = response.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Double] {
                var updated = signals
                updated.sexualIntentScore  = json["sexualIntentScore"]  ?? signals.sexualIntentScore
                updated.aggressionScore    = json["aggressionScore"]    ?? signals.aggressionScore
                updated.manipulationScore  = json["manipulationScore"]  ?? signals.manipulationScore
                updated.escalationVelocity = json["escalationVelocity"] ?? signals.escalationVelocity
                dlog("[BereanSafety] Claude context analysis complete")
                return updated
            }
        } catch {
            dlog("[BereanSafety] Claude analysis error: \(error.localizedDescription)")
        }
        return signals
    }

    // MARK: - Local Heuristics (fast, no AI)

    private func localRiskScore(text: String) -> Double {
        let lower = text.lowercased()
        var score: Double = 0

        let sexualHits = LocalHeuristicsKeywords.sexualIntent.filter { lower.contains($0) }.count
        let aggressHits = LocalHeuristicsKeywords.aggression.filter { lower.contains($0) }.count
        let manipHits   = LocalHeuristicsKeywords.manipulation.filter { lower.contains($0) }.count
        let flatterHits = LocalHeuristicsKeywords.excessiveFlattery.filter { lower.contains($0) }.count

        score += Double(sexualHits)  * 0.25
        score += Double(aggressHits) * 0.20
        score += Double(manipHits)   * 0.18
        score += Double(flatterHits) * 0.10

        return min(score, 1.0)
    }

    // MARK: - Interventions

    func buildIntervention(for level: ConversationRiskLevel, isRecipient: Bool) -> SafetyIntervention {
        switch level {
        case .safe:
            return SafetyIntervention(
                level: .safe,
                message: "This conversation looks respectful.",
                scripture: nil,
                options: [.init(title: "OK", icon: "checkmark.circle", action: .dismiss)]
            )

        case .mild:
            return SafetyIntervention(
                level: .mild,
                message: "Honor one another with purity and respect.",
                scripture: "1 Thessalonians 4:3–5",
                options: [
                    .init(title: "Noted", icon: "hand.thumbsup", action: .dismiss),
                    .init(title: "Keep going", icon: "arrow.right.circle", action: .continueLogged)
                ]
            )

        case .moderate:
            return SafetyIntervention(
                level: .moderate,
                message: "This conversation is moving in a direction that may not honor God or each other. Want to redirect?",
                scripture: "Proverbs 4:23",
                options: [
                    .init(title: "Redirect conversation", icon: "arrow.uturn.left.circle", action: .redirectConversation),
                    .init(title: "Take a pause", icon: "pause.circle", action: .pauseChat(minutes: 5)),
                    .init(title: "Continue (logged)", icon: "eye.circle", action: .continueLogged)
                ]
            )

        case .elevated:
            let boundaryText = "I want to keep our conversation respectful and honoring."
            return SafetyIntervention(
                level: .elevated,
                message: "This conversation is crossing a line. Please choose how to respond.",
                scripture: "Ephesians 5:3",
                options: [
                    .init(title: "Send boundary message", icon: "shield.fill", action: .sendBoundaryMessage(boundaryText)),
                    .init(title: "Pause replies (30 min)", icon: "pause.circle.fill", action: .pauseChat(minutes: 30)),
                    .init(title: "Continue (logged)", icon: "eye.circle", action: .continueLogged),
                    .init(title: "Restrict sender", icon: "person.crop.circle.badge.minus", action: .restrictSender)
                ]
            )

        case .critical:
            return SafetyIntervention(
                level: .critical,
                message: "This conversation needs to stop here. Your dignity and purity are worth protecting.",
                scripture: "1 Corinthians 6:18–20",
                options: [
                    .init(title: "End conversation", icon: "xmark.circle.fill", action: .redirectConversation),
                    .init(title: "Restrict sender", icon: "person.crop.circle.badge.minus", action: .restrictSender)
                ]
            )
        }
    }

    // MARK: - Typing Delay

    func sendDelay() async {
        guard typingDelayMs > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(typingDelayMs) * 1_000_000)
    }

    // MARK: - Conflict De-escalation

    /// Returns a de-escalation rewrite suggestion if aggression is detected, otherwise nil.
    func detectConflict(userTyping: String, recentMessages: [String]) -> String? {
        let lower = userTyping.lowercased()
        let aggressHits = LocalHeuristicsKeywords.aggression.filter { lower.contains($0) }
        guard !aggressHits.isEmpty else { return nil }

        // Simple local rewrites for common patterns
        var rewrite = userTyping
        let rewrites: [String: String] = [
            "you're stupid":    "I disagree, but I want to understand your perspective.",
            "you're an idiot":  "I'm frustrated right now. Can we talk about this calmly?",
            "shut up":          "I need a moment before we continue this conversation.",
            "i hate you":       "I'm really hurt right now and need space.",
            "you're worthless": "I'm struggling to communicate well right now.",
            "go to hell":       "I need to step away from this conversation.",
            "you're trash":     "I don't think this conversation is going well.",
            "you're pathetic":  "I'm finding this hard to discuss right now.",
            "nobody likes you": "I'm saying things I don't mean. Let me try again."
        ]

        for (phrase, replacement) in rewrites {
            if lower.contains(phrase) {
                rewrite = replacement
                break
            }
        }

        return rewrite == userTyping ? nil : rewrite
    }

    /// Generate a calm rewrite using Claude .shepherd mode.
    func generateCalmRewrite(_ aggressiveText: String) async -> String {
        let prompt = """
        Rewrite this message in a calm, respectful, Christ-like tone.
        Keep the core meaning but remove aggression, contempt, or hurtful language.
        Return ONLY the rewritten message — no explanation.

        Original: \(aggressiveText)
        """
        do {
            let result = try await ClaudeService.shared.sendMessageSync(prompt, mode: .shepherd)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            dlog("[BereanSafety] Rewrite error: \(error.localizedDescription)")
            return aggressiveText
        }
    }

    // MARK: - Dismiss / Reset

    func dismissIntervention() {
        activeIntervention = nil
    }

    func resetRisk() {
        currentRisk = .safe
        activeIntervention = nil
        typingDelayMs = 0
        messageWindow.removeAll()
    }
}
