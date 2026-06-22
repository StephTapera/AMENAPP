// AILScriptureExplanationPanel.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Language Surface (A3)
//
// Scripture explanation. Renders a canonical verse VERBATIM and, in a clearly
// separated section, an AI explanation produced via transform(.explainScripture).
//
// IRON RULES — these are load-bearing for this view:
//   • The canonical verse text is LOCKED. It is rendered byte-identical to the
//     input string and is NEVER passed through translate/simplify/any transform.
//     Only the (separate) explanation is AI-generated.
//   • The explanation is clearly labeled "Explanation — not Scripture" so a
//     reader can never mistake commentary for the inspired text.
//   • explainScripture is the one cite-or-refuse task. On failOpen we show a
//     quiet "Explanation unavailable" — we NEVER fabricate scripture explanation.
//   • The AI output carries provenance. (There is no "view original" toggle on
//     the verse: the verse is always present and untransformed above it.)
//   • Reduce Transparency → opaque section background. Reduce Motion → no anim.
//   • NO tier checks.

import SwiftUI

struct AILScriptureExplanationPanel: View {

    /// The canonical verse text — LOCKED. Rendered verbatim, never transformed.
    let canonicalVerse: String
    /// Human-readable reference, e.g. "John 3:16". Shown with the verse and sent
    /// (with the verse) as context to explainScripture.
    let reference: String

    private enum Phase: Equatable {
        case idle          // explanation not requested yet
        case loading       // explainScripture in flight
        case explained     // success — explanation available
        case unavailable   // failOpen / refusal — quiet "unavailable", no fabrication
    }

    @State private var phase: Phase = .idle
    @State private var result: A11yTransformResult?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            verseSection
            Divider()
            explanationSection
        }
        .padding(16)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: phase)
    }

    // MARK: - Canonical verse (LOCKED, verbatim)

    private var verseSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(reference)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            // Byte-identical render of the input. No transform, ever.
            Text(canonicalVerse)
                .font(.body)
                .textSelection(.enabled)
                .accessibilityLabel(Text("\(reference). \(canonicalVerse)"))
        }
    }

    // MARK: - Explanation (clearly NOT Scripture)

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Unmissable label separating commentary from the inspired text.
            Label("Explanation — not Scripture", systemImage: "text.bubble")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Explanation. This is commentary, not Scripture."))

            explanationContent
        }
    }

    @ViewBuilder
    private var explanationContent: some View {
        switch phase {
        case .idle:
            Button {
                runExplain()
            } label: {
                Label("Explain this passage", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityHint(Text("Generates an explanation of this passage. The explanation is not Scripture."))

        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Preparing explanation…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Preparing explanation"))

        case .explained:
            if let result, let text = result.text, !text.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                    AILProvenanceLabel(provenance: result.provenance)
                }
            } else {
                // A "success" with no body is treated as unavailable — never blank.
                unavailableView
            }

        case .unavailable:
            unavailableView
        }
    }

    /// Quiet, honest unavailable state. We NEVER fabricate scripture explanation.
    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Explanation unavailable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Explanation is unavailable right now."))
            Button {
                runExplain()
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var panelBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - Transform

    private func runExplain() {
        phase = .loading
        // Send reference + verse as context. The verse string above is untouched;
        // this is the ONLY place the verse text travels, and only to be EXPLAINED.
        let input = "\(reference)\n\(canonicalVerse)"
        Task {
            let res = await AILTransformService.shared.transform(
                task: .explainScripture,
                input: input,
                originalRef: reference
            )
            await MainActor.run {
                self.result = res
                // explainScripture fails CLOSED at the model, but from the UI this
                // is still a quiet "unavailable" — never a fabricated explanation.
                self.phase = res.failOpen ? .unavailable : .explained
            }
        }
    }
}
