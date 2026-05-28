import SwiftUI

/// Alias used in LivingEntries module — matches the same glass card contract.
typealias LivingEntryLiquidGlassCard = LiquidGlassCard

struct LiquidGlassCard<Content: View>: View {
    var contextTint: Color? = nil
    var elevated = false
    var pressed = false
    var scrollDepth: CGFloat = 0
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .livingGlassMaterial(tint: contextTint, elevated: elevated)
            .clipShape(RoundedRectangle(cornerRadius: elevated ? LiquidGlassTokens.cornerRadiusLarge : LiquidGlassTokens.cornerRadiusMedium, style: .continuous))
            .scaleEffect(pressed ? 0.985 : 1)
            .shadow(
                color: (elevated ? LiquidGlassTokens.shadowFloating : LiquidGlassTokens.shadowSoft).color,
                radius: (elevated ? LiquidGlassTokens.shadowFloating : LiquidGlassTokens.shadowSoft).radius + scrollDepth,
                y: (elevated ? LiquidGlassTokens.shadowFloating : LiquidGlassTokens.shadowSoft).y
            )
            .animation(
                reduceMotion ? .easeOut(duration: LiquidGlassTokens.motionFast) : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82),
                value: pressed
            )
    }
}
