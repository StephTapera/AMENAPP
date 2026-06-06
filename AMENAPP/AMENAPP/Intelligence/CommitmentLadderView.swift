// CommitmentLadderView.swift — AMEN Living Intelligence
// Horizontal commitment ladder showing action rungs for an intelligence card.
//
// Design rules:
//   - Actions ordered by ActionRung (ascending commitment level)
//   - First (lowest) rung uses primary accent; rest use secondary tint
//   - Every button is wired — no dead buttons
//   - No spectacle counters (no "N people" labels)

import SwiftUI

struct CommitmentLadderView: View {
    let actions: [CardAction]
    let onTap: (CardAction) -> Void

    /// Actions sorted by ascending rung order
    private var sortedActions: [CardAction] {
        actions.sorted { $0.rung < $1.rung }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(sortedActions.enumerated()), id: \.element.id) { index, action in
                    LadderButton(
                        action: action,
                        isPrimary: index == 0,
                        onTap: { onTap(action) }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        .accessibilityLabel("Actions you can take")
    }
}

// MARK: - LadderButton

private struct LadderButton: View {
    let action: CardAction
    let isPrimary: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: iconName(for: action.rung))
                    .font(.caption.weight(.semibold))

                Text(action.label)
                    .font(.footnote)
                    .fontWeight(isPrimary ? .semibold : .medium)
            }
            .foregroundStyle(isPrimary ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                isPrimary
                    ? Color.accentColor.opacity(0.12)
                    : Color.primary.opacity(0.06),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isPrimary
                            ? Color.accentColor.opacity(0.3)
                            : Color.primary.opacity(0.10),
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
        .accessibilityHint(accessibilityHint(for: action.rung))
    }

    // MARK: - SF Symbol mapping

    private func iconName(for rung: ActionRung) -> String {
        switch rung {
        case .notice:  return "eye.fill"
        case .pray:    return "hands.sparkles.fill"
        case .learn:   return "book.fill"
        case .discuss: return "bubble.left.and.bubble.right.fill"
        case .give:    return "heart.fill"
        case .showUp:  return "location.fill"
        case .start:   return "plus.circle.fill"
        }
    }

    // MARK: - Accessibility hints

    private func accessibilityHint(for rung: ActionRung) -> String {
        switch rung {
        case .notice:  return "Acknowledge this card"
        case .pray:    return "Open prayer for this item"
        case .learn:   return "Learn more about this topic"
        case .discuss: return "Join a discussion"
        case .give:    return "Give to this need"
        case .showUp:  return "RSVP or find location"
        case .start:   return "Start an initiative"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let actions: [CardAction] = [
        CardAction(rung: .pray,    label: "Pray",        handler: "intelligence.pray",    target: "demo"),
        CardAction(rung: .learn,   label: "Learn More",  handler: "intelligence.learn",   target: "demo"),
        CardAction(rung: .discuss, label: "Discuss",     handler: "intelligence.discuss", target: "demo"),
        CardAction(rung: .give,    label: "Give",        handler: "intelligence.give",    target: "demo"),
    ]

    CommitmentLadderView(actions: actions) { action in
        print("Tapped: \(action.label)")
    }
    .padding()
}
#endif
