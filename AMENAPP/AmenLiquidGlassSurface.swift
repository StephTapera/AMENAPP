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
