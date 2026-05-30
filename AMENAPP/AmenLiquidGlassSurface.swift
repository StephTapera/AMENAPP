import SwiftUI
import UIKit

// MARK: - Material Intensity

/// Four-level material intensity for Amen Liquid Glass surfaces.
/// Maps directly to native iOS materials so the result always looks native.
enum AmenGlassMaterialIntensity {
    case clear      // .ultraThinMaterial — most transparent, background bleeds fully
    case light      // .thinMaterial      — translucent control layer
    case regular    // .regularMaterial   — standard readable surface
    case prominent  // .thickMaterial     — high-opacity, Increase Contrast-safe

    var material: AnyShapeStyle {
        switch self {
        case .clear:    return AnyShapeStyle(.ultraThinMaterial)
        case .light:    return AnyShapeStyle(.thinMaterial)
        case .regular:  return AnyShapeStyle(.regularMaterial)
        case .prominent: return AnyShapeStyle(.thickMaterial)
        }
    }

    var solidFallback: AnyShapeStyle {
        switch self {
        case .clear, .light: return AnyShapeStyle(Color(.systemBackground).opacity(0.94))
        case .regular:       return AnyShapeStyle(Color(.secondarySystemBackground))
        case .prominent:     return AnyShapeStyle(Color(.tertiarySystemBackground))
        }
    }
}

// MARK: - Legacy Variant (kept for backwards compatibility)

enum AmenLiquidGlassVariant {
    case regular
    case clear

    fileprivate var intensity: AmenGlassMaterialIntensity {
        switch self {
        case .regular: return .light
        case .clear:   return .clear
        }
    }
}

enum AmenLiquidGlassTintRole {
    case primary
    case neutral
    case destructive
}

enum AmenLiquidGlassContentComplexity {
    case low
    case medium
    case high
}

// MARK: - AmenLiquidGlassSurface

struct AmenLiquidGlassSurface<Content: View>: View {
    let variant: AmenLiquidGlassVariant
    let intensity: AmenGlassMaterialIntensity
    let cornerRadius: CGFloat
    let isInteractive: Bool
    let isPressed: Bool
    let allowsTint: Bool
    let tintRole: AmenLiquidGlassTintRole
    let contentComplexity: AmenLiquidGlassContentComplexity
    let localizedDimming: Bool
    let showBorder: Bool
    let scrollProgress: CGFloat
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        variant: AmenLiquidGlassVariant = .regular,
        cornerRadius: CGFloat = 16,
        isInteractive: Bool = true,
        isPressed: Bool = false,
        allowsTint: Bool = false,
        tintRole: AmenLiquidGlassTintRole = .neutral,
        contentComplexity: AmenLiquidGlassContentComplexity = .medium,
        localizedDimming: Bool = false,
        showBorder: Bool = true,
        scrollProgress: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.intensity = variant.intensity
        self.cornerRadius = cornerRadius
        self.isInteractive = isInteractive
        self.isPressed = isPressed
        self.allowsTint = allowsTint
        self.tintRole = tintRole
        self.contentComplexity = contentComplexity
        self.localizedDimming = localizedDimming
        self.showBorder = showBorder
        self.scrollProgress = scrollProgress
        self.content = content()
    }

    init(
        intensity: AmenGlassMaterialIntensity,
        cornerRadius: CGFloat = 16,
        isInteractive: Bool = true,
        isPressed: Bool = false,
        allowsTint: Bool = false,
        tintRole: AmenLiquidGlassTintRole = .neutral,
        contentComplexity: AmenLiquidGlassContentComplexity = .medium,
        localizedDimming: Bool = false,
        showBorder: Bool = true,
        scrollProgress: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = intensity == .clear ? .clear : .regular
        self.intensity = intensity
        self.cornerRadius = cornerRadius
        self.isInteractive = isInteractive
        self.isPressed = isPressed
        self.allowsTint = allowsTint
        self.tintRole = tintRole
        self.contentComplexity = contentComplexity
        self.localizedDimming = localizedDimming
        self.showBorder = showBorder
        self.scrollProgress = scrollProgress
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundShape)
            .scaleEffect(pressScale)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.24, dampingFraction: 0.84), value: isPressed)
    }

    private var pressScale: CGFloat {
        guard isInteractive else { return 1 }
        return isPressed ? 0.98 : 1
    }

    @ViewBuilder
    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(surfaceFill)
            .overlay {
                // Water-like top-edge light refraction
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(innerGlowOpacity), Color.clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.45)
                    ))
            }
            .overlay {
                if showBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(borderGradient, lineWidth: contrast == .increased ? 1.0 : 0.7)
                }
            }
            .overlay {
                if intensity == .clear && localizedDimming {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.14))
                }
            }
            .overlay {
                if allowsTint {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tintOverlay)
                }
            }
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
    }

    private var surfaceFill: AnyShapeStyle {
        reduceTransparency ? intensity.solidFallback : intensity.material
    }

    private var borderGradient: LinearGradient {
        let top = contrast == .increased ? 0.72 : 0.50
        let bottom = contrast == .increased ? 0.30 : 0.12
        return LinearGradient(
            colors: [Color.white.opacity(top), Color.white.opacity(bottom)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var innerGlowOpacity: Double {
        reduceTransparency ? 0 : (intensity == .clear ? 0.10 : 0.14)
    }

    private var shadowColor: Color {
        let base = contrast == .increased ? 0.14 : 0.09
        let scrollReduction = Double(scrollProgress) * 0.03
        return Color.black.opacity(base - scrollReduction)
    }

    private var shadowRadius: CGFloat {
        switch contentComplexity {
        case .low: return 4
        case .medium: return 8
        case .high: return 10
        }
    }

    private var shadowYOffset: CGFloat {
        switch contentComplexity {
        case .low: return 2
        case .medium: return 4
        case .high: return 5
        }
    }

    private var tintOverlay: LinearGradient {
        switch tintRole {
        case .primary:
            return LinearGradient(colors: [Color.primary.opacity(0.08), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .neutral:
            return LinearGradient(colors: [Color.white.opacity(0.08), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .destructive:
            return LinearGradient(colors: [Color.red.opacity(0.10), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
// MARK: - Amen Liquid White

enum AmenLiquidWhiteShadowDepth {
    case soft
    case floating
}

struct AmenLiquidWhiteBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.99, green: 0.99, blue: 0.97),
                Color(red: 0.95, green: 0.95, blue: 0.92),
                Color.white
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .top) {
            RadialGradient(
                colors: [Color.white.opacity(0.92), Color.clear],
                center: UnitPoint(x: 0.5, y: -0.08),
                startRadius: 12,
                endRadius: 320
            )
            .frame(height: 360)
        }
        .ignoresSafeArea()
    }
}

struct AmenLiquidWhiteSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let shadow: AmenLiquidWhiteShadowDepth
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        cornerRadius: CGFloat,
        shadow: AmenLiquidWhiteShadowDepth = .soft,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.content = content()
    }

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(surfaceFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(reduceTransparency ? 0 : 0.74),
                                        Color.white.opacity(reduceTransparency ? 0 : 0.22),
                                        Color.white.opacity(reduceTransparency ? 0 : 0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.screen)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(contrast == .increased ? 0.98 : 0.86),
                                        Color.black.opacity(contrast == .increased ? 0.14 : 0.055)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: contrast == .increased ? 1.2 : 0.8
                            )
                    }
                    .shadow(
                        color: .black.opacity(shadow == .floating ? 0.13 : 0.075),
                        radius: shadow == .floating ? 34 : 20,
                        x: 0,
                        y: shadow == .floating ? 20 : 10
                    )
            }
    }

    private var surfaceFill: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color.white.opacity(0.97))
            : AnyShapeStyle(.ultraThinMaterial)
    }
}

struct AmenLiquidWhiteButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.systemScaled(18, weight: .semibold))

            Text(title)
                .font(AMENFont.bold(16))
                .lineLimit(1)
                .minimumScaleFactor(0.86)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
    }
}

struct AmenLiquidWhiteButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case destructive
    }

    let kind: Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background {
                Capsule()
                    .fill(backgroundFill)
                    .overlay {
                        Capsule()
                            .fill(highlight)
                            .blendMode(.screen)
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(stroke, lineWidth: kind == .primary ? 0 : 0.8)
                    }
                    .shadow(
                        color: .black.opacity(configuration.isPressed ? 0.05 : shadowOpacity),
                        radius: configuration.isPressed ? 10 : 18,
                        y: configuration.isPressed ? 5 : 10
                    )
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.23, dampingFraction: 0.82), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return .black
        case .destructive: return .red
        }
    }

    private var backgroundFill: AnyShapeStyle {
        switch kind {
        case .primary:
            return AnyShapeStyle(Color.black)
        case .secondary:
            return reduceTransparency ? AnyShapeStyle(Color.white.opacity(0.96)) : AnyShapeStyle(.ultraThinMaterial)
        case .destructive:
            return AnyShapeStyle(Color.red.opacity(0.08))
        }
    }

    private var highlight: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(kind == .primary ? 0.10 : 0.58),
                Color.white.opacity(kind == .primary ? 0.02 : 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var stroke: Color {
        switch kind {
        case .primary: return .clear
        case .secondary: return Color.white.opacity(0.86)
        case .destructive: return Color.red.opacity(0.16)
        }
    }

    private var shadowOpacity: Double {
        switch kind {
        case .primary: return 0.16
        case .secondary: return 0.07
        case .destructive: return 0.04
        }
    }
}

struct AmenLiquidWhiteCircleButtonStyle: ButtonStyle {
    var isProminent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isProminent ? .white : .black)
            .background {
                Circle()
                    .fill(isProminent ? AnyShapeStyle(Color.black) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isProminent ? 0.12 : 0.72),
                                        Color.white.opacity(isProminent ? 0.02 : 0.18)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .blendMode(.screen)
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(isProminent ? 0.18 : 0.86), lineWidth: 0.8)
                    }
                    .shadow(
                        color: .black.opacity(configuration.isPressed ? 0.05 : 0.11),
                        radius: configuration.isPressed ? 8 : 18,
                        y: configuration.isPressed ? 4 : 10
                    )
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

