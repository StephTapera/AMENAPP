import SwiftUI

struct ChurchNotesGlassCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: ChurchNotesDesignTokens.Radius.card, style: .continuous)
                    .fill(reduceTransparency ? Color(.secondarySystemGroupedBackground) : Color.clear)
                    .background(
                        .thinMaterial,
                        in: RoundedRectangle(cornerRadius: ChurchNotesDesignTokens.Radius.card, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ChurchNotesDesignTokens.Radius.card, style: .continuous)
                            .fill(ChurchNotesDesignTokens.Colors.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ChurchNotesDesignTokens.Radius.card, style: .continuous)
                            .strokeBorder(ChurchNotesDesignTokens.Colors.neutralBorder, lineWidth: 0.5)
                    )
            )
            .shadow(
                color: ChurchNotesDesignTokens.Shadow.card.color,
                radius: ChurchNotesDesignTokens.Shadow.card.radius,
                y: ChurchNotesDesignTokens.Shadow.card.y
            )
    }
}

extension View {
    func churchNotesGlassCard() -> some View {
        modifier(ChurchNotesGlassCardModifier())
    }
}
