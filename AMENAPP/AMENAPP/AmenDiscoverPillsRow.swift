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
    var compactProgress: CGFloat = 0
    var searchMorphNamespace: Namespace.ID? = nil
    let onSearchTap: () -> Void
    let onAskBereanTap: () -> Void
    let topics: [AmenDiscoverPillItem]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedCompactProgress: CGFloat {
        min(max(compactProgress, 0), 1)
    }

    private var searchWidth: CGFloat {
        220 - (clampedCompactProgress * 166)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: onSearchTap) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.systemScaled(13, weight: .medium))
                            .frame(width: 18)

                        Text(searchPlaceholder)
                            .font(.systemScaled(13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .opacity(1 - clampedCompactProgress)
                            .id(searchPlaceholder)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(width: searchWidth, alignment: .leading)
                    .discoverSearchMorph(namespace: searchMorphNamespace)
                    .background(discoverPillBackground(isActive: false))
                    .clipShape(Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(DiscoverPillPressStyle(reduceMotion: reduceMotion))
                .accessibilityLabel("Search")

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
                    .background(discoverPillBackground(isActive: true))
                    .clipShape(Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
                    .shadow(color: .black.opacity(0.04 + (0.04 * clampedCompactProgress)), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(DiscoverPillPressStyle(reduceMotion: reduceMotion))
                .accessibilityLabel("Ask Berean AI")

                if !topics.isEmpty {
                    Divider()
                        .frame(height: 18)
                        .opacity(1 - clampedCompactProgress)
                }

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
                        .background(discoverPillBackground(isActive: topic.isActive))
                        .clipShape(Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(DiscoverPillPressStyle(reduceMotion: reduceMotion))
                    .opacity(1 - (clampedCompactProgress * 0.35))
                    .scaleEffect(1 - (clampedCompactProgress * 0.03))
                    .accessibilityLabel(topic.title)
                    .accessibilityAddTraits(topic.isActive ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
            .animation(Motion.adaptive(.spring(response: 0.34, dampingFraction: 0.86)), value: clampedCompactProgress)
            .animation(Motion.adaptive(.easeInOut(duration: 0.22)), value: searchPlaceholder)
        }
    }

    private func discoverPillBackground(isActive: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(isActive ? 0.58 : 0.42))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(isActive ? 0.55 : 0.36), lineWidth: 0.6)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(isActive ? 0.38 : 0.26), lineWidth: 0.5)
            }
    }
}

private extension View {
    @ViewBuilder
    func discoverSearchMorph(namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: "discover_search_capsule", in: namespace)
        } else {
            self
        }
    }
}

private struct DiscoverPillPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.025 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}
