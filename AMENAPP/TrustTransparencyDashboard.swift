// TrustTransparencyDashboard.swift
// AMENAPP
//
// Trust & Transparency Dashboard
//
// Users should KNOW what AI is doing:
//   - "Why did Berean say this?"
//   - "What data is being used?"
//   - Memory controls (delete, edit, scope)
//   - AI confidence indicators
//   - Human boundary indicators
//
// Entry points:
//   TrustTransparencyDashboard (SwiftUI View)
//   TrustTransparencyService.shared.explainResponse(_ responseId:) async -> ResponseExplanation
//   TrustTransparencyService.shared.getDataUsageSummary() async -> DataUsageSummary

import Foundation
import SwiftUI
import Combine
import FirebaseAuth

// MARK: - Models

/// Explanation for why Berean gave a particular response
struct ResponseExplanation: Identifiable, Codable {
    let id: String
    let responseId: String
    let timestamp: Date

    let sourcesUsed: [SourceUsed]
    let confidenceLevel: Double     // 0.0-1.0
    let reasoning: String           // Why this response was given
    let limitations: [String]       // What Berean can't know
    let humanBoundary: String?      // When to consult a real person
}

struct SourceUsed: Codable, Identifiable {
    var id: String { source }
    let source: String              // "Scripture", "User Context", "Conversation History"
    let description: String
    let weight: Double              // How much it influenced the response
}

/// Summary of what data Berean uses
struct DataUsageSummary: Codable {
    let memoriesCount: Int
    let categoriesEnabled: [String]
    let conversationHistory: Int    // Number of conversations
    let lastContextRefresh: Date?
    let dataRetentionPolicy: String
    let exportAvailable: Bool
}

// MARK: - TrustTransparencyService

@MainActor
final class TrustTransparencyService: ObservableObject {

    static let shared = TrustTransparencyService()

    @Published var dataUsage: DataUsageSummary?
    @Published var isLoading = false

    private let aiService = ClaudeService.shared
    private let knowledgeGraph = PersonalKnowledgeGraph.shared

    private init() {}

    // MARK: - Response Explanation

    /// Explain why Berean gave a response
    func explainResponse(response: String, query: String, context: String = "") async -> ResponseExplanation? {
        let prompt = """
        Explain why this AI response was given. Return as JSON:
        {
            "id": "\(UUID().uuidString)",
            "responseId": "\(UUID().uuidString)",
            "timestamp": "\(ISO8601DateFormatter().string(from: Date()))",
            "sourcesUsed": [
                {"source": "Scripture", "description": "Relevant Bible verses cited", "weight": 0.5},
                {"source": "User Context", "description": "Personal context used", "weight": 0.2},
                {"source": "Conversation History", "description": "Prior messages referenced", "weight": 0.3}
            ],
            "confidenceLevel": 0.8,
            "reasoning": "Clear explanation of why this answer was given",
            "limitations": ["Things the AI couldn't know or verify"],
            "humanBoundary": "When the user should consult a real pastor/counselor instead"
        }

        User asked: \(String(query.prefix(200)))
        AI responded: \(String(response.prefix(500)))

        Be transparent and honest about what influenced the response.
        Return ONLY valid JSON.
        """

        do {
            let aiResponse = try await aiService.sendMessage(prompt)
            let data = Data(cleanJSON(aiResponse).utf8)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ResponseExplanation.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Data Usage

    /// Get summary of all data Berean uses
    func getDataUsageSummary() async -> DataUsageSummary {
        let memCount = knowledgeGraph.totalMemories
        let categories = knowledgeGraph.enabledCategories.map { $0.displayName }

        let summary = DataUsageSummary(
            memoriesCount: memCount,
            categoriesEnabled: categories,
            conversationHistory: UserDefaults.standard.integer(forKey: "berean_conversation_count"),
            lastContextRefresh: nil,
            dataRetentionPolicy: "Memories are stored locally and in your Firestore account. You can delete any memory at any time. Conversation history is retained for your reference but can be cleared.",
            exportAvailable: true
        )

        dataUsage = summary
        return summary
    }

    private func cleanJSON(_ response: String) -> String {
        var s = response
        if let start = s.range(of: "{"), let end = s.range(of: "}", options: .backwards) {
            s = String(s[start.lowerBound...end.upperBound])
        }
        return s
    }
}

// MARK: - Trust Dashboard View

struct TrustTransparencyDashboardView: View {
    @StateObject private var service = TrustTransparencyService.shared
    @StateObject private var knowledgeGraph = PersonalKnowledgeGraph.shared
    @StateObject private var patternIntel = LifePatternIntelligence.shared
    @State private var showMemoryManager = false
    @State private var showDataExport = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // AI Transparency
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How Berean Works", systemImage: "brain.head.profile.fill")
                            .font(.headline)
                        Text("Berean uses scripture, your conversation context, and any memories you've allowed to personalize responses. It never stores data without your permission.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Transparency")
                }

                // Data Controls
                Section("Your Data") {
                    HStack {
                        Label("Memories Stored", systemImage: "brain.fill")
                        Spacer()
                        Text("\(knowledgeGraph.totalMemories)")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showMemoryManager = true
                    } label: {
                        Label("Manage Memories", systemImage: "slider.horizontal.3")
                    }

                    Toggle("Memory Enabled", isOn: $knowledgeGraph.isMemoryEnabled)

                    Toggle("Behavioral Awareness", isOn: $patternIntel.isEnabled)
                }

                // Privacy section
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("On-Device Processing", systemImage: "lock.shield.fill")
                            .font(.subheadline.bold())
                        Text("Behavioral pattern detection runs entirely on your device. No behavioral data is sent to servers.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Encrypted Storage", systemImage: "lock.fill")
                            .font(.subheadline.bold())
                        Text("Memories are stored in your personal Firestore account with Firebase security rules.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("No Data Sharing", systemImage: "hand.raised.fill")
                            .font(.subheadline.bold())
                        Text("Your AI conversations and memories are never shared with other users or third parties.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Privacy & Security")
                }

                // AI Boundaries
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Important Boundaries")
                                .font(.subheadline.bold())
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            boundaryRow("Berean does NOT replace a pastor, counselor, or therapist")
                            boundaryRow("For crisis situations, always seek real-world help first")
                            boundaryRow("AI responses may contain errors — verify important claims")
                            boundaryRow("Berean provides perspectives, not absolute theological authority")
                        }
                    }
                } header: {
                    Text("AI + Human Boundaries")
                }

                // Data actions
                Section {
                    Button("Export My Data") {
                        showDataExport = true
                    }

                    Button("Clear All Memories", role: .destructive) {
                        Task { await knowledgeGraph.clearAll() }
                    }
                } header: {
                    Text("Data Actions")
                }
            }
            .navigationTitle("Trust & Transparency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showMemoryManager) {
                BereanMemoryView()
            }
        }
    }

    private func boundaryRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Response Explanation Popover

struct ResponseExplanationView: View {
    let explanation: ResponseExplanation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("Why Berean Said This")
                    .font(.headline)
            }

            // Confidence
            VStack(alignment: .leading, spacing: 4) {
                Text("Confidence")
                    .font(.caption.bold())
                ProgressView(value: explanation.confidenceLevel)
                    .tint(explanation.confidenceLevel > 0.7 ? .green : explanation.confidenceLevel > 0.4 ? .orange : .red)
            }

            // Sources
            VStack(alignment: .leading, spacing: 8) {
                Text("Sources Used")
                    .font(.caption.bold())
                ForEach(explanation.sourcesUsed) { source in
                    HStack {
                        Text(source.source)
                            .font(.caption)
                        Spacer()
                        Text("\(Int(source.weight * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Reasoning
            Text(explanation.reasoning)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Limitations
            if !explanation.limitations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Limitations")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    ForEach(explanation.limitations, id: \.self) { limit in
                        Text("• \(limit)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Human boundary
            if let boundary = explanation.humanBoundary {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.purple)
                        .font(.caption)
                    Text(boundary)
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
                .padding(8)
                .background(.purple.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
    }
}
