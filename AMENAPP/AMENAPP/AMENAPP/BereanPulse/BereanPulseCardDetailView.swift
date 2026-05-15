import SwiftUI

struct BereanPulseCardDetailView: View {
    let card: BereanPulseCard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            detailSection(title: String(localized: "Why now"), body: card.whyNow)
            detailSection(title: String(localized: "Expanded insight"), body: card.expandedBody)
            detailSection(
                title: String(localized: "Why am I seeing this?"),
                body: card.sourceSignals.filter(\.isUserVisible).map(\.summary).joined(separator: " ")
            )
        }
        .accessibilityElement(children: .contain)
    }

    private func detailSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.white.opacity(0.92))
            Text(body)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
