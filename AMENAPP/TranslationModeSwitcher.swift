// TranslationModeSwitcher.swift
// AMEN App — Accessibility Intelligence Layer (Phase 1)
//
// Glass capsule UI component that shows "Translated from X" with a mode switcher.
// Taps to expand into a [Literal][Natural][Contextual] pill strip.
// Follows AMEN Liquid Glass design language.

import SwiftUI

struct TranslationModeSwitcher: View {

    let sourceLanguage: String
    @Binding var selectedMode: TranslationMode
    let isLoading: Bool
    let onModeChanged: (TranslationMode) -> Void

    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 6) {
            // Globe icon + source label
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.systemScaled(10, weight: .medium))
                Text("Translated from \(SupportedLanguage.displayName(for: sourceLanguage))")
                    .font(AMENFont.regular(11))
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if isLoading {
                // Loading indicator
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Refining…")
                        .font(AMENFont.regular(10))
                        .foregroundStyle(.tertiary)
                }
            } else if isExpanded {
                // Expanded mode picker
                modePillStrip
            } else {
                // Collapsed mode indicator
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                        isExpanded = true
                    }
                    HapticManager.impact(style: .light)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: selectedMode.icon)
                            .font(.systemScaled(9, weight: .medium))
                        Text(selectedMode.displayLabel)
                            .font(AMENFont.semiBold(10))
                        Image(systemName: "chevron.down")
                            .font(.systemScaled(8, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Translation mode: \(selectedMode.displayLabel). Tap to change.")
            }
        }
    }

    // MARK: - Mode Pill Strip

    private var modePillStrip: some View {
        HStack(spacing: 4) {
            ForEach(TranslationMode.allCases, id: \.self) { mode in
                Button {
                    HapticManager.impact(style: .light)
                    withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                        selectedMode = mode
                        isExpanded = false
                    }
                    onModeChanged(mode)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: mode.icon)
                            .font(.systemScaled(9, weight: .medium))
                        if mode == .original {
                            Text(mode.displayLabel)
                                .font(AMENFont.semiBold(10))
                                .italic()
                        } else {
                            Text(mode.displayLabel)
                                .font(AMENFont.semiBold(10))
                        }
                    }
                    .foregroundStyle(selectedMode == mode ? Color.primary : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(selectedMode == mode
                                  ? Color.primary.opacity(0.1)
                                  : Color.clear)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                selectedMode == mode
                                    ? Color.primary.opacity(0.2)
                                    : Color.white.opacity(0.1),
                                lineWidth: 0.5
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.displayLabel) translation mode. \(mode.description)")
            }

            // Close button
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                    isExpanded = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close mode picker")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        ))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        TranslationModeSwitcher(
            sourceLanguage: "es",
            selectedMode: .constant(.literal),
            isLoading: false,
            onModeChanged: { _ in }
        )

        TranslationModeSwitcher(
            sourceLanguage: "fr",
            selectedMode: .constant(.natural),
            isLoading: true,
            onModeChanged: { _ in }
        )
    }
    .padding()
}
