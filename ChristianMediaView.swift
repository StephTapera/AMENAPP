// ChristianMediaView.swift — Main Christian Media browsing experience

import SwiftUI

// MARK: - Scroll Offset Preference Key
struct MediaScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - ChristianMediaView
struct ChristianMediaView: View {
    @StateObject private var vm = ChristianMediaViewModel()
    @Namespace private var tabNamespace
    @Namespace private var filterNamespace

    @State private var scrollOffset: CGFloat = 0
    @State private var showBereanSheet = false
    @State private var bereanQuery = ""

    private let accentPurple = Color(red: 0.49, green: 0.23, blue: 0.93)

    // MARK: - Computed from scroll
    private var heroOpacity: Double {
        max(0, 1.0 - Double(scrollOffset) / 60.0)
    }

    private var heroScale: Double {
        max(0.85, 1.0 - Double(scrollOffset) / 400.0)
    }

    private var navTitleOpacity: Double {
        1.0 - heroOpacity
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // White background matching the rest of the app
                Color(.systemBackground).ignoresSafeArea()

                // MARK: Main Scroll Content
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        // Scroll offset tracker
                        Color.clear
                            .frame(height: 0)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: MediaScrollOffsetKey.self,
                                        value: geo.frame(in: .named("scroll")).minY
                                    )
                                }
                            )

                        // 1. Hero Title
                        heroSection

                        // 2. Tab Control
                        tabControl
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        // 3. Error Banner (if any)
                        if let error = vm.loadError {
                            errorBanner(message: error)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        // 4. Filter Pills
                        filterPills
                            .padding(.top, 10)

                        // 5. Cached content banner
                        if vm.loadError != nil && !vm.items.isEmpty {
                            cachedContentBanner
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                        }

                        // 6. Content Area
                        contentArea
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        // 7. Bottom padding for NowPlayingBar
                        Color.clear.frame(height: 100)
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(MediaScrollOffsetKey.self) { value in
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollOffset = max(0, -value)
                    }
                }

                // MARK: Now Playing Bar
                VStack(spacing: 0) {
                    Spacer()
                    if vm.currentItem != nil {
                        NowPlayingBar(vm: vm)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: vm.currentItem?.id)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Christian Media")
                        .font(.system(size: 17, weight: .semibold))
                        .opacity(navTitleOpacity)
                }
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showBereanSheet) {
            BereanAIAssistantView(initialQuery: bereanQuery)
        }
        .onAppear {
            Task { await vm.loadContent() }
        }
        .onChange(of: vm.selectedTab) { _, tab in
            if tab == .library {
                Task { await vm.loadLibrary() }
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 4) {
            Text("Christian Media")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)
            Text("Watch · Listen · Reflect")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .opacity(heroOpacity)
        .scaleEffect(heroScale)
        .animation(.easeOut(duration: 0.1), value: scrollOffset)
    }

    // MARK: - Custom Tab Control

    private var tabControl: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 44)

            // Tab labels
            HStack(spacing: 0) {
                ForEach(MediaTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            vm.selectedTab = tab
                        }
                    } label: {
                        ZStack {
                            // Active pill
                            if vm.selectedTab == tab {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                                    .matchedGeometryEffect(id: "tab", in: tabNamespace)
                                    .padding(4)
                            }

                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: vm.selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(vm.selectedTab == tab ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                }
            }
        }
        .frame(height: 44)
    }

    // MARK: - Filter Pills

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MediaFilterType.allCases) { filter in
                    filterPill(filter)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterPill(_ filter: MediaFilterType) -> some View {
        let isActive = vm.selectedFilter == filter

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                vm.selectedFilter = filter
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: filter.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(filter.label)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
            }
            .foregroundStyle(isActive ? .white : .primary.opacity(0.70))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isActive ? accentPurple : Color.primary.opacity(0.08))
            .clipShape(Capsule())
            .scaleEffect(isActive ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if vm.isLoading {
            // Skeleton placeholders
            LazyVStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { i in
                    skeletonCard
                }
            }
        } else if vm.displayItems.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 16) {
                ForEach(Array(vm.displayItems.enumerated()), id: \.element.id) { index, item in
                    MediaCard(
                        item: item,
                        index: index,
                        isCurrentlyPlaying: vm.currentItem?.id == item.id && vm.isPlaying,
                        onPlay: { vm.play(item) },
                        onBookmark: { Task { await vm.toggleBookmark(item) } },
                        onShare: {
                            dlog("ChristianMediaView: Share tapped for \(item.title)")
                        },
                        onBerean: item.scriptureRef != nil ? {
                            bereanQuery = "I'm watching: \(item.title) by \(item.author). Scripture reference: \(item.scriptureRef ?? ""). Give me context and commentary."
                            showBereanSheet = true
                        } : nil
                    )
                }
            }
        }
    }

    // MARK: - Skeleton Card

    private var skeletonCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 16)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 140, height: 12)
                Spacer()
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 80, height: 28)
            }
            .padding(.vertical, 10)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: vm.selectedFilter.icon)
                .font(.system(size: 52))
                .foregroundStyle(accentPurple.opacity(0.5))
            Text("No \(vm.selectedFilter.label) content yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Check back soon for new content")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 40)
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14))
            Text(message)
                .font(.system(size: 13))
                .lineLimit(2)
            Spacer()
            Button("Retry") {
                Task { await vm.loadContent() }
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(Color.red.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Cached Content Banner

    private var cachedContentBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11))
            Text("Showing cached content")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }
}
