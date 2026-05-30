//
//  BereanSuggestionChipsView.swift
//  AMENAPP
//
//  Liquid Glass vertical card — idle-state suggestion popup above the Berean composer.
//  Design: Apple "Search or Ask" popup pattern adapted with AMEN tokens.
//  Site #5 of the AMEN glass card rollout.
//

import SwiftUI

// MARK: - BereanSuggestionChipsView

struct BereanSuggestionChipsView: View {
    let chips: [BereanLiquidSuggestionChip]
    let onTap: (BereanLiquidSuggestionChip) -> Void
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if isVisible {
            glassCard
                .transition(
                    reduceMotion
                        ? .opacity
                        : .scale(scale: 0.94, anchor: .bottom).combined(with: .opacity)
                )
                .animation(reduceMotion ? .easeOut(duration: 0.18) : .amenSpring, value: isVisible)
        }
    }

    // MARK: - Glass Card

    private var glassCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(chips.enumerated()), id: \.element.id) { index, chip in
                chipRow(chip)

                if index < chips.count - 1 {
                    Divider()
                        .padding(.leading, 50)
                }
            }
        }
        .frame(maxWidth: 300, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .amenGlassEffect(Color(.systemBackground).opacity(0.35), cornerRadius: 16)
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    // MARK: - Card Background (fallback for < iOS 26)

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        }
    }

    // MARK: - Row

    private func chipRow(_ chip: BereanLiquidSuggestionChip) -> some View {
        Button {
            onTap(chip)
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 12) {
                // Icon well — fixed width keeps all text labels left-aligned
                ZStack {
                    if let icon = chip.icon {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.amenBlue)
                    }
                }
                .frame(width: 26, alignment: .center)

                Text(chip.text)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(chip.text)
        .accessibilityHint("Fills the composer with \"\(chip.text)\"")
    }
}

// MARK: - Default Suggestions
// Maps the four canonical Berean entry points; icons use amenBlue accent per spec.

extension BereanLiquidSuggestionChip {
    static let defaultSuggestions: [BereanLiquidSuggestionChip] = [
        BereanLiquidSuggestionChip(text: "Ask Berean",       icon: "sparkles"),
        BereanLiquidSuggestionChip(text: "Study Scripture",  icon: "book.pages"),
        BereanLiquidSuggestionChip(text: "Pray with Me",     icon: "hands.sparkles"),
        BereanLiquidSuggestionChip(text: "Explain This",     icon: "text.quote")
    ]
}

// MARK: - Preview

#Preview {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()

        VStack(spacing: 0) {
            Spacer()

            BereanSuggestionChipsView(
                chips: BereanLiquidSuggestionChip.defaultSuggestions,
                onTap: { print("Tapped: \($0.text)") },
                isVisible: true
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Simulate the composer bar sitting below
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(height: 52)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
    }
}
