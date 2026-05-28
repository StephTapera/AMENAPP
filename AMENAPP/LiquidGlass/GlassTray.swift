import SwiftUI

/// Bottom-anchored floating tray — the primary container for the reactions emoji bar.
/// Scale + fade in from bottom; each feature agent triggers it via `isVisible`.
/// Conforms to Reduce Motion: removes spring scale, keeps opacity fade.
struct GlassTray<Content: View>: View {
    @Binding var isVisible: Bool
    var alignment: HorizontalAlignment = .center
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion)     private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
            .background { trayBackground }
            .shadow(
                color: LiquidGlassTokens.shadowFloating.color,
                radius: LiquidGlassTokens.shadowFloating.radius,
                y: LiquidGlassTokens.shadowFloating.y
            )
            .scaleEffect(scaleValue, anchor: .bottom)
            .opacity(isVisible ? 1 : 0)
            .animation(revealAnimation, value: isVisible)
    }

    private var scaleValue: CGFloat {
        guard !reduceMotion else { return 1 }
        return isVisible ? 1 : 0.85
    }

    private var revealAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: LiquidGlassTokens.motionFast)
            : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.75)
    }

    @ViewBuilder private var trayBackground: some View {
        let r = LiquidGlassTokens.cornerRadiusMedium
        if reduceTransparency {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(LiquidGlassTokens.blurThin)
                .overlay {
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.44), lineWidth: 0.75)
                }
        }
    }
}
