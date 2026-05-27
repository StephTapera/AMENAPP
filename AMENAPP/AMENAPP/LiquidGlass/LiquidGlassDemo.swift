#if DEBUG
import SwiftUI

/// Live preview harness for the shared Liquid Glass interaction kit.
/// Keep this DEBUG-only so production builds do not ship sample content.
struct LiquidGlassDemo: View {
    @State private var menuOpen = false

    var body: some View {
        TabView {
            heroDemo
                .tabItem { Label("Hero", systemImage: "rectangle.stack") }
            menuDemo
                .tabItem { Label("Menu", systemImage: "ellipsis.circle") }
            barDemo
                .tabItem { Label("Bar", systemImage: "slider.horizontal.3") }
        }
    }

    private var heroDemo: some View {
        FeaturedHeroCarousel(
            featured: [
                FeaturedItem(
                    title: "Sermon of the Week",
                    badge: "NEW",
                    metadata: "ARISE - Teaching - 24 min",
                    rating: nil,
                    accent: .amenPurple
                ),
                FeaturedItem(
                    title: "Berean Deep Dive\nMatthew 5",
                    badge: "LIVE",
                    metadata: "Study - Exegesis",
                    rating: nil,
                    accent: .amenBlue
                ),
                FeaturedItem(
                    title: "Today's Verse",
                    badge: nil,
                    metadata: "Daily - Devotional",
                    rating: nil,
                    accent: .amenGold
                )
            ],
            rowTitle: "Continue in AMEN",
            rowItems: [
                CarouselItem(title: "Get Ready: Sunday", accent: .amenBlue),
                CarouselItem(title: "Church Notes", accent: .amenPurple),
                CarouselItem(title: "OUTPOUR Clips", accent: .amenGold),
                CarouselItem(title: "242 Hub", accent: .amenPurple)
            ]
        )
    }

    private var menuDemo: some View {
        ZStack {
            Color.amenBlack.ignoresSafeArea()
            Button("Open contextual actions") { menuOpen = true }
                .foregroundStyle(.white)
                .padding()
                .liquidGlass()

            ContextualActionMenu(
                isPresented: $menuOpen,
                items: [
                    .init(symbol: "sparkles", title: "Ask Berean") {},
                    .init(symbol: "square.and.arrow.up", title: "Share") {},
                    .init(symbol: "bookmark", title: "Save") {},
                    .init(symbol: "flag", title: "Report", role: .destructive) {}
                ],
                promptPlaceholder: "Ask Berean about this verse...",
                onSubmitPrompt: { _ in }
            ) {
                LinearGradient(
                    colors: [.amenPurple, .amenBlack],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay(
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.white.opacity(0.85))
                )
            }
        }
    }

    private var barDemo: some View {
        ZStack {
            LinearGradient(
                colors: [.amenBlack, .amenPurple.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                MorphingGlassBar(
                    collapsedTitle: "Select",
                    collapsedSymbol: "checkmark.circle",
                    actions: [
                        .init(symbol: "trash", title: "Delete", tint: .red) {},
                        .init(symbol: "folder", title: "Move", tint: .white) {},
                        .init(symbol: "square.and.arrow.up", title: "Share", tint: .amenBlue) {}
                    ],
                    onConfirm: {}
                )
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview { LiquidGlassDemo() }
#endif
