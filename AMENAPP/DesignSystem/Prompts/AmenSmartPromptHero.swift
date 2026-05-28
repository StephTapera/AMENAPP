// AmenSmartPromptHero.swift
// AMEN App — Smart Prompt Hero Component
//
// Inline full-width card for insertion into scroll / list views.
// Used in feeds where a card prompt blends naturally into the content stream.
// Unlike the overlay Card, the Hero is part of the view hierarchy —
// the host view controls when to insert / remove it.
//
// Accessibility:
//   - Grouped element with title + body label
//   - Both CTAs are named and actionable
//   - Respects Dynamic Type
//   - Respects Reduce Motion and Reduce Transparency

import SwiftUI

struct AmenSmartPromptHero: View {

    let prompt: AmenSmartPrompt
    let onPrimaryAction: (AmenSmartPromptAction) -> Void
    let onSecondaryAction: (AmenSmartPromptAction) -> Void
    let onDismiss: (AmenSmartPromptDismissalReason) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topRow
            bodyText
            ctaRow
        }
        .padding(18)
        .background(heroSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 5)
        .padding(.horizontal, 16)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : (reduceMotion ? 1 : 0.96))
        .onAppear {
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.18)
                    : .spring(response: 0.36, dampingFraction: 0.80)
            ) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(prompt.title). \(prompt.body)")
    }

    // MARK: - Sub-views

    private var topRow: some View {
        HStack(spacing: 10) {
            Image(systemName: prompt.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.60))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .accessibilityHidden(true)

            Text(prompt.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

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
            .accessibilityLabel("Dismiss")
        }
    }

    private var bodyText: some View {
        Text(prompt.body)
            .font(.footnote)
            .foregroundStyle(Color.primary.opacity(0.58))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                onSecondaryAction(prompt.secondaryAction)
            } label: {
                Text(prompt.secondaryAction.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.primary.opacity(0.50))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(prompt.secondaryAction.title)

            Button {
                onPrimaryAction(prompt.primaryAction)
            } label: {
                Text(prompt.primaryAction.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Capsule().fill(Color.primary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(prompt.primaryAction.title)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var heroSurface: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            Color(.systemBackground).opacity(0.95)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Hero — Selah Pause") {
    ScrollView {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.gray.opacity(0.12))
                .frame(height: 140)
                .padding(.horizontal, 16)

            AmenSmartPromptHero(
                prompt: AmenSmartPrompt(
                    type: .selahPause,
                    surface: .selah,
                    priority: .low,
                    title: "Pause and reflect?",
                    body: "You can take a Selah moment before continuing.",
                    systemImage: "leaf.fill",
                    primaryAction: .primary("Start Selah", route: .openSelah),
                    secondaryActionTitle: "Continue"
                ),
                onPrimaryAction: { _ in },
                onSecondaryAction: { _ in },
                onDismiss: { _ in }
            )

            RoundedRectangle(cornerRadius: 14)
                .fill(Color.gray.opacity(0.12))
                .frame(height: 200)
                .padding(.horizontal, 16)
        }
        .padding(.top, 24)
    }
}
#endif
