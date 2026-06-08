import SwiftUI

struct AmenObjectHubActivityStrip: View {
    let hub: AmenCommunityHub

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var activityCards: [AmenHubRecentActivity] {
        hub.activityCards()
    }

    var body: some View {
        if !activityCards.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(activityCards.enumerated()), id: \.element.id) { index, card in
                        AmenActivityCard(card: card)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)
                            .animation(
                                reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.82)
                                    .delay(Double(index) * 0.06),
                                value: appeared
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .onAppear { appeared = true }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Hub activity")
        }
    }
}

// MARK: - Single Activity Card

private struct AmenActivityCard: View {
    let card: AmenHubRecentActivity

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: card.iconName)
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(formattedCount(card.count)) \(card.label)")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(card.period)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemGray5))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.thinMaterial)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                }
            }
        }
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .accessibilityLabel("\(formattedCount(card.count)) \(card.label) \(card.period)")
    }

    private func formattedCount(_ n: Int) -> String {
        if n >= 1_000 { return "\(n / 1000)k" }
        return "\(n)"
    }
}
