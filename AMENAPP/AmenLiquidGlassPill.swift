import SwiftUI

/// A capsule-shaped Liquid Glass container for pills, tags, and mode selectors.
///
/// Usage:
/// ```swift
/// AmenLiquidGlassPill(intensity: .light, isPressed: isPressed) {
///     Label("Explain", systemImage: "sparkles")
///         .font(.systemScaled(13, weight: .medium))
///         .foregroundStyle(.primary)
/// }
/// ```
struct AmenLiquidGlassPill<Content: View>: View {
    let intensity: AmenGlassMaterialIntensity
    let showBorder: Bool
    let isPressed: Bool
    let scrollProgress: CGFloat
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        intensity: AmenGlassMaterialIntensity = .light,
        showBorder: Bool = true,
        isPressed: Bool = false,
        scrollProgress: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.intensity = intensity
        self.showBorder = showBorder
        self.isPressed = isPressed
        self.scrollProgress = scrollProgress
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(pillBackground)
            .clipShape(Capsule(style: .continuous))
            .scaleEffect(isPressed ? 0.97 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.80),
                value: isPressed
            )
    }

    @ViewBuilder
    private var pillBackground: some View {
        Capsule(style: .continuous)
            .fill(glassFill)
            .overlay {
                Capsule(style: .continuous)
                    .fill(innerGlow)
            }
            .overlay {
                if showBorder {
                    Capsule(style: .continuous)
                        .strokeBorder(borderGradient, lineWidth: contrast == .increased ? 1.0 : 0.6)
                }
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: 2)
    }

    private var glassFill: AnyShapeStyle {
        reduceTransparency ? intensity.solidFallback : intensity.material
    }

    private var innerGlow: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(reduceTransparency ? 0 : 0.18), Color.clear],
            startPoint: .top,
            endPoint: .center
        )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(contrast == .increased ? 0.72 : 0.48),
                Color.white.opacity(0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var shadowOpacity: Double {
        let base: Double = intensity == .prominent ? 0.12 : 0.07
        return base - Double(scrollProgress) * 0.02
    }

    private var shadowRadius: CGFloat {
        intensity == .prominent ? 10 : 6
    }
}
