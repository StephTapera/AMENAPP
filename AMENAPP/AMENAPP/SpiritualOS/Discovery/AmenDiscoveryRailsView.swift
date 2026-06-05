// AmenDiscoveryRailsView.swift
// AMEN App — Spiritual OS / Community Discovery
//
// Apple TV / Netflix-style horizontal discovery rails.
// Section title + "See All" header above a horizontal LazyHStack of tappable cards.
//
// Design rules:
//   • NO glass on cards — Color(.secondarySystemBackground) only.
//   • NO glass on section headers.
//   • Glass is permitted only on overlaid action controls (not rendered here).
//   • Section title text uses Color.amenBlack — no decorative gold.
//   • Shimmer uses AmenTheme.Colors.shimmerBase / shimmerHighlight.
//
// Usage:
//   AmenDiscoveryRailsView(userId: currentUserId) { item in
//       // navigate to item
//   }

import SwiftUI

// MARK: - AmenDiscoveryRailsView

struct AmenDiscoveryRailsView: View {

    // MARK: Inputs

    let userId: String
    let onItemTap: (DiscoveryRailItem) -> Void
    var onSeeAll: ((DiscoveryRailType) -> Void)? = nil

    // MARK: Feature flags

    @AppStorage("amen_discovery_rails_enabled") private var isEnabled = true
    @AppStorage("amen_hero_cards_enabled") private var heroCardsEnabled = true

    // MARK: State

    @State private var viewModel = AmenDiscoveryRailsViewModel()

    // MARK: Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 32) {
                // Hero card carousel — Church, Space, Event, Prayer, Sermon
                if heroCardsEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Featured")
                            .font(.title3.bold())
                            .foregroundStyle(Color.amenBlack)
                            .padding(.horizontal, 18)
                        AmenDiscoveryHeroCarousel()
                    }
                }

                if viewModel.isLoading && viewModel.rails.isEmpty {
                    loadingPlaceholder
                } else if viewModel.rails.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.rails) { rail in
                        AmenDiscoveryRailSection(
                            rail: rail,
                            onItemTap: onItemTap,
                            onSeeAll: onSeeAll
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .task {
            guard isEnabled else { return }
            await viewModel.load(userId: userId)
        }
    }

    // MARK: - Loading placeholder — 3 shimmer rails

    private var loadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 32) {
            ForEach(0..<3, id: \.self) { _ in
                shimmerRail
            }
        }
        .accessibilityHidden(true)
    }

    private var shimmerRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header skeleton
            HStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(width: 160, height: 14)
                    .amenSkeleton()
                Spacer()
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(width: 48, height: 12)
                    .amenSkeleton()
            }
            .padding(.horizontal, 18)

            // Card skeletons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { _ in
                        shimmerCard
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private var shimmerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.shimmerBase)
                .frame(width: 160, height: 120)
                .amenSkeleton()

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AmenTheme.Colors.shimmerBase)
                .frame(width: 120, height: 12)
                .amenSkeleton()

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AmenTheme.Colors.shimmerBase)
                .frame(width: 80, height: 10)
                .amenSkeleton()
        }
        .frame(width: 160)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.amenSlate.opacity(0.5))
            Text("Discovering your community...")
                .font(.subheadline)
                .foregroundStyle(Color.amenSlate)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Discovering your community — content loading")
    }
}

// MARK: - AmenDiscoveryRailSection

struct AmenDiscoveryRailSection: View {

    let rail: DiscoveryRail
    let onItemTap: (DiscoveryRailItem) -> Void
    var onSeeAll: ((DiscoveryRailType) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader
            itemScrollRow
        }
    }

    // MARK: Section header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: rail.type.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.amenBlack)
                .accessibilityHidden(true)

            Text(rail.type.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.amenBlack)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                onSeeAll?(rail.type)
            } label: {
                Text("See All")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all \(rail.type.title)")
            .accessibilityHint("Opens the full list for this section")
        }
        .padding(.horizontal, 18)
    }

    // MARK: Horizontal scroll row

    private var itemScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(rail.items) { item in
                    AmenDiscoveryRailCard(item: item)
                        .onTapGesture {
                            onItemTap(item)
                        }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)  // prevent shadow clipping at edges
        }
    }
}

// MARK: - AmenDiscoveryRailCard

struct AmenDiscoveryRailCard: View {

    let item: DiscoveryRailItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageSection
            textSection
            progressSection
        }
        .frame(width: 160)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Image area (160 x 120)

    private var imageSection: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let url = item.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure, .empty:
                            fallbackImageView
                        @unknown default:
                            fallbackImageView
                        }
                    }
                } else {
                    fallbackImageView
                }
            }
            .frame(width: 160, height: 120)
            .clipped()
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 12,
                    style: .continuous
                )
            )
            .overlay(alignment: .bottom) {
                // Gradient scrim for legibility
                LinearGradient(
                    colors: [.clear, .black.opacity(0.30)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
            }

            // Badge pill — top right of image
            if let badge = item.badgeText {
                Text(badge)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.70))
                    )
                    .padding(6)
            }
        }
        .frame(width: 160, height: 120)
    }

    // MARK: Fallback when no image

    private var fallbackImageView: some View {
        ZStack {
            Rectangle()
                .fill(Color(.tertiarySystemBackground))
            Image(systemName: fallbackIcon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.amenSlate.opacity(0.5))
        }
    }

    private var fallbackIcon: String {
        switch item.type {
        case .space:       return "bubble.left.and.bubble.right"
        case .mentor:      return "person.circle"
        case .church:      return "building.columns"
        case .event:       return "calendar"
        case .study:       return "book.closed"
        case .person:      return "person.crop.circle"
        case .churchNote:  return "doc.text"
        case .discussion:  return "quote.bubble"
        }
    }

    // MARK: Text section

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let sub = item.subtitle {
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, item.progressFraction != nil ? 6 : 10)
    }

    // MARK: Progress bar (continueJourney items only)

    @ViewBuilder
    private var progressSection: some View {
        if let fraction = item.progressFraction {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemFill))
                        .frame(height: 4)

                    Rectangle()
                        .fill(Color.teal)
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, fraction))), height: 4)
                }
            }
            .frame(height: 4)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .accessibilityLabel("\(Int(max(0, min(1, fraction)) * 100)) percent complete")
        }
    }

    // MARK: Accessibility label

    private var accessibilityLabel: String {
        var parts = [item.title]
        if let sub = item.subtitle { parts.append(sub) }
        if let badge = item.badgeText { parts.append(badge) }
        if let fraction = item.progressFraction {
            parts.append("\(Int(max(0, min(1, fraction)) * 100)) percent complete")
        }
        return parts.joined(separator: ", ")
    }
}

