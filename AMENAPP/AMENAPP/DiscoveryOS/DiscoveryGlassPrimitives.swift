// DiscoveryGlassPrimitives.swift
// AMEN Connect Discovery Engine — Wave 3, Lane H
// Glass primitives: GlassPill, GlassFloatingNav, GlassHeroSurface
// Built on native GlassEffectContainer + .glassEffect().
// Respects Reduce Transparency and Reduce Motion.

import SwiftUI

// MARK: - Discovery Glass Pill (category filter)

struct DiscoveryGlassPill: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color(hex: "D9A441") : .primary.opacity(0.85))
            .padding(.horizontal, isSelected ? 16 : 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44, alignment: .center)
        }
        .buttonStyle(.plain)
        .glassEffect(
            reduceTransparency
                ? .regular
                : isSelected
                    ? .regular.tint(Color(hex: "D9A441").opacity(0.25)).interactive()
                    : .regular.interactive()
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.82),
            value: isSelected
        )
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Glass floating nav pill (hero-compressed state)

struct DiscoveryFloatingPill: View {
    let heroCard: DiscoveryCard
    let onTap: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: heroCard.type.systemIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: heroCard.glassTint.hex).opacity(0.9))

                Text(heroCard.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if heroCard.type == .prayerRoom || heroCard.type == .audioRoom,
                   case .prayerRoom(let pr) = heroCard.payload {
                    liveDot
                    Text("\(pr.liveCount)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(
            reduceTransparency ? .regular : .regular.interactive(),
            in: .capsule
        )
        .frame(maxWidth: 320)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityLabel("\(heroCard.title), tap to expand")
    }

    private var liveDot: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
    }
}

// MARK: - Glass hero surface container

struct DiscoveryGlassHeroSurface<Content: View>: View {
    let backgroundHint: AdaptiveBackground
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Adaptive tinted background
            if !reduceTransparency {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(0.85)
            }

            GlassEffectContainer(spacing: 16) {
                content()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var gradientColors: [Color] {
        let (r, g, b) = backgroundHint.color
        return [
            Color(red: r * 0.4, green: g * 0.4, blue: b * 0.5).opacity(0.6),
            Color(red: r * 0.2, green: g * 0.2, blue: b * 0.3).opacity(0.8),
        ]
    }
}

// MARK: - Shelf section header

struct DiscoveryShelfHeader: View {
    let shelf: DiscoveryShelf

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(shelf.title)
                    .font(.system(size: 17, weight: .bold))
                if let sub = shelf.subtitle {
                    Text(sub)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(shelf.title + (shelf.subtitle.map { ", " + $0 } ?? ""))
    }
}

// MARK: - CalmCap bottom view

struct DiscoveryCaughtUpView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)

            Text("You're caught up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Come back later for more communities and discussions.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're caught up. Come back later for more.")
    }
}

// MARK: - DiscoveryCardType icon helper

extension DiscoveryCardType {
    var systemIcon: String {
        switch self {
        case .bibleStudy:  return "book.closed.fill"
        case .prayerRoom:  return "hands.sparkles.fill"
        case .church:      return "building.columns.fill"
        case .event:       return "calendar.badge.plus"
        case .discussion:  return "bubble.left.and.bubble.right.fill"
        case .space:       return "rectangle.3.group.fill"
        case .audioRoom:   return "waveform.circle.fill"
        }
    }

    var accentHex: String {
        switch self {
        case .prayerRoom:  return "D9A441"
        case .bibleStudy:  return "7B5EA7"
        case .church:      return "245B8F"
        case .event:       return "4A7C59"
        case .discussion:  return "6B7280"
        case .space:       return "7B5EA7"
        case .audioRoom:   return "D9A441"
        }
    }
}
