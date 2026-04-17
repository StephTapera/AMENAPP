// AmenDiscoverPillsRow.swift
// AMEN App — Discover tab search + topic pill row
//
// Liquid Glass pill-style search bar, Ask Berean shortcut, and
// horizontal topic filter pills — used as the landing header in AMENDiscoveryView.

import SwiftUI

// MARK: - Model

struct AmenDiscoverPillItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let systemImage: String?
    let isActive: Bool
    let action: () -> Void

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: AmenDiscoverPillItem, rhs: AmenDiscoverPillItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - Main Pills Row

struct AmenDiscoverPillsRow: View {
    let searchPlaceholder: String
    let onSearchTap: () -> Void
    let onAskBereanTap: () -> Void
    let topics: [AmenDiscoverPillItem]

    // MEDIUM FIX: Track focused pill index so accessibilityScrollAction can scroll
    // the horizontal rail one item at a time for VoiceOver and Switch Control users.
    @State private var focusedPillIndex: Int = 0

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Button(action: onSearchTap) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.systemScaled(18, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.35))

                        Text(searchPlaceholder)
                            .font(.systemScaled(17, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.32))
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    // Vertical padding scales with Dynamic Type instead of fixed height.
                    .padding(.vertical, 18)
                    .background(AmenPillBackground())
                }
                .buttonStyle(AmenPillPressStyle())

                Button(action: onAskBereanTap) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.systemScaled(15, weight: .semibold))
                            .foregroundStyle(Color.purple)

                        Text("Ask Berean")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(Color.purple)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
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

            // MEDIUM FIX: Wrap in ScrollViewReader so accessibilityScrollAction can
            // programmatically scroll to the previous/next pill by ID.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                            AmenTopicPill(item: topic)
                                .id(topic.id)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                // MEDIUM FIX: VoiceOver swipe-left/right scrolls the rail one pill at a time.
                .accessibilityScrollAction { edge in
                    switch edge {
                    case .leading:
                        let newIndex = max(focusedPillIndex - 1, 0)
                        focusedPillIndex = newIndex
                        if newIndex < topics.count {
                            withAnimation { proxy.scrollTo(topics[newIndex].id, anchor: .leading) }
                        }
                    case .trailing:
                        let newIndex = min(focusedPillIndex + 1, topics.count - 1)
                        focusedPillIndex = newIndex
                        if newIndex < topics.count {
                            withAnimation { proxy.scrollTo(topics[newIndex].id, anchor: .trailing) }
                        }
                    default:
                        break
                    }
                }
            }
            // Allow the parent vertical ScrollView to receive vertical gestures
            // simultaneously. Without this, the horizontal ScrollView captures
            // all pan gestures and the parent page cannot scroll when the user
            // starts a drag over the pills row.
            .simultaneousGesture(DragGesture(minimumDistance: 0))
        }
    }
}

// MARK: - Single Topic Pill

struct AmenTopicPill: View {
    let item: AmenDiscoverPillItem

    var body: some View {
        Button(action: item.action) {
            HStack(spacing: 8) {
                if let systemImage = item.systemImage {
                    Image(systemName: systemImage)
                        .font(.systemScaled(14, weight: .semibold))
                }

                Text(item.title)
                    .font(.systemScaled(16, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(item.isActive ? Color.white : Color.black.opacity(0.82))
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
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

// MARK: - Reusable String-Binding Category Pill Row (Liquid Glass edition)
//
// AmenDiscoverCategoryPillsRow — Liquid Glass horizontal pill filter strip
// driven by a @Binding<String> for the selected category.
// Active pill: white fill + shadow. Inactive: .ultraThinMaterial + hairline border.

struct AmenDiscoverCategoryPillsRow: View {
    let categories: [String]
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    Button(action: { selected = cat }) {
                        Text(cat)
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundColor(selected == cat ? .black : Color(white: 0.45))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Group {
                                    if selected == cat {
                                        Capsule().fill(.white)
                                            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
                                    } else {
                                        Capsule().fill(.ultraThinMaterial).opacity(0.8)
                                    }
                                }
                            )
                            .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.6), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Reusable String-Binding Filter Pill Row (legacy)
//
// AmenDiscoverFilterPillsRow — lightweight horizontal pill filter strip
// driven by a @Binding<String> for the selected category.
// Used in AmenDiscoverView and any other view that needs a simple text-only pill row.

struct AmenDiscoverFilterPillsRow: View {
    let categories: [String]
    @Binding var selected: String
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    FilterPillButton(title: cat, isSelected: selected == cat) {
                        withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.82))) {
                            selected = cat
                        }
                        onSelect?(cat)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Internal Pill Button

    private struct FilterPillButton: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.black.opacity(0.80))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color.black)
                                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        } else {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.88), Color.white.opacity(0.62)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.95), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
                        }
                    }
            }
            .buttonStyle(AmenPillPressStyle())
        }
    }
}
