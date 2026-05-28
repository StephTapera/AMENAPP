//
//  ChurchNotesDesignSystem.swift
//  AMENAPP
//
//  AMEN Liquid Glass design system for Church Notes.
//  Light/pearl surfaces, single material pass, black typography.
//

import SwiftUI

// MARK: - Church Notes Accent Colors

extension Color {
    /// Deep near-black for panel backgrounds — used as the notes feature base
    static let cnBlack = Color(hex: "050508")

    /// Warm gold — repurposed alias for use in church notes feature layer
    static let cnGold = Color(hex: "D4A843")

    /// Lighter champagne gold for highlights
    static let amenGoldLight = Color(hex: "F0C96E")

    /// Rich violet — AI panels, insights, spiritual depth indicators
    static let amenPurple = Color(hex: "A855F7")

    /// Soft emerald — voice recording, growth, positive states
    static let amenEmerald = Color(hex: "34D399")

    /// Warm rose — alerts, emotional depth, accent moments
    static let amenRose = Color(hex: "FB7185")

    /// Electric cyan — radar sweep, live elements
    static let amenCyan = Color(hex: "22D3EE")

    /// Warm orange — glory/fire palette, energy states
    static let amenOrange = Color(hex: "FB923C")

    // MARK: Light Glass Tokens

    /// Pearl white surface for Liquid Glass cards
    static let cnSurface = Color.white

    /// Warm ivory — slight warmth for spiritual tone
    static let cnIvory = Color(red: 0.985, green: 0.980, blue: 0.972)

    /// Soft pearl border tint
    static let cnBorderLight = Color.black.opacity(0.07)
}

// MARK: - Light GlassPillButtonStyle

/// Single-material pill — white pearl surface, black text, soft shadow.
struct GlassPillButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(isSelected
                                  ? Color.white.opacity(0.72)
                                  : Color.white.opacity(0.45))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isSelected
                                    ? Color.black.opacity(0.12)
                                    : Color.black.opacity(0.06),
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .shadow(
                color: isSelected ? Color.black.opacity(0.10) : Color.black.opacity(0.04),
                radius: isSelected ? 8 : 4,
                y: isSelected ? 3 : 2
            )
            .animation(reduceMotion ? nil : Motion.liquidSpring, value: configuration.isPressed)
    }
}

// MARK: - Light GlassCardModifier

/// Single-material frosted card — pearl white, subtle border, soft shadow.
struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.68))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 16, y: 4)
            .shadow(color: Color.black.opacity(0.03), radius: 4, y: 1)
    }
}

// MARK: - Light NoteRowCardModifier

/// Lighter card for list rows — smaller radius, minimal shadow.
struct NoteRowCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.75)
                    )
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
            .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
    }
}

// MARK: - View Convenience

extension View {
    func glassCard() -> some View {
        self.modifier(GlassCardModifier())
    }

    func noteRowCard() -> some View {
        self.modifier(NoteRowCardModifier())
    }
}
