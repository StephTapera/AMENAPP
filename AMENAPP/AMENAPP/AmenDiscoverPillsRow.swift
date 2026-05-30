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
                // Search or Ask pill — full-width entry point
                Button(action: onSearchTap) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color.primary.opacity(0.45))
                        Text("Search or Ask")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color.primary.opacity(0.45))
                            .lineLimit(1)
                        Spacer()
                        Button(action: onAskBereanTap) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Color.primary.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ask Berean AI with voice")
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .background(Color(.systemBackground))
                    .clipShape(Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search or Ask")

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
                                ? Color.black
                                : Color.black.opacity(0.45)
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    topic.isActive
                                        ? AnyShapeStyle(Color(.systemBackground))
                                        : AnyShapeStyle(Color(.systemBackground).opacity(0.7))
                                )
                                .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    topic.isActive
                                        ? Color(uiColor: .separator).opacity(0.20)
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
