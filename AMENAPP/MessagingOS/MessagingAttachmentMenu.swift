// MessagingAttachmentMenu.swift
// AMENAPP — MessagingOS
// Glass attachment menu shown when user taps "+" in the message composer.

import SwiftUI

struct MessagingAttachmentMenu: View {
    let onCardCreated: (ContentCard, MessageAttachmentType) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [GridItem(.adaptive(minimum: 72, maximum: 88), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            Text("Add to Message")
                .font(.headline)
                .padding(.vertical, 14)

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(MessageAttachmentType.allCases) { type in
                    AttachmentItemButton(type: type) {
                        handleTap(type)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background {
            if reduceTransparency {
                Color(.systemBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: -4)
    }

    private func handleTap(_ type: MessageAttachmentType) {
        let card = ContentCard(
            id: UUID().uuidString,
            title: type.displayName,
            body: "",
            sourceType: type.sourceType,
            sourceSurface: .directMessage,
            sourceId: UUID().uuidString,
            originalAudience: .private,
            creatorId: "current-user",
            creatorDisplayName: nil,
            sensitivityScore: 0.0,
            hasPrayerContent: type == .prayerRequest,
            hasChildContent: false,
            hasLocationData: type == .location,
            hasMinors: false,
            isAnonymous: false,
            isPaidContent: false,
            isDM: true,
            isChurchInternal: false,
            createdAt: Date(),
            expiresAt: nil,
            moderationState: .safe,
            discussionStatus: .none,
            attributionRules: ContentAttributionRules(
                requiresAttribution: false,
                allowsAnonymous: true,
                allowsQuoteOnly: false,
                expiresAfterDays: nil
            )
        )
        onCardCreated(card, type)
        onDismiss()
    }
}

// MARK: - Item Button

private struct AttachmentItemButton: View {
    let type: MessageAttachmentType
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.amenGold)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
                    .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.92 : 1))
                Text(type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.displayName)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
    }
}

// MARK: - Preview

#Preview {
    Color.gray.opacity(0.3).ignoresSafeArea()
        .overlay(alignment: .bottom) {
            MessagingAttachmentMenu(
                onCardCreated: { _, _ in },
                onDismiss: {}
            )
        }
}
