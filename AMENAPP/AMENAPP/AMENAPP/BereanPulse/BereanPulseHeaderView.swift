import SwiftUI

struct BereanPulseHeaderView: View {
    let titleDate: String
    let intro: String
    let collapseProgress: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "Berean"), systemImage: "sparkle")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .textCase(.uppercase)
                .tracking(3)
                .labelStyle(.titleAndIcon)

            Text(String(localized: "Today's Berean Pulse"))
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)

            Text(titleDate)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(intro)
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .scaleEffect(1 - (collapseProgress * 0.05), anchor: .topLeading)
        .offset(y: -(collapseProgress * 10))
        .opacity(1 - (collapseProgress * 0.16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Today's Berean Pulse. \(titleDate). \(intro)"))
    }
}
