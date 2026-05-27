// AmenSmartPromptSheet.swift
// AMEN App — Smart Prompt Sheet Component
//
// Half-sheet modal (.medium detent) for prompts that benefit from
// a larger canvas — e.g. church discovery follow-up or Berean study.
// Presented via .sheet(isPresented:) from AmenSmartPromptModifier.
//
// Accessibility:
//   - Title marked as .isHeader for VoiceOver
//   - Both CTAs named and actionable
//   - Dynamic Type respected
//   - Reduce Transparency falls back to systemBackground

import SwiftUI

struct AmenSmartPromptSheet: View {

    let prompt: AmenSmartPrompt
    let onPrimaryAction: (AmenSmartPromptAction) -> Void
    let onSecondaryAction: (AmenSmartPromptAction) -> Void
    let onDismiss: (AmenSmartPromptDismissalReason) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            dragIndicator
            content
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .background(sheetBackground)
    }

    // MARK: - Sub-views

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.black.opacity(0.18))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(spacing: 24) {
            iconSection
            textSection
            actionSection
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 32)
    }

    private var iconSection: some View {
        Image(systemName: prompt.systemImage)
            .font(.system(size: 42, weight: .medium))
            .foregroundStyle(.black.opacity(0.75))
            .frame(width: 72, height: 72)
            .background(Circle().fill(Color.black.opacity(0.06)))
            .accessibilityHidden(true)
    }

    private var textSection: some View {
        VStack(spacing: 8) {
            Text(prompt.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(prompt.body)
                .font(.subheadline)
                .foregroundStyle(.black.opacity(0.58))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    private var actionSection: some View {
        VStack(spacing: 10) {
            Button {
                onPrimaryAction(prompt.primaryAction)
            } label: {
                Text(prompt.primaryAction.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(Color.black))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(prompt.primaryAction.title)

            Button {
                onSecondaryAction(prompt.secondaryAction)
            } label: {
                Text(prompt.secondaryAction.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.black.opacity(0.50))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(prompt.secondaryAction.title)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency {
            Color(.systemBackground)
        } else {
            Color.white.opacity(0.98)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Sheet — Berean Study") {
    Color.gray.opacity(0.15)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AmenSmartPromptSheet(
                prompt: AmenSmartPrompt(
                    type: .bereanStudyContinuation,
                    surface: .bereanAI,
                    title: "Continue this study?",
                    body: "Receive gentle reminders to return to this passage.",
                    systemImage: "book.pages.fill",
                    primaryAction: .primary("Remind Me", route: .requestNotificationPermission),
                    secondaryActionTitle: "Not Now",
                    permissionRequirement: .notifications
                ),
                onPrimaryAction: { _ in },
                onSecondaryAction: { _ in },
                onDismiss: { _ in }
            )
        }
}
#endif
