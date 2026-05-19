import SwiftUI

struct AmenContextualReactionLayer: View {
    let results: [AmenContextualReactionResult]
    var maxVisible: Int = 2
    var onSelect: ((AmenContextualReactionResult) -> Void)? = nil

    private var visibleResults: [AmenContextualReactionResult] {
        Array(results.prefix(maxVisible))
    }

    var body: some View {
        if !visibleResults.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visibleResults) { result in
                        Button {
                            onSelect?(result)
                        } label: {
                            Label(result.title, systemImage: symbol(for: result))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.black.opacity(0.78))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .fill(Color.white.opacity(0.82))
                                        )
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(result.title)
                        .accessibilityHint(result.microcopy)
                        .accessibilityIdentifier("contextual_reaction_chip_\(result.triggerType.rawValue)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func symbol(for result: AmenContextualReactionResult) -> String {
        switch result.effectType {
        case .prayerGlow:
            return "sparkles"
        case .scriptureShimmer:
            return "book.closed"
        case .gratitudeBloom:
            return "sun.max"
        case .heartMorph, .amenPulse, .seasonalIconMorph:
            return "hands.sparkles"
        case .shareWithCareChip:
            return "square.and.arrow.up"
        case .saveForStudyChip:
            return "bookmark"
        case .hiddenReactionRing:
            return "circle.hexagongrid"
        case .softFirework, .none:
            return "circle"
        }
    }
}
