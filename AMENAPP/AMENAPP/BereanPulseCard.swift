// BereanPulseCard.swift
// AMEN App — Berean AI "Today's Pulse" entry card.
//
// Signature (frozen — do not change without broadcasting to all callers):
//   BereanPulseCard(pulse: BereanPulse, onOpen: () -> Void)
//
// Design: Quiet premium card. Centered icon tile + title + subtitle + chevron.
// Reduces transparency and motion gracefully. Calls HapticManager on tap.

import SwiftUI

// MARK: - BereanPulseCard

struct BereanAssistantPulseCard: View {

    let pulse: BereanPulse
    let onOpen: () -> Void

    // Entry animation state
    @State private var appeared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(alignment: .center, spacing: 14) {

            // Glass icon tile — 54 × 54
            iconTile

            // Title + subtitle stack
            VStack(alignment: .leading, spacing: 3) {
                Text(pulse.title)
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(pulse.subtitle)
                    .font(.systemScaled(14, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Disclosure chevron
            Image(systemName: "chevron.right")
                .font(.systemScaled(13, weight: .medium))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, DesignTokens.spacingM)
        .padding(.vertical, DesignTokens.spacingM)
        .background(cardBackground)
        // Entry animation
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    appeared = true
                }
            }
        }
        // Interaction
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.radiusCard, style: .continuous))
        .onTapGesture {
            HapticManager.impact(style: .light)
            onOpen()
        }
        // Accessibility
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's Berean Pulse — \(pulse.subtitle)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Icon tile

    private var iconTile: some View {
        ZStack {
            // Background fill — material or solid fallback
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    reduceTransparency
                        ? AnyShapeStyle(Color(.secondarySystemBackground))
                        : AnyShapeStyle(.ultraThinMaterial)
                )

            // White fill overlay — brightens the tile in light mode
            if !reduceTransparency {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.60))
            }

            // Specular top-leading highlight
            if !reduceTransparency {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.75),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Hairline border
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(reduceTransparency ? 0.30 : 0.65),
                    lineWidth: 0.75
                )

            // Symbol
            Image(systemName: "sparkles")
                .font(.systemScaled(22, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(.label).opacity(0.72),
                            Color(.label).opacity(0.46)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: 54, height: 54)
        .shadow(
            color: Color.black.opacity(reduceTransparency ? 0 : 0.07),
            radius: 10,
            y: 3
        )
    }

    // MARK: - Card background

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: DesignTokens.radiusCard, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.radiusCard, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
                .shadow(color: DesignTokens.shadowCard, radius: 12, y: 4)
        } else {
            LiquidGlassCapsuleBackground(
                cornerRadius: DesignTokens.radiusCard,
                glassOpacity: 0.12,
                shadowOpacity: 0.10,
                highlightOpacity: 0.24
            )
        }
    }
}

// MARK: - Preview

#Preview("Pulse Card — Light") {
    ZStack {
        Color(red: 0.971, green: 0.971, blue: 0.969)
            .ignoresSafeArea()
        BereanAssistantPulseCard(pulse: .today) {}
            .padding(.horizontal, 18)
    }
}

#Preview("Pulse Card — Dark") {
    ZStack {
        Color(.systemBackground)
            .ignoresSafeArea()
        BereanAssistantPulseCard(pulse: .today) {}
            .padding(.horizontal, 18)
    }
    .preferredColorScheme(.dark)
}
