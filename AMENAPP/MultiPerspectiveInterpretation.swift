// MultiPerspectiveInterpretation.swift
// AMENAPP
//
// Multi-Perspective Interpretation Layer
//
// Shows different interpretations responsibly:
//   - Common interpretations
//   - Contextual differences
//   - What is universally agreed vs debated
//   - Clear labeling (no confusion)
//
// Builds discernment, not dependency.
//
// Entry points:
//   MultiPerspectiveInterpretation.shared.getInterpretations(for:) async -> InterpretationSet
//   MultiPerspectiveInterpretation.shared.getConsensus(for:) async -> ConsensusReport

import Foundation
import SwiftUI
import Combine

// MARK: - Models

/// Complete set of interpretations for a verse/topic
struct InterpretationSet: Identifiable, Codable {
    let id: String
    let reference: String
    let timestamp: Date
    let consensus: ConsensusReport
    let perspectives: [TheologicalPerspective]
    let historicalViews: [HistoricalView]
    let practicalImplications: String
}

/// What's universally agreed vs debated
struct ConsensusReport: Codable {
    let universallyAgreed: [String]     // Points all major traditions agree on
    let debatedPoints: [DebatedPoint]   // Where traditions differ
    let summary: String
}

struct DebatedPoint: Codable, Identifiable {
    var id: String { topic }
    let topic: String
    let positions: [String]             // The different views
    let significance: String            // Why this debate matters
    let scriptureRefs: [String]
}

/// A theological perspective/tradition
struct TheologicalPerspective: Codable, Identifiable {
    let id: String
    let tradition: String               // "Reformed", "Catholic", "Wesleyan", etc.
    let interpretation: String
    let keyEmphasis: String
    let supportingScriptures: [String]
    let strengthsOfView: [String]
    let limitationsOfView: [String]
}

/// Historical interpretation through church history
struct HistoricalView: Codable, Identifiable {
    let id: String
    let era: String                     // "Early Church", "Medieval", "Reformation", "Modern"
    let interpretation: String
    let keyFigure: String?              // Notable theologian
    let significance: String
}

// MARK: - MultiPerspectiveInterpretation

@MainActor
final class MultiPerspectiveInterpretation: ObservableObject {

    static let shared = MultiPerspectiveInterpretation()

    @Published var isLoading = false
    @Published var currentSet: InterpretationSet?

    private let aiService = ClaudeService.shared
    private var cache: [String: InterpretationSet] = [:]

    private init() {}

    // MARK: - Public API

    /// Get multi-perspective interpretations for a verse or topic
    func getInterpretations(for reference: String) async -> InterpretationSet? {
        if let cached = cache[reference] {
            currentSet = cached
            return cached
        }

        isLoading = true
        defer { isLoading = false }

        let prompt = """
        Provide a multi-perspective interpretation analysis for: \(reference)

        Return as JSON:
        {
            "id": "\(UUID().uuidString)",
            "reference": "\(reference)",
            "timestamp": "\(ISO8601DateFormatter().string(from: Date()))",
            "consensus": {
                "universallyAgreed": ["Points all major Christian traditions agree on about this passage"],
                "debatedPoints": [
                    {
                        "topic": "Topic of disagreement",
                        "positions": ["Position A view", "Position B view"],
                        "significance": "Why this debate matters for understanding",
                        "scriptureRefs": ["Supporting refs"]
                    }
                ],
                "summary": "Brief summary of where there's agreement and disagreement"
            },
            "perspectives": [
                {
                    "id": "p1",
                    "tradition": "Reformed",
                    "interpretation": "How this tradition interprets the passage",
                    "keyEmphasis": "What they emphasize most",
                    "supportingScriptures": ["Key verses they'd cite"],
                    "strengthsOfView": ["What's compelling about this view"],
                    "limitationsOfView": ["What critics point out"]
                }
            ],
            "historicalViews": [
                {
                    "id": "h1",
                    "era": "Early Church (1st-5th century)",
                    "interpretation": "How the early church understood this",
                    "keyFigure": "Augustine / Chrysostom / etc",
                    "significance": "Why this historical view matters"
                }
            ],
            "practicalImplications": "Despite different interpretations, here's what this means practically for faith and life"
        }

        Guidelines:
        - Include 3-4 theological perspectives (Reformed, Catholic/Orthodox, Wesleyan/Arminian, Pentecostal/Charismatic as relevant)
        - Include 2-3 historical views
        - Be fair and respectful to ALL traditions
        - Clearly distinguish agreed vs debated
        - Focus on building discernment
        Return ONLY valid JSON, no markdown.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let data = Data(cleanJSON(response).utf8)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let set = try decoder.decode(InterpretationSet.self, from: data)
            cache[reference] = set
            currentSet = set
            return set
        } catch {
            dlog("❌ [MultiPerspective] Failed: \(error)")
            return nil
        }
    }

    /// Quick consensus check
    func getConsensus(for topic: String) async -> ConsensusReport? {
        if let set = await getInterpretations(for: topic) {
            return set.consensus
        }
        return nil
    }

    private func cleanJSON(_ response: String) -> String {
        var s = response
        if let start = s.range(of: "{"), let end = s.range(of: "}", options: .backwards) {
            s = String(s[start.lowerBound...end.upperBound])
        }
        return s
    }
}

// MARK: - Multi-Perspective View

struct MultiPerspectiveView: View {
    let reference: String
    @StateObject private var service = MultiPerspectiveInterpretation.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if service.isLoading {
                        ProgressView("Gathering perspectives...")
                            .padding(.top, 100)
                    } else if let set = service.currentSet {
                        perspectiveContent(set)
                    }
                }
                .padding()
            }
            .navigationTitle("Perspectives")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await service.getInterpretations(for: reference)
            }
        }
    }

    private func perspectiveContent(_ set: InterpretationSet) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // Consensus section
            VStack(alignment: .leading, spacing: 12) {
                Label("What's Agreed", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                ForEach(set.consensus.universallyAgreed, id: \.self) { point in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(.top, 3)
                        Text(point)
                            .font(.subheadline)
                    }
                }
            }

            // Debated points
            if !set.consensus.debatedPoints.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Where Views Differ", systemImage: "arrow.left.arrow.right.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    ForEach(set.consensus.debatedPoints) { point in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(point.topic)
                                .font(.subheadline.bold())
                            ForEach(point.positions, id: \.self) { pos in
                                Text("• \(pos)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(point.significance)
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Divider()

            // Theological perspectives
            VStack(alignment: .leading, spacing: 16) {
                Text("Theological Traditions")
                    .font(.headline)

                ForEach(set.perspectives) { perspective in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(perspective.tradition)
                            .font(.subheadline.bold())
                        Text(perspective.interpretation)
                            .font(.caption)
                        Text("Emphasis: \(perspective.keyEmphasis)")
                            .font(.caption)
                            .foregroundStyle(.blue)

                        if !perspective.strengthsOfView.isEmpty {
                            Text("Strengths: \(perspective.strengthsOfView.joined(separator: "; "))")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        if !perspective.limitationsOfView.isEmpty {
                            Text("Limitations: \(perspective.limitationsOfView.joined(separator: "; "))")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            // Historical views
            if !set.historicalViews.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Through Church History")
                        .font(.headline)

                    ForEach(set.historicalViews) { view in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(.purple.gradient)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(view.era)
                                    .font(.subheadline.bold())
                                if let figure = view.keyFigure {
                                    Text(figure)
                                        .font(.caption)
                                        .italic()
                                }
                                Text(view.interpretation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // Practical implications
            Text(set.practicalImplications)
                .font(.subheadline)
                .padding()
                .background(.blue.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
