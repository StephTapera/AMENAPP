// WisdomLibraryHeroBanner.swift
// AMENAPP
//
// Premium hero banner for the Wisdom Library entry in ResourcesView.
//
// Design interpretation of the reference:
//   Reference:  three photo cards fanned in an arc above a frosted glass
//               tile, bold centered title, small pill year badge.
//   AMEN:       Three readable book-spine cards layered in a relaxed arc —
//               left card leans back, center card stands tall, right card
//               leans forward — each representing a real curated category
//               (Theology · Prayer · Discipleship).
//               A soft matte-frosted foreground card overlaps the lower
//               portion of the books and carries the section indicator + arrow.
//               Below: large editorial "Wisdom Library" title, "Curated Reads"
//               badge pill.
//               The overall surface is warm parchment/cream — calm, scholarly,
//               spiritually intentional.
//
// Architecture:
//   WisdomLibraryHeroBanner   — root view, manages appear + press state
//   WLBannerBookStack         — three fanned book-spine renders + optional
//                               AsyncImage covers (dynamic book data ready)
//   WLBannerBookCard          — single book spine / cover card
//   WLFrostedTile             — matte frosted foreground card with arrow
//   WLBannerBadge             — small pill badge
//   WLBannerPressStyle        — ButtonStyle that feeds isPressed via env

import SwiftUI

// MARK: - Design Tokens

private enum WLBannerTokens {
    // Surface palette — warm cream/parchment
    static let surfaceTop    = Color(red: 0.965, green: 0.955, blue: 0.940)  // warm cream
    static let surfaceBot    = Color(red: 0.945, green: 0.935, blue: 0.918)  // slightly deeper parchment
    static let strokeTop     = Color.white.opacity(0.75)
    static let strokeBot     = Color(red: 0.80, green: 0.77, blue: 0.73).opacity(0.45)

    // Frosted tile surface
    static let frostFill     = Color.white.opacity(0.68)
    static let frostStroke   = Color.white.opacity(0.85)

    // Typography ink
    static let titleInk      = Color(red: 0.12, green: 0.10, blue: 0.09)    // rich warm black
    static let subtitleInk   = Color(red: 0.40, green: 0.37, blue: 0.34)    // warm medium gray
    static let badgeInk      = Color(red: 0.38, green: 0.34, blue: 0.30)
    static let badgeStroke   = Color(red: 0.72, green: 0.68, blue: 0.62).opacity(0.55)

    // Arrow button disk
    static let arrowDisk     = Color(red: 0.13, green: 0.11, blue: 0.10)    // near-black
    static let arrowIcon     = Color.white

    // Geometry
    static let bannerCorner: CGFloat  = 22
    static let bannerHeight: CGFloat  = 160   // consistent with other section banners
    static let frostedCorner: CGFloat = 16
    static let bookW: CGFloat         = 40
    static let bookH: CGFloat         = 60
    static let bookCorner: CGFloat    = 6

    // Typography
    static let titleFont   = Font.system(size: 20, weight: .bold, design: .default)
    static let badgeFont   = Font.system(size: 10, weight: .medium, design: .default)
    static let sectionFont = Font.system(size: 9, weight: .semibold, design: .default)
}

// MARK: - Environment Key for press state

private struct WLBannerPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var wlBannerIsPressed: Bool {
        get { self[WLBannerPressedKey.self] }
        set { self[WLBannerPressedKey.self] = newValue }
    }
}

// MARK: - WLBannerPressStyle

/// ButtonStyle that injects press state into the banner via environment.
/// Allows NavigationLink to remain fully tappable — no gesture interception.
struct WLBannerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.wlBannerIsPressed, configuration.isPressed)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - Curated Book Data (static, ready for live data injection)

/// Represents a single curated book in the banner.
/// `coverURL` accepts a real thumbnail URL; falls back to `WLBannerBookCard`'s
/// spine design when nil or when the image fails to load.
struct WLBannerBookData {
    let title: String
    let author: String
    let category: String
    /// SwiftUI cover background (spine color when no image is available)
    let spineGradient: LinearGradient
    /// Optional real cover thumbnail — wire BookDiscoveryViewModel.heroBooks here
    var coverURL: URL?

    /// Three always-present curated fallback books used when real data is unavailable.
    static let curated: [WLBannerBookData] = [
        WLBannerBookData(
            title: "Knowing God",
            author: "J.I. Packer",
            category: "Theology",
            spineGradient: LinearGradient(
                stops: [
                    .init(color: Color(red: 0.22, green: 0.28, blue: 0.42), location: 0),
                    .init(color: Color(red: 0.16, green: 0.20, blue: 0.34), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        ),
        WLBannerBookData(
            title: "The Cost of Discipleship",
            author: "Dietrich Bonhoeffer",
            category: "Discipleship",
            spineGradient: LinearGradient(
                stops: [
                    .init(color: Color(red: 0.44, green: 0.32, blue: 0.20), location: 0),
                    .init(color: Color(red: 0.34, green: 0.24, blue: 0.14), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        ),
        WLBannerBookData(
            title: "With Christ in the School of Prayer",
            author: "Andrew Murray",
            category: "Prayer",
            spineGradient: LinearGradient(
                stops: [
                    .init(color: Color(red: 0.28, green: 0.36, blue: 0.30), location: 0),
                    .init(color: Color(red: 0.20, green: 0.28, blue: 0.22), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    ]
}

// MARK: - WisdomLibraryHeroBanner

/// Full-width hero banner for the Wisdom Library entry in ResourcesView.
/// Drop-in replacement for the current ResourceFolderCard call site.
///
/// To wire real book covers: pass `books` from `BookDiscoveryViewModel.heroBooks`.
/// The banner accepts up to three books; falls back to `WLBannerBookData.curated`
/// for any missing slots.
struct WisdomLibraryHeroBanner: View {

    /// Optional live book data (first 3 will be used if provided).
    /// Pass `vm.heroBooks` from `BookDiscoveryViewModel` to show real covers.
    var books: [WLBook]? = nil

    @Environment(\.wlBannerIsPressed) private var isPressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    // Compute display books: merge live data into curated slots
    private var displayBooks: [WLBannerBookData] {
        var slots = WLBannerBookData.curated         // 3 curated fallbacks
        guard let live = books else { return slots }
        for (i, book) in live.prefix(3).enumerated() {
            if let urlStr = book.thumbnailURL, let url = URL(string: urlStr) {
                slots[i] = WLBannerBookData(
                    title: book.title,
                    author: book.primaryAuthor,
                    category: book.primaryCategory ?? slots[i].category,
                    spineGradient: slots[i].spineGradient,
                    coverURL: url
                )
            }
        }
        return slots
    }

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── Layer 0: warm parchment surface ──────────────────────────────
            bannerSurface

            // ── Layer 1: fanned book stack (upper area) ───────────────────────
            WLBannerBookStack(books: displayBooks, appeared: appeared)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 48)   // lifts books above the frosted tile

            // ── Layer 2: frosted tile (lower overlap) ─────────────────────────
            WLFrostedTile(isPressed: isPressed)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

        }
        .frame(maxWidth: .infinity)
        .frame(height: WLBannerTokens.bannerHeight)
        // ── Layer 3: title + badge sitting below the card edge ────────────────
        // Actually we want title INSIDE the banner so it taps as one unit.
        // We compose title inside bannerSurface via the ZStack ordering below.
        .overlay(alignment: .bottom) {
            // Title + badge region at the bottom of the banner surface
            VStack(spacing: 6) {
                Text("Wisdom Library")
                    .font(WLBannerTokens.titleFont)
                    .foregroundStyle(WLBannerTokens.titleInk)
                    .minimumScaleFactor(0.78)
                    .lineLimit(1)

                WLBannerBadge(label: "Curated Reads")
            }
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        // Ambient shadow
        .shadow(
            color: Color(red: 0.55, green: 0.45, blue: 0.30).opacity(isPressed ? 0.08 : 0.18),
            radius: isPressed ? 6 : 20, x: 0, y: isPressed ? 3 : 10
        )
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        // Press: compress slightly
        .scaleEffect(isPressed ? 0.977 : 1.0)
        .offset(y: isPressed ? 1 : 0)
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(.spring(response: 0.70, dampingFraction: 0.80).delay(0.10)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wisdom Library. Curated Christian books. Double tap to browse.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Banner surface

    private var bannerSurface: some View {
        RoundedRectangle(cornerRadius: WLBannerTokens.bannerCorner, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: WLBannerTokens.surfaceTop, location: 0),
                        .init(color: WLBannerTokens.surfaceBot, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // Hairline top highlight
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: WLBannerTokens.bannerCorner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.60), .clear],
                            startPoint: .top,
                            endPoint: .init(x: 0.5, y: 0.15)
                        )
                    )
            }
            // Refined stroke
            .overlay(
                RoundedRectangle(cornerRadius: WLBannerTokens.bannerCorner, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [WLBannerTokens.strokeTop, WLBannerTokens.strokeBot],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
    }
}

// MARK: - WLBannerBookStack

/// Three book cover cards fanned in a relaxed arc — left leans back,
/// center stands upright, right leans forward.
/// Mirrors the reference's "three items arc above the frosted tile" composition.
struct WLBannerBookStack: View {
    let books: [WLBannerBookData]
    let appeared: Bool

    // Fan parameters: (rotation °, x offset, y offset when appeared, delay)
    private let fanConfig: [(rotation: Double, xOffset: CGFloat, yOffset: CGFloat, delay: Double)] = [
        (-14,  -66, -8,   0.00),   // left — leans back, slightly lower
        (  0,    0, -18,  0.07),   // center — upright, tallest
        ( 13,   64, -6,   0.14)    // right — leans forward
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(Array(books.prefix(3).enumerated()), id: \.offset) { i, book in
                let cfg = fanConfig[i]
                WLBannerBookCard(book: book)
                    .rotationEffect(.degrees(cfg.rotation))
                    .offset(
                        x: cfg.xOffset,
                        y: appeared ? cfg.yOffset : 24
                    )
                    .opacity(appeared ? 1.0 : 0.0)
                    .animation(
                        .spring(response: 0.64, dampingFraction: 0.78).delay(cfg.delay),
                        value: appeared
                    )
                    // z-index: center on top, flanks behind
                    .zIndex(i == 1 ? 2 : 1)
            }
        }
        .frame(height: WLBannerTokens.bookH + 24)
        .allowsHitTesting(false)
    }
}

// MARK: - WLBannerBookCard

/// A single book displayed in the banner stack.
/// When `coverURL` is present, shows `AsyncImage` as the cover face.
/// When nil or loading, falls back to an elegant spine render:
///   - colored gradient spine
///   - white title text (truncated to 2 lines)
///   - thin author line
///   - small category chip at foot
struct WLBannerBookCard: View {
    let book: WLBannerBookData

    var body: some View {
        ZStack(alignment: .bottomLeading) {

            if let url = book.coverURL {
                // ── Real cover image path ─────────────────────────────────────
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: WLBannerTokens.bookW, height: WLBannerTokens.bookH)
                            .clipped()
                    case .failure, .empty:
                        spineContent   // graceful fallback
                    @unknown default:
                        spineContent
                    }
                }
                .frame(width: WLBannerTokens.bookW, height: WLBannerTokens.bookH)
                .clipShape(RoundedRectangle(cornerRadius: WLBannerTokens.bookCorner, style: .continuous))

            } else {
                // ── Curated spine fallback ────────────────────────────────────
                spineContent
            }

            // Shared stroke over any content
            RoundedRectangle(cornerRadius: WLBannerTokens.bookCorner, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.75)
                .frame(width: WLBannerTokens.bookW, height: WLBannerTokens.bookH)
        }
        .frame(width: WLBannerTokens.bookW, height: WLBannerTokens.bookH)
        // Elevated drop shadow — each book has its own shadow for depth
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
    }

    // MARK: Spine render (no cover available)

    @ViewBuilder
    private var spineContent: some View {
        RoundedRectangle(cornerRadius: WLBannerTokens.bookCorner, style: .continuous)
            .fill(book.spineGradient)
            // Top-edge inner sheen
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: WLBannerTokens.bookCorner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.20), .clear],
                            startPoint: .top,
                            endPoint: .init(x: 0.5, y: 0.30)
                        )
                    )
            }
            .overlay(alignment: .topLeading) {
                // Book title lines — actual text, small
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(book.author)
                        .font(.system(size: 6.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.top, 10)
                .padding(.horizontal, 7)
            }
            .overlay(alignment: .bottomLeading) {
                // Category chip at spine foot
                Text(book.category.uppercased())
                    .font(.system(size: 5.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .tracking(0.5)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.12))
                    )
                    .padding(6)
            }
            .frame(width: WLBannerTokens.bookW, height: WLBannerTokens.bookH)
    }
}

// MARK: - WLFrostedTile

/// Matte frosted glass card overlapping the lower portion of the book stack.
/// Contains a section descriptor on the left and an arrow button on the right.
/// The frosted surface creates visual depth — it partially obscures the lower
/// book edges, suggesting the books are "behind" a glass library case.
struct WLFrostedTile: View {
    let isPressed: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Left: section descriptor
            VStack(alignment: .leading, spacing: 3) {
                Text("FEATURED COLLECTION")
                    .font(WLBannerTokens.sectionFont)
                    .foregroundStyle(WLBannerTokens.subtitleInk.opacity(0.65))
                    .tracking(0.6)
                Text("Books for every season of faith")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(WLBannerTokens.subtitleInk)
                    .lineLimit(1)
            }
            .padding(.leading, 16)

            Spacer(minLength: 8)

            // Right: arrow disk
            ZStack {
                Circle()
                    .fill(WLBannerTokens.arrowDisk)
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.20), radius: 6, x: 0, y: 3)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WLBannerTokens.arrowIcon)
            }
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.70), value: isPressed)
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background {
            // Matte frosted glass surface
            RoundedRectangle(cornerRadius: WLBannerTokens.frostedCorner, style: .continuous)
                .fill(WLBannerTokens.frostFill)
                // Subtle blur material layered under fill
                .background(
                    RoundedRectangle(cornerRadius: WLBannerTokens.frostedCorner, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: WLBannerTokens.frostedCorner, style: .continuous)
                        .stroke(WLBannerTokens.frostStroke, lineWidth: 1.0)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: WLBannerTokens.frostedCorner, style: .continuous))
    }
}

// MARK: - WLBannerBadge

/// Small pill badge — "Curated Reads" label beneath the title.
struct WLBannerBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(WLBannerTokens.badgeFont)
            .foregroundStyle(WLBannerTokens.badgeInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(red: 0.88, green: 0.84, blue: 0.78).opacity(0.65))
                    .overlay(
                        Capsule()
                            .stroke(WLBannerTokens.badgeStroke, lineWidth: 0.75)
                    )
            )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(red: 0.96, green: 0.95, blue: 0.94)
            .ignoresSafeArea()
        VStack(spacing: 24) {
            // Banner with curated fallback books (no live data)
            NavigationLink(destination: EmptyView()) {
                WisdomLibraryHeroBanner()
            }
            .buttonStyle(WLBannerPressStyle())
            .padding(.horizontal, 20)
        }
    }
}
