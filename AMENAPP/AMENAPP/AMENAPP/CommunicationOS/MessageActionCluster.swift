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
        VStack(spacing: 0) {
            clusterGrid
        }
        .padding(12)
        .background(clusterBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.72)) {
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
                    .frame(width: 44, height: 44)
                    .background(actionButtonBackground(action), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(action.isDestructive ? .red : .primary)
                Text(action.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(action.isDestructive ? .red : .secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(ClusterButtonStyle())
        .accessibilityLabel(action.rawValue)
    }

    private func actionButtonBackground(_ action: MessageClusterAction) -> some ShapeStyle {
        if action.isDestructive { return AnyShapeStyle(Color.red.opacity(0.1)) }
        if reduceTransparency { return AnyShapeStyle(Color(.tertiarySystemBackground)) }
        return AnyShapeStyle(.regularMaterial)
    }

    private var clusterBackground: some ShapeStyle {
        if reduceTransparency { return AnyShapeStyle(Color(.systemBackground)) }
        return AnyShapeStyle(.regularMaterial)
    }
}

private struct ClusterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
    }
}
