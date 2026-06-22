// AmenPrivacyPresetView.swift
// AMENAPP — CommunityOS/Privacy
//
// Phase 4 — Agent TS-a (Privacy Engine)
// Privacy preset picker in White Liquid Glass style.
//
// Design contract (C3 / AmenDesignSystem):
//   • White card surfaces (AmenSurface.card)
//   • systemGroupedBackground page bg
//   • Selected: accentColor border (2pt) + accentColor checkmark
//   • Unselected: secondarySystemFill background
//   • 28pt continuous corner radius
//   • Dynamic Type only; no fixed sizes
//   • Anonymous card shows a moderation-note caption
//
// Accessibility:
//   • Each card exposes its name, description, and selected state
//   • isSelected trait applied when active

import SwiftUI

// MARK: - AmenPrivacyPresetView

/// Full preset picker. Embeds one `AmenPrivacyPresetCard` per preset in a
/// scrollable vertical stack.
///
/// Usage:
/// ```swift
/// @State private var preset: AmenPrivacyPreset = .balanced
/// AmenPrivacyPresetView(selectedPreset: $preset)
/// ```
struct AmenPrivacyPresetView: View {

    @Binding var selectedPreset: AmenPrivacyPreset
    @StateObject private var engine = AmenPrivacyEngine()
    var showDetails: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Label("Privacy Level", systemImage: "lock.shield.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color(uiColor: .label))
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

            // Preset cards
            VStack(spacing: 12) {
                ForEach(AmenPrivacyPreset.allCases, id: \.self) { preset in
                    AmenPrivacyPresetCard(
                        preset: preset,
                        isSelected: selectedPreset == preset,
                        showDetails: showDetails,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedPreset = preset
                            }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - AmenPrivacyPresetCard

/// Single selectable privacy preset card.
/// White background + blue border + checkmark when selected.
/// Anonymous card shows a moderation caveat note.
struct AmenPrivacyPresetCard: View {

    let preset: AmenPrivacyPreset
    let isSelected: Bool
    var showDetails: Bool = true
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap to select this privacy level.")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Card Layout

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemFill))
                    .frame(width: 40, height: 40)
                Image(systemName: preset.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel))
            }
            .accessibilityHidden(true)

            // Text block
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(uiColor: .label))

                if showDetails {
                    Text(preset.description)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }

                // Anonymous-specific moderation note
                if preset == .anonymous {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.shield")
                            .font(.caption2)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            .accessibilityHidden(true)
                        Text("Your name is not shown. Your content is still subject to moderation.")
                            .font(.caption2)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            // Checkmark when selected
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(cardBackground)
    }

    // MARK: - Background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(isSelected ? Color.white : Color(uiColor: .secondarySystemFill))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 2
                    )
            )
            .shadow(
                color: isSelected ? Color.black.opacity(0.06) : Color.clear,
                radius: 10,
                x: 0,
                y: 2
            )
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var label = preset.displayName + ". " + preset.description
        if preset == .anonymous {
            label += " Note: your name is not shown but content is still subject to moderation."
        }
        if isSelected {
            label += " Currently selected."
        }
        return label
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Privacy Preset Picker") {
    PrivacyPresetPreviewWrapper()
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
}

private struct PrivacyPresetPreviewWrapper: View {
    @State private var selected: AmenPrivacyPreset = .balanced

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AmenPrivacyPresetView(selectedPreset: $selected, showDetails: true)

                Text("Selected: \(selected.displayName)")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
    }
}
#endif
