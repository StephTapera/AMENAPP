// AmenDiscoverPillsRow.swift
// AMEN App — Discovery System
//
// Horizontal scrolling pill row: search entry, Ask Berean button, and topic filters.

import SwiftUI

struct AmenDiscoverPillItem {
    let title: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void
}

struct AmenDiscoverPillsRow: View {
    let searchPlaceholder: String
    let onSearchTap: () -> Void
    let onAskBereanTap: () -> Void
    let topics: [AmenDiscoverPillItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Search entry pill
                Button(action: onSearchTap) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.systemScaled(13, weight: .medium))
                        Text(searchPlaceholder)
                            .font(.systemScaled(13, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")

                // Ask Berean AI button
                Button(action: onAskBereanTap) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.systemScaled(13, weight: .medium))
                        Text("Ask Berean")
                            .font(.systemScaled(13, weight: .medium))
                    }
                    .foregroundStyle(Color(uiColor: .label))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask Berean AI")

                if !topics.isEmpty {
                    Divider().frame(height: 18)
                }

                // Topic filter pills
                ForEach(topics.indices, id: \.self) { i in
                    let topic = topics[i]
                    Button(action: topic.action) {
                        HStack(spacing: 5) {
                            Image(systemName: topic.systemImage)
                                .font(.systemScaled(12, weight: .medium))
                            Text(topic.title)
                                .font(.systemScaled(13, weight: topic.isActive ? .semibold : .regular))
                        }
                        .foregroundStyle(
                            topic.isActive
                                ? Color(uiColor: .label)
                                : Color(uiColor: .secondaryLabel)
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    topic.isActive
                                        ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                                        : AnyShapeStyle(Color(uiColor: .tertiarySystemBackground))
                                )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    topic.isActive
                                        ? Color(uiColor: .separator).opacity(0.45)
                                        : Color.clear,
                                    lineWidth: 0.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(topic.title)
                    .accessibilityAddTraits(topic.isActive ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
