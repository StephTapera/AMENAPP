// BILSourceCardsView.swift
// AMENAPP — BI-04 Source Cards

import SwiftUI

struct BILSourceCardsView: View {
    var body: some View {
        List {
            Section("Source cards") {
                ForEach(BILWaveOneSamples.sourceCards) { card in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(card.title)
                                .font(.headline)
                            Spacer()
                            Text(card.tier.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(card.oneLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(card.citationCount) citations")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Tier guard") {
                ForEach(BILTier.allCases) { tier in
                    LabeledContent(tier.rawValue, value: tier.detail)
                }
            }
        }
        .navigationTitle("Source Cards")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        BILSourceCardsView()
    }
}
