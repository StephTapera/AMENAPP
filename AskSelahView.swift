//
//  AskSelahView.swift
//  AMENAPP
//
//  "Ask Selah" grounded AI workspace — lets users ask theological questions
//  with responses grounded in their own notes, prayers, testimonies, and Scripture.
//

import SwiftUI

struct AskSelahView: View {
    @ObservedObject private var selahService = SelahService.shared
    @State private var query = ""
    @State private var isStreaming = false
    @State private var streamedResponse = ""
    @State private var sourceBundle: SelahSourceBundle = .empty
    @State private var citations: [SelahCitation] = []
    @State private var showSources = false
    @State private var selectedFormat: SelahFormat = .essay
    @State private var streamTask: Task<Void, Never>?
    @FocusState private var isQueryFocused: Bool

    // Contextual — optionally pre-seeded with a verse or prior Selah content
    var initialQuery: String = ""
    var initialVerses: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // Source pills strip
            sourcePillsStrip
                .padding(.bottom, 8)

            // Response area
            if !streamedResponse.isEmpty || isStreaming {
                responseArea
            } else {
                emptyStatePrompt
            }

            Spacer(minLength: 0)

            // Input bar
            inputBar
        }
        .onAppear {
            if !initialQuery.isEmpty {
                query = initialQuery
                submitQuery()
            }
        }
    }

    // MARK: - Source Pills Strip

    private var sourcePillsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                sourcePill(
                    icon: "book.fill",
                    label: "\(sourceBundle.verses.count) Verses",
                    isActive: !sourceBundle.verses.isEmpty
                )
                sourcePill(
                    icon: "note.text",
                    label: "\(sourceBundle.notes.count) Notes",
                    isActive: !sourceBundle.notes.isEmpty
                )
                sourcePill(
                    icon: "hands.sparkles",
                    label: "\(sourceBundle.prayers.count) Prayers",
                    isActive: !sourceBundle.prayers.isEmpty
                )
                sourcePill(
                    icon: "heart.text.clipboard",
                    label: "\(sourceBundle.testimonies.count) Testimonies",
                    isActive: !sourceBundle.testimonies.isEmpty
                )

                Spacer()

                // Toggle sources panel
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                        showSources.toggle()
                    }
                } label: {
                    Image(systemName: showSources ? "eye.slash" : "eye")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
    }

    private func sourcePill(icon: String, label: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.systemScaled(10, weight: .semibold))
            Text(label)
                .font(.systemScaled(11, weight: .medium))
        }
        .foregroundStyle(isActive ? Color.accentColor : .secondary.opacity(0.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(isActive ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
        )
    }

    // MARK: - Empty State

    private var emptyStatePrompt: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary.opacity(0.4))

            Text("Ask Selah")
                .font(.systemScaled(22, weight: .bold, design: .serif))
                .foregroundStyle(.primary)

            Text("Ask anything about Scripture, theology, or your spiritual journey.\nSelah grounds its answers in your notes, prayers, and study history.")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 40)

            // Suggestion chips
            VStack(spacing: 8) {
                suggestionChip("What does Romans 8:28 mean for me right now?")
                suggestionChip("How do my recent prayers connect to this verse?")
                suggestionChip("Summarize what I've been studying this week")
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            query = text
            submitQuery()
        } label: {
            Text(text)
                .font(.systemScaled(13, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    // MARK: - Response Area

    private var responseArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Query display
                Text(query)
                    .font(.systemScaled(18, weight: .bold, design: .serif))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                // Streaming response
                Text(streamedResponse)
                    .font(.systemScaled(15))
                    .foregroundStyle(.primary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                if isStreaming {
                    SelahThinkingDots()
                        .padding(.horizontal, 24)
                }

                // Citations
                if !citations.isEmpty {
                    citationsSection
                }

                // Sources detail (expandable)
                if showSources && !sourceBundle.verses.isEmpty {
                    sourcesDetailSection
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var citationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCES")
                .font(.systemScaled(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)

            ForEach(citations) { citation in
                HStack(spacing: 8) {
                    Image(systemName: citationIcon(for: citation.type))
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(citation.label)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.08), in: Capsule())
            }
        }
        .padding(.horizontal, 24)
    }

    private func citationIcon(for type: SelahCitation.CitationType) -> String {
        switch type {
        case .scripture:      return "book.fill"
        case .churchNote:     return "note.text"
        case .prayer:         return "hands.sparkles"
        case .testimony:      return "heart.text.clipboard"
        case .bereanHistory:  return "brain"
        }
    }

    private var sourcesDetailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GROUNDING CONTEXT")
                .font(.systemScaled(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)

            ForEach(sourceBundle.verses) { verse in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verse.reference)
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(verse.text)
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(10)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask Selah anything...", text: $query, axis: .vertical)
                .font(.systemScaled(15))
                .lineLimit(1...4)
                .focused($isQueryFocused)
                .textFieldStyle(.plain)
                .onSubmit { submitQuery() }

            Button {
                if isStreaming {
                    cancelStream()
                } else {
                    submitQuery()
                }
            } label: {
                Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
                            ? Color.secondary.opacity(0.3)
                            : Color.accentColor
                    )
            }
            .buttonStyle(.plain)
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
        }
    }

    // MARK: - Logic

    private func submitQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isQueryFocused = false

        // Detect scripture references in the query
        let detectedRefs = SelahParser.parse(response: trimmed, format: .bullets)
            .flatMap { $0.references }
        let allVerses = initialVerses + detectedRefs

        streamedResponse = ""
        isStreaming = true

        streamTask = Task {
            // 1. Build source bundle
            sourceBundle = await selahService.buildSourceBundle(
                forVerses: allVerses,
                query: trimmed
            )

            // 2. Build citations from sources
            var detectedCitations: [SelahCitation] = []
            for verse in sourceBundle.verses {
                detectedCitations.append(SelahCitation(
                    type: .scripture, label: verse.reference, sourceId: nil
                ))
            }
            for note in sourceBundle.notes {
                detectedCitations.append(SelahCitation(
                    type: .churchNote, label: note.title, sourceId: note.id
                ))
            }
            await MainActor.run { citations = detectedCitations }

            // 3. Stream AI response
            do {
                let stream = selahService.askSelah(
                    query: trimmed,
                    sourceBundle: sourceBundle,
                    format: selectedFormat
                )
                for try await chunk in stream {
                    guard !Task.isCancelled else { break }
                    await MainActor.run { streamedResponse += chunk }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { streamedResponse += "\n\n⚠️ Could not complete response." }
                }
            }

            await MainActor.run { isStreaming = false }
        }
    }

    private func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
}
