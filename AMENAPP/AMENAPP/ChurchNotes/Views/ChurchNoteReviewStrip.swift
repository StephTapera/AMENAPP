// ChurchNoteReviewStrip.swift
// AMENAPP
//
// A lightweight "finishing pass" strip shown before the user closes a note.
// Non-blocking — user can dismiss it or tap Done without acting on any suggestion.
// Design: single-row horizontal scroll of glass pill suggestions.
// Never overlaps the keyboard. Appears above the bottom toolbar.

import SwiftUI

struct ChurchNoteReviewStrip: View {

    let suggestions: [CNReviewSuggestion]
    let onSuggestionTap: (CNReviewAction) -> Void
    let onDismiss: () -> Void

    @State private var isVisible = true

    var body: some View {
        if isVisible && !suggestions.isEmpty {
            VStack(spacing: 0) {
                // Strip label
                HStack {
                    Text("Before you finish")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation(ChurchNotesAnimationTokens.quickTap) {
                            isVisible = false
                        }
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel("Dismiss suggestions")
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

                // Suggestion chips — horizontal scroll, no forced interaction
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { suggestion in
                            reviewChip(suggestion)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
            // Solid system background — removed stacked glass + opacity overlay
            // because the chips inside used .thinMaterial too (glass-on-glass).
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 8, y: 3)
            )
            .padding(.horizontal, 12)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func reviewChip(_ suggestion: CNReviewSuggestion) -> some View {
        Button {
            withAnimation(ChurchNotesAnimationTokens.chipInsert) {
                isVisible = false
            }
            onSuggestionTap(suggestion.action)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: suggestion.icon)
                    .font(.systemScaled(12))
                    .accessibilityHidden(true)
                Text(suggestion.label)
                    .font(.systemScaled(13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Chip background — solid fill instead of glass, so the strip and
            // chips don't stack materials on each other (glass-on-glass).
            .background(
                Capsule()
                    .fill(Color(.secondarySystemFill))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(suggestion.label)
    }
}

// MARK: - Compact inline version (for use at bottom of editor)

/// Reduced version — just a single "complete your note?" row.
/// Used when space is tight (e.g., when keyboard is visible).
struct ChurchNoteReviewMiniBanner: View {

    let count: Int    // number of suggestions pending
    let onTap: () -> Void

    var body: some View {
        if count > 0 {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(count == 1
                         ? "1 thing you could add before finishing"
                         : "\(count) things you could add before finishing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color(.tertiaryLabel))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete your note: \(count) suggestion\(count == 1 ? "" : "s") available")
            .transition(.opacity)
        }
    }
}

#if DEBUG
struct ChurchNoteReviewStrip_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            ChurchNoteReviewStrip(
                suggestions: [
                    CNReviewSuggestion(icon: "lightbulb.fill", label: "Add a key insight", action: .addTakeaway),
                    CNReviewSuggestion(icon: "hands.sparkles.fill", label: "Add a prayer", action: .addPrayer),
                    CNReviewSuggestion(icon: "arrow.circlepath", label: "Revisit this later", action: .setReflectionReminder),
                ],
                onSuggestionTap: { _ in },
                onDismiss: {}
            )

            ChurchNoteReviewMiniBanner(count: 3, onTap: {})
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .previewDisplayName("Review Strip")
    }
}
#endif
