import SwiftUI

struct LiquidGlassMaterial: ViewModifier {
    let tint: Color?
    let elevated: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: elevated ? LiquidGlassTokens.cornerRadiusLarge : LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(elevated ? LiquidGlassTokens.blurElevated : LiquidGlassTokens.blurThin)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: elevated ? LiquidGlassTokens.cornerRadiusLarge : LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(colorScheme == .dark ? 0.18 : 0.7), Color.white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .blendMode(.screen)
                    }
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: elevated ? LiquidGlassTokens.cornerRadiusLarge : LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.clear, Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: elevated ? LiquidGlassTokens.cornerRadiusLarge : LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [tint.opacity(colorScheme == .dark ? 0.18 : 0.14), Color.clear, tint.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
            }
    }
}

extension View {
    func livingGlassMaterial(tint: Color? = nil, elevated: Bool = false) -> some View {
        modifier(LiquidGlassMaterial(tint: tint, elevated: elevated))
    }
}
