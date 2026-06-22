import SwiftUI

struct HighlightActionCapsule: View {
    let onQuote: () -> Void
    let onReply: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onBerean: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            capsuleButton(title: "Quote", systemImage: "quote.opening", action: onQuote)
            capsuleButton(title: "Reply", systemImage: "arrowshape.turn.up.left", action: onReply)
            capsuleButton(title: "Save", systemImage: "bookmark", action: onSave)
            capsuleButton(title: "Share", systemImage: "square.and.arrow.up", action: onShare)
            capsuleButton(title: "Ask", systemImage: "sparkles", action: onBerean)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
    }

    private func capsuleButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.systemScaled(12, weight: .semibold))
                Text(title)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}
