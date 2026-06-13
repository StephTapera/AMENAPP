// NISDetectionStatusBar.swift
// AMEN — NIS Wave 1, Lane D
// Shows processing state + proposed detection count above the block list.
// Gated: only visible when nisDetectionLayerEnabled = true.

import SwiftUI

/// A thin capsule status bar that surfaces NIS processing state and detection count.
///
/// Placement: above the block list in `ChurchNoteSemanticEditorView`.
/// Entry point: `ChurchNoteSemanticEditorView → nisBridge.observe(noteId:) → NISDetectionStatusBar`
///
/// State behaviour:
/// - `.idle` / `.done(0)` → hidden
/// - `.processing`        → pulsing capsule "Analyzing note…"
/// - `.done(N)` N > 0     → accent capsule "N suggestion(s) found"
/// - `.error`             → muted red capsule "NIS unavailable"
struct NISDetectionStatusBar: View {

    @ObservedObject var bridge: NISEditorBridge

    var body: some View {
        // Feature flag gate — nothing rendered when flag is off.
        if AMENFeatureFlags.shared.nisDetectionLayerEnabled {
            content
                .animation(.easeInOut(duration: 0.3), value: bridge.processingState)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch bridge.processingState {
        case .idle:
            EmptyView()

        case .processing:
            processingCapsule

        case .done(let count) where count > 0:
            suggestionsCapsule(count: count)

        case .done:
            // done(0) — no suggestions, stay hidden
            EmptyView()

        case .error:
            errorCapsule
        }
    }

    // MARK: - Processing capsule

    private var processingCapsule: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.65)
                .tint(.secondary)
            Text("Analyzing note…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analyzing note")
    }

    // MARK: - Suggestions capsule

    private func suggestionsCapsule(count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(Color.accentColor)
            Text(count == 1 ? "1 suggestion found" : "\(count) suggestions found")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.10), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count == 1 ? "1 suggestion found" : "\(count) suggestions found")
    }

    // MARK: - Error capsule

    private var errorCapsule: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("NIS unavailable")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.systemRed).opacity(0.08), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notes Intelligence System unavailable")
    }
}
