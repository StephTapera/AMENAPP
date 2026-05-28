// AmenSmartPromptBanner.swift
// AMEN App — Smart Prompt Banner Component
//
// Top-anchored transient bar. Auto-dismisses after 6 seconds.
// Used for low-urgency contextual nudges that should not block the screen.
// Swipe up to dismiss early. Tap the primary CTA to act.
//
// Follows the InAppNotificationBanner pattern already in the app.
//
// Accessibility:
//   - VoiceOver reads title + body on appearance
//   - Dismiss button labeled "Dismiss prompt"
//   - Respects Reduce Motion (no spring)
//   - Respects Reduce Transparency

import SwiftUI

struct AmenSmartPromptBanner: View {

    let prompt: AmenSmartPrompt
    let onPrimaryAction: (AmenSmartPromptAction) -> Void
    let onDismiss: (AmenSmartPromptDismissalReason) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @GestureState private var dragTranslation: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            iconBadge
            textContent
            Spacer(minLength: 0)
            ctaButton
            dismissButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(bannerSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 5)
        .padding(.horizontal, 14)
        .offset(y: min(0, dragTranslation))
        .gesture(swipeUpToDismiss)
        .animation(
            reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.80),
            value: dragTranslation
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(prompt.title). \(prompt.body)")
        .transition(
            .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal:   .move(edge: .top).combined(with: .opacity)
            )
        )
    }

    // MARK: - Sub-views

    private var iconBadge: some View {
        Image(systemName: prompt.systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.primary.opacity(0.60))
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.primary.opacity(0.06)))
            .accessibilityHidden(true)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(prompt.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(prompt.body)
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.55))
                .lineLimit(2)
        }
    }

    private var ctaButton: some View {
        Button {
            onPrimaryAction(prompt.primaryAction)
        } label: {
            Text(prompt.primaryAction.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(Color.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.80)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(prompt.primaryAction.title)
    }

    private var dismissButton: some View {
        Button {
            onDismiss(.userTappedSecondaryAction)
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss prompt")
    }

    // MARK: - Background

    @ViewBuilder
    private var bannerSurface: some View {
        if reduceTransparency {
            Color(.systemBackground)
        } else {
            Color(.systemBackground).opacity(0.96)
                .background(.regularMaterial)
        }
    }

    // MARK: - Gesture

    private var swipeUpToDismiss: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($dragTranslation) { value, state, _ in
                guard !reduceMotion else { return }
                if value.translation.height < 0 {
                    state = value.translation.height * 0.5
                }
            }
            .onEnded { value in
                if value.translation.height < -44 {
                    onDismiss(.userSwipedAway)
                }
            }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Banner — Church Updates") {
    VStack {
        AmenSmartPromptBanner(
            prompt: AmenSmartPrompt(
                type: .churchEventReminder,
                surface: .churchDetail,
                title: "Keep up with this church?",
                body: "Get service reminders and important announcements.",
                systemImage: "building.columns.fill",
                primaryAction: .primary("Keep Me Updated", route: .requestNotificationPermission),
                secondaryActionTitle: "Maybe Later",
                permissionRequirement: .notifications
            ),
            onPrimaryAction: { _ in },
            onDismiss: { _ in }
        )
        .padding(.top, 60)
        Spacer()
    }
    .background(Color.gray.opacity(0.12))
}
#endif
