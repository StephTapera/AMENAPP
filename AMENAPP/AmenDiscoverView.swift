// AmenDiscoverView.swift
// AMENAPP
//
// Premium Liquid Glass Discover experience.
// Standalone view — does NOT replace AMENDiscoveryView or modify any PostCard UI.
// Design language: white/off-white background, black text, ultraThinMaterial glass cards,
// soft shadows, 28-32pt cornerRadius on hero cards, capsule filter pills.

import SwiftUI

// MARK: - DiscoverItem Model

struct DiscoverItem: Identifiable {
    let id = UUID()
    let type: DiscoverItemType
    let title: String
    let subtitle: String
    let badge: String
    let sfSymbol: String
    let isTall: Bool

    enum DiscoverItemType {
        case person, post, video, verse, community, hashtag, comment, photo
    }

    static let sampleItems: [DiscoverItem] = [
        DiscoverItem(
            type: .person,
            title: "Ascend Church Dallas",
            subtitle: "Church · 42k followers",
            badge: "Trending church",
            sfSymbol: "building.2.fill",
            isTall: true
        ),
        DiscoverItem(
            type: .post,
            title: "\"God met me in the middle of my uncertainty.\"",
            subtitle: "Testimony · 2.4k illuminations",
            badge: "Top post",
            sfSymbol: "quote.bubble.fill",
            isTall: false
        ),
        DiscoverItem(
            type: .video,
            title: "Faith under pressure — 90 sec clip",
            subtitle: "Video · 18.2k plays",
            badge: "Watch now",
            sfSymbol: "play.rectangle.fill",
            isTall: false
        ),
        DiscoverItem(
            type: .verse,
            title: "Isaiah 55:6",
            subtitle: "Seek the Lord while He may be found",
            badge: "Daily verse trail",
            sfSymbol: "book.fill",
            isTall: true
        ),
        DiscoverItem(
            type: .community,
            title: "Young Adults Prayer Circle",
            subtitle: "Community · 3.1k members",
            badge: "Join community",
            sfSymbol: "person.3.fill",
            isTall: false
        ),
        DiscoverItem(
            type: .hashtag,
            title: "#OpenTable",
            subtitle: "Hashtag · posts, photos, conversations",
            badge: "Hot topic",
            sfSymbol: "number",
            isTall: false
        ),
        DiscoverItem(
            type: .comment,
            title: "\"This helped me forgive someone this week.\"",
            subtitle: "Comment · 412 replies",
            badge: "Meaningful comment",
            sfSymbol: "message.fill",
            isTall: true
        ),
        DiscoverItem(
            type: .photo,
            title: "Baptism Sunday gallery",
            subtitle: "Photo collection · 184 moments",
            badge: "Photo story",
            sfSymbol: "photo.on.rectangle.angled",
            isTall: false
        ),
    ]
}

// MARK: - Hero Discovery Card Data

private struct HeroCard: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let badge: String
    let symbolName: String
    let accentColor: Color
}

private let heroCards: [HeroCard] = [
    HeroCard(
        title: "Palm Sunday reflections",
        subtitle: "Explore 4.2k shared moments",
        badge: "Seasonal",
        symbolName: "sun.max.fill",
        accentColor: Color(red: 0.95, green: 0.76, blue: 0.30)
    ),
    HeroCard(
        title: "Worship moments near you",
        subtitle: "Discover local communities",
        badge: "Local",
        symbolName: "music.note.house.fill",
        accentColor: Color(red: 0.40, green: 0.55, blue: 0.95)
    ),
    HeroCard(
        title: "Verses for anxiety",
        subtitle: "Daily scripture + reflections",
        badge: "Care",
        symbolName: "heart.text.clipboard.fill",
        accentColor: Color(red: 0.40, green: 0.80, blue: 0.65)
    ),
]

// MARK: - Explore Type Data

private struct ExploreType: Identifiable {
    let id = UUID()
    let label: String
    let symbol: String
}

private let exploreTypes: [ExploreType] = [
    ExploreType(label: "Text posts",    symbol: "doc.text.fill"),
    ExploreType(label: "Photos",        symbol: "photo.fill"),
    ExploreType(label: "Videos",        symbol: "play.rectangle.fill"),
    ExploreType(label: "Comments",      symbol: "bubble.left.fill"),
    ExploreType(label: "Hashtags",      symbol: "number"),
    ExploreType(label: "Bible verses",  symbol: "book.fill"),
    ExploreType(label: "Communities",   symbol: "person.3.fill"),
]

// MARK: - Liquid Glass Helpers

/// Shared Liquid Glass card background with hairline border and soft shadow.
private struct AmenDiscoverGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 28

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color(white: 0.88), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
    }
}

private extension View {
    func liquidGlass(cornerRadius: CGFloat = 28) -> some View {
        modifier(AmenDiscoverGlassCard(cornerRadius: cornerRadius))
    }
}

/// Small glass circle button shell.
private struct GlassCircleButton: View {
    let symbol: String
    var size: CGFloat = 38
    var iconSize: CGFloat = 15
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.systemScaled(iconSize, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.7))
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.55)))
                        .overlay(Circle().strokeBorder(Color(white: 0.88), lineWidth: 0.5))
                )
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Pill

private struct AmenDiscoverCategoryPill: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(isActive ? Color.black : Color.black.opacity(0.72))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    if isActive {
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .fill(Color.white.opacity(0.55))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color(white: 0.88), lineWidth: 0.5)
                            )
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hero Card View

private struct DiscoverHeroCardView: View {
    let card: HeroCard

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background: gradient fill with large symbol as art
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [card.accentColor.opacity(0.45), card.accentColor.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )

            // Large decorative symbol
            Image(systemName: card.symbolName)
                .font(.systemScaled(90, weight: .ultraLight))
                .foregroundStyle(card.accentColor.opacity(0.30))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.bottom, 60)

            // Badge — top left
            VStack {
                HStack {
                    Text(card.badge.uppercased())
                        .font(.systemScaled(10, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.72))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(Capsule().fill(Color.white.opacity(0.60)))
                                .overlay(Capsule().strokeBorder(Color(white: 0.88), lineWidth: 0.5))
                        )
                        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
                    Spacer()
                }
                Spacer()
            }
            .padding(14)

            // Bottom info tray
            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(card.subtitle)
                    .font(.systemScaled(13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(
                RoundedRectangle(cornerRadius: 0, style: .continuous)
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 0.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
        .frame(width: 280, height: 200)
    }
}

// MARK: - AMEN Intelligence Banner

private struct AmenIntelligenceBanner: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 44, height: 44)
                Image(systemName: "sparkles")
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Ranked for meaning, not noise")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(Color.black)
                Text("Discover through scripture, communities, and faith")
                    .font(.systemScaled(13, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.60))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("Explore →")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(Color.black)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .liquidGlass(cornerRadius: 24)
        .padding(.horizontal, 16)
    }
}

// MARK: - Discovery Grid Card

private struct DiscoveryGridCard: View {
    let item: DiscoverItem

    var body: some View {
        ZStack(alignment: .bottom) {
            // Symbol background
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [symbolColor.opacity(0.18), symbolColor.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: item.sfSymbol)
                .font(.systemScaled(48, weight: .ultraLight))
                .foregroundStyle(symbolColor.opacity(0.35))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.bottom, 56)

            // Quick actions — top right
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        GlassCircleButton(symbol: "bookmark", size: 32, iconSize: 13)
                        GlassCircleButton(symbol: "heart", size: 32, iconSize: 13)
                    }
                }
                Spacer()
            }
            .padding(10)

            // Badge — top left
            VStack {
                HStack {
                    Text(item.badge.uppercased())
                        .font(.systemScaled(9, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.72))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(Capsule().fill(Color.white.opacity(0.60)))
                        )
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    Spacer()
                }
                Spacer()
            }
            .padding(10)

            // Bottom info tray
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.systemScaled(11, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
        .frame(height: item.isTall ? 240 : 170)
    }

    private var symbolColor: Color {
        switch item.type {
        case .person:    return Color(red: 0.40, green: 0.55, blue: 0.95)
        case .post:      return Color(red: 0.30, green: 0.72, blue: 0.55)
        case .video:     return Color(red: 0.85, green: 0.30, blue: 0.38)
        case .verse:     return Color(red: 0.42, green: 0.35, blue: 0.88)
        case .community: return Color(red: 0.95, green: 0.62, blue: 0.22)
        case .hashtag:   return Color(red: 0.22, green: 0.68, blue: 0.85)
        case .comment:   return Color(red: 0.85, green: 0.45, blue: 0.70)
        case .photo:     return Color(red: 0.60, green: 0.78, blue: 0.35)
        }
    }
}

// MARK: - AmenDiscoverView

struct AmenDiscoverView: View {
    @State private var searchText = ""
    @State private var activeTab = "For You"
    @State private var activeFilter = "Bible verses"

    private let categories = ["For You", "People", "Posts", "Photos", "Videos", "Verses", "Communities"]
    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ZStack {
            Color(white: 0.97)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // 1. Sticky Header
                    headerSection
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    // 2. Category Pills
                    categoryPillsSection
                        .padding(.bottom, 20)

                    // 3. Hero Discovery Cards
                    heroCardsSection
                        .padding(.bottom, 24)

                    // 4. Explore by Type
                    exploreByTypeSection
                        .padding(.bottom, 24)

                    // 5. AMEN Intelligence Banner
                    AmenIntelligenceBanner()
                        .padding(.bottom, 24)

                    // 6. Discovery Grid
                    discoveryGridSection
                        .padding(.bottom, 60)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title block
            VStack(alignment: .leading, spacing: 4) {
                Text("AMEN DISCOVER")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.40))
                    .kerning(1.2)

                Text("Find people, truth, and\nmeaningful content.")
                    .font(.systemScaled(28, weight: .bold))
                    .foregroundStyle(Color.black)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 20)

            // Search bar
            searchBarRow
                .padding(.horizontal, 16)

            // Utility buttons
            utilityButtonsRow
                .padding(.horizontal, 20)
        }
    }

    private var searchBarRow: some View {
        HStack(spacing: 10) {
            // Search field capsule
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.35))

                TextField("Search people, verses, communities...", text: $searchText)
                    .font(.systemScaled(16, weight: .regular))
                    .foregroundStyle(Color.black)
                    .tint(Color.black)
                    .submitLabel(.search)
                    .onSubmit {
                        dlog("AmenDiscoverView: search submitted — \(searchText)")
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(14))
                            .foregroundStyle(Color.black.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.55)))
                    .overlay(Capsule().strokeBorder(Color(white: 0.88), lineWidth: 0.5))
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)

            // Ask Berean pill
            Button {
                dlog("AmenDiscoverView: Ask Berean tapped")
            } label: {
                Text("Ask Berean")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(Capsule().fill(Color.black))
                    .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
        }
    }

    private var utilityButtonsRow: some View {
        HStack(spacing: 10) {
            GlassCircleButton(symbol: "sparkles", size: 42, iconSize: 16) {
                dlog("AmenDiscoverView: smart suggestions tapped")
            }
            GlassCircleButton(symbol: "mic.fill", size: 42, iconSize: 16) {
                dlog("AmenDiscoverView: voice search tapped")
            }
            GlassCircleButton(symbol: "line.3.horizontal.decrease.circle", size: 42, iconSize: 16) {
                dlog("AmenDiscoverView: filter tapped")
            }
            Spacer()
        }
    }

    // MARK: - Category Pills

    private var categoryPillsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    AmenDiscoverCategoryPill(title: cat, isActive: activeTab == cat) {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                            activeTab = cat
                        }
                        dlog("AmenDiscoverView: category tapped — \(cat)")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Hero Cards

    private var heroCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trending Moments")
                .font(.systemScaled(18, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(heroCards) { card in
                        DiscoverHeroCardView(card: card)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Explore by Type

    private var exploreByTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore by Type")
                .font(.systemScaled(18, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(exploreTypes) { item in
                        exploreTypePill(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color(white: 0.88), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
        .padding(.horizontal, 16)
    }

    private func exploreTypePill(_ item: ExploreType) -> some View {
        Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                activeFilter = item.label
            }
            dlog("AmenDiscoverView: explore type selected — \(item.label)")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .font(.systemScaled(13, weight: .medium))
                Text(item.label)
                    .font(.systemScaled(13, weight: .semibold))
            }
            .foregroundStyle(activeFilter == item.label ? Color.white : Color.black.opacity(0.75))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(activeFilter == item.label ? Color.black : Color.white.opacity(0.80))
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Discovery Grid

    private var discoveryGridSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Discover")
                .font(.systemScaled(18, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 20)

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(DiscoverItem.sampleItems) { item in
                    DiscoveryGridCard(item: item)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - PreviewProvider

struct AmenDiscoverView_Previews: PreviewProvider {
    static var previews: some View {
        AmenDiscoverView()
    }
}
