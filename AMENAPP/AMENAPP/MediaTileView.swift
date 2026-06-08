//
//  MediaTileView.swift
//  AMENAPP
//
//  Premium media tile for the Photos & Videos grid.
//  Shows thumbnail with subtle metadata overlays:
//  carousel count badge, video duration, verse pill.
//  Liquid Glass design system.
//

import SwiftUI

struct MediaTileView: View {
    let item: EnrichedMediaGridItem
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            thumbnailContent
                .overlay(alignment: .topTrailing) { carouselBadge }
                .overlay(alignment: .bottomLeading) { verseBadge }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
                .scaleEffect(isPressed ? 0.96 : 1.0)
                .animation(
                    reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.8),
                    value: isPressed
                )
        }
        .buttonStyle(MediaTileButtonStyle(isPressed: $isPressed))
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailContent: some View {
        CachedAsyncImage(
            url: URL(string: item.imageURL),
            size: CGSize(width: 200, height: 200)
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Rectangle()
                .fill(AmenTheme.Colors.shimmerBase)
                .overlay(
                    Image(systemName: "photo")
                        .font(.systemScaled(20))
                        .foregroundStyle(AmenTheme.Colors.iconSecondary)
                )
        }
        .frame(minHeight: 120)
        .clipped()
    }

    // MARK: - Carousel Count Badge

    @ViewBuilder
    private var carouselBadge: some View {
        if item.isCarousel && item.isFirstInPost {
            HStack(spacing: 3) {
                Image(systemName: "square.on.square")
                    .font(.systemScaled(9, weight: .semibold))
                Text("\(item.carouselCount)")
                    .font(.systemScaled(10, weight: .bold, design: .rounded))
            }
            .foregroundColor(AmenTheme.Colors.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(AmenTheme.Colors.mediaOverlay.opacity(0.78))
            )
            .padding(6)
            .accessibilityLabel("\(item.carouselCount) items")
        }
    }

    // MARK: - Verse Badge

    @ViewBuilder
    private var verseBadge: some View {
        if let verse = item.verseReference, !verse.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: "book.closed.fill")
                    .font(.systemScaled(8, weight: .medium))
                Text(verse)
                    .font(.systemScaled(9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(AmenTheme.Colors.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(AmenTheme.Colors.mediaOverlay.opacity(0.66))
            )
            .padding(6)
            .accessibilityLabel("Verse: \(verse)")
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var desc = "Photo"
        if item.isCarousel {
            desc = "\(item.carouselCount) photos"
        }
        if let verse = item.verseReference, !verse.isEmpty {
            desc += ", verse \(verse)"
        }
        return desc
    }
}

// MARK: - Button Style

/// Custom button style that reports press state without overriding visual behavior.
private struct MediaTileButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}
