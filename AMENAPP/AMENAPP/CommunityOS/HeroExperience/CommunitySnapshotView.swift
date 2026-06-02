// CommunitySnapshotView.swift
// AMEN App — Community Around Content OS › Dynamic Hero Experience
//
// A horizontal strip of community-metric chips.
// Accepts an optional CommunityNode; renders a skeleton while loading.

import SwiftUI
import Foundation

// MARK: - CommunitySnapshotView

struct CommunitySnapshotView: View {

    let node: CommunityNode?
    let isLoading: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        MetricChip(icon: "bubble.left.fill", count: 999, label: "discussing")
                            .redacted(reason: .placeholder)
                    }
                } else if let node {
                    MetricChip(
                        icon: "bubble.left.fill",
                        count: node.discussionCount,
                        label: "discussing"
                    )
                    MetricChip(
                        icon: "hands.sparkles",
                        count: node.prayerCount,
                        label: "praying"
                    )
                    MetricChip(
                        icon: "text.quote",
                        count: node.testimonyCount,
                        label: "testimonies"
                    )
                    if node.churchCount > 0 {
                        MetricChip(
                            icon: "building.columns",
                            count: node.churchCount,
                            label: "churches"
                        )
                    }
                } else {
                    // No community yet — show zero-state chips so layout is stable.
                    MetricChip(icon: "bubble.left.fill",  count: 0, label: "discussing")
                    MetricChip(icon: "hands.sparkles",    count: 0, label: "praying")
                    MetricChip(icon: "text.quote",        count: 0, label: "testimonies")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - MetricChip

private struct MetricChip: View {
    let icon: String
    let count: Int
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
            Text(count.communityAbbreviated)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color(.secondaryLabel))
            Text(label)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count.communityAbbreviated) \(label)")
    }
}

// MARK: - Int + communityAbbreviated

private extension Int {
    var communityAbbreviated: String {
        switch self {
        case 1_000_000...:
            let v = Double(self) / 1_000_000
            return v.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(v))M"
                : String(format: "%.1fM", v)
        case 1_000...:
            let v = Double(self) / 1_000
            return v.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(v))K"
                : String(format: "%.1fK", v)
        default:
            return "\(self)"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Loaded") {
    CommunitySnapshotView(
        node: CommunityNode(
            contentObjectId: "preview",
            contentKind: .song,
            name: "Goodness of God",
            memberCount: 4_200,
            discussionCount: 4_200,
            prayerCount: 900,
            testimonyCount: 220,
            churchCount: 15
        ),
        isLoading: false
    )
}

#Preview("Loading") {
    CommunitySnapshotView(node: nil, isLoading: true)
}

#Preview("No community") {
    CommunitySnapshotView(node: nil, isLoading: false)
}
#endif
