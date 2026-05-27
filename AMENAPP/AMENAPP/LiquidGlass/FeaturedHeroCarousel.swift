import SwiftUI

struct FeaturedItem: Identifiable {
    let id = UUID()
    let title: String
    let badge: String?       // "NEW", "LIVE", nil
    let metadata: String     // e.g. "ARISE · Teaching · 24 min"
    let rating: String?      // e.g. "TV-MA", or nil
    let accent: Color
    var imageURL: URL? = nil // TODO: wire Firebase Storage URL
}

struct CarouselItem: Identifiable {
    let id = UUID()
    let title: String
    let accent: Color
    var imageURL: URL? = nil // TODO: wire Firebase Storage URL
}

/// Apple TV-style featured hero (full-bleed, paged) above a horizontal
/// "continue" carousel row. Drop this at the top of a discovery surface.
struct FeaturedHeroCarousel: View {
    let featured: [FeaturedItem]
    let rowTitle: String
    let rowItems: [CarouselItem]
    var onPlay: (FeaturedItem) -> Void = { _ in }
    var onAdd: (FeaturedItem) -> Void = { _ in }

    @State private var selection = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                heroPager
                carouselRow
            }
            .padding(.bottom, 40)
        }
        .background(Color.amenBlack.ignoresSafeArea())
    }

    private var heroPager: some View {
        VStack(spacing: 14) {
            TabView(selection: $selection) {
                ForEach(Array(featured.enumerated()), id: \.element.id) { index, item in
                    heroCard(item).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 540)

            pageDots
        }
    }

    private func heroCard(_ item: FeaturedItem) -> some View {
        ZStack(alignment: .bottom) {
            artwork(item.accent, url: item.imageURL)
                .overlay(
                    LinearGradient(colors: [.clear, .clear, Color.amenBlack.opacity(0.92)],
                                   startPoint: .top, endPoint: .bottom)
                )

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
                    Button { onPlay(item) } label: {
                        Label("Play", systemImage: "play.fill")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 40).padding(.vertical, 14)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    Button { onAdd(item) } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .frame(width: 50, height: 50)
                            .liquidGlass(cornerRadius: 25)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 28)
            .padding(.horizontal, 20)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(featured.indices, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i == selection ? 0.95 : 0.3))
                    .frame(width: i == selection ? 22 : 7, height: 7)
                    .animation(.amenSnappy, value: selection)
            }
        }
    }

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
                        VStack(alignment: .leading, spacing: 6) {
                            artwork(item.accent, url: item.imageURL)
                                .frame(width: 160, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Text(item.title)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                                .frame(width: 160, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private func artwork(_ accent: Color, url: URL?) -> some View {
        if let url {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                accent.opacity(0.5)
            }
        } else {
            LinearGradient(colors: [accent.opacity(0.85), accent.opacity(0.35), .amenBlack],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
