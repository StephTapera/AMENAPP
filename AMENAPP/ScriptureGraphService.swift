// ScriptureGraphService.swift
// AMENAPP
//
// Scripture Graph Traversal: Verse → Network
//
// Turns scripture into a connected graph, not isolated text.
// When user selects a verse:
//   - Related verses (thematic)
//   - Fulfillment links (OT → NT prophecy/fulfillment)
//   - Typological connections (shadow → reality)
//   - Thematic threads (same concept across books)
//   - Author cross-references (same author, different book)
//
// Entry points:
//   ScriptureGraphService.shared.buildGraph(for:) async -> ScriptureGraph
//   ScriptureGraphService.shared.traceTheme(_ theme:) async -> ThemeTrace

import Foundation
import SwiftUI
import Combine

// MARK: - Models

/// A complete graph of connections for a verse
struct ScriptureGraph: Identifiable {
    let id = UUID()
    let centerVerse: String
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let themes: [String]
    let timestamp: Date
}

/// A node in the scripture graph
struct GraphNode: Identifiable, Codable {
    let id: String
    let reference: String
    let shortText: String           // First ~50 chars of verse
    let testament: String           // "OT" or "NT"
    let book: String
    let nodeType: NodeType

    enum NodeType: String, Codable {
        case center = "center"          // The verse being studied
        case crossRef = "cross_ref"      // Related verse
        case prophecy = "prophecy"       // OT prophecy
        case fulfillment = "fulfillment" // NT fulfillment
        case typology = "typology"       // Type/shadow
        case thematic = "thematic"       // Same theme
        case authorLink = "author"       // Same author
    }
}

/// An edge connecting two nodes
struct GraphEdge: Identifiable, Codable {
    let id: String
    let fromNode: String            // Node ID
    let toNode: String              // Node ID
    let connectionType: ConnectionType
    let description: String         // Why they're connected

    enum ConnectionType: String, Codable {
        case fulfills = "fulfills"
        case foreshadows = "foreshadows"
        case quotes = "quotes"
        case echoes = "echoes"
        case contrasts = "contrasts"
        case parallels = "parallels"
        case explains = "explains"
        case develops = "develops"
    }
}

/// A theme traced through scripture
struct ThemeTrace: Identifiable, Codable {
    let id: String
    let theme: String
    let description: String
    let milestones: [ThemeMilestone]
    let summary: String
}

struct ThemeMilestone: Identifiable, Codable {
    let id: String
    let reference: String
    let era: String                 // "Creation", "Patriarchs", "Exile", "Gospels", etc.
    let contribution: String        // How this verse adds to the theme
    let significance: String
}

// MARK: - ScriptureGraphService

@MainActor
final class ScriptureGraphService: ObservableObject {

    static let shared = ScriptureGraphService()

    @Published var isBuilding = false
    @Published var currentGraph: ScriptureGraph?
    @Published var currentTheme: ThemeTrace?

    private let aiService = ClaudeService.shared
    private var graphCache: [String: ScriptureGraph] = [:]

    private init() {}

    // MARK: - Public API

    /// Build a connection graph for a verse
    func buildGraph(for reference: String) async -> ScriptureGraph? {
        if let cached = graphCache[reference] {
            currentGraph = cached
            return cached
        }

        isBuilding = true
        defer { isBuilding = false }

        let prompt = """
        Build a scripture connection graph for \(reference). Return as JSON:
        {
            "nodes": [
                {
                    "id": "node_1",
                    "reference": "\(reference)",
                    "shortText": "First ~50 chars of verse",
                    "testament": "NT",
                    "book": "John",
                    "nodeType": "center"
                },
                {
                    "id": "node_2",
                    "reference": "Isaiah 55:1",
                    "shortText": "Come, all you who are thirsty...",
                    "testament": "OT",
                    "book": "Isaiah",
                    "nodeType": "prophecy"
                }
            ],
            "edges": [
                {
                    "id": "edge_1",
                    "fromNode": "node_1",
                    "toNode": "node_2",
                    "connectionType": "fulfills",
                    "description": "Why these verses are connected"
                }
            ],
            "themes": ["theme1", "theme2"]
        }

        Include 6-10 connected verses. Show:
        - At least 1 OT→NT fulfillment link (if applicable)
        - At least 2 thematic connections
        - At least 1 same-author connection (if applicable)
        - Cross-references that illuminate meaning

        Node types: center, cross_ref, prophecy, fulfillment, typology, thematic, author
        Connection types: fulfills, foreshadows, quotes, echoes, contrasts, parallels, explains, develops

        Return ONLY valid JSON, no markdown.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let cleaned = cleanJSON(response)
            let data = Data(cleaned.utf8)

            struct GraphResponse: Codable {
                let nodes: [GraphNode]
                let edges: [GraphEdge]
                let themes: [String]
            }

            let parsed = try JSONDecoder().decode(GraphResponse.self, from: data)
            let graph = ScriptureGraph(
                centerVerse: reference,
                nodes: parsed.nodes,
                edges: parsed.edges,
                themes: parsed.themes,
                timestamp: Date()
            )

            graphCache[reference] = graph
            currentGraph = graph
            return graph
        } catch {
            dlog("❌ [ScriptureGraph] Failed: \(error)")
            return nil
        }
    }

    /// Trace a theme through the entire Bible
    func traceTheme(_ theme: String) async -> ThemeTrace? {
        let prompt = """
        Trace the theme of "\(theme)" through the entire Bible. Return as JSON:
        {
            "id": "\(UUID().uuidString)",
            "theme": "\(theme)",
            "description": "Brief description of this theme",
            "milestones": [
                {
                    "id": "m1",
                    "reference": "Genesis 3:15",
                    "era": "Creation/Fall",
                    "contribution": "How this verse introduces or develops the theme",
                    "significance": "Why this moment matters for the theme"
                }
            ],
            "summary": "How the theme develops from Genesis to Revelation — the arc"
        }

        Include 6-8 milestones spanning the full canon. Return ONLY valid JSON.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let data = Data(cleanJSON(response).utf8)
            let trace = try JSONDecoder().decode(ThemeTrace.self, from: data)
            currentTheme = trace
            return trace
        } catch {
            return nil
        }
    }

    private func cleanJSON(_ response: String) -> String {
        var s = response
        if let start = s.range(of: "{"), let end = s.range(of: "}", options: .backwards) {
            s = String(s[start.lowerBound...end.upperBound])
        }
        return s
    }
}

// MARK: - Scripture Graph View

struct ScriptureGraphView: View {
    let reference: String
    @StateObject private var graphService = ScriptureGraphService.shared
    @State private var selectedNode: GraphNode?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if graphService.isBuilding {
                        ProgressView("Building connections...")
                            .padding(.top, 100)
                    } else if let graph = graphService.currentGraph {
                        graphContent(graph)
                    }
                }
                .padding()
            }
            .navigationTitle("Verse Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await graphService.buildGraph(for: reference)
            }
        }
    }

    private func graphContent(_ graph: ScriptureGraph) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Center verse
            Text(graph.centerVerse)
                .font(.title2.bold())

            // Themes
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(graph.themes, id: \.self) { theme in
                        Text(theme)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }

            // Connection groups
            let prophecyNodes = graph.nodes.filter { $0.nodeType == .prophecy || $0.nodeType == .fulfillment }
            let thematicNodes = graph.nodes.filter { $0.nodeType == .thematic }
            let crossRefNodes = graph.nodes.filter { $0.nodeType == .crossRef }

            if !prophecyNodes.isEmpty {
                connectionSection(title: "Prophecy & Fulfillment", icon: "arrow.right.circle.fill", nodes: prophecyNodes, edges: graph.edges)
            }

            if !thematicNodes.isEmpty {
                connectionSection(title: "Thematic Connections", icon: "link.circle.fill", nodes: thematicNodes, edges: graph.edges)
            }

            if !crossRefNodes.isEmpty {
                connectionSection(title: "Cross-References", icon: "arrow.triangle.branch", nodes: crossRefNodes, edges: graph.edges)
            }
        }
    }

    private func connectionSection(title: String, icon: String, nodes: [GraphNode], edges: [GraphEdge]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)

            ForEach(nodes) { node in
                let edge = edges.first { $0.toNode == node.id || $0.fromNode == node.id }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(node.reference)
                            .font(.subheadline.bold())
                        Spacer()
                        Text(node.testament)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(node.testament == "OT" ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    Text(node.shortText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let edge = edge {
                        Text(edge.description)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}
