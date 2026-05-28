import SwiftUI

struct AmenObjectHubLiquidGlassStyle {
    let reduceTransparency: Bool
    let increasedContrast: Bool

    var materialSurface: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(.systemBackground))
        }
        return AnyShapeStyle(.thinMaterial)
    }

    var glassBorder: Color {
        increasedContrast ? Color.black.opacity(0.16) : Color.white.opacity(0.58)
    }

    var sectionFill: Color {
        increasedContrast ? Color.white : Color(.secondarySystemBackground)
    }

    var primaryText: Color { .black }
    var secondaryText: Color { increasedContrast ? .black.opacity(0.72) : .black.opacity(0.62) }

    var shadow: Color {
        increasedContrast ? Color.black.opacity(0.14) : Color.black.opacity(0.08)
    }

    func specularHighlight(_ pressed: Bool = false) -> some View {
        LinearGradient(
            colors: [
                Color.white.opacity(pressed ? 0.42 : 0.30),
                Color.white.opacity(0.03)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct AmenHubGlassButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.01 : 0)
            .animation(reduceMotion ? nil : Motion.liquidSpring, value: configuration.isPressed)
    }
}
