// AmenDiscoverPillsRow.swift
// AMEN App — Discover tab search + topic pill row
//
// Liquid Glass pill-style search bar, Ask Berean shortcut, and
// horizontal topic filter pills — used as the landing header in AMENDiscoveryView.

import SwiftUI

// MARK: - Model

struct DiscoverPillItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let systemImage: String?
    let isActive: Bool
    let action: () -> Void

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: DiscoverPillItem, rhs: DiscoverPillItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - Main Pills Row

struct AmenDiscoverPillsRow: View {
    let searchPlaceholder: String
    let onSearchTap: () -> Void
    let onAskBereanTap: () -> Void
    let topics: [DiscoverPillItem]

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Button(action: onSearchTap) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.35))

                        Text(searchPlaceholder)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.32))
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(AmenPillBackground())
                }
                .buttonStyle(AmenPillPressStyle())

                Button(action: onAskBereanTap) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.purple)

                        Text("Ask Berean")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.purple)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(
                        AmenPillBackground(
                            topColor: Color.purple.opacity(0.12),
                            bottomColor: Color.purple.opacity(0.06),
                            borderColor: Color.white.opacity(0.95)
                        )
                    )
                }
                .buttonStyle(AmenPillPressStyle())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(topics) { topic in
                        AmenTopicPill(item: topic)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
}

// MARK: - Single Topic Pill

struct AmenTopicPill: View {
    let item: DiscoverPillItem

    var body: some View {
        Button(action: item.action) {
            HStack(spacing: 8) {
                if let systemImage = item.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }

                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(item.isActive ? Color.white : Color.black.opacity(0.82))
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background {
                if item.isActive {
                    Capsule()
                        .fill(Color.black)
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                } else {
                    AmenPillBackground()
                }
            }
        }
        .buttonStyle(AmenPillPressStyle())
    }
}

// MARK: - Shared Pill Background

struct AmenPillBackground: View {
    var topColor: Color = Color.white.opacity(0.88)
    var bottomColor: Color = Color.white.opacity(0.62)
    var borderColor: Color = Color.white.opacity(0.95)

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [topColor, bottomColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .frame(height: 1)
                    .blur(radius: 0.2)
                    .padding(.horizontal, 10)
            }
    }
}

// MARK: - Press Style

struct AmenPillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}
