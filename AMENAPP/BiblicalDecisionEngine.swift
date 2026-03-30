// BiblicalDecisionEngine.swift
// AMENAPP
//
// Biblical Decision Engine: Faith + Real Life
//
// User asks anything (business, relationships, career) →
// Berean answers with biblical grounding.
//
// Structure:
//   Step 1: Understand intent (decision, confusion, strategy)
//   Step 2: Map to biblical principles
//   Step 3: Provide wisdom, practical steps, risks/guardrails
//
// Not preachy → applied biblical intelligence.
//
// Entry points:
//   BiblicalDecisionEngine.shared.analyze(question:) async -> DecisionAnalysis
//   BiblicalDecisionEngine.shared.testThought(_ thought:) async -> DiscernmentResult

import Foundation
import SwiftUI
import Combine

// MARK: - Models

/// Complete biblical decision analysis
struct DecisionAnalysis: Identifiable, Codable {
    let id: String
    let question: String
    let timestamp: Date

    // Understanding
    let intentType: IntentType
    let emotionalState: String?     // Detected emotional context

    // Biblical grounding
    let principles: [BiblicalPrinciple]
    let relevantScriptures: [ScriptureWithApplication]

    // Practical output
    let wisdom: String              // Core wisdom
    let practicalSteps: [PracticalStep]
    let risks: [DecisionRisk]
    let guardrails: [String]        // Boundaries to maintain

    // Summary
    let summary: String
    let prayerPrompt: String?
}

enum IntentType: String, Codable {
    case decision = "decision"          // "Should I...?"
    case confusion = "confusion"        // "I don't understand..."
    case strategy = "strategy"          // "How do I...?"
    case conflict = "conflict"          // "I'm struggling with..."
    case affirmation = "affirmation"    // "Is it okay to...?"
    case direction = "direction"        // "What should I do about...?"
}

struct BiblicalPrinciple: Codable, Identifiable {
    var id: String { principle }
    let principle: String           // The principle name
    let description: String         // What it means
    let scriptureRef: String        // Supporting verse
    let applicationToSituation: String // How it applies HERE
}

struct ScriptureWithApplication: Codable, Identifiable {
    var id: String { reference }
    let reference: String
    let text: String
    let whyItApplies: String
}

struct PracticalStep: Codable, Identifiable {
    let id: String
    let step: String
    let timeframe: String           // "immediate", "this week", "ongoing"
    let reasoning: String           // Why this step matters
}

struct DecisionRisk: Codable, Identifiable {
    var id: String { risk }
    let risk: String
    let severity: String            // "low", "medium", "high"
    let mitigation: String          // How to guard against it
    let scriptureWarning: String?   // Biblical warning
}

/// Result of "Test This Thought" engine
struct DiscernmentResult: Identifiable, Codable {
    let id: String
    let thought: String
    let timestamp: Date

    let alignment: AlignmentScore
    let supportingScriptures: [String]
    let warningScriptures: [String]
    let analysis: String
    let balancedGuidance: String
    let verdict: String             // Clear but nuanced assessment
}

struct AlignmentScore: Codable {
    let score: Double               // 0.0 (misaligned) - 1.0 (aligned)
    let confidence: Double          // How confident in the assessment
    let explanation: String
}

// MARK: - BiblicalDecisionEngine

@MainActor
final class BiblicalDecisionEngine: ObservableObject {

    static let shared = BiblicalDecisionEngine()

    @Published var isAnalyzing = false
    @Published var currentAnalysis: DecisionAnalysis?
    @Published var currentDiscernment: DiscernmentResult?

    private let aiService = ClaudeService.shared

    private init() {}

    // MARK: - Decision Analysis

    /// Analyze a life question with biblical grounding
    func analyze(question: String) async -> DecisionAnalysis? {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let userContext = await BereanUserContext.shared.getContextBlock()

        let prompt = """
        A user is seeking biblical wisdom for a real-life decision. Analyze their question and provide grounded, practical guidance.

        Question: \(question)

        User context: \(userContext)

        Return as JSON:
        {
            "id": "\(UUID().uuidString)",
            "question": "\(question.replacingOccurrences(of: "\"", with: "\\\""))",
            "timestamp": "\(ISO8601DateFormatter().string(from: Date()))",
            "intentType": "decision|confusion|strategy|conflict|affirmation|direction",
            "emotionalState": "What emotional state you detect (or null)",
            "principles": [
                {
                    "principle": "Stewardship",
                    "description": "God entrusts us with resources to manage wisely",
                    "scriptureRef": "Matthew 25:14-30",
                    "applicationToSituation": "How this principle applies to their specific question"
                }
            ],
            "relevantScriptures": [
                {"reference": "Proverbs 3:5-6", "text": "Trust in the LORD...", "whyItApplies": "Why this verse matters here"}
            ],
            "wisdom": "Core wisdom for this situation (2-3 sentences, warm but direct)",
            "practicalSteps": [
                {"id": "s1", "step": "Specific action", "timeframe": "immediate", "reasoning": "Why this step"}
            ],
            "risks": [
                {"risk": "Potential risk", "severity": "low|medium|high", "mitigation": "How to guard against it", "scriptureWarning": "Verse ref or null"}
            ],
            "guardrails": ["Boundary to maintain"],
            "summary": "2-3 sentence summary of guidance",
            "prayerPrompt": "A short prayer the user can pray about this decision"
        }

        Guidelines:
        - Be warm, not preachy
        - Be practical, not just theoretical
        - Include 3-5 biblical principles
        - Include 3-5 relevant scriptures
        - Include 3-5 practical steps
        - Include 2-3 risks with mitigations
        - The prayer should be specific to their situation
        Return ONLY valid JSON, no markdown.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let data = Data(cleanJSON(response).utf8)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let analysis = try decoder.decode(DecisionAnalysis.self, from: data)
            currentAnalysis = analysis
            return analysis
        } catch {
            dlog("❌ [DecisionEngine] Analysis failed: \(error)")
            return nil
        }
    }

    // MARK: - Discernment Engine ("Test This Thought")

    /// Test a thought/belief/decision against scripture
    func testThought(_ thought: String) async -> DiscernmentResult? {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let prompt = """
        The user wants to test this thought/belief/decision against scripture:

        "\(thought)"

        Evaluate it honestly but gracefully. Return as JSON:
        {
            "id": "\(UUID().uuidString)",
            "thought": "\(thought.replacingOccurrences(of: "\"", with: "\\\""))",
            "timestamp": "\(ISO8601DateFormatter().string(from: Date()))",
            "alignment": {
                "score": 0.7,
                "confidence": 0.8,
                "explanation": "How aligned this thought is with biblical teaching and why"
            },
            "supportingScriptures": ["Verses that support aspects of this thought"],
            "warningScriptures": ["Verses that caution against aspects of this thought"],
            "analysis": "Balanced analysis of the thought — what's good, what needs adjustment",
            "balancedGuidance": "Nuanced guidance that honors complexity",
            "verdict": "A clear but gracious assessment (1-2 sentences)"
        }

        Guidelines:
        - Score 0.0 = completely misaligned, 1.0 = fully aligned
        - Be honest but not condemning
        - Always show both supporting and cautionary scriptures when applicable
        - The verdict should be direct but kind
        Return ONLY valid JSON, no markdown.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let data = Data(cleanJSON(response).utf8)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let result = try decoder.decode(DiscernmentResult.self, from: data)
            currentDiscernment = result
            return result
        } catch {
            dlog("❌ [DecisionEngine] Discernment failed: \(error)")
            return nil
        }
    }

    // MARK: - Life-to-Scripture Mapping

    /// Map a life situation to relevant scripture
    func mapToScripture(situation: String) async -> [ScriptureWithApplication] {
        let prompt = """
        The user describes this life situation:
        "\(situation)"

        Find 5-7 relevant scriptures and explain why each applies. Prioritize:
        - Supportive scriptures if they seem distressed
        - Corrective scriptures if they need direction
        - Balanced mix otherwise

        Return as JSON array:
        [{"reference": "Verse ref", "text": "Verse text", "whyItApplies": "Why this verse matters for their situation"}]

        Be warm and specific. Return ONLY valid JSON array.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let data = Data(cleanJSONArray(response).utf8)
            return try JSONDecoder().decode([ScriptureWithApplication].self, from: data)
        } catch {
            return []
        }
    }

    // MARK: - Helpers

    private func cleanJSON(_ response: String) -> String {
        var s = response
        if let start = s.range(of: "{"), let end = s.range(of: "}", options: .backwards) {
            s = String(s[start.lowerBound...end.upperBound])
        }
        return s
    }

    private func cleanJSONArray(_ response: String) -> String {
        var s = response
        if let start = s.range(of: "["), let end = s.range(of: "]", options: .backwards) {
            s = String(s[start.lowerBound...end.upperBound])
        }
        return s
    }
}

// MARK: - Decision Analysis View

struct DecisionAnalysisView: View {
    let analysis: DecisionAnalysis

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Question
                Text(analysis.question)
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Wisdom
                VStack(alignment: .leading, spacing: 8) {
                    Label("Wisdom", systemImage: "lightbulb.fill")
                        .font(.headline)
                    Text(analysis.wisdom)
                        .font(.body)
                }

                // Biblical Principles
                VStack(alignment: .leading, spacing: 12) {
                    Label("Biblical Principles", systemImage: "book.fill")
                        .font(.headline)

                    ForEach(analysis.principles) { principle in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(principle.principle)
                                .font(.subheadline.bold())
                            Text(principle.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(principle.applicationToSituation)
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Text(principle.scriptureRef)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Practical Steps
                VStack(alignment: .leading, spacing: 10) {
                    Label("Practical Steps", systemImage: "checklist")
                        .font(.headline)

                    ForEach(analysis.practicalSteps) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(.green)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.step)
                                    .font(.subheadline)
                                Text(step.reasoning)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Risks
                if !analysis.risks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Watch Out For", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)

                        ForEach(analysis.risks) { risk in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(risk.risk)
                                        .font(.subheadline)
                                    Spacer()
                                    Text(risk.severity)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(risk.severity == "high" ? Color.red.opacity(0.2) : risk.severity == "medium" ? Color.orange.opacity(0.2) : Color.yellow.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                                Text(risk.mitigation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                // Prayer
                if let prayer = analysis.prayerPrompt {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Pray About This", systemImage: "hands.sparkles.fill")
                            .font(.headline)
                        Text(prayer)
                            .font(.subheadline)
                            .italic()
                            .padding()
                            .background(.purple.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Discernment Result View

struct DiscernmentResultView: View {
    let result: DiscernmentResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Thought being tested
                Text("\"\(result.thought)\"")
                    .font(.headline)
                    .italic()

                // Alignment score
                VStack(spacing: 8) {
                    Text("Alignment Score")
                        .font(.subheadline.bold())

                    ProgressView(value: result.alignment.score)
                        .tint(alignmentColor(result.alignment.score))

                    Text(result.alignment.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Verdict
                Text(result.verdict)
                    .font(.body.bold())

                // Analysis
                Text(result.analysis)
                    .font(.subheadline)

                // Supporting scriptures
                if !result.supportingScriptures.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Supporting", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                        ForEach(result.supportingScriptures, id: \.self) { ref in
                            Text("• \(ref)")
                                .font(.caption)
                        }
                    }
                }

                // Warning scriptures
                if !result.warningScriptures.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Caution", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                        ForEach(result.warningScriptures, id: \.self) { ref in
                            Text("• \(ref)")
                                .font(.caption)
                        }
                    }
                }

                // Balanced guidance
                Text(result.balancedGuidance)
                    .font(.subheadline)
                    .padding()
                    .background(.blue.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding()
        }
    }

    private func alignmentColor(_ score: Double) -> Color {
        if score >= 0.7 { return .green }
        if score >= 0.4 { return .orange }
        return .red
    }
}
