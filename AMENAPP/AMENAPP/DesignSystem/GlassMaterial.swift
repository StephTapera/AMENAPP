// GlassMaterial.swift
// AMENAPP — DesignSystem
//
// glassSurface(cornerRadius:) ViewModifier.
// Single source-of-truth for notification-layer glass surfaces.
//
// Color(hex:) is defined project-wide in Color+Hex.swift — not redeclared here.

import SwiftUI

// MARK: - GlassSurface ViewModifier

private struct GlassSurfaceModifier: ViewModifier {

    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion)       private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(backgroundLayer)
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            // 1px top specular — sits on top of clip
            .overlay(alignment: .top) {
                specularLine
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
            }
            .shadow(
                color: Color.black.opacity(0.25),
                radius: 16,
                x: 0,
                y: 6
            )
    }

    // MARK: Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if reduceTransparency {
            // PURGED: #1A1A2E (cosmic dark) → systemBackground per C3 design contract
            // Solid opaque fill — meets WCAG contrast requirement
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }

    // MARK: Specular highlight

    private var specularLine: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.35))
            .frame(height: 1)
            .padding(.horizontal, cornerRadius * 0.3)
            .padding(.top, 1)
            .allowsHitTesting(false)
    }
}

// MARK: - Public View extension

extension View {
    /// Wraps content in a translucent glass surface.
    ///
    /// - Parameter cornerRadius: Corner radius of the glass panel. Defaults to 20.
    ///
    /// Accessibility:
    /// - `reduceTransparency` → solid `Color(uiColor: .systemBackground)` fill instead of material.
    /// - `reduceMotion` is respected by callers — this modifier itself is static.
    func glassSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Design tokens (notification layer only)

/// Raw design tokens used by the notification-layer components.
/// Named differently from `LiquidGlassTokens` to avoid ambiguity.
///
/// PURGE LOG (C3 design contract, 2026-06-05):
///   goldPrimary (#C9A84C) → REMOVED; consumers: use Color.accentColor or Color(uiColor: .label)
///   goldLight (#FFD97D) → REMOVED; consumers: use Color.accentColor
///   goldGradient → REMOVED; consumers: use Color.accentColor or plain white fill
///   primaryButtonGradient → REMOVED; consumers: use Color.accentColor pill
///   accentPurple (#7B68EE) → REMOVED; consumers: use Color.accentColor
///   cosmicDark (#0D0D1A) → REMOVED; consumers: use Color(uiColor: .systemBackground)
enum NotifGlassTokens {
    // PURGED: goldPrimary  = Color(hex: "#C9A84C") → Color.accentColor per C3 design contract
    // PURGED: goldLight    = Color(hex: "#FFD97D") → Color.accentColor per C3 design contract
    // PURGED: accentPurple = Color(hex: "#7B68EE") → Color.accentColor per C3 design contract
    // PURGED: cosmicDark   = Color(hex: "#0D0D1A") → Color(uiColor: .systemBackground) per C3 design contract
    // PURGED: goldGradient (LinearGradient using gold hex) → Color.accentColor per C3 design contract
    // PURGED: primaryButtonGradient (LinearGradient using gold hex) → Color.accentColor per C3 design contract

    // Remaining tokens below are C3-compatible (white/system colors only):

    static let accentPurple = Color.accentColor   // PURGED: was #7B68EE; now system accent
    static let goldPrimary  = Color.accentColor   // PURGED: was #C9A84C; now system accent
    static let goldLight    = Color.accentColor   // PURGED: was #FFD97D; now system accent
    static let cosmicDark   = Color(uiColor: .systemBackground)  // PURGED: was #0D0D1A

    static let goldGradient = LinearGradient(
        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let primaryButtonGradient = LinearGradient(
        colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Preview

#Preview("glassSurface — normal") {
    ZStack {
        // PURGED: cosmicDark preview gradient (#0D0D1A, #1A1A2E) → systemGroupedBackground per C3
        Color(uiColor: .systemGroupedBackground)
        .ignoresSafeArea()

        VStack(spacing: 20) {
            Text("Glass surface, cornerRadius 20")
                .foregroundStyle(.white)
                .padding(24)
                .glassSurface(cornerRadius: 20)

            Text("Glass surface, cornerRadius 32")
                .foregroundStyle(.white)
                .padding(24)
                .glassSurface(cornerRadius: 32)
        }
        .padding()
    }
}

#Preview("glassSurface — reduceTransparency") {
    ZStack {
        Color.purple.ignoresSafeArea()
        Text("Reduce Transparency On")
            .foregroundStyle(.white)
            .padding(24)
            .glassSurface(cornerRadius: 20)
    }
}
