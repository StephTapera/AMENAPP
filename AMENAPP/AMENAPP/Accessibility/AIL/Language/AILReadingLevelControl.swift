// AILReadingLevelControl.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Language Surface (A3)
//
// C2 Reading Level. Two reusable pieces:
//
//   • AILReadingLevelControl — a segmented Picker over ReadingLevel, bound to
//     AILProfileService.shared.profile.readingLevel via setReadingLevel(_:). The
//     user's choice is a portable preference (synced by the profile service).
//
//   • AILReadingLevelText — renders a block of text at the user's chosen reading
//     level. At .original it shows the original verbatim. At any other level it
//     routes through transform(.simplify, readingLevel:), shows the simplified
//     text with provenance + a one-tap "View original", and re-runs when the
//     level changes.
//
// IRON RULES honored here:
//   • FAIL OPEN — failOpen results render the ORIGINAL with a quiet caption.
//   • Every AI output is labeled (provenance) and reversible ("View original").
//   • Scripture must NOT be re-leveled — this view is for ordinary prose; the
//     scripture panel renders canonical verse text verbatim and only EXPLAINS.
//   • Reduce Motion → no animation. NO tier checks.

import SwiftUI

// MARK: - Segmented reading-level picker

/// Segmented control bound to the user's persisted reading-level preference.
struct AILReadingLevelControl: View {

    /// Observe the shared profile so the picker reflects external changes too.
    @State private var profileService = AILProfileService.shared

    var body: some View {
        Picker("Reading level", selection: levelBinding) {
            ForEach(ReadingLevel.allCases, id: \.self) { level in
                Text(level.displayName).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(Text("Reading level"))
        .accessibilityHint(Text("Choose how simply text is shown to you."))
    }

    /// Two-way binding that writes through the profile service's setter so the
    /// choice persists locally and syncs to the account.
    private var levelBinding: Binding<ReadingLevel> {
        Binding(
            get: { profileService.profile.readingLevel },
            set: { profileService.setReadingLevel($0) }
        )
    }
}

// MARK: - Reading-level-aware text

/// Renders `originalText` at the user's chosen reading level. Ordinary prose
/// only — never Scripture verse text.
struct AILReadingLevelText: View {

    let originalText: String
    let originalRef: String

    private enum Phase: Equatable {
        case original          // showing the verbatim original (level == .original or toggled)
        case loading           // simplify in flight
        case simplified        // success — showing simplified text
        case failOpen          // simplify failed — original shown + caption
    }

    @State private var profileService = AILProfileService.shared
    @State private var phase: Phase = .original
    @State private var result: A11yTransformResult?
    /// The level we last produced text for — guards against redundant calls.
    @State private var renderedLevel: ReadingLevel = .original
    /// User explicitly toggled back to original despite a non-original level.
    @State private var userForcedOriginal = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var level: ReadingLevel { profileService.profile.readingLevel }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
            controls
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: phase)
        // Initial render + react to reading-level changes.
        .task(id: level) { syncToLevel() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .original:
            Text(originalText).textSelection(.enabled)

        case .loading:
            VStack(alignment: .leading, spacing: 6) {
                Text(originalText)
                    .textSelection(.enabled)
                    .opacity(0.6)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Simplifying…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Simplifying"))
            }

        case .simplified:
            if let result, let text = result.text, !text.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(text).textSelection(.enabled)
                    AILProvenanceLabel(provenance: result.provenance)
                }
            } else {
                Text(originalText).textSelection(.enabled)
            }

        case .failOpen:
            // FAIL OPEN — show the original verbatim, quiet caption only.
            VStack(alignment: .leading, spacing: 4) {
                Text(originalText).textSelection(.enabled)
                Text("Simpler version unavailable")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(Text("A simpler version is unavailable. Showing the original."))
            }
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        switch phase {
        case .simplified:
            AILViewOriginalButton(isShowingOriginal: false) {
                userForcedOriginal = true
                phase = .original
            }
        case .original:
            // If a non-original level is active but the user toggled to original,
            // offer a way back to the simplified rendering.
            if level != .original && userForcedOriginal {
                AILViewOriginalButton(isShowingOriginal: true) {
                    userForcedOriginal = false
                    syncToLevel()
                }
            }
        case .failOpen:
            Button {
                runSimplify()
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        case .loading:
            EmptyView()
        }
    }

    // MARK: - Level sync

    /// Bring the rendered text in line with the current reading level.
    private func syncToLevel() {
        guard !userForcedOriginal else { return }
        if level == .original {
            phase = .original
            result = nil
            renderedLevel = .original
            return
        }
        // Avoid re-running if we already produced text for this level.
        if phase == .simplified && renderedLevel == level { return }
        runSimplify()
    }

    private func runSimplify() {
        let requested = level
        phase = .loading
        Task {
            let res = await AILTransformService.shared.transform(
                task: .simplify,
                input: originalText,
                originalRef: originalRef,
                readingLevel: requested
            )
            await MainActor.run {
                self.result = res
                self.renderedLevel = requested
                // FAIL OPEN: any failOpen result shows the original quietly.
                self.phase = res.failOpen ? .failOpen : .simplified
            }
        }
    }
}
