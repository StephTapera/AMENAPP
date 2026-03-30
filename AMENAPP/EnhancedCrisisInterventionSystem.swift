// EnhancedCrisisInterventionSystem.swift
// AMENAPP
//
// Enhanced Crisis & Intervention System
//
// Detects and responds to:
//   - Depression patterns (persistent low mood)
//   - Isolation indicators (withdrawing from community)
//   - Harm signals (self-harm, suicidal ideation)
//   - Addiction loops (compulsive behavior patterns)
//   - Grief patterns (loss, mourning)
//
// Hard rules:
//   - NEVER replace human help
//   - ALWAYS escalate to real-world support
//   - Conservative detection (false negatives >> false positives)
//   - No data leaves device without explicit consent
//
// Integrates with:
//   - CrisisDetectionService (existing)
//   - LifePatternIntelligence (behavioral signals)
//   - BehavioralAwarenessEngine (session signals)
//
// Entry points:
//   EnhancedCrisisInterventionSystem.shared.assessRisk(from:) -> CrisisAssessment
//   EnhancedCrisisInterventionSystem.shared.getInterventionResponse(for:) async -> InterventionResponse

import Foundation
import SwiftUI
import Combine

// MARK: - Models

/// Risk assessment result
struct CrisisAssessment {
    let level: CrisisLevel
    let confidence: Double          // 0.0-1.0
    let signals: [CrisisSignal]
    let timestamp: Date
    let requiresImmediate: Bool

    var shouldIntervene: Bool {
        level.severity >= 2 && confidence > 0.5
    }
}

enum CrisisLevel: String {
    case none = "none"
    case mild = "mild"              // Low-level concern, monitor
    case moderate = "moderate"      // Noticeable pattern, offer support
    case elevated = "elevated"      // Clear concern, proactive intervention
    case critical = "critical"      // Immediate support needed

    var severity: Int {
        switch self {
        case .none: return 0
        case .mild: return 1
        case .moderate: return 2
        case .elevated: return 3
        case .critical: return 4
        }
    }
}

struct CrisisSignal {
    let type: CrisisSignalType
    let evidence: String
    let weight: Double
}

enum CrisisSignalType: String {
    case suicidalIdeation = "suicidal_ideation"
    case selfHarm = "self_harm"
    case hopelessness = "hopelessness"
    case isolation = "isolation"
    case substanceUse = "substance_use"
    case domesticAbuse = "domestic_abuse"
    case griefOverload = "grief_overload"
    case severeAnxiety = "severe_anxiety"
    case panicIndicators = "panic"
}

/// The intervention response shown to user
struct InterventionResponse: Identifiable {
    let id = UUID()
    let level: CrisisLevel
    let message: String             // Warm, non-clinical message
    let groundingPrompt: String?    // Breathing/grounding exercise
    let scriptureComfort: String?   // Comforting verse
    let resources: [CrisisResource]
    let suggestedActions: [String]
    let humanBoundaryMessage: String // "This does not replace..."
}

struct CrisisResource: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let phone: String?
    let textLine: String?
    let isEmergency: Bool
}

// MARK: - EnhancedCrisisInterventionSystem

@MainActor
final class EnhancedCrisisInterventionSystem: ObservableObject {

    static let shared = EnhancedCrisisInterventionSystem()

    @Published var currentAssessment: CrisisAssessment?
    @Published var activeIntervention: InterventionResponse?
    @Published var isAssessing = false

    private let aiService = ClaudeService.shared

    // Crisis keywords (conservative — high specificity)
    private let criticalKeywords = [
        "kill myself", "end my life", "don't want to live",
        "suicide", "suicidal", "want to die", "better off dead",
        "no reason to live", "end it all"
    ]

    private let elevatedKeywords = [
        "self-harm", "cutting", "hurting myself",
        "can't go on", "giving up", "no hope",
        "nobody cares", "alone forever", "worthless"
    ]

    private let moderateKeywords = [
        "depressed", "hopeless", "can't cope",
        "overwhelmed", "breaking down", "falling apart",
        "addiction", "relapse", "abusive", "being hurt"
    ]

    // Standard resources
    private let emergencyResources: [CrisisResource] = [
        CrisisResource(
            name: "988 Suicide & Crisis Lifeline",
            description: "Free, confidential 24/7 support",
            phone: "988",
            textLine: "Text 988",
            isEmergency: true
        ),
        CrisisResource(
            name: "Crisis Text Line",
            description: "Text HOME to 741741",
            phone: nil,
            textLine: "741741",
            isEmergency: true
        ),
        CrisisResource(
            name: "National Domestic Violence Hotline",
            description: "24/7 confidential support",
            phone: "1-800-799-7233",
            textLine: "Text START to 88788",
            isEmergency: true
        ),
        CrisisResource(
            name: "SAMHSA National Helpline",
            description: "Substance abuse & mental health",
            phone: "1-800-662-4357",
            textLine: nil,
            isEmergency: false
        )
    ]

    private init() {}

    // MARK: - Risk Assessment

    /// Assess crisis risk from text content
    func assessRisk(from text: String) -> CrisisAssessment {
        let lower = text.lowercased()
        var signals: [CrisisSignal] = []
        var maxLevel = CrisisLevel.none

        // Check critical keywords
        for keyword in criticalKeywords {
            if lower.contains(keyword) {
                signals.append(CrisisSignal(
                    type: .suicidalIdeation,
                    evidence: keyword,
                    weight: 1.0
                ))
                maxLevel = .critical
            }
        }

        // Check elevated keywords
        if maxLevel != .critical {
            for keyword in elevatedKeywords {
                if lower.contains(keyword) {
                    signals.append(CrisisSignal(
                        type: keyword.contains("harm") || keyword.contains("cutting") ? .selfHarm : .hopelessness,
                        evidence: keyword,
                        weight: 0.7
                    ))
                    if maxLevel.severity < CrisisLevel.elevated.severity {
                        maxLevel = .elevated
                    }
                }
            }
        }

        // Check moderate keywords
        if maxLevel.severity < CrisisLevel.moderate.severity {
            for keyword in moderateKeywords {
                if lower.contains(keyword) {
                    let type: CrisisSignalType =
                        keyword.contains("addict") || keyword.contains("relapse") ? .substanceUse :
                        keyword.contains("abus") || keyword.contains("hurt") ? .domesticAbuse :
                        .severeAnxiety

                    signals.append(CrisisSignal(
                        type: type,
                        evidence: keyword,
                        weight: 0.5
                    ))
                    maxLevel = .moderate
                }
            }
        }

        // Integrate behavioral signals
        let patternState = LifePatternIntelligence.shared.getSpiritualState()
        if patternState.primary == .crisis {
            maxLevel = max(maxLevel, .elevated)
        }

        let confidence = signals.isEmpty ? 0.0 : min(signals.reduce(0) { $0 + $1.weight } / Double(signals.count), 1.0)

        let assessment = CrisisAssessment(
            level: maxLevel,
            confidence: confidence,
            signals: signals,
            timestamp: Date(),
            requiresImmediate: maxLevel == .critical
        )

        currentAssessment = assessment
        return assessment
    }

    // MARK: - Intervention Response

    /// Get appropriate intervention response for a crisis level
    func getInterventionResponse(for assessment: CrisisAssessment) async -> InterventionResponse {
        let message: String
        let grounding: String?
        let scripture: String?
        let resources: [CrisisResource]
        let actions: [String]

        switch assessment.level {
        case .critical:
            message = "I hear you, and I want you to know that your life matters deeply. What you're feeling right now is real, but it doesn't have to be permanent. Please reach out to someone who can help right now."
            grounding = "Take a slow breath with me. Breathe in for 4 counts... hold for 4... out for 4. You're here. You matter."
            scripture = "\"The Lord is close to the brokenhearted and saves those who are crushed in spirit.\" — Psalm 34:18"
            resources = emergencyResources.filter { $0.isEmergency }
            actions = ["Call 988 now", "Text a trusted friend", "Go to your nearest ER"]

        case .elevated:
            message = "It sounds like you're going through something really hard. You don't have to carry this alone. Would you be open to talking to someone who can help?"
            grounding = "Take a moment. Place your feet on the floor. Feel the ground beneath you. You are held."
            scripture = "\"Cast all your anxiety on him because he cares for you.\" — 1 Peter 5:7"
            resources = emergencyResources
            actions = ["Talk to a pastor or counselor", "Reach out to a trusted friend", "Save these resources"]

        case .moderate:
            message = "I can see you're struggling. That takes courage to express. There are people and resources that can help."
            grounding = nil
            scripture = "\"Come to me, all you who are weary and burdened, and I will give you rest.\" — Matthew 11:28"
            resources = emergencyResources.filter { !$0.isEmergency } + [emergencyResources[0]]
            actions = ["Save these resources", "Consider talking to someone you trust"]

        case .mild:
            message = "It seems like things are weighing on you. Remember, it's okay to not be okay — and it's wise to seek help."
            grounding = nil
            scripture = "\"God is our refuge and strength, an ever-present help in trouble.\" — Psalm 46:1"
            resources = []
            actions = ["Explore the Resources hub", "Pray about what you're feeling"]

        case .none:
            message = ""
            grounding = nil
            scripture = nil
            resources = []
            actions = []
        }

        let response = InterventionResponse(
            level: assessment.level,
            message: message,
            groundingPrompt: grounding,
            scriptureComfort: scripture,
            resources: resources,
            suggestedActions: actions,
            humanBoundaryMessage: "Berean AI is not a substitute for professional counseling, therapy, or emergency services. If you or someone you know is in danger, please contact emergency services (911) or the 988 Suicide & Crisis Lifeline immediately."
        )

        activeIntervention = response
        return response
    }

    // MARK: - Berean Message Safety Check

    /// Quick check if a Berean conversation message needs crisis intervention
    func checkMessage(_ message: String) async -> InterventionResponse? {
        let assessment = assessRisk(from: message)
        guard assessment.shouldIntervene else { return nil }
        return await getInterventionResponse(for: assessment)
    }

    // MARK: - Helpers

    private func max(_ a: CrisisLevel, _ b: CrisisLevel) -> CrisisLevel {
        a.severity >= b.severity ? a : b
    }
}

// MARK: - Crisis Intervention View

struct CrisisInterventionView: View {
    let intervention: InterventionResponse
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Warm message
                Text(intervention.message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding()

                // Grounding exercise
                if let grounding = intervention.groundingPrompt {
                    VStack(spacing: 8) {
                        Image(systemName: "wind")
                            .font(.title)
                            .foregroundStyle(.teal)
                        Text(grounding)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(.teal.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                // Scripture comfort
                if let scripture = intervention.scriptureComfort {
                    Text(scripture)
                        .font(.subheadline)
                        .italic()
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.purple.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Resources
                if !intervention.resources.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Help is Available")
                            .font(.headline)

                        ForEach(intervention.resources) { resource in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    if resource.isEmergency {
                                        Image(systemName: "phone.fill")
                                            .foregroundStyle(.red)
                                    }
                                    Text(resource.name)
                                        .font(.subheadline.bold())
                                }
                                Text(resource.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 12) {
                                    if let phone = resource.phone {
                                        Button {
                                            if let url = URL(string: "tel:\(phone)") {
                                                openURL(url)
                                            }
                                        } label: {
                                            Label("Call \(phone)", systemImage: "phone.fill")
                                                .font(.caption.bold())
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(.green.gradient)
                                                .foregroundStyle(.white)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    if let textLine = resource.textLine {
                                        Text("Text: \(textLine)")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                // Human boundary
                Text(intervention.humanBoundaryMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .padding()
        }
    }
}
