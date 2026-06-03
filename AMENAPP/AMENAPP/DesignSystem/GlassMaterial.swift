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
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
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
            // Solid opaque fill — meets WCAG contrast requirement
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(hex: "#1A1A2E"))
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
    /// - `reduceTransparency` → solid `#1A1A2E` fill instead of material.
    /// - `reduceMotion` is respected by callers — this modifier itself is static.
    func glassSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Design tokens (notification layer only)

/// Raw design tokens used by the notification-layer components.
/// Named differently from `LiquidGlassTokens` to avoid ambiguity.
enum NotifGlassTokens {
    static let goldPrimary  = Color(hex: "#C9A84C")
    static let goldLight    = Color(hex: "#FFD97D")
    static let accentPurple = Color(hex: "#7B68EE")
    static let cosmicDark   = Color(hex: "#0D0D1A")

    static let goldGradient = LinearGradient(
        colors: [Color(hex: "#FFD97D"), Color(hex: "#C9A84C")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let primaryButtonGradient = LinearGradient(
        colors: [Color(hex: "#C9A84C"), Color(hex: "#A07830")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Preview

#Preview("glassSurface — normal") {
    ZStack {
        LinearGradient(
            colors: [Color(hex: "#0D0D1A"), Color(hex: "#1A1A2E")],
            startPoint: .top, endPoint: .bottom
        )
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
            .environment(\.accessibilityReduceTransparency, true)
    }
}
