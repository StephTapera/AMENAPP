import SwiftUI

/// A safe-area-aware Liquid Glass container for bottom bars, tab bars,
/// and persistent control strips.
///
/// The `scrollProgress` parameter (0–1) boosts material opacity when
/// content has scrolled beneath the bar, preserving text contrast.
///
/// Usage:
/// ```swift
/// AmenLiquidGlassBottomBar(scrollProgress: scrollOffset > 0 ? 1 : 0) {
///     HStack { /* tab items */ }
/// }
/// .ignoresSafeArea(edges: .bottom)
/// ```
struct AmenLiquidGlassBottomBar<Content: View>: View {
    var intensity: AmenGlassMaterialIntensity = .regular
    var cornerRadius: CGFloat = 0
    var isPressed: Bool = false
    var scrollProgress: CGFloat = 0
    var showBorder: Bool = true
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        content
            .padding(.horizontal, 16)
            .background(barBackground)
            .overlay(alignment: .top) {
                if showBorder {
                    topEdge
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(isPressed ? 0.99 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.84), value: isPressed)
    }

    // Top luminous edge — glass catching overhead light
    private var topEdge: some View {
        Rectangle()
            .frame(height: contrast == .increased ? 1.0 : 0.5)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(topEdgeOpacity),
                        Color.white.opacity(topEdgeOpacity * 0.4)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }

    @ViewBuilder
    private var barBackground: some View {
        if reduceTransparency {
            Rectangle().fill(intensity.solidFallback)
        } else {
            Rectangle()
                .fill(intensity.material)
                .overlay {
                    // Translucent white tint boosts with scroll so content stays readable.
                    Rectangle()
                        .fill(Color.white.opacity(0.05 + Double(scrollProgress) * 0.08))
                }
        }
    }

    private var topEdgeOpacity: Double {
        let base = contrast == .increased ? 0.80 : 0.32
        return base + Double(scrollProgress) * 0.20
    }
}

// MARK: - View Modifier

extension View {
    /// Wraps the view in an `AmenLiquidGlassBottomBar` glass backing.
    func amenLiquidGlassBottomBar(
        intensity: AmenGlassMaterialIntensity = .regular,
        cornerRadius: CGFloat = 0,
        isPressed: Bool = false,
        scrollProgress: CGFloat = 0,
        showBorder: Bool = true
    ) -> some View {
        AmenLiquidGlassBottomBar(
            intensity: intensity,
            cornerRadius: cornerRadius,
            isPressed: isPressed,
            scrollProgress: scrollProgress,
            showBorder: showBorder
        ) {
            self
        }
    }
}
