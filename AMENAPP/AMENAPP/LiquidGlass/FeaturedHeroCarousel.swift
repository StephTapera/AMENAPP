import SwiftUI

struct FeaturedItem: Identifiable {
    let id = UUID()
    let title: String
    let badge: String?
    let metadata: String
    let rating: String?
    let accent: Color
    var imageURL: URL? = nil
}

struct CarouselItem: Identifiable {
    let id = UUID()
    let title: String
    let accent: Color
    var imageURL: URL? = nil
}

/// Apple TV-style featured hero (full-bleed, paged) above a horizontal
/// "continue" carousel row. Embed inside an outer ScrollView — does not
/// wrap its own ScrollView. Pass `scrollOffset` from the outer scroll to
/// get parallax and text-fade effects.
struct FeaturedHeroCarousel: View {
    let featured: [FeaturedItem]
    let rowTitle: String
    let rowItems: [CarouselItem]
    /// Y offset from the outer ScrollView (contentOffset.y). Used for parallax.
    var scrollOffset: CGFloat = 0
    var onPlay: (FeaturedItem) -> Void = { _ in }
    var onAdd: (FeaturedItem) -> Void = { _ in }
    var onCardTap: (FeaturedItem) -> Void = { _ in }

    @State private var selection = 0

    private let autoAdvanceTimer = Timer.publish(every: 4.5, on: .main, in: .common).autoconnect()

    // How much the hero text fades as the user scrolls past the carousel.
    private var textOpacity: Double {
        max(0, 1.0 - Double(max(0, scrollOffset)) / 180.0)
    }

    // Artwork parallax: image moves down at 28% of scroll speed, appearing to
    // lag behind the card container and stay fixed in space.
    private var parallaxOffset: CGFloat {
        max(0, scrollOffset) * 0.28
    }

    // Outer hero parallax: when user scrolls content up (negative offset),
    // the whole hero card moves at 40% speed creating depth separation.
    private var scrollParallaxOffset: CGFloat {
        min(0, scrollOffset) * 0.4
    }

    // Pull-down stretch: when overscrolled downward (positive offset),
    // scale the hero slightly so it feels anchored at the bottom edge.
    private var pullDownScale: CGFloat {
        max(1.0, 1.0 + scrollOffset * 0.003)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            heroPager
                .offset(y: scrollParallaxOffset)
                .scaleEffect(pullDownScale, anchor: .bottom)
            if !rowItems.isEmpty {
                carouselRow
            }
        }
        .padding(.bottom, 32)
    }

    // MARK: - Hero pager

    private var heroPager: some View {
        VStack(spacing: 14) {
            TabView(selection: $selection) {
                ForEach(Array(featured.enumerated()), id: \.element.id) { index, item in
                    heroCard(item)
                        .tag(index)
                        .onTapGesture { onCardTap(item) }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 500)
            .onReceive(autoAdvanceTimer) { _ in
                guard !featured.isEmpty else { return }
                // Pattern 2: bouncy spring for hero page advance
                withAnimation(
                    UIAccessibility.isReduceMotionEnabled
                        ? .easeOut(duration: 0.18)
                        : .spring(.bouncy(duration: 0.4, extraBounce: 0.1))
                ) {
                    selection = (selection + 1) % featured.count
                }
            }

            pageDots
        }
    }

    private func heroCard(_ item: FeaturedItem) -> some View {
        ZStack(alignment: .bottom) {
            // Artwork layer — clips to card bounds, offset creates parallax
            artwork(item.accent, url: item.imageURL)
                .offset(y: parallaxOffset)
                .overlay(
                    LinearGradient(
                        colors: [.clear, .clear, Color.amenBlack.opacity(0.93)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipped()

            // Text + buttons — fade as card scrolls off screen
            VStack(spacing: 14) {
                if let badge = item.badge {
                    Text(badge)
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .liquidGlass(cornerRadius: 999)
                        .foregroundStyle(.white)
                }

                Text(item.title)
                    .font(.largeTitle.weight(.heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Text(item.metadata)
                    if let rating = item.rating {
                        Text(rating)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.white.opacity(0.6)))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))

                HStack(spacing: 14) {
                    // Pattern 7 + 10: press-scale + specular top-edge shimmer on Play
                    Button { onPlay(item) } label: {
                        Label("Play", systemImage: "play.fill")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 40).padding(.vertical, 14)
                            .background(
                                ZStack {
                                    Capsule().fill(Color.white)
                                    // Pattern 10: specular top-edge highlight
                                    Capsule()
                                        .fill(Color.white.opacity(0.45))
                                        .frame(height: 1.5)
                                        .padding(.horizontal, 10)
                                        .frame(maxHeight: .infinity, alignment: .top)
                                        .padding(.top, 2)
                                }
                            )
                            .foregroundStyle(.black)
                    }
                    .amenPress()
                    Button { onAdd(item) } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .frame(width: 50, height: 50)
                            .liquidGlass(cornerRadius: 25)
                            .foregroundStyle(.white)
                    }
                    .amenPress()
                }
                .buttonStyle(.plain)
            }
            .opacity(textOpacity)
            .padding(.bottom, 28)
            .padding(.horizontal, 20)
        }
    }

    private var pageDots: some View {
        // Pattern 6: stretching page indicator — active dot morphs wider with bouncy spring
        HStack(spacing: 7) {
            ForEach(featured.indices, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i == selection ? 0.95 : 0.30))
                    // Active pill stretches to 26pt; inactive dots collapse to 7pt
                    .frame(width: i == selection ? 26 : 7, height: 7)
                    // Pattern 6: canonical bouncy spring for pill width morph
                    .animation(
                        UIAccessibility.isReduceMotionEnabled
                            ? .easeOut(duration: 0.18)
                            : .spring(.bouncy(duration: 0.4, extraBounce: 0.1)),
                        value: selection
                    )
                    // Pattern 10: specular top highlight on active pill
                    .overlay(alignment: .top) {
                        if i == selection {
                            Capsule()
                                .fill(Color.white.opacity(0.45))
                                .frame(height: 1.5)
                                .padding(.horizontal, 4)
                                .padding(.top, 1)
                        }
                    }
            }
        }
    }

    // MARK: - Carousel row

    private var carouselRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text(rowTitle).font(.title3.weight(.bold)).foregroundStyle(.white)
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(rowItems) { item in
                        carouselCard(item)
                            .frame(width: 160, height: 110)
                            // Scale-in as card enters viewport center
                            .visualEffect { content, proxy in
                                let midX = proxy.frame(in: .global).midX
                                let center = UIScreen.main.bounds.width / 2
                                let distance = abs(midX - center)
                                let scale = max(0.88, 1.0 - distance / (UIScreen.main.bounds.width * 0.9) * 0.12)
                                return content.scaleEffect(scale)
                            }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func carouselCard(_ item: CarouselItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            artwork(item.accent, url: item.imageURL)

            LinearGradient(
                colors: [.clear, Color.amenBlack.opacity(0.75)],
                startPoint: .center, endPoint: .bottom
            )

            Text(item.title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Shared artwork builder

    @ViewBuilder
    private func artwork(_ accent: Color, url: URL?) -> some View {
        if let url {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                accent.opacity(0.5)
            }
        } else {
            LinearGradient(
                colors: [accent.opacity(0.85), accent.opacity(0.35), .amenBlack],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}
