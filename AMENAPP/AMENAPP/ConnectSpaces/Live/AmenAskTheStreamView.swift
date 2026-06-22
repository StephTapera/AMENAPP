// AmenAskTheStreamView.swift
// AMEN Connect + Spaces — Post-Stream AI Q&A Search
// Built: 2026-06-03

import SwiftUI
import FirebaseFunctions

// MARK: - Local types

private struct StreamAnswer: Identifiable {
    let id: UUID = UUID()
    var answer: String
    var sourceQuote: String?
    var sourceTimestamp: String?
    var scriptureRefs: [String]
    var confidence: Double
}

// MARK: - Main view

struct AmenAskTheStreamView: View {
    let streamId: String
    let streamTitle: String

    @State private var query: String = ""
    @State private var isSearching: Bool = false
    @State private var searchResult: StreamAnswer? = nil
    @State private var searchError: String? = nil
    @State private var suggestedQuestions: [String] = [
        "What was said about forgiveness?",
        "What action items were given?",
        "What scriptures were referenced?",
        "What prayer requests were made?"
    ]

    @FocusState private var queryFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let functions = Functions.functions()

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                searchBarSection
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                Divider().opacity(0.15)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if isSearching {
                            searchingState
                                .padding(.top, 40)
                        } else if let error = searchError {
                            errorState(error)
                                .padding(.top, 40)
                        } else if let result = searchResult {
                            resultSection(result)
                        } else {
                            emptyState
                                .padding(.top, 48)
                        }

                        suggestionsSection
                            .padding(.top, searchResult == nil && !isSearching ? 0 : 8)

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
        }
        .navigationTitle("Ask the Stream")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Search Bar

    private var searchBarSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
                .accessibilityHidden(true)

            TextField("Ask anything about this stream…", text: $query)
                .font(.systemScaled(15))
                .foregroundStyle(.white)
                .tint(Color(hex: "D9A441"))
                .submitLabel(.search)
                .focused($queryFocused)
                .onSubmit { submitQuery() }
                .accessibilityLabel("Search question input")

            if !query.isEmpty {
                Button {
                    submitQuery()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.systemScaled(26))
                        .foregroundStyle(Color(hex: "D9A441"))
                }
                .buttonStyle(.plain)
                .disabled(isSearching)
                .accessibilityLabel("Submit question")
                .transition(
                    reduceMotion
                        ? .opacity
                        : .scale.combined(with: .opacity)
                )
                .animation(
                    reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.25, dampingFraction: 0.7),
                    value: query.isEmpty
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass.circle")
                .font(.systemScaled(56, weight: .ultraLight))
                .foregroundStyle(Color.white.opacity(0.2))
                .accessibilityHidden(true)
            Text("Ask anything about this stream")
                .font(.systemScaled(16, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Your question will be answered from the stream's transcript.")
                .font(.systemScaled(13))
                .foregroundStyle(Color.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ask anything about this stream. Your question will be answered from the stream transcript.")
    }

    // MARK: - Searching State

    private var searchingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color(hex: "D9A441"))
                .scaleEffect(1.2)
            Text("Searching the transcript…")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Searching transcript, please wait")
    }

    // MARK: - Error State

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(32))
                .foregroundStyle(Color.red.opacity(0.65))
                .accessibilityHidden(true)
            Text(message)
                .font(.systemScaled(14))
                .foregroundStyle(Color.red.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                submitQuery()
            } label: {
                Text("Try Again")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background {
                        Capsule()
                            .fill(Color(hex: "D9A441").opacity(0.14))
                            .overlay {
                                Capsule().strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 1)
                            }
                    }
            }
            .accessibilityLabel("Retry search")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Result Section

    @ViewBuilder
    private func resultSection(_ result: StreamAnswer) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Answer card — matte content area
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color(hex: "D9A441"))
                        .accessibilityHidden(true)
                    Text("Answer")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.5)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Answer")

                Text(result.answer)
                    .font(.systemScaled(15))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if result.confidence < 0.6 {
                    HStack(spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(.systemScaled(11))
                            .accessibilityHidden(true)
                        Text("Low confidence — this answer may be incomplete.")
                            .font(.systemScaled(11))
                    }
                    .foregroundStyle(Color.yellow.opacity(0.65))
                    .accessibilityLabel("Low confidence answer — may be incomplete")
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    }
            }

            // Source Quote pull-quote
            if let quote = result.sourceQuote, !quote.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                            .font(.systemScaled(11))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .accessibilityHidden(true)
                        Text("From the transcript")
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .kerning(0.5)
                    }
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("From the transcript")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("\u{201C}\(quote)\u{201D}")
                            .font(.systemScaled(13).italic())
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)

                        if let ts = result.sourceTimestamp, !ts.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.systemScaled(10))
                                    .accessibilityHidden(true)
                                Text(ts)
                                    .font(.systemScaled(11))
                            }
                            .foregroundStyle(Color(hex: "D9A441").opacity(0.75))
                            .accessibilityLabel("Timestamp: \(ts)")
                        }
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color(hex: "D9A441").opacity(0.6))
                                    .frame(width: 3)
                                    .padding(.vertical, 4)
                            }
                    }
                }
            }

            // Scripture Refs chips
            if !result.scriptureRefs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scripture References")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.5)
                        .accessibilityAddTraits(.isHeader)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(result.scriptureRefs, id: \.self) { ref in
                                Text(ref)
                                    .font(.systemScaled(12, weight: .medium))
                                    .foregroundStyle(Color(hex: "D9A441"))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background {
                                        Capsule()
                                            .fill(Color(hex: "D9A441").opacity(0.13))
                                            .overlay {
                                                Capsule()
                                                    .strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 1)
                                            }
                                    }
                                    .accessibilityLabel(ref)
                            }
                        }
                    }
                }
            }
        }
        .transition(
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .move(edge: .bottom))
        )
    }

    // MARK: - Suggestions

    @ViewBuilder
    private var suggestionsSection: some View {
        if !suggestedQuestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Suggested Questions")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .accessibilityAddTraits(.isHeader)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestedQuestions, id: \.self) { suggestion in
                            Button {
                                let anim: Animation? = reduceMotion
                                    ? nil
                                    : .spring(response: 0.2, dampingFraction: 0.8)
                                withAnimation(anim) {
                                    query = suggestion
                                }
                                submitQuery()
                            } label: {
                                Text(suggestion)
                                    .font(.systemScaled(13))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background {
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                            .overlay {
                                                Capsule()
                                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                            }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Suggested: \(suggestion)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Search Action

    private func submitQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSearching else { return }

        queryFocused = false
        isSearching = true
        searchResult = nil
        searchError = nil

        Task { @MainActor in
            defer { isSearching = false }
            do {
                let callable = functions.httpsCallable("askStreamTranscript")
                let result = try await callable.call([
                    "streamId": streamId,
                    "question": trimmed
                ])
                guard let data = result.data as? [String: Any] else {
                    searchError = "Unexpected response. Please try again."
                    return
                }
                let answer = data["answer"] as? String ?? ""
                let sourceQuote = data["sourceQuote"] as? String
                let sourceTimestamp = data["sourceTimestamp"] as? String
                let scriptureRefs = data["scriptureRefs"] as? [String] ?? []
                let confidence = data["confidence"] as? Double ?? 1.0

                let anim: Animation? = reduceMotion
                    ? nil
                    : .spring(response: 0.35, dampingFraction: 0.8)
                withAnimation(anim) {
                    searchResult = StreamAnswer(
                        answer: answer,
                        sourceQuote: sourceQuote,
                        sourceTimestamp: sourceTimestamp,
                        scriptureRefs: scriptureRefs,
                        confidence: confidence
                    )
                }
            } catch {
                searchError = error.localizedDescription
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AmenAskTheStreamView(
            streamId: "stream-001",
            streamTitle: "Sunday Morning Teaching: Grace and Redemption"
        )
    }
    .preferredColorScheme(.dark)
}
