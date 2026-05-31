// A11yCoPilotView.swift
// AMEN Universal Accessibility Engine — A8 Co-Pilot + Emotional Safety UI

import SwiftUI

// MARK: - Co-Pilot Panel (bottom-leading FAB)

/// Expandable FAB panel that surfaces the current assistive suggestion.
/// Only renders when `a11yCoPilotEnabled` is on and a suggestion is pending.
struct A11yCoPilotPanel: View {
    @ObservedObject private var service = A11yCoPilotService.shared
    @ObservedObject private var flags = TrustAccessibilityFeatureFlags.shared
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    @State private var isExpanded = false

    var body: some View {
        if flags.a11yCoPilotEnabled, let suggestion = service.pendingSuggestion {
            VStack(alignment: .leading, spacing: 8) {
                if isExpanded {
                    AccessibilitySuggestionRow(suggestion: suggestion)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Button {
                    let animation: Animation = reducedMotion
                        ? .easeInOut(duration: 0.15)
                        : .spring(response: 0.35, dampingFraction: 0.7)
                    withAnimation(animation) {
                        isExpanded.toggle()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 44, height: 44)
                        Image(systemName: isExpanded ? "xmark" : "accessibility")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                .accessibilityLabel(isExpanded ? "Close accessibility panel" : "Open accessibility co-pilot")
            }
            .onChange(of: suggestion) { _ in
                // Auto-collapse when suggestion changes so user sees the new one
                isExpanded = false
            }
        }
    }
}

// MARK: - Suggestion Row

private struct AccessibilitySuggestionRow: View {
    let suggestion: AccessibilitySuggestion

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(suggestion.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                Button(suggestion.actionLabel) {
                    A11yCoPilotService.shared.acceptSuggestion(suggestion)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.amenPurple)
                .buttonStyle(.plain)

                Button {
                    A11yCoPilotService.shared.suppress(type: suggestion.type)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss suggestion")
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Emotional Safety Notice

/// Banner shown when a thread contains content that may be emotionally intense.
struct EmotionalSafetyNotice: View {
    let isIntenseContent: Bool
    let onSummary: () -> Void
    let onLowerStimulation: () -> Void

    @ObservedObject private var flags = TrustAccessibilityFeatureFlags.shared

    init(
        isIntenseContent: Bool,
        onSummary: @escaping () -> Void,
        onLowerStimulation: @escaping () -> Void
    ) {
        self.isIntenseContent = isIntenseContent
        self.onSummary = onSummary
        self.onLowerStimulation = onLowerStimulation
    }

    var body: some View {
        if flags.emotionalSafetyEnabled && isIntenseContent {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color.amenGold)
                    .font(.system(size: 16))

                Text("This thread contains intense content")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    Button("View summary instead", action: onSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.amenPurple)
                        .buttonStyle(.plain)

                    Button("Lower stimulation", action: onLowerStimulation)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.amenBlue)
                        .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                Color.amenGold.opacity(0.08)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
