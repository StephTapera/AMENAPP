// A11yCoPilotView.swift
// AMEN Universal Accessibility Engine — A8 Co-Pilot + Emotional Safety UI

import SwiftUI

// MARK: - Co-Pilot Panel (bottom-leading FAB)

/// Expandable FAB panel that surfaces up to 3 assistive hints at a time.
/// Only renders when `a11yCoPilotEnabled` is on.
struct A11yCoPilotPanel: View {
    @ObservedObject private var service = A11yCoPilotService.shared
    @ObservedObject private var flags = TrustAccessibilityFeatureFlags.shared
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var userId: String
    var onAction: (A11yCoPilotService.CoPilotHint.CoPilotAction) -> Void

    @State private var isExpanded = false

    var body: some View {
        if flags.a11yCoPilotEnabled {
            VStack(alignment: .leading, spacing: 8) {
                // Hint rows (shown only when expanded, max 3)
                if isExpanded {
                    let visibleHints = Array(service.hints.prefix(3))
                    ForEach(visibleHints) { hint in
                        CoPilotHintRow(
                            hint: hint,
                            userId: userId,
                            onAction: onAction
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }

                    // Quick settings link
                    NavigationLink {
                        // Placeholder — caller provides destination via NavigationStack.
                        EmptyView()
                    } label: {
                        Label("Accessibility settings", systemImage: "gearshape")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                    .transition(.opacity)
                }

                // Collapse/Expand button
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
        }
    }
}

// MARK: - Hint Row

struct CoPilotHintRow: View {
    let hint: A11yCoPilotService.CoPilotHint
    let userId: String
    let onAction: (A11yCoPilotService.CoPilotHint.CoPilotAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Hint text
            Text(hint.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Optional action button
            if let actionLabel = hint.actionLabel, let action = hint.action {
                Button(actionLabel) {
                    onAction(action)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.amenPurple)
                .buttonStyle(.plain)
            }

            // Dismiss button
            Button {
                Task {
                    try? await A11yCoPilotService.shared.dismissHint(id: hint.id, userId: userId)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss hint")
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Emotional Safety Notice

/// Banner shown when a thread contains content that may be emotionally intense.
/// Visibility is controlled by the caller via `isIntenseContent` and the
/// `emotionalSafetyEnabled` feature flag.
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
                        .foregroundStyle(.amenPurple)
                        .buttonStyle(.plain)

                    Button("Lower stimulation", action: onLowerStimulation)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.amenBlue)
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

// MARK: - Color Tokens

private extension Color {
    static var amenPurple: Color { Color("amenPurple", bundle: nil) }
    static var amenGold: Color   { Color("amenGold",   bundle: nil) }
    static var amenBlue: Color   { Color("amenBlue",   bundle: nil) }
}
