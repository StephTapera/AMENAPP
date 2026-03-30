// SermonIntelligenceEngine.swift
// AMENAPP
//
// Sermon Intelligence: Audio → Structured Growth
//
// Extends the existing SermonRecorder with intelligence:
//   1. Post-recording analysis pipeline
//   2. Topic segmentation (points, themes, scriptures)
//   3. Auto-tagging (faith, anxiety, obedience, etc.)
//   4. Structured output generation:
//      - Summary
//      - Key takeaways
//      - Reflection prompts
//      - Action steps
//   5. Speaker/church detection (location + time)
//   6. Growth loop integration (follow-up scheduling)
//
// Entry points:
//   SermonIntelligenceEngine.shared.analyze(transcript:) async -> SermonAnalysis
//   SermonIntelligenceEngine.shared.generateReflectionPrompts(from:) async -> [ReflectionPrompt]

import Foundation
import SwiftUI
import Combine
import CoreLocation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Models

/// Complete sermon analysis
struct SermonAnalysis: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let transcript: String

    // Structured content
    let title: String
    let summary: String
    let keyTakeaways: [KeyTakeaway]
    let mainPoints: [SermonPoint]
    let scripturesReferenced: [String]
    let tags: [String]              // auto-detected topics

    // Actionable output
    let reflectionPrompts: [ReflectionPrompt]
    let actionSteps: [ActionStep]

    // Metadata
    let estimatedDuration: TimeInterval?
    let speakerName: String?
    let churchName: String?
}

struct KeyTakeaway: Codable, Identifiable {
    var id: String { takeaway }
    let takeaway: String
    let supportingVerse: String?
}

struct SermonPoint: Codable, Identifiable {
    let id: String
    let pointNumber: Int
    let title: String
    let content: String
    let scriptures: [String]
    let application: String
}

struct ReflectionPrompt: Codable, Identifiable {
    let id: String
    let prompt: String
    let depth: ReflectionDepth
    let relatedPoint: String?       // Which sermon point it relates to
    let scheduledDay: Int?          // Days after sermon (1, 3, 7)
}

enum ReflectionDepth: String, Codable {
    case surface = "surface"        // Quick thought
    case personal = "personal"      // Deeper personal reflection
    case transformative = "transformative" // Life-change level
}

struct ActionStep: Codable, Identifiable {
    let id: String
    let action: String
    let timeframe: String           // "today", "this week", "this month"
    let difficulty: ActionDifficulty
    let relatedVerse: String?
}

enum ActionDifficulty: String, Codable {
    case easy = "easy"
    case moderate = "moderate"
    case challenging = "challenging"
}

// MARK: - SermonIntelligenceEngine

@MainActor
final class SermonIntelligenceEngine: ObservableObject {

    static let shared = SermonIntelligenceEngine()

    @Published var isAnalyzing = false
    @Published var currentAnalysis: SermonAnalysis?
    @Published var analysisStage: AnalysisStage = .idle
    @Published var recentAnalyses: [SermonAnalysis] = []

    enum AnalysisStage: String {
        case idle = "Ready"
        case segmenting = "Identifying key points..."
        case extractingScripture = "Finding scriptures..."
        case generating = "Building insights..."
        case scheduling = "Setting up growth loop..."
        case complete = "Complete"
    }

    private let aiService = ClaudeService.shared
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Public API

    /// Analyze a sermon transcript into structured, actionable content
    func analyze(transcript: String, speakerName: String? = nil, churchName: String? = nil) async -> SermonAnalysis? {
        guard !transcript.isEmpty else { return nil }

        isAnalyzing = true
        defer { isAnalyzing = false }

        analysisStage = .segmenting

        let prompt = """
        Analyze this sermon transcript and produce structured, actionable output. Return as JSON:
        {
            "id": "\(UUID().uuidString)",
            "timestamp": "\(ISO8601DateFormatter().string(from: Date()))",
            "transcript": "",
            "title": "A clear, meaningful title for this sermon",
            "summary": "3-4 sentence summary capturing the core message",
            "keyTakeaways": [
                {"takeaway": "Key insight", "supportingVerse": "John 3:16"}
            ],
            "mainPoints": [
                {
                    "id": "p1",
                    "pointNumber": 1,
                    "title": "Point title",
                    "content": "What was taught",
                    "scriptures": ["Verse refs used"],
                    "application": "How to apply this point"
                }
            ],
            "scripturesReferenced": ["All verse refs mentioned"],
            "tags": ["faith", "anxiety", "hope"],
            "reflectionPrompts": [
                {"id": "r1", "prompt": "A thoughtful question", "depth": "surface", "relatedPoint": "p1", "scheduledDay": 1},
                {"id": "r2", "prompt": "Deeper question", "depth": "personal", "relatedPoint": "p1", "scheduledDay": 3},
                {"id": "r3", "prompt": "Transformative question", "depth": "transformative", "relatedPoint": "p2", "scheduledDay": 7}
            ],
            "actionSteps": [
                {"id": "a1", "action": "Specific action", "timeframe": "today", "difficulty": "easy", "relatedVerse": "Verse ref"},
                {"id": "a2", "action": "Harder action", "timeframe": "this week", "difficulty": "moderate", "relatedVerse": null}
            ],
            "estimatedDuration": null,
            "speakerName": \(speakerName.map { "\"\($0)\"" } ?? "null"),
            "churchName": \(churchName.map { "\"\($0)\"" } ?? "null")
        }

        Sermon transcript:
        \(String(transcript.prefix(8000)))

        Guidelines:
        - Extract 3-5 main points
        - Generate 5-7 reflection prompts at varying depths
        - Include 3-5 concrete action steps
        - Schedule reflections at day 1, 3, and 7
        - Tags should be lowercase, relevant topics
        - Be warm, pastoral, practical
        Return ONLY valid JSON, no markdown.
        """

        analysisStage = .extractingScripture

        do {
            let response = try await aiService.sendMessage(prompt)
            analysisStage = .generating

            let cleaned = cleanJSON(response)
            let data = Data(cleaned.utf8)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var analysis = try decoder.decode(SermonAnalysis.self, from: data)

            analysisStage = .scheduling

            // Save to Firestore
            saveAnalysis(analysis)

            // Schedule growth loop notifications
            scheduleGrowthLoop(for: analysis)

            analysisStage = .complete
            currentAnalysis = analysis
            recentAnalyses.insert(analysis, at: 0)

            return analysis
        } catch {
            dlog("❌ [SermonIntelligence] Analysis failed: \(error)")
            analysisStage = .idle
            return nil
        }
    }

    /// Generate additional reflection prompts
    func generateReflectionPrompts(from analysis: SermonAnalysis, count: Int = 5) async -> [ReflectionPrompt] {
        let prompt = """
        Based on this sermon summary, generate \(count) deep reflection prompts:

        Title: \(analysis.title)
        Summary: \(analysis.summary)
        Key Points: \(analysis.mainPoints.map { $0.title }.joined(separator: ", "))

        Return as JSON array:
        [{"id": "rp1", "prompt": "Question", "depth": "personal", "relatedPoint": null, "scheduledDay": 1}]

        Depths: surface, personal, transformative
        Return ONLY valid JSON array.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let cleaned = cleanJSONArray(response)
            let data = Data(cleaned.utf8)
            return try JSONDecoder().decode([ReflectionPrompt].self, from: data)
        } catch {
            return []
        }
    }

    // MARK: - Growth Loop Scheduling

    private func scheduleGrowthLoop(for analysis: SermonAnalysis) {
        let center = UNUserNotificationCenter.current()

        for prompt in analysis.reflectionPrompts {
            guard let day = prompt.scheduledDay else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Reflect on Sunday's Sermon"
            content.body = prompt.prompt
            content.sound = .default
            content.userInfo = [
                "type": "sermon_reflection",
                "analysisId": analysis.id,
                "promptId": prompt.id
            ]

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(day * 86400),
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: "sermon_reflection_\(analysis.id)_\(prompt.id)",
                content: content,
                trigger: trigger
            )

            center.add(request)
        }

        dlog("📅 [SermonIntelligence] Scheduled \(analysis.reflectionPrompts.count) growth loop prompts")
    }

    // MARK: - Persistence

    private func saveAnalysis(_ analysis: SermonAnalysis) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let data: [String: Any] = [
            "title": analysis.title,
            "summary": analysis.summary,
            "tags": analysis.tags,
            "scripturesReferenced": analysis.scripturesReferenced,
            "timestamp": Timestamp(date: analysis.timestamp),
            "speakerName": analysis.speakerName ?? "",
            "churchName": analysis.churchName ?? "",
            "userId": uid
        ]

        db.collection("users").document(uid)
            .collection("sermonAnalyses").document(analysis.id)
            .setData(data, merge: true)
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

// MARK: - Sermon Analysis View

struct SermonAnalysisView: View {
    let analysis: SermonAnalysis

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(analysis.title)
                        .font(.title2.bold())

                    if let speaker = analysis.speakerName {
                        Text(speaker)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Tags
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(analysis.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.blue.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                // Summary
                Text(analysis.summary)
                    .font(.body)

                Divider()

                // Key Takeaways
                VStack(alignment: .leading, spacing: 10) {
                    Text("Key Takeaways")
                        .font(.headline)

                    ForEach(analysis.keyTakeaways) { takeaway in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .padding(.top, 3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(takeaway.takeaway)
                                    .font(.subheadline)
                                if let verse = takeaway.supportingVerse {
                                    Text(verse)
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                Divider()

                // Main Points
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sermon Points")
                        .font(.headline)

                    ForEach(analysis.mainPoints) { point in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(point.pointNumber). \(point.title)")
                                .font(.subheadline.bold())
                            Text(point.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Apply: \(point.application)")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                Divider()

                // Action Steps
                VStack(alignment: .leading, spacing: 10) {
                    Text("Action Steps")
                        .font(.headline)

                    ForEach(analysis.actionSteps) { step in
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text(step.action)
                                    .font(.subheadline)
                                Text(step.timeframe)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Divider()

                // Reflection Prompts
                VStack(alignment: .leading, spacing: 10) {
                    Text("Growth Loop")
                        .font(.headline)
                    Text("You'll receive these prompts over the next week")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(analysis.reflectionPrompts) { prompt in
                        HStack(alignment: .top, spacing: 8) {
                            if let day = prompt.scheduledDay {
                                Text("Day \(day)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            Text(prompt.prompt)
                                .font(.caption)
                        }
                    }
                }
            }
            .padding()
        }
    }
}
