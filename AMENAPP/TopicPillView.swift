// TopicPillView.swift
// AMENAPP
//
// Tappable capsule pill for topic/interest labels.
// Wraps a NavigationLink to TopicFeedView.
// Matches the existing chip style from ProfileView (AMENFont.semiBold(12),
// white capsule with subtle border).

import SwiftUI

struct TopicPillView: View {
    let label: String
    let canonicalKey: String

    /// Optional cluster for colored accent dot
    var cluster: SpiritualTopicCluster? = nil

    var body: some View {
        NavigationLink(destination: TopicFeedView(topicKey: canonicalKey, displayName: label)) {
            HStack(spacing: 4) {
                if let cluster = cluster {
                    Circle()
                        .fill(Color(
                            red: cluster.chipColor.r,
                            green: cluster.chipColor.g,
                            blue: cluster.chipColor.b
                        ))
                        .frame(width: 6, height: 6)
                }

                Text(label)
                    .font(AMENFont.semiBold(12))
                    .foregroundColor(.black.opacity(0.65))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.82))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Convenience Initializers

    /// Create from a raw topic string (normalizes automatically).
    init(rawTopic: String) {
        let normalization = TopicNormalizationService.shared
        let key = normalization.normalize(rawTopic)
        self.canonicalKey = key
        self.label = rawTopic
        self.cluster = normalization.cluster(for: key)
    }

    /// Create from a canonical key.
    init(canonicalKey: String, label: String? = nil, cluster: SpiritualTopicCluster? = nil) {
        self.canonicalKey = canonicalKey
        self.label = label ?? TopicNormalizationService.shared.displayName(for: canonicalKey)
        self.cluster = cluster ?? TopicNormalizationService.shared.cluster(for: canonicalKey)
    }
}
