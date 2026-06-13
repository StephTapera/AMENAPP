// BereanCoCreatorInlineView.swift
// AMEN App — Berean Co-Creator inline affordance for block editors
//
// Shows a subtle dismissible chip at the bottom of the active block
// when a suggestion is ready. Max 1 suggestion chip visible at any time.
//
// Design invariants:
//   - Suggestions are NEVER auto-inserted — user must tap "tap to add".
//   - Dismiss clears the suggestion; next block can get a new one.
//   - "Ask Berean" explicit invoke button always visible in toolbar.
//   - Breath animation on chip appear.
//   - Living Memory echo shown as a separate callout if present.
//
// Flag-gated: AMENFeatureFlags.shared.bereanCoCreator

import SwiftUI

// MARK: - Inline chip component

struct BereanCoCreatorInlineView: View {

    @ObservedObject private var flags = AMENFeatureFlags.shared
    @ObservedObject var service: BereanCoCreatorService

    let onInsert: (CoCreatorSuggestion) -> Void   // called when user taps "tap to add"

    @State private var chipVisible: Bool = false

    var body: some View {
        if !flags.bereanCoCreator {
            EmptyView()
        } else {
            content
                .onChange(of: service.currentSuggestion?.id) { _, newId in
                    if newId != nil {
                        withAnimation(Breath.inhale) {
                            chipVisible = true
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            chipVisible = false
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let suggestion = service.currentSuggestion, chipVisible {
            VStack(alignment: .leading, spacing: 8) {
                // Living Memory echo callout (shown above the main chip when present)
                if let echo = suggestion.personalEcho {
                    livingMemoryCallout(echo: echo)
                }

                // Main suggestion chip
                suggestionChip(suggestion: suggestion)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity
            ))
        }
    }

    // MARK: - Suggestion chip

    private func suggestionChip(suggestion: CoCreatorSuggestion) -> some View {
        HStack(spacing: 10) {
            kindIcon(for: suggestion.kind)
                .foregroundStyle(.secondary)

            Text(chipLabel(for: suggestion))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 4)

            // "tap to add" action
            Button {
                onInsert(suggestion)
                service.dismissSuggestion()
            } label: {
                Text("Add")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Add this Berean suggestion")

            // Dismiss
            Button {
                service.dismissSuggestion()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss Berean suggestion")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Berean suggestion: \(suggestion.content). Double-tap Add to insert, or dismiss.")
    }

    // MARK: - Living Memory callout

    private func livingMemoryCallout(echo: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "memories")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(echo)
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
        .accessibilityLabel("Living memory: \(echo)")
    }

    // MARK: - Helpers

    private func kindIcon(for kind: CoCreatorSuggestionKind) -> some View {
        switch kind {
        case .crossReference:
            return Image(systemName: "link")
        case .originalLanguage:
            return Image(systemName: "textformat.abc")
        case .livingMemoryEcho:
            return Image(systemName: "memories")
        }
    }

    private func chipLabel(for suggestion: CoCreatorSuggestion) -> String {
        switch suggestion.kind {
        case .crossReference:
            return suggestion.content
        case .originalLanguage:
            return suggestion.content
        case .livingMemoryEcho:
            return suggestion.content
        }
    }
}

// MARK: - Toolbar "Ask Berean" button

/// Drop this into any editor toolbar to give users explicit Berean invocation.
struct BereanCoCreatorToolbarButton: View {

    @ObservedObject private var flags = AMENFeatureFlags.shared
    @ObservedObject var service: BereanCoCreatorService

    let activeBlockText: String

    @State private var isInvoking: Bool = false

    var body: some View {
        if flags.bereanCoCreator {
            Button {
                Task { await explicitInvoke() }
            } label: {
                HStack(spacing: 5) {
                    if isInvoking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                    }
                    Text("Ask Berean")
                        .font(.subheadline)
                }
                .foregroundStyle(Color.accentColor)
            }
            .disabled(isInvoking || activeBlockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Ask Berean for a suggestion on this text")
        }
    }

    private func explicitInvoke() async {
        guard !activeBlockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isInvoking = true
        defer { isInvoking = false }
        _ = try? await service.invokeBerean(for: activeBlockText)
    }
}

// MARK: - Breath animation shim
// References the frozen Breath tokens from the BreathMotion system.
// If Breath is not yet in scope (other agents build first), use a safe fallback.

private extension Animation {
    static var inhale: Animation {
        // Breath.inhale from the frozen BreathMotion contracts
        .spring(response: 0.45, dampingFraction: 0.7)
    }
}
