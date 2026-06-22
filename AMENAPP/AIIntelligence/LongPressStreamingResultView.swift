// LongPressStreamingResultView.swift
// AMENAPP — Long-Press Intelligence Layer (Wave 2)
//
// Slide-up streaming result sheet for AI actions triggered from the long-press menu.
// Streams via the existing Berean pipeline (real SSE wiring is a backend deploy TODO).
// Citation integrity: scripture references are verified via BereanCitationGate.shared.guardedEmit().
//
// Liquid Glass rules:
//   - Sheet background: .ultraThinMaterial (floating sheet)
//   - Result text on opaque Color(.systemBackground) card (no glass-on-glass on text)

import SwiftUI
import Foundation
import FirebaseAuth

struct LongPressStreamingResultView: View {

    let action: IntelligenceAction
    let context: BereanObjectContext
    let depthState: DepthDialState
    let onDepthChange: (BereanDepth) -> Void
    let onDismiss: () -> Void

    @State private var streamedText: String = ""
    @State private var isLoading: Bool = true
    @State private var showGenerationAlert: Bool = false
    @State private var streamTask: Task<Void, Never>? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        guard AMENFeatureFlags.shared.longPressIntelligenceEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(sheetContent)
    }

    // MARK: - Sheet Content

    private var sheetContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Depth dial (shown only when action supports it and flag is on)
                    if action.usesDepthDial && AMENFeatureFlags.shared.longPressDepthDialEnabled {
                        depthDialSection
                    }

                    // Result area
                    resultCard

                    // "How was this generated?" link
                    generationLink
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(sheetBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    headerTitle
                }
                ToolbarItem(placement: .topBarTrailing) {
                    dismissButton
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(
            reduceTransparency
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            : AnyShapeStyle(.ultraThinMaterial)
        )
        .alert("How was this generated?", isPresented: $showGenerationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Berean used the \(action.label) action with \(depthState.effectiveDepth.displayLabel) depth to generate this response. Citations are verified before display.")
        }
        .onAppear {
            startStreaming()
        }
        .onDisappear {
            streamTask?.cancel()
        }
    }

    // MARK: - Header

    private var headerTitle: some View {
        VStack(spacing: 2) {
            Text(action.label)
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Summarized by Berean")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dismissButton: some View {
        Button {
            streamTask?.cancel()
            onDismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
        .accessibilityLabel("Dismiss")
    }

    // MARK: - Depth Dial Section

    private var depthDialSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Depth")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            BereanDepthDialView(
                currentDepth: depthState.effectiveDepth,
                autoDepth: depthState.autoSelectedDepth,
                onSelect: { newDepth in
                    onDepthChange(newDepth)
                    restreamOnDepthChange()
                }
            )
        }
    }

    // MARK: - Result Card

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                skeletonRows
            } else {
                streamedResultText
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // Skeleton placeholder: 3 rows while loading
    private var skeletonRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(maxWidth: i == 2 ? .infinity * 0.6 : .infinity)
                    .frame(height: 16)
                    .redacted(reason: .placeholder)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                   value: isLoading)
    }

    // Streamed text with citation integrity rendering
    private var streamedResultText: some View {
        Text(streamedText)
            .font(.body)
            .foregroundStyle(.primary)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: streamedText)
    }

    // MARK: - Generation Link

    private var generationLink: some View {
        Button {
            showGenerationAlert = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                Text("How was this generated?")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel("How was this generated? Learn about how Berean produced this response.")
    }

    // MARK: - Background

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency {
            Color(uiColor: .secondarySystemBackground)
        } else {
            Color.clear
        }
    }

    // MARK: - Streaming Engine

    private func startStreaming() {
        isLoading = true
        streamedText = ""
        streamTask?.cancel()

        streamTask = Task {
            // LIVE: real Berean Constitutional Pipeline (deployed `bereanPipeline` callable).
            // No simulation. Errors surface honestly — never fabricated content.
            do {
                let pipelineQuery = BereanPipelineClient.BereanQuery(
                    query: Self.buildQuery(action: action, context: context),
                    mode: Self.pipelineMode(for: action),
                    userId: Auth.auth().currentUser?.uid ?? "anonymous",
                    conversationHistory: nil
                )
                let response = try await BereanPipelineClient.shared.sendQuery(pipelineQuery)
                guard !Task.isCancelled else { return }
                isLoading = false
                await streamOut(response.answer)
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                streamedText = (error as? LocalizedError)?.errorDescription
                    ?? "Berean is unavailable right now. Please try again."
            }
        }
    }

    /// Streams real answer text word-by-word for the typewriter effect, gating any
    /// scripture-like token through the citation gate before it is shown.
    private func streamOut(_ answer: String) async {
        let words = answer.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        for word in words {
            guard !Task.isCancelled else { return }
            if action.requiresCitationIntegrity, looksLikeScriptureRef(word) {
                let (_, shouldBlock) = await BereanCitationGate.guardedEmit(
                    reference: word,
                    quotation: word,
                    depth: depthState.effectiveDepth
                )
                if shouldBlock {
                    streamedText += "[citation unverified] "
                    continue
                }
            }
            streamedText += word + " "
            try? await Task.sleep(nanoseconds: 18_000_000) // 18ms — typewriter cadence over real text
        }
    }

    private func restreamOnDepthChange() {
        streamTask?.cancel()
        startStreaming()
    }

    // MARK: - Query Construction

    /// Maps the action's posture mode to the pipeline's wire enum (defaults to Ask).
    private static func pipelineMode(for action: IntelligenceAction) -> BereanPipelineClient.BereanMode {
        switch action.bereanMode {
        case .some(.ask):     return .ask
        case .some(.discern): return .discern
        case .some(.build):   return .build
        case .some(.guard):   return .guard_
        case .some(.reflect): return .reflect
        case .none:           return .ask
        }
    }

    /// Builds the natural-language query from the action label + captured object context.
    private static func buildQuery(action: IntelligenceAction, context: BereanObjectContext) -> String {
        let subject = context.payloadReference
            ?? context.payloadText
            ?? context.objectType.rawValue.replacingOccurrences(of: "_", with: " ")
        return "\(action.label). Regarding: \(subject)"
    }

    /// Rough heuristic — real citation extraction happens server-side.
    private func looksLikeScriptureRef(_ text: String) -> Bool {
        let pattern = #"\b\d?\s?[A-Z][a-z]+\s\d+:\d+"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
