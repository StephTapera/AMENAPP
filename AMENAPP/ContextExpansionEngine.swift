//
//  ContextExpansionEngine.swift
//  AMENAPP
//
//  Verse → Layered Context (prevents misinterpretation by design).
//  When a user highlights or taps a verse, this engine progressively
//  unfolds context like a liquid-glass ripple:
//
//    Layer 1 — Immediate:   verses before/after (same passage)
//    Layer 2 — Chapter:     chapter summary + purpose
//    Layer 3 — Book:        book theme, author, audience, date
//    Layer 4 — Historical:  world events, culture, geography
//    Layer 5 — Canonical:   OT↔NT connections, fulfilment
//
//  Architecture:
//    ContextExpansionEngine (@MainActor singleton)
//    ├── ContextLayer          (model — one layer of context)
//    ├── expand(verse:)        (builds all 5 layers via Claude)
//    └── ContextExpansionView  (progressive disclosure UI)
//

import Foundation
import SwiftUI
import Combine

// MARK: - Models

struct ContextLayer: Identifiable, Equatable {
    let id: Int
    let title: String
    let icon: String
    var content: String
    var isLoading: Bool
    var isExpanded: Bool

    static let placeholders: [ContextLayer] = [
        ContextLayer(id: 0, title: "Immediate Context",  icon: "text.alignleft",         content: "", isLoading: false, isExpanded: false),
        ContextLayer(id: 1, title: "Chapter Overview",   icon: "book.pages",              content: "", isLoading: false, isExpanded: false),
        ContextLayer(id: 2, title: "Book & Author",      icon: "books.vertical.fill",     content: "", isLoading: false, isExpanded: false),
        ContextLayer(id: 3, title: "Historical Setting", icon: "globe.americas.fill",     content: "", isLoading: false, isExpanded: false),
        ContextLayer(id: 4, title: "Biblical Threads",   icon: "arrow.triangle.branch",   content: "", isLoading: false, isExpanded: false),
    ]
}

// MARK: - Service

@MainActor
final class ContextExpansionEngine: ObservableObject {
    static let shared = ContextExpansionEngine()

    @Published var layers: [ContextLayer] = ContextLayer.placeholders
    @Published var currentVerse: String = ""
    @Published var isLoadingAny: Bool = false

    private let claude = ClaudeService.shared

    private init() {}

    /// Reset and begin expansion for a new verse reference.
    func expand(verse: String) {
        currentVerse = verse
        layers = ContextLayer.placeholders
        isLoadingAny = true
        Task { await loadAllLayers(verse: verse) }
    }

    func toggleLayer(_ id: Int) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            layers[idx].isExpanded.toggle()
        }
        // Load on-demand if not yet loaded
        if layers[idx].content.isEmpty && !layers[idx].isLoading {
            Task { await loadLayer(id: id, verse: currentVerse) }
        }
    }

    // MARK: - Loading

    private func loadAllLayers(verse: String) async {
        // Load sequentially so UI feels like progressive disclosure
        for id in 0..<5 {
            await loadLayer(id: id, verse: verse)
            // Auto-expand the first layer
            if id == 0 {
                withAnimation(.spring(response: 0.5)) {
                    layers[0].isExpanded = true
                }
            }
        }
        isLoadingAny = false
    }

    private func loadLayer(id: Int, verse: String) async {
        guard var layer = layers.first(where: { $0.id == id }), layer.content.isEmpty else { return }
        let idx = id

        layers[idx].isLoading = true

        let prompt = layerPrompt(id: id, verse: verse)
        let result = (try? await claude.sendMessageSync(prompt, mode: .scholar)) ?? ""

        layers[idx].content = result.trimmingCharacters(in: .whitespacesAndNewlines)
        layers[idx].isLoading = false
    }

    // MARK: - Prompts per layer

    private func layerPrompt(id: Int, verse: String) -> String {
        switch id {
        case 0:
            return """
            For the Bible verse \(verse), provide the IMMEDIATE CONTEXT:
            - Quote 2-3 verses before and after this verse
            - Briefly explain how they connect to the verse in question
            Keep it under 150 words. Be factual and direct.
            """
        case 1:
            return """
            For the Bible verse \(verse), provide a CHAPTER OVERVIEW:
            - What is the main purpose of this chapter?
            - How does this verse fit into the chapter's flow?
            Keep it under 120 words.
            """
        case 2:
            return """
            For the Bible verse \(verse), provide BOOK & AUTHOR context:
            - Who wrote this book? When? To whom?
            - What is the book's central theme?
            - Why does that matter for understanding this verse?
            Keep it under 150 words.
            """
        case 3:
            return """
            For the Bible verse \(verse), provide HISTORICAL SETTING:
            - What was happening in the world/Israel when this was written?
            - What cultural or political factors are relevant?
            - How does the setting shape the meaning?
            Keep it under 150 words.
            """
        case 4:
            return """
            For the Bible verse \(verse), identify BIBLICAL THREADS:
            - Name 2-3 other passages that connect thematically or prophetically
            - For each: verse reference + one sentence explaining the connection
            - If this is an OT verse, name NT fulfillments if applicable
            Keep it under 150 words.
            """
        default:
            return "Explain the context of \(verse) briefly."
        }
    }
}

// MARK: - SwiftUI View

/// Embed this view anywhere a verse reference appears.
struct ContextExpansionView: View {
    let verse: String
    @StateObject private var engine = ContextExpansionEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verse)
                        .font(.headline)
                    Text("Context Explorer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if engine.isLoadingAny {
                    ProgressView().scaleEffect(0.8)
                }
                Button {
                    engine.expand(verse: verse)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            // Layers
            ForEach(engine.layers) { layer in
                ContextLayerRow(layer: layer, onTap: {
                    engine.toggleLayer(layer.id)
                })
                if layer.id < engine.layers.count - 1 {
                    Divider().padding(.leading)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            if engine.currentVerse != verse {
                engine.expand(verse: verse)
            }
        }
    }
}

// MARK: - Layer Row

private struct ContextLayerRow: View {
    let layer: ContextLayer
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row header — always visible
            Button(action: onTap) {
                HStack {
                    Image(systemName: layer.icon)
                        .foregroundStyle(.indigo)
                        .frame(width: 24)
                    Text(layer.title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if layer.isLoading {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: layer.isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // Expanded content — liquid-glass ripple effect
            if layer.isExpanded {
                Group {
                    if layer.content.isEmpty && !layer.isLoading {
                        Text("Tap to load…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        Text(layer.content)
                            .font(.subheadline)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                    }
                }
                .transition(.asymmetric(
                    insertion: .push(from: .top).combined(with: .opacity),
                    removal: .push(from: .bottom).combined(with: .opacity)
                ))
            }
        }
    }
}

// MARK: - Compact Pill Trigger

/// Small pill you can embed in PostCard or BereanChatView to open the expander.
struct ContextExpansionPill: View {
    let verse: String
    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption2)
                Text("Expand Context")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.indigo.opacity(0.12), in: Capsule())
            .foregroundStyle(.indigo)
        }
        .sheet(isPresented: $showingSheet) {
            NavigationStack {
                ScrollView {
                    ContextExpansionView(verse: verse)
                        .padding()
                }
                .navigationTitle("Context: \(verse)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showingSheet = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
