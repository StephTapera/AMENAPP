// AILAudioSummaryCard.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Perception Surface (A4)
//
// A card that summarizes a voice-note / audio transcript (.summarizeAudio) into a
// short, scannable Main point / What's being asked / Tone. Every summary carries a
// provenance label and a one-tap "View original" so the listener can always reach
// the full transcript.
//
// FAIL OPEN (iron rule 3): if the transform fails open, the card shows a quiet
// "summary unavailable" state with View original still available — the audio /
// transcript is never blocked or hidden by a missing summary.
//
// The card parses the model's labeled lines best-effort; if it can't, it shows the
// whole summary as the main point. The summary NEVER fabricates content beyond the
// transcript — the backend prompt owns that; here we only display what's returned.
//
// NO tier checks. No force-unwraps. 4-space indent. Six UI states below.

import SwiftUI

/// Summarizes `transcript`; `originalRef` resolves the full original for review.
struct AILAudioSummaryCard: View {

    let transcript: String
    let originalRef: String

    /// Fires when the listener taps "View original".
    var onViewOriginal: (() -> Void)? = nil

    // MARK: - Six UI states
    private enum Phase: Equatable {
        case idle            // 1. not yet requested
        case loading         // 2. transform in flight
        case ready           // 3. parsed main point / action / tone
        case readyPlain      // 4. summary returned but unlabeled — show as one block
        case failedOpen      // 5. failed open — quiet "unavailable" + View original
        case showingOriginal // 6. listener expanded the full transcript
    }

    private struct Summary: Equatable {
        var mainPoint: String
        var action: String?
        var tone: String?
    }

    @State private var phase: Phase = .idle
    @State private var summary: Summary = Summary(mainPoint: "", action: nil, tone: nil)
    @State private var provenance: A11yProvenance = .aiGenerated

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch phase {
            case .idle:
                summarizeButton
            case .loading:
                loadingRow
            case .ready, .readyPlain:
                summaryBody
                footer
            case .failedOpen:
                unavailableRow
                footer
            case .showingOriginal:
                originalBody
                footer
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        Label("Audio summary", systemImage: "waveform")
            .font(.headline)
    }

    // MARK: - State 1: idle

    private var summarizeButton: some View {
        Button {
            Task { await summarize() }
        } label: {
            Label("Summarize this audio", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint(Text("Creates a short summary of the recording."))
    }

    // MARK: - State 2: loading

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Summarizing…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - States 3/4: summary

    private var summaryBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryRow(title: "Main point", value: summary.mainPoint)
            if let action = summary.action, !action.isEmpty {
                summaryRow(title: "What's being asked", value: action)
            }
            if let tone = summary.tone, !tone.isEmpty {
                summaryRow(title: "Tone", value: tone)
            }
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title): \(value)"))
    }

    // MARK: - State 5: failed open

    private var unavailableRow: some View {
        Label("Summary unavailable — you can still listen to the full audio.", systemImage: "exclamationmark.bubble")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: - State 6: original transcript

    private var originalBody: some View {
        ScrollView {
            Text(transcript)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: 240)
        .accessibilityLabel(Text("Full transcript: \(transcript)"))
    }

    // MARK: - Footer (provenance + view original / collapse)

    private var footer: some View {
        HStack(spacing: 12) {
            if phase != .failedOpen {
                AILProvenanceLabel(provenance: provenance)
            }
            Spacer(minLength: 0)
            AILViewOriginalButton(isShowingOriginal: phase == .showingOriginal) {
                onViewOriginal?()
                phase = (phase == .showingOriginal) ? lastSummaryPhase() : .showingOriginal
            }
        }
    }

    /// When collapsing the transcript, return to whichever summary state we had.
    private func lastSummaryPhase() -> Phase {
        if summary.mainPoint.isEmpty { return .failedOpen }
        return (summary.action == nil && summary.tone == nil) ? .readyPlain : .ready
    }

    // MARK: - Actions

    private func summarize() async {
        phase = .loading
        let result = await AILTransformService.shared.transform(
            task: .summarizeAudio,
            input: transcript,
            originalRef: originalRef
        )

        if result.failOpen {
            phase = .failedOpen
            return
        }

        let text = (result.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = .failedOpen
            return
        }

        provenance = result.provenance
        summary = Self.parse(text)
        phase = (summary.action == nil && summary.tone == nil) ? .readyPlain : .ready
    }

    // MARK: - Best-effort parsing of labeled lines

    /// Pulls "Main point / Action / Tone"-style lines out of the model output.
    /// Falls back to the whole text as the main point (readyPlain).
    private static func parse(_ text: String) -> Summary {
        var mainPoint: String?
        var action: String?
        var tone: String?

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }

            if key.contains("main") || key.contains("point") || key.contains("summary") {
                mainPoint = value
            } else if key.contains("ask") || key.contains("action") || key.contains("request") {
                action = value
            } else if key.contains("tone") || key.contains("feel") || key.contains("mood") {
                tone = value
            }
        }

        return Summary(
            mainPoint: mainPoint ?? text,
            action: action,
            tone: tone
        )
    }

    // MARK: - Chrome

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}
