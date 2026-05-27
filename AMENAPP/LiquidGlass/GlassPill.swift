import SwiftUI

/// Capsule-shaped glass surface — the standard container for reply input bars, tags, and badges.
/// Use `isProminent` to elevate to regularMaterial when legibility over media matters.
struct GlassPill<Content: View>: View {
    var isProminent: Bool = false
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 9
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background { pillBackground }
            .shadow(
                color: LiquidGlassTokens.shadowSoft.color,
                radius: LiquidGlassTokens.shadowSoft.radius,
                y: LiquidGlassTokens.shadowSoft.y
            )
    }

    @ViewBuilder private var pillBackground: some View {
        let material: Material = reduceTransparency
            ? Material.thick
            : (isProminent ? LiquidGlassTokens.blurElevated : LiquidGlassTokens.blurThin)
        let borderOpacity: Double = reduceTransparency ? 0.18 : (isProminent ? 0.50 : 0.40)

        Capsule(style: .continuous)
            .fill(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(material))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 0.75)
            }
    }
}

// MARK: - Convenience modifier

extension View {
    func glassPill(prominent: Bool = false) -> some View {
        GlassPill(isProminent: prominent) { self }
    }
}
