// MessageLongPressMenu.swift
// AMENAPP — MessagingOS
// Long-press context menu on a message bubble.

import SwiftUI

struct MessageLongPressMenu: View {
    let messageId: String
    let messageBody: String
    let senderId: String
    let isDM: Bool
    let isAnonymous: Bool
    let onAction: (MessageLongPressAction) -> Void
    let onCardCreated: (ContentCard) -> Void
    let onDismiss: () -> Void

    @State private var permissionAlert: PermissionAlert? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Message preview
            Text(messageBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider().opacity(0.4)

            // Actions
            ForEach(MessageLongPressAction.allCases) { action in
                actionRow(action)
                if action != MessageLongPressAction.allCases.last {
                    Divider().opacity(0.2).padding(.leading, 52)
                }
            }
        }
        .background {
            if reduceTransparency {
                Color(.systemBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 4)
        .alert(item: $permissionAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private func actionRow(_ action: MessageLongPressAction) -> some View {
        Button {
            handleAction(action)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: action.icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(action == .pray ? Color.amenGold : Color.primary)
                    .frame(width: 28)
                Text(action.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.displayName)
    }

    private func handleAction(_ action: MessageLongPressAction) {
        if action.producesContentCard, let targetAction = action.targetAction {
            let card = ContentCard.fromMessage(
                messageId: messageId,
                body: messageBody,
                senderId: senderId,
                isDM: isDM,
                isAnonymous: isAnonymous
            )
            // Gate check
            let outcome = ContentPermissionEngine.evaluate(
                action: targetAction,
                card: card,
                requestorIsCreator: false,
                requestorIsSpaceAdmin: false,
                requestorIsChurchAdmin: false,
                requestorIsTrustedMember: false,
                targetSurface: isDM ? .directMessage : .space
            )
            if case .denied(let reason) = outcome {
                permissionAlert = PermissionAlert(
                    title: "Not Allowed",
                    message: reason
                )
                return
            }
            onCardCreated(card)
        }
        onAction(action)
        onDismiss()
    }
}

// MARK: - Supporting Types

private struct PermissionAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Preview

#Preview {
    Color.gray.opacity(0.4).ignoresSafeArea()
        .overlay {
            MessageLongPressMenu(
                messageId: "msg-1",
                messageBody: "God is so good! The sermon today really spoke to me.",
                senderId: "user-abc",
                isDM: false,
                isAnonymous: false,
                onAction: { _ in },
                onCardCreated: { _ in },
                onDismiss: {}
            )
            .padding(24)
        }
}
