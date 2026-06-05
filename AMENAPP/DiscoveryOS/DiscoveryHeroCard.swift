// DiscoveryHeroCard.swift
// AMENAPP — DiscoveryOS
// Apple Music-style hero card for Spaces, mentors, churches, studies, events, resources.

import SwiftUI

// MARK: - Discovery Item

struct DiscoveryItem: Identifiable {
    let id: String
    var type: DiscoveryItemType
    var title: String
    var subtitle: String
    var badgeText: String?
    var accentColor: Color
    var gradientColors: [Color]
    var memberCount: Int?
    var isJoined: Bool

    enum DiscoveryItemType: String {
        case space, mentor, church, study, event, resource
        var icon: String {
            switch self {
            case .space:    return "rectangle.3.group.fill"
            case .mentor:   return "person.badge.key.fill"
            case .church:   return "building.columns.fill"
            case .study:    return "book.closed.fill"
            case .event:    return "calendar.badge.plus"
            case .resource: return "books.vertical.fill"
            }
        }
    }

    static let previews: [DiscoveryItem] = [
        DiscoveryItem(id: "1", type: .space, title: "Sunday Morning Crew",
                      subtitle: "A warm community for early risers in the faith",
                      badgeText: "Active", accentColor: .amenGold,
                      gradientColors: [Color(red: 0.6, green: 0.4, blue: 0.1), Color(red: 0.3, green: 0.15, blue: 0.05)],
                      memberCount: 84, isJoined: false),
        DiscoveryItem(id: "2", type: .study, title: "Book of James Deep Dive",
                      subtitle: "6-week study on faith and works",
                      badgeText: "Starting Soon", accentColor: .amenBlue ?? .blue,
                      gradientColors: [.blue.opacity(0.8), .indigo.opacity(0.6)],
                      memberCount: 23, isJoined: true),
        DiscoveryItem(id: "3", type: .mentor, title: "Elder Maria Thompson",
                      subtitle: "20 years of women's ministry and pastoral care",
                      badgeText: "Open", accentColor: Color.purple,
                      gradientColors: [.purple.opacity(0.7), .pink.opacity(0.4)],
                      memberCount: nil, isJoined: false)
    ]
}

// MARK: - Hero Card

struct DiscoveryHeroCard: View {
    let item: DiscoveryItem
    let onJoin: (DiscoveryItem) -> Void
    let onTap: (DiscoveryItem) -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            onTap(item)
        } label: {
            ZStack(alignment: .bottomLeading) {
                // Gradient background
                LinearGradient(
                    colors: item.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Content
                VStack(alignment: .leading, spacing: 8) {
                    Spacer()

                    // Type badge
                    if let badge = item.badgeText {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(item.type.rawValue.capitalized, systemImage: item.type.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))

                            Text(item.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(2)

                            if let count = item.memberCount {
                                Text("\(count) members")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }

                        Spacer()

                        // Join button
                        Button {
                            onJoin(item)
                        } label: {
                            Text(item.isJoined ? "Joined ✓" : "Join")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(item.isJoined ? Color.amenGold : .white)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(
                                    item.isJoined
                                        ? Color.white.opacity(0.15)
                                        : Color.amenGold,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.isJoined ? "Joined \(item.title)" : "Join \(item.title)")
                    }
                }
                .padding(16)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.97 : 1))
            .shadow(color: item.accentColor.opacity(0.3), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityHint("Double tap to view details")
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(reduceMotion ? nil : .spring(response: 0.25), value: isPressed)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(DiscoveryItem.previews) { item in
                DiscoveryHeroCard(item: item, onJoin: { _ in }, onTap: { _ in })
            }
        }
        .padding()
    }
}
