//  GlassKitTokens.swift
//  AMEN GlassKit — design tokens (spec §2.2). One source of truth so every component
//  reads identically and no call site hardcodes a color or radius.
//
//  NEW FILE — needs target membership added in Xcode (see report).
//
//  DESIGN LAW (spec §2): cards are OPAQUE WHITE surfaces on a light-gray page. Glass
//  (blur/translucency) is reserved for the action pill ON MEDIA, floating controls, and
//  sheets/nav — never a frosted card on a frosted sheet (no-glass-on-glass). This is an
//  intentionally fixed light editorial palette (same precedent as PulseInk), so the white
//  card surface and ink colors do not invert in dark mode — they are the design.

import SwiftUI

enum GlassKitTokens {

    // MARK: Surfaces
    static let page         = Color(hex: "F2F2F4")              // light-gray page beneath cards
    static let surface      = Color.white                       // opaque white card
    static let divider      = Color(hex: "E5E5EA")              // soft-gray divider
    static let hairline     = Color.white.opacity(0.6)          // lit-glass edge (media pill only)

    // MARK: Ink
    static let ink          = Color(hex: "1C1C1E")              // primary text (near-black)
    static let inkSecondary = Color(hex: "3C3C43").opacity(0.6) // captions / byline
    static let inkTertiary  = Color(hex: "8A8A8E")              // eyebrow / faint

    // MARK: Brand (spec §2.2)
    static let amenGold     = Color(hex: "D4A85C")
    static let amenPurple   = Color(hex: "6B47FF")
    static let amenBlue     = Color(hex: "3473F2")
    static let amenBlack    = Color(hex: "1C1C1E")

    // MARK: Status (fact card ✓ / ⚠︎)
    static let statusOk      = Color(hex: "2FA36B")
    static let statusWarn    = Color(hex: "E8A23D")

    // MARK: Metrics
    static let cardCorner: CGFloat  = 32                        // outer card
    static let heroCorner: CGFloat  = 26                        // hero image
    static let thumbCorner: CGFloat = 16                        // preview thumb
    static let pillCorner: CGFloat  = 999

    // MARK: Motion
    static let motionFast: Double   = 0.18
    static let motionNormal: Double = 0.32
}

// MARK: - Surface recipes

extension View {
    /// The canonical GlassKit card: OPAQUE WHITE + soft diffuse shadow, no hard border.
    /// This is deliberately NOT glass — cards never frost (spec §2 no-glass-on-glass).
    func glassCardSurface(corner: CGFloat = GlassKitTokens.cardCorner, elevated: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(GlassKitTokens.surface)
            )
            .shadow(color: .black.opacity(elevated ? 0.10 : 0.06),
                    radius: elevated ? 28 : 22, x: 0, y: elevated ? 14 : 10)
    }
}

// MARK: - Glass action pill (ON MEDIA only)

/// The one place glass belongs on a card: the action pill that sits over a hero image.
/// On a white surface use a solid/tinted pill instead (`GlassKitSolidPillStyle`).
struct GlassMediaPillStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color.black.opacity(0.18))
            }
            .overlay(Capsule().stroke(GlassKitTokens.hairline, lineWidth: 0.5))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Solid/tinted pill for actions that sit on the WHITE card body (not on media).
struct GlassKitSolidPillStyle: ButtonStyle {
    var tint: Color = GlassKitTokens.amenBlue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(tint.opacity(0.12)))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}
