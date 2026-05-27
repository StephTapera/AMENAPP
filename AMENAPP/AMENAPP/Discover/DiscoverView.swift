import SwiftUI

/// Discover surface — wraps `FeaturedHeroCarousel` with live Firestore data.
/// Falls back to `fallbackFeatured` / `fallbackContinue` while the `featured`
/// collection loads or when it returns empty (e.g., before backend is seeded).
///
/// Drop this inside an outer `ScrollView` (no internal scroll).  Pass
/// `scrollOffset` from the parent's `onScrollGeometryChange` to drive parallax.
struct DiscoverView: View {
    /// Y scroll offset from the outer ScrollView, used for hero parallax.
    var scrollOffset: CGFloat = 0
    /// Live items from HomeView's local data sources (verse, sermon, Berean).
    var fallbackFeatured: [FeaturedItem] = []
    var fallbackContinue: [CarouselItem] = []
    var onPlay: (FeaturedItem) -> Void = { _ in }
    var onAdd: (FeaturedItem) -> Void = { _ in }

    @State private var model = DiscoverViewModel()
    @State private var expandedItem: FeaturedItem?

    private var displayFeatured: [FeaturedItem] {
        model.phase.featured ?? fallbackFeatured
    }
    private var displayContinue: [CarouselItem] {
        model.phase.continueItems ?? fallbackContinue
    }

    var body: some View {
        FeaturedHeroCarousel(
            featured: displayFeatured,
            rowTitle: "Continue in AMEN",
            rowItems: displayContinue,
            scrollOffset: scrollOffset,
            onPlay: { item in
                model.play(item)
                onPlay(item)
            },
            onAdd: { item in
                model.add(item)
                onAdd(item)
            },
            onCardTap: { item in
                withAnimation(.amenSpring) { expandedItem = item }
            }
        )
        .task { model.start() }
        .onDisappear { model.stop() }
        .sheet(item: $expandedItem) { item in
            ExpandableCardDetail(item: item)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Expandable card detail

/// Full-screen detail view shown when a hero card is tapped.
struct ExpandableCardDetail: View {
    let item: FeaturedItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            // Artwork
            Group {
                if let url = item.imageURL {
                    AsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fill) }
                        placeholder: { item.accent.opacity(0.5) }
                } else {
                    LinearGradient(
                        colors: [item.accent.opacity(0.9), item.accent.opacity(0.4), .amenBlack],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
            .ignoresSafeArea()
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.amenBlack.opacity(0.97)],
                    startPoint: .center, endPoint: .bottom
                )
                .ignoresSafeArea()
            )

            // Info + actions
            VStack(spacing: 18) {
                if let badge = item.badge {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .liquidGlass(cornerRadius: 999)
                        .foregroundStyle(.white)
                }

                Text(item.title)
                    .font(.title.weight(.heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Text(item.metadata)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                HStack(spacing: 16) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    Button { dismiss() } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .frame(width: 54, height: 54)
                            .liquidGlass(cornerRadius: 27)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 28)
        }
    }
}
