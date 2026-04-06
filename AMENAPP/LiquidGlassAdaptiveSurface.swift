import SwiftUI

struct AdaptiveGlassModifier: ViewModifier {
    var scrollVelocity: CGFloat
    var backgroundLuminance: CGFloat
    var cornerRadius: CGFloat
    var isPressed: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(opacity)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(borderOpacity), lineWidth: 0.5)
            )
            .scaleEffect(scale)
            .animation(.easeOut(duration: 0.25), value: scrollVelocity)
            .animation(.easeOut(duration: 0.2), value: isPressed)
    }

    private var opacity: Double {
        let velocityBoost = Double(scrollVelocity) * 0.2
        let luminanceBoost = (1 - Double(backgroundLuminance)) * 0.3
        return min(0.85, 0.4 + velocityBoost + luminanceBoost)
    }

    private var scale: CGFloat {
        isPressed || scrollVelocity > 1.5 ? 0.97 : 1.0
    }

    private var borderOpacity: Double {
        scrollVelocity > 1.5 ? 0.15 : 0.05
    }
}

extension View {
    func adaptiveGlass(
        scrollVelocity: CGFloat,
        backgroundLuminance: CGFloat,
        cornerRadius: CGFloat = 20,
        isPressed: Bool = false
    ) -> some View {
        modifier(
            AdaptiveGlassModifier(
                scrollVelocity: scrollVelocity,
                backgroundLuminance: backgroundLuminance,
                cornerRadius: cornerRadius,
                isPressed: isPressed
            )
        )
    }
}
