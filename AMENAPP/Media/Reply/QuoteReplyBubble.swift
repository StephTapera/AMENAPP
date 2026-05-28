import SwiftUI

struct QuoteReplyBubble: View {
    var quotedAuthorName: String
    var quotedContent: String
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 0) {
            // Purple left border
            Rectangle()
                .fill(Color.purple)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(quotedAuthorName)
                    .font(.caption.bold())
                    .foregroundStyle(Color.purple)
                    .lineLimit(1)
                Text(quotedContent.prefix(100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss quote reply")
        }
        .background { pillBackground }
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous))
        .shadow(
            color: LiquidGlassTokens.shadowSoft.color,
            radius: LiquidGlassTokens.shadowSoft.radius,
            y: LiquidGlassTokens.shadowSoft.y
        )
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Replying to \(quotedAuthorName): \(quotedContent)")
    }

    @ViewBuilder private var pillBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                .fill(LiquidGlassTokens.blurThin)
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.38), lineWidth: 0.6)
                }
        }
    }
}
