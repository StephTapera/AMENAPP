import SwiftUI

struct BereanPulseCardDetailView: View {
    let card: BereanPulseCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailSection(title: String(localized: "Expanded insight"), body: card.expandedBody)

            if !card.whyNowEvidence.isEmpty {
                evidenceSection
            }

            detailSection(
                title: String(localized: "Context Berean used"),
                body: contextBody
            )
        }
        .padding(14)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var contextBody: String {
        let visible = card.sourceSignals.filter(\.isUserVisible).map(\.summary)
        guard !visible.isEmpty else {
            return String(localized: "No visible source signals were attached to this card.")
        }
        return visible.joined(separator: " ")
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Evidence"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(card.whyNowEvidence, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func detailSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
