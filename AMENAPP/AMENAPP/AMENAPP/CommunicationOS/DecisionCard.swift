// DecisionCard.swift
// AMENAPP
//
// Liquid Glass card surfacing a detected decision.
// Shown inline in the smart context panel inside UnifiedChatView.

import SwiftUI

struct DecisionCard: View {
    let decision: ThreadDecision
    var onConfirm: () -> Void
    var onChallenge: () -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(decision.summary)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let snippet = decision.sourceMessageSnippet {
                sourceSnippet(snippet)
            }
            actionRow
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(statusColor.opacity(0.3), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.35, dampingFraction: 0.8)) {
                appeared = true
            }
            AmenMessagingAnalytics.track(.decisionCardSeen)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suggested decision: \(decision.summary). Status: \(decision.status.rawValue)")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
            Text("Suggested Decision")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            statusBadge
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss decision")
        }
    }

    private var statusBadge: some View {
        Text(decision.status.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.12), in: Capsule())
    }

    private func sourceSnippet(_ snippet: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 2)
            Text(snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.leading, 2)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if decision.status != .confirmed {
                Button("Confirm") {
                    AmenMessagingAnalytics.track(.decisionConfirmed)
                    onConfirm()
                }
                .buttonStyle(SmallPillButtonStyle(color: .green))
                .accessibilityLabel("Confirm this decision")
            }
            Button("Challenge") {
                AmenMessagingAnalytics.track(.decisionChallenged)
                onChallenge()
            }
            .buttonStyle(SmallPillButtonStyle(color: .orange))
            .accessibilityLabel("Challenge this decision")
            Spacer()
        }
    }

    private var statusColor: Color {
        switch decision.status {
        case .proposed:   return .blue
        case .confirmed:  return .green
        case .challenged: return .orange
        case .outdated:   return .secondary
        }
    }

    private var cardBackground: some ShapeStyle {
        if reduceTransparency { return AnyShapeStyle(Color(.secondarySystemBackground)) }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

// MARK: - Open Question Card

struct OpenQuestionCard: View {
    let question: ThreadQuestion
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(question.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let snippet = question.sourceMessageSnippet {
                HStack(alignment: .top, spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 2)
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .background(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { appeared = true }
            AmenMessagingAnalytics.track(.questionCardSeen)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open question: \(question.text)")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.bubble.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Open Question")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss question")
        }
    }
}

// MARK: - Smart Follow-Up Card

struct SmartFollowUpCard: View {
    let action: ThreadAction
    var onAccept: () -> Void
    var onMarkDone: () -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(action.description)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let snippet = action.sourceMessageSnippet {
                HStack(alignment: .top, spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 2)
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            actionRow
        }
        .padding(14)
        .background(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.purple.opacity(0.25), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { appeared = true }
            AmenMessagingAnalytics.track(.actionCardSeen)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suggested follow-up: \(action.description)")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)
            Text("Suggested Follow-up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss follow-up")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if action.status == .suggested {
                Button("Add Reminder") {
                    AmenMessagingAnalytics.track(.actionAccepted, parameters: ["type": "reminder"])
                    onAccept()
                }
                .buttonStyle(SmallPillButtonStyle(color: .purple))
            }
            Button("Mark Done") {
                AmenMessagingAnalytics.track(.actionDone)
                onMarkDone()
            }
            .buttonStyle(SmallPillButtonStyle(color: .green))
            Spacer()
        }
    }
}

// MARK: - Shared Button Style

struct SmallPillButtonStyle: ButtonStyle {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
