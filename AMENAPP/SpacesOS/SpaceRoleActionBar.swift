// SpaceRoleActionBar.swift
// AMENAPP — SpacesOS
// Glass action bar rendering role-appropriate quick actions.

import SwiftUI

struct SpaceRoleActionBar: View {
    let role: SpaceMemberRole
    let spaceName: String
    let onPost: () -> Void
    let onAnnouncement: () -> Void
    let onEvent: () -> Void
    let onPrayer: () -> Void
    let onMembers: () -> Void
    let onAnalytics: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var actions: [SpaceQuickAction] {
        SpaceQuickAction.actions(
            for: role,
            onPost: onPost,
            onAnnouncement: onAnnouncement,
            onEvent: onEvent,
            onPrayer: onPrayer,
            onMembers: onMembers,
            onAnalytics: onAnalytics
        )
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(actions) { action in
                    ActionBarButton(action: action)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background {
            if reduceTransparency {
                Color(.systemBackground).opacity(0.97)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .overlay(alignment: .top) {
            Divider().opacity(0.25)
        }
    }
}

// MARK: - Action Bar Button

private struct ActionBarButton: View {
    let action: SpaceQuickAction

    var body: some View {
        Button {
            guard action.isEnabled else { return }
            action.action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(action.isEnabled ? Color.amenGold : Color.secondary.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(action.isEnabled
                                      ? Color.amenGold.opacity(0.12)
                                      : Color.secondary.opacity(0.08))
                    )
                Text(action.label)
                    .font(.caption2)
                    .foregroundStyle(action.isEnabled ? .primary : .secondary.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .accessibilityLabel(action.label)
        .accessibilityHint(action.disabledReason ?? "")
        .overlay(alignment: .topTrailing) {
            if !action.isEnabled, let reason = action.disabledReason {
                // Tooltip trigger (shown in accessibility and as a tooltip on long press)
                Color.clear
                    .accessibilityLabel(reason)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ForEach(SpaceMemberRole.allCases) { role in
            VStack(alignment: .leading, spacing: 4) {
                Text(role.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                SpaceRoleActionBar(
                    role: role,
                    spaceName: "Sunday Morning Group",
                    onPost: {}, onAnnouncement: {}, onEvent: {},
                    onPrayer: {}, onMembers: {}, onAnalytics: {}
                )
            }
        }
    }
    .padding(.vertical)
}
