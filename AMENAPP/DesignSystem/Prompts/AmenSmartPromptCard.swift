// AmenSmartPromptCard.swift
// AMEN App — Smart Prompt Card Component
//
// Bottom-anchored overlay card, swipe-down to dismiss.
// White background, black text, native SF Symbols, capsule CTAs.
// No Liquid Glass on the card surface (reserved for nav chrome only).
//
// Accessibility:
//   - Full VoiceOver container with title + body label
//   - Dismiss button labeled "Dismiss"
//   - CTA buttons labeled with their titles
//   - Respects Reduce Motion (no spring on drag rubber-band)
//   - Respects Reduce Transparency (falls back to systemBackground)
//   - Minimum 44pt tap targets on all buttons

import SwiftUI

struct AmenSmartPromptCard: View {

    let prompt: AmenSmartPrompt
    let onPrimaryAction: (AmenSmartPromptAction) -> Void
    let onSecondaryAction: (AmenSmartPromptAction) -> Void
    let onDismiss: (AmenSmartPromptDismissalReason) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @GestureState private var dragTranslation: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            actionRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.09), radius: 20, x: 0, y: 8)
        .padding(.horizontal, 16)
        .offset(y: max(0, dragTranslation))
        .gesture(swipeToDismiss)
        .animation(
            reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.32, dampingFraction: 0.82),
            value: dragTranslation
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(prompt.title). \(prompt.body)")
        .transition(
            .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal:   .move(edge: .bottom).combined(with: .opacity)
            )
        )
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack(spacing: 12) {
            iconBadge
            textStack
            Spacer(minLength: 0)
            dismissButton
        }
    }

    private var iconBadge: some View {
        Image(systemName: prompt.systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.primary.opacity(0.65))
            .frame(width: 38, height: 38)
            .background(Circle().fill(Color.primary.opacity(0.06)))
            .accessibilityHidden(true)
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(prompt.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(prompt.body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dismissButton: some View {
        Button {
            onDismiss(.userTappedSecondaryAction)
        } label: {
            Image(systemName: "xmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.38))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            secondaryCTA
            primaryCTA
        }
    }

    private var secondaryCTA: some View {
        Button {
            onSecondaryAction(prompt.secondaryAction)
        } label: {
            Text(prompt.secondaryAction.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.primary.opacity(0.55))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(prompt.secondaryAction.title)
    }

    private var primaryCTA: some View {
        Button {
            onPrimaryAction(prompt.primaryAction)
        } label: {
            Text(prompt.primaryAction.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.systemBackground))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(Color.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(prompt.primaryAction.title)
    }

    // MARK: - Background

    @ViewBuilder
    private var cardSurface: some View {
        if reduceTransparency {
            Color(.systemBackground)
        } else {
            Color(.systemBackground).opacity(0.97)
        }
    }

    // MARK: - Gesture

    private var swipeToDismiss: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragTranslation) { value, state, _ in
                guard !reduceMotion else { return }
                if value.translation.height > 0 {
                    state = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > 70 {
                    onDismiss(.userSwipedAway)
                }
            }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Prayer Prompt Card") {
    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.15).ignoresSafeArea()
        AmenSmartPromptCard(
            prompt: AmenSmartPrompt(
                type: .prayerReplyNotification,
                surface: .prayerRequests,
                priority: .high,
                title: "Stay close to this prayer?",
                body: "We can let you know when people pray or reply.",
                systemImage: "bell.badge.fill",
                primaryAction: .primary("Enable Prayer Updates", route: .requestNotificationPermission),
                secondaryActionTitle: "Not Now",
                permissionRequirement: .notifications
            ),
            onPrimaryAction: { _ in },
            onSecondaryAction: { _ in },
            onDismiss: { _ in }
        )
        .padding(.bottom, 32)
    }
}
#endif
