import SwiftUI

struct ChurchNotesGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: ChurchNotesDesignTokens.Radius.card, style: .continuous)
                    .fill(.thinMaterial)
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
