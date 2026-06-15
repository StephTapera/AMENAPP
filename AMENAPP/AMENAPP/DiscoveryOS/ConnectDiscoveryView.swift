// ConnectDiscoveryView.swift
// AMEN Connect Discovery Engine — Wave 3, Lanes J + K + L
// Scroll-driven hero → glass pill morph (Lane J)
// Category pills with glass morph (Lane K)
// Server-ordered shelves with finite CalmCap bottom (Lane L)
// Flag-gated behind connectDiscoveryEnabled.

import SwiftUI

struct ConnectDiscoveryView: View {

    @State private var viewModel = ConnectDiscoveryViewModel()
    @State private var heroCollapsed = false
    @State private var showSearch = false
    @State private var showPreview: DiscoveryCard? = nil
    @State private var adaptiveTint: AdaptiveBackground = .neutral

    @Namespace private var heroNamespace
    @Namespace private var pillNamespace

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let heroHeight: CGFloat = 300

    var body: some View {
        ZStack(alignment: .top) {
            // Adaptive screen tint (subtle, not flashing)
            backgroundCanvas

            // Main scroll content
            GlassEffectContainer(spacing: 12) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Scroll offset tracker (iOS 17-compatible, preference key pattern)
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("connectScroll")).minY
                            )
                        }
                        .frame(height: 0)

                        // Hero spacer (maintains scroll position when hero collapses)
                        Color.clear
                            .frame(height: heroCollapsed ? 0 : heroHeight + 16)

                        // Pills row
                        pillsRow
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                        // Feed content
                        feedContent
                    }
                    .padding(.bottom, 100)
                }
                .coordinateSpace(name: "connectScroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                    let newCollapsed = -offset > heroHeight * 0.55
                    if newCollapsed != heroCollapsed {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.85)) {
                            heroCollapsed = newCollapsed
                        }
                    }
                    viewModel.checkSessionLimit()
                }
            }

            // Hero (overlays the top — positioned above scroll content)
            if !heroCollapsed, let feed = viewModel.currentFeed, let first = feed.hero.first {
                heroView(card: first.card, background: first.backgroundHint)
                    .frame(height: heroHeight)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 0.96))
                    ))
                    .glassEffectID("discovery-hero", in: heroNamespace)
            }

            // Floating compressed pill (hero collapsed state)
            if heroCollapsed, let feed = viewModel.currentFeed, let first = feed.hero.first {
                HStack {
                    DiscoveryFloatingPill(heroCard: first.card) {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38)) {
                            heroCollapsed = false
                        }
                    }
                    .glassEffectID("discovery-hero", in: heroNamespace)

                    Spacer()

                    // Search button
                    searchButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            } else {
                // Search button (always accessible when hero is expanded)
                HStack {
                    Spacer()
                    searchButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Connect")
        .navigationBarHidden(true)
        .task { await viewModel.loadFeed() }
        .sheet(isPresented: $showSearch) {
            DiscoverySearchView(viewModel: viewModel)
        }
        .sheet(item: $showPreview) { card in
            DiscoveryPreviewSheet(card: card)
        }
        .onChange(of: viewModel.currentFeed?.hero.first?.backgroundHint) { _, hint in
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.6)) {
                adaptiveTint = hint ?? .neutral
            }
        }
    }

    // MARK: - Background canvas

    private var backgroundCanvas: some View {
        let (r, g, b) = adaptiveTint.color
        return Color(red: r * 0.12, green: g * 0.10, blue: b * 0.18)
            .opacity(reduceTransparency ? 0 : 0.35)
            .ignoresSafeArea()
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.8), value: adaptiveTint)
    }

    // MARK: - Hero view

    private func heroView(card: DiscoveryCard, background: AdaptiveBackground) -> some View {
        DiscoveryGlassHeroSurface(backgroundHint: background) {
            Button { /* open detail */ } label: {
                VStack(alignment: .leading, spacing: 12) {
                    Spacer()

                    HStack(spacing: 8) {
                        Image(systemName: card.type.systemIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: card.type.accentHex))
                        Text(card.type.rawValue.capitalized.replacingOccurrences(of: "audio", with: "Audio "))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: card.type.accentHex))
                    }

                    Text(card.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let sub = card.subtitle {
                        Text(sub)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: card.reason.kind.icon)
                            .font(.system(size: 10))
                        Text(card.reason.detail)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive())
            .accessibilityLabel("\(card.title). \(card.subtitle ?? ""). \(card.reason.detail).")
            .accessibilityHint("Double tap to open")
        }
    }

    // MARK: - Pills row (Lane K)

    private var pillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(DiscoveryCategoryPill.allPills) { pill in
                        DiscoveryGlassPill(
                            label: pill.label,
                            icon: pill.icon,
                            isSelected: viewModel.selectedCategory == pill.id
                        ) {
                            viewModel.selectCategory(pill.id)
                        }
                        .glassEffectID(pill.id, in: pillNamespace)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
        .accessibilityLabel("Category filters")
    }

    // MARK: - Feed content (Lane L)

    @ViewBuilder
    private var feedContent: some View {
        switch viewModel.feedState {
        case .idle:
            EmptyView()

        case .loading:
            DiscoveryLoadingView()
                .padding(.top, 24)

        case .loaded(let feed):
            // CalmCap: render shelves in server order, up to maxShelves
            let shelves = Array(feed.shelves.prefix(feed.calmCap.maxShelves))
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                ForEach(shelves) { shelf in
                    shelfView(shelf, maxItems: feed.calmCap.maxItemsPerShelf)
                }
            }
            .padding(.top, 8)

            // CalmCap bottom — no "load more" forever
            if viewModel.calmCapReached {
                DiscoveryCaughtUpView()
            } else {
                // Finite bottom marker (CalmCap enforced — no infinite scroll)
                Color.clear.frame(height: 1)
                    .onAppear { viewModel.checkSessionLimit() }
            }

        case .empty:
            DiscoveryEmptyView()
                .padding(.top, 40)

        case .error(let msg):
            DiscoveryErrorView(message: msg) {
                Task { await viewModel.loadFeed() }
            }
            .padding(.top, 40)
        }
    }

    // MARK: - Shelf view

    private func shelfView(_ shelf: DiscoveryShelf, maxItems: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DiscoveryShelfHeader(shelf: shelf)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(shelf.items.prefix(maxItems)) { card in
                        DiscoveryCardView(
                            card: card,
                            onTap: { _ in /* navigate to detail */ },
                            onPreview: { card in showPreview = card }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
        .accessibilityLabel(shelf.title + " shelf")
    }

    // MARK: - Search button

    private var searchButton: some View {
        Button { showSearch = true } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .padding(10)
                .glassEffect(.regular.interactive())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search communities")
    }
}

// MARK: - Loading / empty / error states

private struct DiscoveryLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                skeletonShelf
            }
        }
        .padding(.horizontal, 16)
    }

    private var skeletonShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 140, height: 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.secondary.opacity(0.08))
                            .frame(width: 260, height: 140)
                    }
                }
            }
        }
    }
}

private struct DiscoveryEmptyView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "globe.americas")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("No communities yet")
                .font(.system(size: 17, weight: .semibold))
            Text("Check back soon — communities are being added.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No communities yet. Check back soon.")
    }
}

private struct DiscoveryErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("Couldn't load communities")
                .font(.system(size: 17, weight: .semibold))
            Button("Try Again", action: onRetry)
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive())
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
