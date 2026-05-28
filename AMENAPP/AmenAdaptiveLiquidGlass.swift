import SwiftUI

enum AmenAdaptiveGlassRole {
    case navigation
    case composer
    case floatingControl
    case sheetChrome
    case mediaChrome

    var cornerRadius: CGFloat {
        switch self {
        case .navigation, .composer, .floatingControl:
            return 28
        case .sheetChrome, .mediaChrome:
            return 20
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .navigation, .composer, .floatingControl:
            return 18
        case .sheetChrome:
            return 12
        case .mediaChrome:
            return 16
        }
    }
}

struct AmenAdaptiveGlassContext {
    var role: AmenAdaptiveGlassRole
    var isSelected: Bool = false
    var isPressed: Bool = false
    var isScrolling: Bool = false
    var ambientTint: Color = .white

    var materialOpacity: Double {
        var opacity = isScrolling ? 0.18 : 0.12
        if isSelected { opacity += 0.06 }
        if isPressed { opacity += 0.04 }
        return min(opacity, 0.24)
    }

    var edgeOpacity: Double {
        isSelected ? 0.48 : 0.30
    }

    var shadowOpacity: Double {
        isSelected ? 0.10 : 0.07
    }

    var pressScale: CGFloat {
        isPressed ? 0.975 : 1
    }
}

struct AmenAdaptiveLiquidGlassModifier: ViewModifier {
    let context: AmenAdaptiveGlassContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(surfaceBackground)
            .overlay(edgeHighlight)
            .shadow(
                color: .black.opacity(reduceTransparency ? 0.03 : context.shadowOpacity),
                radius: context.role.shadowRadius,
                x: 0,
                y: context.role.shadowRadius * 0.45
            )
            .scaleEffect(reduceMotion ? 1 : context.pressScale)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.88), value: context.isPressed)
            .animation(.easeOut(duration: 0.16), value: context.isSelected)
            .modifier(AmenAdaptiveGlassAccessibilityModifier(isSelected: context.isSelected))
    }

    @ViewBuilder
    private var surfaceBackground: some View {
        RoundedRectangle(cornerRadius: context.role.cornerRadius, style: .continuous)
            .fill(backgroundStyle)
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: context.role.cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(reduceTransparency ? 0 : 0.24),
                                Color.white.opacity(0.02),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: context.role.cornerRadius, style: .continuous)
                    .fill(context.ambientTint.opacity(reduceTransparency ? 0 : context.materialOpacity))
                    .blendMode(.softLight)
                    .allowsHitTesting(false)
            }
    }

    private var backgroundStyle: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemBackground))
        }

        switch context.role {
        case .navigation, .floatingControl, .mediaChrome:
            return AnyShapeStyle(.ultraThinMaterial)
        case .composer, .sheetChrome:
            return AnyShapeStyle(.thinMaterial)
        }
    }

    @ViewBuilder
    private var edgeHighlight: some View {
        let lineWidth = contrast == .increased ? 1.0 : 0.7
        RoundedRectangle(cornerRadius: context.role.cornerRadius, style: .continuous)
            .strokeBorder(
                reduceTransparency ? Color.primary.opacity(0.18) : Color.white.opacity(context.edgeOpacity),
                lineWidth: lineWidth
            )
            .overlay {
                RoundedRectangle(cornerRadius: context.role.cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(contrast == .increased ? 0.20 : 0.08), lineWidth: 0.5)
            }
            .allowsHitTesting(false)
    }
}

private struct AmenAdaptiveGlassAccessibilityModifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.accessibilityAddTraits(.isSelected)
        } else {
            content
        }
    }
}

extension View {
    func amenAdaptiveLiquidGlass(_ context: AmenAdaptiveGlassContext) -> some View {
        modifier(AmenAdaptiveLiquidGlassModifier(context: context))
    }
}
