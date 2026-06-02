// BereanGlassStyles.swift
// AMENAPP — Berean Onboarding V2
// Onboarding-specific extensions on BereanColor/BereanType,
// plus reusable glass components and button style.
// Core tokens (BereanColor, BereanType) live in BereanDesignSystem.swift.

import SwiftUI

// MARK: - BereanColor Onboarding Extensions

extension BereanColor {
    static let glassShadow    = AmenTheme.Colors.shadowCard
    static let selectedFill   = AmenTheme.Colors.buttonPrimary
    static let selectedText   = AmenTheme.Colors.buttonPrimaryText
}

// MARK: - BereanType Onboarding Extensions

extension BereanType {
    static func badge() -> Font { AMENFont.regular(12) }
}

// MARK: - Glass Card Helper

extension View {
    func bereanGlassCard(cornerRadius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(BereanColor.glassFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                    )
                    .shadow(color: BereanColor.glassShadow, radius: 12, x: 0, y: 4)
            )
    }
}

// MARK: - Glass Capsule Modifier

struct BereanGlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(BereanColor.glassFill))
                    .overlay(Capsule().strokeBorder(BereanColor.glassStroke, lineWidth: 0.5))
                    .shadow(color: BereanColor.glassShadow, radius: 6, x: 0, y: 2)
            )
    }
}

extension View {
    func bereanGlassCapsule() -> some View {
        modifier(BereanGlassCapsuleModifier())
    }
}

// MARK: - Glass Orb

struct BereanGlassOrb: View {
    let icon: String
    var size: CGFloat = 110
    var iconSize: CGFloat = 36
    var pulse: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        ZStack {
            // Outer breathing ring — disabled under Reduce Motion
            if pulse && !reduceMotion {
                Circle()
                    .fill(AmenTheme.Colors.pressedOverlay)
                    .frame(width: size * 1.35, height: size * 1.35)
                    .scaleEffect(breathing ? 1.0 : 0.85)
                    .opacity(breathing ? 0 : 0.45)
                    .animation(
                        .easeInOut(duration: 2.4).repeatForever(autoreverses: false),
                        value: breathing
                    )
            }

            // Glass circle
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(AmenTheme.Colors.glassFill))
                .overlay(Circle().strokeBorder(BereanColor.glassStroke, lineWidth: 0.75))
                .shadow(color: BereanColor.glassShadow, radius: 20, x: 0, y: 8)
                .frame(width: size, height: size)

            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .light))
                .foregroundStyle(BereanColor.textPrimary)
        }
        .onAppear {
            if pulse && !reduceMotion {
                breathing = true
            }
        }
    }
}

// MARK: - Glass Icon Tile

struct BereanGlassIconTile: View {
    let icon: String
    var size: CGFloat = 48
    var iconSize: CGFloat = 20

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BereanColor.glassFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                )
                .frame(width: size, height: size)

            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .light))
                .foregroundStyle(BereanColor.textPrimary)
        }
    }
}

// MARK: - Primary CTA Button Style

struct BereanPrimaryCTAStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
            .frame(maxWidth: .infinity)
            // HIGH FIX: minHeight instead of exact height so button grows with Dynamic Type
            .frame(minHeight: 56)
            .background(
                AmenTheme.Colors.buttonPrimary
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            )
            .shadow(color: AmenTheme.Colors.shadowFloating, radius: 14, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Step Badge

struct BereanStepBadge: View {
    let current: Int
    let total: Int

    var body: some View {
        Text("Step \(current) of \(total)")
            .font(BereanType.badge())
            .foregroundStyle(BereanColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(AmenTheme.Colors.glassFill)
                    .overlay(Capsule().strokeBorder(BereanColor.glassStroke, lineWidth: 0.5))
            )
            .fixedSize()
            .minimumScaleFactor(0.8)
    }
}

// MARK: - Progress Pills

struct BereanProgressPills: View {
    let currentStep: BereanOnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(BereanOnboardingStep.allCases) { step in
                Capsule()
                    .fill(step == currentStep ? AmenTheme.Colors.iconPrimary.opacity(0.88) : AmenTheme.Colors.iconSecondary.opacity(0.35))
                    .frame(width: step == currentStep ? 28 : 10, height: 5)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentStep)
            }
        }
    }
}
