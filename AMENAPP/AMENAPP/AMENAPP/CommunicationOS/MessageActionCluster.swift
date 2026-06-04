// MessageActionCluster.swift
// AMENAPP
//
// Long-press / context menu action cluster for individual messages.
// Surfaces React, Reply, Copy, Pin, Save, Summarize, Create Task,
// Mark Decision, Remind Me, and More. All actions are feature-gated.

import SwiftUI

enum MessageClusterAction: String, CaseIterable {
    case react         = "React"
    case reply         = "Reply"
    case copy          = "Copy"
    case pin           = "Pin"
    case save          = "Save"
    case summarize     = "Summarize"
    case createTask    = "Create Task"
    case markDecision  = "Mark Decision"
    case remindMe      = "Remind Me"
    case forward       = "Share"
    case report        = "Report"

    var icon: String {
        switch self {
        case .react:        return "face.smiling"
        case .reply:        return "arrowshape.turn.up.left"
        case .copy:         return "doc.on.doc"
        case .pin:          return "pin"
        case .save:         return "bookmark"
        case .summarize:    return "text.quote"
        case .createTask:   return "checkmark.circle"
        case .markDecision: return "checkmark.seal"
        case .remindMe:     return "bell"
        case .forward:      return "arrowshape.turn.up.right"
        case .report:       return "flag"
        }
    }

    var isDestructive: Bool { self == .report }
}

struct MessageActionCluster: View {
    let message: AppMessage
    var onAction: (MessageClusterAction) -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var appeared = false

    private var availableActions: [MessageClusterAction] {
        var actions: [MessageClusterAction] = [.react, .reply, .copy]
        actions.append(.pin)
        actions.append(.save)
        if AMENFeatureFlags.shared.threadSummaryEnabled, !message.text.isEmpty {
            actions.append(.summarize)
        }
        if AMENFeatureFlags.shared.threadActionExtractionEnabled, !message.text.isEmpty {
            actions.append(.createTask)
        }
        if AMENFeatureFlags.shared.threadDecisionExtractionEnabled, !message.text.isEmpty {
            actions.append(.markDecision)
        }
        if AMENFeatureFlags.shared.messagingCrossSurfaceActionsEnabled {
            actions.append(.remindMe)
        }
        actions.append(.forward)
        actions.append(.report)
        return actions
    }

    var body: some View {
        // Shadow must sit before .glassEffect so it renders behind the glass surface.
        GlassEffectContainer(spacing: 0) {
            clusterGrid
                .padding(12)
        }
        .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
        .glassEffect(reduceTransparency ? .subtle : .regular,
                     in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            // .amenSpringEntry for show/hide per kit convention; linear fallback for Reduce Motion.
            withAnimation(reduceMotion ? .linear(duration: 0.12) : .amenSpringEntry) {
                appeared = true
            }
            AmenMessagingAnalytics.track(.messageActionClusterShown)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Message actions")
    }

    private var clusterGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(availableActions, id: \.self) { action in
                actionButton(action)
            }
        }
    }

    private func actionButton(_ action: MessageClusterAction) -> some View {
        Button {
            AmenMessagingAnalytics.track(.messageActionTapped, parameters: ["action": action.rawValue])
            onAction(action)
            onDismiss()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: action.icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(action.isDestructive ? Color.red : Color.primary)
                    .frame(width: 44, height: 44)
                    // Reduce-transparency fallback: solid system fill — no glass layered on glass.
                    .background {
                        if reduceTransparency {
                            Circle()
                                .fill(action.isDestructive
                                      ? Color.red.opacity(0.12)
                                      : Color(.tertiarySystemBackground))
                        }
                    }
                    // Glass circle for each icon — child elements inside the outer glass card,
                    // not overlapping glass layers.
                    .glassEffect(
                        reduceTransparency
                            ? .subtle       // identity-equivalent; background block above handles fill
                            : (action.isDestructive ? .subtle.tint(.red) : .regular),
                        in: Circle()
                    )
                Text(action.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(action.isDestructive ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
        }
        // .amenSpringBouncy for selection/tap feedback per kit convention.
        .buttonStyle(ClusterButtonStyle())
        .accessibilityLabel(action.rawValue)
    }
}

private struct ClusterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            // .amenSpringBouncy for selection/index changes per kit convention.
            .animation(.amenSpringBouncy, value: configuration.isPressed)
    }
}
