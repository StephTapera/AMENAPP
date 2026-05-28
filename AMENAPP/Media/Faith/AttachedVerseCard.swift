import SwiftUI

struct AttachedVerseCard: View {
    var verse: VerseAttachment
    var onTap: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // amenGold left border
                Rectangle()
                    .fill(Color.amenGold)
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(verse.reference)
                            .font(.caption.bold())
                            .foregroundStyle(Color.amenGold)
                        Spacer()
                        GlassBadge(icon: "", label: verse.translation, tint: Color.amenGold)
                    }
                    Text(verse.text)
                        .font(.custom("Georgia", size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background { cardBackground }
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous))
            .shadow(
                color: LiquidGlassTokens.shadowSoft.color,
                radius: LiquidGlassTokens.shadowSoft.radius,
                y: LiquidGlassTokens.shadowSoft.y
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Verse: \(verse.reference). \(verse.text). Tap to open in Berean.")
    }

    @ViewBuilder private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .fill(Color(.systemBackground))
        } else {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .fill(LiquidGlassTokens.blurThin)
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .strokeBorder(Color.amenGold.opacity(0.22), lineWidth: 0.75)
                }
        }
    }
}
