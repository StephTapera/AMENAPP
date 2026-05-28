// AmenGatheringCard.swift
// AMENAPP — Gathering Card Components
//
// Large hero, compact list, and calendar variants.
// White Liquid Glass surface. Accessible. Reduce Motion/Transparency aware.

import SwiftUI

// MARK: - Large Hero Card

struct AmenGatheringHeroCard: View {
    let card: AmenGatheringFeedCard
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                heroBackground
                heroOverlay
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 6)
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.98 : 1))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !reduceMotion { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Tap to view gathering details")
    }

    @ViewBuilder
    private var heroBackground: some View {
        if let url = card.coverImageUrl {
            CachedAsyncImage(url: URL(string: url), size: CGSize(width: 800, height: 600)) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                gradientFallback
            }
        } else {
            gradientFallback
        }
    }

    private var gradientFallback: some View {
        ZStack {
            Color(.systemGray6)
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: card.type.systemImage)
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var heroOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                gatheringTypeBadge
                Spacer()
                if let countdown = card.countdownLabel {
                    countdownBadge(countdown)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)

                HStack(spacing: 6) {
                    Image(systemName: card.location.type.systemImage)
                        .font(.caption.weight(.medium))
                    Text(card.location.displaySummary)
                        .font(.caption.weight(.medium))
                    Text("·")
                    Text(card.startAt, style: .date)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.4), radius: 3)

                HStack(spacing: 8) {
                    rsvpCountLabel
                    accessModeBadge
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
        )
    }

    private var gatheringTypeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: card.type.systemImage)
                .font(.caption2.weight(.semibold))
            Text(card.type.displayName)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule(style: .continuous))
    }

    private func countdownBadge(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.5))
            .clipShape(Capsule(style: .continuous))
    }

    private var rsvpCountLabel: some View {
        Group {
            if card.rsvpCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                    Text("\(card.rsvpCount) going")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private var accessModeBadge: some View {
        if card.accessMode != .join {
            HStack(spacing: 3) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                Text(card.accessMode.displayName)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var gradientColors: [Color] {
        switch card.type {
        case .prayerNight:          return [Color(hue: 0.62, saturation: 0.4, brightness: 0.6), Color(hue: 0.7, saturation: 0.3, brightness: 0.4)]
        case .worshipNight:         return [Color(hue: 0.08, saturation: 0.5, brightness: 0.65), Color(hue: 0.03, saturation: 0.4, brightness: 0.5)]
        case .bibleStudy:           return [Color(hue: 0.35, saturation: 0.35, brightness: 0.55), Color(hue: 0.42, saturation: 0.3, brightness: 0.4)]
        case .volunteerOpportunity: return [Color(hue: 0.55, saturation: 0.4, brightness: 0.55), Color(hue: 0.5, saturation: 0.35, brightness: 0.4)]
        case .retreat:              return [Color(hue: 0.28, saturation: 0.35, brightness: 0.5), Color(hue: 0.33, saturation: 0.3, brightness: 0.38)]
        default:                    return [Color(hue: 0.6, saturation: 0.3, brightness: 0.55), Color(hue: 0.65, saturation: 0.25, brightness: 0.4)]
        }
    }

    private var accessibilityDescription: String {
        "\(card.type.displayName): \(card.title). \(card.startAt.formatted(date: .abbreviated, time: .shortened)). \(card.location.displaySummary). \(card.rsvpCount) going."
    }
}

// MARK: - Compact List Card

struct AmenGatheringCompactCard: View {
    let card: AmenGatheringFeedCard
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                typeIconTile

                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(card.startAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(card.location.displaySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let countdown = card.countdownLabel {
                        Text(countdown)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule(style: .continuous))
                    }
                    rsvpIndicator
                }
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.99 : 1))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !reduceMotion { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("\(card.type.displayName): \(card.title)")
        .accessibilityHint("Tap to view details")
    }

    private var typeIconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemGray6))
                .frame(width: 52, height: 52)
            Image(systemName: card.type.systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var rsvpIndicator: some View {
        if let status = card.userRsvpStatus {
            Image(systemName: status.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(status == .going ? .green : .secondary)
        } else if card.rsvpCount > 0 {
            Text("\(card.rsvpCount)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Section Header

struct AmenGatheringsSectionHeader: View {
    let title: String
    var showAll: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
            Spacer()
            if let action = showAll {
                Button("See All", action: action)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("See all \(title)")
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Skeleton Loading Card

struct AmenGatheringSkeletonCard: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(.systemGray5), Color(.systemGray6), Color(.systemGray5)],
                    startPoint: UnitPoint(x: phase - 0.5, y: 0),
                    endPoint: UnitPoint(x: phase + 0.5, y: 0)
                )
            )
            .frame(height: 220)
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
            .accessibilityLabel("Loading gathering")
    }
}
