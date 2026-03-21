// AMENResourcesHubView.swift
// AMENAPP
//
// Cinematic stacking-card Christian Media screen.
// Dark immersive design with scrolling card stack, mode switcher,
// filter chips, now-playing chip, and floating glass dock.
// Preserves AMENResourcesHubViewModel data layer unchanged.

import SwiftUI
import Observation

// MARK: - View Model (unchanged data layer)

@Observable
@MainActor
final class AMENResourcesHubViewModel {
    var featuredSermons: [AMENSermon] = []
    var featuredPodcasts: [AMENPodcastEpisode] = []
    var selectedCategory: AMENResourceCategory = .all
    var searchText: String = ""
    var isLoading = false

    private let service = AMENMediaService.shared

    var visibleSermons: [AMENSermon] {
        let base = featuredSermons.isEmpty ? AMENSermon.curated : featuredSermons
        if searchText.isEmpty { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.speaker.localizedCaseInsensitiveContains(searchText) ||
            $0.church.localizedCaseInsensitiveContains(searchText)
        }
    }

    var visiblePodcasts: [AMENPodcastEpisode] {
        let base = featuredPodcasts.isEmpty ? AMENPodcastEpisode.curated : featuredPodcasts
        if searchText.isEmpty { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.showName.localizedCaseInsensitiveContains(searchText)
        }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        featuredSermons = await service.fetchFeaturedSermons()
        guard !Task.isCancelled else { return }
        featuredPodcasts = await service.fetchFeaturedPodcasts()
    }
}

// MARK: - Media Mode

private enum MediaMode: String, CaseIterable {
    case forYou   = "For You"
    case discover = "Discover"
    case library  = "Library"
}

// MARK: - Dock Tab

private enum DockTab: String, CaseIterable {
    case browse  = "Browse"
    case search  = "Search"
    case saved   = "Saved"
    case playing = "Playing"

    var icon: String {
        switch self {
        case .browse:  return "square.grid.2x2"
        case .search:  return "magnifyingglass"
        case .saved:   return "bookmark"
        case .playing: return "waveform"
        }
    }
}

// MARK: - Unified Media Item (for card stack)

private struct MediaCardItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String        // speaker / host / artist
    let sourceLabel: String     // church / show / album
    let category: AMENResourceCategory
    let thumbnailURL: String?
    let accentColors: [Color]
    let durationSeconds: Int?
    let scriptureRef: String?
    let entry: AMENMediaEntry

    static func from(_ sermon: AMENSermon) -> MediaCardItem {
        MediaCardItem(
            id: sermon.id,
            title: sermon.title,
            subtitle: sermon.speaker,
            sourceLabel: sermon.church,
            category: .sermons,
            thumbnailURL: sermon.thumbnailURL,
            accentColors: [Color(red: 0.52, green: 0.18, blue: 0.80), Color(red: 0.30, green: 0.10, blue: 0.55)],
            durationSeconds: sermon.durationSeconds,
            scriptureRef: sermon.scriptureReference,
            entry: .sermon(sermon)
        )
    }

    static func from(_ episode: AMENPodcastEpisode) -> MediaCardItem {
        MediaCardItem(
            id: episode.id,
            title: episode.title,
            subtitle: episode.host,
            sourceLabel: episode.showName,
            category: .podcasts,
            thumbnailURL: episode.thumbnailURL,
            accentColors: [Color(red: 0.18, green: 0.48, blue: 0.80), Color(red: 0.10, green: 0.28, blue: 0.55)],
            durationSeconds: episode.durationSeconds,
            scriptureRef: nil,
            entry: .podcast(episode)
        )
    }

    static func from(_ track: AMENWorshipTrack) -> MediaCardItem {
        MediaCardItem(
            id: track.id,
            title: track.title,
            subtitle: track.artist,
            sourceLabel: track.album ?? track.artist,
            category: .worship,
            thumbnailURL: track.thumbnailURL,
            accentColors: [Color(red: 0.15, green: 0.54, blue: 0.44), Color(red: 0.08, green: 0.30, blue: 0.24)],
            durationSeconds: track.durationSeconds,
            scriptureRef: track.scriptureReference,
            entry: .worship(track)
        )
    }
}

// MARK: - Scroll Offset Preference Key

private struct ResourcesHubScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Hub View

struct AMENResourcesHubView: View {
    @State private var vm = AMENResourcesHubViewModel()
    @State private var selectedEntry: AMENMediaEntry?

    // Cinematic state
    @State private var selectedMode: MediaMode = .forYou
    @State private var selectedDock: DockTab = .browse
    @State private var searchText = ""
    @State private var isSearchActive = false
    @FocusState private var searchFocused: Bool
    @State private var savedIDs: Set<String> = []
    @State private var nowPlayingItem: MediaCardItem?
    @State private var scrollOffset: CGFloat = 0

    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed item list

    private var allItems: [MediaCardItem] {
        var items: [MediaCardItem] = []
        switch selectedMode {
        case .forYou:
            // Interleave: sermon, podcast, sermon, worship, sermon…
            let sermons = vm.visibleSermons.map { MediaCardItem.from($0) }
            let podcasts = vm.visiblePodcasts.map { MediaCardItem.from($0) }
            let worship  = AMENWorshipTrack.curated.map { MediaCardItem.from($0) }
            let maxCount = max(sermons.count, max(podcasts.count, worship.count))
            for i in 0..<maxCount {
                if i < sermons.count  { items.append(sermons[i]) }
                if i < podcasts.count { items.append(podcasts[i]) }
                if i < worship.count  { items.append(worship[i]) }
            }
        case .discover:
            items = vm.visibleSermons.map { MediaCardItem.from($0) }
                  + AMENWorshipTrack.curated.map { MediaCardItem.from($0) }
        case .library:
            items = savedIDs.isEmpty ? [] :
                (vm.visibleSermons.map { MediaCardItem.from($0) }
               + vm.visiblePodcasts.map { MediaCardItem.from($0) }
               + AMENWorshipTrack.curated.map { MediaCardItem.from($0) })
               .filter { savedIDs.contains($0.id) }
        }
        return filterItems(items)
    }

    private func filterItems(_ items: [MediaCardItem]) -> [MediaCardItem] {
        var result = items
        if vm.selectedCategory != .all {
            result = result.filter { $0.category == vm.selectedCategory }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.subtitle.localizedCaseInsensitiveContains(searchText) ||
                $0.sourceLabel.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Dark background
            Color(red: 0.047, green: 0.047, blue: 0.055)
                .ignoresSafeArea()

            // Dot-grid texture overlay
            dotGridTexture
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom nav bar
                navBar

                // Mode switcher
                modeSwitcher
                    .padding(.top, 4)

                // Hero label
                heroLabel
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                // Filter chips
                filterChips
                    .padding(.top, 14)

                // Search bar (expands from dock)
                if isSearchActive {
                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Card stack
                if vm.isLoading && allItems.isEmpty {
                    loadingStack
                        .padding(.top, 24)
                } else if allItems.isEmpty {
                    emptyState
                        .padding(.top, 40)
                } else {
                    cardStack
                        .padding(.top, 20)
                }

                Spacer(minLength: 0)
            }

            // Floating dock
            floatingDock
                .padding(.bottom, 24)
        }
        .navigationBarHidden(true)
        .task { await vm.load() }
        .navigationDestination(item: $selectedEntry) { entry in
            AMENResourceDetailView(entry: entry)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSearchActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selectedMode)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: vm.selectedCategory)
    }

    // MARK: - Dot Grid Texture

    private var dotGridTexture: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            let dotSize: CGFloat = 1.5
            var x: CGFloat = 0
            while x < size.width {
                var y: CGFloat = 0
                while y < size.height {
                    let rect = CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.04)))
                    y += spacing
                }
                x += spacing
            }
        }
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.08), in: Circle())
            }

            Spacer()

            Text("Christian Media")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            // Now-playing chip (visible when something is playing)
            if let playing = nowPlayingItem {
                nowPlayingChip(playing)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func nowPlayingChip(_ item: MediaCardItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .bold))
                .symbolEffect(.variableColor.iterative, isActive: true)
            Text(item.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: item.accentColors,
                    startPoint: .leading, endPoint: .trailing
                )
            )
        )
        .frame(maxWidth: 120)
    }

    // MARK: - Mode Switcher

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(MediaMode.allCases, id: \.self) { mode in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedMode = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 14, weight: selectedMode == mode ? .semibold : .regular))
                        .foregroundStyle(selectedMode == mode ? .white : .white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if selectedMode == mode {
                                    Capsule()
                                        .fill(.white.opacity(0.12))
                                        .matchedGeometryEffect(id: "modeTab", in: modeNamespace)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.white.opacity(0.06))
        )
        .padding(.horizontal, 20)
    }

    @Namespace private var modeNamespace

    // MARK: - Hero Label

    private var heroLabel: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(modeHeroText)
                .font(.system(size: 52, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())

            Spacer()

            Text("\(allItems.count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.bottom, 4)
        }
    }

    private var modeHeroText: String {
        switch selectedMode {
        case .forYou:   return "For You"
        case .discover: return "Discover"
        case .library:  return "Library"
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AMENResourceCategory.allCases.filter { $0 != .series }, id: \.self) { cat in
                    filterChip(cat)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func filterChip(_ cat: AMENResourceCategory) -> some View {
        let isSelected = vm.selectedCategory == cat
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                vm.selectedCategory = cat
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: cat.sfSymbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(cat.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    isSelected
                        ? LinearGradient(
                            colors: [Color(red: 0.52, green: 0.18, blue: 0.80), Color(red: 0.35, green: 0.10, blue: 0.60)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                          )
                        : LinearGradient(
                            colors: [.white.opacity(0.09), .white.opacity(0.09)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                          )
                )
            )
            .overlay(
                Capsule().stroke(.white.opacity(isSelected ? 0 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))

            TextField("Search media…", text: $searchText)
                .focused($searchFocused)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(.white)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .onChange(of: searchText) { _, new in vm.searchText = new }
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // Spacing before first card so hero label has room
                Color.clear.frame(height: 4)

                ForEach(Array(allItems.enumerated()), id: \.element.id) { index, item in
                    StackingMediaCard(
                        item: item,
                        index: index,
                        isSaved: savedIDs.contains(item.id),
                        isNowPlaying: nowPlayingItem?.id == item.id,
                        onTap: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            selectedEntry = item.entry
                        },
                        onPlay: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                nowPlayingItem = nowPlayingItem?.id == item.id ? nil : item
                            }
                        },
                        onSave: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                if savedIDs.contains(item.id) {
                                    savedIDs.remove(item.id)
                                } else {
                                    savedIDs.insert(item.id)
                                }
                            }
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }

                // Bottom padding so last card clears the dock
                Color.clear.frame(height: 100)
            }
        }
    }

    // MARK: - Loading Stack

    private var loadingStack: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white.opacity(0.06))
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
                    .shimmerDark()
                    .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: selectedMode == .library ? "bookmark.slash" : "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.2))

            Text(selectedMode == .library ? "Nothing saved yet" : "No results")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))

            if selectedMode == .library {
                Text("Tap the bookmark icon on any card to save it here.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Floating Dock

    private var floatingDock: some View {
        HStack(spacing: 0) {
            ForEach(DockTab.allCases, id: \.self) { tab in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if tab == .search {
                        withAnimation { isSearchActive.toggle() }
                        if isSearchActive { searchFocused = true }
                        else { searchFocused = false; searchText = ""; vm.searchText = "" }
                    } else {
                        if isSearchActive {
                            withAnimation { isSearchActive = false }
                            searchFocused = false
                            searchText = ""
                            vm.searchText = ""
                        }
                        selectedDock = tab
                        if tab == .saved {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                selectedMode = .library
                            }
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab == .playing && nowPlayingItem != nil ? "waveform" : tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .symbolEffect(.variableColor.iterative,
                                          options: .repeating,
                                          isActive: tab == .playing && nowPlayingItem != nil)
                            .foregroundStyle(dockTabIsActive(tab) ? .white : .white.opacity(0.35))
                            .frame(height: 22)

                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: dockTabIsActive(tab) ? .semibold : .regular))
                            .foregroundStyle(dockTabIsActive(tab) ? .white : .white.opacity(0.3))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Group {
                            if dockTabIsActive(tab) {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.white.opacity(0.10))
                                    .matchedGeometryEffect(id: "dockActive", in: dockNamespace)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        )
        .padding(.horizontal, 24)
    }

    @Namespace private var dockNamespace

    private func dockTabIsActive(_ tab: DockTab) -> Bool {
        if tab == .search { return isSearchActive }
        if tab == .playing { return nowPlayingItem != nil }
        return selectedDock == tab && !isSearchActive
    }
}

// MARK: - Stacking Media Card

private struct StackingMediaCard: View {
    let item: MediaCardItem
    let index: Int
    let isSaved: Bool
    let isNowPlaying: Bool
    let onTap: () -> Void
    let onPlay: () -> Void
    let onSave: () -> Void

    @State private var cardScale: CGFloat = 1.0
    @State private var isPressed = false

    private var categoryLabel: String {
        switch item.category {
        case .sermons:  return "SERMON"
        case .podcasts: return "PODCAST"
        case .worship:  return "WORSHIP"
        default:        return item.category.rawValue.uppercased()
        }
    }

    private var durationLabel: String? {
        guard let secs = item.durationSeconds, secs > 0 else { return nil }
        let m = secs / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) min"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background: gradient + thumbnail
            cardBackground

            // Content overlay
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                // Category + duration row
                HStack(spacing: 8) {
                    Text(categoryLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.12)))

                    if let dur = durationLabel {
                        Text(dur)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()

                    if isNowPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, isActive: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                // Title
                Text(item.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.horizontal, 16)

                // Subtitle row
                HStack(spacing: 6) {
                    Text(item.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))

                    Text("·")
                        .foregroundStyle(.white.opacity(0.3))

                    Text(item.sourceLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                // Scripture reference
                if let ref = item.scriptureRef {
                    Text(ref)
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundStyle(.white.opacity(0.45))
                        .italic()
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }

                // Action row
                HStack(spacing: 0) {
                    // Play / pause
                    Button(action: onPlay) {
                        HStack(spacing: 6) {
                            Image(systemName: isNowPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text(isNowPlaying ? "Pause" : "Play")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Save
                    Button(action: onSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 16))
                            .foregroundStyle(isSaved ? Color(red: 0.52, green: 0.18, blue: 0.80) : .white.opacity(0.6))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)

                    // More / open
                    Button(action: onTap) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture { onTap() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeOut(duration: 0.1)) { isPressed = true }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPressed = false }
                }
        )
    }

    // MARK: - Card Background

    @ViewBuilder
    private var cardBackground: some View {
        ZStack {
            // Gradient base
            LinearGradient(
                colors: item.accentColors + [Color(red: 0.06, green: 0.06, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Thumbnail (if available)
            if let urlStr = item.thumbnailURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .opacity(0.35)
                } placeholder: {
                    Color.clear
                }
            }

            // Gradient scrim — makes text readable
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.35),
                    .init(color: Color(red: 0.06, green: 0.06, blue: 0.08).opacity(0.85), location: 0.75),
                    .init(color: Color(red: 0.06, green: 0.06, blue: 0.08), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Dark Shimmer Modifier

private struct DarkShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.06), location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .init(x: phase, y: 0),
                    endPoint: .init(x: phase + 1, y: 0)
                )
                .frame(width: geo.size.width * 2)
                .offset(x: geo.size.width * phase)
            }
        )
        .clipped()
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

private extension View {
    func shimmerDark() -> some View { modifier(DarkShimmerModifier()) }
}

// MARK: - Curated Worship Tracks (static seed)

extension AMENWorshipTrack {
    static let curated: [AMENWorshipTrack] = [
        AMENWorshipTrack(
            id: "wt-1",
            title: "Graves Into Gardens",
            artist: "Elevation Worship",
            album: "Graves Into Gardens",
            thumbnailURL: nil,
            durationSeconds: 271,
            publishedAt: nil,
            spotifyTrackID: "3y3CREt4sDZgaJi5ZWbVOB",
            youtubeVideoID: nil,
            appleMusicID: nil,
            scriptureReference: "Ezekiel 37",
            topic: "Resurrection"
        ),
        AMENWorshipTrack(
            id: "wt-2",
            title: "Way Maker",
            artist: "Sinach",
            album: "Way Maker",
            thumbnailURL: nil,
            durationSeconds: 349,
            publishedAt: nil,
            spotifyTrackID: "2MKMHKeHBb2xCfTgY8BK2r",
            youtubeVideoID: nil,
            appleMusicID: nil,
            scriptureReference: "Isaiah 43:16",
            topic: "Faith"
        ),
        AMENWorshipTrack(
            id: "wt-3",
            title: "Goodness of God",
            artist: "Bethel Music",
            album: "Victory",
            thumbnailURL: nil,
            durationSeconds: 310,
            publishedAt: nil,
            spotifyTrackID: "2RlSq0fB0o1UcAjGTi7IeE",
            youtubeVideoID: nil,
            appleMusicID: nil,
            scriptureReference: "Psalm 23",
            topic: "Praise"
        ),
        AMENWorshipTrack(
            id: "wt-4",
            title: "What A Beautiful Name",
            artist: "Hillsong Worship",
            album: "Let There Be Light",
            thumbnailURL: nil,
            durationSeconds: 295,
            publishedAt: nil,
            spotifyTrackID: "0ofHAoxe9vBkTCp2UQIavz",
            youtubeVideoID: nil,
            appleMusicID: nil,
            scriptureReference: "Philippians 2:9",
            topic: "Worship"
        )
    ]
}
