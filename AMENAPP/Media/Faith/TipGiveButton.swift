import SwiftUI

struct TipGiveButton: View {
    var creatorId: String
    var postId: String
    var onTap: () -> Void

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.65)) {
                isExpanded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.80)) {
                    isExpanded = false
                }
                onTap()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.amenGold)
                Text("Give")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background { pillBackground }
            .scaleEffect(isExpanded ? 1.08 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.65), value: isExpanded)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Give to creator")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var pillBackground: some View {
        if reduceTransparency {
            Capsule().fill(Color(.systemBackground))
                .overlay(Capsule().strokeBorder(Color.amenGold.opacity(0.5), lineWidth: 1))
        } else {
            Capsule().fill(LiquidGlassTokens.blurThin)
                .overlay(Capsule().strokeBorder(Color.amenGold.opacity(0.35), lineWidth: 0.75))
        }
    }
}
