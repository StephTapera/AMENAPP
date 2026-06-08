import SwiftUI

struct HeyFeedSessionModeChips: View {
    let sessionModes: [HeyFeedSessionMode]
    let activeMode: HeyFeedSessionMode
    let onSelect: (HeyFeedSessionMode) -> Void

    private let fixedModes: [HeyFeedSessionMode] = [
        .lighterTonight,
        .moreEncouragement,
        .moreBibleTeaching,
        .lessControversy,
        .moreLocalChurches,
        .exploreNewCreators,
        .morePrayerTestimonies,
        .morePracticalFaith
    ]

    var body: some View {
        HStack(spacing: 8) {
            Group {
                modeButton(.lighterTonight)
                modeButton(.moreEncouragement)
                modeButton(.moreBibleTeaching)
                modeButton(.lessControversy)
                modeButton(.moreLocalChurches)
                modeButton(.exploreNewCreators)
                modeButton(.morePrayerTestimonies)
                modeButton(.morePracticalFaith)
            }
        }
    }

    @ViewBuilder
    private func modeButton(_ mode: HeyFeedSessionMode) -> some View {
        let isActive = activeMode == mode
        Button {
            onSelect(mode)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.systemScaled(12, weight: .semibold))
                Text(mode.label)
                    .font(AMENFont.semiBold(13))
            }
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isActive ? AnyShapeStyle(Color(.systemGray5)) : AnyShapeStyle(.thinMaterial))
                    .overlay(
                        Capsule().strokeBorder(
                            isActive ? Color.primary.opacity(0.2) : Color.primary.opacity(0.08),
                            lineWidth: 1
                        )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.7)), value: isActive)
    }
}
