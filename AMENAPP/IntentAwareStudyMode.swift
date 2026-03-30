// IntentAwareStudyMode.swift
// AMENAPP
//
// Intent-Aware Study Mode + Explanation Mode Toggle
//
// Detects WHY the user is studying and adapts output:
//   - Curiosity → simple explanation
//   - Deep study → theological breakdown
//   - Struggle → pastoral guidance
//   - Teaching → structured outline
//
// Explanation modes (user-selectable):
//   - Pastor → practical, encouraging
//   - Scholar → deep, structured, original language
//   - Friend → simple, relatable
//   - Coach → action-oriented
//
// Entry points:
//   IntentAwareStudyMode.shared.detectIntent(from:) -> StudyIntent
//   IntentAwareStudyMode.shared.buildSystemPrompt(intent:mode:) -> String
//   IntentAwareStudyMode.shared.currentMode (user toggle)

import Foundation
import SwiftUI
import Combine

// MARK: - Study Intent

/// Detected reason for studying
enum StudyIntent: String, Codable, CaseIterable {
    case curiosity = "curiosity"            // "What does this mean?"
    case deepStudy = "deep_study"           // "Explain the theology of..."
    case struggle = "struggle"              // "I'm struggling with..."
    case teaching = "teaching"              // "I need to teach about..."
    case devotion = "devotion"              // "Help me meditate on..."
    case apologetics = "apologetics"        // "How do I answer..."
    case application = "application"        // "How do I apply..."
    case comparison = "comparison"          // "What's the difference between..."

    var displayName: String {
        switch self {
        case .curiosity: return "Curious"
        case .deepStudy: return "Deep Study"
        case .struggle: return "Seeking Help"
        case .teaching: return "Preparing to Teach"
        case .devotion: return "Devotional"
        case .apologetics: return "Apologetics"
        case .application: return "Life Application"
        case .comparison: return "Comparing Ideas"
        }
    }

    var icon: String {
        switch self {
        case .curiosity: return "questionmark.circle"
        case .deepStudy: return "book.closed.fill"
        case .struggle: return "heart.fill"
        case .teaching: return "person.fill.badge.plus"
        case .devotion: return "sun.max.fill"
        case .apologetics: return "shield.fill"
        case .application: return "hammer.fill"
        case .comparison: return "arrow.left.arrow.right"
        }
    }
}

// MARK: - Explanation Mode

/// User-selectable explanation tone/depth
enum ExplanationMode: String, Codable, CaseIterable {
    case pastor = "pastor"
    case scholar = "scholar"
    case friend = "friend"
    case coach = "coach"

    var displayName: String {
        switch self {
        case .pastor: return "Pastor"
        case .scholar: return "Scholar"
        case .friend: return "Friend"
        case .coach: return "Coach"
        }
    }

    var description: String {
        switch self {
        case .pastor: return "Practical, encouraging, pastoral"
        case .scholar: return "Deep, structured, original language"
        case .friend: return "Simple, relatable, casual"
        case .coach: return "Action-oriented, challenging"
        }
    }

    var icon: String {
        switch self {
        case .pastor: return "person.fill"
        case .scholar: return "graduationcap.fill"
        case .friend: return "face.smiling.fill"
        case .coach: return "figure.run"
        }
    }

    var systemPromptBlock: String {
        switch self {
        case .pastor:
            return """
            Respond as a warm, experienced pastor would. Be:
            - Practical and applicable to daily life
            - Encouraging but honest
            - Use relatable examples
            - End with hope and direction
            - Keep theological language accessible
            """
        case .scholar:
            return """
            Respond as a careful biblical scholar would. Be:
            - Detailed and precise
            - Reference original languages (Greek/Hebrew) when relevant
            - Cite historical and textual context
            - Note scholarly consensus and debates
            - Use structured, logical reasoning
            - Include relevant cross-references
            """
        case .friend:
            return """
            Respond as a trusted friend who knows the Bible well. Be:
            - Casual and conversational
            - Use simple language, no jargon
            - Share like you're having coffee together
            - Be real and relatable
            - Keep it brief unless they ask for more
            """
        case .coach:
            return """
            Respond as a spiritual coach/mentor would. Be:
            - Direct and action-oriented
            - Focus on what to DO, not just what to know
            - Challenge them appropriately
            - Set clear next steps
            - Hold them to a high standard with grace
            - Ask probing questions
            """
        }
    }
}

// MARK: - IntentAwareStudyMode

@MainActor
final class IntentAwareStudyMode: ObservableObject {

    static let shared = IntentAwareStudyMode()

    /// Current user-selected explanation mode
    @Published var currentMode: ExplanationMode {
        didSet {
            UserDefaults.standard.set(currentMode.rawValue, forKey: "berean_explanation_mode")
        }
    }

    /// Last detected intent
    @Published var detectedIntent: StudyIntent = .curiosity

    /// Whether to auto-detect intent
    @Published var autoDetectIntent: Bool {
        didSet {
            UserDefaults.standard.set(autoDetectIntent, forKey: "berean_auto_detect_intent")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "berean_explanation_mode") ?? "pastor"
        currentMode = ExplanationMode(rawValue: saved) ?? .pastor
        autoDetectIntent = UserDefaults.standard.object(forKey: "berean_auto_detect_intent") as? Bool ?? true
    }

    // MARK: - Intent Detection

    /// Detect study intent from user's message
    func detectIntent(from message: String) -> StudyIntent {
        let lower = message.lowercased()

        // Struggle detection (highest priority)
        let struggleWords = ["struggling", "help me", "i'm hurting", "afraid", "anxious", "worried", "lost", "confused about my", "don't know what to do", "pray for"]
        if struggleWords.contains(where: { lower.contains($0) }) {
            detectedIntent = .struggle
            return .struggle
        }

        // Teaching detection
        let teachingWords = ["teaching about", "sermon on", "lesson about", "how to explain", "i need to teach", "leading a study"]
        if teachingWords.contains(where: { lower.contains($0) }) {
            detectedIntent = .teaching
            return .teaching
        }

        // Deep study detection
        let deepStudyWords = ["theology of", "exegesis", "hermeneutic", "greek word", "hebrew word", "original language", "systematic", "doctrine of", "explain the theology"]
        if deepStudyWords.contains(where: { lower.contains($0) }) {
            detectedIntent = .deepStudy
            return .deepStudy
        }

        // Application detection
        let applicationWords = ["how do i apply", "what should i do", "how to live", "practical steps", "apply this"]
        if applicationWords.contains(where: { lower.contains($0) }) {
            detectedIntent = .application
            return .application
        }

        // Devotion detection
        let devotionWords = ["meditate", "devotional", "reflect on", "quiet time", "morning reading", "spend time with"]
        if devotionWords.contains(where: { lower.contains($0) }) {
            detectedIntent = .devotion
            return .devotion
        }

        // Apologetics detection
        let apologeticsWords = ["how do i answer", "defend", "someone asked me", "challenge to", "argue that", "respond to"]
        if apologeticsWords.contains(where: { lower.contains($0) }) {
            detectedIntent = .apologetics
            return .apologetics
        }

        // Comparison detection
        let comparisonWords = ["difference between", "compare", "vs", "versus", "how does.*differ", "contrast"]
        if comparisonWords.contains(where: { lower.contains($0) }) {
            detectedIntent = .comparison
            return .comparison
        }

        // Default: curiosity
        detectedIntent = .curiosity
        return .curiosity
    }

    // MARK: - System Prompt Building

    /// Build a complete system prompt block based on intent + mode
    func buildSystemPrompt(intent: StudyIntent? = nil, mode: ExplanationMode? = nil) -> String {
        let activeIntent = intent ?? detectedIntent
        let activeMode = mode ?? currentMode

        var prompt = activeMode.systemPromptBlock + "\n\n"

        // Add intent-specific instructions
        switch activeIntent {
        case .curiosity:
            prompt += """
            The user is curious and exploring. Keep answers clear and inviting.
            Offer to go deeper if they want. Don't overwhelm with detail.
            """
        case .deepStudy:
            prompt += """
            The user wants depth. Include:
            - Original language analysis
            - Historical-grammatical context
            - Cross-references
            - Theological implications
            Don't simplify — they want the full picture.
            """
        case .struggle:
            prompt += """
            IMPORTANT: The user may be hurting. Lead with empathy.
            - Acknowledge their feelings first
            - Then offer biblical comfort
            - Be gentle with correction
            - Offer hope and practical next steps
            - Suggest they talk to someone in real life if appropriate
            """
        case .teaching:
            prompt += """
            The user is preparing to teach. Provide:
            - Structured outline format
            - Key points with supporting scriptures
            - Common questions/objections
            - Application points for their audience
            - Illustrations they can use
            """
        case .devotion:
            prompt += """
            The user is in devotional/meditative mode. Be:
            - Reflective and contemplative
            - Guide them to encounter God, not just learn about Him
            - Include prompts for personal reflection
            - Suggest prayers
            - Keep the pace slow and thoughtful
            """
        case .apologetics:
            prompt += """
            The user needs to defend or explain their faith. Provide:
            - Clear logical arguments
            - Evidence and reasoning
            - Common objections and responses
            - Scriptural backing
            - Gracious tone (truth AND love)
            """
        case .application:
            prompt += """
            The user wants practical application. Focus on:
            - Specific, concrete actions
            - Real-life scenarios
            - Step-by-step guidance
            - Potential obstacles and how to overcome them
            """
        case .comparison:
            prompt += """
            The user wants to compare concepts. Provide:
            - Clear side-by-side analysis
            - Key similarities and differences
            - Biblical basis for each position
            - Practical implications of the differences
            """
        }

        return prompt
    }
}

// MARK: - Explanation Mode Toggle View (Liquid Glass Pills)

struct ExplanationModeToggle: View {
    @ObservedObject var studyMode = IntentAwareStudyMode.shared
    @Namespace private var modeAnimation

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExplanationMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            studyMode.currentMode = mode
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.caption)
                            Text(mode.displayName)
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if studyMode.currentMode == mode {
                                Capsule()
                                    .fill(.blue.gradient)
                                    .matchedGeometryEffect(id: "modeBackground", in: modeAnimation)
                            } else {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            }
                        }
                        .foregroundStyle(studyMode.currentMode == mode ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Intent Badge View

struct IntentBadgeView: View {
    let intent: StudyIntent

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: intent.icon)
                .font(.caption2)
            Text(intent.displayName)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
}
