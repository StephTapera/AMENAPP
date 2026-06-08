// BereanSourceQualityBadge.swift
// AMENAPP
//
// Reusable badge that shows a quality score (0.0–1.0) as a 1-5 star rating
// with a colour-coded background and a source type label.

import SwiftUI

struct BereanSourceQualityBadge: View {

    let score: Double       // 0.0 – 1.0
    var sourceType: BereanSourceType? = nil

    // MARK: - Derived values

    private var starCount: Int { max(1, min(5, Int((score * 5).rounded()))) }

    private var badgeColor: Color {
        if score >= 0.8 { return .green }
        if score >= 0.5 { return .yellow }
        return .red
    }

    private var accessibilityLabel: String {
        let stars = starCount
        let typeLabel = sourceType?.displayName ?? "source"
        return "\(typeLabel), quality \(stars) out of 5 stars"
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 3) {
            // Star row
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { index in
                    Image(systemName: index <= starCount ? "star.fill" : "star")
                        .font(.systemScaled(8, weight: .semibold))
                        .foregroundStyle(index <= starCount ? badgeColor : Color.secondary.opacity(0.4))
                }
            }

            // Source type label (optional)
            if let sourceType {
                Text(sourceType.displayName)
                    .font(.systemScaled(9, weight: .medium))
                    .foregroundStyle(badgeColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        BereanSourceQualityBadge(score: 0.92, sourceType: .peerReviewed)
        BereanSourceQualityBadge(score: 0.65, sourceType: .news)
        BereanSourceQualityBadge(score: 0.30, sourceType: .communityNote)
        BereanSourceQualityBadge(score: 1.0, sourceType: .scripture)
        BereanSourceQualityBadge(score: 0.0, sourceType: .video)
    }
    .padding()
}
