import SwiftUI

/// Horizontal deck of featured cards. Tapping a card expands it to a full-screen
/// overlay. Drag down (> 120 pt) or flick (predicted > 300 pt) to collapse.
///
/// Cards scale in from the edges toward the viewport center using `visualEffect`.
/// The expanded state uses `matchedGeometryEffect` for a seamless card-to-overlay
/// transition animated by `.amenSpring`.
struct ExpandableDeck<Detail: View>: View {
    let items: [FeaturedItem]
    @ViewBuilder var detail: (FeaturedItem) -> Detail

    @Namespace private var ns
    @State private var selectedIndex: Int?
    @State private var dragOffset: CGSize = .zero

    private var dragProgress: Double {
        min(1, abs(dragOffset.height) / 300)
    }

    var body: some View {
        ZStack {
            deck
            if let idx = selectedIndex, idx < items.count {
                expandedOverlay(item: items[idx], index: idx)
                    .transition(.opacity)
            }
        }
        .animation(.amenSpring, value: selectedIndex)
    }

    // MARK: - Deck row

    private var deck: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    deckCard(item)
                        .frame(width: 200, height: 150)
                        .matchedGeometryEffect(id: idx, in: ns, isSource: selectedIndex == nil)
                        // Scale toward center as card enters the viewport
                        .visualEffect { content, proxy in
                            let midX = proxy.frame(in: .global).midX
                            let center = UIScreen.main.bounds.width / 2
                            let dist = abs(midX - center)
                            let scale = max(0.88, 1.0 - (dist / UIScreen.main.bounds.width) * 0.22)
                            return content.scaleEffect(scale)
                        }
                        .onTapGesture {
                            withAnimation(.amenSpring) { selectedIndex = idx }
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private func deckCard(_ item: FeaturedItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            cardArtwork(item)
            LinearGradient(
                colors: [.clear, Color.amenBlack.opacity(0.82)],
                startPoint: .center, endPoint: .bottom
            )
            Text(item.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Expanded overlay

    private func expandedOverlay(item: FeaturedItem, index: Int) -> some View {
        ZStack {
            // Scrim — tapping dismisses
            Color.amenBlack.opacity(0.68 - dragProgress * 0.55)
                .ignoresSafeArea()
                .onTapGesture { collapse() }

            VStack(spacing: 12) {
                // Drag handle
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: 40, height: 4)
                    .padding(.top, 8)
                    .opacity(1 - dragProgress)

                detail(item)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 16)
                    .matchedGeometryEffect(id: index, in: ns, isSource: selectedIndex != nil)
                    .offset(y: dragOffset.height)
                    .gesture(dragGesture)

                Spacer()
            }
        }
    }

    // MARK: - Drag gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                let shouldCollapse = abs(value.translation.height) > 120
                    || abs(value.predictedEndTranslation.height) > 300
                if shouldCollapse {
                    collapse()
                } else {
                    withAnimation(.amenSpring) { dragOffset = .zero }
                }
            }
    }

    private func collapse() {
        withAnimation(.amenSpring) {
            selectedIndex = nil
            dragOffset = .zero
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private func cardArtwork(_ item: FeaturedItem) -> some View {
        if let url = item.imageURL {
            CachedAsyncImage(url: url) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                item.accent.opacity(0.5)
            }
        } else {
            LinearGradient(
                colors: [item.accent.opacity(0.85), item.accent.opacity(0.3)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}
