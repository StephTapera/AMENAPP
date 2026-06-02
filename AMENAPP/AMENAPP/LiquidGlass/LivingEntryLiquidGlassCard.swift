import SwiftUI

struct LivingEntryLiquidGlassCard<Content: View>: View {
    var contextTint: Color = .clear
    var elevated: Bool = false
    var pressed: Bool = false
    var scrollDepth: CGFloat = 0
    let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    init(
        contextTint: Color = .clear,
        elevated: Bool = false,
        pressed: Bool = false,
        scrollDepth: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.contextTint = contextTint
        self.elevated = elevated
        self.pressed = pressed
        self.scrollDepth = scrollDepth
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(background)
            .scaleEffect(pressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: pressed)
    }

    @ViewBuilder
    private var background: some View {
        let radius: CGFloat = elevated ? 18 : 14
        let shadowRadius: CGFloat = elevated ? 12 : 6
        let shadowY: CGFloat = elevated ? 5 : 2
        let shadowOpacity: Double = elevated ? 0.14 : 0.08

        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fillMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(contextTint)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: elevated ? 0.8 : 0.5)
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
    }

    private var fillMaterial: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(.systemBackground).opacity(0.97))
        }
        return elevated
            ? AnyShapeStyle(.thinMaterial)
            : AnyShapeStyle(.ultraThinMaterial)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(elevated ? 0.18 : 0.10)
            : Color.black.opacity(elevated ? 0.10 : 0.06)
    }
}
