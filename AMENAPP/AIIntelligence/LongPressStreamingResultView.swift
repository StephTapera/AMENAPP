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
            // TODO(wave2-deploy): wire BereanSSEClient for real server-sent events.
            // For now, simulate streaming with chunk delivery using Task.sleep.
            let chunks = simulatedChunks(for: action, context: context, depth: depthState.effectiveDepth)
            isLoading = false

            for chunk in chunks {
                guard !Task.isCancelled else { return }

                // If this chunk contains a scripture-style reference and action requires
                // citation integrity, gate it before appending to the stream.
                if action.requiresCitationIntegrity, looksLikeScriptureRef(chunk) {
                    let (_, shouldBlock) = await BereanCitationGate.guardedEmit(
                        reference: chunk,
                        quotation: chunk,
                        depth: depthState.effectiveDepth
                    )
                    if shouldBlock {
                        streamedText += "[Citation unverified] "
                        continue
                    }
                }

                streamedText += chunk
                try? await Task.sleep(nanoseconds: 45_000_000) // 45ms between chunks
            }
        }
    }

    private func restreamOnDepthChange() {
        streamTask?.cancel()
        startStreaming()
    }

    // MARK: - Simulation

    private func simulatedChunks(
        for action: IntelligenceAction,
        context: BereanObjectContext,
        depth: BereanDepth
    ) -> [String] {
        // Produces plausible streaming chunks. Replace with BereanSSEClient output in prod.
        let base = "Based on your \(context.objectType.rawValue.replacingOccurrences(of: "_", with: " ")), "
        let depthNote = "at \(depth.displayLabel) depth, "
        let actionNote = "here is what Berean found for \"\(action.label)\": "
        let body = "This is a streamed Berean response. Real content will be delivered via SSE when the backend pipeline is wired. The response will respect the token ceiling (~\(depth.tokenCeiling / 1000)k tokens) and latency budget (≤\(depth.latencyBudgetMs / 1000)s) for this depth level."
        let fullText = base + depthNote + actionNote + body
        // Split by words for chunk simulation
        return fullText.components(separatedBy: " ").map { $0 + " " }
    }

    /// Rough heuristic — real citation extraction happens server-side.
    private func looksLikeScriptureRef(_ text: String) -> Bool {
        let pattern = #"\b\d?\s?[A-Z][a-z]+\s\d+:\d+"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
