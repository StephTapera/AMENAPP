// WisdomLibraryView.swift
// AMENAPP
//
// Wisdom Library — Premium Editorial Redesign.
// Design philosophy: Apple-native editorial feel, spiritually grounded, calm and intentional.
// Uses AMEN's adaptive color system (light/dark), OpenSans typography, and
// selective Liquid Glass blur — never excessive.
//
// Architecture:
//   WisdomLibraryView       — root container + scroll orchestration
//   WLHeroSection           — compressible hero with streak + featured card
//   WLFeaturedCarousel      — large horizontal cover shelf with focus scaling
//   WLCategoryBar           — sticky animated category chips
//   WLSectionRow            — horizontal shelf section (title + book strip)
//   WLBookCard              — cover card (multiple size modes)
//   WLEditorialCard         — wide editorial recommendation card
//   WLBookDetailView        — full detail sheet (in BookDetailView.swift)
//   Supporting helpers:     WLCoverImage, WLBookCoverPlaceholder,
//                           WLSkeletonModifier, WLGlassPanel, WLShimmerModifier

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Design Tokens

private enum WLToken {
    // Adaptive background system
    static let bg          = Color(.systemBackground)
    static let bgSecondary = Color(.secondarySystemBackground)
    static let bgTertiary  = Color(.tertiarySystemBackground)
    static let separator   = Color(.separator).opacity(0.3)

    // Text
    static let textPrimary   = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary  = Color(.tertiaryLabel)

    // Accent — warm amber for AMEN's spiritual warmth
    static let accent        = Color(red: 0.78, green: 0.50, blue: 0.18)
    static let accentSoft    = Color(red: 0.78, green: 0.50, blue: 0.18).opacity(0.12)

    // Hero gradient (adapts between modes)
    static func heroGradient(in colorScheme: ColorScheme) -> LinearGradient {
        colorScheme == .dark
        ? LinearGradient(
            colors: [Color(white: 0.07), Color(white: 0.04)],
            startPoint: .top, endPoint: .bottom)
        : LinearGradient(
            colors: [Color(white: 0.96), Color(white: 0.99)],
            startPoint: .top, endPoint: .bottom)
    }

    // Metrics
    static let hPad: CGFloat       = 20
    static let cardCorner: CGFloat = 16
    static let coverCorner: CGFloat = 10

    // Featured shelf card sizes
    static let featuredW: CGFloat  = 160
    static let featuredH: CGFloat  = 230

    // Shelf card sizes
    static let shelfW: CGFloat     = 110
    static let shelfH: CGFloat     = 158

    // Typography
    static let heroTitle    = Font.system(size: 32, weight: .bold, design: .default)
    static let heroSub      = Font.system(size: 14, weight: .regular)
    static let sectionTitle = Font.system(size: 19, weight: .bold)
    static let sectionSub   = Font.system(size: 12, weight: .regular)
    static let cardTitle    = Font.system(size: 13, weight: .semibold)
    static let cardAuthor   = Font.system(size: 11, weight: .regular)
    static let chipLabel    = Font.system(size: 13, weight: .medium)
    static let labelFont    = Font.system(size: 11, weight: .semibold)
}

// MARK: - Main View

struct WisdomLibraryView: View {
    @StateObject private var vm = BookDiscoveryViewModel()
    @State private var selectedBook: WLBook?
    @State private var showSearch     = false
    @State private var searchQuery    = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            WLToken.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // ── FULL-BLEED HERO ───────────────────────────────────────
                    WLHeroSection(
                        vm: vm,
                        showSearch: $showSearch,
                        onBack: { dismiss() },
                        onBook: { selectedBook = $0 }
                    )

                    // ── SEARCH BAR (slides in below hero) ────────────────────
                    if showSearch {
                        WLInlineSearchBar(
                            query: $searchQuery,
                            vm: vm,
                            onSelectBook: { selectedBook = $0 }
                        )
                        .padding(.horizontal, WLToken.hPad)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // ── CATEGORY BAR ─────────────────────────────────────────
                    WLCategoryBar(
                        selected: vm.selectedCategory,
                        onSelect: { vm.selectCategory($0) }
                    )
                    .padding(.top, showSearch ? 8 : 20)

                    // ── FEATURED CAROUSEL ────────────────────────────────────
                    WLFeaturedCarousel(
                        books: vm.heroBooks,
                        isLoading: vm.isLoadingHero,
                        savedIds: vm.savedBookIds,
                        onBook: { selectedBook = $0 },
                        onSave: { vm.toggleSave(book: $0) }
                    )
                    .padding(.top, 28)

                    // ── CURATED SECTIONS ─────────────────────────────────────
                    if vm.isLoadingShelves {
                        WLShelvesSkeletonView()
                            .padding(.top, 28)
                    } else if vm.shelves.isEmpty && vm.errorMessage != nil {
                        WLErrorRetryView(message: vm.errorMessage ?? "Could not load books.") {
                            vm.errorMessage = nil
                            Task { await vm.loadInitialData() }
                        }
                        .padding(.top, 40)
                    } else {
                        WLCuratedSections(
                            vm: vm,
                            onBook: { selectedBook = $0 }
                        )
                        .padding(.top, 28)
                    }

                    Spacer().frame(height: 60)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $selectedBook) { book in
            WLBookDetailView(book: book, vm: vm)
        }
        .onAppear {
            if vm.heroBooks.isEmpty && !vm.isLoadingHero {
                Task { await vm.loadInitialData() }
            }
        }
    }
}

// MARK: - (WLFloatingNavBar removed — nav is now embedded in WLHeroSection)

// MARK: - Inline Search Bar

private struct WLInlineSearchBar: View {
    @Binding var query: String
    let vm: BookDiscoveryViewModel
    let onSelectBook: (WLBook) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Input row
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WLToken.textSecondary)
                    .font(.system(size: 14))

                TextField("Books, authors, topics…", text: $query)
                    .focused($focused)
                    .font(.system(size: 15))
                    .foregroundStyle(WLToken.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onAppear { focused = true }
                    .onChange(of: query) { _, _ in
                        vm.searchQuery = query
                        vm.performSearch()
                    }

                if vm.isSearching {
                    ProgressView().scaleEffect(0.75)
                        .tint(WLToken.textSecondary)
                } else if !query.isEmpty {
                    Button { query = ""; vm.clearSearch() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(WLToken.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(WLToken.bgSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(WLToken.separator, lineWidth: 0.5))

            // Results
            if !vm.searchResults.isEmpty && !query.isEmpty {
                VStack(spacing: 0) {
                    ForEach(vm.searchResults.prefix(7)) { book in
                        Button {
                            WLBookAnalytics.trackDetailOpen(book: book, source: "search")
                            onSelectBook(book)
                        } label: {
                            HStack(spacing: 12) {
                                WLCoverImage(book: book, width: 36, height: 52, corner: 6)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(book.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(WLToken.textPrimary)
                                        .lineLimit(2)
                                    Text(book.authorDisplayString)
                                        .font(.system(size: 12))
                                        .foregroundStyle(WLToken.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(WLToken.textTertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if book.id != vm.searchResults.prefix(7).last?.id {
                            WLToken.separator.frame(height: 0.5).padding(.leading, 62)
                        }
                    }
                }
                .background(WLToken.bgSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(WLToken.separator, lineWidth: 0.5))
            }
        }
    }
}

// MARK: - Hero Section (full-bleed, GivingNonprofitsDetailView-style)

private struct WLHeroSection: View {
    let vm: BookDiscoveryViewModel
    @Binding var showSearch: Bool
    let onBack: () -> Void
    let onBook: (WLBook) -> Void

    @Environment(\.colorScheme) private var colorScheme

    // Hero gradient — warm amber-gold on light, deep slate on dark
    private var heroGradient: LinearGradient {
        colorScheme == .dark
        ? LinearGradient(
            colors: [Color(white: 0.10), Color(red: 0.12, green: 0.08, blue: 0.04)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        : LinearGradient(
            colors: [Color(red: 0.95, green: 0.85, blue: 0.65),
                     Color(red: 0.88, green: 0.70, blue: 0.40)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Contrasting text color for inside the hero
    private var heroTextPrimary: Color {
        colorScheme == .dark ? .white : Color(red: 0.18, green: 0.10, blue: 0.02)
    }
    private var heroTextSecondary: Color {
        colorScheme == .dark ? Color(white: 0.7) : Color(red: 0.35, green: 0.22, blue: 0.06)
    }
    private var heroPillBg: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color(red: 0.18, green: 0.10, blue: 0.02).opacity(0.12)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // ── Background gradient ───────────────────────────────────────────
            heroGradient
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .ignoresSafeArea(edges: .top)

            // ── Subtle texture overlay ────────────────────────────────────────
            LinearGradient(
                colors: [.clear, Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .ignoresSafeArea(edges: .top)

            // ── Bottom-left title block ───────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                // Scripture label above title
                Text("AMEN WISDOM LIBRARY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(heroTextSecondary)
                    .kerning(1.4)

                // Big serif title
                Text(vm.heroHeadline)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(heroTextPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .animation(.easeOut(duration: 0.22), value: vm.heroHeadline)

                // Subheadline
                Text(vm.heroSubheadline)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(heroTextSecondary)
                    .animation(.easeOut(duration: 0.2), value: vm.heroSubheadline)
                    .padding(.top, 2)

                // Streak pill (if applicable)
                if let streak = vm.streakLabel {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(streak)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(heroTextSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(heroPillBg, in: Capsule())
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, WLToken.hPad)
            .padding(.bottom, 22)

            // ── Top-left: Back button ─────────────────────────────────────────
            VStack {
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 15, weight: .regular))
                        }
                        .foregroundStyle(heroTextPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(heroPillBg, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // ── Top-right: Search button ──────────────────────────────
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            showSearch.toggle()
                            if !showSearch { vm.clearSearch() }
                        }
                    } label: {
                        Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(heroTextPrimary)
                            .frame(width: 36, height: 36)
                            .background(heroPillBg, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, WLToken.hPad)
                .padding(.top, 56)

                Spacer()
            }
            .frame(height: 280)
        }
        .frame(height: 280)
    }
}

// MARK: - (WLAvatarBadge and WLStreakPill consolidated into WLHeroSection)

// MARK: - Featured Carousel

private struct WLFeaturedCarousel: View {
    let books: [WLBook]
    let isLoading: Bool
    let savedIds: Set<String>
    let onBook: (WLBook) -> Void
    let onSave: (WLBook) -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section label
            WLSectionHeader(
                title: "Featured",
                subtitle: "Curated for your walk"
            )
            .padding(.horizontal, WLToken.hPad)

            // Horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    let displayBooks = isLoading
                        ? Array(repeating: WLBook.placeholder, count: 5)
                        : Array(books.prefix(10))

                    ForEach(Array(displayBooks.enumerated()), id: \.offset) { idx, book in
                        WLFeaturedCard(
                            book: book,
                            isLoading: isLoading,
                            isSaved: savedIds.contains(book.id),
                            onTap: {
                                guard !isLoading else { return }
                                WLBookAnalytics.trackDetailOpen(book: book, source: "featured_carousel")
                                onBook(book)
                            },
                            onSave: {
                                guard !isLoading else { return }
                                onSave(book)
                            }
                        )
                        // Subtle entrance stagger
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, WLToken.hPad)
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Featured Card

private struct WLFeaturedCard: View {
    let book: WLBook
    let isLoading: Bool
    let isSaved: Bool
    let onTap: () -> Void
    let onSave: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Cover
                ZStack(alignment: .topTrailing) {
                    if isLoading {
                        RoundedRectangle(cornerRadius: WLToken.coverCorner)
                            .fill(Color(.systemGray5))
                            .frame(width: WLToken.featuredW, height: WLToken.featuredH)
                            .wlShimmer()
                    } else {
                        WLCoverImage(
                            book: book,
                            width: WLToken.featuredW,
                            height: WLToken.featuredH,
                            corner: WLToken.coverCorner
                        )
                        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
                    }

                    // Save button (top-right corner of cover)
                    if !isLoading {
                        Button(action: onSave) {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isSaved ? WLToken.accent : .white)
                                .frame(width: 30, height: 30)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSaved)
                    }
                }

                // Metadata below cover
                if !isLoading {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(book.title)
                            .font(WLToken.cardTitle)
                            .foregroundStyle(WLToken.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(book.authorDisplayString)
                            .font(WLToken.cardAuthor)
                            .foregroundStyle(WLToken.textSecondary)
                            .lineLimit(1)

                        if let tag = book.curatedTags.first ?? book.primaryCategory {
                            Text(tag.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(WLToken.accent)
                                .kerning(0.6)
                                .padding(.top, 2)
                        }
                    }
                    .frame(width: WLToken.featuredW, alignment: .leading)
                    .padding(.top, 10)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(width: WLToken.featuredW * 0.8, height: 13)
                            .wlShimmer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(width: WLToken.featuredW * 0.55, height: 11)
                            .wlShimmer()
                    }
                    .padding(.top, 10)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(isLoading ? "Loading book" : "\(book.title) by \(book.authorDisplayString)")
        .accessibilityHint("Double tap to view details")
    }
}

// MARK: - Category Bar

private struct WLCategoryBar: View {
    let selected: WLBookCategory
    let onSelect: (WLBookCategory) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WLBookCategory.allCases) { cat in
                    WLCategoryChip(
                        category: cat,
                        isSelected: cat == selected,
                        onTap: { onSelect(cat) }
                    )
                }
            }
            .padding(.horizontal, WLToken.hPad)
            .padding(.vertical, 2)
        }
    }
}

private struct WLCategoryChip: View {
    let category: WLBookCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: category.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .transition(.scale.combined(with: .opacity))
                }
                Text(category.rawValue)
                    .font(WLToken.chipLabel)
            }
            .foregroundStyle(isSelected ? .white : WLToken.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? WLToken.accent : Color(.systemGray6))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? WLToken.accent : WLToken.separator,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isSelected)
        .accessibilityLabel("\(category.rawValue) category")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Curated Sections

private struct WLCuratedSections: View {
    let vm: BookDiscoveryViewModel
    let onBook: (WLBook) -> Void

    // Editorial intro card appears at top
    private var topThreeBooks: [WLBook] {
        Array(vm.heroBooks.prefix(3))
    }

    var body: some View {
        VStack(spacing: 36) {
            // Editorial wide card (first hero book)
            if let featured = vm.heroBooks.first {
                WLEditorialBanner(book: featured) {
                    WLBookAnalytics.trackDetailOpen(book: featured, source: "editorial_banner")
                    onBook(featured)
                }
                .padding(.horizontal, WLToken.hPad)
            }

            // Curated shelves from VM
            ForEach(Array(vm.shelves.enumerated()), id: \.element.id) { idx, shelf in
                WLSectionRow(
                    shelf: shelf,
                    savedIds: vm.savedBookIds,
                    onBook: { book in
                        WLBookAnalytics.trackDetailOpen(book: book, source: "shelf_\(shelf.id)")
                        onBook(book)
                    },
                    onSave: { vm.toggleSave(book: $0) }
                )

                // Alternate editorial card between shelves (every 2nd shelf)
                if idx % 2 == 1 && idx < vm.shelves.count - 1,
                   let promotedBook = vm.shelves[safe: idx + 1]?.books.first {
                    WLVerseCard(book: promotedBook) {
                        onBook(promotedBook)
                    }
                    .padding(.horizontal, WLToken.hPad)
                }
            }

            // Saved section (if any)
            if !vm.savedBookIds.isEmpty {
                WLSavedSection(
                    allShelves: vm.shelves,
                    savedIds: vm.savedBookIds,
                    onBook: onBook
                )
            }
        }
    }
}

// MARK: - Editorial Banner

/// Wide full-bleed editorial recommendation card
private struct WLEditorialBanner: View {
    let book: WLBook
    let onTap: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Cover as blurred background
                ZStack {
                    if let urlStr = book.thumbnailURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .clipped()
                                    .blur(radius: 28)
                                    .saturation(0.7)
                            } else {
                                book.coverColor.opacity(0.25)
                            }
                        }
                    } else {
                        book.coverColor.opacity(0.25)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .clipped()

                // Gradient overlay
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top, endPoint: .bottom
                )

                // Content
                HStack(alignment: .bottom, spacing: 14) {
                    // Cover thumbnail
                    WLCoverImage(book: book, width: 80, height: 115, corner: 8)
                        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
                        .padding(.bottom, 16)

                    VStack(alignment: .leading, spacing: 5) {
                        // "AMEN Recommends" label
                        Text("AMEN RECOMMENDS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(WLToken.accent)
                            .kerning(1.2)

                        Text(book.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(book.authorDisplayString)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)

                        if let reason = book.recommendationReason ?? book.shortDescription {
                            Text(reason)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(2)
                                .padding(.top, 2)
                        }

                        Text("Explore")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WLToken.accent)
                            .padding(.top, 4)
                    }
                    .padding(.bottom, 18)

                    Spacer()
                }
                .padding(.horizontal, 16)
            }
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: WLToken.cardCorner, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
        .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("Featured: \(book.title) by \(book.authorDisplayString). AMEN Recommends.")
    }
}

// MARK: - Verse Card (Interstitial Panel)

/// Between-section spiritual quote panel referencing a book
private struct WLVerseCard: View {
    let book: WLBook
    let onTap: () -> Void

    // Rotating scripture prompts — non-prescriptive, focuses on invitation
    private let prompts = [
        "\"Wisdom begins with the fear of the Lord.\" — Proverbs 9:10",
        "\"Study to show yourself approved.\" — 2 Timothy 2:15",
        "\"Your word is a lamp to my feet.\" — Psalm 119:105",
        "\"As iron sharpens iron, so one person sharpens another.\" — Proverbs 27:17"
    ]
    private var prompt: String {
        prompts[abs(book.id.hashValue) % prompts.count]
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Vertical accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(WLToken.accent)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 6) {
                    Text(prompt)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(WLToken.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text("Explore in")
                            .font(.system(size: 11))
                            .foregroundStyle(WLToken.textTertiary)
                        Text(book.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WLToken.accent)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(WLToken.textTertiary)
            }
            .padding(16)
            .background(WLToken.bgSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(WLToken.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scripture prompt. Tap to explore \(book.title)")
    }
}

// MARK: - Section Row (Curated Shelf)

private struct WLSectionRow: View {
    let shelf: WLBookShelf
    let savedIds: Set<String>
    let onBook: (WLBook) -> Void
    let onSave: (WLBook) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .center) {
                HStack(spacing: 7) {
                    if let icon = shelf.icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(shelf.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(shelf.title)
                            .font(WLToken.sectionTitle)
                            .foregroundStyle(WLToken.textPrimary)
                        if let sub = shelf.subtitle {
                            Text(sub)
                                .font(WLToken.sectionSub)
                                .foregroundStyle(WLToken.textSecondary)
                        }
                    }
                    if shelf.isPremium {
                        Text("PRO")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(WLToken.accent, in: Capsule())
                    }
                }
                Spacer()
                Text("\(shelf.books.count)")
                    .font(WLToken.sectionSub)
                    .foregroundStyle(WLToken.textTertiary)
            }
            .padding(.horizontal, WLToken.hPad)

            // Horizontal strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(shelf.books.prefix(12)) { book in
                        WLShelfCard(
                            book: book,
                            isSaved: savedIds.contains(book.id),
                            onTap: { onBook(book) },
                            onSave: { onSave(book) }
                        )
                    }
                }
                .padding(.horizontal, WLToken.hPad)
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Shelf Card (Small Cover)

private struct WLShelfCard: View {
    let book: WLBook
    let isSaved: Bool
    let onTap: () -> Void
    let onSave: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    WLCoverImage(book: book, width: WLToken.shelfW, height: WLToken.shelfH, corner: 8)
                        .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 3)

                    // Bookmark
                    Button(action: onSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSaved ? WLToken.accent : .white)
                            .frame(width: 26, height: 26)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSaved)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WLToken.textPrimary)
                        .lineLimit(2)
                        .frame(width: WLToken.shelfW, alignment: .leading)

                    Text(book.primaryAuthor)
                        .font(.system(size: 10))
                        .foregroundStyle(WLToken.textSecondary)
                        .lineLimit(1)
                        .frame(width: WLToken.shelfW, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed && !reduceMotion ? 0.95 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("\(book.title) by \(book.primaryAuthor)")
        .accessibilityHint("Double tap to view book details")
    }
}

// MARK: - Saved Section

private struct WLSavedSection: View {
    let allShelves: [WLBookShelf]
    let savedIds: Set<String>
    let onBook: (WLBook) -> Void

    private var savedBooks: [WLBook] {
        var seen = Set<String>()
        var result: [WLBook] = []
        for shelf in allShelves {
            for book in shelf.books where savedIds.contains(book.id) && seen.insert(book.id).inserted {
                result.append(book)
            }
        }
        return result
    }

    var body: some View {
        if !savedBooks.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                WLSectionHeader(title: "Saved for Later", subtitle: "\(savedBooks.count) books")
                    .padding(.horizontal, WLToken.hPad)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(savedBooks.prefix(8)) { book in
                            WLShelfCard(
                                book: book,
                                isSaved: true,
                                onTap: { onBook(book) },
                                onSave: {}
                            )
                        }
                    }
                    .padding(.horizontal, WLToken.hPad)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Section Header

private struct WLSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(WLToken.sectionTitle)
                .foregroundStyle(WLToken.textPrimary)
            Text(subtitle)
                .font(WLToken.sectionSub)
                .foregroundStyle(WLToken.textSecondary)
        }
    }
}

// MARK: - Shelves Skeleton

private struct WLShelvesSkeletonView: View {
    var body: some View {
        VStack(spacing: 36) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 14) {
                    // Section title skeleton
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                        .frame(width: 160, height: 18)
                        .wlShimmer()
                        .padding(.horizontal, WLToken.hPad)

                    // Book strip skeleton
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 8) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray5))
                                        .frame(width: WLToken.shelfW, height: WLToken.shelfH)
                                        .wlShimmer()
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.systemGray5))
                                        .frame(width: WLToken.shelfW * 0.8, height: 12)
                                        .wlShimmer()
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.systemGray5))
                                        .frame(width: WLToken.shelfW * 0.6, height: 10)
                                        .wlShimmer()
                                }
                            }
                        }
                        .padding(.horizontal, WLToken.hPad)
                    }
                }
            }
        }
    }
}

// MARK: - Cover Image

/// Reusable async cover image with graceful fallback
struct WLCoverImage: View {
    let book: WLBook
    let width: CGFloat
    let height: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let urlStr = book.thumbnailURL ?? book.highResThumbnailURL,
               let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    case .failure, .empty:
                        WLBookCoverPlaceholder(book: book)
                            .frame(width: width, height: height)
                    @unknown default:
                        WLBookCoverPlaceholder(book: book)
                            .frame(width: width, height: height)
                    }
                }
            } else {
                WLBookCoverPlaceholder(book: book)
                    .frame(width: width, height: height)
            }
        }
    }
}

// MARK: - Cover Placeholder

struct WLBookCoverPlaceholder: View {
    let book: WLBook

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [book.coverColor.opacity(0.55), book.coverColor.opacity(0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 4) {
                Text(book.title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 6)

                Text(book.primaryAuthor)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Shimmer Modifier (WL-scoped)

private struct WLShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.38), .clear],
                        startPoint: .init(x: phase, y: 0.5),
                        endPoint: .init(x: phase + 0.6, y: 0.5)
                    )
                    .onAppear {
                        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                            phase = 1.4
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .clipped()
    }
}

extension View {
    func wlShimmer() -> some View {
        modifier(WLShimmerModifier())
    }
}

// MARK: - Error Retry View

private struct WLErrorRetryView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(WLToken.textTertiary)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(WLToken.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: onRetry) {
                Text("Try Again")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(WLToken.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Safe Array Index

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Analytics stub (defined in AffiliateLinkBuilder.swift)
// WLBookAnalytics used above references the enum defined in AffiliateLinkBuilder.swift

// MARK: - Preview

#if DEBUG
private extension WLBook {
    static func make(_ title: String, author: String, color: Color = .indigo) -> WLBook {
        WLBook(
            id: UUID().uuidString, title: title, subtitle: nil,
            authors: [author], description: "A profound work for your faith journey.",
            categories: ["Christian Living"], isbn13: nil, isbn10: nil,
            publishedDate: "2024", publisher: "Crossway", pageCount: 256,
            language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
            previewLink: nil, averageRating: 4.8, ratingsCount: 1240,
            isFeatured: true,
            recommendationReason: "Endorsed by AMEN community leaders.",
            curatedTags: ["Discipleship", "Prayer"]
        )
    }
}

#Preview {
    WisdomLibraryView()
}
#endif
