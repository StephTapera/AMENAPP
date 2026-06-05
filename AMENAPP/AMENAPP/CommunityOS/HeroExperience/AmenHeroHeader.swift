// AmenHeroHeader.swift
// AMEN App — Community OS › Hero Experience
//
// Phase 5 Agent D2 — Hero Experience
// The single canonical photo-hero component used across all major surfaces.
//
// Design contract (C3):
//   - Photo: AsyncImage with .systemGray4/.systemGray5 gradient placeholder
//   - Scrim: LinearGradient(.clear → .black.opacity(0.70)) bottom 40%
//   - Badge pill: black.opacity(0.55) capsule, white text — AmenGlassDarkPill pattern
//   - Title: .title2.bold(), white
//   - Subtitle: .callout, white.opacity(0.85)
//   - Action pills: bottom-right, AmenGlassDarkPill only
//   - Corner radius: AmenRadius.photoHero (22pt), .continuous
//   - NO custom hex colors — system semantic colors + AmenDesignSystem tokens only
//   - Accessibility: image always has accessibilityLabel; Dynamic Type on all text
//   - Status bar integration: callers pass .ignoresSafeArea(.all, edges: .top) when
//     used as a full-screen header replacement

import SwiftUI

// MARK: — AmenHeroHeader

/// Core reusable photo hero component.
/// Embeds a photo (or gray placeholder), a bottom scrim, badge + text overlay
/// (bottom-left), and an action pill slot (bottom-right).
///
/// Usage:
/// ```swift
/// AmenHeroHeader(
///     imageUrl: "https://…",
///     title: "Crosspoint Church",
///     subtitle: "Phoenix, AZ",
///     badge: "Verified",
///     height: .standard
/// ) {
///     AmenGlassDarkPill(label: "Follow", systemImage: "plus.circle") { … }
/// }
/// ```
struct AmenHeroHeader<ActionPill: View>: View {

    let imageUrl: String?
    let title: String
    let subtitle: String?
    let badge: String?
    let height: HeroHeight
    @ViewBuilder let actionPill: () -> ActionPill

    // MARK: - HeroHeight

    enum HeroHeight {
        /// 200 pt — list cards, discovery rail items
        case compact
        /// 280 pt — profile headers, detail top-of-screen
        case standard
        /// 360 pt — full-screen immersive heroes, parallax entries
        case large

        var points: CGFloat {
            switch self {
            case .compact:  return 200
            case .standard: return 280
            case .large:    return 360
            }
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {

                // 1. Background: photo or gray placeholder
                heroBackground(size: geo.size)

                // 2. Bottom-anchored gradient scrim for text legibility
                //    Starts transparent at the vertical midpoint, fades to black 70% at bottom.
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.70)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.55)
                }

                // 3. Text overlay — badge + title + subtitle pinned to bottom-left
                VStack(alignment: .leading, spacing: 4) {
                    if let badge {
                        badgePill(badge)
                    }

                    if !title.isEmpty {
                        Text(title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .shadow(color: .black.opacity(0.30), radius: 4, x: 0, y: 1)
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                    }
                }
                .padding(.leading, 14)
                .padding(.bottom, 14)
                .padding(.trailing, geo.size.width * 0.38) // leave room for action pills

                // 4. Action pill slot — bottom-right
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                    actionPill()
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                }
            }
            .frame(width: geo.size.width, height: height.points)
            .clipShape(
                RoundedRectangle(cornerRadius: AmenRadius.photoHero, style: .continuous)
            )
        }
        .frame(height: height.points)
    }

    // MARK: - Hero background

    @ViewBuilder
    private func heroBackground(size: CGSize) -> some View {
        if let urlString = imageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: height.points)
                        .clipped()
                case .failure:
                    placeholderGradient(size: size)
                case .empty:
                    placeholderGradient(size: size)
                        .redacted(reason: .placeholder)
                @unknown default:
                    placeholderGradient(size: size)
                }
            }
            .accessibilityLabel(title.isEmpty ? "Hero image" : title)
            .accessibilityHidden(true) // decorative — title text is the accessible label
        } else {
            placeholderGradient(size: size)
                .accessibilityHidden(true)
        }
    }

    private func placeholderGradient(size: CGSize) -> some View {
        LinearGradient(
            colors: [Color(uiColor: .systemGray4), Color(uiColor: .systemGray5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: size.width, height: height.points)
    }

    // MARK: - Badge pill

    private func badgePill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5)
            )
    }
}

// MARK: — Accessibility note
// When AmenHeroHeader is used as a full-screen navigation header (replacing
// navigationBarTitleDisplayMode(.large)), the caller should apply:
//   .ignoresSafeArea(.all, edges: .top)
// so the photo bleeds under the status bar and Dynamic Island.

// MARK: — Preview

#if DEBUG
#Preview("Compact — with badge and action") {
    AmenHeroHeader(
        imageUrl: nil,
        title: "Men's Bible Study",
        subtitle: "Active · 245 Members",
        badge: "Bible Study",
        height: .compact
    ) {
        AmenGlassDarkPill(label: "Join", systemImage: "person.crop.circle.badge.plus") {}
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Standard — church hero") {
    AmenHeroHeader(
        imageUrl: nil,
        title: "Crosspoint Church",
        subtitle: "Non-Denominational",
        badge: "Verified",
        height: .standard
    ) {
        HStack(spacing: 8) {
            AmenGlassDarkPill(label: "Follow", systemImage: "plus.circle") {}
            AmenGlassDarkPill(label: "Visit", systemImage: "location.fill") {}
        }
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Large — no action pill") {
    AmenHeroHeader(
        imageUrl: nil,
        title: "Faith Over Fear",
        subtitle: "Pastor James · 42 min",
        badge: "Sermon",
        height: .large
    ) {
        EmptyView()
    }
    .ignoresSafeArea(.all, edges: .top)
}
#endif
