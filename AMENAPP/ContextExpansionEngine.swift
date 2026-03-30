// ContextExpansionEngine.swift
// AMENAPP
//
// Context Expansion: Zoom Out Intelligently
//
// When user highlights a verse/word, this engine expands context automatically:
//   Layer 1: Immediate context (verses before/after)
//   Layer 2: Chapter summary
//   Layer 3: Book theme
//   Layer 4: Historical setting (who, when, why)
//   Layer 5: Canonical context (where this fits in the Bible's story)
//
// Prevents misinterpretation by design — context is king.
//
// Entry points:
//   ContextExpansionEngine.shared.expand(reference:) async -> ContextExpansion
//   ContextExpansionEngine.shared.expandLayer(_ layer:for:) async -> ContextLayer

import Foundation
import SwiftUI
import Combine

// MARK: - Models

/// Complete context expansion for a verse
struct ContextExpansion: Identifiable {
    let id = UUID()
    let reference: String
    let layers: [ContextLayer]
    let timestamp: Date

    func layer(at depth: ExpansionDepth) -> ContextLayer? {
        layers.first { $0.depth == depth }
    }
}

/// A single expansion layer
struct ContextLayer: Identifiable, Codable {
    let id: String
    let depth: ExpansionDepth
    let title: String
    let content: String
    let keyInsight: String          // One-line takeaway
    let relevantVerses: [String]    // Related refs at this layer
}

/// Progressive expansion depths
enum ExpansionDepth: String, Codable, CaseIterable {
    case immediate = "immediate"        // Verses before/after
    case chapter = "chapter"            // Chapter summary
    case book = "book"                  // Book theme + purpose
    case historical = "historical"      // Who, when, why, audience
    case canonical = "canonical"        // Where it fits in the whole Bible story

    var displayName: String {
        switch self {
        case .immediate:  return "Surrounding Verses"
        case .chapter:    return "Chapter Context"
        case .book:       return "Book Overview"
        case .historical: return "Historical Setting"
        case .canonical:  return "Big Picture"
        }
    }

    var icon: String {
        switch self {
        case .immediate:  return "text.quote"
        case .chapter:    return "doc.text"
        case .book:       return "book.closed"
        case .historical: return "clock.arrow.circlepath"
        case .canonical:  return "globe"
        }
    }

    var order: Int {
        switch self {
        case .immediate:  return 0
        case .chapter:    return 1
        case .book:       return 2
        case .historical: return 3
        case .canonical:  return 4
        }
    }
}

// MARK: - ContextExpansionEngine

@MainActor
final class ContextExpansionEngine: ObservableObject {

    static let shared = ContextExpansionEngine()

    @Published var isExpanding = false
    @Published var currentExpansion: ContextExpansion?
    @Published var activeDepth: ExpansionDepth = .immediate
    @Published var expandedLayers: Set<ExpansionDepth> = [.immediate]

    private let aiService = ClaudeService.shared
    private var cache: [String: ContextExpansion] = [:]

    private init() {}

    // MARK: - Public API

    /// Expand all layers for a verse reference
    func expand(reference: String) async -> ContextExpansion? {
        if let cached = cache[reference] {
            currentExpansion = cached
            return cached
        }

        isExpanding = true
        defer { isExpanding = false }

        let prompt = """
        Provide a progressive context expansion for \(reference). Return as JSON:
        {
            "layers": [
                {
                    "id": "unique_id",
                    "depth": "immediate",
                    "title": "Surrounding Verses",
                    "content": "What the verses immediately before and after say, and how they connect",
                    "keyInsight": "One-line takeaway",
                    "relevantVerses": ["verse refs"]
                },
                {
                    "id": "unique_id",
                    "depth": "chapter",
                    "title": "Chapter Context",
                    "content": "Summary of the chapter — what's the main argument/narrative",
                    "keyInsight": "One-line takeaway",
                    "relevantVerses": ["key verse refs in this chapter"]
                },
                {
                    "id": "unique_id",
                    "depth": "book",
                    "title": "Book Overview",
                    "content": "The book's theme, purpose, and how this verse fits",
                    "keyInsight": "One-line takeaway",
                    "relevantVerses": ["key thematic verses from the book"]
                },
                {
                    "id": "unique_id",
                    "depth": "historical",
                    "title": "Historical Setting",
                    "content": "Who wrote it, when, to whom, why — cultural and historical context",
                    "keyInsight": "One-line takeaway",
                    "relevantVerses": ["verses that illuminate the historical context"]
                },
                {
                    "id": "unique_id",
                    "depth": "canonical",
                    "title": "Big Picture",
                    "content": "Where this verse fits in the Bible's overarching story — creation, fall, redemption, restoration",
                    "keyInsight": "One-line takeaway",
                    "relevantVerses": ["verses that connect across the canon"]
                }
            ]
        }

        Be accurate and scholarly but accessible. Each layer should build on the previous.
        Return ONLY valid JSON, no markdown.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let cleaned = cleanJSON(response)
            let data = Data(cleaned.utf8)

            struct ExpansionResponse: Codable {
                let layers: [ContextLayer]
            }

            let parsed = try JSONDecoder().decode(ExpansionResponse.self, from: data)
            let expansion = ContextExpansion(
                reference: reference,
                layers: parsed.layers.sorted { $0.depth.order < $1.depth.order },
                timestamp: Date()
            )

            cache[reference] = expansion
            currentExpansion = expansion
            return expansion
        } catch {
            dlog("❌ [ContextExpansion] Failed: \(error)")
            return nil
        }
    }

    /// Expand a single layer (for lazy loading)
    func expandLayer(_ depth: ExpansionDepth, for reference: String) async -> ContextLayer? {
        if let expansion = currentExpansion, let layer = expansion.layer(at: depth) {
            return layer
        }

        // Fetch all and return requested
        if let expansion = await expand(reference: reference) {
            return expansion.layer(at: depth)
        }
        return nil
    }

    // MARK: - Helpers

    private func cleanJSON(_ response: String) -> String {
        var s = response
        if let start = s.range(of: "{"), let end = s.range(of: "}", options: .backwards) {
            s = String(s[start.lowerBound...end.upperBound])
        }
        return s
    }
}

// MARK: - Context Expansion View (Liquid Glass Ripple)

struct ContextExpansionView: View {
    let reference: String
    @StateObject private var engine = ContextExpansionEngine.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if engine.isExpanding {
                        expandingView
                    } else if let expansion = engine.currentExpansion {
                        expansionContent(expansion)
                    }
                }
                .padding()
            }
            .navigationTitle(reference)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await engine.expand(reference: reference)
            }
        }
    }

    private var expandingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Expanding context...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 100)
    }

    private func expansionContent(_ expansion: ContextExpansion) -> some View {
        VStack(spacing: 16) {
            ForEach(ExpansionDepth.allCases, id: \.rawValue) { depth in
                if let layer = expansion.layer(at: depth) {
                    expansionLayerCard(layer, depth: depth)
                }
            }
        }
    }

    private func expansionLayerCard(_ layer: ContextLayer, depth: ExpansionDepth) -> some View {
        let isExpanded = engine.expandedLayers.contains(depth)

        return VStack(spacing: 0) {
            // Header — always visible
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if isExpanded {
                        engine.expandedLayers.remove(depth)
                    } else {
                        engine.expandedLayers.insert(depth)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: depth.icon)
                        .foregroundStyle(.blue)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(depth.displayName)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text(layer.keyInsight)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 1)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)

            // Content — expandable
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(layer.content)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !layer.relevantVerses.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(layer.relevantVerses, id: \.self) { ref in
                                    Text(ref)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.blue.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Divider between layers
            if depth != .canonical {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 0.5)
                    .padding(.leading, 56)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: depth == .immediate ? 16 : (depth == .canonical ? 16 : 0), style: .continuous))
    }
}
