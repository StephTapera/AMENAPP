//
//  AskSelahView.swift
//  AMENAPP
//
//  Grounded AI workspace — the user asks questions and Selah
//  responds using their personal context (notes, verses, prayers,
//  testimonies, prior studies) as grounding sources.
//

import SwiftUI

struct AskSelahView: View {
    let initialQuery: String
    let initialVerses: [String]

    @StateObject private var selahService = SelahService.shared
    @State private var query = ""
    @State private var isStreaming = false
    @State private var streamedContent = ""
    @State private var sourceBundle = SelahSourceBundle(verses: [], notes: [], prayers: [], testimonies: [], bereanHistory: [])
    @State private var citations: [SelahCitation] = []
    @State private var hasSubmitted = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool
    /// Stored so we can cancel streaming when the view disappears.
    @State private var activeTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Source pills
            if !sourceBundle.isEmpty {
                sourcePillsStrip
                    .padding(.top, 8)
            }

            if hasSubmitted {
                // Response area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Streaming response
                        if !streamedContent.isEmpty {
                            Text(streamedContent)
                                .font(.systemScaled(15))
                                .foregroundStyle(.primary)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .textSelection(.enabled)

                            // Check against Scripture — Requires DiscernmentActionButton.swift in target (see SelahScripture/)
                            DiscernmentActionButton(
                                inputText: streamedContent,
                                sourceType: "selah_note",
                                sourceRef: nil
                            )
                            .padding(.horizontal, 20)
                        }

                        if isStreaming {
                            SelahThinkingDots()
                                .padding(.horizontal, 20)
                        }

                        // Citations
                        if !citations.isEmpty {
                            citationsSection
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }

                        Spacer(minLength: 80)
                    }
                }
            } else {
                // Empty state with suggestions
                emptyState
            }

            Spacer(minLength: 0)

            // Input bar
            inputBar
        }
        .onAppear {
            query = initialQuery
            loadSources()
        }
        .onDisappear {
            activeTask?.cancel()
        }
    }

    // MARK: - Source Pills

    private var sourcePillsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !sourceBundle.verses.isEmpty {
                    sourcePill(
                        icon: "book.fill",
                        label: "\(sourceBundle.verses.count) Verses",
                        color: .blue
                    )
                }
                if !sourceBundle.notes.isEmpty {
                    sourcePill(
                        icon: "note.text",
                        label: "\(sourceBundle.notes.count) Notes",
                        color: .orange
                    )
                }
                if !sourceBundle.prayers.isEmpty {
                    sourcePill(
                        icon: "hands.sparkles",
                        label: "\(sourceBundle.prayers.count) Prayers",
                        color: .purple
                    )
                }
                if !sourceBundle.bereanHistory.isEmpty {
                    sourcePill(
                        icon: "brain.head.profile",
                        label: "\(sourceBundle.bereanHistory.count) Studies",
                        color: .green
                    )
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(minHeight: 34)
    }

    private func sourcePill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.systemScaled(10))
            Text(label)
                .font(.systemScaled(11, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.10), in: Capsule())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.systemScaled(44, weight: .light))
                .foregroundStyle(.secondary.opacity(0.35))

            VStack(spacing: 6) {
                Text("Ask Selah")
                    .font(.systemScaled(20, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Grounded in your notes, prayers,\nand scripture history")
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            // Suggestion chips
            VStack(spacing: 8) {
                suggestionChip("How does this connect to my prayers?")
                suggestionChip("What themes keep appearing in my studies?")
                suggestionChip("Help me apply this verse to my life")
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            query = text
            submitQuery()
        } label: {
            Text(text)
                .font(.systemScaled(13, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.accentColor.opacity(0.12), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Citations

    private var citationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCES")
                .font(.systemScaled(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)

            ForEach(citations) { citation in
                HStack(spacing: 8) {
                    Image(systemName: citation.sourceType.icon)
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(citation.label)
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.primary)
                        if !citation.snippetPreview.isEmpty {
                            Text(citation.snippetPreview)
                                .font(.systemScaled(11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.03))
                )
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask anything...", text: $query, axis: .vertical)
                .font(.systemScaled(15))
                .lineLimit(1...4)
                .focused($isInputFocused)
                .onSubmit { submitQuery() }

            Button {
                submitQuery()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.systemScaled(30))
                    .foregroundStyle(query.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    // MARK: - Logic

    private func loadSources() {
        activeTask = Task {
            sourceBundle = await selahService.buildSourceBundle(
                forVerses: initialVerses,
                query: initialQuery
            )
        }
    }

    private func submitQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isStreaming else { return }

        hasSubmitted = true
        isStreaming = true
        streamedContent = ""
        citations = []
        errorMessage = nil
        isInputFocused = false

        let currentBundle = sourceBundle

        activeTask?.cancel()
        activeTask = Task {
            do {
                let stream = selahService.askSelah(
                    query: trimmed,
                    sourceBundle: currentBundle
                )

                for try await chunk in stream {
                    guard !Task.isCancelled else { break }
                    streamedContent += chunk
                }

                // Extract citations from response
                extractCitations(from: streamedContent)
                isStreaming = false
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                isStreaming = false
            }
        }
    }

    private func extractCitations(from text: String) {
        // Find bracketed references like [John 3:16] or [Note: Sunday Sermon]
        let pattern = try? NSRegularExpression(pattern: #"\[([^\]]+)\]"#)
        let range = NSRange(text.startIndex..., in: text)
        var found: [SelahCitation] = []

        pattern?.enumerateMatches(in: text, range: range) { match, _, _ in
            if let match = match, let labelRange = Range(match.range(at: 1), in: text) {
                let label = String(text[labelRange])
                let type: SelahCitation.SourceType
                if label.lowercased().hasPrefix("note:") {
                    type = .note
                } else if label.lowercased().hasPrefix("prayer:") {
                    type = .prayer
                } else {
                    type = .scripture
                }
                if !found.contains(where: { $0.label == label }) {
                    found.append(SelahCitation(label: label, sourceType: type, snippetPreview: ""))
                }
            }
        }
        citations = found
    }
}
